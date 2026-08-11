"""Payment Phase 0 orchestration — orders, attempts, webhook processing.

Transaction/concurrency notes:
 - Order creation and attempt creation each run inside a single connection's
   transaction; the unique indexes on payment_orders (active-per-registration,
   idempotency-per-payer) and payment_attempts (order+attempt_number,
   gateway_payment_ref) are the actual duplicate-prevention mechanism —
   application checks are a fast path, not the source of truth.
 - Webhook processing takes `SELECT ... FOR UPDATE` on the order row so two
   webhook deliveries for the same order can never both apply a captured
   transition.
 - Registration confirmation on capture is idempotent: it only fires when the
   registration is not already 'registered'.
"""
import json
import logging
import secrets
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

import asyncpg
from fastapi import BackgroundTasks, HTTPException

from app.database import get_pool
from app.gateways import deterministic_sandbox as sandbox
from app.repositories.payment_repository import PaymentRepository
from app.repositories.registration_repository import RegistrationRepository
from app.schemas.payments import (
    CreatePaymentAttemptRequest,
    PaymentAttemptResponse,
    PaymentOrderResponse,
    PaymentTimelineResponse,
    PricingBreakdownResponse,
    TimelineEntry,
    WebhookAckResponse,
)
from app.services import audit_service, email_service, pricing_service
from app.config import get_settings

_log = logging.getLogger(__name__)

# Minutes an attempt may sit in 'pending' before a verify() call escalates it
# to 'requires_verification' and opens a VERIFICATION_UNRESOLVED exception.
# Phase 0 constant — the spec's "configurable pending-verification seat
# extension" would naturally become a payment_configurations column; not
# added in this pass to avoid another migration for a single number.
PENDING_VERIFICATION_WINDOW_MINUTES = 30
# How far to push the registration's hold_expires_at out when an attempt
# enters verification, so the seat isn't lost mid-check.
PENDING_VERIFICATION_HOLD_EXTENSION_MINUTES = 30

_HOLD_BEARING_STATUSES = ("seat_held", "payment_pending", "payment_verification", "payment_failed")

# event_audit_log.event_type -> attendee-facing label + whether the entry is
# shown to the attendee at all. Entries not listed here (webhook security
# events, internal rejection reasons) are developer/technical-only.
_ATTENDEE_TIMELINE_LABELS: Dict[str, str] = {
    "registration_seat_held": "Seat reserved",
    "payment_order_created": "Payment order created",
    "payment_attempt_initiated": "Payment started",
    "payment_captured": "Payment successful",
    "payment_failed": "Payment failed",
    "payment_pending": "Payment pending confirmation",
    "payment_cancelled": "Payment cancelled",
    "payment_verification_checked": "Payment status checked",
    "payment_verification_unresolved": "Payment still being verified",
    "registration_confirmed_by_payment": "Registration confirmed",
    "payment_captured_after_seat_expiry": "Payment received after seat hold expired — under review",
}


def _public_id(prefix: str) -> str:
    return f"{prefix}-{secrets.token_urlsafe(9)}"


def _is_hold_expired(registration: Optional[asyncpg.Record]) -> bool:
    if not registration:
        return False
    hold_expires_at = registration["hold_expires_at"]
    return hold_expires_at is not None and hold_expires_at < datetime.now(timezone.utc)


async def _get_config_or_404(conn: asyncpg.Connection, event_id: int) -> asyncpg.Record:
    config = await PaymentRepository(conn).get_published_config_for_event(event_id)
    if not config:
        raise HTTPException(status_code=409, detail="payment_not_configured")
    return config


