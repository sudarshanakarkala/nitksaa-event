"""Non-alumni registration (step 3, NON_ALUMNI_REGISTRATION_DESIGN.md).

Anyone signed in can register. Alumni get name/batch/branch from their alumni
record (whatever its status); everyone else types name and phone. Phone is
required for all; a typed phone is saved on the registration only. Email is
always the sign-in email.
"""
import uuid

import pytest

from tests.test_payments import _mk_paid_event

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


def _non_alumnus():
    """A fresh non-alumni identity per test (the test database is shared)."""
    n = uuid.uuid4().hex[:10]
    return {
        "firebase_uid": f"TEST_OTHER_{n}", "sub": f"guest.{n}@example.invalid",
        "email": f"guest.{n}@example.invalid", "fullname": None,
        "user_type": "other", "ref_id": None, "graduation_year": None,
    }


def _bearer(identity):
    from app.middleware.auth import make_access_token
    return {"Authorization": f"Bearer {make_access_token(dict(identity))}"}


def _run(dsn_attr, query, *args):
    import asyncio
    import asyncpg
    from app.config import get_settings

    async def _go():
        conn = await asyncpg.connect(dsn=getattr(get_settings(), dsn_attr))
        try:
            if query.strip().lower().startswith("select"):
                return await conn.fetchrow(query, *args)
            return await conn.execute(query, *args)
        finally:
            await conn.close()

    return asyncio.run(_go())


def _db(query, *args):
    return _run("events_db_dsn", query, *args)


def _alumni_db(query, *args):
    return _run("alumni_db_dsn", query, *args)


def _seed_user(ident):
    _db(
        """INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
           VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (firebase_uid) DO NOTHING""",
        ident["firebase_uid"], ident["email"], ident["fullname"] or "",
        ident["user_type"], ident["ref_id"], ident["graduation_year"],
    )


@pytest.fixture(autouse=True)
def _seed():
    for ident in (_TEST_ALUMNI, _FIXTURE_ADMIN):
        _seed_user(ident)
    _db(
        """INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
           VALUES ($1,'platform_admin','test_fixture_bootstrap')
           ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING""",
        _FIXTURE_ADMIN["firebase_uid"],
    )


def _mk_free_event(client):
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"FREE NA {uuid.uuid4().hex[:8]}", "description": "x",
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


def _register(client, eid, ident, **body):
    return client.post(f"/api/v1/events/{eid}/register", json=body, headers=_bearer(ident))


def test_non_alumni_free_registration(client, monkeypatch):
    from app.services import email_service
    sent = {}
    real = email_service.send_confirmation_email

    async def _capture(**kw):
        sent.update(kw)
        return await real(**kw)

    monkeypatch.setattr(email_service, "send_confirmation_email", _capture)
    who = _non_alumnus()
    _seed_user(who)
    eid = _mk_free_event(client)
    r = _register(client, eid, who, fullname="  Asha Rao ", phone="+91 98450-12345", attendee_note="Veg")
    assert r.status_code == 201, r.text
    reg = r.json()
    assert reg["status"] == "registered"
    assert reg["fullname_snapshot"] == "Asha Rao"
    assert reg["email_snapshot"] == who["email"]
    assert reg["phone_snapshot"] == "+91 98450-12345"
    assert reg["ref_id"] is None
    assert reg["batch_year_snapshot"] is None and reg["branch_snapshot"] is None
    assert sent["email_to"] == who["email"]
    assert sent["fullname"] == "Asha Rao"


def test_non_alumni_paid_registration_holds_seat_then_pays(client):
    who = _non_alumnus()
    _seed_user(who)
    eid = _mk_paid_event(client, f"na-{uuid.uuid4().hex[:8]}")
    r = _register(client, eid, who, fullname="Asha Rao", phone="9845012345")
    assert r.status_code == 201, r.text
    reg = r.json()
    assert reg["status"] == "seat_held"
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"na-order-{reg['registration_id']}"},
        headers=_bearer(who),
    )
    assert r.status_code == 201, r.text


