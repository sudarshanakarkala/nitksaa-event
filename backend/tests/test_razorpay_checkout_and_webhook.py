"""Razorpay Test Mode — end-to-end through the ASGI app against local
Postgres, with the Razorpay REST surface faked offline.

Covers: ₹1 paid flow via a razorpay-gateway event, checkout signature
verification (valid / invalid / tampered / amount-mismatch / fake-success),
authoritative query_payment_status, and the raw-body webhook path
(valid / invalid / tampered / duplicate / replay / pending / failed /
freshness / unknown-order).
"""
import json
import uuid
from decimal import Decimal

import pytest

from tests import _razorpay_fakes as fakes

_TEST_ALUMNI = {
    "firebase_uid": "TEST_ALUMNI_UID_001", "sub": "ravi.test@nitksaa.dev",
    "email": "ravi.test@nitksaa.dev", "fullname": "Ravi Shankar Test",
    "user_type": "alumni", "ref_id": "NITK2020CS001", "graduation_year": 2020,
}
_TEST_ALUMNI_2 = {
    "firebase_uid": "TEST_ALUMNI_UID_002", "sub": "priya.test@nitksaa.dev",
    "email": "priya.test@nitksaa.dev", "fullname": "Priya Kumari Test",
    "user_type": "alumni", "ref_id": "NITK2019EC002", "graduation_year": 2019,
}
_FIXTURE_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_043", "sub": "fixture.admin.rbac@nitksaa.dev",
    "email": "fixture.admin.rbac@nitksaa.dev", "fullname": "Fixture Admin RBAC Test",
    "user_type": "alumni", "ref_id": "NITK2018CS043", "graduation_year": 2018,
}
_ADMIN = {"X-Dev-User": "admin"}


def _bearer(identity: dict = _TEST_ALUMNI) -> dict:
    from app.middleware.auth import make_access_token
    return {"Authorization": f"Bearer {make_access_token(dict(identity))}"}


def _db_exec(query, *args):
    import asyncio
    import asyncpg
    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            await conn.execute(query, *args)
        finally:
            await conn.close()

    asyncio.run(_run())


def _db_fetchval(query, *args):
    import asyncio
    import asyncpg
    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            return await conn.fetchval(query, *args)
        finally:
            await conn.close()

    return asyncio.run(_run())


@pytest.fixture(autouse=True)
def _seed_and_fakes(monkeypatch):
    for ident in (_TEST_ALUMNI, _TEST_ALUMNI_2, _FIXTURE_ADMIN):
        _db_exec(
            """INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
               VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (firebase_uid) DO NOTHING""",
            ident["firebase_uid"], ident["email"], ident["fullname"],
            ident["user_type"], ident["ref_id"], ident["graduation_year"],
        )
    _db_exec(
        """INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
           VALUES ($1,'platform_admin','test_fixture_bootstrap')
           ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING""",
        _FIXTURE_ADMIN["firebase_uid"],
    )
    fakes.set_razorpay_env(monkeypatch)
    fakes.install(monkeypatch)
    yield
    from app.config import get_settings
    get_settings.cache_clear()


def _mk_razorpay_event(client, suffix: str, *, base_amount: str = "1.00") -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"RZP PILOT {suffix}", "description": "pytest razorpay",
            "start_datetime": "2027-03-01T08:00:00+05:30",
            "end_datetime": "2027-03-01T10:00:00+05:30",
            "location_text": "Venue", "is_virtual": False, "capacity": 20,
            "is_free": False, "ticket_price": base_amount,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    event_id = r.json()["event_id"]
    assert client.post(f"/api/v1/admin/events/{event_id}/publish",
                       headers=_bearer(_FIXTURE_ADMIN)).status_code == 200
    r = client.post(
        "/api/v1/dev/diagnostics/payments/configuration/import",
        json={
            "configuration_key": f"rzp-{suffix}", "event_id": event_id,
            "base_amount": base_amount, "gst_enabled": False,
            "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15,
            "gateway": "razorpay",
        },
        headers=_ADMIN,
    )
    assert r.status_code == 200, r.text
    return event_id


def _register_and_initiate(client, event_id, identity=_TEST_ALUMNI):
    h = _bearer(identity)
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=h)
    assert r.status_code == 201, r.text
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"rzp-{uuid.uuid4().hex}"}, headers=h,
    )
    assert r.status_code == 201, r.text
    order = r.json()
    r = client.post(f"/api/v1/payment-orders/{order['order_id']}/attempts", json={}, headers=h)
    assert r.status_code == 201, r.text
    attempt = r.json()
    return reg, order, attempt


# ── initiation / checkout contract ──────────────────────────────────────

