"""Refund domain — attendee cancellation + full refund.

Exercised end-to-end against local Postgres through the ASGI app using the
deterministic sandbox gateway (which now supports REFUND/QUERY_REFUND
deterministically), so the refund persistence / idempotency / concurrency /
ownership / state machine is proven without a real provider. The Razorpay
adapter's own refund() / query_refund() mapping is unit-tested separately in
test_razorpay_gateway.py.
"""
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

import pytest

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


def _db(query, *args, val=False):
    import asyncio
    import asyncpg
    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            if query.strip().lower().startswith(("select",)):
                return await (conn.fetchval(query, *args) if val else conn.fetch(query, *args))
            return await conn.execute(query, *args)
        finally:
            await conn.close()

    return asyncio.run(_run())


@pytest.fixture(autouse=True)
def _seed():
    for ident in (_TEST_ALUMNI, _TEST_ALUMNI_2, _FIXTURE_ADMIN):
        _db(
            """INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
               VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (firebase_uid) DO NOTHING""",
            ident["firebase_uid"], ident["email"], ident["fullname"],
            ident["user_type"], ident["ref_id"], ident["graduation_year"],
        )
    _db(
        """INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
           VALUES ($1,'platform_admin','test_fixture_bootstrap')
           ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING""",
        _FIXTURE_ADMIN["firebase_uid"],
    )


def _mk_event(client, suffix, *, is_free, base_amount="1.00"):
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"REFUND {suffix}", "description": "pytest",
            "start_datetime": "2027-03-01T08:00:00+05:30",
            "end_datetime": "2027-03-01T10:00:00+05:30",
            "location_text": "V", "is_virtual": False, "capacity": 20,
            "is_free": is_free, "ticket_price": None if is_free else base_amount,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    eid = r.json()["event_id"]
    assert client.post(f"/api/v1/admin/events/{eid}/publish", headers=_bearer(_FIXTURE_ADMIN)).status_code == 200
    if not is_free:
        r = client.post(
            "/api/v1/dev/diagnostics/payments/configuration/import",
            json={
                "configuration_key": f"rf-{suffix}", "event_id": eid,
                "base_amount": base_amount, "gst_enabled": False,
                "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15,
                "gateway": "deterministic_sandbox",
            },
            headers=_ADMIN,
        )
        assert r.status_code == 200, r.text
    return eid


def _paid_registered(client, event_id, identity=_TEST_ALUMNI):
    h = _bearer(identity)
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=h).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"k-{uuid.uuid4().hex}"}, headers=h,
    ).json()
    att = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "SUCCESS"}, headers=h,
    ).json()
    assert att["status"] == "captured", att
    return reg, order


# ── happy path ────────────────────────────────────────────────────────

def test_full_refund_of_captured_payment(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]

    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"cancel-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "refund_processed"
    assert str(body["amount"]) in ("1.00", "1.0")
    assert body["currency"] == "INR"

    assert _db("SELECT status FROM registrations WHERE registration_id=$1", rid, val=True) == "cancelled"
    row = _db("SELECT amount, status, provider_refund_id, provider_payment_id FROM payment_refunds WHERE registration_id=$1", rid)[0]
    assert str(row["amount"]) == "1.00"
    assert row["status"] == "processed"
    assert row["provider_refund_id"] and row["provider_payment_id"]

    g = client.get(f"/api/v1/registrations/{rid}/refund", headers=_bearer())
    assert g.status_code == 200
    assert g.json()["status"] == "refund_processed"


def test_refund_amount_equals_captured_amount(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False, base_amount="1.00")
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]
    client.post(f"/api/v1/registrations/{rid}/cancel",
                json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=_bearer())
    refund_amt = _db("SELECT amount FROM payment_refunds WHERE registration_id=$1", rid, val=True)
    order_final = _db("SELECT final_amount FROM payment_orders WHERE public_order_number=$1", order["order_id"], val=True)
    assert refund_amt == order_final


# ── rejections ────────────────────────────────────────────────────────

