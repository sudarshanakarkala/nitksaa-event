"""Sprint 3 Verification Closure — closes five evidence gaps identified in
a post-sprint audit of ADMIN_EVENT_SCHEMA_ALIGNMENT_REPORT.md:

  Gap 1: no explicit test proving finance_operator/auditor/support are
         denied admin_events.py routes (previously inferred from code
         reading, not proven at runtime).
  Gap 2: no adversarial privilege/identity-injection tests against
         admin_events.py (fabricated role/actor/ownership in request data).
  Gap 3: event lifecycle (publish/close) concurrency was never
         characterized — reproduced here before any fix is considered.
  Gap 4: no malformed-payload tests for event/session/check-in routes.
  Gap 5: PATCH omitted-field preservation was inferred
         (exclude_unset=True), never asserted.

Per the closure workflow: reproduce first, only fix production code if a
test actually demonstrates a defect. See the report's "Sprint 3
Verification Closure" section for what was found.
"""
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

import pytest

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_080",
    "sub": "platform.admin.closure@nitksaa.dev",
    "email": "platform.admin.closure@nitksaa.dev",
    "fullname": "Platform Admin Closure Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS080",
    "graduation_year": 2018,
}
_FINANCE = {
    "firebase_uid": "TEST_ALUMNI_UID_081",
    "sub": "finance.closure@nitksaa.dev",
    "email": "finance.closure@nitksaa.dev",
    "fullname": "Finance Closure Test",
    "user_type": "alumni",
    "ref_id": "NITK2017CS081",
    "graduation_year": 2017,
}
_AUDITOR = {
    "firebase_uid": "TEST_ALUMNI_UID_082",
    "sub": "auditor.closure@nitksaa.dev",
    "email": "auditor.closure@nitksaa.dev",
    "fullname": "Auditor Closure Test",
    "user_type": "alumni",
    "ref_id": "NITK2016CS082",
    "graduation_year": 2016,
}
_SUPPORT = {
    "firebase_uid": "TEST_ALUMNI_UID_083",
    "sub": "support.closure@nitksaa.dev",
    "email": "support.closure@nitksaa.dev",
    "fullname": "Support Closure Test",
    "user_type": "alumni",
    "ref_id": "NITK2015CS083",
    "graduation_year": 2015,
}
_EVENT_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_084",
    "sub": "eventadmin.closure@nitksaa.dev",
    "email": "eventadmin.closure@nitksaa.dev",
    "fullname": "Event Admin Closure Test",
    "user_type": "alumni",
    "ref_id": "NITK2019CS084",
    "graduation_year": 2019,
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

