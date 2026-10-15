"""Attendee-initiated cancellation + refund.

A registration is a group (migration 031): the leader's row plus guest rows.
Cancelling a guest's row cancels that guest and refunds one person's share
of the order; cancelling the leader's row cancels everyone still in the
group and refunds their shares. One refund row per cancellation; an order's
refunds never add up to more than was paid. INR only, no policy engine.

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
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Dict, Optional

import asyncpg
from fastapi import HTTPException

from app.database import get_pool
from app.gateways import registry as gateway_registry
from app.gateways.base import (
    TEMPORARY_REFUND_FAILURES,
    GatewayCapability,
    GatewayError,
    GatewayRefundRefusedError,
    NormalizedRefundStatus,
    RefundFailureReason,
)
from app.gateways.registry import GatewayDisabledError, UnknownGatewayError
from app.repositories.payment_repository import PaymentRepository
from app.repositories.refund_repository import RefundRepository
from app.repositories.registration_repository import RegistrationRepository
from app.schemas.payments import GroupRefundItem, RefundStatusResponse
from app.services import audit_service
from app.config import get_settings

_log = logging.getLogger(__name__)

_ATTENDEE_STATUS = {
    "pending": "refund_pending",
    "processing": "refund_pending",
    "delayed": "refund_delayed",
    "processed": "refund_processed",
    "failed": "refund_failed",
}

# Plain words for each refund failure reason. ADMIN text is specific (what
# happened and what to do); attendees get REASON_ATTENDEE, which never
# blames the association's finances.
REASON_ADMIN = {
    "insufficient_balance": "Razorpay balance too low to send the refund yet. Clears as payments come in or "
                            "settle (usually 2–3 working days); retrying automatically.",
    "provider_unavailable": "Razorpay couldn't be reached or had a problem; retrying automatically.",
    "payment_too_old": "Razorpay won't refund a payment this old. Refund the person another way.",
    "already_refunded": "Razorpay says this payment is already fully refunded. Check the Razorpay dashboard.",
    "amount_not_allowed": "Razorpay refused the refund amount. Check what was already refunded in Razorpay.",
    "payment_not_captured": "Razorpay says the payment was never captured, so there's nothing to refund.",
    "refunded_outside_app": "A refund for this payment was already made outside the app (e.g. in the Razorpay "
                            "dashboard). Check it there before doing anything else.",
    "declined": "Razorpay refused the refund for a reason the app doesn't recognise. Check the payment in Razorpay.",
    "provider_failed": "Razorpay reported the refund as failed. Check the payment in Razorpay.",
    "provider_error": "The refund call to Razorpay failed (recorded before reasons were kept).",
}


_NORMALIZED_TO_INTERNAL = {
    NormalizedRefundStatus.REFUND_PROCESSED: ("processed", True),
    NormalizedRefundStatus.REFUND_PENDING: ("processing", False),
    NormalizedRefundStatus.REFUND_FAILED: ("failed", True),
}


def _safe_message(status: str, bank_reference: Optional[str] = None) -> str:
    if status == "refund_processed":
        return ("Your refund has been sent. Banks usually show it within 5–7 working days."
                + (f" Your bank reference is {bank_reference}." if bank_reference else ""))
    return {
        "refund_pending": "Your registration is cancelled. Your refund is on its way. We'll email you when it's been sent.",
        "refund_delayed": "Your registration is cancelled. Your refund couldn't be sent yet because of a temporary "
                          "issue with the payment provider. We're retrying automatically and will email you as soon "
                          "as it's on its way. You don't need to do anything.",
        "refund_failed": "Your registration is cancelled, but we couldn't send your refund automatically. Someone from "
                         "NITKSAA will contact you within 2 working days. Please quote your refund reference.",
        "none": "Your registration is cancelled. No payment was collected, so there is nothing to refund.",
    }.get(status, "Your registration is cancelled.")


def _view(registration_id: int, refund: Optional[asyncpg.Record]) -> RefundStatusResponse:
    if refund is None:
        return RefundStatusResponse(
            registration_id=registration_id, status="none", safe_message=_safe_message("none")
        )
    attendee_status = _ATTENDEE_STATUS.get(refund["status"], "refund_pending")
    payment_mode = refund["payment_mode"] if "payment_mode" in refund else "test"
    bank_reference = refund["bank_reference"] if "bank_reference" in refund else None
    return RefundStatusResponse(
        refund_id=refund["public_refund_number"],
        registration_id=registration_id,
        status=attendee_status,
        amount=refund["amount"],
        currency=refund["currency"],
        requested_at=refund["requested_at"],
        finalized_at=refund["finalized_at"],
        safe_message=_safe_message(attendee_status, bank_reference),
        payment_mode=payment_mode,
        real_money=payment_mode == "live",
        payment_reference=refund["provider_payment_id"] or None,
        bank_reference=bank_reference,
    )


async def _load_owned_registration(
    conn: asyncpg.Connection, registration_id: int, firebase_uid: str
) -> asyncpg.Record:
    reg = await RegistrationRepository(conn).get_by_id(registration_id)
    if not reg or reg["firebase_uid"] != firebase_uid:
        # Same body for not-found and not-owned — no cross-user existence leak.
        raise HTTPException(status_code=404, detail="registration_not_found")
    return reg


class _AlreadyRefunding(Exception):
    """Inside the order lock: this registration already has its refund."""


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

        # The group's order is on the leader's row.
        head_id = reg["group_head_id"] if "group_head_id" in reg else registration_id
        is_guest = head_id != registration_id
        paid_order = await conn.fetchrow(
            """
            SELECT * FROM payment_orders
            WHERE registration_id = $1 AND status = 'paid'
            ORDER BY paid_at DESC NULLS LAST, created_at DESC LIMIT 1
            """,
            head_id,
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
                context={"paid": False, "guest_of": head_id if is_guest else None},
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
        existing_active = await refund_repo.get_active_for_registration(registration_id)
        if existing_active is not None:
            return await _refresh_and_view(conn, registration_id, existing_active, gw)

        i_am_the_refund_creator = False
        winner = None
        try:
            async with conn.transaction():
                # Lock the order: refunds on it are worked out one at a time.
                await conn.execute(
                    "SELECT 1 FROM payment_orders WHERE id = $1 FOR UPDATE", paid_order["id"]
                )
                # A repeated click that waited for the lock: return the refund
                # the first one made.
                winner = (
                    await refund_repo.get_by_idempotency_key(idempotency_key)
                    or await refund_repo.get_active_for_registration(registration_id)
                )
                if winner is not None:
                    raise _AlreadyRefunding()
                quantity = int(paid_order["quantity"]) if "quantity" in paid_order else 1
                share = (Decimal(paid_order["final_amount"]) / Decimal(max(quantity, 1))).quantize(Decimal("0.01"))
                if is_guest:
                    people = 1
                else:
                    people = int(await conn.fetchval(
                        "SELECT COUNT(*) FROM registrations"
                        " WHERE group_head_id = $1::int AND status = 'registered'",
                        registration_id,
                    ))
                refunded = await refund_repo.total_active_for_order(paid_order["id"])
                left = Decimal(paid_order["final_amount"]) - refunded
                # The last refund on an order takes what's left, so rounding
                # never leaves a paisa behind; never more than was paid.
                amount = left if (not is_guest or people * share > left) else people * share
                if amount <= 0:
                    raise HTTPException(status_code=409, detail="nothing_left_to_refund")
                refund_row = await refund_repo.create(
                    public_refund_number=f"RFND-{secrets.token_urlsafe(9)}",
                    registration_id=registration_id,
                    payment_order_id=paid_order["id"],
                    payment_attempt_id=captured["id"],
                    gateway=gateway_name,
                    provider_payment_id=captured["gateway_payment_ref"],
                    amount=amount,
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
        except _AlreadyRefunding:
            return await _refresh_and_view(conn, registration_id, winner, gw)
        except asyncpg.exceptions.UniqueViolationError:
            # Lost the race (same key, or the one-active-refund-per-order
            # index). Reload the winner and return it — do NOT call the
            # provider a second time.
            winner = (
                await refund_repo.get_by_idempotency_key(idempotency_key)
                or await refund_repo.get_active_for_registration(registration_id)
            )
            return await _refresh_and_view(conn, registration_id, winner, gw)

        await audit_service.emit(
            actor_uid=firebase_uid, event_type="payment_refund_requested",
            entity_type="payment_refund", entity_id=refund_row["id"],
            context={"order_id": paid_order["id"], "amount": str(refund_row["amount"]),
                     "guest_of": head_id if is_guest else None},
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
            refund_number=refund_row["public_refund_number"],
        )
    except GatewayError as exc:
        reason = _refusal_reason(exc)
        _log.warning("[refunds] provider refused %s: %s", refund_row["public_refund_number"], reason.value)
        async with pool.acquire() as conn:
            updated = await record_refusal(conn, refund_row, reason, source="refund_call")
        return _view(registration_id, updated)

    if result.status not in _NORMALIZED_TO_INTERNAL:
        # The provider accepted the call but didn't say how it went:
        # treat as in progress, as before.
        from dataclasses import replace
        result = replace(result, status=NormalizedRefundStatus.REFUND_PENDING)
    async with pool.acquire() as conn:
        updated = await apply_refund_result(conn, refund_row, result, source="refund_call")
    return _view(registration_id, updated)


_STATUS_RANK = {"pending": 0, "processing": 0, "delayed": 0, "failed": 1, "processed": 2}

_REFUND_AUDIT_TYPE = {"processed": "payment_refund_processed", "failed": "payment_refund_failed"}


async def apply_refund_result(
    conn: asyncpg.Connection,
    refund_row: asyncpg.Record,
    result,
    *,
    source: str,
    provider_event: Optional[str] = None,
) -> asyncpg.Record:
    """Apply what the provider says about a refund (the refund call's own
    answer, a status check, or a refund webhook) to our row. One place, so
    the status, the bank reference (ARN) and the audit entry are handled the
    same way whichever way the news arrives.

    A refund never moves backwards: a late "pending" after "processed" (or
    after "failed") is ignored for the status, though a new bank reference
    is still kept. Writes an audit entry only when something changed."""
    async with conn.transaction():
        row = await conn.fetchrow(
            "SELECT * FROM payment_refunds WHERE id = $1 FOR UPDATE", refund_row["id"]
        )
        current = row["status"]
        mapped = _NORMALIZED_TO_INTERNAL.get(result.status)
        new_status, finalized = mapped if mapped else (current, False)
        if _STATUS_RANK.get(new_status, 0) < _STATUS_RANK.get(current, 0):
            new_status, finalized = current, False
        if new_status == "failed":
            failure_reason = result.failure_reason or row["failure_reason"] or "provider_failed"
        elif new_status == "processed":
            failure_reason = None
        else:
            failure_reason = row["failure_reason"]

        bank_ref = getattr(result, "bank_reference", None)
        speed = getattr(result, "speed_processed", None)
        changed = (
            new_status != current
            or (bank_ref and bank_ref != (row["bank_reference"] if "bank_reference" in row else None))
            or (result.provider_refund_id and not row["provider_refund_id"])
        )
        if not changed:
            return row
        updated = await RefundRepository(conn).mark(
            row["id"],
            status=new_status,
            provider_refund_id=result.provider_refund_id or None,
            failure_reason=failure_reason,
            finalized=finalized,
            bank_reference=bank_ref,
            speed_processed=speed,
        )

    context = {
        "status": new_status,
        "source": source,
        "order_id": updated["payment_order_id"],
        "provider": updated["gateway"],
        "provider_event": provider_event,
        "provider_refund_id": updated["provider_refund_id"],
        "bank_reference": updated["bank_reference"] if "bank_reference" in updated else None,
        "speed": speed,
        "amount": str(updated["amount"]),
        "reason": failure_reason if new_status == "failed" else None,
    }
    await audit_service.emit(
        actor_uid="system",
        event_type=_REFUND_AUDIT_TYPE.get(new_status, "payment_refund_updated"),
        entity_type="payment_refund", entity_id=updated["id"],
        context={k: v for k, v in context.items() if v is not None},
    )
    if new_status in ("processed", "failed"):
        _spawn(notify_refund(updated["id"]))
    return updated


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
            refund = await apply_refund_result(conn, refund, result, source="status_check")
    return _view(registration_id, refund)


async def get_refund_status(
    registration_id: int, user: Dict[str, Any]
) -> RefundStatusResponse:
    firebase_uid = user["firebase_uid"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        reg = await _load_owned_registration(conn, registration_id, firebase_uid)
        refund = await RefundRepository(conn).get_latest_for_registration(registration_id)
        if refund is None:
            view = _view(registration_id, None)
        else:
            gw = _resolve_gateway(refund["gateway"])
            view = await _refresh_and_view(conn, registration_id, refund, gw)
        return await _with_group_refunds(conn, reg, view)


async def _with_group_refunds(
    conn: asyncpg.Connection, reg: asyncpg.Record, view: RefundStatusResponse
) -> RefundStatusResponse:
    """Adds every refund on the registration's group, so the attendee sees
    each one (a guest's, then the rest) and what they add up to."""
    head_id = reg["group_head_id"] if "group_head_id" in reg else reg["registration_id"]
    people = await conn.fetchval(
        "SELECT COUNT(*) FROM registrations WHERE group_head_id = $1::int", head_id
    )
    if (people or 0) <= 1:
        return view
    rows = await conn.fetch(
        """
        SELECT f.*, r.fullname_snapshot AS person_name,
               r.registration_id <> r.group_head_id AS person_is_guest
        FROM payment_refunds f
        JOIN registrations r ON r.registration_id = f.registration_id
        WHERE r.group_head_id = $1::int
          AND f.status IN ('pending', 'processing', 'processed', 'delayed', 'failed')
        ORDER BY f.requested_at, f.id
        """,
        head_id,
    )
    paid = await conn.fetchval(
        """
        SELECT final_amount FROM payment_orders
        WHERE registration_id = $1::int AND status = 'paid'
        ORDER BY paid_at DESC NULLS LAST, created_at DESC LIMIT 1
        """,
        head_id,
    )
    view.group_refunds = [
        GroupRefundItem(
            refund_id=r["public_refund_number"],
            registration_id=r["registration_id"],
            name=r["person_name"],
            is_guest=bool(r["person_is_guest"]),
            status=_ATTENDEE_STATUS.get(r["status"], "refund_pending"),
            amount=r["amount"],
            currency=r["currency"],
            requested_at=r["requested_at"],
            finalized_at=r["finalized_at"],
            payment_reference=r["provider_payment_id"] or None,
            bank_reference=r["bank_reference"] if "bank_reference" in r else None,
        )
        for r in rows
    ]
    view.group_paid = paid
    return view


# ── Refund reliability (admin revamp step 10c) ───────────────────────────────
#
# A refund the provider refuses for a TEMPORARY reason (low balance, outage)
# becomes 'delayed' and is retried: after each captured payment (the balance
# just grew) and on an admin's Retry now. A retry after REFUND_RETRY_DAYS,
# or a FINAL reason at any time, makes it
# 'failed' — a person must act — and the attendee and admins are told once.
# A retry first asks the provider what refunds already exist for the
# payment, so it can never refund twice.


def _refusal_reason(exc: Exception) -> RefundFailureReason:
    if isinstance(exc, GatewayRefundRefusedError):
        return exc.reason
    return RefundFailureReason.PROVIDER_UNAVAILABLE


def _spawn(coro, delay_seconds: float = 2.0) -> None:
    """Run a side task (emails, retries) without holding up the caller. It
    starts after a short delay, so a caller's own transaction (e.g. a
    webhook's) has committed first. Best effort."""
    import asyncio

    async def _guard():
        try:
            if delay_seconds:
                await asyncio.sleep(delay_seconds)
            await coro
        except Exception:  # noqa: BLE001
            _log.exception("[refunds] background task failed")

    try:
        asyncio.get_running_loop().create_task(_guard())
    except RuntimeError:
        coro.close()


def _retry_window() -> timedelta:
    return timedelta(days=max(get_settings().refund_retry_days, 0))


async def record_refusal(
    conn: asyncpg.Connection,
    refund_row: asyncpg.Record,
    reason: RefundFailureReason,
    *,
    source: str,
) -> asyncpg.Record:
    """The provider refused (or couldn't take) a refund call. Temporary and
    still inside the retry window → 'delayed'; otherwise →
    'failed' (needs a person)."""
    now = datetime.now(timezone.utc)
    async with conn.transaction():
        row = await conn.fetchrow("SELECT * FROM payment_refunds WHERE id = $1 FOR UPDATE", refund_row["id"])
        if row["status"] == "processed":
            return row
        temporary = reason in TEMPORARY_REFUND_FAILURES
        within_window = now - row["requested_at"] < _retry_window()
        if temporary and within_window:
            status = "delayed"
        else:
            status = "failed"
        updated = await conn.fetchrow(
            """
            UPDATE payment_refunds SET status = $2::text, failure_reason = $3::text,
                   last_attempt_at = now(), updated_at = now(),
                   finalized_at = CASE WHEN $2::text = 'failed' THEN now() END
            WHERE id = $1::bigint RETURNING *
            """,
            row["id"], status, reason.value,
        )
    await audit_service.emit(
        actor_uid="system",
        event_type="payment_refund_delayed" if status == "delayed" else "payment_refund_failed",
        entity_type="payment_refund", entity_id=updated["id"],
        context={
            "status": status, "reason": reason.value, "temporary": temporary,
            "attempt": updated["attempt_count"], "source": source,
            "order_id": updated["payment_order_id"], "amount": str(updated["amount"]),
            "gave_up": bool(temporary and not within_window) or None,
        },
    )
    _spawn(notify_refund(updated["id"]))
    return updated


async def retry_refund(refund_id: int, *, source: str, actor_uid: str = "system",
                       force: bool = False) -> Optional[asyncpg.Record]:
    """Try a delayed refund again (or, with force — an admin's Retry now — a
    delayed or failed one). Returns the refund row, or None if there was
    nothing to do."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                "SELECT * FROM payment_refunds WHERE id = $1 FOR UPDATE", refund_id)
            if row is None:
                return None
            allowed = ("delayed", "failed") if force else ("delayed",)
            if row["status"] not in allowed:
                return row
            # Claim it: concurrent retries see 'pending' and leave it alone.
            row = await conn.fetchrow(
                """
                UPDATE payment_refunds SET status = 'pending', attempt_count = attempt_count + 1,
                       last_attempt_at = now(), finalized_at = NULL,
                       updated_at = now()
                WHERE id = $1 RETURNING *
                """,
                refund_id,
            )
        await audit_service.emit(
            actor_uid=actor_uid, event_type="payment_refund_retried",
            entity_type="payment_refund", entity_id=refund_id,
            context={"source": source, "attempt": row["attempt_count"], "order_id": row["payment_order_id"]},
        )

        gw = _resolve_gateway(row["gateway"])
        if gw is None or GatewayCapability.REFUND not in gw.capabilities:
            return await record_refusal(conn, row, RefundFailureReason.PROVIDER_UNAVAILABLE, source=source)
        mode = row["payment_mode"] if "payment_mode" in row else "test"

        # Never refund twice: see what the provider already holds for this payment.
        if hasattr(gw, "list_refunds"):
            try:
                existing = [r for r in gw.list_refunds(provider_payment_id=row["provider_payment_id"],
                                                       payment_mode=mode)
                            if r.status != NormalizedRefundStatus.REFUND_FAILED]
            except GatewayError:
                return await record_refusal(conn, row, RefundFailureReason.PROVIDER_UNAVAILABLE, source=source)
            # Ours: the provider's id we stored, or our refund number in its notes.
            def is_this(r) -> bool:
                return bool((row["provider_refund_id"] and r.provider_refund_id == row["provider_refund_id"])
                            or (r.refund_number and r.refund_number == row["public_refund_number"]))

            same = next((r for r in existing if is_this(r)), None)
            if same is None:
                # An order can have several refunds (one per cancelled guest):
                # set aside the provider's refunds that are our other ones.
                others = await conn.fetch(
                    """
                    SELECT provider_refund_id, public_refund_number FROM payment_refunds
                    WHERE payment_order_id = $1::bigint AND id <> $2::bigint
                    """,
                    row["payment_order_id"], row["id"],
                )
                other_ids = {o["provider_refund_id"] for o in others if o["provider_refund_id"]}
                other_numbers = {o["public_refund_number"] for o in others}
                unexplained = [r for r in existing
                               if r.provider_refund_id not in other_ids
                               and not (r.refund_number and r.refund_number in other_numbers)]
                # A refund sent before refund numbers were stored, for exactly
                # this amount: it's this one (the old rule).
                expected_minor = int((Decimal(row["amount"]) * 100).to_integral_value())
                same = next((r for r in unexplained
                             if not r.refund_number and r.amount_minor == expected_minor), None)
                if same is None and unexplained:
                    return await record_refusal(conn, row, RefundFailureReason.REFUNDED_OUTSIDE_APP,
                                                source=source)
            if same is not None:
                # It already went through at the provider: take that result.
                return await apply_refund_result(conn, row, same, source=f"{source}:found_at_provider")

        amount_minor = int((Decimal(row["amount"]) * 100).to_integral_value())
        try:
            result = gw.refund(
                provider_payment_id=row["provider_payment_id"],
                amount_minor=amount_minor,
                currency=row["currency"],
                # A new key per try: the provider remembers a refused key's answer.
                idempotency_key=f"{row['idempotency_key']}:try{row['attempt_count']}",
                payment_mode=mode,
                refund_number=row["public_refund_number"],
            )
        except GatewayError as exc:
            return await record_refusal(conn, row, _refusal_reason(exc), source=source)
        if result.status not in _NORMALIZED_TO_INTERNAL:
            from dataclasses import replace
            result = replace(result, status=NormalizedRefundStatus.REFUND_PENDING)
        return await apply_refund_result(conn, row, result, source=source)


async def retry_delayed_refunds(*, source: str, limit: int = 50) -> Dict[str, int]:
    """Retry every delayed refund, oldest first. Called right after a payment
    is captured: the balance just grew, so a refund refused for a low
    balance may go through now."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        ids = await conn.fetch(
            """
            SELECT id FROM payment_refunds
            WHERE status = 'delayed'
            ORDER BY requested_at, id LIMIT $1::int
            """,
            limit,
        )
    counts = {"tried": 0, "processed_or_sent": 0, "still_delayed": 0, "failed": 0}
    for r in ids:
        row = await retry_refund(r["id"], source=source)
        if row is None:
            continue
        counts["tried"] += 1
        if row["status"] == "delayed":
            counts["still_delayed"] += 1
        elif row["status"] == "failed":
            counts["failed"] += 1
        else:
            counts["processed_or_sent"] += 1
    return counts


