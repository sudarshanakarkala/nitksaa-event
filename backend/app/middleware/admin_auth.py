"""Production admin RBAC — shared by the payment-admin surface
(app/api/admin_payments.py) and the event-admin surface
(app/api/admin_events.py).

Identity is the real Firebase-JWT-backed pipeline (app.middleware.auth) —
the same one attendees use. This module never uses app.middleware.dev_auth;
that module is a development-only placeholder (gated by APP_ENV=development)
and must never be treated as production authorization.

Role sources, in priority order:
  1. settings.platform_admin_firebase_uids — bootstrap list (env var). The
     only way the very first platform_admin is established, since no admin
     identity exists yet to grant that role through the API.
  2. payment_platform_roles table — every grant made after bootstrap,
     platform-wide (platform_admin, finance_operator, auditor, support).
     Despite the table name (payment_platform_roles, from the sprint that
     introduced it), platform_admin here is a genuinely general-purpose
     role — event_admin's own scope check treats it as such. The other
     three (finance_operator/auditor/support) remain payment-specific by
     design; see require_event_payment_read_access below.
  3. event_members table (role='event_admin', status='active') — per-event
     scoped role, reusing the pre-existing (previously unused) table from
     migration 003. Originally wired up for payment-config management,
     reused as-is here for general event administration — "manage this
     event" is the same permission regardless of which admin surface is
     asking.

Nothing here ever reads a role from a request body, query string, or
header — the caller's identity always comes from a verified JWT, and their
roles always come from the database or the server-side settings object.
"""
from typing import Any, Dict

from fastapi import Depends, HTTPException

from app.config import get_settings
from app.database import get_pool
from app.middleware.auth import get_current_user
from app.repositories.payment_role_repository import PaymentRoleRepository

_ALL_PLATFORM_ROLES = {"platform_admin", "finance_operator", "auditor", "support"}


async def _resolve_platform_roles(firebase_uid: str) -> set:
    settings = get_settings()
    roles: set = set()
    if firebase_uid in settings.platform_admin_firebase_uids:
        roles.add("platform_admin")
    pool = await get_pool()
    async with pool.acquire() as conn:
        roles |= await PaymentRoleRepository(conn).active_platform_roles(firebase_uid)
    return roles


def require_platform_role(*allowed_roles: str):
    """Dependency factory — the caller must hold at least one of
    allowed_roles (platform_admin always satisfies any check)."""

    async def _dep(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        roles = await _resolve_platform_roles(user["firebase_uid"])
        if "platform_admin" in roles or (roles & set(allowed_roles)):
            return user
        raise HTTPException(status_code=403, detail="payment_role_required")

    return _dep


async def require_event_admin(
    event_id: int,
    user: Dict[str, Any] = Depends(get_current_user),
) -> Dict[str, Any]:
    """Route dependency for event-scoped administration: platform_admin
    (any event) or event_admin (this event only). Shared by
    admin_payments.py's config-mutation routes and every admin_events.py
    route — "manage this event" is one permission, not a payment-specific
    one. `event_id` is bound by FastAPI from the enclosing route's path
    parameter of the same name."""
    settings = get_settings()
    pool = await get_pool()
    async with pool.acquire() as conn:
        event_exists = await conn.fetchval(
            "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1)", event_id
        )
        if not event_exists:
            raise HTTPException(status_code=404, detail="event_not_found")

        if user["firebase_uid"] in settings.platform_admin_firebase_uids:
            return user

        role_repo = PaymentRoleRepository(conn)
        if "platform_admin" in await role_repo.active_platform_roles(user["firebase_uid"]):
            return user
        if await role_repo.is_event_admin(event_id, user["firebase_uid"]):
            return user

    raise HTTPException(status_code=403, detail="event_admin_required")


async def require_event_payment_read_access(
    event_id: int,
    user: Dict[str, Any] = Depends(get_current_user),
) -> Dict[str, Any]:
    """Read-only variant used ONLY by payment-configuration read routes —
    platform_admin/finance_operator/auditor/support (platform-wide) or
    event_admin scoped to this event. Deliberately payment-specific
    (unlike require_event_admin above): finance/auditor/support are
    payment-operational roles and must not gain visibility into unrelated
    event-management data through a generically-named dependency — see
    require_event_admin's docstring and the admin RBAC unification
    decision recorded in the operational-readiness sprint report."""
    settings = get_settings()
    pool = await get_pool()
    async with pool.acquire() as conn:
        event_exists = await conn.fetchval(
            "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1)", event_id
        )
        if not event_exists:
            raise HTTPException(status_code=404, detail="event_not_found")

        if user["firebase_uid"] in settings.platform_admin_firebase_uids:
            return user

        role_repo = PaymentRoleRepository(conn)
        if await role_repo.active_platform_roles(user["firebase_uid"]) & _ALL_PLATFORM_ROLES:
            return user
        if await role_repo.is_event_admin(event_id, user["firebase_uid"]):
            return user

    raise HTTPException(status_code=403, detail="payment_read_access_required")
