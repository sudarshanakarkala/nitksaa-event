"""Attendee-initiated paid-registration cancellation + full refund.

Scope (this sprint): full refund only, one logical refund per paid order,
INR only, 100% for the ₹1 pilot. No partial refunds, no policy engine.

Refund truth lives in payment_refunds — never inferred from the provider
dashboard alone. The registration is set to 'cancelled' immediately (the
seat is released regardless of how the refund settles); the refund object
then tracks pending -> processed / failed independently. We never present a
refund as fully "processed" until the provider's own status says so.

Idempotency / concurrency: the database indexes on payment_refunds
(idempotency_key unique; one non-failed refund per order) are the
authoritative guard. Only the caller that wins the INSERT race talks to the
provider; every other concurrent/duplicate caller reloads and returns the
winner's row without a second provider call. The provider's Idempotency-Key
header is an extra safeguard layered on top.
"""
import logging
import secrets
from decimal import Decimal
from typing import Any, Dict, Optional

import asyncpg
from fastapi import HTTPException

from app.database import get_pool
from app.gateways import registry as gateway_registry
from app.gateways.base import (
    GatewayCapability,
    GatewayError,
    NormalizedRefundStatus,
)
from app.gateways.registry import GatewayDisabledError, UnknownGatewayError
from app.repositories.payment_repository import PaymentRepository
from app.repositories.refund_repository import RefundRepository
from app.repositories.registration_repository import RegistrationRepository
from app.schemas.payments import RefundStatusResponse
from app.services import audit_service
from app.config import get_settings

_log = logging.getLogger(__name__)

_ATTENDEE_STATUS = {
    "pending": "refund_pending",
    "processing": "refund_pending",
    "processed": "refund_processed",
    "failed": "refund_failed",
}

_NORMALIZED_TO_INTERNAL = {
    NormalizedRefundStatus.REFUND_PROCESSED: ("processed", True),
    NormalizedRefundStatus.REFUND_PENDING: ("processing", False),
    NormalizedRefundStatus.REFUND_FAILED: ("failed", True),
}


def _safe_message(status: str) -> str:
    return {
        "refund_pending": "Your cancellation is confirmed. The refund has been initiated and is being processed by the payment provider.",
        "refund_processed": "Your cancellation is confirmed and the refund has been processed by the payment provider.",
        "refund_failed": "Your registration is cancelled, but the refund could not be completed automatically. Our team will follow up.",
        "none": "Your registration is cancelled. No payment was collected, so there is nothing to refund.",
    }.get(status, "Your registration is cancelled.")


def _view(registration_id: int, refund: Optional[asyncpg.Record]) -> RefundStatusResponse:
    if refund is None:
        return RefundStatusResponse(
            registration_id=registration_id, status="none", safe_message=_safe_message("none")
        )
    attendee_status = _ATTENDEE_STATUS.get(refund["status"], "refund_pending")
    payment_mode = refund["payment_mode"] if "payment_mode" in refund else "test"
    return RefundStatusResponse(
        refund_id=refund["public_refund_number"],
        registration_id=registration_id,
        status=attendee_status,
        amount=refund["amount"],
        currency=refund["currency"],
        requested_at=refund["requested_at"],
        finalized_at=refund["finalized_at"],
        safe_message=_safe_message(attendee_status),
        payment_mode=payment_mode,
        real_money=payment_mode == "live",
    )


async def _load_owned_registration(
    conn: asyncpg.Connection, registration_id: int, firebase_uid: str
) -> asyncpg.Record:
    reg = await RegistrationRepository(conn).get_by_id(registration_id)
    if not reg or reg["firebase_uid"] != firebase_uid:
        # Same body for not-found and not-owned — no cross-user existence leak.
        raise HTTPException(status_code=404, detail="registration_not_found")
    return reg


def _resolve_gateway(name: str):
    try:
        return gateway_registry.get_enabled_gateway(name, get_settings())
    except (UnknownGatewayError, GatewayDisabledError):
        return None


