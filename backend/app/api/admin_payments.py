"""Production payment admin API — configuration lifecycle (WP1), RBAC role
management (WP2), and explicit expiry-sweep triggers (WP4).

Every route here is authorized through app.middleware.admin_auth, which is
backed by the real Firebase-JWT identity pipeline (app.middleware.auth) —
never app.middleware.dev_auth. This is deliberately a separate router from
app/api/dev_diagnostics.py: the dev-diagnostics payment routes stay exactly
as they are (development-env-gated), this router is the first production
write path for payment configuration and the first production payment RBAC
surface. app/middleware/admin_auth.py (renamed from payment_auth.py in the
operational-readiness sprint) is now also used by app/api/admin_events.py.
"""
from typing import Any, Dict

import asyncpg
from fastapi import APIRouter, Depends, HTTPException

from app.database import get_pool
from app.middleware.admin_auth import (
    require_event_admin,
    require_event_payment_read_access,
    require_platform_role,
)
from app.repositories.payment_role_repository import PaymentRoleRepository
from app.schemas.payment_admin import (
    EventPaymentAdminGrantRequest,
    EventPaymentAdminGrantResponse,
    ExpireHoldsResponse,
    ExpireOrdersResponse,
    PaymentConfigAdminResponse,
    PaymentConfigDraftCreateRequest,
    PaymentConfigListResponse,
    PaymentConfigValidateResponse,
    PlatformRoleGrantRequest,
    PlatformRoleListResponse,
    PlatformRoleResponse,
)
from app.services import audit_service, payment_config_service, payment_lifecycle_service

router = APIRouter(prefix="/api/v1/admin", tags=["payment-admin"])


# ── WP1: payment configuration lifecycle ───────────────────────────────────

@router.post(
    "/events/{event_id}/payment-configurations",
    response_model=PaymentConfigAdminResponse,
    status_code=201,
)
async def create_payment_configuration_draft(
    event_id: int,
    body: PaymentConfigDraftCreateRequest,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    return await payment_config_service.create_draft(event_id, body.model_dump(), user)


@router.get(
    "/events/{event_id}/payment-configurations",
    response_model=PaymentConfigListResponse,
)
async def list_payment_configurations(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_payment_read_access),
) -> Dict[str, Any]:
    return {"event_id": event_id, "configurations": await payment_config_service.list_history(event_id)}


@router.get(
    "/events/{event_id}/payment-configurations/{configuration_id}",
    response_model=PaymentConfigAdminResponse,
)
async def get_payment_configuration(
    event_id: int,
    configuration_id: int,
    user: Dict[str, Any] = Depends(require_event_payment_read_access),
) -> Dict[str, Any]:
    return await payment_config_service.get_one(event_id, configuration_id)


@router.post(
    "/events/{event_id}/payment-configurations/{configuration_id}/validate",
    response_model=PaymentConfigValidateResponse,
)
async def validate_payment_configuration(
    event_id: int,
    configuration_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    return await payment_config_service.validate_draft(configuration_id, user)


@router.post(
    "/events/{event_id}/payment-configurations/{configuration_id}/publish",
    response_model=PaymentConfigAdminResponse,
)
async def publish_payment_configuration(
    event_id: int,
    configuration_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    return await payment_config_service.publish(event_id, configuration_id, user)


# ── WP2: payment RBAC role management ───────────────────────────────────────

@router.post("/payment-roles", response_model=PlatformRoleResponse, status_code=201)
async def grant_platform_role(
    body: PlatformRoleGrantRequest,
    user: Dict[str, Any] = Depends(require_platform_role("platform_admin")),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        try:
            row = await PaymentRoleRepository(conn).grant_platform_role(
                firebase_uid=body.firebase_uid, role=body.role, granted_by=user["firebase_uid"]
            )
        except asyncpg.exceptions.UniqueViolationError:
            # uq_payment_platform_roles_active — this (firebase_uid, role)
            # already has an active grant. Clean conflict, not a 500.
            raise HTTPException(status_code=409, detail="payment_role_already_active")
        except asyncpg.exceptions.ForeignKeyViolationError:
            # firebase_uid has no event_users row yet.
            raise HTTPException(status_code=404, detail="firebase_uid_not_found")
    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="payment_role_granted",
        entity_type="payment_platform_role",
        entity_id=row["id"],
        context={"role": body.role, "granted_to": body.firebase_uid},
    )
    return dict(row)


@router.post("/payment-roles/{grant_id}/revoke", status_code=200)
async def revoke_platform_role(
    grant_id: int,
    user: Dict[str, Any] = Depends(require_platform_role("platform_admin")),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        role_repo = PaymentRoleRepository(conn)
        existing = await role_repo.get_active_grant_by_id(grant_id)
        if not existing:
            raise HTTPException(status_code=404, detail="payment_role_grant_not_found")
        await role_repo.revoke_platform_role(grant_id, revoked_by=user["firebase_uid"])

    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="payment_role_revoked",
        entity_type="payment_platform_role",
        entity_id=grant_id,
        context={"role": existing["role"], "revoked_from": existing["firebase_uid"]},
    )
    return {"status": "ok", "grant_id": grant_id}


@router.get("/payment-roles", response_model=PlatformRoleListResponse)
async def list_platform_roles(
    user: Dict[str, Any] = Depends(require_platform_role("platform_admin", "auditor")),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await PaymentRoleRepository(conn).list_active_platform_roles()
    return {"roles": [dict(r) for r in rows]}


@router.post(
    "/events/{event_id}/payment-admins",
    response_model=EventPaymentAdminGrantResponse,
    status_code=201,
)
async def grant_event_payment_admin(
    event_id: int,
    body: EventPaymentAdminGrantRequest,
    user: Dict[str, Any] = Depends(require_platform_role("platform_admin")),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        event_exists = await conn.fetchval(
            "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1)", event_id
        )
        if not event_exists:
            raise HTTPException(status_code=404, detail="event_not_found")
        row = await PaymentRoleRepository(conn).grant_event_admin(event_id, body.firebase_uid)

    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="event_payment_admin_granted",
        entity_type="event",
        entity_id=event_id,
        context={"granted_to": body.firebase_uid},
    )
    return {
        "event_id": row["event_id"],
        "firebase_uid": row["firebase_uid"],
        "role": row["role"],
        "status": row["status"],
    }


# ── WP4: explicit expiry-sweep triggers ─────────────────────────────────────

@router.post("/payments/lifecycle/expire-orders", response_model=ExpireOrdersResponse)
async def trigger_expire_stale_orders(
    user: Dict[str, Any] = Depends(require_platform_role("platform_admin")),
) -> Dict[str, Any]:
    return await payment_lifecycle_service.expire_stale_payment_orders(user["firebase_uid"])


@router.post("/payments/lifecycle/expire-registration-holds", response_model=ExpireHoldsResponse)
async def trigger_expire_stale_registration_holds(
    user: Dict[str, Any] = Depends(require_platform_role("platform_admin")),
) -> Dict[str, Any]:
    return await payment_lifecycle_service.expire_stale_registration_holds(user["firebase_uid"])
