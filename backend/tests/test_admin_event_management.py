"""Admin-event-schema-alignment sprint — dedicated functional coverage for
the repaired event/session/check-in subsystem: the full real-schema
check-in flow (verify -> create -> duplicate/invalid/ineligible rejected
-> list), concurrent-check-in race safety, session creation DB-state, and
the one gap left by retiring test_event_flow.py's obsolete duplicate
-registration test (the free-event branch of register_for_event, which
the payment test suite's equivalent coverage only exercises for paid
events).
"""
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

import pytest

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_070",
    "sub": "platform.admin.evtmgmt@nitksaa.dev",
    "email": "platform.admin.evtmgmt@nitksaa.dev",
    "fullname": "Platform Admin EvtMgmt Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS070",
    "graduation_year": 2018,
}

_TEST_ALUMNI = {
    "firebase_uid": "TEST_ALUMNI_UID_001",
    "sub": "ravi.test@nitksaa.dev",
    "email": "ravi.test@nitksaa.dev",
    "fullname": "Ravi Shankar Test",
    "user_type": "alumni",
    "ref_id": "NITK2020CS001",
    "graduation_year": 2020,
}
_TEST_ALUMNI_2 = {
    "firebase_uid": "TEST_ALUMNI_UID_002",
    "sub": "priya.test@nitksaa.dev",
    "email": "priya.test@nitksaa.dev",
    "fullname": "Priya Kumari Test",
    "user_type": "alumni",
    "ref_id": "NITK2019EC002",
    "graduation_year": 2019,
}

_FUTURE_START = "2027-11-01T08:00:00+05:30"
_FUTURE_END = "2027-11-01T10:00:00+05:30"


def _bearer(identity: dict) -> dict:
    from app.middleware.auth import make_access_token

    token = make_access_token(dict(identity))
    return {"Authorization": f"Bearer {token}"}


def _as_platform_admin(monkeypatch) -> None:
    from app.config import get_settings

    monkeypatch.setenv("PLATFORM_ADMIN_FIREBASE_UIDS", _PLATFORM_ADMIN["firebase_uid"])
    get_settings.cache_clear()


def _clear_bootstrap(monkeypatch) -> None:
    from app.config import get_settings

    monkeypatch.delenv("PLATFORM_ADMIN_FIREBASE_UIDS", raising=False)
    get_settings.cache_clear()


def _db_fetch(query: str, *args) -> list:
    import asyncio

    import asyncpg

    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            return await conn.fetch(query, *args)
        finally:
            await conn.close()

    return asyncio.run(_run())


def _db_exec(query: str, *args) -> None:
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


