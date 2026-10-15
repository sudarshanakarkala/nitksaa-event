"""Razorpay gateway adapter.

Talks to Razorpay through the official Python SDK (razorpay==2.0.1,
razorpay.Client). Only four SDK resource calls are used — order.create,
order.payments, payment.refund, refund.fetch — plus the SDK's signature
utilities. The SDK is reached only through _build_client, which is also the
offline test seam (tests/_razorpay_fakes.py).

Design rules honoured here:
 - No branching on "razorpay" anywhere in payment_service — this adapter is
   reached only through app.gateways.registry, and everything it returns is
   already normalized (NormalizedStatus / NormalizedRefundStatus).
 - Amounts crossing this boundary are converted here and only here:
   Decimal rupees  <->  integer paise. The domain keeps working in rupees.
 - Secrets (key_secret, webhook_secret) are read from settings inside method
   bodies and never returned, logged, or put in an exception message.
 - Fail closed: if credentials are absent, is_enabled() is False, so
   payment_service raises payment_gateway_unavailable rather than calling out.
"""
from __future__ import annotations

import json
import secrets
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Callable, Dict, FrozenSet, Optional

import razorpay
import requests
from razorpay.errors import BadRequestError, ServerError, SignatureVerificationError
from razorpay.errors import GatewayError as RazorpaySdkGatewayError

from app.gateways.base import (
    GatewayCapability,
    GatewayCapabilityNotSupportedError,
    GatewayCheckout,
    GatewayError,
    GatewayInitiationResult,
    GatewayRefundRefusedError,
    GatewayWebhookUnparseableError,
    NormalizedGatewayEvent,
    NormalizedRefundResult,
    NormalizedRefundStatus,
    NormalizedStatus,
    PaymentDetails,
    PaymentGateway,
    RefundFailureReason,
)

GATEWAY_NAME = "razorpay"

_TWO_PLACES = Decimal("0.01")

# Every order id Razorpay mints starts with this; our own pre-creation
# placeholder (create_gateway_order_ref) never does.
_RAZORPAY_ORDER_ID_PREFIX = "order_"

# Razorpay payment.status -> normalized. 'authorized' means the customer paid
# but the amount is not captured yet — for our auto-capture orders this is a
# transient pre-capture state, mapped to PENDING so the seat is protected
# while capture completes.
_PAYMENT_STATUS_MAP = {
    "captured": NormalizedStatus.PAYMENT_SUCCESS,
    "authorized": NormalizedStatus.PAYMENT_PENDING,
    "created": NormalizedStatus.PAYMENT_PENDING,
    "pending": NormalizedStatus.PAYMENT_PENDING,
    "failed": NormalizedStatus.PAYMENT_FAILED,
    "refunded": NormalizedStatus.PAYMENT_SUCCESS,  # was captured, later refunded
}

# Razorpay webhook `event` -> normalized. Only the events we subscribe to.
_WEBHOOK_EVENT_MAP = {
    "payment.captured": NormalizedStatus.PAYMENT_SUCCESS,
    "order.paid": NormalizedStatus.PAYMENT_SUCCESS,
    "payment.failed": NormalizedStatus.PAYMENT_FAILED,
    "payment.authorized": NormalizedStatus.PAYMENT_PENDING,
}

_REFUND_STATUS_MAP = {
    "processed": NormalizedRefundStatus.REFUND_PROCESSED,
    "pending": NormalizedRefundStatus.REFUND_PENDING,
    "created": NormalizedRefundStatus.REFUND_PENDING,
    "failed": NormalizedRefundStatus.REFUND_FAILED,
}

# Razorpay refund webhook `event` -> refund status, used when the refund
# entity in the body has no status of its own.
_REFUND_EVENT_STATUS = {
    "refund.created": "pending",
    "refund.processed": "processed",
    "refund.failed": "failed",
}


def _int_or_none(v: Any) -> Optional[int]:
    try:
        return int(v) if v is not None else None
    except (TypeError, ValueError):
        return None


