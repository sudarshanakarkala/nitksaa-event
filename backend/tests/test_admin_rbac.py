"""WP1 (operational-readiness sprint) — admin_events.py RBAC migration
tests. Route-level verification (real HTTP requests, not just dependency
unit tests) that every /api/v1/admin/events/* route now runs on real
Firebase-JWT-backed RBAC (app.middleware.admin_auth) instead of the
development-only app.middleware.dev_auth placeholder.

Important, evidence-based scoping note: live-probing all 13 routes against
the real DB before writing this file showed that only 3 of them
(GET .../attendees, GET .../attendees/export, GET .../registrations) are
functionally correct — the other 10 pre-date this sprint and fail with
either asyncpg.exceptions.UndefinedColumnError (event/session mutations —
EventRepository/CheckInRepository target column names from the superseded
001_create_events_alpha_schema.sql migration, not the actual events/
sessions/check_ins tables from 001_events.sql/002_sessions.sql/
004_registrations_and_check_ins.sql) or a FastAPI ResponseValidationError
(GET .../events list-all — the query succeeds, but EventResponse requires
fields like event_type that don't exist on a real row). This is a
pre-existing, unrelated defect — this sprint's job is proving the RBAC
migration is correct, not fixing that bug. So:
  - every route gets full negative/denial coverage (auth runs before any
    business logic, so this is unaffected by the underlying bug);
  - the 3 working routes additionally get full positive-path coverage;
  - the 10 broken routes get an "auth passes through" check instead of a
    full positive test: a legitimate platform_admin/event_admin caller
    must NOT be blocked by auth (not 401/403) and must reach the SAME
    pre-existing failure category any valid caller would hit — proving
    the migration didn't newly break anything and isn't silently swapping
    one broken behavior for another.
"""
import uuid

import pytest

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_040",
    "sub": "platform.admin.rbac@nitksaa.dev",
    "email": "platform.admin.rbac@nitksaa.dev",
    "fullname": "Platform Admin RBAC Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS040",
    "graduation_year": 2018,
}

_EVENT_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_041",
    "sub": "event.admin.rbac@nitksaa.dev",
    "email": "event.admin.rbac@nitksaa.dev",
    "fullname": "Event Admin RBAC Test",
    "user_type": "alumni",
    "ref_id": "NITK2019CS041",
    "graduation_year": 2019,
}

_ATTENDEE = {
    "firebase_uid": "TEST_ALUMNI_UID_042",
    "sub": "attendee.rbac@nitksaa.dev",
    "email": "attendee.rbac@nitksaa.dev",
    "fullname": "Attendee RBAC Test",
    "user_type": "alumni",
    "ref_id": "NITK2020CS042",
    "graduation_year": 2020,
}

