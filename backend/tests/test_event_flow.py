"""
NITKSAA Event Platform — event lifecycle + public-visibility test suite.

Rewritten in the admin-event-schema-alignment sprint. Every test in this
file previously targeted a superseded schema/auth mechanism
(X-Dev-User admin_events.py routes, legacy EventCreate/CheckInResponse
field names) — see that sprint's report for the full classification of
what was fixed vs. retired vs. superseded by test_admin_rbac.py /
test_admin_event_management.py. What remains here focuses on coverage
those newer, more targeted files don't already provide: PUBLIC
(unauthenticated) event/session visibility, and event-lifecycle business
rules (draft/publish/close/registration-blocking) traced end-to-end
through the real schema.

Each test scenario is fully self-contained:
  - creates its own event/registration data using UUID-based unique ids
  - does NOT depend on fixture ordering or shared mutable state
  - does NOT assume any fixed event_id or registration_id
"""
import uuid

import pytest

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_060",
    "sub": "platform.admin.evtflow@nitksaa.dev",
    "email": "platform.admin.evtflow@nitksaa.dev",
    "fullname": "Platform Admin EvtFlow Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS060",
    "graduation_year": 2018,
}

# Seeded in both alumni_db and events_db — see test_payments.py's
# _TEST_ALUMNI docstring. Needed here because /register requires a real
# alumni_db lookup to succeed, not just an events_db event_users row.
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

_FUTURE_START = "2027-06-15T10:00:00+05:30"
_FUTURE_END = "2027-06-15T12:00:00+05:30"


def uid() -> str:
    return uuid.uuid4().hex[:10]


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


def _make_event(client, admin_headers: dict, *, publish: bool = False, capacity: int = 50) -> dict:
    """Create a draft event via the real (now-fixed) admin_events.py
    create route; optionally publish it. Returns the event dict."""
    s = uid()
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"Test Event {s}",
            "description": "Created by pytest",
            "start_datetime": _FUTURE_START,
            "end_datetime": _FUTURE_END,
            "location_text": "Test Venue",
            "is_virtual": False,
            "capacity": capacity,
        },
        headers=admin_headers,
    )
    assert r.status_code == 201, f"event create failed: {r.text}"
    event = r.json()
    if publish:
        r2 = client.post(f"/api/v1/admin/events/{event['event_id']}/publish", headers=admin_headers)
        assert r2.status_code == 200, f"event publish failed: {r2.text}"
        event = r2.json()
    return event


# ─────────────────────────────────────────────────────────────────────────────
# A. Health endpoints (unchanged — never touched the broken schema)
# ─────────────────────────────────────────────────────────────────────────────

