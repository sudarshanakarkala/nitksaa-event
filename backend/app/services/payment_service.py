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
from app.gateways import registry as gateway_registry
from app.gateways.base import (
    GatewayCapability,
    GatewayError,
    GatewayWebhookUnparseableError,
    NormalizedStatus,
    payload_hash as _gateway_payload_hash,
)
from app.gateways.registry import GatewayDisabledError, UnknownGatewayError
from app.repositories.payment_repository import PaymentRepository
from app.repositories.refund_repository import RefundRepository
from app.repositories.registration_repository import RegistrationRepository
from app.schemas.payments import (
    CreatePaymentAttemptRequest,
    PaymentAttemptResponse,
    PaymentCheckout,
    PaymentOrderResponse,
    PaymentTimelineResponse,
    PricingBreakdownResponse,
    TimelineEntry,
    VerifyCheckoutRequest,
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

# Attempt states a provider-confirmed capture may still move to 'captured'
# (see _outcome_applies). Never 'captured' itself.
_CAPTURE_RECOVERABLE_STATUSES = ("requires_verification", "failed", "cancelled")

# event_audit_log.event_type -> attendee-facing label + whether the entry is
# shown to the attendee at all. Entries not listed here (webhook security
# events, internal rejection reasons) are developer/technical-only.
# Cancellation / refund audit rows are deliberately NOT listed: the attendee
# timeline builds those from the state rows instead (see
# _cancellation_and_refund_entries), and listing them here would show each
# event twice.
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


def _outcome_applies(attempt_status: str, outcome: NormalizedStatus) -> bool:
    """Whether a gateway outcome may still change an attempt in
    `attempt_status`. Any outcome applies to an in-flight attempt
    ('initiated' / 'pending'). A provider-confirmed capture ALSO applies to
    one earlier marked requires_verification / failed / cancelled — captured
    money is never discarded because another outcome for the same provider
    order (e.g. a declined first card) happened to arrive first. Failure and
    pending outcomes never resurrect or overwrite those states, and nothing
    moves a 'captured' attempt."""
    if attempt_status in ("initiated", "pending"):
        return True
    return outcome == NormalizedStatus.PAYMENT_SUCCESS and attempt_status in _CAPTURE_RECOVERABLE_STATUSES


def _payment_mode_of(row: asyncpg.Record) -> str:
    return row["payment_mode"] if "payment_mode" in row else "test"


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
    payment_mode = _payment_mode_of(order)
    # An expired / cancelled order keeps its own, more specific message even
    # when the registration is cancelled too (a seat-hold expiry cancels the
    # registration and expires the order together). Past that, the
    # registration's current state wins over the order's: a refunded paid
    # order keeps status='paid' (migration 022), so a cancelled or
    # under-review registration must never be described as confirmed.
    if order["status"] == "expired":
        safe_message = "This payment session expired. Please register again."
    elif order["status"] == "cancelled":
        safe_message = "This order was cancelled."
    elif registration_status == "cancelled":
        safe_message = "Your registration is cancelled."
    elif order["status"] == "paid" and registration_status == "registered":
        safe_message = "Payment complete. Your registration is confirmed."
    elif order["status"] == "paid":
        safe_message = "Payment received. Your registration is under review."
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
        payment_mode=payment_mode,
        real_money=payment_mode == "live",
        gateway=order["gateway"] if "gateway" in order else None,
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
                    gateway=config["gateway"] if "gateway" in config else "deterministic_sandbox",
                    payment_mode=config["payment_mode"] if "payment_mode" in config else "test",
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


def _gateway_for_order(order: asyncpg.Record):
    """Resolve the enabled gateway an order was created against
    (payment_orders.gateway snapshot). Returns None if it is unknown/disabled
    — callers fall back to the legacy sandbox re-read behaviour."""
    name = order["gateway"] if "gateway" in order else get_settings().payment_gateway_mode
    try:
        return gateway_registry.get_enabled_gateway(name, get_settings())
    except (UnknownGatewayError, GatewayDisabledError):
        return None


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
    settings = get_settings()

    pool = await get_pool()
    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)
        reg_repo = RegistrationRepository(conn)
        order = await _load_order_for_user(conn, public_order_number, firebase_uid)
        registration = await reg_repo.get_by_id(order["registration_id"])

    # Gateway dispatch is per-order (payment_configurations.gateway, snapshotted
    # onto payment_orders.gateway at create_order time) — NOT the global
    # settings.payment_gateway_mode. This is what lets the ₹1 razorpay pilot
    # event and every existing deterministic_sandbox event coexist.
    order_gateway_name = order["gateway"] if "gateway" in order else settings.payment_gateway_mode
    order_payment_mode = _payment_mode_of(order)
    try:
        gateway = gateway_registry.get_enabled_gateway(order_gateway_name, settings)
    except (UnknownGatewayError, GatewayDisabledError):
        # Unknown/disabled/misconfigured (e.g. razorpay with no credentials)
        # — fail closed, never silently fall back to another gateway.
        raise HTTPException(status_code=503, detail="payment_gateway_unavailable")
    # `scenario` is only meaningful to gateways that declare supported_scenarios
    # (the sandbox). A real gateway ignores it and determines its own outcome.
    if gateway.supported_scenarios and body.scenario not in gateway.supported_scenarios:
        raise HTTPException(status_code=422, detail="unsupported_scenario")

    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)
        reg_repo = RegistrationRepository(conn)

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
            try:
                reusable = await _reusable_hosted_checkout(pay_repo, gateway, order, registration)
            except GatewayError:
                # e.g. the order's payment_mode no longer matches this
                # deployment's credentials — fail closed, attempt untouched.
                raise HTTPException(status_code=502, detail="payment_gateway_error")
            if reusable is not None:
                existing_attempt, existing_checkout = reusable
                return _attempt_response(existing_attempt, order, gateway.name, existing_checkout)
            detail = (
                "payment_verification_in_progress"
                if registration and registration["status"] == "payment_verification"
                else "payment_attempt_active"
            )
            raise HTTPException(status_code=409, detail=detail)

        gateway_order_ref = gateway.create_gateway_order_ref()
        try:
            async with conn.transaction():
                attempt_number = await pay_repo.next_attempt_number(order["id"])
                attempt = await pay_repo.create_attempt(
                    public_attempt_number=_public_id("ATT"),
                    order_id=order["id"],
                    attempt_number=attempt_number,
                    gateway=gateway.name,
                    scenario=body.scenario,
                    amount=order["final_amount"],
                    currency=order["currency"],
                    gateway_order_ref=gateway_order_ref,
                    payment_mode=order_payment_mode,
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

    try:
        initiation = gateway.create_payment(
            gateway_order_ref=gateway_order_ref,
            amount=order["final_amount"],
            currency=order["currency"],
            scenario=body.scenario,
            payment_mode=order_payment_mode,
        )
    except GatewayError:
        # Provider order creation failed (network, credentials, provider
        # error). The attempt row exists but has no usable gateway order —
        # mark it failed so it doesn't block retry, and surface a safe error.
        _log.exception("[payments] gateway create_payment failed for attempt %s", attempt["id"])
        async with pool.acquire() as conn:
            await PaymentRepository(conn).update_attempt_failed(
                attempt["id"], "GATEWAY_INITIATION_FAILED", "Could not start payment. Please try again."
            )
        raise HTTPException(status_code=502, detail="payment_gateway_error")

    # A provider that mints its own order id (Razorpay) returns it here; it
    # differs from the placeholder we generated. Persist the real reference so
    # the later webhook / status query can correlate back to this attempt.
    if initiation.gateway_order_ref and initiation.gateway_order_ref != gateway_order_ref:
        async with pool.acquire() as conn:
            await PaymentRepository(conn).update_attempt_gateway_order_ref(
                attempt["id"], initiation.gateway_order_ref
            )
        gateway_order_ref = initiation.gateway_order_ref

    if initiation.delayed_webhook:
        delayed = initiation.delayed_webhook
        background_tasks.add_task(
            _deliver_delayed_webhook, gateway.name, delayed.raw_body, delayed.signature, delayed.delay_seconds
        )
    elif initiation.immediate_webhook:
        immediate = initiation.immediate_webhook
        await process_webhook(
            gateway.name, immediate.raw_body, immediate.signature, payment_mode=order_payment_mode
        )
        # Immediate scenarios resolve synchronously above — re-read the attempt
        # so the response reflects the outcome, not the pre-webhook 'initiated' row.
        async with pool.acquire() as conn:
            attempt = await PaymentRepository(conn).get_attempt_by_id(attempt["id"])

    return _attempt_response(attempt, order, gateway.name, initiation.checkout)


def _attempt_response(
    attempt: asyncpg.Record, order: asyncpg.Record, gateway_name: str, gateway_checkout: Any
) -> PaymentAttemptResponse:
    checkout = None
    if gateway_checkout:
        c = gateway_checkout
        checkout = PaymentCheckout(
            provider=gateway_name,
            provider_order_id=c.provider_order_id,
            key_id=c.key_id,
            amount_minor=c.amount_minor,
            currency=c.currency,
        )
    payment_mode = _payment_mode_of(order)
    return PaymentAttemptResponse(
        attempt_id=attempt["public_attempt_number"],
        order_id=order["public_order_number"],
        attempt_number=attempt["attempt_number"],
        gateway=attempt["gateway"],
        status=attempt["status"],
        scenario=attempt["scenario"],
        initiated_at=attempt["initiated_at"],
        checkout=checkout,
        payment_mode=payment_mode,
        real_money=payment_mode == "live",
    )


async def _reusable_hosted_checkout(
    pay_repo: PaymentRepository,
    gateway: Any,
    order: asyncpg.Record,
    registration: Optional[asyncpg.Record],
) -> Optional[tuple]:
    """(attempt, checkout) to hand back when an attendee closed hosted
    checkout without paying and presses Pay again — the SAME attempt and the
    SAME provider order, rebuilt without any provider call — or None to keep
    the one-unresolved-attempt 409.

    Callers have already checked ownership and that the order is payable,
    unexpired and not fully paid, and that the seat hold is still valid.
    Only an attempt still 'initiated' qualifies: 'pending' and
    'requires_verification' mean a payment may already be in flight (the
    attendee is told not to pay again), so those are never reopened."""
    attempt = await pay_repo.get_unresolved_attempt(order["id"])
    if (
        attempt is None
        or attempt["status"] != "initiated"
        or attempt["gateway"] != gateway.name
        or _payment_mode_of(attempt) != _payment_mode_of(order)
        or attempt["currency"] != order["currency"]
        or Decimal(attempt["amount"]) != Decimal(order["final_amount"])
        or registration is None
        or registration["status"] not in ("seat_held", "payment_pending", "payment_failed")
    ):
        return None
    checkout = gateway.rebuild_checkout(
        gateway_order_ref=attempt["gateway_order_ref"],
        amount=attempt["amount"],
        currency=attempt["currency"],
        payment_mode=_payment_mode_of(attempt),
    )
    return (attempt, checkout) if checkout is not None else None


async def _deliver_delayed_webhook(gateway_name: str, raw_body: bytes, signature: str, delay_seconds: int) -> None:
    import asyncio

    await asyncio.sleep(delay_seconds)
    try:
        await process_webhook(gateway_name, raw_body, signature)
    except Exception:
        _log.exception("[payments] delayed sandbox webhook delivery failed")


async def process_webhook(
    gateway: str,
    raw_body: bytes,
    signature: str,
    provider_event_id: Optional[str] = None,
    payment_mode: Optional[str] = None,
) -> WebhookAckResponse:
    """`payment_mode` is set only for Razorpay deliveries to the single
    webhook route POST /api/v1/payments/webhook (see app/api/payments.py),
    which passes this deployment's RAZORPAY_MODE. It selects which credential
    profile `verify_webhook` checks the signature against, AND is
    cross-checked against the matched order's own snapshotted payment_mode
    below — a delivery for an order of the other mode is rejected even if
    its signature happens to verify. None for gateways without a mode
    concept (the sandbox) and for internal calls (immediate/delayed sandbox
    delivery)."""
    settings = get_settings()

    try:
        gateway_obj = gateway_registry.get_enabled_gateway(gateway, settings)
    except (UnknownGatewayError, GatewayDisabledError):
        # Defense in depth: the HTTP route (app.api.payments) already
        # rejects an unknown/disabled gateway before calling this function,
        # but process_webhook is also called directly (delayed sandbox
        # delivery, dev diagnostics) and must not trust its own caller
        # blindly, especially since `gateway` originates from an
        # attacker-controlled URL path segment on the primary call path.
        await audit_service.emit(
            actor_uid="system",
            event_type="payment_webhook_unknown_gateway",
            entity_type="payment_webhook",
            entity_id=0,
            context={"gateway": gateway},
        )
        return WebhookAckResponse(status="rejected", processing_status="rejected")

    signature_valid = gateway_obj.verify_webhook(raw_body, signature, payment_mode=payment_mode)
    if not signature_valid and payment_mode is not None:
        # Mode-specific (Razorpay) routes: an unauthenticated delivery —
        # missing/malformed/wrong signature, or a route whose credentials this
        # deployment doesn't hold — is refused BEFORE any webhook-event write,
        # so it can never claim the event id a genuine delivery will use.
        # 400 (not 200) so a real Razorpay delivery that fails here is retried.
        await audit_service.emit(
            actor_uid="system",
            event_type="payment_webhook_invalid_signature",
            entity_type="payment_webhook",
            entity_id=0,
            context={"gateway": gateway},
        )
        raise HTTPException(status_code=400, detail="invalid_signature")

    try:
        event = gateway_obj.parse_webhook(raw_body)
    except GatewayWebhookUnparseableError:
        await audit_service.emit(
            actor_uid="system",
            event_type="payment_webhook_unparseable",
            entity_type="payment_webhook",
            entity_id=0,
            context={"gateway": gateway},
        )
        return WebhookAckResponse(status="rejected", processing_status="rejected")

    # Dedupe id: the provider's own event id (Razorpay X-Razorpay-Event-Id
    # header, passed by the route) is preferred; otherwise the adapter's
    # body-derived id (sandbox uuid, or Razorpay "<event>:<entity_id>").
    event_id = provider_event_id or event.event_id
    gateway_order_ref = event.gateway_order_ref
    hash_ = _gateway_payload_hash(raw_body)

    # WP3: webhook freshness. issued_at is part of the signed body (see
    # deterministic_sandbox.build_webhook_payload), so this is never trusted
    # from an unsigned source — it's only meaningful once signature_valid is
    # confirmed below, but computed here so both signature and freshness
    # errors are available at the same point in the flow.
    issued_at = event.issued_at_raw
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
        # ONE transaction for the event claim, the checks and the payment
        # state change (_apply_gateway_outcome's own transaction nests as a
        # savepoint). If processing fails, the claim rolls back with it, the
        # route returns 500 and Razorpay's retry of the same event id is
        # processed normally. A concurrent delivery of the same id waits on
        # the unique (gateway, gateway_event_id) index until this commits,
        # then resolves as a duplicate.
        async with conn.transaction():
            attempt = await pay_repo.get_attempt_by_gateway_ref(gateway_order_ref) if gateway_order_ref else None
            order = await pay_repo.get_order_by_id(attempt["order_id"]) if attempt else None

            webhook_row = await pay_repo.record_webhook_event(
                gateway=gateway,
                gateway_event_id=event_id,
                event_type=event.raw_event_type,
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

            if payment_mode is not None and _payment_mode_of(order) != payment_mode:
                # Delivered to a deployment of the other mode (e.g. an order
                # created under RAZORPAY_MODE=test, delivered to
                # /api/v1/payments/webhook after the deployment moved to live) —
                # fail closed even though signature/timestamp already passed.
                # Never happens for a real Razorpay delivery (its webhook secret
                # only ever verifies on a deployment of the matching mode), but a
                # misconfigured Dashboard webhook or a replayed delivery must
                # not be allowed to apply.
                await pay_repo.mark_webhook_processed(webhook_row["id"], "rejected", "webhook_mode_mismatch")
                await audit_service.emit(
                    actor_uid="system",
                    event_type="payment_webhook_mode_mismatch",
                    entity_type="payment_webhook",
                    entity_id=webhook_row["id"],
                    context={"gateway": gateway, "route_mode": payment_mode, "order_mode": _payment_mode_of(order)},
                )
                return WebhookAckResponse(status="rejected", processing_status="rejected")

            if str(event.currency) != attempt["currency"] or Decimal(event.amount_raw) != Decimal(attempt["amount"]):
                await pay_repo.mark_webhook_processed(webhook_row["id"], "rejected", "amount_or_currency_mismatch")
                await audit_service.emit(
                    actor_uid="system",
                    event_type="payment_webhook_amount_mismatch",
                    entity_type="payment_webhook",
                    entity_id=webhook_row["id"],
                    context={"order_id": order["id"], "attempt_id": attempt["id"]},
                )
                return WebhookAckResponse(status="rejected", processing_status="rejected")

            async def _mark(status: str, error_code: Optional[str] = None) -> None:
                await pay_repo.mark_webhook_processed(webhook_row["id"], status, error_code)

            outcome = await _apply_gateway_outcome(
                conn, attempt=attempt, order=order, event=event, mark_processed=_mark,
                stale_attempt_audit_entity_id=webhook_row["id"],
            )

    if outcome == "duplicate":
        return WebhookAckResponse(status="ok", processing_status="duplicate")
    if outcome == "rejected":
        return WebhookAckResponse(status="rejected", processing_status="rejected")
    return WebhookAckResponse(status="ok", processing_status="processed")


async def _apply_gateway_outcome(
    conn: asyncpg.Connection,
    *,
    attempt: asyncpg.Record,
    order: asyncpg.Record,
    event,
    mark_processed,
    stale_attempt_audit_entity_id: int = 0,
) -> str:
    """Apply a normalized gateway outcome (from a verified webhook OR an
    authoritative query_payment_status check) to the attempt / order /
    registration under a row lock. Single source of truth for the
    captured / failed / pending / cancelled state machine — the webhook path
    and the checkout-verify path both funnel through here so they can never
    diverge.

    `mark_processed(status, error_code=None)` is the caller's bookkeeping
    hook: the webhook path updates its payment_webhook_events row; the
    verify path passes a no-op. Returns 'processed' | 'duplicate' |
    'rejected'.
    """
    async with conn.transaction():
        pay_repo = PaymentRepository(conn)
        reg_repo = RegistrationRepository(conn)
        locked_order = await conn.fetchrow(
            "SELECT * FROM payment_orders WHERE id = $1 FOR UPDATE", order["id"]
        )
        registration = await reg_repo.get_by_id(locked_order["registration_id"])
        # Decide on the attempt as it is NOW, under the order lock — never on
        # the caller's pre-lock copy: a concurrent verify / webhook for the
        # same order may already have moved it (e.g. to captured).
        attempt = await pay_repo.get_attempt_by_id(attempt["id"])

        if not _outcome_applies(attempt["status"], event.status):
            await mark_processed("duplicate")
            await audit_service.emit(
                actor_uid="system",
                event_type="payment_webhook_ignored_stale_attempt",
                entity_type="payment_webhook",
                entity_id=stale_attempt_audit_entity_id,
                context={"attempt_id": attempt["id"], "attempt_status": attempt["status"]},
            )
            return "duplicate"

        if event.status == NormalizedStatus.PAYMENT_SUCCESS:
            await pay_repo.update_attempt_captured(attempt["id"], event.gateway_payment_ref)
            # Financial state is preserved unconditionally — the money side of
            # this always happens, regardless of what state the registration/
            # seat is in. What varies below is only whether we're also allowed
            # to auto-confirm the registration.
            if Decimal(locked_order["amount_paid"]) < Decimal(locked_order["final_amount"]):
                await pay_repo.mark_order_paid(locked_order["id"], Decimal(locked_order["final_amount"]))
            already_confirmed = registration and registration["status"] == "registered"
            # The seat can no longer be safely confirmed: its hold expired, or
            # the registration was already cancelled (seat released) — e.g. a
            # late capture on an attempt earlier marked failed. The money is
            # still recorded above; the support exception below handles it.
            hold_expired = (
                registration
                and not already_confirmed
                and (
                    registration["status"] == "cancelled"
                    or (registration["status"] in _HOLD_BEARING_STATUSES and _is_hold_expired(registration))
                )
            )

            await mark_processed("processed")
            await audit_service.emit(
                actor_uid="system", event_type="payment_captured",
                entity_type="payment_attempt", entity_id=attempt["id"],
                context={"order_id": order["id"]},
            )

            if hold_expired:
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
                            "registration_status": registration["status"],
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

        elif event.status == NormalizedStatus.PAYMENT_FAILED:
            await pay_repo.update_attempt_failed(
                attempt["id"], event.failure_code, event.failure_message,
            )
            if registration and registration["status"] in ("seat_held", "payment_pending", "payment_verification"):
                await reg_repo.set_status(registration["registration_id"], "payment_failed")
            await mark_processed("processed")
            await audit_service.emit(
                actor_uid="system", event_type="payment_failed",
                entity_type="payment_attempt", entity_id=attempt["id"],
                context={"order_id": order["id"]},
            )

        elif event.status == NormalizedStatus.PAYMENT_PENDING:
            await pay_repo.update_attempt_status(attempt["id"], "pending")
            if registration and registration["status"] in ("seat_held", "payment_pending"):
                await reg_repo.set_status(registration["registration_id"], "payment_verification")
                await reg_repo.extend_hold(
                    registration["registration_id"],
                    datetime.now(timezone.utc) + timedelta(minutes=PENDING_VERIFICATION_HOLD_EXTENSION_MINUTES),
                )
            await mark_processed("processed")
            await audit_service.emit(
                actor_uid="system", event_type="payment_pending",
                entity_type="payment_attempt", entity_id=attempt["id"],
                context={"order_id": order["id"]},
            )

        elif event.status == NormalizedStatus.PAYMENT_CANCELLED:
            await pay_repo.update_attempt_status(attempt["id"], "cancelled")
            if registration and registration["status"] in ("seat_held", "payment_pending", "payment_verification"):
                await reg_repo.set_status(registration["registration_id"], "payment_failed")
            await mark_processed("processed")
            await audit_service.emit(
                actor_uid="system", event_type="payment_cancelled",
                entity_type="payment_attempt", entity_id=attempt["id"],
                context={"order_id": order["id"]},
            )
        else:
            await mark_processed("rejected", "unknown_event_type")
            return "rejected"

    return "processed"


async def verify_checkout(
    public_order_number: str, user: Dict[str, Any], body: VerifyCheckoutRequest
) -> "VerifyCheckoutResponse":
    """Backend verification of a hosted-checkout (Razorpay) return.

    The client's (order_id, payment_id, signature) triple is a FIRST GATE
    only — a valid signature proves the values came from the gateway
    unmodified, not that money moved. Confirmation happens strictly from
    gw.query_payment_status() (authoritative, server-to-server), applied
    through the same _apply_gateway_outcome state machine the webhook uses.
    A browser that merely POSTs a fake success can never confirm a
    registration.
    """
    from app.schemas.payments import VerifyCheckoutResponse

    firebase_uid = user["firebase_uid"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)
        order = await _load_order_for_user(conn, public_order_number, firebase_uid)

        gw = _gateway_for_order(order)
        if gw is None or GatewayCapability.VERIFY_PAYMENT not in gw.capabilities:
            raise HTTPException(status_code=409, detail="checkout_verification_not_supported")

        attempt = await pay_repo.get_attempt_by_gateway_ref(body.razorpay_order_id)
        if not attempt or attempt["order_id"] != order["id"]:
            raise HTTPException(status_code=404, detail="payment_attempt_not_found")

        # Server-stored provider order id must match what the client returned.
        if attempt["gateway_order_ref"] != body.razorpay_order_id:
            raise HTTPException(status_code=400, detail="checkout_order_mismatch")

        order_payment_mode = _payment_mode_of(order)
        sig_ok = gw.verify_checkout_signature(
            provider_order_id=body.razorpay_order_id,
            provider_payment_id=body.razorpay_payment_id,
            signature=body.razorpay_signature,
            payment_mode=order_payment_mode,
        )
        if not sig_ok:
            await audit_service.emit(
                actor_uid="system", event_type="payment_checkout_signature_invalid",
                entity_type="payment_attempt", entity_id=attempt["id"],
                context={"order_id": order["id"]},
            )
            raise HTTPException(status_code=400, detail="checkout_signature_invalid")

        try:
            remote = gw.query_payment_status(body.razorpay_order_id, payment_mode=order_payment_mode)
        except GatewayError:
            _log.exception("[payments] query_payment_status failed during verify-checkout")
            raise HTTPException(status_code=502, detail="payment_gateway_error")

        # Never trust the browser-reported payment id either — confirm the
        # provider's own record is for the same order and amount/currency.
        if remote.status == NormalizedStatus.PAYMENT_SUCCESS:
            if (
                str(remote.currency) != attempt["currency"]
                or Decimal(remote.amount_raw) != Decimal(attempt["amount"])
            ):
                await audit_service.emit(
                    actor_uid="system", event_type="payment_checkout_amount_mismatch",
                    entity_type="payment_attempt", entity_id=attempt["id"],
                    context={"order_id": order["id"]},
                )
                raise HTTPException(status_code=400, detail="checkout_amount_mismatch")

        # Pre-filter only — _apply_gateway_outcome re-checks under the order lock.
        if _outcome_applies(attempt["status"], remote.status):
            async def _noop(_s: str, _e: Optional[str] = None) -> None:
                return None

            await _apply_gateway_outcome(
                conn, attempt=attempt, order=order, event=remote, mark_processed=_noop,
            )

        order = await pay_repo.get_order_by_public_id(public_order_number)
        attempt = await pay_repo.get_attempt_by_id(attempt["id"])
        registration = await RegistrationRepository(conn).get_by_id(order["registration_id"])

    reg_status = registration["status"] if registration else "unknown"
    confirmed = order["status"] == "paid" and reg_status == "registered"
    if confirmed:
        msg = "Payment confirmed. Your registration is complete."
    elif remote.status == NormalizedStatus.PAYMENT_PENDING or attempt["status"] in ("pending", "requires_verification"):
        msg = "Payment received — confirmation is still being verified. Please do not pay again."
    elif attempt["status"] == "failed":
        msg = "Payment was not completed. You may retry."
    else:
        msg = "Payment status could not be confirmed yet. Please check again shortly."

    return VerifyCheckoutResponse(
        order_id=order["public_order_number"],
        attempt_id=attempt["public_attempt_number"],
        order_status=order["status"],
        registration_status=reg_status,
        payment_confirmed=confirmed,
        safe_message=msg,
    )


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
           OR (entity_type = 'payment_refund' AND entity_id IN (
                SELECT id FROM payment_refunds WHERE payment_order_id = $1
           ))
        ORDER BY created_at ASC
        """,
        order_id,
        [a["id"] for a in attempts],
    )


def _cancellation_and_refund_entries(
    registration: Optional[asyncpg.Record], refunds: List[asyncpg.Record]
) -> List[TimelineEntry]:
    """Attendee timeline entries for what happened AFTER the payment:
    registration cancellation and the refund lifecycle.

    Built from the authoritative state rows (registrations.cancelled_at,
    payment_refunds.requested_at / updated_at / finalized_at), not from
    event_audit_log: audit emission is best-effort, the paid cancellation
    path never emitted a cancellation row, and a refund settled by a later
    status refresh emits none. An event whose timestamp column is NULL is
    omitted — no time is ever invented for it."""
    entries: List[TimelineEntry] = []

    def add(event_type: str, entity_type: str, label: str, at: Optional[datetime]) -> None:
        if at is not None:
            entries.append(TimelineEntry(event_type=event_type, entity_type=entity_type, at=at, label=label))

    if registration and registration["status"] == "cancelled":
        add("registration_cancelled", "registration", "Registration cancelled", registration["cancelled_at"])

    for refund in refunds:
        add("refund_requested", "payment_refund", "Refund requested", refund["requested_at"])
        status = refund["status"]
        if status == "processing":
            # updated_at is only ever written by RefundRepository.mark, so on
            # a 'processing' row it is the moment the provider accepted the
            # refund. Once the refund settles that moment is overwritten, so
            # a processed/failed refund shows no "processing" step.
            add("refund_processing", "payment_refund", "Refund processing", refund["updated_at"])
        elif status == "processed":
            add(
                "refund_processed", "payment_refund", "Refund processed",
                refund["finalized_at"] or refund["updated_at"],
            )
        elif status == "failed":
            add(
                "refund_failed", "payment_refund", "Refund failed",
                refund["finalized_at"] or refund["updated_at"],
            )
    return entries


async def get_timeline(public_order_number: str, user: Dict[str, Any]) -> PaymentTimelineResponse:
    """Attendee-safe view: friendly labels only, internal technical events
    (webhook signature/replay/mismatch rejections, stale-attempt no-ops)
    excluded, and no raw internal integer order/attempt IDs in `detail`.
    History is append-only: a later cancellation / refund is added after
    "Registration confirmed", never rewrites it."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        order = await _load_order_for_user(conn, public_order_number, user["firebase_uid"])
        audit_rows = await _fetch_audit_rows(conn, order["id"])
        registration = await RegistrationRepository(conn).get_by_id(order["registration_id"])
        refunds = await RefundRepository(conn).list_for_order(order["id"])

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
    entries.extend(_cancellation_and_refund_entries(registration, refunds))
    # Stable sort: entries sharing a timestamp (cancellation and refund
    # request are written in one transaction) keep the order built above.
    entries.sort(key=lambda entry: entry.at)
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

        # Real-gateway path: query authoritative provider status and apply it
        # through the shared state machine. Covers "manual Check Status",
        # browser-callback-before-webhook, and missed/late webhook recovery.
        gw = _gateway_for_order(order)
        if (
            gw is not None
            and GatewayCapability.QUERY_PAYMENT_STATUS in gw.capabilities
            # failed / cancelled too: only a provider-confirmed capture can
            # still change those (see _outcome_applies).
            and attempt["status"] in ("initiated", "pending") + _CAPTURE_RECOVERABLE_STATUSES
            and attempt["gateway_order_ref"]
        ):
            try:
                remote = gw.query_payment_status(
                    attempt["gateway_order_ref"], payment_mode=_payment_mode_of(order)
                )
            except GatewayError:
                _log.warning("[payments] query_payment_status failed for attempt %s", attempt["id"])
                remote = None
            if remote is not None and remote.no_payment and attempt["status"] == "initiated":
                # The provider holds no payment at all for this order — the
                # attendee closed hosted checkout without paying. Nothing is
                # in flight, so leave the attempt 'initiated' (registration
                # untouched) and Pay reopens the same checkout through
                # create_attempt's reuse path. Anything already 'pending' /
                # 'requires_verification' is left exactly as before.
                remote = None
            if remote is not None and remote.status in (
                NormalizedStatus.PAYMENT_SUCCESS,
                NormalizedStatus.PAYMENT_FAILED,
                NormalizedStatus.PAYMENT_PENDING,
            ) and _outcome_applies(attempt["status"], remote.status):
                amount_ok = (
                    str(remote.currency) == attempt["currency"]
                    and Decimal(remote.amount_raw) == Decimal(attempt["amount"])
                )
                if amount_ok or remote.status != NormalizedStatus.PAYMENT_SUCCESS:
                    async def _noop(_s: str, _e: Optional[str] = None) -> None:
                        return None

                    await _apply_gateway_outcome(
                        conn, attempt=attempt, order=order, event=remote, mark_processed=_noop,
                    )
                    attempt = await pay_repo.get_attempt_by_id(attempt["id"])
                elif remote.status == NormalizedStatus.PAYMENT_SUCCESS and not amount_ok:
                    await audit_service.emit(
                        actor_uid="system", event_type="payment_verification_amount_mismatch",
                        entity_type="payment_attempt", entity_id=attempt["id"],
                        context={"order_id": order["id"]},
                    )
            await pay_repo.record_verification_check(attempt["id"])
            attempt = await pay_repo.get_attempt_by_id(attempt["id"])
            await audit_service.emit(
                actor_uid=firebase_uid, event_type="payment_verification_checked",
                entity_type="payment_attempt", entity_id=attempt["id"],
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
                payment_mode=_payment_mode_of(order),
                real_money=_payment_mode_of(order) == "live",
            )

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
        payment_mode=_payment_mode_of(order),
        real_money=_payment_mode_of(order) == "live",
    )
