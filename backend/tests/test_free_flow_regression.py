"""Free-event flow must be untouched by the Razorpay / refund sprint.

Admin create + publish -> alumnus registers -> confirmed immediately, with
NO payment order / attempt / config created. Free cancellation works and
creates no refund object.
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


def _bearer(identity):
    from app.middleware.auth import make_access_token
    return {"Authorization": f"Bearer {make_access_token(dict(identity))}"}


def _db(query, *args):
    import asyncio
    import asyncpg
    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            if query.strip().lower().startswith("select"):
                return await conn.fetchval(query, *args)
            return await conn.execute(query, *args)
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
            ident["user_type"], ident["ref_id"], ident["graduation_year"],
        )
    _db(
        """INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
           VALUES ($1,'platform_admin','test_fixture_bootstrap')
           ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING""",
        _FIXTURE_ADMIN["firebase_uid"],
    )


def _mk_free_event(client, suffix):
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"FREE {suffix}", "description": "x",
            "start_datetime": "2027-03-01T08:00:00+05:30",
            "end_datetime": "2027-03-01T10:00:00+05:30",
            "location_text": "V", "is_virtual": False, "capacity": 50, "is_free": True,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    eid = r.json()["event_id"]
    assert client.post(f"/api/v1/admin/events/{eid}/publish", headers=_bearer(_FIXTURE_ADMIN)).status_code == 200
    return eid


def test_free_registration_confirms_immediately_no_payment_objects(client):
    eid = _mk_free_event(client, uuid.uuid4().hex[:8])
    r = client.post(f"/api/v1/events/{eid}/register", json={}, headers=_bearer(_TEST_ALUMNI))
    assert r.status_code == 201, r.text
    reg = r.json()
    assert reg["status"] == "registered"
    rid = reg["registration_id"]

    assert _db("SELECT count(*) FROM payment_orders WHERE registration_id=$1", rid) == 0
    assert _db("SELECT count(*) FROM payment_configurations WHERE event_id=$1", eid) == 0
    assert _db(
        "SELECT count(*) FROM payment_attempts pa JOIN payment_orders po ON pa.order_id=po.id WHERE po.registration_id=$1",
        rid,
    ) == 0


def test_free_registration_cancellation_no_refund_object(client):
    eid = _mk_free_event(client, uuid.uuid4().hex[:8])
    h = _bearer(_TEST_ALUMNI)
    reg = client.post(f"/api/v1/events/{eid}/register", json={}, headers=h).json()
    rid = reg["registration_id"]
    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "none"
    assert _db("SELECT status FROM registrations WHERE registration_id=$1", rid) == "cancelled"
    assert _db("SELECT count(*) FROM payment_refunds WHERE registration_id=$1", rid) == 0