async def get_pricing(event_id: int) -> PricingBreakdownResponse:
    pool = await get_pool()
    async with pool.acquire() as conn:
        config = await _get_config_or_404(conn, event_id)
    breakdown = pricing_service.calculate_price(dict(config))
    return PricingBreakdownResponse(
        event_id=event_id,
        configuration_key=config["configuration_key"],
        currency=breakdown["currency"],
        base_amount=breakdown["base_amount"],
        gst_enabled=breakdown["gst_enabled"],
        gst_rate=breakdown["gst_rate"],
        gst_mode=breakdown["gst_mode"],
        tax_amount=breakdown["tax_amount"],
        convenience_fee_enabled=breakdown["convenience_fee_enabled"],
        convenience_fee=breakdown["convenience_fee"],
        final_amount=breakdown["final_amount"],
        line_items=breakdown["line_items"],
    )


def _order_view(order: asyncpg.Record, registration_status: str) -> PaymentOrderResponse:
    outstanding = Decimal(order["final_amount"]) - Decimal(order["amount_paid"])
    can_pay = order["status"] in ("created", "payment_pending") and outstanding > 0
    if order["status"] == "paid":
        safe_message = "Payment complete. Your registration is confirmed."
    elif order["status"] == "expired":
        safe_message = "This payment session expired. Please register again."
    elif order["status"] == "cancelled":
        safe_message = "This order was cancelled."
    elif registration_status == "payment_verification":
        safe_message = "Your payment confirmation is being verified. Please do not pay again."
    elif registration_status == "payment_failed":
        safe_message = "Payment was not completed. Your registration details are saved — you may retry."
    else:
        safe_message = "Complete payment to confirm your registration."
    return PaymentOrderResponse(
        order_id=order["public_order_number"],
        registration_id=order["registration_id"],
        event_id=order["event_id"],
        currency=order["currency"],
        base_amount=order["base_amount"],
        tax_amount=order["tax_amount"],
        convenience_fee=order["convenience_fee"],
        final_amount=order["final_amount"],
        amount_paid=order["amount_paid"],
        outstanding_amount=outstanding,
        status=order["status"],
        registration_status=registration_status,
        expires_at=order["expires_at"],
        can_pay=can_pay,
        can_retry=can_pay and registration_status in ("payment_failed", "payment_pending", "seat_held"),
        safe_message=safe_message,
    )