@pytest.fixture(autouse=True)
def _seed_test_identities():
    for identity in (_PLATFORM_ADMIN, _TEST_ALUMNI, _TEST_ALUMNI_2):
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (firebase_uid) DO NOTHING
            """,
            identity["firebase_uid"], identity["email"], identity["fullname"],
            identity["user_type"], identity["ref_id"], identity["graduation_year"],
        )


def _mk_published_event(client, admin_headers: dict, uid_suffix: str, *, capacity: int = 50) -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST EVTMGMT EVENT {uid_suffix}", "description": "Created by pytest",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Test Venue", "is_virtual": False, "capacity": capacity,
        },
        headers=admin_headers,
    )
    assert r.status_code == 201, r.text
    event_id = r.json()["event_id"]
    r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=admin_headers)
    assert r.status_code == 200, r.text
    return event_id


def _get_qrtoken(registration_id: int) -> str:
    return _db_fetch(
        "SELECT qrtoken FROM registrations WHERE registration_id = $1", registration_id
    )[0]["qrtoken"]


# ─────────────────────────────────────────────────────────────────────────────
# Full check-in flow against the real schema
# ─────────────────────────────────────────────────────────────────────────────

def test_full_checkin_flow(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_published_event(client, admin_headers, f"checkin-{uuid.uuid4().hex[:8]}")

        reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=_bearer(_TEST_ALUMNI))
        assert reg.status_code == 201, reg.text
        reg_id = reg.json()["registration_id"]
        qrtoken = _get_qrtoken(reg_id)
        assert qrtoken, "registration must have a qrtoken generated at insert time"

        # 1. Verify eligible.
        r = client.get(
            f"/api/v1/admin/events/{event_id}/check-ins/verify",
            params={"qr_token": qrtoken}, headers=admin_headers,
        )
        assert r.status_code == 200, r.text
        v = r.json()
        assert v["valid"] is True
        assert v["already_checked_in"] is False
        assert v["message"] == "ready_to_checkin"
        assert v["registration_id"] == reg_id

        # 2. Check in succeeds.
        r = client.post(
            f"/api/v1/admin/events/{event_id}/check-ins",
            json={"qr_token": qrtoken}, headers=admin_headers,
        )
        assert r.status_code == 201, r.text
        ci = r.json()
        assert ci["registration_id"] == reg_id
        assert ci["event_id"] == event_id
        assert ci["result"] == "success"
        assert ci["checked_in_by"] == _PLATFORM_ADMIN["firebase_uid"]

        # registrations.status is NEVER mutated by check-in — explicit
        # sprint decision, verified directly against the DB.
        row = _db_fetch("SELECT status FROM registrations WHERE registration_id = $1", reg_id)[0]
        assert row["status"] == "registered"

        # 3. Duplicate check-in rejected.
        r = client.post(
            f"/api/v1/admin/events/{event_id}/check-ins",
            json={"qr_token": qrtoken}, headers=admin_headers,
        )
        assert r.status_code == 409, r.text
        assert r.json()["detail"] == "already_checked_in"

        # 4. Invalid token rejected.
        r = client.post(
            f"/api/v1/admin/events/{event_id}/check-ins",
            json={"qr_token": "totally-bogus-token"}, headers=admin_headers,
        )
        assert r.status_code == 404, r.text
        assert r.json()["detail"] == "invalid_qr_token"

        # 5. Verify after check-in reflects new state.
        r = client.get(
            f"/api/v1/admin/events/{event_id}/check-ins/verify",
            params={"qr_token": qrtoken}, headers=admin_headers,
        )
        assert r.status_code == 200, r.text
        v = r.json()
        assert v["already_checked_in"] is True
        assert v["message"] == "already_checked_in"

        # 6. List reflects the check-in.
        r = client.get(f"/api/v1/admin/events/{event_id}/check-ins", headers=admin_headers)
        assert r.status_code == 200, r.text
        checkins = r.json()
        assert any(c["registration_id"] == reg_id for c in checkins)

        # 7. Attempt listing is the documented PARTIAL capability.
        r = client.get(f"/api/v1/admin/events/{event_id}/check-in-attempts", headers=admin_headers)
        assert r.status_code == 501, r.text
        assert r.json()["detail"] == "check_in_attempt_logging_not_supported_by_current_schema"
    finally:
        _clear_bootstrap(monkeypatch)


def test_checkin_rejects_wrong_event_registration(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_a = _mk_published_event(client, admin_headers, f"wrongevt-a-{uuid.uuid4().hex[:8]}")
        event_b = _mk_published_event(client, admin_headers, f"wrongevt-b-{uuid.uuid4().hex[:8]}")

        reg = client.post(f"/api/v1/events/{event_a}/register", json={}, headers=_bearer(_TEST_ALUMNI))
        reg_id = reg.json()["registration_id"]
        qrtoken = _get_qrtoken(reg_id)

        r = client.post(
            f"/api/v1/admin/events/{event_b}/check-ins",
            json={"qr_token": qrtoken}, headers=admin_headers,
        )
        assert r.status_code == 400, r.text
        assert r.json()["detail"] == "registration_belongs_to_different_event"
    finally:
        _clear_bootstrap(monkeypatch)


def test_checkin_rejects_ineligible_registration(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_published_event(client, admin_headers, f"ineligible-{uuid.uuid4().hex[:8]}")

        reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=_bearer(_TEST_ALUMNI))
        reg_id = reg.json()["registration_id"]
        qrtoken = _get_qrtoken(reg_id)

        # No cancel API exists — direct DB write is test setup for a state
        # the API has no route to produce, same rationale as this
        # codebase's other _db_exec-based test fixtures.
        _db_exec("UPDATE registrations SET status = 'cancelled' WHERE registration_id = $1", reg_id)

        r = client.post(
            f"/api/v1/admin/events/{event_id}/check-ins",
            json={"qr_token": qrtoken}, headers=admin_headers,
        )
        assert r.status_code == 403, r.text
        assert r.json()["detail"] == "registration_not_eligible"

        r = client.get(
            f"/api/v1/admin/events/{event_id}/check-ins/verify",
            params={"qr_token": qrtoken}, headers=admin_headers,
        )
        assert r.status_code == 200, r.text
        assert r.json()["message"] == "registration_not_eligible"
    finally:
        _clear_bootstrap(monkeypatch)


def test_concurrent_checkin_exactly_one_succeeds(client, monkeypatch):
    """Two threads race to check in the SAME registration at (as close as
    possible to) the same instant. Exactly one must win with 201; the
    other must lose cleanly with 409 — verifies
    uq_check_ins_event_registration (migration 019) is the real guard,
    not just the sequential find-then-insert check."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_published_event(client, admin_headers, f"concchk-{uuid.uuid4().hex[:8]}")

        reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=_bearer(_TEST_ALUMNI_2))
        reg_id = reg.json()["registration_id"]
        qrtoken = _get_qrtoken(reg_id)

        def _check_in():
            return client.post(
                f"/api/v1/admin/events/{event_id}/check-ins",
                json={"qr_token": qrtoken}, headers=admin_headers,
            )

        with ThreadPoolExecutor(max_workers=2) as pool:
            f1 = pool.submit(_check_in)
            f2 = pool.submit(_check_in)
            try:
                r1, r2 = f1.result(timeout=10), f2.result(timeout=10)
            except FutureTimeoutError:
                pytest.fail("Concurrent check-in hung past 10s.")

        statuses = sorted([r1.status_code, r2.status_code])
        assert statuses == [201, 409], f"expected exactly one winner, got {statuses}"

        rows = _db_fetch(
            "SELECT count(*) AS n FROM check_ins WHERE event_id = $1 AND registration_id = $2",
            event_id, reg_id,
        )
        assert rows[0]["n"] == 1, "concurrent check-in must never produce two rows"
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# Session creation — DB-state assertion
# ─────────────────────────────────────────────────────────────────────────────