async def cancel_registration(
    registration_id: int, user: Dict[str, Any], idempotency_key: str
) -> RefundStatusResponse:
    firebase_uid = user["firebase_uid"]
    pool = await get_pool()

    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)
        refund_repo = RefundRepository(conn)
        reg = await _load_owned_registration(conn, registration_id, firebase_uid)

        # Already handled — return the current refund view idempotently.
        if reg["status"] == "cancelled":
            existing = await refund_repo.get_latest_for_registration(registration_id)
            return _view(registration_id, existing)

        if reg["status"] != "registered":
            # seat_held / payment_pending / payment_verification / payment_failed
            # are pre-confirmation states; there is nothing captured to refund
            # and the lifecycle sweep / retry paths own those.
            raise HTTPException(status_code=409, detail="registration_not_cancellable")

        # Find a captured payment for this registration.
        paid_order = await conn.fetchrow(
            """
            SELECT * FROM payment_orders
            WHERE registration_id = $1 AND status = 'paid'
            ORDER BY paid_at DESC NULLS LAST, created_at DESC LIMIT 1
            """,
            registration_id,
        )

        if paid_order is None:
            # Free registration (or a paid one that never captured) — just
            # cancel. No refund object.
            async with conn.transaction():
                await RegistrationRepository(conn).set_status(registration_id, "cancelled")
                await conn.execute(
                    "UPDATE registrations SET cancelled_at = now() WHERE registration_id = $1",
                    registration_id,
                )
            await audit_service.emit(
                actor_uid=firebase_uid, event_type="registration_cancelled",
                entity_type="registration", entity_id=registration_id,
                context={"paid": False},
            )
            return _view(registration_id, None)

        attempts = await pay_repo.list_attempts_for_order(paid_order["id"])
        captured = next(
            (a for a in attempts if a["status"] == "captured" and a["gateway_payment_ref"]),
            None,
        )
        if captured is None:
            raise HTTPException(status_code=409, detail="no_captured_payment")

        gateway_name = captured["gateway"]
        gw = _resolve_gateway(gateway_name)
        if gw is None or GatewayCapability.REFUND not in gw.capabilities:
            raise HTTPException(status_code=409, detail="refund_not_supported")

        # The refund's payment_mode is the mode the payment was actually
        # captured under (the attempt's own snapshot) — never the order's,
        # in case they could ever disagree. In this schema they cannot (both
        # descend from the same config snapshot at order-creation time), but
        # asserting it here means a future change that broke that invariant
        # would fail loudly instead of silently refunding through the wrong
        # credential profile. See test_cross_mode_refund_impossible.
        captured_payment_mode = captured["payment_mode"] if "payment_mode" in captured else "test"
        order_payment_mode = paid_order["payment_mode"] if "payment_mode" in paid_order else "test"
        if captured_payment_mode != order_payment_mode:
            _log.error(
                "[refunds] payment_mode mismatch between attempt %s (%s) and order %s (%s) — refusing refund",
                captured["id"], captured_payment_mode, paid_order["id"], order_payment_mode,
            )
            raise HTTPException(status_code=409, detail="refund_mode_mismatch")

        # ── create the internal refund row + cancel the registration ──
        existing_by_key = await refund_repo.get_by_idempotency_key(idempotency_key)
        if existing_by_key is not None:
            return await _refresh_and_view(conn, registration_id, existing_by_key, gw)
        existing_active = await refund_repo.get_active_for_order(paid_order["id"])
        if existing_active is not None:
            return await _refresh_and_view(conn, registration_id, existing_active, gw)

        i_am_the_refund_creator = False
        try:
            async with conn.transaction():
                refund_row = await refund_repo.create(
                    public_refund_number=f"RFND-{secrets.token_urlsafe(9)}",
                    registration_id=registration_id,
                    payment_order_id=paid_order["id"],
                    payment_attempt_id=captured["id"],
                    gateway=gateway_name,
                    provider_payment_id=captured["gateway_payment_ref"],
                    amount=Decimal(paid_order["final_amount"]),
                    currency=paid_order["currency"],
                    idempotency_key=idempotency_key,
                    reason="attendee_cancellation",
                    requested_by=firebase_uid,
                    payment_mode=captured_payment_mode,
                )
                await RegistrationRepository(conn).set_status(registration_id, "cancelled")
                await conn.execute(
                    "UPDATE registrations SET cancelled_at = now() WHERE registration_id = $1",
                    registration_id,
                )
                i_am_the_refund_creator = True
        except asyncpg.exceptions.UniqueViolationError:
            # Lost the race (same key, or the one-active-refund-per-order
            # index). Reload the winner and return it — do NOT call the
            # provider a second time.
            winner = (
                await refund_repo.get_by_idempotency_key(idempotency_key)
                or await refund_repo.get_active_for_order(paid_order["id"])
            )
            return await _refresh_and_view(conn, registration_id, winner, gw)

        await audit_service.emit(
            actor_uid=firebase_uid, event_type="payment_refund_requested",
            entity_type="payment_refund", entity_id=refund_row["id"],
            context={"order_id": paid_order["id"], "amount": str(refund_row["amount"])},
        )

    # ── provider call (outside the DB transaction) ──
    if not i_am_the_refund_creator:
        return _view(registration_id, refund_row)

    amount_minor = int((Decimal(refund_row["amount"]) * 100).to_integral_value())
    try:
        result = gw.refund(
            provider_payment_id=refund_row["provider_payment_id"],
            amount_minor=amount_minor,
            currency=refund_row["currency"],
            idempotency_key=refund_row["idempotency_key"],
            payment_mode=refund_row["payment_mode"] if "payment_mode" in refund_row else "test",
        )
    except GatewayError:
        _log.exception("[refunds] provider refund call failed for %s", refund_row["public_refund_number"])
        async with pool.acquire() as conn:
            updated = await RefundRepository(conn).mark(
                refund_row["id"], status="failed", failure_reason="provider_error", finalized=False
            )
        await audit_service.emit(
            actor_uid="system", event_type="payment_refund_failed",
            entity_type="payment_refund", entity_id=refund_row["id"],
            context={"reason": "provider_error"},
        )
        return _view(registration_id, updated)

    internal_status, finalized = _NORMALIZED_TO_INTERNAL.get(result.status, ("processing", False))
    async with pool.acquire() as conn:
        updated = await RefundRepository(conn).mark(
            refund_row["id"],
            status=internal_status,
            provider_refund_id=result.provider_refund_id or None,
            failure_reason=result.failure_reason if internal_status == "failed" else None,
            finalized=finalized,
        )
    await audit_service.emit(
        actor_uid="system",
        event_type="payment_refund_processed" if internal_status == "processed" else "payment_refund_updated",
        entity_type="payment_refund", entity_id=refund_row["id"],
        context={"status": internal_status},
    )
    return _view(registration_id, updated)