def test_one_rupee_attempt_returns_razorpay_checkout_payload(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, attempt = _register_and_initiate(client, event_id)
    assert attempt["gateway"] == "razorpay"
    assert attempt["status"] == "initiated"
    c = attempt["checkout"]
    assert c is not None
    assert c["provider"] == "razorpay"
    assert c["amount_minor"] == 100          # ₹1.00
    assert c["currency"] == "INR"
    assert c["key_id"] == "rzp_test_fake"
    assert c["provider_order_id"].startswith("order_")
    # The fixture's active secrets must never appear in the API response.
    blob = json.dumps(attempt)
    assert "secret_fake" not in blob and "whsec_fake" not in blob and "key_secret" not in blob
    # stored gateway_order_ref is the real provider order id
    ref = _db_fetchval(
        "SELECT gateway_order_ref FROM payment_attempts WHERE public_attempt_number=$1",
        attempt["attempt_id"],
    )
    assert ref == c["provider_order_id"]


def test_order_snapshots_gateway_razorpay(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, _ = _register_and_initiate(client, event_id)
    gw = _db_fetchval("SELECT gateway FROM payment_orders WHERE public_order_number=$1", order["order_id"])
    assert gw == "razorpay"


# ── checkout verification ──────────────────────────────────────────────

def test_checkout_verification_success_confirms_registration(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    oid = attempt["checkout"]["provider_order_id"]
    pid = "pay_client_ok"
    sig = fakes.checkout_signature(oid, pid)
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/verify-checkout",
        json={"razorpay_payment_id": pid, "razorpay_order_id": oid, "razorpay_signature": sig},
        headers=_bearer(),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["payment_confirmed"] is True
    assert body["order_status"] == "paid"
    assert body["registration_status"] == "registered"

    mr = client.get(f"/api/v1/events/{event_id}/my-registration", headers=_bearer())
    assert mr.json()["status"] == "registered"


def test_checkout_invalid_signature_rejected_no_capture(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    oid = attempt["checkout"]["provider_order_id"]
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/verify-checkout",
        json={"razorpay_payment_id": "pay_x", "razorpay_order_id": oid, "razorpay_signature": "deadbeef"},
        headers=_bearer(),
    )
    assert r.status_code == 400
    assert r.json()["detail"] == "checkout_signature_invalid"
    status = _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"])
    assert status != "paid"


def test_checkout_tampered_payment_id_rejected(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    oid = attempt["checkout"]["provider_order_id"]
    sig = fakes.checkout_signature(oid, "pay_REAL")
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/verify-checkout",
        json={"razorpay_payment_id": "pay_ATTACKER", "razorpay_order_id": oid, "razorpay_signature": sig},
        headers=_bearer(),
    )
    assert r.status_code == 400
    assert r.json()["detail"] == "checkout_signature_invalid"


def test_checkout_tampered_order_id_rejected(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    pid = "pay_x"
    sig = fakes.checkout_signature("order_ATTACKER", pid)
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/verify-checkout",
        json={"razorpay_payment_id": pid, "razorpay_order_id": "order_ATTACKER", "razorpay_signature": sig},
        headers=_bearer(),
    )
    # A bogus provider order id resolves to no attempt (404, existence-hiding);
    # an id that resolves to a *different* order gives checkout_order_mismatch.
    assert r.status_code in (400, 404)
    assert r.json()["detail"] in ("checkout_order_mismatch", "payment_attempt_not_found")
    status = _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"])
    assert status != "paid"


def test_checkout_amount_mismatch_rejected_no_capture(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    oid = attempt["checkout"]["provider_order_id"]
    pid = "pay_x"
    sig = fakes.checkout_signature(oid, pid)
    fakes.STATE["payments_amount_override"] = 5000  # provider says ₹50 captured
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/verify-checkout",
        json={"razorpay_payment_id": pid, "razorpay_order_id": oid, "razorpay_signature": sig},
        headers=_bearer(),
    )
    assert r.status_code == 400
    assert r.json()["detail"] == "checkout_amount_mismatch"
    status = _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"])
    assert status != "paid"


def test_checkout_browser_reports_success_but_provider_not_captured(client):
    """Valid signature, but authoritative provider status is 'authorized'
    (not captured) — registration must NOT be confirmed."""
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    oid = attempt["checkout"]["provider_order_id"]
    pid = "pay_x"
    sig = fakes.checkout_signature(oid, pid)
    fakes.STATE["payment_status"] = "authorized"
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/verify-checkout",
        json={"razorpay_payment_id": pid, "razorpay_order_id": oid, "razorpay_signature": sig},
        headers=_bearer(),
    )
    assert r.status_code == 200, r.text
    assert r.json()["payment_confirmed"] is False
    status = _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"])
    assert status != "paid"
    reg_status = _db_fetchval("SELECT status FROM registrations WHERE registration_id=$1", reg["registration_id"])
    assert reg_status != "registered"


def test_checkout_verification_cross_user_denied(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id, identity=_TEST_ALUMNI)
    oid = attempt["checkout"]["provider_order_id"]
    pid = "pay_x"
    sig = fakes.checkout_signature(oid, pid)
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/verify-checkout",
        json={"razorpay_payment_id": pid, "razorpay_order_id": oid, "razorpay_signature": sig},
        headers=_bearer(_TEST_ALUMNI_2),
    )
    assert r.status_code == 404


# ── query_payment_status via POST /verify ──────────────────────────────

def test_manual_verify_captures_via_query_status(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    fakes.STATE["payment_status"] = "captured"
    r = client.post(f"/api/v1/payment-attempts/{attempt['attempt_id']}/verify", headers=_bearer())
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "captured"
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) == "paid"


def test_manual_verify_failed_via_query_status(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    fakes.STATE["payment_status"] = "failed"
    r = client.post(f"/api/v1/payment-attempts/{attempt['attempt_id']}/verify", headers=_bearer())
    assert r.status_code == 200
    assert r.json()["status"] == "failed"


def test_manual_verify_authorized_stays_pending(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    fakes.STATE["payment_status"] = "authorized"
    r = client.post(f"/api/v1/payment-attempts/{attempt['attempt_id']}/verify", headers=_bearer())
    assert r.status_code == 200
    assert r.json()["status"] == "pending"
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) != "paid"


# ── webhook (raw-body) ────────────────────────────────────────────────

def _event_rows(gateway_event_id: str) -> int:
    return _db_fetchval(
        "SELECT count(*) FROM payment_webhook_events WHERE gateway = 'razorpay' AND gateway_event_id = $1",
        gateway_event_id,
    )


def _webhook(client, event, *, order_ref, event_id, amount_paise=100, created_at=None, mangle=False, bad_sig=False):
    raw, sig = fakes.webhook_body_and_sig(event, order_id=order_ref, amount_paise=amount_paise, created_at=created_at)
    if mangle:
        raw = raw + b" "
    if bad_sig:
        sig = "00" + sig[2:]
    return client.post(
        "/api/v1/payment-gateways/razorpay/test/webhook",
        content=raw,
        headers={"X-Razorpay-Signature": sig, "X-Razorpay-Event-Id": event_id,
                 "Content-Type": "application/json"},
    )


def test_webhook_valid_capture_confirms(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}")
    assert r.status_code == 200, r.text
    assert r.json()["processing_status"] == "processed"
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) == "paid"
    assert _db_fetchval("SELECT status FROM registrations WHERE registration_id=$1", reg["registration_id"]) == "registered"


def test_webhook_invalid_signature_rejected(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    evt = f"evt_{uuid.uuid4().hex}"
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=evt, bad_sig=True)
    assert r.status_code == 400 and r.json()["detail"] == "invalid_signature"
    assert _event_rows(evt) == 0
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) != "paid"


def test_webhook_tampered_body_rejected(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    evt = f"evt_{uuid.uuid4().hex}"
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=evt, mangle=True)
    assert r.status_code == 400 and r.json()["detail"] == "invalid_signature"
    assert _event_rows(evt) == 0