def test_cancel_non_captured_registration_rejected(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    h = _bearer()
    reg = client.post(f"/api/v1/events/{eid}/register", json={}, headers=h).json()
    # seat_held, nothing captured
    r = client.post(f"/api/v1/registrations/{reg['registration_id']}/cancel",
                    json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=h)
    assert r.status_code == 409
    assert r.json()["detail"] == "registration_not_cancellable"
    assert _db("SELECT count(*) FROM payment_refunds WHERE registration_id=$1", reg["registration_id"], val=True) == 0


def test_cross_user_cancel_denied(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid, identity=_TEST_ALUMNI)
    r = client.post(f"/api/v1/registrations/{reg['registration_id']}/cancel",
                    json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=_bearer(_TEST_ALUMNI_2))
    assert r.status_code == 404
    assert _db("SELECT status FROM registrations WHERE registration_id=$1", reg["registration_id"], val=True) == "registered"


def test_cross_user_refund_status_denied(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid, identity=_TEST_ALUMNI)
    client.post(f"/api/v1/registrations/{reg['registration_id']}/cancel",
                json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=_bearer(_TEST_ALUMNI))
    r = client.get(f"/api/v1/registrations/{reg['registration_id']}/refund", headers=_bearer(_TEST_ALUMNI_2))
    assert r.status_code == 404


# ── idempotency / concurrency ────────────────────────────────────────

def test_duplicate_cancel_same_key_is_idempotent(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]
    key = f"cancel-{uuid.uuid4().hex}"
    r1 = client.post(f"/api/v1/registrations/{rid}/cancel", json={"idempotency_key": key}, headers=_bearer())
    r2 = client.post(f"/api/v1/registrations/{rid}/cancel", json={"idempotency_key": key}, headers=_bearer())
    assert r1.status_code == 200 and r2.status_code == 200
    assert r1.json()["refund_id"] == r2.json()["refund_id"]
    assert _db("SELECT count(*) FROM payment_refunds WHERE payment_order_id=(SELECT id FROM payment_orders WHERE public_order_number=$1)",
               order["order_id"], val=True) == 1


def test_repeated_cancel_different_keys_one_logical_refund(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]
    r1 = client.post(f"/api/v1/registrations/{rid}/cancel", json={"idempotency_key": f"a-{uuid.uuid4().hex}"}, headers=_bearer())
    r2 = client.post(f"/api/v1/registrations/{rid}/cancel", json={"idempotency_key": f"b-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r1.status_code == 200 and r2.status_code == 200
    assert _db("SELECT count(*) FROM payment_refunds WHERE payment_order_id=(SELECT id FROM payment_orders WHERE public_order_number=$1)",
               order["order_id"], val=True) == 1


def test_concurrent_cancel_only_one_logical_refund(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]
    key = f"cancel-{uuid.uuid4().hex}"

    def _cancel():
        return client.post(f"/api/v1/registrations/{rid}/cancel", json={"idempotency_key": key}, headers=_bearer())

    with ThreadPoolExecutor(max_workers=5) as pool:
        futs = [pool.submit(_cancel) for _ in range(5)]
        try:
            results = [f.result(timeout=15) for f in futs]
        except FutureTimeoutError:
            pytest.fail("concurrent cancel hung")

    assert all(r.status_code == 200 for r in results), [r.status_code for r in results]
    assert all(r.json()["status"].startswith("refund_") for r in results)
    n = _db("SELECT count(*) FROM payment_refunds WHERE payment_order_id=(SELECT id FROM payment_orders WHERE public_order_number=$1)",
            order["order_id"], val=True)
    assert n == 1, f"expected exactly one refund row, got {n}"


# ── provider failure ─────────────────────────────────────────────────

def test_provider_refund_failure_leaves_safe_state(client, monkeypatch):
    from app.gateways.base import GatewayError
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]

    def _boom(*a, **k):
        raise GatewayError("simulated provider outage")

    monkeypatch.setattr(DeterministicSandboxGateway, "refund", _boom)
    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "refund_failed"
    # registration still cancelled (seat released), refund row is 'failed' and retryable
    assert _db("SELECT status FROM registrations WHERE registration_id=$1", rid, val=True) == "cancelled"
    assert _db("SELECT status FROM payment_refunds WHERE registration_id=$1", rid, val=True) == "failed"


# ── free cancellation ────────────────────────────────────────────────

def test_free_registration_cancellation_no_refund(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=True)
    h = _bearer()
    reg = client.post(f"/api/v1/events/{eid}/register", json={}, headers=h).json()
    assert reg["status"] == "registered"
    r = client.post(f"/api/v1/registrations/{reg['registration_id']}/cancel",
                    json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "none"
    assert _db("SELECT status FROM registrations WHERE registration_id=$1", reg["registration_id"], val=True) == "cancelled"
    assert _db("SELECT count(*) FROM payment_refunds WHERE registration_id=$1", reg["registration_id"], val=True) == 0


# ── TEST/LIVE mode separation ─────────────────────────────────────────────

def test_full_refund_snapshots_test_payment_mode(client):
    """Every refund created through the normal flow snapshots the mode the
    payment was actually captured under. The default here is 'test' — no
    LIVE credentials exist anywhere in this project (see
    docs/payments/RAZORPAY_LOCAL_CREDENTIAL_CONFIGURATION_REPORT.md)."""
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, _ = _paid_registered(client, eid)
    rid = reg["registration_id"]
    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"cancel-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 200, r.text
    assert r.json()["payment_mode"] == "test"
    assert r.json()["real_money"] is False
    assert _db("SELECT payment_mode FROM payment_refunds WHERE registration_id=$1", rid, val=True) == "test"


def test_cross_mode_refund_is_structurally_rejected(client):
    """Defence-in-depth: even if a data-integrity bug ever let a captured
    attempt's payment_mode disagree with its order's (impossible through the
    normal API — both descend from the same config snapshot), refund_service
    must fail closed rather than refund through the wrong credential
    profile. Simulated here by forcing that disagreement directly in the DB,
    since the API itself cannot produce it."""
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]

    _db(
        """UPDATE payment_attempts SET payment_mode = 'live'
           WHERE order_id = (SELECT id FROM payment_orders WHERE public_order_number = $1)
             AND status = 'captured'""",
        order["order_id"],
    )

    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"cancel-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 409, r.text
    assert r.json()["detail"] == "refund_mode_mismatch"

    # Fails closed before any mutation: no refund row, registration untouched.
    assert _db("SELECT count(*) FROM payment_refunds WHERE registration_id=$1", rid, val=True) == 0
    assert _db("SELECT status FROM registrations WHERE registration_id=$1", rid, val=True) == "registered"


# ── cancellation-aware order message + cancellation/refund timeline ────────

_CONFIRMED_HISTORY = ["Payment successful", "Registration confirmed"]


def _cancel(client, rid):
    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"cancel-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 200, r.text
    return r.json()


def _timeline(client, order_id):
    r = client.get(f"/api/v1/payment-orders/{order_id}/timeline", headers=_bearer())
    assert r.status_code == 200, r.text
    return r.json()["entries"]


def _at(entries, event_type):
    from datetime import datetime
    at = next(e["at"] for e in entries if e["event_type"] == event_type)
    return datetime.fromisoformat(at.replace("Z", "+00:00"))


def _refund_row(rid):
    return _db("SELECT * FROM payment_refunds WHERE registration_id=$1", rid)[0]


def test_order_message_is_confirmed_only_while_registration_is_active(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    path = f"/api/v1/payment-orders/{order['order_id']}"

    paid = client.get(path, headers=_bearer()).json()
    assert paid["status"] == "paid" and paid["registration_status"] == "registered"
    assert paid["safe_message"] == "Payment complete. Your registration is confirmed."
    # The gateway snapshot tells the internal sandbox apart from Razorpay TEST.
    assert paid["gateway"] == "deterministic_sandbox"
    assert paid["payment_mode"] == "test"

    _cancel(client, reg["registration_id"])
    cancelled = client.get(path, headers=_bearer()).json()
    # The refunded order is still 'paid', but must not read as confirmed.
    assert cancelled["status"] == "paid" and cancelled["registration_status"] == "cancelled"
    assert cancelled["safe_message"] == "Your registration is cancelled."
    assert "confirmed" not in cancelled["safe_message"]


@pytest.mark.parametrize(
    "order_status, expected_message",
    [
        ("expired", "This payment session expired. Please register again."),
        ("cancelled", "This order was cancelled."),
    ],
)
def test_order_state_message_survives_a_cancelled_registration(client, order_status, expected_message):
    """A seat-hold expiry cancels the registration and expires the order
    together. The order's own message says why and what to do next, so the
    generic cancelled-registration message must not replace it."""
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    h = _bearer()
    reg = client.post(f"/api/v1/events/{eid}/register", json={}, headers=h).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"k-{uuid.uuid4().hex}"}, headers=h,
    ).json()
    # The state the lifecycle sweep leaves behind, set on this test's own rows.
    _db("UPDATE payment_orders SET status=$2 WHERE public_order_number=$1", order["order_id"], order_status)
    _db("UPDATE registrations SET status='cancelled', cancelled_at=now() WHERE registration_id=$1",
        reg["registration_id"])

    view = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=h).json()
    assert view["status"] == order_status and view["registration_status"] == "cancelled"
    assert view["safe_message"] == expected_message
    assert view["can_pay"] is False


