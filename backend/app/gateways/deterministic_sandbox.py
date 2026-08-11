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
import uuid
from decimal import Decimal
from typing import Any, Dict, Tuple

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