def _payment_details(payment: Dict[str, Any]) -> Optional[PaymentDetails]:
    """Razorpay payment entity -> provider-neutral details. Deliberately
    leaves out personal data the entity carries (email, contact, vpa, card)."""
    if not payment:
        return None
    acquirer = payment.get("acquirer_data") if isinstance(payment.get("acquirer_data"), dict) else {}
    bank_ref = (acquirer.get("rrn") or acquirer.get("bank_transaction_id")
                or acquirer.get("upi_transaction_id") or None)
    details = PaymentDetails(
        method=payment.get("method") or None,
        instrument=payment.get("bank") or payment.get("wallet") or None,
        international=payment.get("international") if isinstance(payment.get("international"), bool) else None,
        fee_minor=_int_or_none(payment.get("fee")),
        tax_minor=_int_or_none(payment.get("tax")),
        failure_source=payment.get("error_source") or None,
        failure_step=payment.get("error_step") or None,
        failure_reason=payment.get("error_reason") or None,
        bank_reference=str(bank_ref) if bank_ref else None,
    )
    return details if details != PaymentDetails() else None


class RazorpayModeCredentialError(GatewayError):
    """Fail-closed guard: `payment_mode` was missing/invalid or differs from
    the deployment's RAZORPAY_MODE, the active credentials are unconfigured,
    or the key_id doesn't carry the mode's rzp_test_/rzp_live_ prefix.
    Raised instead of using the active credentials for the wrong mode — see
    app/config.py Settings.razorpay_credential_problem."""

    def __init__(self, payment_mode: Optional[str], reason: str):
        self.payment_mode = payment_mode
        super().__init__(f"razorpay {payment_mode!r} credentials {reason}")


class RazorpayApiError(GatewayError):
    """A Razorpay SDK call failed (provider error, network, timeout,
    unreadable response). The message carries only the operation name and a
    fixed code — never secrets, response bodies, or SDK exception text."""

    def __init__(self, operation: str, status_code: Optional[int] = None, code: str = ""):
        self.operation = operation
        self.status_code = status_code
        self.code = code
        super().__init__(
            f"razorpay {operation} failed"
            + (f" (http {status_code})" if status_code is not None else "")
            + (f" [{code}]" if code else "")
        )


def rupees_to_paise(amount: Decimal) -> int:
    """Exact Decimal-rupees -> integer-paise. ₹1.00 -> 100."""
    q = Decimal(amount).quantize(_TWO_PLACES, rounding=ROUND_HALF_UP)
    return int((q * 100).to_integral_value(rounding=ROUND_HALF_UP))


def paise_to_rupees_str(paise: Any) -> str:
    """Integer-paise -> canonical rupees string for the domain's Decimal
    amount comparison (attempt.amount is NUMERIC(14,2) rupees)."""
    return str((Decimal(int(paise)) / Decimal(100)).quantize(_TWO_PLACES))


def _sdk_base_url(api_base: str) -> str:
    """RAZORPAY_API_BASE names the REST root including /v1 (documented value
    https://api.razorpay.com/v1). razorpay.Client's base_url is the host
    root — every SDK resource path already starts with /v1 — so a trailing
    /v1 is dropped here rather than requested twice."""
    base = api_base.rstrip("/")
    return base[: -len("/v1")] if base.endswith("/v1") else base


# Razorpay refund error text -> plain reason. Matched on lowercased text;
# only the classification survives, never the text itself.
_REFUND_ERROR_PATTERNS = (
    (("balance",), RefundFailureReason.INSUFFICIENT_BALANCE),
    (("older than", "6 months", "six months", "too old"), RefundFailureReason.PAYMENT_TOO_OLD),
    (("fully refunded", "already been refunded", "already refunded"), RefundFailureReason.ALREADY_REFUNDED),
    (("greater than", "exceed", "more than the", "invalid amount"), RefundFailureReason.AMOUNT_NOT_ALLOWED),
    (("not been captured", "not captured", "only captured"), RefundFailureReason.PAYMENT_NOT_CAPTURED),
)


def _classify_refund_error(code: str, text: str) -> RefundFailureReason:
    if code in ("SERVER_ERROR", "GATEWAY_ERROR", "TIMEOUT", "TRANSPORT_ERROR", "UNEXPECTED_RESPONSE"):
        return RefundFailureReason.PROVIDER_UNAVAILABLE
    lowered = (text or "").lower()
    for needles, reason in _REFUND_ERROR_PATTERNS:
        if any(n in lowered for n in needles):
            return reason
    return RefundFailureReason.DECLINED


