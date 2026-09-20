"""Deterministic sandbox payment gateway — Phase 0, no real money.

Behaves like a gateway rather than a direct DB status switch: it produces a
signed webhook payload and that payload is run through the same
signature-verification + processing path payment_service uses for a real
gateway's HTTP webhook (app.api.payments.receive_webhook). The only shortcut
versus a real gateway is transport — the payload is delivered via an in-process
function call (or a short asyncio delay for the DELAYED_* scenarios) instead of
an outbound HTTP request, since there is no real gateway on the other end to
call back to us.
"""
import hashlib
import hmac
import json
import secrets
import time
import uuid
from decimal import Decimal
from typing import Any, Dict, FrozenSet, Optional, Tuple

from app.gateways.base import (
    DelayedWebhookDelivery,
    GatewayCapability,
    GatewayInitiationResult,
    GatewayWebhookUnparseableError,
    NormalizedGatewayEvent,
    NormalizedRefundResult,
    NormalizedRefundStatus,
    NormalizedStatus,
    PaymentGateway,
    SignedWebhookDelivery,
)

GATEWAY_NAME = "deterministic_sandbox"

SUPPORTED_SCENARIOS = (
    "SUCCESS",
    "FAILURE",
    "PENDING",
    "CANCELLED",
    "DELAYED_SUCCESS",
    "DELAYED_FAILURE",
)

DELAYED_SCENARIO_DELAY_SECONDS = 2

_EVENT_TYPE_BY_SCENARIO = {
    "SUCCESS": "payment.captured",
    "DELAYED_SUCCESS": "payment.captured",
    "FAILURE": "payment.failed",
    "DELAYED_FAILURE": "payment.failed",
    "PENDING": "payment.pending",
    "CANCELLED": "payment.cancelled",
}


def is_delayed_scenario(scenario: str) -> bool:
    return scenario.startswith("DELAYED_")


def create_gateway_order_ref() -> str:
    return f"sbx_ord_{secrets.token_urlsafe(12)}"


def _create_gateway_payment_ref() -> str:
    return f"sbx_pay_{secrets.token_urlsafe(12)}"


def build_webhook_payload(
    gateway_order_ref: str,
    scenario: str,
    amount: Decimal,
    currency: str,
) -> Dict[str, Any]:
    if scenario not in SUPPORTED_SCENARIOS:
        raise ValueError(f"unsupported sandbox scenario: {scenario!r}")
    event_type = _EVENT_TYPE_BY_SCENARIO[scenario]
    payload: Dict[str, Any] = {
        "event_id": str(uuid.uuid4()),
        "event_type": event_type,
        "gateway": GATEWAY_NAME,
        "gateway_order_ref": gateway_order_ref,
        "amount": str(amount),
        "currency": currency,
        # UTC epoch seconds. Part of the signed body (canonicalize() sorts
        # keys and signs the whole payload), so this cannot be altered
        # post-signing without invalidating the signature — see
        # payment_service.process_webhook's freshness gate.
        "issued_at": int(time.time()),
    }
    if event_type == "payment.captured":
        payload["gateway_payment_ref"] = _create_gateway_payment_ref()
    if event_type == "payment.failed":
        payload["failure_code"] = "SANDBOX_SIMULATED_FAILURE"
        payload["failure_message"] = "Simulated failure requested by sandbox scenario"
    return payload


def canonicalize(payload: Dict[str, Any]) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sign(raw_body: bytes, secret: str) -> str:
    return hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()


def verify_signature(raw_body: bytes, signature: str, secret: str) -> bool:
    expected = sign(raw_body, secret)
    return hmac.compare_digest(expected, signature)


def payload_hash(raw_body: bytes) -> str:
    return hashlib.sha256(raw_body).hexdigest()


def build_signed_delivery(
    gateway_order_ref: str, scenario: str, amount: Decimal, currency: str, secret: str
) -> Tuple[bytes, str]:
    """Return (raw_body, signature) ready to hand to the webhook processor —
    exactly what would arrive over HTTP from a real gateway."""
    payload = build_webhook_payload(gateway_order_ref, scenario, amount, currency)
    raw_body = canonicalize(payload)
    signature = sign(raw_body, secret)
    return raw_body, signature


_STATUS_BY_EVENT_TYPE = {
    "payment.captured": NormalizedStatus.PAYMENT_SUCCESS,
    "payment.failed": NormalizedStatus.PAYMENT_FAILED,
    "payment.pending": NormalizedStatus.PAYMENT_PENDING,
    "payment.cancelled": NormalizedStatus.PAYMENT_CANCELLED,
}