async def create_order(
    registration_id: int, user: Dict[str, Any], idempotency_key: str
) -> PaymentOrderResponse:
    firebase_uid = user["firebase_uid"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        reg_repo = RegistrationRepository(conn)
        pay_repo = PaymentRepository(conn)

        registration = await reg_repo.get_by_id(registration_id)
        if not registration or registration["firebase_uid"] != firebase_uid:
            raise HTTPException(status_code=404, detail="registration_not_found")

        existing_by_key = await pay_repo.get_order_by_idempotency_key(firebase_uid, idempotency_key)
        if existing_by_key:
            if existing_by_key["registration_id"] != registration_id:
                raise HTTPException(status_code=409, detail="idempotency_key_conflict")
            return _order_view(existing_by_key, registration["status"])

        if registration["status"] not in ("seat_held", "payment_pending", "payment_failed"):
            raise HTTPException(status_code=409, detail="registration_not_payable")

        if _is_hold_expired(registration):
            await reg_repo.set_status(registration_id, "cancelled")
            raise HTTPException(status_code=409, detail="seat_hold_expired")

        active_order = await pay_repo.get_active_order_for_registration(registration_id)
        if active_order:
            return _order_view(active_order, registration["status"])

        config = await _get_config_or_404(conn, registration["event_id"])
        breakdown = pricing_service.calculate_price(dict(config))

        expires_at = datetime.now(timezone.utc) + timedelta(
            minutes=config["payment_session_expiry_minutes"]
        )

        try:
            async with conn.transaction():
                order = await pay_repo.create_order(
                    public_order_number=_public_id("ORD"),
                    registration_id=registration_id,
                    event_id=registration["event_id"],
                    payer_firebase_uid=firebase_uid,
                    configuration_id=config["id"],
                    configuration_version=config["version"],
                    currency=breakdown["currency"],
                    base_amount=breakdown["base_amount"],
                    tax_amount=breakdown["tax_amount"],
                    convenience_fee=breakdown["convenience_fee"],
                    final_amount=breakdown["final_amount"],
                    pricing_snapshot=breakdown,
                    idempotency_key=idempotency_key,
                    expires_at=expires_at,
                )
                if registration["status"] == "seat_held":
                    await reg_repo.set_status(registration_id, "payment_pending")
        except asyncpg.exceptions.UniqueViolationError:
            # Two concurrent create_order calls (double-click / two tabs) both
            # passed the idempotency-key and active-order checks above before
            # either had inserted — the unique indexes are the real source of
            # truth here, this is the losing side of that race. Resolve it the
            # same way a sequential retry would, instead of surfacing a 500.
            existing_by_key = await pay_repo.get_order_by_idempotency_key(firebase_uid, idempotency_key)
            if existing_by_key:
                return _order_view(existing_by_key, registration["status"])
            active_order = await pay_repo.get_active_order_for_registration(registration_id)
            if active_order:
                return _order_view(active_order, registration["status"])
            raise HTTPException(status_code=409, detail="payment_order_creation_conflict")

        await audit_service.emit(
            actor_uid=firebase_uid,
            event_type="payment_order_created",
            entity_type="payment_order",
            entity_id=order["id"],
            context={"registration_id": registration_id, "final_amount": str(order["final_amount"])},
        )
        return _order_view(order, "payment_pending" if registration["status"] == "seat_held" else registration["status"])


async def _load_order_for_user(
    conn: asyncpg.Connection, public_order_number: str, firebase_uid: str
) -> asyncpg.Record:
    order = await PaymentRepository(conn).get_order_by_public_id(public_order_number)
    if not order or order["payer_firebase_uid"] != firebase_uid:
        raise HTTPException(status_code=404, detail="payment_order_not_found")
    return order


async def get_order(public_order_number: str, user: Dict[str, Any]) -> PaymentOrderResponse:
    pool = await get_pool()
    async with pool.acquire() as conn:
        order = await _load_order_for_user(conn, public_order_number, user["firebase_uid"])
        registration = await RegistrationRepository(conn).get_by_id(order["registration_id"])
    return _order_view(order, registration["status"] if registration else "unknown")


async def create_attempt(
    public_order_number: str,
    user: Dict[str, Any],
    body: CreatePaymentAttemptRequest,
    background_tasks: BackgroundTasks,
) -> PaymentAttemptResponse:
    firebase_uid = user["firebase_uid"]
    if body.scenario not in sandbox.SUPPORTED_SCENARIOS:
        raise HTTPException(status_code=422, detail="unsupported_scenario")

    pool = await get_pool()
    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)
        reg_repo = RegistrationRepository(conn)
        order = await _load_order_for_user(conn, public_order_number, firebase_uid)
        registration = await reg_repo.get_by_id(order["registration_id"])

        if order["status"] not in ("created", "payment_pending"):
            raise HTTPException(status_code=409, detail="payment_order_not_payable")
        if order["expires_at"] < datetime.now(timezone.utc):
            raise HTTPException(status_code=409, detail="payment_order_expired")
        if Decimal(order["amount_paid"]) >= Decimal(order["final_amount"]):
            raise HTTPException(status_code=409, detail="payment_already_completed")
        if registration and registration["status"] in _HOLD_BEARING_STATUSES and _is_hold_expired(registration):
            await reg_repo.set_status(order["registration_id"], "cancelled")
            raise HTTPException(status_code=409, detail="seat_hold_expired")
        if await pay_repo.has_unresolved_attempt(order["id"]):
            detail = (
                "payment_verification_in_progress"
                if registration and registration["status"] == "payment_verification"
                else "payment_attempt_active"
            )
            raise HTTPException(status_code=409, detail=detail)

        gateway_order_ref = sandbox.create_gateway_order_ref()
        try:
            async with conn.transaction():
                attempt_number = await pay_repo.next_attempt_number(order["id"])
                attempt = await pay_repo.create_attempt(
                    public_attempt_number=_public_id("ATT"),
                    order_id=order["id"],
                    attempt_number=attempt_number,
                    gateway=sandbox.GATEWAY_NAME,
                    scenario=body.scenario,
                    amount=order["final_amount"],
                    currency=order["currency"],
                    gateway_order_ref=gateway_order_ref,
                )
                if order["status"] == "created":
                    await pay_repo.mark_order_payment_pending(order["id"])
        except asyncpg.exceptions.UniqueViolationError:
            # Two concurrent create_attempt calls (double-click) both passed
            # has_unresolved_attempt above before either had inserted — the
            # UNIQUE(order_id, attempt_number) constraint is the real guard.
            # This is the losing side of that race; fail clean, not with a 500.
            raise HTTPException(status_code=409, detail="payment_attempt_active")

    await audit_service.emit(
        actor_uid=firebase_uid,
        event_type="payment_attempt_initiated",
        entity_type="payment_attempt",
        entity_id=attempt["id"],
        context={"order_id": order["id"], "scenario": body.scenario},
    )

    settings = get_settings()
    raw_body, signature = sandbox.build_signed_delivery(
        gateway_order_ref=gateway_order_ref,
        scenario=body.scenario,
        amount=order["final_amount"],
        currency=order["currency"],
        secret=settings.payment_sandbox_signing_secret,
    )
    if sandbox.is_delayed_scenario(body.scenario):
        background_tasks.add_task(
            _deliver_delayed_webhook, raw_body, signature, sandbox.DELAYED_SCENARIO_DELAY_SECONDS
        )
    else:
        await process_webhook(sandbox.GATEWAY_NAME, raw_body, signature)
        # Immediate scenarios resolve synchronously above — re-read the attempt
        # so the response reflects the outcome, not the pre-webhook 'initiated' row.
        async with pool.acquire() as conn:
            attempt = await PaymentRepository(conn).get_attempt_by_id(attempt["id"])

    return PaymentAttemptResponse(
        attempt_id=attempt["public_attempt_number"],
        order_id=order["public_order_number"],
        attempt_number=attempt["attempt_number"],
        gateway=attempt["gateway"],
        status=attempt["status"],
        scenario=attempt["scenario"],
        initiated_at=attempt["initiated_at"],
    )