class RazorpayRefundRefusedError(RazorpayApiError, GatewayRefundRefusedError):
    """payments.refund refused, with the reason classified. Same safe message
    as RazorpayApiError (operation + fixed code), never the provider text."""

    def __init__(self, code: str, reason: RefundFailureReason):
        # Set the fields directly: with two error bases, RazorpayApiError's
        # super().__init__ would land in GatewayRefundRefusedError.__init__
        # with the message in place of the reason.
        self.operation = "payments.refund"
        self.status_code = None
        self.code = code
        self.reason = reason
        GatewayError.__init__(self, f"razorpay payments.refund failed [{code}]")


def _call(operation: str, fn: Callable[..., Any], *args: Any, **kwargs: Any) -> Dict[str, Any]:
    """Run one SDK resource call; translate every provider/transport failure
    into RazorpayApiError with a fixed code. The SDK's own exception text
    (provider description, request URL) is deliberately dropped, and the
    error is raised outside the except block so it isn't chained into
    logged tracebacks either."""
    failure: Optional[str] = None
    refusal: Optional[RefundFailureReason] = None
    try:
        result = fn(*args, **kwargs)
    except BadRequestError as exc:
        failure = "BAD_REQUEST_ERROR"
        if operation == "payments.refund":
            # Classify now, inside the handler; the text itself is dropped.
            refusal = _classify_refund_error(failure, str(exc))
    except RazorpaySdkGatewayError:
        failure = "GATEWAY_ERROR"
    except ServerError:
        failure = "SERVER_ERROR"
    except requests.exceptions.Timeout:
        failure = "TIMEOUT"
    except (requests.exceptions.RequestException, ValueError):
        # connection/TLS failures and non-JSON responses
        failure = "TRANSPORT_ERROR"
    if failure is not None:
        if operation == "payments.refund":
            raise RazorpayRefundRefusedError(
                failure, refusal or _classify_refund_error(failure, ""))
        raise RazorpayApiError(operation, code=failure)
    if not isinstance(result, dict):  # the SDK returns '{}' (a str) for a 204
        raise RazorpayApiError(operation, code="UNEXPECTED_RESPONSE")
    return result


def _resolve_credentials(settings: Any, payment_mode: Optional[str]) -> tuple[str, str, str]:
    """(key_id, key_secret, webhook_secret) for `payment_mode`, fail-closed.
    Returns the deployment's active credentials only when `payment_mode`
    equals RAZORPAY_MODE — this is the single choke point every Razorpay
    call goes through."""
    problem = settings.razorpay_credential_problem(payment_mode)
    if problem is not None:
        raise RazorpayModeCredentialError(payment_mode, problem)
    return settings.razorpay_credentials_for(payment_mode)


def _build_client(settings: Any, payment_mode: Optional[str]) -> razorpay.Client:
    """Overridable seam for tests (monkeypatch this to inject a fake). The
    only place a razorpay.Client is created, and only ever with credentials
    _resolve_credentials returned for `payment_mode`. SDK retries stay
    disabled (its default): one attempt per call."""
    key_id, key_secret, _ = _resolve_credentials(settings, payment_mode)
    return razorpay.Client(
        auth=(key_id, key_secret), base_url=_sdk_base_url(settings.razorpay_api_base)
    )