def test_health_endpoints(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert r.json()["service"] == "NITKSAA Event API"

    r = client.get("/api/v1/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert data["db"] == "ok"
    assert "version" in data
    assert "env" in data


# ─────────────────────────────────────────────────────────────────────────────
# B. Event lifecycle: create → draft not public → publish → visible publicly
#
# VALID BUSINESS TEST, STALE AUTH + STALE SCHEMA — repaired. Covers public
# (unauthenticated) event visibility, which test_admin_rbac.py never
# touches (that file is entirely about the authenticated admin surface).
# ─────────────────────────────────────────────────────────────────────────────

def test_event_create_publish_and_public_visibility(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)

        event = _make_event(client, admin_headers)
        event_id = event["event_id"]
        assert event_id > 0
        assert event["status"] == "draft"
        assert event["created_by_firebase_uid"] == _PLATFORM_ADMIN["firebase_uid"]

        # Public listing is paginated and shared across the whole dev DB
        # (many other tests' events accumulate in it), so searching it for
        # one specific event_id is unreliable — the deterministic signal
        # is the public DETAIL endpoint's 404-vs-200 transition, which is
        # exactly what "not public yet" / "now public" means.
        r = client.get(f"/api/v1/events/public/{event_id}")
        assert r.status_code == 404, r.text

        r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=admin_headers)
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "published"
        assert r.json()["event_id"] == event_id

        # Publishing an already-published event is not a valid transition.
        r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=admin_headers)
        assert r.status_code == 409, r.text
        assert r.json()["detail"] == "invalid_status_transition_published_to_published"

        r = client.get(f"/api/v1/events/public/{event_id}")
        assert r.status_code == 200, r.text
        detail = r.json()["event"]
        assert detail["status"] == "published"
        assert detail["event_id"] == event_id

        # Admin can also see draft/published events in the admin listing.
        admin_ids = [e["event_id"] for e in client.get("/api/v1/admin/events", headers=admin_headers).json()]
        assert event_id in admin_ids
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# C. Registration duplicate prevention — OBSOLETE (business rule retired)
#
# The original test asserted duplicate-by-email and duplicate-by-ref_id
# both produce 409 registration_duplicate. The current registration
# system (app/services/registration_service.py) does not check email or
# ref_id at all — duplicate prevention is entirely firebase_uid-scoped
# (RegistrationRepository.get_active_for_user /
# get_active_or_held_for_user, detail="already_registered"), enforced via
# uq_registrations_active. Two different firebase_uids with the same
# email/ref_id can both register today; that is current, intended
# behavior (alumni identity is Firebase-UID-based, not email-based), not
# a regression to chase. The firebase_uid-scoped duplicate rule this
# retired test used to (accidentally) also exercise is already covered
# for paid events by test_payments.py::test_duplicate_registration_returns_promptly_no_hang
# and test_concurrent_double_click_registration_only_one_succeeds, which
# hit the same shared code path register_for_event uses regardless of
# is_paid_event. See tests/test_admin_event_management.py for a
# dedicated free-event duplicate-registration check (the one branch of
# that shared path the payment suite doesn't exercise).
# ─────────────────────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────────────────────
# D. QR verify → check-in → duplicate/invalid — DUPLICATED BY NEW TESTS +
#    OBSOLETE assertions
#
# The original test asserted (a) a successful check-in changes
# registrations.status to 'checked_in' — explicitly decided against this
# sprint (check-in is represented entirely by a check_ins row; the
# payment-domain status machine is never touched — see the sprint
# report's "check-in status" decision) — and (b) a check-in-attempts
# audit log with success/duplicate/invalid entries — no check_in_attempts
# table exists in the active schema (PARTIAL, 501, by explicit decision).
# Both assertions test retired/never-existed behavior. The valid parts of
# this flow (verify eligible → check in → duplicate rejected → invalid
# token rejected → list reflects it) are covered by
# tests/test_admin_event_management.py against the real, fixed schema.
# ─────────────────────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────────────────────
# E. Closed event blocks further registration
#
# VALID BUSINESS TEST, STALE AUTH + STALE SCHEMA — repaired. "Close" now
# maps to status='completed' (see the sprint report's "close semantics"
# decision — the active status model has no separate 'closed' value).
# ─────────────────────────────────────────────────────────────────────────────

def test_completed_event_blocks_registration(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event = _make_event(client, admin_headers, publish=True)
        event_id = event["event_id"]

        # Register one attendee before closing (proves it works while open).
        r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=_bearer(_TEST_ALUMNI))
        assert r.status_code == 201, r.text
        assert r.json()["status"] == "registered"

        r = client.post(f"/api/v1/admin/events/{event_id}/close", headers=admin_headers)
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "completed"

        # Closing again is not a valid transition (completed has no outgoing transitions).
        r = client.post(f"/api/v1/admin/events/{event_id}/close", headers=admin_headers)
        assert r.status_code == 409, r.text
        assert r.json()["detail"] == "invalid_status_transition_completed_to_completed"

        # Registration on a non-published event is blocked.
        r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=_bearer(_TEST_ALUMNI_2))
        assert r.status_code == 409, r.text
        assert r.json()["detail"] == "event_not_published"

        # Public detail also reflects non-published (404 — public detail
        # only ever returns published events).
        r = client.get(f"/api/v1/events/public/{event_id}")
        assert r.status_code == 404, r.text
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# F. Access control — public (no-auth) visibility only
#
# The original test's admin-403 assertions (attendee/no-auth denied on
# admin_events.py routes) are DUPLICATED BY test_admin_rbac.py, which
# covers every one of the 13 routes × every denial scenario (unauthenticated,
# invalid token, attendee, wrong-event event_admin, spoofed dev header,
# revoked grant) far more thoroughly than this single test did. What's
# NOT covered elsewhere: that the public event/session endpoints require
# no auth at all — kept here.
# ─────────────────────────────────────────────────────────────────────────────