async def _deliver_delayed_webhook(raw_body: bytes, signature: str, delay_seconds: int) -> None:
    import asyncio

    await asyncio.sleep(delay_seconds)
    try:
        await process_webhook(sandbox.GATEWAY_NAME, raw_body, signature)
    except Exception:
        _log.exception("[payments] delayed sandbox webhook delivery failed")


async def process_webhook(gateway: str, raw_body: bytes, signature: str) -> WebhookAckResponse:
    settings = get_settings()
    signature_valid = sandbox.verify_signature(raw_body, signature, settings.payment_sandbox_signing_secret)

    try:
        payload: Dict[str, Any] = json.loads(raw_body)
    except (ValueError, TypeError):
        await audit_service.emit(
            actor_uid="system",
            event_type="payment_webhook_unparseable",
            entity_type="payment_webhook",
            entity_id=0,
            context={"gateway": gateway},
        )
        return WebhookAckResponse(status="rejected", processing_status="rejected")

    event_id = payload.get("event_id", "")
    event_type = payload.get("event_type", "")
    gateway_order_ref = payload.get("gateway_order_ref", "")
    hash_ = sandbox.payload_hash(raw_body)

    # WP3: webhook freshness. issued_at is part of the signed body (see
    # deterministic_sandbox.build_webhook_payload), so this is never trusted
    # from an unsigned source — it's only meaningful once signature_valid is
    # confirmed below, but computed here so both signature and freshness
    # errors are available at the same point in the flow.
    issued_at = payload.get("issued_at")
    now_epoch = datetime.now(timezone.utc).timestamp()
    timestamp_error: Optional[str] = None
    if issued_at is None:
        timestamp_error = "timestamp_missing"
    else:
        try:
            issued_at_val = float(issued_at)
        except (TypeError, ValueError):
            timestamp_error = "timestamp_malformed"
        else:
            age_seconds = now_epoch - issued_at_val
            if age_seconds > settings.payment_webhook_max_age_seconds:
                timestamp_error = "timestamp_stale"
            elif age_seconds < -settings.payment_webhook_max_future_skew_seconds:
                timestamp_error = "timestamp_future_skew"

    pool = await get_pool()
    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)

        attempt = await pay_repo.get_attempt_by_gateway_ref(gateway_order_ref) if gateway_order_ref else None
        order = await pay_repo.get_order_by_id(attempt["order_id"]) if attempt else None

        webhook_row = await pay_repo.record_webhook_event(
            gateway=gateway,
            gateway_event_id=event_id,
            event_type=event_type,
            payload_hash=hash_,
            signature_valid=signature_valid,
            correlated_order_id=order["id"] if order else None,
            correlated_attempt_id=attempt["id"] if attempt else None,
        )
        if webhook_row is None:
            # Same (gateway, event_id) already recorded — duplicate delivery, no-op.
            await audit_service.emit(
                actor_uid="system",
                event_type="payment_webhook_duplicate",
                entity_type="payment_webhook",
                entity_id=0,
                context={"gateway": gateway, "gateway_event_id": event_id},
            )
            return WebhookAckResponse(status="ok", processing_status="duplicate")

        if not signature_valid:
            await pay_repo.mark_webhook_processed(webhook_row["id"], "rejected", "invalid_signature")
            await audit_service.emit(
                actor_uid="system",
                event_type="payment_webhook_invalid_signature",
                entity_type="payment_webhook",
                entity_id=webhook_row["id"],
                context={"gateway": gateway},
            )
            return WebhookAckResponse(status="rejected", processing_status="rejected")

        if timestamp_error:
            # Positioned after the signature gate (a forged/unsigned stale
            # timestamp never reaches here) and before any attempt/order
            # lookup or business-state mutation. Duplicate protection above
            # is unaffected by this: a replay of an event_id already
            # recorded is caught by the webhook_row is None branch first,
            # regardless of its timestamp, so freshness is enforced
            # specifically for events seen for the first time.
            await pay_repo.mark_webhook_processed(webhook_row["id"], "rejected", timestamp_error)
            await audit_service.emit(
                actor_uid="system",
                event_type="payment_webhook_timestamp_rejected",
                entity_type="payment_webhook",
                entity_id=webhook_row["id"],
                context={"gateway": gateway, "reason": timestamp_error},
            )
            return WebhookAckResponse(status="rejected", processing_status="rejected")

        if not attempt or not order:
            await pay_repo.mark_webhook_processed(webhook_row["id"], "rejected", "unknown_gateway_order")
            await audit_service.emit(
                actor_uid="system",
                event_type="payment_webhook_unknown_order",
                entity_type="payment_webhook",
                entity_id=webhook_row["id"],
                context={"gateway": gateway, "gateway_order_ref": gateway_order_ref},
            )
            return WebhookAckResponse(status="rejected", processing_status="rejected")

        if str(payload.get("currency")) != attempt["currency"] or Decimal(str(payload.get("amount", "0"))) != Decimal(attempt["amount"]):
            await pay_repo.mark_webhook_processed(webhook_row["id"], "rejected", "amount_or_currency_mismatch")
            await audit_service.emit(
                actor_uid="system",
                event_type="payment_webhook_amount_mismatch",
                entity_type="payment_webhook",
                entity_id=webhook_row["id"],
                context={"order_id": order["id"], "attempt_id": attempt["id"]},
            )
            return WebhookAckResponse(status="rejected", processing_status="rejected")

        async with conn.transaction():
            locked_order = await conn.fetchrow(
                "SELECT * FROM payment_orders WHERE id = $1 FOR UPDATE", order["id"]
            )
            reg_repo = RegistrationRepository(conn)
            registration = await reg_repo.get_by_id(locked_order["registration_id"])

            if attempt["status"] not in ("initiated", "pending"):
                await pay_repo.mark_webhook_processed(webhook_row["id"], "duplicate")
                await audit_service.emit(
                    actor_uid="system",
                    event_type="payment_webhook_ignored_stale_attempt",
                    entity_type="payment_webhook",
                    entity_id=webhook_row["id"],
                    context={"attempt_id": attempt["id"], "attempt_status": attempt["status"]},
                )
                return WebhookAckResponse(status="ok", processing_status="duplicate")

            if event_type == "payment.captured":
                await pay_repo.update_attempt_captured(attempt["id"], payload.get("gateway_payment_ref", ""))
                # Financial state is preserved unconditionally — the money
                # side of this always happens, regardless of what state the
                # registration/seat is in. What varies below is only whether
                # we're also allowed to auto-confirm the registration.
                if Decimal(locked_order["amount_paid"]) < Decimal(locked_order["final_amount"]):
                    await pay_repo.mark_order_paid(locked_order["id"], Decimal(locked_order["final_amount"]))
                already_confirmed = registration and registration["status"] == "registered"
                hold_expired = (
                    registration
                    and not already_confirmed
                    and registration["status"] in _HOLD_BEARING_STATUSES
                    and _is_hold_expired(registration)
                )

                await pay_repo.mark_webhook_processed(webhook_row["id"], "processed")
                await audit_service.emit(
                    actor_uid="system", event_type="payment_captured",
                    entity_type="payment_attempt", entity_id=attempt["id"],
                    context={"order_id": order["id"]},
                )

                if hold_expired:
                    # Do not silently reconfirm an expired seat (possible
                    # overbooking) and do not discard the payment — preserve
                    # the captured funds and raise an exception for manual
                    # resolution instead.
                    existing_exc = await pay_repo.get_open_exception(
                        "PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY", attempt_id=attempt["id"]
                    )
                    if not existing_exc:
                        await pay_repo.create_exception(
                            exception_type="PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY",
                            order_id=order["id"],
                            attempt_id=attempt["id"],
                            registration_id=registration["registration_id"],
                            summary=(
                                f"Payment captured for order {locked_order['public_order_number']} "
                                f"after seat hold expired at {registration['hold_expires_at']}"
                            ),
                            detail={
                                "hold_expires_at": str(registration["hold_expires_at"]),
                                "captured_at": str(datetime.now(timezone.utc)),
                                "final_amount": str(locked_order["final_amount"]),
                            },
                        )
                    await audit_service.emit(
                        actor_uid="system", event_type="payment_captured_after_seat_expiry",
                        entity_type="registration", entity_id=registration["registration_id"],
                        context={"order_id": order["id"]},
                    )
                elif registration and not already_confirmed:
                    await reg_repo.set_status(registration["registration_id"], "registered")
                    await audit_service.emit(
                        actor_uid="system", event_type="registration_confirmed_by_payment",
                        entity_type="registration", entity_id=registration["registration_id"],
                        context={"order_id": order["id"]},
                    )
                    await _send_payment_confirmation_email(conn, registration)

            elif event_type == "payment.failed":
                await pay_repo.update_attempt_failed(
                    attempt["id"],
                    payload.get("failure_code", "UNKNOWN"),
                    payload.get("failure_message", "Payment failed"),
                )
                if registration and registration["status"] in ("seat_held", "payment_pending", "payment_verification"):
                    await reg_repo.set_status(registration["registration_id"], "payment_failed")
                await pay_repo.mark_webhook_processed(webhook_row["id"], "processed")
                await audit_service.emit(
                    actor_uid="system", event_type="payment_failed",
                    entity_type="payment_attempt", entity_id=attempt["id"],
                    context={"order_id": order["id"]},
                )

            elif event_type == "payment.pending":
                await pay_repo.update_attempt_status(attempt["id"], "pending")
                if registration and registration["status"] in ("seat_held", "payment_pending"):
                    await reg_repo.set_status(registration["registration_id"], "payment_verification")
                    # Protect the seat while verification is in progress —
                    # don't let it expire out from under a payment that may
                    # still resolve to captured.
                    await reg_repo.extend_hold(
                        registration["registration_id"],
                        datetime.now(timezone.utc) + timedelta(minutes=PENDING_VERIFICATION_HOLD_EXTENSION_MINUTES),
                    )
                await pay_repo.mark_webhook_processed(webhook_row["id"], "processed")
                await audit_service.emit(
                    actor_uid="system", event_type="payment_pending",
                    entity_type="payment_attempt", entity_id=attempt["id"],
                    context={"order_id": order["id"]},
                )

            elif event_type == "payment.cancelled":
                await pay_repo.update_attempt_status(attempt["id"], "cancelled")
                if registration and registration["status"] in ("seat_held", "payment_pending", "payment_verification"):
                    await reg_repo.set_status(registration["registration_id"], "payment_failed")
                await pay_repo.mark_webhook_processed(webhook_row["id"], "processed")
                await audit_service.emit(
                    actor_uid="system", event_type="payment_cancelled",
                    entity_type="payment_attempt", entity_id=attempt["id"],
                    context={"order_id": order["id"]},
                )
            else:
                await pay_repo.mark_webhook_processed(webhook_row["id"], "rejected", "unknown_event_type")
                return WebhookAckResponse(status="rejected", processing_status="rejected")

        return WebhookAckResponse(status="ok", processing_status="processed")