class RazorpayGateway(PaymentGateway):
    name = GATEWAY_NAME
    capabilities: FrozenSet[GatewayCapability] = frozenset(
        {
            GatewayCapability.CREATE_PAYMENT,
            GatewayCapability.VERIFY_PAYMENT,       # checkout-return signature (first gate only)
            GatewayCapability.VERIFY_WEBHOOK,
            GatewayCapability.PROCESS_WEBHOOK,
            GatewayCapability.QUERY_PAYMENT_STATUS,
            GatewayCapability.REFUND,
            GatewayCapability.QUERY_REFUND,
        }
    )
    # Razorpay determines its own outcome — the caller cannot pick one.
    supported_scenarios: FrozenSet[str] = frozenset()

    def is_enabled(self, settings: Any) -> bool:
        # Fail closed: usable only if the deployment's active credential set
        # is valid for its own RAZORPAY_MODE. Whether a specific payment_mode
        # may use it is checked per call in _resolve_credentials — this is
        # only the coarse "is Razorpay reachable at all" gate the registry
        # checks before a mode is even known (e.g. the webhook route's
        # {gateway} segment).
        return settings.razorpay_configured

    # ── initiation ────────────────────────────────────────────────────────

    def create_gateway_order_ref(self) -> str:
        # Placeholder only. The real reference is the Razorpay order id
        # returned by create_payment(); payment_service persists whatever
        # GatewayInitiationResult.gateway_order_ref carries.
        return f"rzp_pending_{secrets.token_urlsafe(9)}"

    def create_payment(
        self,
        *,
        gateway_order_ref: str,
        amount: Decimal,
        currency: str,
        scenario: Optional[str] = None,
        payment_mode: Optional[str] = None,
    ) -> GatewayInitiationResult:
        if currency != "INR":
            raise GatewayError("razorpay adapter supports INR only")
        from app.config import get_settings

        settings = get_settings()
        amount_minor = rupees_to_paise(amount)
        key_id, _, _ = _resolve_credentials(settings, payment_mode)
        client = _build_client(settings, payment_mode)
        body = {
            "amount": amount_minor,
            "currency": "INR",
            "receipt": gateway_order_ref[:40],
            "payment_capture": 1,
            "notes": {"source": "nitksaa-event"},
        }
        order = _call(
            "orders.create", client.order.create,
            data=body, timeout=settings.razorpay_http_timeout_seconds,
        )
        provider_order_id = order.get("id")
        if not provider_order_id:
            raise RazorpayApiError("orders.create")
        return GatewayInitiationResult(
            gateway_order_ref=provider_order_id,
            checkout=GatewayCheckout(
                provider_order_id=provider_order_id,
                key_id=key_id,
                amount_minor=amount_minor,
                currency="INR",
            ),
        )

    def rebuild_checkout(
        self,
        *,
        gateway_order_ref: str,
        amount: Decimal,
        currency: str,
        payment_mode: Optional[str] = None,
    ) -> Optional[GatewayCheckout]:
        # Only a real Razorpay order id (order_...) can be reopened — the
        # rzp_pending_ placeholder means order.create never returned (or is
        # still in flight), so there is no provider order to hand out.
        if not gateway_order_ref or not gateway_order_ref.startswith(_RAZORPAY_ORDER_ID_PREFIX):
            return None
        if currency != "INR":
            raise GatewayError("razorpay adapter supports INR only")
        from app.config import get_settings

        # Same fail-closed mode/credential/prefix rules as create_payment; no
        # Razorpay call is made.
        key_id, _, _ = _resolve_credentials(get_settings(), payment_mode)
        return GatewayCheckout(
            provider_order_id=gateway_order_ref,
            key_id=key_id,
            amount_minor=rupees_to_paise(amount),
            currency="INR",
        )

    # ── checkout return (first gate) ──────────────────────────────────────

    def verify_checkout_signature(
        self,
        *,
        provider_order_id: str,
        provider_payment_id: str,
        signature: str,
        payment_mode: Optional[str] = None,
    ) -> bool:
        from app.config import get_settings

        if not signature:
            return False
        try:
            # The SDK signs with client.auth[1] — the key_secret that
            # _resolve_credentials returned for this payment_mode.
            client = _build_client(get_settings(), payment_mode)
        except RazorpayModeCredentialError:
            return False
        try:
            return client.utility.verify_payment_signature({
                "razorpay_order_id": provider_order_id,
                "razorpay_payment_id": provider_payment_id,
                "razorpay_signature": signature,
            }) is True
        except (SignatureVerificationError, TypeError, ValueError):
            # TypeError: hmac.compare_digest rejects a non-ASCII signature —
            # client-supplied input, so it is a mismatch, never a 500.
            return False

    # ── authoritative status ─────────────────────────────────────────────

    def query_payment_status(
        self, gateway_order_ref: str, *, payment_mode: Optional[str] = None
    ) -> NormalizedGatewayEvent:
        from app.config import get_settings

        settings = get_settings()
        client = _build_client(settings, payment_mode)
        data = _call(
            "orders.payments", client.order.payments,
            gateway_order_ref, timeout=settings.razorpay_http_timeout_seconds,
        )
        items = data.get("items") or []
        if not items:
            return NormalizedGatewayEvent(
                event_id=f"query:{gateway_order_ref}:empty",
                status=NormalizedStatus.PAYMENT_PENDING,
                gateway_order_ref=gateway_order_ref,
                amount_raw="0",
                currency="INR",
                raw_event_type="orders.payments:empty",
                no_payment=True,
            )
        # Prefer a captured payment; else the most recent.
        payment = next((p for p in items if p.get("status") == "captured"), items[0])
        return self._payment_to_event(payment, gateway_order_ref, source="query")

    def _payment_to_event(
        self, payment: Dict[str, Any], gateway_order_ref: str, *, source: str
    ) -> NormalizedGatewayEvent:
        raw_status = payment.get("status", "")
        return NormalizedGatewayEvent(
            event_id=f"{source}:{payment.get('id', '')}:{raw_status}",
            status=_PAYMENT_STATUS_MAP.get(raw_status, NormalizedStatus.UNKNOWN),
            gateway_order_ref=gateway_order_ref or payment.get("order_id", ""),
            amount_raw=paise_to_rupees_str(payment.get("amount", 0)),
            currency=payment.get("currency", "INR"),
            raw_event_type=f"payment.{raw_status}",
            gateway_payment_ref=payment.get("id", ""),
            failure_code=payment.get("error_code") or "UNKNOWN",
            failure_message=payment.get("error_description") or "Payment failed",
            details=_payment_details(payment),
        )

    # ── webhook ──────────────────────────────────────────────────────────

    def verify_webhook(
        self, raw_body: bytes, signature: str, *, payment_mode: Optional[str] = None
    ) -> bool:
        from app.config import get_settings

        settings = get_settings()
        try:
            _, _, secret = _resolve_credentials(settings, payment_mode)
            client = _build_client(settings, payment_mode)
        except RazorpayModeCredentialError:
            return False
        if not secret or not signature:
            return False
        try:
            # razorpay==2.0.1 HMACs bytes(body, "utf-8"), so it takes str. A
            # strict UTF-8 decode round-trips to the exact signed bytes; a
            # body that isn't valid UTF-8 can't be a Razorpay delivery.
            body = raw_body.decode("utf-8")
            return client.utility.verify_webhook_signature(body, signature, secret) is True
        except (SignatureVerificationError, TypeError, ValueError):
            # ValueError covers UnicodeDecodeError; TypeError a non-ASCII
            # signature header (hmac.compare_digest) — reject, never a 500.
            return False

    def parse_webhook(self, raw_body: bytes) -> NormalizedGatewayEvent:
        try:
            payload: Dict[str, Any] = json.loads(raw_body)
        except (ValueError, TypeError) as exc:
            raise GatewayWebhookUnparseableError(str(exc)) from exc

        event_type = payload.get("event", "")
        p = payload.get("payload", {}) or {}
        payment_entity = ((p.get("payment") or {}).get("entity")) or {}
        order_entity = ((p.get("order") or {}).get("entity")) or {}
        refund_entity = ((p.get("refund") or {}).get("entity")) or {}

        if event_type.startswith("refund.") and refund_entity:
            # Refund outcome (refund.created / processed / failed). Never
            # drives the payment state machine (status UNKNOWN); the refund
            # domain applies `refund`.
            if not refund_entity.get("status"):
                refund_entity = {**refund_entity, "status": _REFUND_EVENT_STATUS.get(event_type, "")}
            refund = self._refund_to_result(refund_entity)
            return NormalizedGatewayEvent(
                event_id=f"{event_type}:{refund_entity.get('id', '')}",
                status=NormalizedStatus.UNKNOWN,
                raw_event_type=event_type,
                gateway_order_ref=payment_entity.get("order_id") or "",
                amount_raw=paise_to_rupees_str(refund_entity.get("amount", 0)),
                currency=refund_entity.get("currency") or "INR",
                issued_at_raw=payload.get("created_at"),
                gateway_payment_ref=refund.provider_payment_id,
                refund=refund,
            )

        gateway_order_ref = payment_entity.get("order_id") or order_entity.get("id") or ""
        amount = payment_entity.get("amount", order_entity.get("amount_paid", 0))
        currency = payment_entity.get("currency") or order_entity.get("currency") or "INR"

        # Dedupe id: prefer the payment/order entity id + event, which is in
        # the SIGNED body (the X-Razorpay-Event-Id header is passed
        # separately by the route and wins when present — see
        # payment_service.process_webhook `provider_event_id`).
        entity_id = payment_entity.get("id") or order_entity.get("id") or ""
        body_event_id = f"{event_type}:{entity_id}" if entity_id else event_type

        return NormalizedGatewayEvent(
            event_id=body_event_id,
            status=_WEBHOOK_EVENT_MAP.get(event_type, NormalizedStatus.UNKNOWN),
            raw_event_type=event_type,
            gateway_order_ref=gateway_order_ref,
            amount_raw=paise_to_rupees_str(amount),
            currency=currency,
            issued_at_raw=payload.get("created_at"),
            gateway_payment_ref=payment_entity.get("id", ""),
            failure_code=payment_entity.get("error_code") or "UNKNOWN",
            failure_message=payment_entity.get("error_description") or "Payment failed",
            details=_payment_details(payment_entity),
        )

    # ── refunds ──────────────────────────────────────────────────────────

    def refund(
        self,
        *,
        provider_payment_id: str,
        amount_minor: int,
        currency: str,
        idempotency_key: str,
        payment_mode: Optional[str] = None,
        refund_number: Optional[str] = None,
    ) -> NormalizedRefundResult:
        from app.config import get_settings

        if currency != "INR":
            raise GatewayError("razorpay adapter supports INR only")
        # payment_mode must be the mode the original payment was captured
        # under (refund_service snapshots it onto the refund row) — resolving
        # credentials here means a live payment can only ever be refunded
        # with live credentials, and vice versa; never a cross-mode fallback.
        settings = get_settings()
        client = _build_client(settings, payment_mode)
        # payment.refund forwards **kwargs through Client.post to requests,
        # so the Idempotency-Key header reaches the HTTP request unchanged.
        data = _call(
            "payments.refund", client.payment.refund,
            provider_payment_id,
            data={"amount": int(amount_minor), "speed": "normal",
                  "notes": {"reason": "attendee_cancellation",
                            **({"refund_number": refund_number} if refund_number else {})}},
            headers={"Idempotency-Key": idempotency_key},
            timeout=settings.razorpay_http_timeout_seconds,
        )
        return self._refund_to_result(data)

    def query_refund(
        self,
        *,
        provider_payment_id: str,
        provider_refund_id: str,
        payment_mode: Optional[str] = None,
    ) -> NormalizedRefundResult:
        from app.config import get_settings

        settings = get_settings()
        client = _build_client(settings, payment_mode)
        data = _call(
            "refunds.fetch", client.refund.fetch,
            provider_refund_id, timeout=settings.razorpay_http_timeout_seconds,
        )
        return self._refund_to_result(data)

    def list_refunds(
        self, *, provider_payment_id: str, payment_mode: Optional[str] = None
    ) -> list:
        """Every refund the provider holds for a payment (ours or made in
        the dashboard), so a retry never refunds twice."""
        from app.config import get_settings

        settings = get_settings()
        client = _build_client(settings, payment_mode)
        data = _call(
            "payments.refunds", client.payment.fetch_multiple_refund,
            provider_payment_id, timeout=settings.razorpay_http_timeout_seconds,
        )
        return [self._refund_to_result(item) for item in (data.get("items") or [])]

    @staticmethod
    def _refund_to_result(data: Dict[str, Any]) -> NormalizedRefundResult:
        raw = data.get("status", "")
        return NormalizedRefundResult(
            provider_refund_id=data.get("id", ""),
            status=_REFUND_STATUS_MAP.get(raw, NormalizedRefundStatus.UNKNOWN),
            amount_minor=int(data.get("amount", 0) or 0),
            currency=data.get("currency", "INR"),
            raw_status=raw,
            failure_reason=(data.get("notes") or {}).get("failure_reason")
            if isinstance(data.get("notes"), dict) else None,
            bank_reference=(acquirer.get("arn") or acquirer.get("rrn") or acquirer.get("utr") or None)
            if isinstance(acquirer := data.get("acquirer_data"), dict) else None,
            speed_processed=data.get("speed_processed") or None,
            provider_payment_id=data.get("payment_id") or "",
            refund_number=(data.get("notes") or {}).get("refund_number")
            if isinstance(data.get("notes"), dict) else None,
        )


__all__ = [
    "RazorpayGateway",
    "RazorpayApiError",
    "RazorpayModeCredentialError",
    "GATEWAY_NAME",
    "rupees_to_paise",
    "paise_to_rupees_str",
    "_build_client",
]