def test_public_endpoints_require_no_auth(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        event = _make_event(client, _bearer(_PLATFORM_ADMIN), publish=True)
        event_id = event["event_id"]
    finally:
        _clear_bootstrap(monkeypatch)

    r = client.get("/api/v1/events/public")
    assert r.status_code == 200
    assert isinstance(r.json()["events"], list)

    r = client.get(f"/api/v1/events/public/{event_id}")
    assert r.status_code == 200
    assert r.json()["event"]["event_id"] == event_id

    # Attendee endpoints, by contrast, do require auth.
    r = client.post(f"/api/v1/events/{event_id}/register", json={})
    assert r.status_code == 403


# ─────────────────────────────────────────────────────────────────────────────
# G. Admin listings: sessions, attendees, registrations, event update
#
# VALID BUSINESS TEST, STALE SCHEMA — repaired. Covers session creation
# and the admin listing endpoints' actual (wrapped, not bare-list)
# response shape — test_admin_rbac.py checks authorization on these
# routes but not their response contents. (No public session-listing
# endpoint exists in the active API — the original test's assumption of
# one was itself stale; not carried forward.)
# ─────────────────────────────────────────────────────────────────────────────

def test_admin_listings_and_sessions(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event = _make_event(client, admin_headers, publish=True)
        event_id = event["event_id"]

        r = client.post(
            f"/api/v1/admin/events/{event_id}/sessions",
            json={"title": "Opening Keynote", "speaker_name": "Prof. Ramesh Kumar",
                  "location": "Main Auditorium", "starts_at": _FUTURE_START, "ends_at": _FUTURE_END,
                  "sort_order": 1},
            headers=admin_headers,
        )
        assert r.status_code == 201, r.text
        session = r.json()
        assert session["session_id"] > 0
        assert session["event_id"] == event_id
        assert session["title"] == "Opening Keynote"
        assert session["location"] == "Main Auditorium"
        assert session["sort_order"] == 1

        # ── Event update (PATCH) ──────────────────────────────────────────
        r = client.patch(
            f"/api/v1/admin/events/{event_id}",
            json={"description": "Updated by pytest PATCH test"},
            headers=admin_headers,
        )
        assert r.status_code == 200, r.text
        assert r.json()["description"] == "Updated by pytest PATCH test"

        # ── Attendees list (wrapped response, not a bare list) ─────────────
        r = client.get(f"/api/v1/admin/events/{event_id}/attendees", headers=admin_headers)
        assert r.status_code == 200, r.text
        assert r.json()["attendees"] == []
        assert r.json()["total"] == 0

        reg1 = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=_bearer(_TEST_ALUMNI))
        reg2 = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=_bearer(_TEST_ALUMNI_2))
        assert reg1.status_code == 201, reg1.text
        assert reg2.status_code == 201, reg2.text

        r = client.get(f"/api/v1/admin/events/{event_id}/attendees", headers=admin_headers)
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["total"] == 2
        attendee_reg_ids = {a["registration_id"] for a in body["attendees"]}
        assert reg1.json()["registration_id"] in attendee_reg_ids
        assert reg2.json()["registration_id"] in attendee_reg_ids

        # ── Admin registrations list ────────────────────────────────────────
        r = client.get(f"/api/v1/admin/events/{event_id}/registrations", headers=admin_headers)
        assert r.status_code == 200, r.text
        reg_body = r.json()
        assert reg_body["total"] == 2

        # ── Admin all-events list includes this event ───────────────────────
        r = client.get("/api/v1/admin/events", headers=admin_headers)
        assert r.status_code == 200, r.text
        all_ids = [e["event_id"] for e in r.json()]
        assert event_id in all_ids
    finally:
        _clear_bootstrap(monkeypatch)
