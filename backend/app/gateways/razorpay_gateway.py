"""Razorpay gateway adapter (Test Mode slice).

Talks to the Razorpay REST API (https://api.razorpay.com/v1) over HTTPS with
HTTP Basic auth (key_id:key_secret). The `razorpay` PyPI SDK is intentionally
NOT used: it is a thin wrapper over the six REST calls below, pulls in an
extra `requests` dependency, and is not present in this repo's locked venv —
a small httpx client (httpx is already a dependency) is fully offline-testable
and keeps the surface auditable. See the sprint report §6.

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

import hashlib
import hmac
import json
import secrets
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Dict, FrozenSet, Optional

import httpx

from app.gateways.base import (
    GatewayCapability,
    GatewayCapabilityNotSupportedError,
    GatewayCheckout,
    GatewayError,
    GatewayInitiationResult,
    GatewayWebhookUnparseableError,
    NormalizedGatewayEvent,
    NormalizedRefundResult,
    NormalizedRefundStatus,
    NormalizedStatus,
    PaymentGateway,
)

GATEWAY_NAME = "razorpay"

_TWO_PLACES = Decimal("0.01")

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


_KEY_PREFIX = {"test": "rzp_test_", "live": "rzp_live_"}


class RazorpayModeCredentialError(GatewayError):
    """Fail-closed guard: `payment_mode` was missing/invalid, the
    corresponding credential profile is unconfigured, or the configured
    key_id doesn't carry that mode's expected rzp_test_/rzp_live_ prefix.
    Raised instead of silently using the other mode's credentials or an
    unprefixed key — see app/config.py Settings.razorpay_credentials_for."""

    def __init__(self, payment_mode: Optional[str], reason: str):
        self.payment_mode = payment_mode
        super().__init__(f"razorpay {payment_mode!r} credentials {reason}")


class RazorpayApiError(GatewayError):
    """A Razorpay REST call returned a non-2xx status or could not be reached.
    The message is deliberately generic — no secrets, no full response body."""

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


class _RazorpayClient:
    """Minimal synchronous REST client. One instance per call site is fine;
    httpx.Client is created and closed per request to stay dependency-free of
    any app lifecycle."""

    def __init__(self, *, key_id: str, key_secret: str, api_base: str, timeout: float):
        self._auth = (key_id, key_secret)
        self._base = api_base.rstrip("/")
        self._timeout = timeout

    def request(
        self, method: str, path: str, *, json_body: Optional[Dict[str, Any]] = None,
        headers: Optional[Dict[str, str]] = None, operation: str = "",
    ) -> Dict[str, Any]:
        url = f"{self._base}/{path.lstrip('/')}"
        try:
            resp = httpx.request(
                method, url, auth=self._auth, json=json_body,
                headers=headers or {}, timeout=self._timeout,
            )
        except httpx.HTTPError as exc:  # network / timeout — no secrets in str(exc) for our URLs
            raise RazorpayApiError(operation or f"{method} {path}") from exc
        if resp.status_code // 100 != 2:
            code = ""
            try:
                code = (resp.json().get("error", {}) or {}).get("code", "") or ""
            except Exception:
                pass
            raise RazorpayApiError(operation or f"{method} {path}", resp.status_code, code)
        try:
            return resp.json()
        except Exception as exc:
            raise RazorpayApiError(operation or f"{method} {path}", resp.status_code) from exc


def _resolve_credentials(settings: Any, payment_mode: Optional[str]) -> tuple[str, str, str]:
    """(key_id, key_secret, webhook_secret) for `payment_mode`, fail-closed.
    Never returns credentials from a mode other than the one requested —
    this is the single choke point every Razorpay call goes through."""
    if payment_mode not in ("test", "live"):
        raise RazorpayModeCredentialError(payment_mode, "payment_mode must be 'test' or 'live'")
    key_id, key_secret, webhook_secret = settings.razorpay_credentials_for(payment_mode)
    if not key_id or not key_secret:
        raise RazorpayModeCredentialError(payment_mode, "are not configured")
    expected_prefix = _KEY_PREFIX[payment_mode]
    if not key_id.startswith(expected_prefix):
        raise RazorpayModeCredentialError(
            payment_mode, f"key_id does not start with {expected_prefix!r}"
        )
    return key_id, key_secret, webhook_secret


def _build_client(settings: Any, payment_mode: Optional[str]) -> _RazorpayClient:
    """Overridable seam for tests (monkeypatch this to inject a fake)."""
    key_id, key_secret, _ = _resolve_credentials(settings, payment_mode)
    return _RazorpayClient(
        key_id=key_id,
        key_secret=key_secret,
        api_base=settings.razorpay_api_base,
        timeout=settings.razorpay_http_timeout_seconds,
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
        # Fail closed: usable only if at least one credential profile
        # (TEST or LIVE) is actually configured. Per-call mode resolution
        # (which profile, and the rzp_test_/rzp_live_ prefix check) happens
        # in _resolve_credentials for the specific payment_mode in play —
        # this is only the coarse "is Razorpay reachable at all" gate the
        # registry checks before a mode is even known (e.g. the webhook
        # route's {gateway} segment).
        test_key_id, test_key_secret, _ = settings.razorpay_credentials_for("test")
        live_key_id, live_key_secret, _ = settings.razorpay_credentials_for("live")
        return bool((test_key_id and test_key_secret) or (live_key_id and live_key_secret))

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
        order = client.request("POST", "/orders", json_body=body, operation="orders.create")
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

        try:
            _, secret, _ = _resolve_credentials(get_settings(), payment_mode)
        except RazorpayModeCredentialError:
            return False
        if not secret or not signature:
            return False
        expected = hmac.new(
            secret.encode("utf-8"),
            f"{provider_order_id}|{provider_payment_id}".encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    # ── authoritative status ─────────────────────────────────────────────

    def query_payment_status(
        self, gateway_order_ref: str, *, payment_mode: Optional[str] = None
    ) -> NormalizedGatewayEvent:
        from app.config import get_settings

        client = _build_client(get_settings(), payment_mode)
        data = client.request(
            "GET", f"/orders/{gateway_order_ref}/payments", operation="orders.payments"
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
        )

    # ── webhook ──────────────────────────────────────────────────────────

    def verify_webhook(
        self, raw_body: bytes, signature: str, *, payment_mode: Optional[str] = None
    ) -> bool:
        from app.config import get_settings

        try:
            _, _, secret = _resolve_credentials(get_settings(), payment_mode)
        except RazorpayModeCredentialError:
            return False
        if not secret or not signature:
            return False
        expected = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature)

    def parse_webhook(self, raw_body: bytes) -> NormalizedGatewayEvent:
        try:
            payload: Dict[str, Any] = json.loads(raw_body)
        except (ValueError, TypeError) as exc:
            raise GatewayWebhookUnparseableError(str(exc)) from exc

        event_type = payload.get("event", "")
        p = payload.get("payload", {}) or {}
        payment_entity = ((p.get("payment") or {}).get("entity")) or {}
        order_entity = ((p.get("order") or {}).get("entity")) or {}

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
    ) -> NormalizedRefundResult:
        from app.config import get_settings

        if currency != "INR":
            raise GatewayError("razorpay adapter supports INR only")
        # payment_mode must be the mode the original payment was captured
        # under (refund_service snapshots it onto the refund row) — resolving
        # credentials here means a live payment can only ever be refunded
        # with live credentials, and vice versa; never a cross-mode fallback.
        client = _build_client(get_settings(), payment_mode)
        data = client.request(
            "POST",
            f"/payments/{provider_payment_id}/refund",
            json_body={"amount": int(amount_minor), "speed": "normal",
                       "notes": {"reason": "attendee_cancellation"}},
            headers={"Idempotency-Key": idempotency_key},
            operation="payments.refund",
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

        client = _build_client(get_settings(), payment_mode)
        data = client.request(
            "GET", f"/refunds/{provider_refund_id}", operation="refunds.fetch"
        )
        return self._refund_to_result(data)

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