_FUTURE_START = "2028-01-01T08:00:00+05:30"
_FUTURE_END = "2028-01-01T10:00:00+05:30"


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
    for identity in (_PLATFORM_ADMIN, _FINANCE, _AUDITOR, _SUPPORT, _EVENT_ADMIN, _TEST_ALUMNI):
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (firebase_uid) DO NOTHING
            """,
            identity["firebase_uid"], identity["email"], identity["fullname"],
            identity["user_type"], identity["ref_id"], identity["graduation_year"],
        )


def _grant_platform_role(client, admin_headers: dict, firebase_uid: str, role: str) -> None:
    r = client.post(
        "/api/v1/admin/payment-roles",
        json={"firebase_uid": firebase_uid, "role": role},
        headers=admin_headers,
    )
    assert r.status_code in (201, 409), r.text  # 409 = already granted from a prior test, fine


def _mk_event(client, admin_headers: dict, uid_suffix: str, *, publish: bool = False) -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST CLOSURE EVENT {uid_suffix}", "description": "Created by pytest",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Test Venue", "is_virtual": False, "capacity": 20,
        },
        headers=admin_headers,
    )
    assert r.status_code == 201, r.text
    event_id = r.json()["event_id"]
    if publish:
        r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=admin_headers)
        assert r.status_code == 200, r.text
    return event_id


def _event_row(event_id: int):
    return _db_fetch("SELECT * FROM events WHERE event_id = $1", event_id)[0]


def _audit_count(entity_type: str, entity_id: int) -> int:
    return _db_fetch(
        "SELECT count(*) AS n FROM event_audit_log WHERE entity_type = $1 AND entity_id = $2",
        entity_type, entity_id,
    )[0]["n"]


# ═════════════════════════════════════════════════════════════════════════════
# Gap 1 — finance_operator / auditor / support denied admin-event CRUD
# ═════════════════════════════════════════════════════════════════════════════

@pytest.mark.parametrize("role_identity,role_name", [(_FINANCE, "finance_operator"), (_AUDITOR, "auditor"), (_SUPPORT, "support")])
def test_non_event_role_denied_global_event_create(client, monkeypatch, role_identity, role_name):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_platform_role(client, admin_headers, role_identity["firebase_uid"], role_name)

        before_count = _db_fetch("SELECT count(*) AS n FROM events")[0]["n"]
        r = client.post(
            "/api/v1/admin/events",
            json={"title": f"SHOULD NOT EXIST {uuid.uuid4().hex[:8]}", "description": "d",
                  "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
                  "location_text": "Venue", "is_virtual": False, "capacity": 10},
            headers=_bearer(role_identity),
        )
        assert r.status_code == 403, f"{role_name}: expected 403, got {r.status_code}: {r.text}"
        assert "detail" in r.json()
        assert "Traceback" not in r.text and "asyncpg" not in r.text and "psycopg" not in r.text

        after_count = _db_fetch("SELECT count(*) AS n FROM events")[0]["n"]
        assert after_count == before_count, f"{role_name}: denied create must cause zero DB mutation"
    finally:
        _clear_bootstrap(monkeypatch)


@pytest.mark.parametrize("role_identity,role_name", [(_FINANCE, "finance_operator"), (_AUDITOR, "auditor"), (_SUPPORT, "support")])
def test_non_event_role_denied_event_patch(client, monkeypatch, role_identity, role_name):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_platform_role(client, admin_headers, role_identity["firebase_uid"], role_name)
        event_id = _mk_event(client, admin_headers, f"patch-{role_name}-{uuid.uuid4().hex[:6]}")
        before = _event_row(event_id)

        r = client.patch(
            f"/api/v1/admin/events/{event_id}",
            json={"title": "HACKED TITLE"},
            headers=_bearer(role_identity),
        )
        assert r.status_code == 403, f"{role_name}: expected 403, got {r.status_code}: {r.text}"

        after = _event_row(event_id)
        assert after["title"] == before["title"], f"{role_name}: denied PATCH must not mutate the event"
    finally:
        _clear_bootstrap(monkeypatch)


@pytest.mark.parametrize("role_identity,role_name", [(_FINANCE, "finance_operator"), (_AUDITOR, "auditor"), (_SUPPORT, "support")])
def test_non_event_role_denied_publish(client, monkeypatch, role_identity, role_name):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_platform_role(client, admin_headers, role_identity["firebase_uid"], role_name)
        event_id = _mk_event(client, admin_headers, f"publish-{role_name}-{uuid.uuid4().hex[:6]}")

        r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=_bearer(role_identity))
        assert r.status_code == 403, f"{role_name}: expected 403, got {r.status_code}: {r.text}"

        after = _event_row(event_id)
        assert after["status"] == "draft", f"{role_name}: denied publish must leave event in draft"
    finally:
        _clear_bootstrap(monkeypatch)


@pytest.mark.parametrize("role_identity,role_name", [(_FINANCE, "finance_operator"), (_AUDITOR, "auditor"), (_SUPPORT, "support")])
def test_non_event_role_denied_close(client, monkeypatch, role_identity, role_name):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_platform_role(client, admin_headers, role_identity["firebase_uid"], role_name)
        event_id = _mk_event(client, admin_headers, f"close-{role_name}-{uuid.uuid4().hex[:6]}", publish=True)

        r = client.post(f"/api/v1/admin/events/{event_id}/close", headers=_bearer(role_identity))
        assert r.status_code == 403, f"{role_name}: expected 403, got {r.status_code}: {r.text}"

        after = _event_row(event_id)
        assert after["status"] == "published", f"{role_name}: denied close must leave event published"
    finally:
        _clear_bootstrap(monkeypatch)


@pytest.mark.parametrize("role_identity,role_name", [(_FINANCE, "finance_operator"), (_AUDITOR, "auditor"), (_SUPPORT, "support")])
def test_non_event_role_denied_checkin_creation(client, monkeypatch, role_identity, role_name):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_platform_role(client, admin_headers, role_identity["firebase_uid"], role_name)
        event_id = _mk_event(client, admin_headers, f"checkin-{role_name}-{uuid.uuid4().hex[:6]}", publish=True)

        reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=_bearer(_TEST_ALUMNI))
        assert reg.status_code == 201, reg.text
        reg_id = reg.json()["registration_id"]
        qrtoken = _db_fetch("SELECT qrtoken FROM registrations WHERE registration_id = $1", reg_id)[0]["qrtoken"]

        r = client.post(
            f"/api/v1/admin/events/{event_id}/check-ins",
            json={"qr_token": qrtoken},
            headers=_bearer(role_identity),
        )
        assert r.status_code == 403, f"{role_name}: expected 403, got {r.status_code}: {r.text}"

        rows = _db_fetch(
            "SELECT count(*) AS n FROM check_ins WHERE event_id = $1 AND registration_id = $2",
            event_id, reg_id,
        )
        assert rows[0]["n"] == 0, f"{role_name}: denied check-in must create zero check_ins rows"
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# Gap 2 — privilege / identity injection
# ═════════════════════════════════════════════════════════════════════════════

_FORGED_FIELDS = {
    "role": "platform_admin",
    "roles": ["platform_admin"],
    "is_admin": True,
    "firebase_uid": "forged-admin",
    "actor_uid": "forged-admin",
    "created_by": "forged-admin",
    "created_by_firebase_uid": "forged-admin",
    "updated_by": "forged-admin",
    "event_admin": True,
    "owner_uid": "forged-admin",
}


def test_attendee_cannot_elevate_via_forged_fields_on_create(client):
    """An attendee (no role at all) stuffs every plausible privilege field
    into the create-event body. Must still be denied at the auth layer —
    forged fields in the body are never even reached, since
    require_platform_role runs before the handler body is touched."""
    payload = {
        "title": f"FORGED {uuid.uuid4().hex[:8]}", "description": "d",
        "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
        "location_text": "Venue", "is_virtual": False, "capacity": 10,
        **_FORGED_FIELDS,
    }
    r = client.post("/api/v1/admin/events", json=payload, headers=_bearer(_TEST_ALUMNI))
    assert r.status_code == 403, r.text


def test_finance_operator_cannot_elevate_via_forged_fields(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_platform_role(client, admin_headers, _FINANCE["firebase_uid"], "finance_operator")

        payload = {
            "title": f"FORGED FIN {uuid.uuid4().hex[:8]}", "description": "d",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Venue", "is_virtual": False, "capacity": 10,
            **_FORGED_FIELDS,
        }
        r = client.post("/api/v1/admin/events", json=payload, headers=_bearer(_FINANCE))
        assert r.status_code == 403, r.text
    finally:
        _clear_bootstrap(monkeypatch)


def test_event_admin_cannot_inject_ownership_of_another_event(client, monkeypatch):
    """event_admin granted on event A tries to PATCH event B by putting
    event A's id / a forged owner claim into the body of a request whose
    URL still targets event B. The path event_id is authoritative — a
    forged event_id/owner field in the body must have zero effect."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_a = _mk_event(client, admin_headers, f"inject-a-{uuid.uuid4().hex[:6]}")
        event_b = _mk_event(client, admin_headers, f"inject-b-{uuid.uuid4().hex[:6]}")

        r = client.post(
            f"/api/v1/admin/events/{event_a}/payment-admins",
            json={"firebase_uid": _EVENT_ADMIN["firebase_uid"]},
            headers=admin_headers,
        )
        assert r.status_code == 201, r.text

        before_b = _event_row(event_b)
        r = client.patch(
            f"/api/v1/admin/events/{event_b}",
            json={"title": "hacked via forged ownership", "event_id": event_a,
                  "owner_uid": _EVENT_ADMIN["firebase_uid"], "created_by_firebase_uid": _EVENT_ADMIN["firebase_uid"]},
            headers=_bearer(_EVENT_ADMIN),
        )
        assert r.status_code == 403, r.text
        after_b = _event_row(event_b)
        assert after_b["title"] == before_b["title"]
    finally:
        _clear_bootstrap(monkeypatch)