def test_webhook_duplicate_event_id_is_idempotent(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    evt = f"evt_{uuid.uuid4().hex}"
    r1 = _webhook(client, "payment.captured", order_ref=ref, event_id=evt)
    r2 = _webhook(client, "payment.captured", order_ref=ref, event_id=evt)
    assert r1.json()["processing_status"] == "processed"
    assert r2.json()["processing_status"] == "duplicate"
    cap = _db_fetchval(
        "SELECT count(*) FROM payment_attempts WHERE order_id=(SELECT id FROM payment_orders WHERE public_order_number=$1) AND status='captured'",
        order["order_id"],
    )
    assert cap == 1


def test_webhook_replay_after_capture_no_extra_mutation(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    _webhook(client, "payment.captured", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}")
    paid_at = _db_fetchval("SELECT paid_at FROM payment_orders WHERE public_order_number=$1", order["order_id"])
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}")
    assert r.json()["processing_status"] == "duplicate"  # stale attempt, already captured
    assert _db_fetchval("SELECT paid_at FROM payment_orders WHERE public_order_number=$1", order["order_id"]) == paid_at


def test_webhook_failed_marks_payment_failed(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    r = _webhook(client, "payment.failed", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}")
    assert r.json()["processing_status"] == "processed"
    assert _db_fetchval("SELECT status FROM payment_attempts WHERE public_attempt_number=$1", attempt["attempt_id"]) == "failed"
    assert _db_fetchval("SELECT status FROM registrations WHERE registration_id=$1", reg["registration_id"]) == "payment_failed"


def test_webhook_authorized_maps_to_pending_verification(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    r = _webhook(client, "payment.authorized", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}")
    assert r.json()["processing_status"] == "processed"
    assert _db_fetchval("SELECT status FROM payment_attempts WHERE public_attempt_number=$1", attempt["attempt_id"]) == "pending"
    assert _db_fetchval("SELECT status FROM registrations WHERE registration_id=$1", reg["registration_id"]) == "payment_verification"


def test_webhook_stale_timestamp_rejected(client):
    """Beyond the configured maximum age (default 25 h, past Razorpay's
    24-hour retry horizon) a signed event is still rejected as stale."""
    import time
    from app.config import get_settings
    max_age = get_settings().payment_webhook_max_age_seconds
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}",
                 created_at=int(time.time()) - (max_age + 60))
    assert r.status_code == 200 and r.json()["processing_status"] == "rejected"
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) != "paid"


def test_webhook_unknown_order_rejected(client):
    _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    r = _webhook(client, "payment.captured", order_ref="order_NOPE", event_id=f"evt_{uuid.uuid4().hex}")
    assert r.json()["processing_status"] == "rejected"


# ── TEST/LIVE mode separation ─────────────────────────────────────────────

def test_attempt_and_order_carry_test_mode_metadata(client):
    """The dev-diagnostics import path (used by _mk_razorpay_event) doesn't
    set payment_mode explicitly, so it defaults to 'test' — every order/
    attempt created against it must say so, safely, with real_money=False."""
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, attempt = _register_and_initiate(client, event_id)
    assert order["payment_mode"] == "test"
    assert order["real_money"] is False
    assert attempt["payment_mode"] == "test"
    assert attempt["real_money"] is False


def test_generic_webhook_route_rejects_razorpay(client):
    """Razorpay must use the mode-specific routes — the legacy generic route
    now 404s for it exactly like an unregistered gateway would."""
    r = client.post(
        "/api/v1/payment-gateways/razorpay/webhook",
        content=b"{}",
        headers={"X-Sandbox-Signature": "irrelevant", "Content-Type": "application/json"},
    )
    assert r.status_code == 404


def test_live_webhook_route_rejects_test_signed_delivery(client):
    """This fixture is a RAZORPAY_MODE=test deployment — a delivery to the
    LIVE route must fail closed (invalid signature), never be checked
    against the active TEST webhook secret."""
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    raw, sig = fakes.webhook_body_and_sig("payment.captured", order_id=ref, amount_paise=100)
    evt = f"evt_{uuid.uuid4().hex}"
    r = client.post(
        "/api/v1/payment-gateways/razorpay/live/webhook",
        content=raw,
        headers={"X-Razorpay-Signature": sig, "X-Razorpay-Event-Id": evt,
                 "Content-Type": "application/json"},
    )
    assert r.status_code == 400 and r.json()["detail"] == "invalid_signature"
    assert _event_rows(evt) == 0
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) != "paid"


def test_live_signed_webhook_for_test_order_is_mode_mismatch_rejected(monkeypatch, client):
    """A TEST-mode order created before the deployment switched to
    RAZORPAY_MODE=live must not be confirmed by a correctly LIVE-signed
    delivery — cross-mode webhook application is rejected regardless of
    signature validity (spec §18/§21: cross-mode must be structurally
    impossible)."""
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, attempt = _register_and_initiate(client, event_id)
    assert order["payment_mode"] == "test"
    ref = attempt["checkout"]["provider_order_id"]
    fakes.set_razorpay_live_env(monkeypatch)
    raw, sig = fakes.webhook_body_and_sig(
        "payment.captured", order_id=ref, amount_paise=100, webhook_secret="live_whsec_fake"
    )
    r = client.post(
        "/api/v1/payment-gateways/razorpay/live/webhook",
        content=raw,
        headers={"X-Razorpay-Signature": sig, "X-Razorpay-Event-Id": f"evt_{uuid.uuid4().hex}",
                 "Content-Type": "application/json"},
    )
    assert r.json()["processing_status"] == "rejected"
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) != "paid"


# ── retry after the attendee closed Checkout without paying ─────────────
# Same attempt, same Razorpay order: no new payment_attempts row, no second
# order.create — and never for a paid / expired / cancelled / in-flight one.

def _order_create_calls() -> int:
    return sum(1 for c in fakes.CALLS if c["method"] == "order.create")


def _attempt_count(public_order_number: str) -> int:
    return _db_fetchval(
        "SELECT count(*) FROM payment_attempts pa JOIN payment_orders po ON po.id = pa.order_id "
        "WHERE po.public_order_number = $1",
        public_order_number,
    )


def _pay(client, order, identity=_TEST_ALUMNI):
    return client.post(f"/api/v1/payment-orders/{order['order_id']}/attempts", json={}, headers=_bearer(identity))


def test_retry_after_dismissed_checkout_reuses_same_attempt_and_razorpay_order(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, first = _register_and_initiate(client, event_id)   # A: first Pay
    assert _order_create_calls() == 1
    # B: attendee closes Checkout — no verify-checkout call, no webhook.
    r = _pay(client, order)                                        # C: Pay again
    assert r.status_code == 201, r.text
    second = r.json()
    assert second["attempt_id"] == first["attempt_id"]
    assert second["status"] == "initiated"
    assert second["checkout"] == first["checkout"]
    assert second["checkout"]["provider_order_id"].startswith("order_")
    assert second["checkout"]["amount_minor"] == 100
    assert _order_create_calls() == 1                              # D
    assert _attempt_count(order["order_id"]) == 1                  # E
    assert "secret_fake" not in r.text and "whsec_fake" not in r.text


def test_concurrent_retries_all_reuse_the_same_checkout(client):
    from concurrent.futures import ThreadPoolExecutor

    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, first = _register_and_initiate(client, event_id)
    with ThreadPoolExecutor(max_workers=5) as pool:
        responses = list(pool.map(lambda _: _pay(client, order), range(5)))
    assert [r.status_code for r in responses] == [201] * 5, [r.text for r in responses]
    assert {r.json()["attempt_id"] for r in responses} == {first["attempt_id"]}
    assert {r.json()["checkout"]["provider_order_id"] for r in responses} == {first["checkout"]["provider_order_id"]}
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


def test_concurrent_first_pay_creates_exactly_one_razorpay_order(client):
    from concurrent.futures import ThreadPoolExecutor

    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    h = _bearer()
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=h).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"rzp-{uuid.uuid4().hex}"}, headers=h,
    ).json()
    with ThreadPoolExecutor(max_workers=5) as pool:
        responses = list(pool.map(lambda _: _pay(client, order), range(5)))
    ok = [r for r in responses if r.status_code == 201]
    conflicts = [r for r in responses if r.status_code == 409]
    assert ok and len(ok) + len(conflicts) == 5, [r.text for r in responses]
    assert len({r.json()["attempt_id"] for r in ok}) == 1
    assert len({r.json()["checkout"]["provider_order_id"] for r in ok}) == 1
    assert all(r.json()["detail"] == "payment_attempt_active" for r in conflicts)
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


