"""Scheduled maintenance (admin revamp step 10c).

POST /api/v1/internal/maintenance — called every few hours by Cloud
Scheduler with a Google-signed ID token (audience MAINTENANCE_AUDIENCE,
issued to MAINTENANCE_INVOKER_EMAIL). An overall admin's app sign-in also
works, so it can be run by hand. Anyone else: 401/403.

One run, each task independent (one failing doesn't stop the rest):
  1. retry delayed refunds that are due;
  2. hand refunds past the retry window to a person;
  3. ask the provider about refunds still in flight (missed webhooks);
  4. expire payment orders and seat holds whose time ran out;
  5. send refund emails that didn't go out.
Safe to run any number of times.
"""
import asyncio
import logging
from typing import Any, Dict

from fastapi import APIRouter, Header, HTTPException

from app.config import get_settings
from app.middleware.auth import decode_access_token
from app.services import payment_lifecycle_service, refund_service
from app.services.access import load_access

_log = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/internal", tags=["internal"])


def _verify_google_token(token: str, audience: str) -> Dict[str, Any]:
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token as google_id_token

    return google_id_token.verify_oauth2_token(token, google_requests.Request(), audience)


async def _authorize(authorization: str) -> str:
    """Returns who is running it ('scheduler' or the admin's uid)."""
    token = authorization[7:].strip() if authorization.lower().startswith("bearer ") else ""
    if not token:
        raise HTTPException(status_code=401, detail="not_authenticated")
    settings = get_settings()
    if settings.maintenance_audience and settings.maintenance_invoker_email:
        try:
            claims = await asyncio.to_thread(_verify_google_token, token, settings.maintenance_audience)
            if claims.get("email_verified") and claims.get("email") == settings.maintenance_invoker_email:
                return "scheduler"
        except Exception:  # noqa: BLE001 — not a Google token; try an app token
            pass
    try:
        payload = decode_access_token(token)
    except HTTPException:
        raise HTTPException(status_code=401, detail="not_authenticated")
    access = await load_access(payload["firebase_uid"])
    if not access.is_admin:
        raise HTTPException(status_code=403, detail="admin_required")
    return payload["firebase_uid"]


@router.post("/maintenance")
async def run_maintenance(authorization: str = Header(default="")) -> Dict[str, Any]:
    actor = await _authorize(authorization)
    results: Dict[str, Any] = {"run_by": "scheduler" if actor == "scheduler" else "admin"}

    async def task(name: str, coro):
        try:
            results[name] = await coro
        except Exception:  # noqa: BLE001 — one task never stops the rest
            _log.exception("[maintenance] %s failed", name)
            results[name] = "error"

    await task("refunds_retried", refund_service.retry_due_refunds(source="scheduled"))
    await task("refunds_handed_to_a_person", refund_service.escalate_overdue_refunds())
    await task("refunds_checked_with_provider", refund_service.reconcile_open_refunds())
    await task("orders_expired", _count(payment_lifecycle_service.expire_stale_payment_orders("system")))
    await task("holds_expired", _count(payment_lifecycle_service.expire_stale_registration_holds("system")))
    await task("refund_emails_sent", refund_service.send_due_refund_notifications())
    _log.info("[maintenance] %s", results)
    return results


async def _count(coro) -> int:
    out = await coro
    return int(out.get("expired_count", 0)) if isinstance(out, dict) else 0