def test_audit_actor_cannot_be_forged(client, monkeypatch):
    """A legitimate platform_admin stuffs a forged actor_uid/created_by
    into the create-event body. The audit trail's actor_uid must reflect
    the VERIFIED JWT identity, never a client-supplied value."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)

        payload = {
            "title": f"AUDIT FORGE {uuid.uuid4().hex[:8]}", "description": "d",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Venue", "is_virtual": False, "capacity": 10,
            "actor_uid": "forged-actor", "created_by": "forged-actor",
        }
        r = client.post("/api/v1/admin/events", json=payload, headers=admin_headers)
        assert r.status_code == 201, r.text
        event_id = r.json()["event_id"]

        # The event's own created_by_firebase_uid column must be the real caller.
        row = _event_row(event_id)
        assert row["created_by_firebase_uid"] == _PLATFORM_ADMIN["firebase_uid"]

        # And the audit row's actor must match too — never the forged value.
        audit_rows = _db_fetch(
            "SELECT actor_uid FROM event_audit_log WHERE entity_type = 'event' AND entity_id = $1 AND event_type = 'event_created'",
            event_id,
        )
        assert len(audit_rows) == 1
        assert audit_rows[0]["actor_uid"] == _PLATFORM_ADMIN["firebase_uid"]
        assert audit_rows[0]["actor_uid"] != "forged-actor"
    finally:
        _clear_bootstrap(monkeypatch)


def test_unexpected_query_params_cannot_bypass_event_scope(client, monkeypatch):
    """An event_admin for event A tries an unexpected query parameter
    aimed at some other event on a route that only takes event_id from
    the path. Must still be denied for event B."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_a = _mk_event(client, admin_headers, f"qsbypass-a-{uuid.uuid4().hex[:6]}")
        event_b = _mk_event(client, admin_headers, f"qsbypass-b-{uuid.uuid4().hex[:6]}")
        client.post(f"/api/v1/admin/events/{event_a}/payment-admins",
                    json={"firebase_uid": _EVENT_ADMIN["firebase_uid"]}, headers=admin_headers)

        r = client.patch(
            f"/api/v1/admin/events/{event_b}?event_id={event_a}&scope=admin",
            json={"title": "should not work"},
            headers=_bearer(_EVENT_ADMIN),
        )
        assert r.status_code == 403, r.text
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# Gap 3 — event lifecycle concurrency (reproduce-before-fix)
# ═════════════════════════════════════════════════════════════════════════════

