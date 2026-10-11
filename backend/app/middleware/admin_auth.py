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

Admin revamp step 1: every check below resolves roles through
app.services.access.get_access — one resolver that also counts
event_users.is_admin (migration 026) as overall admin (reported as
platform_admin) and event_users.is_event_creator as "may create events".

Nothing here ever reads a role from a request body, query string, or
header — the caller's identity always comes from a verified JWT, and their
roles always come from the database or the server-side settings object.
"""
from typing import Any, Dict

from fastapi import Depends, HTTPException

from app.database import get_pool
from app.middleware.auth import get_current_user
from app.repositories.payment_role_repository import PaymentRoleRepository
from app.services.access import Access, get_access, load_access

_ALL_PLATFORM_ROLES = {"platform_admin", "finance_operator", "auditor", "support"}


async def _resolve_platform_roles(firebase_uid: str) -> set:
    return (await load_access(firebase_uid)).platform_roles


def _with_access(user: Dict[str, Any], access: Access) -> Dict[str, Any]:
    """The caller's user dict plus their resolved Access, so routes can
    scope queries without resolving roles a second time."""
    return {**user, "access": access}


def require_platform_role(*allowed_roles: str):
    """Dependency factory — the caller must hold at least one of
    allowed_roles (platform_admin, i.e. any overall admin, always satisfies
    any check)."""

    async def _dep(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        roles = await _resolve_platform_roles(user["firebase_uid"])
        if "platform_admin" in roles or (roles & set(allowed_roles)):
            return user
        raise HTTPException(status_code=403, detail="payment_role_required")

    return _dep


async def require_overall_admin(
    user: Dict[str, Any] = Depends(get_current_user),
) -> Dict[str, Any]:
    access = await load_access(user["firebase_uid"])
    if access.is_admin:
        return _with_access(user, access)
    raise HTTPException(status_code=403, detail="overall_admin_required")


async def require_event_creator(
    user: Dict[str, Any] = Depends(get_current_user),
) -> Dict[str, Any]:
    """Overall admin, or event_users.is_event_creator."""
    access = await load_access(user["firebase_uid"])
    if access.is_event_creator:
        return _with_access(user, access)
    raise HTTPException(status_code=403, detail="event_creator_required")


async def require_any_admin(
    user: Dict[str, Any] = Depends(get_current_user),
) -> Dict[str, Any]:
    """Overall admin, an event creator, or admin of at least one event.
    Routes using this must scope their data with
    user["access"].scope_event_ids()."""
    access = await load_access(user["firebase_uid"])
    if access.is_any_admin:
        return _with_access(user, access)
    raise HTTPException(status_code=403, detail="admin_required")


async def require_event_admin(
    event_id: int,
    user: Dict[str, Any] = Depends(get_current_user),
) -> Dict[str, Any]:
    """Route dependency for event-scoped administration: overall admin
    (any event) or event_admin (this event only). Shared by
    admin_payments.py's config-mutation routes and every admin_events.py
    route — "manage this event" is one permission, not a payment-specific
    one. `event_id` is bound by FastAPI from the enclosing route's path
    parameter of the same name."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        event_exists = await conn.fetchval(
            "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1)", event_id
        )
        if not event_exists:
            raise HTTPException(status_code=404, detail="event_not_found")

        access = await get_access(conn, user["firebase_uid"])
        if access.is_admin:
            return user
        if await PaymentRoleRepository(conn).is_event_admin(event_id, user["firebase_uid"]):
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
    pool = await get_pool()
    async with pool.acquire() as conn:
        event_exists = await conn.fetchval(
            "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1)", event_id
        )
        if not event_exists:
            raise HTTPException(status_code=404, detail="event_not_found")

        access = await get_access(conn, user["firebase_uid"])
        if access.platform_roles & _ALL_PLATFORM_ROLES:
            return user
        if await PaymentRoleRepository(conn).is_event_admin(event_id, user["firebase_uid"]):
            return user

    raise HTTPException(status_code=403, detail="payment_read_access_required")
