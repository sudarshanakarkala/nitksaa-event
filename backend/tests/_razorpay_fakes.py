"""Offline, SDK-shaped fake of the razorpay.Client surface RazorpayGateway
uses (razorpay==2.0.1): order.create, order.payments, payment.refund,
refund.fetch, utility.verify_payment_signature and
utility.verify_webhook_signature.

Injected by monkeypatching app.gateways.razorpay_gateway._build_client. No
network, deterministic. `utility` is the SDK's real Utility class (pure HMAC,
no I/O), so signature tests exercise razorpay==2.0.1's own verification code.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import uuid
from typing import Any, Dict, List, Optional

from razorpay.errors import ServerError
from razorpay.utility.utility import Utility


# order_id -> {"amount": paise, "currency": "INR"}
_ORDERS: Dict[str, Dict[str, Any]] = {}
# refund_id -> refund dict
_REFUNDS: Dict[str, Dict[str, Any]] = {}
# Every SDK resource call the fake received, in order — lets tests assert the
# SDK method, arguments, timeout and headers the adapter actually used.
CALLS: List[Dict[str, Any]] = []

# Test knobs
STATE: Dict[str, Any] = {
    "payment_status": "captured",   # what order.payments reports
    "payments_amount_override": None,  # force a mismatched amount (paise)
    "refund_status": "processed",   # what payment.refund / refund.fetch report
    "refund_raises": False,         # payment.refund raises the SDK's ServerError
    "orders_create_raises": False,  # order.create raises the SDK's ServerError
    "payments_empty": False,        # order.payments returns no items
    "payment_id": None,             # fixed id for the order.payments item (else random)
    "payments_raises": False,       # order.payments raises the SDK's ServerError
    "payments_currency_override": None,  # force a mismatched currency
}

# Provider text the fake puts in SDK exceptions; must never surface.
SDK_ERROR_TEXT = "provider says card 4111-1111 for payer@example.com failed"


def reset() -> None:
    _ORDERS.clear()
    _REFUNDS.clear()
    CALLS.clear()
    STATE.update(
        payment_status="captured",
        payments_amount_override=None,
        refund_status="processed",
        refund_raises=False,
        orders_create_raises=False,
        payments_empty=False,
        payment_id=None,
        payments_raises=False,
        payments_currency_override=None,
    )


def _uid(prefix: str) -> str:
    # Globally unique — the tests run against a persistent local Postgres, so
    # predictable ids would collide with rows left by earlier runs.
    return f"{prefix}_{uuid.uuid4().hex}"


def _record(method: str, args: tuple, data: Optional[Dict[str, Any]], kwargs: Dict[str, Any]) -> None:
    CALLS.append({"method": method, "args": args, "data": data or {}, "kwargs": dict(kwargs)})


class _Order:
    def create(self, data=None, **kwargs):
        _record("order.create", (), data, kwargs)
        if STATE["orders_create_raises"]:
            raise ServerError(SDK_ERROR_TEXT)
        oid = _uid("order")
        _ORDERS[oid] = {"amount": int(data["amount"]), "currency": data.get("currency", "INR")}
        return {"id": oid, "amount": int(data["amount"]),
                "currency": data.get("currency", "INR"), "status": "created",
                "receipt": data.get("receipt", "")}

    def payments(self, order_id, data=None, **kwargs):
        _record("order.payments", (order_id,), data, kwargs)
        if STATE["payments_raises"]:
            raise ServerError(SDK_ERROR_TEXT)
        if STATE["payments_empty"]:
            return {"count": 0, "items": []}
        base = _ORDERS.get(order_id, {"amount": 100, "currency": "INR"})
        amount = STATE["payments_amount_override"] or base["amount"]
        return {"count": 1, "items": [{
            "id": STATE["payment_id"] or _uid("pay"),
            "order_id": order_id,
            "amount": int(amount),
            "currency": STATE["payments_currency_override"] or base["currency"],
            "status": STATE["payment_status"],
            "error_code": None if STATE["payment_status"] != "failed" else "BAD_CARD",
            "error_description": None if STATE["payment_status"] != "failed" else "declined",
        }]}


class _Payment:
    def refund(self, payment_id, data=None, **kwargs):
        _record("payment.refund", (payment_id,), data, kwargs)
        if STATE["refund_raises"]:
            raise ServerError(SDK_ERROR_TEXT)
        rid = _uid("rfnd")
        rec = {"id": rid, "payment_id": payment_id, "amount": int(data["amount"]),
               "currency": "INR", "status": STATE["refund_status"]}
        _REFUNDS[rid] = rec
        return rec


class _Refund:
    def fetch(self, refund_id, data=None, **kwargs):
        _record("refund.fetch", (refund_id,), data, kwargs)
        rec = dict(_REFUNDS.get(refund_id, {"id": refund_id, "amount": 100, "currency": "INR"}))
        rec["status"] = STATE["refund_status"]
        return rec


class FakeRazorpayClient:
    def __init__(self, auth):
        self.auth = auth
        self.order = _Order()
        self.payment = _Payment()
        self.refund = _Refund()
        # The SDK's real Utility: verify_payment_signature reads self.auth[1].
        self.utility = Utility(self)


def _fake_build_client(settings, payment_mode):
    # Same contract as the real seam: credentials come only from the real
    # fail-closed _resolve_credentials for this payment_mode.
    from app.gateways.razorpay_gateway import _resolve_credentials

    key_id, key_secret, _ = _resolve_credentials(settings, payment_mode)
    return FakeRazorpayClient(auth=(key_id, key_secret))


def install(monkeypatch) -> None:
    """Point the adapter at the fake and reset knobs. Only razorpay.Client
    is faked — credential resolution (mode match, missing creds, key prefix)
    still runs for every call."""
    reset()
    import app.gateways.razorpay_gateway as rg
    monkeypatch.setattr(rg, "_build_client", _fake_build_client)


def set_razorpay_env(monkeypatch, *, key_id="rzp_test_fake", key_secret="secret_fake",
                     webhook_secret="whsec_fake", mode="test") -> None:
    """Set the deployment's single active credential set (fake values).
    Explicit env vars outrank backend/.env, so real local creds never leak in."""
    from app.config import get_settings

    monkeypatch.setenv("RAZORPAY_KEY_ID", key_id)
    monkeypatch.setenv("RAZORPAY_KEY_SECRET", key_secret)
    monkeypatch.setenv("RAZORPAY_WEBHOOK_SECRET", webhook_secret)
    monkeypatch.setenv("RAZORPAY_MODE", mode)
    get_settings.cache_clear()


def set_razorpay_live_env(monkeypatch, *, key_id="rzp_live_fake", key_secret="live_secret_fake",
                          webhook_secret="live_whsec_fake") -> None:
    """Switch the fake deployment to RAZORPAY_MODE=live (fake values only)."""
    set_razorpay_env(monkeypatch, key_id=key_id, key_secret=key_secret,
                     webhook_secret=webhook_secret, mode="live")


def clear_razorpay_env(monkeypatch) -> None:
    """Blank the active Razorpay credential set."""
    from app.config import get_settings

    for name in ("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET"):
        monkeypatch.setenv(name, "")
    get_settings.cache_clear()


def checkout_signature(order_id: str, payment_id: str, key_secret="secret_fake") -> str:
    return hmac.new(key_secret.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256).hexdigest()


def webhook_body_and_sig(event: str, *, order_id: str, payment_id: Optional[str] = None,
                         amount_paise: int = 100, currency: str = "INR",
                         created_at: Optional[int] = None, webhook_secret="whsec_fake"):
    import time as _t
    import uuid as _uuid

    if payment_id is None:
        payment_id = f"pay_hook_{_uuid.uuid4().hex[:16]}"

    payment_entity = {
        "id": payment_id, "order_id": order_id, "amount": amount_paise,
        "currency": currency, "status": "captured" if event == "payment.captured" else "failed",
    }
    body = {
        "entity": "event",
        "event": event,
        "contains": ["payment"],
        "payload": {"payment": {"entity": payment_entity}},
        "created_at": int(created_at if created_at is not None else _t.time()),
    }
    raw = json.dumps(body, separators=(",", ":")).encode()
    sig = hmac.new(webhook_secret.encode(), raw, hashlib.sha256).hexdigest()
    return raw, sig