def test_concurrent_publish_publish_no_corruption(client, monkeypatch):
    """Two workers call publish on the SAME draft event at (as close as
    possible to) the same instant. EventsService.update_status is
    check-then-act (SELECT current status, validate transition, UPDATE) —
    reproduced here without assuming the outcome."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"concpub-{uuid.uuid4().hex[:8]}")

        def _publish():
            return client.post(f"/api/v1/admin/events/{event_id}/publish", headers=admin_headers)

        with ThreadPoolExecutor(max_workers=2) as pool:
            f1 = pool.submit(_publish)
            f2 = pool.submit(_publish)
            try:
                r1, r2 = f1.result(timeout=10), f2.result(timeout=10)
            except FutureTimeoutError:
                pytest.fail("Concurrent publish hung past 10s — deadlock.")

        statuses = sorted([r1.status_code, r2.status_code])
        assert 500 not in statuses, f"concurrent publish produced a 500: {statuses}"
        # Fixed via EventsRepository.update_event_if_status (conditional
        # UPDATE ... WHERE status = expected): exactly one caller's
        # conditional write can match 'draft' — the other loses the race
        # and gets a clean 409, never a silent duplicate success.
        assert statuses == [200, 409], f"expected exactly one winner, got {statuses}"

        final = _event_row(event_id)
        assert final["status"] == "published", "final state must be a valid, intended state"

        audit_rows = _db_fetch(
            "SELECT count(*) AS n FROM event_audit_log WHERE entity_type='event' AND entity_id=$1 AND event_type='event_published'",
            event_id,
        )
        assert audit_rows[0]["n"] == 1, (
            f"expected exactly one audit row for one logical transition, got {audit_rows[0]['n']}"
        )
    finally:
        _clear_bootstrap(monkeypatch)


def test_concurrent_close_close_no_corruption(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"concclose-{uuid.uuid4().hex[:8]}", publish=True)

        def _close():
            return client.post(f"/api/v1/admin/events/{event_id}/close", headers=admin_headers)

        with ThreadPoolExecutor(max_workers=2) as pool:
            f1 = pool.submit(_close)
            f2 = pool.submit(_close)
            try:
                r1, r2 = f1.result(timeout=10), f2.result(timeout=10)
            except FutureTimeoutError:
                pytest.fail("Concurrent close hung past 10s — deadlock.")

        statuses = sorted([r1.status_code, r2.status_code])
        assert 500 not in statuses, f"concurrent close produced a 500: {statuses}"
        assert statuses == [200, 409], f"expected exactly one winner, got {statuses}"

        final = _event_row(event_id)
        assert final["status"] == "completed", "final state must be a valid, intended state"

        audit_rows = _db_fetch(
            "SELECT count(*) AS n FROM event_audit_log WHERE entity_type='event' AND entity_id=$1 AND event_type='event_completed'",
            event_id,
        )
        assert audit_rows[0]["n"] == 1, (
            f"expected exactly one audit row for one logical transition, got {audit_rows[0]['n']}"
        )
    finally:
        _clear_bootstrap(monkeypatch)


def test_concurrent_publish_and_close_conflicting_race(client, monkeypatch):
    """The strongest realistic conflicting race admin_events.py's actual
    route surface permits without inventing an unreachable transition:
    starting from 'draft', one worker calls publish (draft->published,
    valid) while another simultaneously calls close (only valid FROM
    published, per _VALID_TRANSITIONS) — whether close succeeds depends
    entirely on whether it reads before or after publish's write commits.
    Both outcomes are legitimate; a 500, a deadlock, or an impossible
    final state are the only defects this test would catch."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"concrace-{uuid.uuid4().hex[:8]}")  # starts 'draft'

        def _publish():
            return client.post(f"/api/v1/admin/events/{event_id}/publish", headers=admin_headers)

        def _close():
            return client.post(f"/api/v1/admin/events/{event_id}/close", headers=admin_headers)

        with ThreadPoolExecutor(max_workers=2) as pool:
            f1 = pool.submit(_publish)
            f2 = pool.submit(_close)
            try:
                r_publish, r_close = f1.result(timeout=10), f2.result(timeout=10)
            except FutureTimeoutError:
                pytest.fail("Concurrent publish/close race hung past 10s.")

        assert r_publish.status_code != 500, f"publish side produced a 500: {r_publish.text}"
        assert r_close.status_code != 500, f"close side produced a 500: {r_close.text}"
        assert r_publish.status_code == 200, f"publish (draft->published) must always succeed regardless of close's timing: {r_publish.text}"
        assert r_close.status_code in (200, 409), f"close must either win cleanly or lose cleanly, got {r_close.status_code}: {r_close.text}"

        final = _event_row(event_id)
        assert final["status"] in ("published", "completed"), f"impossible final state: {final['status']}"
        if r_close.status_code == 200:
            assert final["status"] == "completed"
        else:
            assert final["status"] == "published"
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# Gap 4 — malformed payloads
# ═════════════════════════════════════════════════════════════════════════════