class DeterministicSandboxGateway(PaymentGateway):
    """Gateway-interface adapter over the module-level functions above.

    The functions themselves are untouched (dev_diagnostics.py's security/
    scenario runner calls them directly, exercising the sandbox
    implementation itself rather than the generic dispatch path — that is
    intentional and stays as-is). This class is the only thing
    payment_service and the gateway registry are allowed to know about.
    """

    name = GATEWAY_NAME
    capabilities = frozenset(
        {
            GatewayCapability.CREATE_PAYMENT,
            GatewayCapability.PROCESS_WEBHOOK,
            GatewayCapability.VERIFY_WEBHOOK,
            # Deterministic, no-real-money refunds — added so the refund
            # domain (persistence, idempotency, concurrency, ownership,
            # state machine) is exercisable end-to-end without a real
            # provider. There is no settlement delay to simulate: a sandbox
            # refund is 'processed' the instant it is created.
            GatewayCapability.REFUND,
            GatewayCapability.QUERY_REFUND,
        }
    )
    supported_scenarios: FrozenSet[str] = frozenset(SUPPORTED_SCENARIOS)

    def is_enabled(self, settings: Any) -> bool:
        # A deterministic, no-real-money gateway must never be silently
        # reachable in a real production deployment — that would let
        # "payment" succeed without any money actually moving. Off by
        # default in production; explicit opt-in only (e.g. a demo/staging
        # environment that happens to run with APP_ENV=production).
        if settings.app_env == "production" and not settings.payment_sandbox_allow_in_production:
            return False
        return True

    def create_gateway_order_ref(self) -> str:
        return create_gateway_order_ref()

    def create_payment(
        self,
        *,
        gateway_order_ref: str,
        amount: Decimal,
        currency: str,
        scenario: Optional[str] = None,
        payment_mode: Optional[str] = None,
    ) -> GatewayInitiationResult:
        # payment_mode is a Razorpay concept (test/live credential profile);
        # the sandbox has no real credentials to select between and ignores it.
        if scenario not in SUPPORTED_SCENARIOS:
            raise ValueError(f"unsupported sandbox scenario: {scenario!r}")
        from app.config import get_settings

        secret = get_settings().payment_sandbox_signing_secret
        raw_body, signature = build_signed_delivery(gateway_order_ref, scenario, amount, currency, secret)
        if is_delayed_scenario(scenario):
            return GatewayInitiationResult(
                gateway_order_ref=gateway_order_ref,
                delayed_webhook=DelayedWebhookDelivery(raw_body, signature, DELAYED_SCENARIO_DELAY_SECONDS),
            )
        return GatewayInitiationResult(
            gateway_order_ref=gateway_order_ref,
            immediate_webhook=SignedWebhookDelivery(raw_body, signature),
        )

    def verify_webhook(
        self, raw_body: bytes, signature: str, *, payment_mode: Optional[str] = None
    ) -> bool:
        from app.config import get_settings

        secret = get_settings().payment_sandbox_signing_secret
        return verify_signature(raw_body, signature, secret)

    def refund(
        self,
        *,
        provider_payment_id: str,
        amount_minor: int,
        currency: str,
        idempotency_key: str,
        payment_mode: Optional[str] = None,
    ) -> NormalizedRefundResult:
        # No async settlement in the sandbox — a refund is processed at once.
        return NormalizedRefundResult(
            provider_refund_id=f"sbx_rfnd_{secrets.token_urlsafe(12)}",
            status=NormalizedRefundStatus.REFUND_PROCESSED,
            amount_minor=amount_minor,
            currency=currency,
            raw_status="processed",
        )

    def query_refund(
        self,
        *,
        provider_payment_id: str,
        provider_refund_id: str,
        payment_mode: Optional[str] = None,
    ) -> NormalizedRefundResult:
        return NormalizedRefundResult(
            provider_refund_id=provider_refund_id,
            status=NormalizedRefundStatus.REFUND_PROCESSED,
            amount_minor=0,
            currency="INR",
            raw_status="processed",
        )

    def parse_webhook(self, raw_body: bytes) -> NormalizedGatewayEvent:
        try:
            payload: Dict[str, Any] = json.loads(raw_body)
        except (ValueError, TypeError) as exc:
            raise GatewayWebhookUnparseableError(str(exc)) from exc
        event_type = payload.get("event_type", "")
        return NormalizedGatewayEvent(
            event_id=payload.get("event_id", ""),
            status=_STATUS_BY_EVENT_TYPE.get(event_type, NormalizedStatus.UNKNOWN),
            raw_event_type=event_type,
            gateway_order_ref=payload.get("gateway_order_ref", ""),
            amount_raw=str(payload.get("amount", "0")),
            currency=payload.get("currency"),
            issued_at_raw=payload.get("issued_at"),
            gateway_payment_ref=payload.get("gateway_payment_ref", ""),
            failure_code=payload.get("failure_code", "UNKNOWN"),
            failure_message=payload.get("failure_message", "Payment failed"),
        )