def test_retry_while_only_placeholder_ref_exists_is_still_409(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, first = _register_and_initiate(client, event_id)
    # order.create never returned for this attempt (placeholder still stored)
    _db_exec(
        "UPDATE payment_attempts SET gateway_order_ref = $1 WHERE public_attempt_number = $2",
        f"rzp_pending_{uuid.uuid4().hex[:12]}", first["attempt_id"],
    )
    r = _pay(client, order)
    assert r.status_code == 409 and r.json()["detail"] == "payment_attempt_active"
    assert "rzp_pending_" not in r.text
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


def test_paid_order_is_never_reopened(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, first = _register_and_initiate(client, event_id)
    ref = first["checkout"]["provider_order_id"]
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}")
    assert r.json()["processing_status"] == "processed"
    r = _pay(client, order)
    assert r.status_code == 409 and r.json()["detail"] == "payment_order_not_payable"
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


@pytest.mark.parametrize("mutation,detail", [
    ("UPDATE payment_orders SET expires_at = now() - interval '1 minute' WHERE public_order_number = $1",
     "payment_order_expired"),
    ("UPDATE payment_orders SET status = 'expired' WHERE public_order_number = $1", "payment_order_not_payable"),
    ("UPDATE payment_orders SET status = 'cancelled' WHERE public_order_number = $1", "payment_order_not_payable"),
])
def test_expired_or_cancelled_order_is_never_reopened(client, mutation, detail):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, _first = _register_and_initiate(client, event_id)
    _db_exec(mutation, order["order_id"])
    r = _pay(client, order)
    assert r.status_code == 409 and r.json()["detail"] == detail
    assert "checkout" not in r.json()
    assert _order_create_calls() == 1


def test_expired_seat_hold_is_never_reopened(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, _first = _register_and_initiate(client, event_id)
    _db_exec(
        "UPDATE registrations SET hold_expires_at = now() - interval '1 minute' WHERE registration_id = $1",
        reg["registration_id"],
    )
    r = _pay(client, order)
    assert r.status_code == 409 and r.json()["detail"] == "seat_hold_expired"
    assert _order_create_calls() == 1


def test_pending_attempt_payment_in_flight_is_not_reopened(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, first = _register_and_initiate(client, event_id)
    _db_exec("UPDATE payment_attempts SET status = 'pending' WHERE public_attempt_number = $1", first["attempt_id"])
    _db_exec("UPDATE registrations SET status = 'payment_verification' WHERE registration_id = $1", reg["registration_id"])
    r = _pay(client, order)
    assert r.status_code == 409 and r.json()["detail"] == "payment_verification_in_progress"
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


def test_failed_attempt_is_not_reopened_retry_creates_a_new_one(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, first = _register_and_initiate(client, event_id)
    _db_exec("UPDATE payment_attempts SET status = 'failed' WHERE public_attempt_number = $1", first["attempt_id"])
    r = _pay(client, order)
    assert r.status_code == 201, r.text
    assert r.json()["attempt_id"] != first["attempt_id"]
    assert r.json()["checkout"]["provider_order_id"] != first["checkout"]["provider_order_id"]
    assert _order_create_calls() == 2
    assert _attempt_count(order["order_id"]) == 2


def test_other_user_cannot_reuse_the_attempt(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, first = _register_and_initiate(client, event_id)
    r = _pay(client, order, identity=_TEST_ALUMNI_2)
    assert r.status_code == 404 and r.json()["detail"] == "payment_order_not_found"
    assert first["checkout"]["provider_order_id"] not in r.text
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


def test_retry_after_deployment_mode_change_fails_closed(monkeypatch, client):
    """A TEST-mode attempt must not be reopened once this deployment runs
    RAZORPAY_MODE=live — its credentials may not serve a test order."""
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, first = _register_and_initiate(client, event_id)
    fakes.set_razorpay_live_env(monkeypatch)
    r = _pay(client, order)
    assert r.status_code == 502 and r.json()["detail"] == "payment_gateway_error"
    assert "rzp_live_fake" not in r.text
    assert _db_fetchval(
        "SELECT status FROM payment_attempts WHERE public_attempt_number = $1", first["attempt_id"]
    ) == "initiated"
    assert _order_create_calls() == 1


# ── "Check payment status" after closing Checkout ───────────────────────

def _check_status(client, attempt, identity=_TEST_ALUMNI):
    return client.post(f"/api/v1/payment-attempts/{attempt['attempt_id']}/verify", headers=_bearer(identity))


def _reg_status(reg) -> str:
    return _db_fetchval("SELECT status FROM registrations WHERE registration_id = $1", reg["registration_id"])


def test_status_check_with_no_razorpay_payment_keeps_checkout_reusable(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, first = _register_and_initiate(client, event_id)   # Pay -> Razorpay order created
    # Checkout dismissed, then "Check payment status": Razorpay has zero payments.
    fakes.STATE["payments_empty"] = True
    for _ in range(2):  # repeated checks never escalate it either
        r = _check_status(client, first)
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "initiated"
    assert sum(1 for c in fakes.CALLS if c["method"] == "order.payments") == 2
    assert _reg_status(reg) == "payment_pending"

    r = _pay(client, order)                                          # Pay again
    assert r.status_code == 201, r.text
    assert r.json()["attempt_id"] == first["attempt_id"]
    assert r.json()["checkout"]["provider_order_id"] == first["checkout"]["provider_order_id"]
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


@pytest.mark.parametrize("provider_status,attempt_status,registration_status,pay_detail", [
    # a real payment in flight: existing do-not-pay-again behaviour
    ("authorized", "pending", "payment_verification", "payment_verification_in_progress"),
    # captured: existing confirmation behaviour, order can't be reopened
    ("captured", "captured", "registered", "payment_order_not_payable"),
])
def test_status_check_with_a_real_payment_keeps_existing_behaviour(
    client, provider_status, attempt_status, registration_status, pay_detail
):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, first = _register_and_initiate(client, event_id)
    fakes.STATE["payment_status"] = provider_status
    r = _check_status(client, first)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == attempt_status
    assert _reg_status(reg) == registration_status
    r = _pay(client, order)
    assert r.status_code == 409 and r.json()["detail"] == pay_detail
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


def test_status_check_with_failed_payment_keeps_failure_and_fresh_retry(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, first = _register_and_initiate(client, event_id)
    fakes.STATE["payment_status"] = "failed"
    r = _check_status(client, first)
    assert r.status_code == 200 and r.json()["status"] == "failed"
    assert _reg_status(reg) == "payment_failed"
    r = _pay(client, order)
    assert r.status_code == 201, r.text
    assert r.json()["attempt_id"] != first["attempt_id"]
    assert _order_create_calls() == 2
    assert _attempt_count(order["order_id"]) == 2


def test_already_pending_attempt_is_not_reopened_by_an_empty_status_check(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, first = _register_and_initiate(client, event_id)
    _db_exec("UPDATE payment_attempts SET status = 'pending' WHERE public_attempt_number = $1", first["attempt_id"])
    _db_exec("UPDATE registrations SET status = 'payment_verification' WHERE registration_id = $1", reg["registration_id"])
    fakes.STATE["payments_empty"] = True
    r = _check_status(client, first)
    assert r.status_code == 200 and r.json()["status"] == "pending"
    assert _reg_status(reg) == "payment_verification"
    r = _pay(client, order)
    assert r.status_code == 409 and r.json()["detail"] == "payment_verification_in_progress"
    assert _order_create_calls() == 1


def test_concurrent_pay_after_empty_status_check_reuses_one_checkout(client):
    from concurrent.futures import ThreadPoolExecutor

    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, order, first = _register_and_initiate(client, event_id)
    fakes.STATE["payments_empty"] = True
    assert _check_status(client, first).json()["status"] == "initiated"
    with ThreadPoolExecutor(max_workers=5) as pool:
        responses = list(pool.map(lambda _: _pay(client, order), range(5)))
    assert [r.status_code for r in responses] == [201] * 5, [r.text for r in responses]
    assert {r.json()["attempt_id"] for r in responses} == {first["attempt_id"]}
    assert _order_create_calls() == 1
    assert _attempt_count(order["order_id"]) == 1


def test_other_user_cannot_status_check_the_attempt(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    _, _order, first = _register_and_initiate(client, event_id)
    fakes.STATE["payments_empty"] = True
    r = _check_status(client, first, identity=_TEST_ALUMNI_2)
    assert r.status_code == 404 and r.json()["detail"] == "payment_attempt_not_found"
    assert not any(c["method"] == "order.payments" for c in fakes.CALLS)


# ── Step 5: verify-checkout correctness, ordering and race safety ────────

def _db_fetchrow(query, *args):
    import asyncio
    import asyncpg
    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            row = await conn.fetchrow(query, *args)
            return dict(row) if row else None
        finally:
            await conn.close()

    return asyncio.run(_run())


def _snapshot(reg, order, attempt) -> dict:
    return {
        "attempt": _db_fetchrow(
            "SELECT id, status, gateway_payment_ref, captured_at, failed_at, updated_at "
            "FROM payment_attempts WHERE public_attempt_number = $1", attempt["attempt_id"]),
        "order": _db_fetchrow(
            "SELECT status, amount_paid, final_amount, paid_at, updated_at "
            "FROM payment_orders WHERE public_order_number = $1", order["order_id"]),
        "registration": _db_fetchrow(
            "SELECT status, updated_at FROM registrations WHERE registration_id = $1", reg["registration_id"]),
    }


def _audit_count(event_type: str, entity_type: str, entity_id: int) -> int:
    return _db_fetchval(
        "SELECT count(*) FROM event_audit_log WHERE event_type = $1 AND entity_type = $2 AND entity_id = $3",
        event_type, entity_type, entity_id,
    )


def _confirmations(reg) -> int:
    return _audit_count("registration_confirmed_by_payment", "registration", reg["registration_id"])


def _captures(state) -> int:
    return _audit_count("payment_captured", "payment_attempt", state["attempt"]["id"])


def _verify(client, order, provider_order_id, payment_id, *, identity=_TEST_ALUMNI, signature=None):
    return client.post(
        f"/api/v1/payment-orders/{order['order_id']}/verify-checkout",
        json={"razorpay_payment_id": payment_id, "razorpay_order_id": provider_order_id,
              "razorpay_signature": signature or fakes.checkout_signature(provider_order_id, payment_id)},
        headers=_bearer(identity),
    )


def _payment_webhook(client, event, *, order_ref, payment_id):
    raw, sig = fakes.webhook_body_and_sig(event, order_id=order_ref, payment_id=payment_id, amount_paise=100)
    return client.post(
        "/api/v1/payment-gateways/razorpay/test/webhook",
        content=raw,
        headers={"X-Razorpay-Signature": sig, "X-Razorpay-Event-Id": f"evt_{uuid.uuid4().hex}",
                 "Content-Type": "application/json"},
    )


def _paid_setup(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    return reg, order, attempt, attempt["checkout"]["provider_order_id"]


def _assert_captured_paid_registered(reg, order, attempt, payment_id):
    s = _snapshot(reg, order, attempt)
    assert s["attempt"]["status"] == "captured"
    assert s["attempt"]["gateway_payment_ref"] == payment_id
    assert s["attempt"]["captured_at"] is not None
    assert s["order"]["status"] == "paid"
    assert s["order"]["amount_paid"] == s["order"]["final_amount"]
    assert s["order"]["paid_at"] is not None
    assert s["registration"]["status"] == "registered"
    return s


def test_successful_verification_sets_every_captured_paid_field(client):   # 14
    reg, order, attempt, ref = _paid_setup(client)
    pid = f"pay_{uuid.uuid4().hex[:14]}"
    fakes.STATE["payment_id"] = pid
    r = _verify(client, order, ref, pid)
    assert r.status_code == 200 and r.json()["payment_confirmed"] is True
    s = _assert_captured_paid_registered(reg, order, attempt, pid)
    assert _confirmations(reg) == 1 and _captures(s) == 1


def test_verify_then_webhook_success_is_idempotent(client):              # 1
    reg, order, attempt, ref = _paid_setup(client)
    pid = f"pay_{uuid.uuid4().hex[:14]}"
    fakes.STATE["payment_id"] = pid
    assert _verify(client, order, ref, pid).json()["payment_confirmed"] is True
    before = _snapshot(reg, order, attempt)

    r = _payment_webhook(client, "payment.captured", order_ref=ref, payment_id=pid)
    assert r.json()["processing_status"] == "duplicate"
    after = _assert_captured_paid_registered(reg, order, attempt, pid)
    assert after == before                      # amount_paid, paid_at, captured_at untouched
    assert _confirmations(reg) == 1 and _captures(after) == 1
    assert _attempt_count(order["order_id"]) == 1


def test_webhook_success_then_verify_is_idempotent(client):              # 2
    reg, order, attempt, ref = _paid_setup(client)
    pid = f"pay_{uuid.uuid4().hex[:14]}"
    fakes.STATE["payment_id"] = pid
    assert _payment_webhook(client, "payment.captured", order_ref=ref, payment_id=pid).json()["processing_status"] == "processed"
    before = _snapshot(reg, order, attempt)

    r = _verify(client, order, ref, pid)
    assert r.status_code == 200
    assert r.json()["payment_confirmed"] is True and r.json()["order_status"] == "paid"
    after = _snapshot(reg, order, attempt)
    assert after == before
    assert _confirmations(reg) == 1 and _captures(after) == 1


def test_verify_twice_keeps_timestamps_and_side_effects(client):         # 3
    reg, order, attempt, ref = _paid_setup(client)
    pid = f"pay_{uuid.uuid4().hex[:14]}"
    fakes.STATE["payment_id"] = pid
    assert _verify(client, order, ref, pid).json()["payment_confirmed"] is True
    first = _snapshot(reg, order, attempt)
    r = _verify(client, order, ref, pid)
    assert r.status_code == 200 and r.json()["payment_confirmed"] is True
    second = _snapshot(reg, order, attempt)
    assert second == first
    assert _confirmations(reg) == 1 and _captures(second) == 1


def test_concurrent_verify_calls_capture_exactly_once(client):           # 4
    from concurrent.futures import ThreadPoolExecutor

    reg, order, attempt, ref = _paid_setup(client)
    pid = f"pay_{uuid.uuid4().hex[:14]}"
    fakes.STATE["payment_id"] = pid
    with ThreadPoolExecutor(max_workers=5) as pool:
        responses = list(pool.map(lambda _: _verify(client, order, ref, pid), range(5)))
    assert [r.status_code for r in responses] == [200] * 5, [r.text for r in responses]
    assert all(r.json()["payment_confirmed"] for r in responses)
    s = _assert_captured_paid_registered(reg, order, attempt, pid)
    assert _confirmations(reg) == 1 and _captures(s) == 1
    assert _attempt_count(order["order_id"]) == 1


def test_stale_failure_racing_a_verified_capture_cannot_regress_it(monkeypatch, client):   # 5
    """The webhook read the attempt ('initiated') just before verify-checkout
    committed the capture; its payment.failed is then applied. The state
    machine must decide on the attempt as re-read under the order lock."""
    from app.repositories.payment_repository import PaymentRepository

    reg, order, attempt, ref = _paid_setup(client)
    stale_attempt = _db_fetchrow("SELECT * FROM payment_attempts WHERE public_attempt_number = $1", attempt["attempt_id"])
    assert stale_attempt["status"] == "initiated"
    pid = f"pay_{uuid.uuid4().hex[:14]}"
    fakes.STATE["payment_id"] = pid
    assert _verify(client, order, ref, pid).json()["payment_confirmed"] is True
    before = _snapshot(reg, order, attempt)

    async def _stale_lookup(self, gateway_order_ref):
        return stale_attempt
    monkeypatch.setattr(PaymentRepository, "get_attempt_by_gateway_ref", _stale_lookup)
    r = _payment_webhook(client, "payment.failed", order_ref=ref, payment_id=f"pay_{uuid.uuid4().hex[:14]}")
    assert r.json()["processing_status"] == "duplicate"

    after = _assert_captured_paid_registered(reg, order, attempt, pid)
    assert after == before
    assert _confirmations(reg) == 1


def test_failure_applied_first_then_verified_capture_wins(client):       # 5 (other order)
    reg, order, attempt, ref = _paid_setup(client)
    assert _payment_webhook(client, "payment.failed", order_ref=ref,
                            payment_id=f"pay_{uuid.uuid4().hex[:14]}").json()["processing_status"] == "processed"
    assert _reg_status(reg) == "payment_failed"
    pid = f"pay_{uuid.uuid4().hex[:14]}"
    fakes.STATE["payment_id"] = pid
    r = _verify(client, order, ref, pid)
    assert r.status_code == 200 and r.json()["payment_confirmed"] is True
    _assert_captured_paid_registered(reg, order, attempt, pid)


@pytest.mark.parametrize("capture_path", ["webhook", "verify_checkout", "status_check"])
def test_late_failure_then_capture_on_same_razorpay_order_is_not_lost(client, capture_path):   # 6
    reg, order, attempt, ref = _paid_setup(client)
    # First Razorpay payment on this order fails -> attempt marked failed.
    r = _payment_webhook(client, "payment.failed", order_ref=ref, payment_id=f"pay_X{uuid.uuid4().hex[:12]}")
    assert r.json()["processing_status"] == "processed"
    s = _snapshot(reg, order, attempt)
    assert s["attempt"]["status"] == "failed" and _reg_status(reg) == "payment_failed"

    # A second payment Y on the SAME Razorpay order is captured.
    pid = f"pay_Y{uuid.uuid4().hex[:12]}"
    fakes.STATE["payment_id"] = pid
    if capture_path == "webhook":
        assert _payment_webhook(client, "payment.captured", order_ref=ref, payment_id=pid).json()["processing_status"] == "processed"
    elif capture_path == "verify_checkout":
        assert _verify(client, order, ref, pid).json()["payment_confirmed"] is True
    else:
        r = _check_status(client, attempt)
        assert r.status_code == 200 and r.json()["status"] == "captured"

    s = _assert_captured_paid_registered(reg, order, attempt, pid)
    assert _confirmations(reg) == 1 and _captures(s) == 1
    assert _attempt_count(order["order_id"]) == 1


@pytest.mark.parametrize("seat_gone_sql", [
    "UPDATE registrations SET hold_expires_at = now() - interval '1 minute' WHERE registration_id = $1",
    "UPDATE registrations SET status = 'cancelled', cancelled_at = now() WHERE registration_id = $1",
])
def test_late_capture_when_seat_no_longer_confirmable_is_recorded_not_registered(client, seat_gone_sql):   # 7
    reg, order, attempt, ref = _paid_setup(client)
    _payment_webhook(client, "payment.failed", order_ref=ref, payment_id=f"pay_X{uuid.uuid4().hex[:12]}")
    _db_exec(seat_gone_sql, reg["registration_id"])
    pid = f"pay_Y{uuid.uuid4().hex[:12]}"
    assert _payment_webhook(client, "payment.captured", order_ref=ref, payment_id=pid).json()["processing_status"] == "processed"

    s = _snapshot(reg, order, attempt)
    assert s["attempt"]["status"] == "captured" and s["attempt"]["gateway_payment_ref"] == pid
    assert s["order"]["status"] == "paid" and s["order"]["amount_paid"] == s["order"]["final_amount"]
    assert s["registration"]["status"] != "registered"
    assert _confirmations(reg) == 0
    assert _db_fetchval(
        "SELECT count(*) FROM payment_exceptions WHERE exception_type = 'PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY' "
        "AND attempt_id = $1 AND status = 'open'", s["attempt"]["id"]) == 1


@pytest.mark.parametrize("late_event", ["payment.failed", "payment.authorized"])
def test_late_failure_or_pending_after_capture_cannot_regress(client, late_event):   # 8, 9
    reg, order, attempt, ref = _paid_setup(client)
    pid = f"pay_{uuid.uuid4().hex[:14]}"
    fakes.STATE["payment_id"] = pid
    assert _verify(client, order, ref, pid).json()["payment_confirmed"] is True
    before = _snapshot(reg, order, attempt)
    r = _payment_webhook(client, late_event, order_ref=ref, payment_id=f"pay_{uuid.uuid4().hex[:14]}")
    assert r.json()["processing_status"] == "duplicate"
    after = _snapshot(reg, order, attempt)
    assert after == before
    assert after["attempt"]["status"] == "captured" and after["registration"]["status"] == "registered"


def test_invalid_signature_changes_no_state_at_all(client):              # 10
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    r = _verify(client, order, ref, "pay_x", signature="deadbeef")
    assert r.status_code == 400 and r.json()["detail"] == "checkout_signature_invalid"
    assert _snapshot(reg, order, attempt) == before


def test_razorpay_api_failure_during_verify_is_502_and_changes_nothing(client):   # 11
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    fakes.STATE["payments_raises"] = True
    r = _verify(client, order, ref, "pay_x")
    assert r.status_code == 502 and r.json()["detail"] == "payment_gateway_error"
    assert "4111" not in r.text and "payer@" not in r.text
    assert _snapshot(reg, order, attempt) == before


def test_currency_mismatch_is_rejected_and_changes_nothing(client):      # 12
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    fakes.STATE["payments_currency_override"] = "USD"
    r = _verify(client, order, ref, "pay_x")
    assert r.status_code == 400 and r.json()["detail"] == "checkout_amount_mismatch"
    assert _snapshot(reg, order, attempt) == before


def test_wrong_deployment_mode_fails_closed_and_changes_nothing(monkeypatch, client):   # 13
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    fakes.set_razorpay_live_env(monkeypatch)   # this TEST order can no longer be served
    r = _verify(client, order, ref, "pay_x")
    assert r.status_code == 400 and r.json()["detail"] == "checkout_signature_invalid"
    assert _snapshot(reg, order, attempt) == before
    assert not any(c["method"] == "order.payments" for c in fakes.CALLS)


# ── Step 6: webhook authentication, atomic claim, retry horizon ──────────

def _signed(body, secret="whsec_fake"):
    import hashlib
    import hmac as _hmac
    raw = body if isinstance(body, bytes) else json.dumps(body, separators=(",", ":")).encode()
    return raw, _hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()


def _event_body(event, *, order_ref, payment_id, created_at=None, with_order_entity=False):
    import time
    payload = {"payment": {"entity": {
        "id": payment_id, "order_id": order_ref, "amount": 100, "currency": "INR",
        "status": {"payment.captured": "captured", "order.paid": "captured"}.get(event, "failed"),
    }}}
    if with_order_entity:
        payload["order"] = {"entity": {"id": order_ref, "amount": 100, "amount_paid": 100,
                                       "currency": "INR", "status": "paid"}}
    return {"entity": "event", "event": event, "contains": list(payload), "payload": payload,
            "created_at": int(created_at if created_at is not None else time.time())}


def _post(client, raw, *, signature, event_id, route="test"):
    headers = {"X-Razorpay-Event-Id": event_id, "Content-Type": "application/json"}
    if signature is not None:
        headers["X-Razorpay-Signature"] = signature
    return client.post(f"/api/v1/payment-gateways/razorpay/{route}/webhook", content=raw, headers=headers)


def _evt():
    return f"evt_{uuid.uuid4().hex}"


def _pid():
    return f"pay_{uuid.uuid4().hex[:14]}"


def _row_status(gateway_event_id):
    return _db_fetchval(
        "SELECT processing_status FROM payment_webhook_events WHERE gateway = 'razorpay' AND gateway_event_id = $1",
        gateway_event_id,
    )


def test_max_age_default_covers_razorpay_24h_retry_horizon():
    from app.config import Settings
    default = Settings.model_fields["payment_webhook_max_age_seconds"].default
    assert default == 90000 and default > 24 * 3600


def test_step6_valid_payment_captured_is_processed(client):                  # 1, 18
    reg, order, attempt, ref = _paid_setup(client)
    pid, evt = _pid(), _evt()
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=pid))
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 200 and r.json()["processing_status"] == "processed"
    assert _row_status(evt) == "processed"
    _assert_captured_paid_registered(reg, order, attempt, pid)


def test_step6_valid_order_paid_is_processed_and_idempotent(client):         # 2
    reg, order, attempt, ref = _paid_setup(client)
    pid = _pid()
    raw, sig = _signed(_event_body("order.paid", order_ref=ref, payment_id=pid, with_order_entity=True))
    r = _post(client, raw, signature=sig, event_id=_evt())
    assert r.status_code == 200 and r.json()["processing_status"] == "processed"
    s = _assert_captured_paid_registered(reg, order, attempt, pid)
    # payment.captured for the same payment (different event id) changes nothing
    raw2, sig2 = _signed(_event_body("payment.captured", order_ref=ref, payment_id=pid))
    assert _post(client, raw2, signature=sig2, event_id=_evt()).json()["processing_status"] == "duplicate"
    assert _snapshot(reg, order, attempt) == s
    assert _confirmations(reg) == 1 and _captures(s) == 1


def test_step6_valid_payment_failed_keeps_failure_behaviour(client):         # 3
    reg, order, attempt, ref = _paid_setup(client)
    raw, sig = _signed(_event_body("payment.failed", order_ref=ref, payment_id=_pid()))
    r = _post(client, raw, signature=sig, event_id=_evt())
    assert r.status_code == 200 and r.json()["processing_status"] == "processed"
    s = _snapshot(reg, order, attempt)
    assert s["attempt"]["status"] == "failed" and s["order"]["status"] != "paid"
    assert _reg_status(reg) == "payment_failed"


@pytest.mark.parametrize("signature", [
    None,                          # 4: header missing
    "",                            # 4: header empty
    "deadbeef",                    # 6: malformed (wrong length)
    "zz" * 32,                     # 6: malformed (not hex)
    "INVALID",                     # 6: malformed
])
def test_step6_missing_or_malformed_signature_is_400_without_claim(client, signature):
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    raw, _ = _signed(_event_body("payment.captured", order_ref=ref, payment_id=_pid()))
    evt = _evt()
    r = _post(client, raw, signature=signature, event_id=evt)
    assert r.status_code == 400 and r.json() == {"detail": "invalid_signature"}
    assert _event_rows(evt) == 0
    assert _snapshot(reg, order, attempt) == before


@pytest.mark.parametrize("secret", ["whsec_WRONG", "live_whsec_fake"])
def test_step6_wrong_secret_is_400_without_claim(client, secret):           # 5, 19
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=_pid()), secret=secret)
    evt = _evt()
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 400 and r.json() == {"detail": "invalid_signature"}
    assert "whsec" not in r.text
    assert _event_rows(evt) == 0
    assert _snapshot(reg, order, attempt) == before


def test_step6_invalid_first_delivery_cannot_poison_the_event_id(client):   # 7
    reg, order, attempt, ref = _paid_setup(client)
    pid, evt = _pid(), _evt()
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=pid))
    assert _post(client, raw, signature="00" + sig[2:], event_id=evt).status_code == 400
    assert _event_rows(evt) == 0
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 200 and r.json()["processing_status"] == "processed"
    _assert_captured_paid_registered(reg, order, attempt, pid)


def test_step6_duplicate_valid_event_id_changes_state_once(client):         # 8
    reg, order, attempt, ref = _paid_setup(client)
    pid, evt = _pid(), _evt()
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=pid))
    assert _post(client, raw, signature=sig, event_id=evt).json()["processing_status"] == "processed"
    s = _snapshot(reg, order, attempt)
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 200 and r.json()["processing_status"] == "duplicate"
    assert _snapshot(reg, order, attempt) == s
    assert _event_rows(evt) == 1 and _captures(s) == 1 and _confirmations(reg) == 1


def test_step6_concurrent_same_event_id_is_processed_once(client):          # 9
    from concurrent.futures import ThreadPoolExecutor

    reg, order, attempt, ref = _paid_setup(client)
    pid, evt = _pid(), _evt()
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=pid))
    with ThreadPoolExecutor(max_workers=5) as pool:
        responses = list(pool.map(lambda _: _post(client, raw, signature=sig, event_id=evt), range(5)))
    assert [r.status_code for r in responses] == [200] * 5, [r.text for r in responses]
    statuses = sorted(r.json()["processing_status"] for r in responses)
    assert statuses == ["duplicate"] * 4 + ["processed"]
    s = _assert_captured_paid_registered(reg, order, attempt, pid)
    assert _event_rows(evt) == 1 and _captures(s) == 1 and _confirmations(reg) == 1