def test_malformed_event_create_missing_required_field(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        r = client.post("/api/v1/admin/events", json={"description": "no title"}, headers=_bearer(_PLATFORM_ADMIN))
        assert r.status_code == 422, r.text
        assert "Traceback" not in r.text and "asyncpg" not in r.text
    finally:
        _clear_bootstrap(monkeypatch)


def test_malformed_event_create_bad_datetime(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        r = client.post(
            "/api/v1/admin/events",
            json={"title": "Bad Date Event", "description": "d", "start_datetime": "not-a-date",
                  "end_datetime": _FUTURE_END, "location_text": "Venue", "is_virtual": False, "capacity": 10},
            headers=_bearer(_PLATFORM_ADMIN),
        )
        assert r.status_code == 422, r.text
    finally:
        _clear_bootstrap(monkeypatch)


def test_malformed_event_create_end_before_start_rejected(client, monkeypatch):
    """end_datetime <= start_datetime validation is a current, real
    business rule (EventCreate.validate_datetimes) — exercised here."""
    try:
        _as_platform_admin(monkeypatch)
        r = client.post(
            "/api/v1/admin/events",
            json={"title": "Backwards Event", "description": "d", "start_datetime": _FUTURE_END,
                  "end_datetime": _FUTURE_START, "location_text": "Venue", "is_virtual": False, "capacity": 10},
            headers=_bearer(_PLATFORM_ADMIN),
        )
        assert r.status_code == 422, r.text
    finally:
        _clear_bootstrap(monkeypatch)


def test_malformed_event_patch_invalid_type(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"badpatch-{uuid.uuid4().hex[:6]}")
        before = _event_row(event_id)

        r = client.patch(f"/api/v1/admin/events/{event_id}", json={"capacity": "not-a-number"}, headers=admin_headers)
        assert r.status_code == 422, r.text

        after = _event_row(event_id)
        assert after["capacity"] == before["capacity"], "invalid PATCH must cause zero DB mutation"
    finally:
        _clear_bootstrap(monkeypatch)


def test_malformed_event_patch_status_not_client_controlled(client, monkeypatch):
    """EventUpdate has no 'status' field at all — status is exclusively
    controlled via the dedicated publish/close routes (EventStatusUpdate),
    never via PATCH. Confirms a client cannot smuggle a status change
    through the generic update endpoint."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"statuspatch-{uuid.uuid4().hex[:6]}")

        r = client.patch(f"/api/v1/admin/events/{event_id}", json={"status": "published"}, headers=admin_headers)
        # Pydantic drops the unknown 'status' field silently (extras
        # ignored, not rejected) — the route still succeeds (200), but the
        # actual DB status must remain untouched by it.
        assert r.status_code == 200, r.text
        after = _event_row(event_id)
        assert after["status"] == "draft", "status must never change via PATCH regardless of body content"
    finally:
        _clear_bootstrap(monkeypatch)


def test_malformed_session_create_missing_title(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"badsession-{uuid.uuid4().hex[:6]}")

        r = client.post(
            f"/api/v1/admin/events/{event_id}/sessions",
            json={"starts_at": _FUTURE_START, "ends_at": _FUTURE_END},
            headers=admin_headers,
        )
        assert r.status_code == 422, r.text

        rows = _db_fetch("SELECT count(*) AS n FROM sessions WHERE event_id = $1", event_id)
        assert rows[0]["n"] == 0
    finally:
        _clear_bootstrap(monkeypatch)


def test_malformed_session_create_bad_datetime(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"badsessiondt-{uuid.uuid4().hex[:6]}")

        r = client.post(
            f"/api/v1/admin/events/{event_id}/sessions",
            json={"title": "Bad Session", "starts_at": "not-a-date", "ends_at": _FUTURE_END},
            headers=admin_headers,
        )
        assert r.status_code == 422, r.text
    finally:
        _clear_bootstrap(monkeypatch)


def test_malformed_checkin_missing_token(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"badcheckin-{uuid.uuid4().hex[:6]}", publish=True)

        r = client.post(f"/api/v1/admin/events/{event_id}/check-ins", json={}, headers=admin_headers)
        assert r.status_code == 422, r.text

        rows = _db_fetch("SELECT count(*) AS n FROM check_ins WHERE event_id = $1", event_id)
        assert rows[0]["n"] == 0
    finally:
        _clear_bootstrap(monkeypatch)


def test_malformed_checkin_wrong_type(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"badcheckintype-{uuid.uuid4().hex[:6]}", publish=True)

        r = client.post(
            f"/api/v1/admin/events/{event_id}/check-ins",
            json={"qr_token": 12345, "session_id": "not-an-int"},
            headers=admin_headers,
        )
        assert r.status_code == 422, r.text
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# Gap 5 — PATCH omitted-field preservation
# ═════════════════════════════════════════════════════════════════════════════

def test_patch_preserves_omitted_fields(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)

        r = client.post(
            "/api/v1/admin/events",
            json={
                "title": f"PATCH Preservation {uuid.uuid4().hex[:8]}",
                "tagline": "Original Tagline",
                "description": "Original description",
                "start_datetime": _FUTURE_START,
                "end_datetime": _FUTURE_END,
                "location_text": "Original Venue",
                "is_virtual": False,
                "capacity": 42,
                "is_free": False,
                "ticket_price": "150.00",
                "show_attendee_list": True,
            },
            headers=admin_headers,
        )
        assert r.status_code == 201, r.text
        event_id = r.json()["event_id"]
        before = dict(_event_row(event_id))

        r = client.patch(
            f"/api/v1/admin/events/{event_id}",
            json={"description": "Only the description changed"},
            headers=admin_headers,
        )
        assert r.status_code == 200, r.text
        after_via_api = r.json()

        # Target field changed.
        assert after_via_api["description"] == "Only the description changed"

        # Every other relevant field, reloaded from the DB, is untouched.
        after = dict(_event_row(event_id))
        assert after["tagline"] == before["tagline"] == "Original Tagline"
        assert after["location_text"] == before["location_text"] == "Original Venue"
        assert after["start_datetime"] == before["start_datetime"]
        assert after["end_datetime"] == before["end_datetime"]
        assert after["is_full_day"] == before["is_full_day"]
        assert after["is_free"] == before["is_free"] is False
        assert str(after["ticket_price"]) == str(before["ticket_price"]) == "150.00"
        assert after["show_attendee_list"] == before["show_attendee_list"] is True
        assert after["capacity"] == before["capacity"] == 42

        # Server-owned fields not clearable/overridable via PATCH (no such
        # fields in EventUpdate's schema at all — confirmed, not just
        # assumed, by attempting one anyway in a separate call).
        assert after["created_by_firebase_uid"] == before["created_by_firebase_uid"] == _PLATFORM_ADMIN["firebase_uid"]
        assert after["event_id"] == before["event_id"]
        assert after["slug"] == before["slug"]
    finally:
        _clear_bootstrap(monkeypatch)


def test_patch_cannot_override_server_owned_fields(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"serverowned-{uuid.uuid4().hex[:6]}")
        before = _event_row(event_id)

        r = client.patch(
            f"/api/v1/admin/events/{event_id}",
            json={"event_id": before["event_id"] + 999, "slug": "hacked-slug",
                  "created_by_firebase_uid": "forged-owner", "created_at": "2000-01-01T00:00:00Z"},
            headers=admin_headers,
        )
        assert r.status_code == 200, r.text  # unknown fields silently dropped, not an error
        after = _event_row(event_id)
        assert after["event_id"] == before["event_id"]
        assert after["slug"] == before["slug"]
        assert after["created_by_firebase_uid"] == before["created_by_firebase_uid"]
        assert after["created_at"] == before["created_at"]
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# check_in_attempts 501 decision — re-confirmed under real auth
# ═════════════════════════════════════════════════════════════════════════════

def test_checkin_attempts_501_authenticated_authorized_no_fabrication(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"attempts501-{uuid.uuid4().hex[:6]}", publish=True)

        # Unauthenticated: 403 (authn gate still applies before the 501).
        r = client.get(f"/api/v1/admin/events/{event_id}/check-in-attempts")
        assert r.status_code == 403

        # Attendee: still denied (authz gate applies before the 501).
        r = client.get(f"/api/v1/admin/events/{event_id}/check-in-attempts", headers=_bearer(_TEST_ALUMNI))
        assert r.status_code == 403

        # Authorized platform_admin: honest 501, no fabricated body.
        r = client.get(f"/api/v1/admin/events/{event_id}/check-in-attempts", headers=admin_headers)
        assert r.status_code == 501, r.text
        body = r.json()
        assert body == {"detail": "check_in_attempt_logging_not_supported_by_current_schema"}
        assert "Traceback" not in r.text and "asyncpg" not in r.text
    finally:
        _clear_bootstrap(monkeypatch)
