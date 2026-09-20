"""Offline fake of the Razorpay REST surface used by RazorpayGateway.

Injected by monkeypatching app.gateways.razorpay_gateway._build_client. No
network, deterministic. Only the six calls the adapter makes are modelled.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import re
import uuid
from typing import Any, Dict, Optional


# order_id -> {"amount": paise, "currency": "INR"}
_ORDERS: Dict[str, Dict[str, Any]] = {}
# refund_id -> refund dict
_REFUNDS: Dict[str, Dict[str, Any]] = {}

# Test knobs
STATE: Dict[str, Any] = {
    "payment_status": "captured",   # what GET /orders/{id}/payments reports
    "payments_amount_override": None,  # force a mismatched amount (paise)
    "refund_status": "processed",   # what POST refund / GET refund reports
    "refund_raises": False,         # make the refund call raise RazorpayApiError
    "orders_create_raises": False,
    "payments_empty": False,        # GET /orders/{id}/payments returns no items
}


def reset() -> None:
    _ORDERS.clear()
    _REFUNDS.clear()
    STATE.update(
        payment_status="captured",
        payments_amount_override=None,
        refund_status="processed",
        refund_raises=False,
        orders_create_raises=False,
        payments_empty=False,
    )


_ORDER_PAYMENTS_RE = re.compile(r"^/orders/([^/]+)/payments$")
_REFUND_FETCH_RE = re.compile(r"^/refunds/([^/]+)$")
_PAYMENT_REFUND_RE = re.compile(r"^/payments/([^/]+)/refund$")


def _uid(prefix: str) -> str:
    # Globally unique — the tests run against a persistent local Postgres, so
    # predictable ids would collide with rows left by earlier runs.
    return f"{prefix}_{uuid.uuid4().hex}"


class FakeRazorpayClient:
    def request(self, method, path, *, json_body=None, headers=None, operation=""):
        from app.gateways.razorpay_gateway import RazorpayApiError

        method = method.upper()
        path = "/" + path.lstrip("/")

        if method == "POST" and path == "/orders":
            if STATE["orders_create_raises"]:
                raise RazorpayApiError("orders.create", 502, "server_error")
            oid = _uid("order")
            _ORDERS[oid] = {"amount": int(json_body["amount"]), "currency": json_body.get("currency", "INR")}
            return {"id": oid, "amount": int(json_body["amount"]),
                    "currency": json_body.get("currency", "INR"), "status": "created",
                    "receipt": json_body.get("receipt", "")}

        m = _ORDER_PAYMENTS_RE.match(path)
        if method == "GET" and m:
            oid = m.group(1)
            if STATE["payments_empty"]:
                return {"count": 0, "items": []}
            base = _ORDERS.get(oid, {"amount": 100, "currency": "INR"})
            amount = STATE["payments_amount_override"] or base["amount"]
            return {"count": 1, "items": [{
                "id": _uid("pay"),
                "order_id": oid,
                "amount": int(amount),
                "currency": base["currency"],
                "status": STATE["payment_status"],
                "error_code": None if STATE["payment_status"] != "failed" else "BAD_CARD",
                "error_description": None if STATE["payment_status"] != "failed" else "declined",
            }]}

        m = _PAYMENT_REFUND_RE.match(path)
        if method == "POST" and m:
            if STATE["refund_raises"]:
                raise RazorpayApiError("payments.refund", 502, "server_error")
            pid = m.group(1)
            rid = _uid("rfnd")
            rec = {"id": rid, "payment_id": pid, "amount": int(json_body["amount"]),
                   "currency": "INR", "status": STATE["refund_status"]}
            _REFUNDS[rid] = rec
            return rec

        m = _REFUND_FETCH_RE.match(path)
        if method == "GET" and m:
            rid = m.group(1)
            rec = dict(_REFUNDS.get(rid, {"id": rid, "amount": 100, "currency": "INR"}))
            rec["status"] = STATE["refund_status"]
            return rec

        raise RazorpayApiError(operation or f"{method} {path}", 404, "not_found")


def install(monkeypatch) -> None:
    """Point the adapter at the fake and reset knobs. The fake ignores which
    mode it was called for — credential *resolution* (fail-closed
    prefix/missing checks) is exercised separately via _resolve_credentials,
    not through this seam."""
    reset()
    import app.gateways.razorpay_gateway as rg
    monkeypatch.setattr(rg, "_build_client", lambda settings, payment_mode: FakeRazorpayClient())


def set_razorpay_env(monkeypatch, *, key_id="rzp_test_fake", key_secret="secret_fake",
                     webhook_secret="whsec_fake", mode="test") -> None:
    """Legacy-var seed (RAZORPAY_KEY_ID/...): exercises the TEST-profile
    back-compat fallback in Settings.razorpay_credentials_for."""
    from app.config import get_settings

    monkeypatch.setenv("RAZORPAY_KEY_ID", key_id)
    monkeypatch.setenv("RAZORPAY_KEY_SECRET", key_secret)
    monkeypatch.setenv("RAZORPAY_WEBHOOK_SECRET", webhook_secret)
    monkeypatch.setenv("RAZORPAY_MODE", mode)
    get_settings.cache_clear()


def set_razorpay_test_env(monkeypatch, *, key_id="rzp_test_fake", key_secret="secret_fake",
                          webhook_secret="whsec_fake") -> None:
    from app.config import get_settings

    monkeypatch.setenv("RAZORPAY_TEST_KEY_ID", key_id)
    monkeypatch.setenv("RAZORPAY_TEST_KEY_SECRET", key_secret)
    monkeypatch.setenv("RAZORPAY_TEST_WEBHOOK_SECRET", webhook_secret)
    get_settings.cache_clear()


def set_razorpay_live_env(monkeypatch, *, key_id="rzp_live_fake", key_secret="live_secret_fake",
                          webhook_secret="live_whsec_fake") -> None:
    from app.config import get_settings

    monkeypatch.setenv("RAZORPAY_LIVE_KEY_ID", key_id)
    monkeypatch.setenv("RAZORPAY_LIVE_KEY_SECRET", key_secret)
    monkeypatch.setenv("RAZORPAY_LIVE_WEBHOOK_SECRET", webhook_secret)
    get_settings.cache_clear()


def clear_razorpay_env(monkeypatch) -> None:
    """Blank every Razorpay credential var (legacy + test + live)."""
    from app.config import get_settings

    for name in (
        "RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET",
        "RAZORPAY_TEST_KEY_ID", "RAZORPAY_TEST_KEY_SECRET", "RAZORPAY_TEST_WEBHOOK_SECRET",
        "RAZORPAY_LIVE_KEY_ID", "RAZORPAY_LIVE_KEY_SECRET", "RAZORPAY_LIVE_WEBHOOK_SECRET",
    ):
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
