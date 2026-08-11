"""Explicit payment/registration expiry lifecycle (WP4).

Prior to this module, order expiry was purely reactive: an order past
expires_at was rejected on the next create_attempt call, but its DB
`status` column stayed 'created'/'payment_pending' forever, and
registration-hold expiry only ever ran inline, scoped to one event, as a
side effect of a new registration attempt (RegistrationRepository.
expire_stale_holds). Nothing ever sweeps stale state on its own.

These functions are manually callable (via the admin API in
app/api/admin_payments.py) and safe to run repeatedly or concurrently —
see the repository methods they call
(PaymentRepository.expire_stale_orders, RegistrationRepository.
expire_all_stale_holds) for the concurrency/idempotency argument. No
scheduler is wired up here — none exists anywhere in this repository today,
and building one is out of scope for this sprint. Future invocation is
expected to be either a cron hitting these admin endpoints, or a small
ops script calling these functions directly.
"""
from typing import Any, Dict

from app.database import get_pool
from app.repositories.payment_repository import PaymentRepository
from app.repositories.registration_repository import RegistrationRepository
from app.services import audit_service


async def expire_stale_payment_orders(actor_uid: str) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await PaymentRepository(conn).expire_stale_orders()
    # Audit emitted after the transaction/connection is released — same
    # established pattern as payment_service.py / registration_service.py,
    # avoiding the self-deadlock class documented there (a second pooled
    # connection awaited while still holding a lock from the first).
    for row in rows:
        await audit_service.emit(
            actor_uid=actor_uid,
            event_type="payment_order_expired",
            entity_type="payment_order",
            entity_id=row["id"],
            context={"event_id": row["event_id"], "registration_id": row["registration_id"]},
        )
    return {
        "expired_count": len(rows),
        "expired_order_ids": [r["public_order_number"] for r in rows],
    }


async def expire_stale_registration_holds(actor_uid: str) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await RegistrationRepository(conn).expire_all_stale_holds()
    for row in rows:
        await audit_service.emit(
            actor_uid=actor_uid,
            event_type="registration_hold_expired",
            entity_type="registration",
            entity_id=row["registration_id"],
            context={"event_id": row["event_id"]},
        )
    return {
        "expired_count": len(rows),
        "expired_registration_ids": [r["registration_id"] for r in rows],
    }