async def _send_payment_confirmation_email(conn: asyncpg.Connection, registration: asyncpg.Record) -> None:
    reg_row = await RegistrationRepository(conn).get_by_id_with_event(registration["registration_id"])
    if not reg_row:
        return
    join_url = (
        reg_row["virtual_url"]
        if reg_row["is_virtual"] and reg_row["event_status"] == "published"
        else None
    )
    result = await email_service.send_confirmation_email(
        email_to=reg_row["email_snapshot"],
        fullname=reg_row["fullname_snapshot"] or "",
        event_title=reg_row["event_title"] or "",
        registration_number=reg_row["registration_number"] or "",
        join_url=join_url,
    )
    await RegistrationRepository(conn).update_email_status(
        registration_id=registration["registration_id"],
        status=result.status,
        sent_at=result.sent_at,
        error=result.error,
    )


async def _fetch_audit_rows(conn: asyncpg.Connection, order_id: int) -> List[asyncpg.Record]:
    pay_repo = PaymentRepository(conn)
    attempts = await pay_repo.list_attempts_for_order(order_id)
    return await conn.fetch(
        """
        SELECT event_type, entity_type, entity_id, created_at, context FROM event_audit_log
        WHERE (entity_type = 'payment_order' AND entity_id = $1)
           OR (entity_type = 'payment_attempt' AND entity_id = ANY($2::int[]))
           OR (entity_type = 'registration' AND entity_id = (
                SELECT registration_id FROM payment_orders WHERE id = $1
           ))
        ORDER BY created_at ASC
        """,
        order_id,
        [a["id"] for a in attempts],
    )