async def _refund_mail_details(conn: asyncpg.Connection, refund_id: int) -> Optional[Dict[str, Any]]:
    row = await conn.fetchrow(
        """
        SELECT f.*, e.event_id, e.title AS event_title, r.email AS attendee_email,
               COALESCE(r.fullname_snapshot, r.badge_name) AS attendee_name
        FROM payment_refunds f
        JOIN registrations r ON r.registration_id = f.registration_id
        JOIN events e ON e.event_id = r.event_id
        WHERE f.id = $1
        """,
        refund_id,
    )
    if row is None:
        return None
    d = dict(row)
    d["mail"] = {
        "fullname": d["attendee_name"], "event_title": d["event_title"],
        "amount": f"₹{d['amount']}", "refund_number": d["public_refund_number"],
        "payment_reference": d["provider_payment_id"], "bank_reference": d.get("bank_reference"),
        "attendee": f"{d['attendee_name']} <{d['attendee_email']}>",
        "reason_text": REASON_ADMIN.get(d.get("failure_reason") or "", d.get("failure_reason")),
        "attempts": str(d.get("attempt_count") or 1),
    }
    return d


async def notify_refund(refund_id: int) -> None:
    """Send whichever refund email is due, once each: delayed (attendee),
    sent (attendee), needs attention (attendee + event admins + finance)."""
    from app.services import email_service

    pool = await get_pool()
    async with pool.acquire() as conn:
        d = await _refund_mail_details(conn, refund_id)
        if d is None:
            return
        status = d["status"]

        async def mark(column: str) -> bool:
            # Claim the send so a parallel run doesn't send it twice.
            return await conn.fetchval(
                f"UPDATE payment_refunds SET {column} = now() WHERE id = $1 AND {column} IS NULL RETURNING true",
                refund_id,
            ) is True

        if status == "delayed" and await mark("attendee_notified_delay_at"):
            await email_service.send_refund_delayed_email(d["attendee_email"], d["mail"])
        elif status == "processed" and await mark("attendee_notified_result_at"):
            await email_service.send_refund_processed_email(d["attendee_email"], d["mail"])
        elif status == "failed":
            if await mark("attendee_notified_result_at"):
                await email_service.send_refund_failed_email(d["attendee_email"], d["mail"])
            if await mark("admins_notified_at"):
                admins = await conn.fetch(
                    """
                    SELECT DISTINCT u.email FROM event_members m JOIN event_users u USING (firebase_uid)
                    WHERE m.event_id = $1 AND m.role = 'event_admin' AND m.status = 'active'
                    """,
                    d["event_id"],
                )
                to = {a["email"] for a in admins if a["email"]}
                to |= {e.strip() for e in get_settings().finance_alert_email.split(",") if e.strip()}
                for address in sorted(to):
                    await email_service.send_refund_admin_alert(address, d["mail"])