async def _refresh_and_view(
    conn: asyncpg.Connection, registration_id: int, refund: Optional[asyncpg.Record], gw
) -> RefundStatusResponse:
    """Best-effort provider refresh for a non-terminal refund, then view."""
    if refund is None:
        return _view(registration_id, None)
    if (
        refund["status"] in ("pending", "processing")
        and refund["provider_refund_id"]
        and gw is not None
        and GatewayCapability.QUERY_REFUND in gw.capabilities
    ):
        try:
            result = gw.query_refund(
                provider_payment_id=refund["provider_payment_id"],
                provider_refund_id=refund["provider_refund_id"],
                payment_mode=refund["payment_mode"] if "payment_mode" in refund else "test",
            )
        except GatewayError:
            result = None
        if result is not None:
            internal_status, finalized = _NORMALIZED_TO_INTERNAL.get(
                result.status, (refund["status"], False)
            )
            if internal_status != refund["status"]:
                refund = await RefundRepository(conn).mark(
                    refund["id"], status=internal_status, finalized=finalized
                )
    return _view(registration_id, refund)


async def get_refund_status(
    registration_id: int, user: Dict[str, Any]
) -> RefundStatusResponse:
    firebase_uid = user["firebase_uid"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _load_owned_registration(conn, registration_id, firebase_uid)
        refund = await RefundRepository(conn).get_latest_for_registration(registration_id)
        if refund is None:
            return _view(registration_id, None)
        gw = _resolve_gateway(refund["gateway"])
        return await _refresh_and_view(conn, registration_id, refund, gw)