def test_timeline_of_active_paid_registration_has_no_cancellation_or_refund(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    _, order = _paid_registered(client, eid)
    entries = _timeline(client, order["order_id"])
    assert [e["label"] for e in entries][-2:] == _CONFIRMED_HISTORY
    assert not any(
        e["event_type"] == "registration_cancelled" or e["event_type"].startswith("refund_") for e in entries
    )


def test_timeline_cancelled_with_processed_refund(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]
    assert _cancel(client, rid)["status"] == "refund_processed"

    r = client.get(f"/api/v1/payment-orders/{order['order_id']}/timeline", headers=_bearer())
    entries = r.json()["entries"]
    # History is appended to, never rewritten: "Registration confirmed" stays.
    assert [e["label"] for e in entries][-5:] == _CONFIRMED_HISTORY + [
        "Registration cancelled", "Refund requested", "Refund processed",
    ]
    # No authoritative timestamp survives for the provider-processing step.
    assert "Refund processing" not in [e["label"] for e in entries]
    assert [e["at"] for e in entries] == sorted(e["at"] for e in entries)

    # Every timestamp is the stored backend value, not a generated one.
    refund = _refund_row(rid)
    assert _at(entries, "registration_cancelled") == _db(
        "SELECT cancelled_at FROM registrations WHERE registration_id=$1", rid, val=True)
    assert _at(entries, "refund_requested") == refund["requested_at"]
    assert _at(entries, "refund_processed") == refund["finalized_at"]

    # Provider identifiers stay out of the attendee-facing timeline.
    assert refund["provider_refund_id"] not in r.text
    assert refund["provider_payment_id"] not in r.text


def test_timeline_cancelled_with_pending_refund_shows_only_refund_requested(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]
    _cancel(client, rid)
    # A refund row whose provider call has not been confirmed yet.
    _db("UPDATE payment_refunds SET status='pending', updated_at=NULL, finalized_at=NULL WHERE registration_id=$1", rid)

    labels = [e["label"] for e in _timeline(client, order["order_id"])]
    assert labels[-4:] == _CONFIRMED_HISTORY + ["Registration cancelled", "Refund requested"]
    assert "Refund processed" not in labels and "Refund processing" not in labels


def test_timeline_cancelled_with_processing_refund(client, monkeypatch):
    from app.gateways.base import NormalizedRefundResult, NormalizedRefundStatus
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]

    def _accepted_not_settled(self, *, amount_minor, currency, **_):
        return NormalizedRefundResult(
            provider_refund_id="sbx_rfnd_async", status=NormalizedRefundStatus.REFUND_PENDING,
            amount_minor=amount_minor, currency=currency, raw_status="pending",
        )

    monkeypatch.setattr(DeterministicSandboxGateway, "refund", _accepted_not_settled)
    body = _cancel(client, rid)
    assert body["status"] == "refund_pending"
    assert body["safe_message"] == "Your registration is cancelled. Your refund is being processed."

    refund = _refund_row(rid)
    assert refund["status"] == "processing"
    entries = _timeline(client, order["order_id"])
    assert [e["label"] for e in entries][-5:] == _CONFIRMED_HISTORY + [
        "Registration cancelled", "Refund requested", "Refund processing",
    ]
    assert _at(entries, "refund_processing") == refund["updated_at"]
    assert "Refund processed" not in [e["label"] for e in entries]