async def get_timeline(public_order_number: str, user: Dict[str, Any]) -> PaymentTimelineResponse:
    """Attendee-safe view: friendly labels only, internal technical events
    (webhook signature/replay/mismatch rejections, stale-attempt no-ops)
    excluded, and no raw internal integer order/attempt IDs in `detail`."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        order = await _load_order_for_user(conn, public_order_number, user["firebase_uid"])
        audit_rows = await _fetch_audit_rows(conn, order["id"])

    entries = []
    for row in audit_rows:
        label = _ATTENDEE_TIMELINE_LABELS.get(row["event_type"])
        if label is None:
            continue  # not attendee-facing (security/internal-only event)
        detail = json.loads(row["context"]) if row["context"] else None
        if isinstance(detail, dict):
            detail = {k: v for k, v in detail.items() if k not in ("order_id",)}
            detail = detail or None
        entries.append(
            TimelineEntry(
                event_type=row["event_type"],
                entity_type=row["entity_type"],
                at=row["created_at"],
                detail=detail,
                label=label,
            )
        )
    return PaymentTimelineResponse(order_id=order["public_order_number"], entries=entries)


async def get_developer_timeline(public_order_number: str) -> PaymentTimelineResponse:
    """Full technical feed — every audit row, unfiltered, raw context intact.
    No ownership check (caller is dev-diagnostics-gated, not the attendee).
    Serves as the "admin" timeline too for Phase 0: no distinct admin role
    model exists yet for payments, so both are the same gated view."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        order = await PaymentRepository(conn).get_order_by_public_id(public_order_number)
        if not order:
            raise HTTPException(status_code=404, detail="payment_order_not_found")
        audit_rows = await _fetch_audit_rows(conn, order["id"])

    entries = [
        TimelineEntry(
            event_type=row["event_type"],
            entity_type=row["entity_type"],
            at=row["created_at"],
            detail=json.loads(row["context"]) if row["context"] else None,
            label=None,
        )
        for row in audit_rows
    ]
    return PaymentTimelineResponse(order_id=order["public_order_number"], entries=entries)