# Dedicated fixture-only identity, permanently granted platform_admin via a
# direct DB row (not the per-test env-var bootstrap _PLATFORM_ADMIN relies
# on) — used ONLY by _mk_event to create the events these tests exercise.
# Needed because admin-auth-unification migrated events.py's own create
# route off dev-auth: _mk_event can no longer use the (now removed)
# X-Dev-User shortcut, and threading monkeypatch/bootstrap state through
# every one of _mk_event's ~10 call sites (several of which intentionally
# have no active bootstrap, e.g. test_route_denies_unauthenticated) would
# be far more invasive than giving fixture setup its own always-on identity.
_FIXTURE_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_043",
    "sub": "fixture.admin.rbac@nitksaa.dev",
    "email": "fixture.admin.rbac@nitksaa.dev",
    "fullname": "Fixture Admin RBAC Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS043",
    "graduation_year": 2018,
}


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
    for identity in (_PLATFORM_ADMIN, _EVENT_ADMIN, _ATTENDEE, _FIXTURE_ADMIN):
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (firebase_uid) DO NOTHING
            """,
            identity["firebase_uid"],
            identity["email"],
            identity["fullname"],
            identity["user_type"],
            identity["ref_id"],
            identity["graduation_year"],
        )
    _db_exec(
        """
        INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
        VALUES ($1, 'platform_admin', 'test_fixture_bootstrap')
        ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING
        """,
        _FIXTURE_ADMIN["firebase_uid"],
    )


def _mk_event(client, uid_suffix: str) -> int:
    """A real, working event, created via admin_events.py's own (real-RBAC,
    now fully functional per the admin-event-schema-alignment sprint)
    create route, authenticated as the dedicated _FIXTURE_ADMIN identity —
    independent of any per-test bootstrap state so every call site (many
    of which intentionally have none active) keeps working unchanged."""
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST ADMIN-RBAC EVENT {uid_suffix}",
            "description": "Created by pytest (admin RBAC)",
            "start_datetime": "2027-10-01T08:00:00+05:30",
            "end_datetime": "2027-10-01T10:00:00+05:30",
            "location_text": "Test Venue",
            "is_virtual": False,
            "capacity": 10,
            "is_free": True,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    return r.json()["event_id"]


def _grant_event_admin(client, admin_headers: dict, event_id: int, firebase_uid: str) -> None:
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-admins",
        json={"firebase_uid": firebase_uid},
        headers=admin_headers,
    )
    assert r.status_code == 201, r.text


# Route registry: (label, method, path template, is_write, json_body)
# path template takes {event_id}. Written == known-functional against the
# real schema; the other 10 are the pre-existing-broken set (see module
# docstring).
# Repaired in the admin-event-schema-alignment sprint (were in
# _BROKEN_ROUTES before that sprint fixed the underlying
# EventRepository/EventService schema mismatch — see that sprint's report).
_WORKING_ROUTES = [
    ("attendees", "GET", "/api/v1/admin/events/{event_id}/attendees", False, None),
    ("attendees_export", "GET", "/api/v1/admin/events/{event_id}/attendees/export", False, None),
    ("registrations", "GET", "/api/v1/admin/events/{event_id}/registrations", False, None),
    ("create_event", "POST", "/api/v1/admin/events", True,
     {"title": "Test Event Title", "description": "d", "start_datetime": "2027-10-01T08:00:00+05:30",
      "end_datetime": "2027-10-01T10:00:00+05:30", "location_text": "Venue", "is_virtual": False, "capacity": 10}),
    ("list_all_events", "GET", "/api/v1/admin/events", False, None),
    ("update_event", "PATCH", "/api/v1/admin/events/{event_id}", True, {"title": "Updated Title"}),
    ("publish_event", "POST", "/api/v1/admin/events/{event_id}/publish", True, None),
    ("close_event", "POST", "/api/v1/admin/events/{event_id}/close", True, None),
    ("create_session", "POST", "/api/v1/admin/events/{event_id}/sessions", True,
     {"title": "Test Session Title", "starts_at": "2027-10-01T09:00:00+05:30", "ends_at": "2027-10-01T09:30:00+05:30",
      "location": "Room A", "track_name": "Main"}),
    # verify_qr always 200s (valid=False for an unknown token, never an
    # HTTP error) and list_checkins always 200s — both fit the generic
    # single-call harness. check_in with a deliberately bogus token
    # correctly 404s (invalid_qr_token) — see _EXPECTED_STATUS below; the
    # full verify->create->duplicate->list flow with a REAL registration
    # is covered separately in tests/test_admin_event_management.py.
    ("checkins_verify", "GET", "/api/v1/admin/events/{event_id}/check-ins/verify?qr_token=x", False, None),
    ("checkins_create", "POST", "/api/v1/admin/events/{event_id}/check-ins", True, {"qr_token": "x"}),
    ("checkins_list", "GET", "/api/v1/admin/events/{event_id}/check-ins", False, None),
]

# check_in_attempts remains PARTIAL by explicit product/schema decision —
# no check_in_attempts table exists in the active schema (see
# CheckInRepository's docstring and the sprint report) — the route
# returns 501, not fabricated data. This is not a bug to fix.
_BROKEN_ROUTES = [
    ("checkin_attempts", "GET", "/api/v1/admin/events/{event_id}/check-in-attempts", False, None),
]
_ALL_ROUTES = _WORKING_ROUTES + _BROKEN_ROUTES


def _call(client, method, path, event_id, body, headers):
    url = path.format(event_id=event_id) if event_id is not None else path
    if method == "GET":
        return client.get(url, headers=headers)
    if method == "POST":
        return client.post(url, json=body or {}, headers=headers)
    if method == "PATCH":
        return client.patch(url, json=body or {}, headers=headers)
    raise ValueError(method)


# ─────────────────────────────────────────────────────────────────────────────
# A. Negative/denial coverage — every route, real HTTP requests
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("label,method,path,is_write,body", _ALL_ROUTES, ids=[r[0] for r in _ALL_ROUTES])
def test_route_denies_unauthenticated(client, label, method, path, is_write, body):
    event_id = _mk_event(client, f"denyunauth-{label}-{uuid.uuid4().hex[:6]}")
    r = _call(client, method, path, event_id, body, headers={})
    assert r.status_code == 403, f"{label}: expected 403 for unauthenticated, got {r.status_code}"


@pytest.mark.parametrize("label,method,path,is_write,body", _ALL_ROUTES, ids=[r[0] for r in _ALL_ROUTES])
def test_route_denies_invalid_token(client, label, method, path, is_write, body):
    event_id = _mk_event(client, f"denyinvalid-{label}-{uuid.uuid4().hex[:6]}")
    r = _call(client, method, path, event_id, body, headers={"Authorization": "Bearer not-a-real-jwt"})
    assert r.status_code == 401, f"{label}: expected 401 for invalid token, got {r.status_code}"


@pytest.mark.parametrize("label,method,path,is_write,body", _ALL_ROUTES, ids=[r[0] for r in _ALL_ROUTES])
def test_route_denies_attendee(client, label, method, path, is_write, body):
    event_id = _mk_event(client, f"denyattendee-{label}-{uuid.uuid4().hex[:6]}")
    r = _call(client, method, path, event_id, body, headers=_bearer(_ATTENDEE))
    assert r.status_code == 403, f"{label}: expected 403 for plain attendee, got {r.status_code}"


@pytest.mark.parametrize("label,method,path,is_write,body", _ALL_ROUTES, ids=[r[0] for r in _ALL_ROUTES])
def test_route_denies_spoofed_dev_header(client, label, method, path, is_write, body):
    """A spoofed X-Dev-User: admin header must not grant production access
    on any migrated route — the key regression check for this sprint."""
    event_id = _mk_event(client, f"denyspoof-{label}-{uuid.uuid4().hex[:6]}")
    headers = _bearer(_ATTENDEE)
    headers["X-Dev-User"] = "admin"
    r = _call(client, method, path, event_id, body, headers=headers)
    assert r.status_code == 403, f"{label}: expected 403 for spoofed X-Dev-User, got {r.status_code}"


@pytest.mark.parametrize("label,method,path,is_write,body", _ALL_ROUTES, ids=[r[0] for r in _ALL_ROUTES])
def test_route_denies_wrong_event_admin(client, monkeypatch, label, method, path, is_write, body):
    """An event_admin granted on a DIFFERENT event must be denied here —
    skipped for the two routes with no event_id (create/list-all), which
    are platform_admin-only by design and have no per-event scope to be
    'wrong' about."""
    if "{event_id}" not in path:
        pytest.skip(f"{label} has no event_id to scope — platform_admin-only by design")

    own_event_id = _mk_event(client, f"wrongevt-own-{label}-{uuid.uuid4().hex[:6]}")
    other_event_id = _mk_event(client, f"wrongevt-other-{label}-{uuid.uuid4().hex[:6]}")
    try:
        _as_platform_admin(monkeypatch)
        _grant_event_admin(client, _bearer(_PLATFORM_ADMIN), own_event_id, _EVENT_ADMIN["firebase_uid"])
        r = _call(client, method, path, other_event_id, body, headers=_bearer(_EVENT_ADMIN))
        assert r.status_code == 403, f"{label}: expected 403 on a non-owned event, got {r.status_code}"
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# B. Positive coverage — the 3 routes verified functional against real schema
# ─────────────────────────────────────────────────────────────────────────────

# Some working routes expect a non-200 success status, or need the event
# in a specific state before the call under test is meaningful (e.g.
# close_event requires status='published' — draft cannot transition
# directly to 'completed').
_EXPECTED_STATUS = {
    "create_event": 201,
    "create_session": 201,
    # Deliberately bogus qr_token in the generic body — a working route
    # correctly reports 404 invalid_qr_token, not a success status. The
    # real create-a-checkin success path is exercised with a genuine
    # registration in tests/test_admin_event_management.py.
    "checkins_create": 404,
}
_PRECONDITION = {
    "close_event": lambda client, headers, event_id: client.post(
        f"/api/v1/admin/events/{event_id}/publish", headers=headers
    ),
}


@pytest.mark.parametrize("label,method,path,is_write,body", _WORKING_ROUTES, ids=[r[0] for r in _WORKING_ROUTES])
def test_working_route_platform_admin_succeeds(client, monkeypatch, label, method, path, is_write, body):
    event_id = _mk_event(client, f"platok-{label}-{uuid.uuid4().hex[:6]}")
    try:
        _as_platform_admin(monkeypatch)
        headers = _bearer(_PLATFORM_ADMIN)
        if label in _PRECONDITION:
            pre = _PRECONDITION[label](client, headers, event_id)
            assert pre.status_code == 200, f"{label}: precondition setup failed: {pre.text}"
        r = _call(client, method, path, event_id, body, headers=headers)
        expected = _EXPECTED_STATUS.get(label, 200)
        assert r.status_code == expected, f"{label}: expected {expected} for platform_admin, got {r.status_code}: {r.text}"
    finally:
        _clear_bootstrap(monkeypatch)


@pytest.mark.parametrize("label,method,path,is_write,body", _WORKING_ROUTES, ids=[r[0] for r in _WORKING_ROUTES])
def test_working_route_own_event_admin_succeeds(client, monkeypatch, label, method, path, is_write, body):
    if "{event_id}" not in path:
        pytest.skip(f"{label} has no event_id to scope — platform_admin-only by design")
    event_id = _mk_event(client, f"evtok-{label}-{uuid.uuid4().hex[:6]}")
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_event_admin(client, admin_headers, event_id, _EVENT_ADMIN["firebase_uid"])
        event_admin_headers = _bearer(_EVENT_ADMIN)
        if label in _PRECONDITION:
            pre = _PRECONDITION[label](client, admin_headers, event_id)
            assert pre.status_code == 200, f"{label}: precondition setup failed: {pre.text}"
        r = _call(client, method, path, event_id, body, headers=event_admin_headers)
        expected = _EXPECTED_STATUS.get(label, 200)
        assert r.status_code == expected, f"{label}: expected {expected} for own-event event_admin, got {r.status_code}: {r.text}"
    finally:
        _clear_bootstrap(monkeypatch)


def test_revoked_event_admin_loses_access(client, monkeypatch):
    from app.repositories.payment_role_repository import PaymentRoleRepository

    event_id = _mk_event(client, f"revoke-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_event_admin(client, admin_headers, event_id, _EVENT_ADMIN["firebase_uid"])

        r = client.get(f"/api/v1/admin/events/{event_id}/attendees", headers=_bearer(_EVENT_ADMIN))
        assert r.status_code == 200, r.text

        # Revoke by flipping event_members.status — no HTTP revoke endpoint
        # exists for event_admin membership (only platform role grants have
        # one); this is the direct-DB equivalent an ops action would take,
        # same rationale as other tests' direct-DB test setup.
        _db_exec(
            "UPDATE event_members SET status = 'inactive' WHERE event_id = $1 AND firebase_uid = $2",
            event_id, _EVENT_ADMIN["firebase_uid"],
        )

        r2 = client.get(f"/api/v1/admin/events/{event_id}/attendees", headers=_bearer(_EVENT_ADMIN))
        assert r2.status_code == 403, r2.text
    finally:
        _clear_bootstrap(monkeypatch)


def test_platform_admin_retains_access_regardless_of_event_membership(client, monkeypatch):
    event_id = _mk_event(client, f"platretain-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        r = client.get(f"/api/v1/admin/events/{event_id}/attendees", headers=_bearer(_PLATFORM_ADMIN))
        assert r.status_code == 200, r.text
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# C. "Auth passes through" coverage for the 10 pre-existing-broken routes
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("label,method,path,is_write,body", _BROKEN_ROUTES, ids=[r[0] for r in _BROKEN_ROUTES])
def test_broken_route_platform_admin_not_blocked_by_auth(client, monkeypatch, label, method, path, is_write, body):
    """Originally covered 10 pre-existing-broken routes; the admin-event
    -schema-alignment sprint repaired all but check_in_attempts, which
    remains a deliberate, documented PARTIAL (no check_in_attempts table
    exists — 501, not a crash). Either way, a legitimate platform_admin
    must get PAST auth (not 401/403) — proving the RBAC layer isn't the
    cause of whatever non-2xx/exception outcome the route produces.

    The shared `client` fixture uses raise_server_exceptions=True (see
    conftest.py), so an unhandled exception (were one to occur) propagates
    as a real Python exception here rather than a 500 response object —
    unlike an auth denial or a deliberate HTTPException (like
    check_in_attempts' 501), which FastAPI's exception handler always
    turns into a normal response regardless of that setting.
    """
    from fastapi import HTTPException

    event_id = _mk_event(client, f"brokenauth-{label}-{uuid.uuid4().hex[:6]}")
    try:
        _as_platform_admin(monkeypatch)
        try:
            r = _call(client, method, path, event_id, body, headers=_bearer(_PLATFORM_ADMIN))
        except HTTPException as exc:
            pytest.fail(f"{label}: auth incorrectly blocked a legitimate platform_admin ({exc.status_code})")
        except Exception:
            return  # pre-existing bug reached — auth was not the blocker, as expected
        assert r.status_code not in (401, 403), (
            f"{label}: auth incorrectly blocked a legitimate platform_admin (got {r.status_code})"
        )
        assert r.status_code >= 500, (
            f"{label}: expected the known pre-existing failure, got a clean {r.status_code}: {r.text} "
            f"(if this route now works, move it from _BROKEN_ROUTES to _WORKING_ROUTES)"
        )
    finally:
        _clear_bootstrap(monkeypatch)
