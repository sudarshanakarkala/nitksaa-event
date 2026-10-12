"""Admin Payments tab (admin revamp step 9): read-only order and refund lists.

Who sees what:
  - overall admins and payment roles (finance operator, auditor, support):
    every event;
  - event admins: their own events;
  - anyone else: 403.
"""
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_pool
from app.middleware.auth import get_current_user
from app.services.access import load_access

router = APIRouter(prefix="/api/v1/admin/payments", tags=["admin"])

_PAYMENT_ROLES = {"platform_admin", "finance_operator", "auditor", "support"}

# An order still pending after this long is flagged as stuck.
_STUCK_AFTER = timedelta(minutes=30)

# "$1::int[] IS NULL" = every event.
_SCOPE = "($1::int[] IS NULL OR o.event_id = ANY($1::int[]))"


async def payment_list_scope(
    user: Dict[str, Any] = Depends(get_current_user),
) -> Optional[List[int]]:
    """None = every event; otherwise the events this user administers."""
    access = await load_access(user["firebase_uid"])
    if access.is_admin or (access.platform_roles & _PAYMENT_ROLES):
        return None
    if access.admin_event_ids:
        return list(access.admin_event_ids)
    raise HTTPException(status_code=403, detail="payment_read_access_required")


def _money(v: Any) -> float:
    return float(v) if v is not None else 0.0


@router.get("/orders")
async def list_orders(
    event_id: Optional[int] = Query(None),
    page: int = Query(1, ge=1),
    per_page: int = Query(200, ge=1, le=500),
    scope: Optional[List[int]] = Depends(payment_list_scope),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        where = f"{_SCOPE} AND ($2::int IS NULL OR o.event_id = $2::int)"
        total = await conn.fetchval(
            f"SELECT COUNT(*) FROM payment_orders o WHERE {where}", scope, event_id
        )
        rows = await conn.fetch(
            f"""
            SELECT o.id, o.public_order_number, o.event_id, e.title AS event_title,
                   o.registration_id, r.registration_number,
                   r.fullname_snapshot AS fullname, r.email,
                   o.final_amount, o.amount_paid, o.currency, o.status,
                   o.payment_mode, o.gateway, o.created_at, o.paid_at, o.expires_at
            FROM payment_orders o
            JOIN events e ON e.event_id = o.event_id
            LEFT JOIN registrations r ON r.registration_id = o.registration_id
            WHERE {where}
            ORDER BY o.created_at DESC
            LIMIT $3::int OFFSET $4::int
            """,
            scope, event_id, per_page, (page - 1) * per_page,
        )

    now = datetime.now(timezone.utc)
    orders = []
    for r in rows:
        d = dict(r)
        d["final_amount"] = _money(d["final_amount"])
        d["amount_paid"] = _money(d["amount_paid"])
        d["stuck"] = d["status"] in ("created", "payment_pending") and d["created_at"] < now - _STUCK_AFTER
        orders.append(d)
    return {"orders": orders, "total": total, "page": page, "per_page": per_page}


@router.get("/refunds")
async def list_refunds(
    event_id: Optional[int] = Query(None),
    page: int = Query(1, ge=1),
    per_page: int = Query(200, ge=1, le=500),
    scope: Optional[List[int]] = Depends(payment_list_scope),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        where = f"{_SCOPE} AND ($2::int IS NULL OR o.event_id = $2::int)"
        total = await conn.fetchval(
            f"""
            SELECT COUNT(*) FROM payment_refunds f
            JOIN payment_orders o ON o.id = f.payment_order_id
            WHERE {where}
            """,
            scope, event_id,
        )
        rows = await conn.fetch(
            f"""
            SELECT f.id, f.public_refund_number, o.public_order_number,
                   o.event_id, e.title AS event_title,
                   f.registration_id, r.registration_number,
                   r.fullname_snapshot AS fullname, r.email,
                   f.amount, f.currency, f.status, f.payment_mode,
                   f.provider_refund_id, f.failure_reason,
                   f.requested_at, f.updated_at, f.finalized_at
            FROM payment_refunds f
            JOIN payment_orders o ON o.id = f.payment_order_id
            JOIN events e ON e.event_id = o.event_id
            LEFT JOIN registrations r ON r.registration_id = f.registration_id
            WHERE {where}
            ORDER BY f.requested_at DESC
            LIMIT $3::int OFFSET $4::int
            """,
            scope, event_id, per_page, (page - 1) * per_page,
        )

    refunds = []
    for r in rows:
        d = dict(r)
        d["amount"] = _money(d["amount"])
        refunds.append(d)
    return {"refunds": refunds, "total": total, "page": page, "per_page": per_page}