def test_non_alumni_name_required(client):
    who = _non_alumnus()
    _seed_user(who)
    eid = _mk_free_event(client)
    r = _register(client, eid, who, fullname="   ", phone="9845012345")
    assert r.status_code == 422
    assert r.json()["detail"] == "name_required"


@pytest.mark.parametrize("phone,code", [(None, "phone_required"), ("  ", "phone_required"),
                                        ("123", "phone_invalid"), ("98450abcde", "phone_invalid"),
                                        ("+1234567890123456", "phone_invalid")])
def test_phone_required_and_valid(client, phone, code):
    who = _non_alumnus()
    _seed_user(who)
    eid = _mk_free_event(client)
    r = _register(client, eid, who, fullname="Asha Rao", phone=phone)
    assert r.status_code == 422
    assert r.json()["detail"] == code


def test_alumni_prefilled_typed_phone_kept_record_unchanged(client):
    before = _alumni_db("SELECT fullname, phone FROM alumni WHERE alumni_id=$1", _TEST_ALUMNI["ref_id"])
    eid = _mk_free_event(client)
    r = _register(client, eid, _TEST_ALUMNI, fullname="Someone Else", phone="+44 7700 900123")
    assert r.status_code == 201, r.text
    reg = r.json()
    assert reg["fullname_snapshot"] == before["fullname"]  # typed name ignored for alumni
    assert reg["phone_snapshot"] == "+44 7700 900123"
    assert reg["ref_id"] == _TEST_ALUMNI["ref_id"]
    assert reg["email_snapshot"] == _TEST_ALUMNI["email"]
    after = _alumni_db("SELECT phone FROM alumni WHERE alumni_id=$1", _TEST_ALUMNI["ref_id"])
    assert after["phone"] == before["phone"]


def test_alumni_phone_falls_back_to_record(client):
    record = _alumni_db("SELECT phone FROM alumni WHERE alumni_id=$1", _TEST_ALUMNI["ref_id"])
    eid = _mk_free_event(client)
    r = _register(client, eid, _TEST_ALUMNI)
    assert r.status_code == 201, r.text
    assert r.json()["phone_snapshot"] == record["phone"]


def test_alumni_with_pending_record_registers_as_alumni(client):
    n = uuid.uuid4().hex[:8]
    ref = f"PENDING-{n}"
    who = {
        "firebase_uid": f"TEST_PENDING_{n}", "sub": f"pending.{n}@example.invalid",
        "email": f"pending.{n}@example.invalid", "fullname": "Pending Alumnus",
        "user_type": "alumni", "ref_id": ref, "graduation_year": 2024,
    }
    _alumni_db(
        """INSERT INTO alumni (alumni_id, fullname, email, phone, graduationyear, branch, registrationstatus, firebase_uid)
           VALUES ($1,'Pending Alumnus',$2,'9845099999',2024,'ECE','Pending',$3)""",
        ref, who["email"], who["firebase_uid"],
    )
    _seed_user(who)
    eid = _mk_free_event(client)

    r = client.get(f"/api/v1/events/{eid}/registration-eligibility", headers=_bearer(who))
    assert r.status_code == 200, r.text
    assert r.json()["eligibility_status"] == "eligible"

    r = _register(client, eid, who)
    assert r.status_code == 201, r.text
    reg = r.json()
    assert reg["ref_id"] == ref
    assert reg["fullname_snapshot"] == "Pending Alumnus"
    assert reg["batch_year_snapshot"] == 2024 and reg["branch_snapshot"] == "ECE"


def test_eligibility_eligible_for_non_alumni(client):
    who = _non_alumnus()
    _seed_user(who)
    eid = _mk_free_event(client)
    r = client.get(f"/api/v1/events/{eid}/registration-eligibility", headers=_bearer(who))
    assert r.status_code == 200, r.text
    assert r.json()["eligibility_status"] == "eligible"