async def verify_attempt(public_attempt_number: str, user: Dict[str, Any]) -> PaymentAttemptResponse:
    """Controlled gateway-status check for a pending attempt. There is no
    real external gateway to query in Phase 0 sandbox, so "verification"
    means: re-read the attempt's current state (a webhook may already have
    resolved it since the last check) and, if it's been 'pending' longer
    than PENDING_VERIFICATION_WINDOW_MINUTES, escalate to
    'requires_verification' and open a VERIFICATION_UNRESOLVED exception for
    manual/dev resolution rather than leaving it silently stuck forever."""
    firebase_uid = user["firebase_uid"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)
        attempt = await pay_repo.get_attempt_by_public_id(public_attempt_number)
        if not attempt:
            raise HTTPException(status_code=404, detail="payment_attempt_not_found")
        order = await pay_repo.get_order_by_id(attempt["order_id"])
        if not order or order["payer_firebase_uid"] != firebase_uid:
            raise HTTPException(status_code=404, detail="payment_attempt_not_found")

        if attempt["status"] not in ("pending", "requires_verification"):
            raise HTTPException(status_code=409, detail="attempt_not_verifiable")

        await pay_repo.record_verification_check(attempt["id"])
        attempt = await pay_repo.get_attempt_by_id(attempt["id"])

        elapsed_minutes = (datetime.now(timezone.utc) - attempt["initiated_at"]).total_seconds() / 60
        if attempt["status"] == "pending" and elapsed_minutes >= PENDING_VERIFICATION_WINDOW_MINUTES:
            await pay_repo.update_attempt_status(attempt["id"], "requires_verification")
            registration = await RegistrationRepository(conn).get_by_id(order["registration_id"])
            existing_exc = await pay_repo.get_open_exception(
                "VERIFICATION_UNRESOLVED", attempt_id=attempt["id"]
            )
            if not existing_exc:
                await pay_repo.create_exception(
                    exception_type="VERIFICATION_UNRESOLVED",
                    order_id=order["id"],
                    attempt_id=attempt["id"],
                    registration_id=registration["registration_id"] if registration else None,
                    summary=(
                        f"Attempt {attempt['public_attempt_number']} still pending "
                        f"after {elapsed_minutes:.0f} minutes"
                    ),
                    detail={"elapsed_minutes": round(elapsed_minutes, 1)},
                )
            attempt = await pay_repo.get_attempt_by_id(attempt["id"])

    await audit_service.emit(
        actor_uid=firebase_uid,
        event_type="payment_verification_checked" if attempt["status"] == "pending" else "payment_verification_unresolved",
        entity_type="payment_attempt",
        entity_id=attempt["id"],
        context={"order_id": order["id"], "status": attempt["status"]},
    )

    return PaymentAttemptResponse(
        attempt_id=attempt["public_attempt_number"],
        order_id=order["public_order_number"],
        attempt_number=attempt["attempt_number"],
        gateway=attempt["gateway"],
        status=attempt["status"],
        scenario=attempt["scenario"],
        initiated_at=attempt["initiated_at"],
    )
