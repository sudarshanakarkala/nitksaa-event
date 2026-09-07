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
    assert "secret" not in json.dumps(attempt).lower() or "key_secret" not in json.dumps(attempt)
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

def _webhook(client, event, *, order_ref, event_id, amount_paise=100, created_at=None, mangle=False, bad_sig=False):
    raw, sig = fakes.webhook_body_and_sig(event, order_id=order_ref, amount_paise=amount_paise, created_at=created_at)
    if mangle:
        raw = raw + b" "
    if bad_sig:
        sig = "00" + sig[2:]
    return client.post(
        "/api/v1/payment-gateways/razorpay/webhook",
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
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}", bad_sig=True)
    assert r.json()["processing_status"] == "rejected"
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) != "paid"


def test_webhook_tampered_body_rejected(client):
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}", mangle=True)
    assert r.json()["processing_status"] == "rejected"


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
    import time
    event_id = _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    reg, order, attempt = _register_and_initiate(client, event_id)
    ref = attempt["checkout"]["provider_order_id"]
    r = _webhook(client, "payment.captured", order_ref=ref, event_id=f"evt_{uuid.uuid4().hex}",
                 created_at=int(time.time()) - 4000)
    assert r.json()["processing_status"] == "rejected"
    assert _db_fetchval("SELECT status FROM payment_orders WHERE public_order_number=$1", order["order_id"]) != "paid"


def test_webhook_unknown_order_rejected(client):
    _mk_razorpay_event(client, uuid.uuid4().hex[:8])
    r = _webhook(client, "payment.captured", order_ref="order_NOPE", event_id=f"evt_{uuid.uuid4().hex}")
    assert r.json()["processing_status"] == "rejected"
