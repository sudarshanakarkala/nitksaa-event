"""Per-event gateway selection (migration 021).

payment_configurations.gateway is the admin's choice; payment_orders.gateway
is snapshotted at order-creation time. The global settings.payment_gateway_mode
no longer drives dispatch. Existing sandbox events (incl. event_id=392 if
present) are unaffected.
"""
import uuid

import pytest

_FIXTURE_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_043", "sub": "fixture.admin.rbac@nitksaa.dev",
    "email": "fixture.admin.rbac@nitksaa.dev", "fullname": "Fixture Admin RBAC Test",
    "user_type": "alumni", "ref_id": "NITK2018CS043", "graduation_year": 2018,
}
_TEST_ALUMNI = {
    "firebase_uid": "TEST_ALUMNI_UID_001", "sub": "ravi.test@nitksaa.dev",
    "email": "ravi.test@nitksaa.dev", "fullname": "Ravi Shankar Test",
    "user_type": "alumni", "ref_id": "NITK2020CS001", "graduation_year": 2020,
}
_ADMIN = {"X-Dev-User": "admin"}


def _bearer(identity):
    from app.middleware.auth import make_access_token
    return {"Authorization": f"Bearer {make_access_token(dict(identity))}"}


def _db(query, *args, val=True):
    import asyncio
    import asyncpg
    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            return await (conn.fetchval(query, *args) if val else conn.fetch(query, *args))
        finally:
            await conn.close()

    return asyncio.run(_run())


@pytest.fixture(autouse=True)
def _seed():
    for ident in (_TEST_ALUMNI, _FIXTURE_ADMIN):
        _db(
            """INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
               VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (firebase_uid) DO NOTHING""",
            ident["firebase_uid"], ident["email"], ident["fullname"],
            ident["user_type"], ident["ref_id"], ident["graduation_year"], val=True,
        )
    _db(
        """INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
           VALUES ($1,'platform_admin','test_fixture_bootstrap')
           ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING""",
        _FIXTURE_ADMIN["firebase_uid"],
    )


def _mk_event(client, suffix):
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"PEG {suffix}", "description": "x",
            "start_datetime": "2027-03-01T08:00:00+05:30",
            "end_datetime": "2027-03-01T10:00:00+05:30",
            "location_text": "V", "is_virtual": False, "capacity": 10,
            "is_free": False, "ticket_price": "1.00",
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    eid = r.json()["event_id"]
    client.post(f"/api/v1/admin/events/{eid}/publish", headers=_bearer(_FIXTURE_ADMIN))
    return eid


def test_import_defaults_gateway_to_sandbox(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8])
    r = client.post(
        "/api/v1/dev/diagnostics/payments/configuration/import",
        json={"configuration_key": f"peg-{uuid.uuid4().hex[:8]}", "event_id": eid,
              "base_amount": "1.00", "gst_enabled": False,
              "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15},
        headers=_ADMIN,
    )
    assert r.status_code == 200
    gw = _db("SELECT gateway FROM payment_configurations WHERE event_id=$1 AND status='published'", eid)
    assert gw == "deterministic_sandbox"


def test_import_accepts_razorpay_gateway(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8])
    r = client.post(
        "/api/v1/dev/diagnostics/payments/configuration/import",
        json={"configuration_key": f"peg-{uuid.uuid4().hex[:8]}", "event_id": eid,
              "base_amount": "1.00", "gst_enabled": False,
              "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15,
              "gateway": "razorpay"},
        headers=_ADMIN,
    )
    assert r.status_code == 200
    assert _db("SELECT gateway FROM payment_configurations WHERE event_id=$1 AND status='published'", eid) == "razorpay"


def test_import_rejects_unknown_gateway(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8])
    r = client.post(
        "/api/v1/dev/diagnostics/payments/configuration/import",
        json={"configuration_key": f"peg-{uuid.uuid4().hex[:8]}", "event_id": eid,
              "base_amount": "1.00", "gst_enabled": False,
              "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15,
              "gateway": "stripe"},
        headers=_ADMIN,
    )
    assert r.status_code == 422


def test_order_snapshots_config_gateway(client):
    eid = _mk_event(client, uuid.uuid4().hex[:8])
    client.post(
        "/api/v1/dev/diagnostics/payments/configuration/import",
        json={"configuration_key": f"peg-{uuid.uuid4().hex[:8]}", "event_id": eid,
              "base_amount": "1.00", "gst_enabled": False,
              "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15,
              "gateway": "deterministic_sandbox"},
        headers=_ADMIN,
    )
    h = _bearer(_TEST_ALUMNI)
    reg = client.post(f"/api/v1/events/{eid}/register", json={}, headers=h).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"k-{uuid.uuid4().hex}"}, headers=h,
    ).json()
    assert _db("SELECT gateway FROM payment_orders WHERE public_order_number=$1", order["order_id"]) == "deterministic_sandbox"


def test_existing_event_392_remains_sandbox_if_present(client):
    row = _db("SELECT gateway FROM payment_configurations WHERE event_id=392 AND status='published'")
    if row is None:
        pytest.skip("event_id=392 has no published payment config in this DB")
    assert row == "deterministic_sandbox"


def test_draft_config_validation_rejects_bad_gateway():
    from app.services.payment_config_service import validate_configuration
    errs = validate_configuration({
        "base_amount": "1.00", "gst_mode": "exclusive", "convenience_fee_type": "fixed",
        "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15, "gateway": "paypal",
    })
    assert any("gateway" in e for e in errs)
