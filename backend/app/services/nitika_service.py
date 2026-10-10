"""NITiKa — calls the events assistant on behalf of a signed-in user.

NITiKa trusts whatever user, role and admin scope its caller sends, so this
module is the only place they are built: the user from the verified
session, the scope from the same role sources as app.middleware.admin_auth.
Nothing from the request body ever reaches `user`.

Calls carry a Google ID token (NITiKa's Cloud Run service is IAM-only) and
the events client key. Message text, answers and tables are never logged.
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

import httpx

from app.config import get_settings
from app.database import get_pool
from app.repositories.payment_role_repository import PaymentRoleRepository

logger = logging.getLogger(__name__)

ALL_CAPABILITIES = ["registrations", "attendees", "payments", "sql"]
EVENT_ADMIN_CAPABILITIES = ["registrations", "attendees", "payments"]
PAYMENT_ROLES = {"finance_operator", "auditor", "support"}

# NITiKa error statuses passed through to the app as they are. Anything
# else (NITiKa's 401 for a bad client key, Cloud Run's own IAM rejection, an
# unexpected body) is a fault on our side and becomes a 502: the app must
# not tell the user their session expired because our key is wrong.
_PASS_THROUGH = {400, 403, 429, 502, 503, 504}

# Google ID tokens last an hour; refresh well before that.
_TOKEN_TTL_SECONDS = 45 * 60
_token_cache: Dict[str, Tuple[str, float]] = {}


def admin_scope_from_roles(
    platform_roles: set, event_admin_ids: List[int]
) -> Optional[Dict[str, Any]]:
    """NITiKa's admin_scope for a user's roles (service design §4), or None
    for a member.

      platform_admin                     → all events, every capability
      event_admin                        → their events: registrations,
                                           attendees, payments
      finance_operator / auditor / support → all events, payments

    NITiKa takes one scope, so a true union isn't possible when someone is
    both an event_admin and a payment role. They get the event_admin scope:
    neither choice is a superset of the other, and this one never widens
    attendee access beyond the events they manage.
    """
    if "platform_admin" in platform_roles:
        return {"event_ids": "all", "capabilities": list(ALL_CAPABILITIES)}
    if event_admin_ids:
        return {
            "event_ids": sorted(set(event_admin_ids)),
            "capabilities": list(EVENT_ADMIN_CAPABILITIES),
        }
    if platform_roles & PAYMENT_ROLES:
        return {"event_ids": "all", "capabilities": ["payments"]}
    return None


async def resolve_admin_scope(firebase_uid: str) -> Optional[Dict[str, Any]]:
    settings = get_settings()
    roles: set = set()
    if firebase_uid in settings.platform_admin_firebase_uids:
        roles.add("platform_admin")
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = PaymentRoleRepository(conn)
        roles |= await repo.active_platform_roles(firebase_uid)
        event_ids = (
            [] if "platform_admin" in roles
            else await repo.event_admin_event_ids(firebase_uid)
        )
    return admin_scope_from_roles(roles, event_ids)


def nitika_user(user: Dict[str, Any], scope: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """The `user` NITiKa receives, from the verified session only."""
    out: Dict[str, Any] = {
        "id": user["firebase_uid"],
        "role": "admin" if scope else "user",
    }
    if user.get("user_type"):
        out["user_type"] = str(user["user_type"])[:32]
    if scope:
        out["admin_scope"] = scope
    return out


def error_body(code: str, message: str, request_id: Optional[str] = None) -> Dict[str, Any]:
    """NITiKa's error format, so the app handles ours and its alike."""
    return {"error": {"code": code, "message": message, "request_id": request_id}}


def _needs_id_token(url: str) -> bool:
    host = urlparse(url).hostname or ""
    return host not in {"localhost", "127.0.0.1"}


def _fetch_id_token(audience: str) -> str:
    # google-auth comes with firebase-admin. On Cloud Run it asks the
    # metadata server for a token for the runtime service account.
    import google.auth.transport.requests
    import google.oauth2.id_token

    return google.oauth2.id_token.fetch_id_token(
        google.auth.transport.requests.Request(), audience
    )


async def _id_token(audience: str) -> str:
    cached = _token_cache.get(audience)
    if cached and cached[1] > time.monotonic():
        return cached[0]
    token = await asyncio.to_thread(_fetch_id_token, audience)
    _token_cache[audience] = (token, time.monotonic() + _TOKEN_TTL_SECONDS)
    return token


async def chat(payload: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
    """POST payload to NITiKa's /v1/chat. Returns (status, body) for the app:
    NITiKa's answer, or an error in NITiKa's format."""
    settings = get_settings()
    base = settings.nitika_url.strip().rstrip("/")
    headers = {"X-NITiKa-Client-Key": settings.nitika_client_key.strip()}

    if _needs_id_token(base):
        try:
            headers["Authorization"] = f"Bearer {await _id_token(base)}"
        except Exception as exc:  # noqa: BLE001 — any failure means no call
            logger.error("nitika: could not get an ID token: %s", type(exc).__name__)
            return 502, error_body("upstream_auth", "NITiKa couldn't answer just now.")

    started = time.monotonic()
    try:
        async with httpx.AsyncClient(timeout=settings.nitika_timeout_seconds) as client:
            response = await client.post(f"{base}/v1/chat", json=payload, headers=headers)
    except httpx.TimeoutException:
        logger.warning("nitika: timed out after %.1fs", time.monotonic() - started)
        return 504, error_body("timeout", "NITiKa took too long to answer.")
    except httpx.HTTPError as exc:
        logger.error("nitika: unreachable: %s", type(exc).__name__)
        return 503, error_body("unreachable", "NITiKa couldn't answer just now.")

    try:
        data = response.json()
    except ValueError:
        data = None
    status = response.status_code
    request_id = (
        data["error"].get("request_id")
        if isinstance(data, dict) and isinstance(data.get("error"), dict)
        else (data.get("request_id") if isinstance(data, dict) else None)
    )
    logger.info(
        "nitika: status=%s request_id=%s latency_ms=%d",
        status, request_id, (time.monotonic() - started) * 1000,
    )

    if status == 200 and isinstance(data, dict):
        return 200, data
    if (
        status in _PASS_THROUGH
        and isinstance(data, dict)
        and isinstance(data.get("error"), dict)
    ):
        return status, data

    if status in (401, 403):
        # A stale or rejected token: fetch a fresh one next time.
        _token_cache.pop(base, None)
    logger.error("nitika: unexpected response status=%s", status)
    return 502, error_body("upstream_error", "NITiKa couldn't answer just now.", request_id)