def test_timeline_cancelled_with_failed_refund_keeps_registration_cancelled(client, monkeypatch):
    from app.gateways.base import GatewayError
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]

    def _boom(*a, **k):
        raise GatewayError("simulated provider outage")

    monkeypatch.setattr(DeterministicSandboxGateway, "refund", _boom)
    assert _cancel(client, rid)["status"] == "refund_failed"

    entries = _timeline(client, order["order_id"])
    assert [e["label"] for e in entries][-5:] == _CONFIRMED_HISTORY + [
        "Registration cancelled", "Refund requested", "Refund failed",
    ]
    assert "Refund processed" not in [e["label"] for e in entries]
    assert _at(entries, "refund_failed") == _refund_row(rid)["updated_at"]

    # A failed refund never puts the registration back to confirmed.
    view = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=_bearer()).json()
    assert view["registration_status"] == "cancelled"
    assert view["safe_message"] == "Your registration is cancelled."


def test_timeline_never_infers_a_refund_from_cancellation_alone(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, order = _paid_registered(client, eid)
    rid = reg["registration_id"]
    _cancel(client, rid)
    _db("DELETE FROM payment_refunds WHERE registration_id=$1", rid)

    entries = _timeline(client, order["order_id"])
    assert [e["label"] for e in entries][-3:] == _CONFIRMED_HISTORY + ["Registration cancelled"]
    assert not any(e["event_type"].startswith("refund_") for e in entries)