def test_step6_processing_failure_rolls_back_claim_and_retry_succeeds(monkeypatch, client):   # 10
    from app.repositories.payment_repository import PaymentRepository

    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    pid, evt = _pid(), _evt()
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=pid))

    real_mark_paid = PaymentRepository.mark_order_paid
    failures = {"left": 1}

    async def _failing_once(self, order_id, amount_paid):
        if failures["left"]:
            failures["left"] -= 1
            raise RuntimeError("simulated database failure")
        return await real_mark_paid(self, order_id, amount_paid)

    monkeypatch.setattr(PaymentRepository, "mark_order_paid", _failing_once)
    monkeypatch.setattr(client._transport, "raise_server_exceptions", False)
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 500
    assert _event_rows(evt) == 0                       # the claim rolled back
    assert _snapshot(reg, order, attempt) == before    # and so did the partial capture

    r = _post(client, raw, signature=sig, event_id=evt)   # Razorpay's retry, same event id
    assert r.status_code == 200 and r.json()["processing_status"] == "processed"
    assert _row_status(evt) == "processed"
    _assert_captured_paid_registered(reg, order, attempt, pid)


def test_step6_signed_retry_inside_24h_horizon_is_accepted(monkeypatch, client):   # 11
    import time
    from app.config import get_settings
    monkeypatch.setenv("PAYMENT_WEBHOOK_MAX_AGE_SECONDS", "90000")
    get_settings.cache_clear()
    reg, order, attempt, ref = _paid_setup(client)
    pid = _pid()
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=pid,
                                   created_at=int(time.time()) - 6 * 3600))   # 6 hours old
    r = _post(client, raw, signature=sig, event_id=_evt())
    assert r.status_code == 200 and r.json()["processing_status"] == "processed"
    _assert_captured_paid_registered(reg, order, attempt, pid)