def test_session_creation_persists_correct_columns(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_published_event(client, admin_headers, f"session-{uuid.uuid4().hex[:8]}")

        r = client.post(
            f"/api/v1/admin/events/{event_id}/sessions",
            json={
                "title": "Keynote", "description": "d", "speaker_name": "Dr. Test",
                "location": "Hall A", "track_name": "Main Track",
                "starts_at": _FUTURE_START, "ends_at": _FUTURE_END, "sort_order": 2,
            },
            headers=admin_headers,
        )
        assert r.status_code == 201, r.text
        session_id = r.json()["session_id"]

        row = _db_fetch("SELECT * FROM sessions WHERE session_id = $1", session_id)[0]
        assert row["location_text"] == "Hall A"
        assert row["track"] == "Main Track"
        assert row["event_id"] == event_id
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# Free-event duplicate registration (the gap left by retiring
# test_event_flow.py's obsolete email/ref_id-based duplicate test)
# ─────────────────────────────────────────────────────────────────────────────

def test_free_event_duplicate_registration_rejected(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        r = client.post(
            "/api/v1/admin/events",
            json={
                "title": f"TEST FREE DUP {uuid.uuid4().hex[:8]}", "description": "d",
                "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
                "location_text": "Venue", "is_virtual": False, "capacity": 10,
            },
            headers=admin_headers,
        )
        event_id = r.json()["event_id"]
        client.post(f"/api/v1/admin/events/{event_id}/publish", headers=admin_headers)

        headers = _bearer(_TEST_ALUMNI)
        r1 = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
        assert r1.status_code == 201, r1.text

        r2 = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
        assert r2.status_code == 409, r2.text
        assert r2.json()["detail"] == "already_registered"
    finally:
        _clear_bootstrap(monkeypatch)