@pytest.mark.parametrize("offset,error_code", [
    (-(90000 + 60), "timestamp_stale"),     # 12: beyond the maximum age
    (+120, "timestamp_future_skew"),        # 13: beyond the 30 s future skew
])
def test_step6_timestamp_outside_policy_is_rejected(monkeypatch, client, offset, error_code):
    import time
    from app.config import get_settings
    monkeypatch.setenv("PAYMENT_WEBHOOK_MAX_AGE_SECONDS", "90000")
    get_settings.cache_clear()
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    evt = _evt()
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=_pid(),
                                   created_at=int(time.time()) + offset))
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 200 and r.json()["processing_status"] == "rejected"
    assert _db_fetchval("SELECT error_code FROM payment_webhook_events WHERE gateway_event_id = $1", evt) == error_code
    assert _snapshot(reg, order, attempt) == before


def test_step6_malformed_json_with_valid_signature_is_safe(client):         # 15
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    evt = _evt()
    raw, sig = _signed(b'{"event": "payment.captured", "payload": ')
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 200 and r.json()["processing_status"] == "rejected"
    assert _event_rows(evt) == 0
    assert _snapshot(reg, order, attempt) == before


def test_step6_unknown_event_type_is_permanently_rejected(client):          # 16
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    evt = _evt()
    raw, sig = _signed(_event_body("payment.dispute.created", order_ref=ref, payment_id=_pid()))
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 200 and r.json()["processing_status"] == "rejected"
    assert _db_fetchval("SELECT error_code FROM payment_webhook_events WHERE gateway_event_id = $1", evt) == "unknown_event_type"
    assert _snapshot(reg, order, attempt) == before


def test_step6_unknown_razorpay_order_is_rejected_safely(client):           # 17
    reg, order, attempt, _ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    evt = _evt()
    raw, sig = _signed(_event_body("payment.captured", order_ref=f"order_{uuid.uuid4().hex[:14]}", payment_id=_pid()))
    r = _post(client, raw, signature=sig, event_id=evt)
    assert r.status_code == 200 and r.json()["processing_status"] == "rejected"
    assert _db_fetchval("SELECT error_code FROM payment_webhook_events WHERE gateway_event_id = $1", evt) == "unknown_gateway_order"
    assert _snapshot(reg, order, attempt) == before


def test_step6_test_signed_delivery_on_live_route_fails_closed_without_claim(client):   # 19
    reg, order, attempt, ref = _paid_setup(client)
    before = _snapshot(reg, order, attempt)
    evt = _evt()
    raw, sig = _signed(_event_body("payment.captured", order_ref=ref, payment_id=_pid()))
    r = _post(client, raw, signature=sig, event_id=evt, route="live")
    assert r.status_code == 400 and r.json() == {"detail": "invalid_signature"}
    assert _event_rows(evt) == 0
    assert _snapshot(reg, order, attempt) == before
