"""
NITKSAA Event Platform — Alpha backend test suite.

Each test scenario is fully self-contained:
  - creates its own event/registration data using UUID-based unique ids
  - does NOT depend on fixture ordering or shared mutable state
  - does NOT assume any fixed event_id, registration_id, or QR token

Run from the repo root:
    pytest backend/tests -v

Run from backend/:
    pytest tests -v

Prerequisites:
  - events_db running and migrated
  - backend/.env with correct EVENTS_DB_URL
  - APP_ENV=development (set in .env)
"""
import uuid
import pytest

# ── Auth header shortcuts ─────────────────────────────────────────────────────
ADMIN = {"X-Dev-User": "admin"}
ATTENDEE = {"X-Dev-User": "attendee"}

# A future date used for all test events so capacity/window rules never fire.
_FUTURE = "2027-06-15T10:00:00+05:30"


# ── Helpers ───────────────────────────────────────────────────────────────────

def uid() -> str:
    """Short collision-resistant suffix — safe for slugs, emails, ref_ids."""
    return uuid.uuid4().hex[:10]


def _make_event(client, *, publish: bool = False, capacity: int = 50) -> dict:
    """Create a draft event; optionally publish it. Returns the event dict."""
    s = uid()
    r = client.post(
        "/api/v1/admin/events",
        json={
            "slug": f"test-{s}",
            "title": f"Test Event {s}",
            "description": "Created by pytest",
            "starts_at": _FUTURE,
            "capacity": capacity,
        },
        headers=ADMIN,
    )
    assert r.status_code == 201, f"event create failed: {r.text}"
    event = r.json()
    if publish:
        r2 = client.post(
            f"/api/v1/admin/events/{event['event_id']}/publish",
            headers=ADMIN,
        )
        assert r2.status_code == 200, f"event publish failed: {r2.text}"
        event = r2.json()
    return event


def _make_registration(client, event_id: int, *, ref_id: str = None) -> dict:
    """Register a fresh attendee on the given event. Returns the registration dict."""
    s = uid()
    r = client.post(
        f"/api/v1/events/{event_id}/register",
        json={
            "full_name": f"Test Alumnus {s}",
            "email": f"user-{s}@example.com",
            "ref_id": ref_id or f"NITK-{s}",
        },
        headers=ATTENDEE,
    )
    assert r.status_code == 201, f"registration failed: {r.text}"
    return r.json()


# ─────────────────────────────────────────────────────────────────────────────
# A. Health endpoints
# ─────────────────────────────────────────────────────────────────────────────

def test_health_endpoints(client):
    # Root health — no auth, no DB required
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert r.json()["service"] == "NITKSAA Event API"

    # API health — confirms DB connectivity
    r = client.get("/api/v1/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert data["db"] == "ok"
    assert "version" in data
    assert "env" in data


# ─────────────────────────────────────────────────────────────────────────────
# B. Event lifecycle: create → draft not public → publish → visible publicly
# ─────────────────────────────────────────────────────────────────────────────

def test_event_create_publish_and_public_visibility(client):
    # --- Create as draft ---
    event = _make_event(client)
    event_id = event["event_id"]
    assert event_id > 0
    assert event["status"] == "draft"
    assert event["created_by"] == "dev-admin-firebase-uid"

    # Draft must NOT appear in public listing
    public_ids = [e["event_id"] for e in client.get("/api/v1/events").json()]
    assert event_id not in public_ids, "draft event must not appear in public listing"

    # Accessing draft via public detail endpoint must return 400
    r = client.get(f"/api/v1/events/{event_id}")
    assert r.status_code == 400
    assert r.json()["detail"] == "event_not_published"

    # --- Publish ---
    r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=ADMIN)
    assert r.status_code == 200
    assert r.json()["status"] == "published"
    assert r.json()["event_id"] == event_id

    # Attempting to publish again must return 400 (already published)
    r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=ADMIN)
    assert r.status_code == 400
    assert r.json()["detail"] == "only_draft_events_can_be_published"

    # Published event appears in public listing
    public_ids = [e["event_id"] for e in client.get("/api/v1/events").json()]
    assert event_id in public_ids, "published event must appear in public listing"

    # Public detail returns correct data
    r = client.get(f"/api/v1/events/{event_id}")
    assert r.status_code == 200
    detail = r.json()
    assert detail["status"] == "published"
    assert detail["event_id"] == event_id
    assert detail["slug"].startswith("test-")

    # Admin can also see draft events in admin listing
    admin_ids = [e["event_id"] for e in
                 client.get("/api/v1/admin/events", headers=ADMIN).json()]
    assert event_id in admin_ids


# ─────────────────────────────────────────────────────────────────────────────
# C. Registration lifecycle and duplicate prevention
# ─────────────────────────────────────────────────────────────────────────────

def test_attendee_registration_and_duplicates(client):
    event = _make_event(client, publish=True)
    event_id = event["event_id"]
    s = uid()
    email = f"rajesh-{s}@example.com"
    ref_id = f"NITK-REF-{s}"

    # --- Successful registration ---
    r = client.post(
        f"/api/v1/events/{event_id}/register",
        json={"full_name": "Rajesh Nair", "email": email, "ref_id": ref_id},
        headers=ATTENDEE,
    )
    assert r.status_code == 201, r.text
    reg = r.json()

    assert reg["registration_id"] > 0
    assert reg["event_id"] == event_id
    assert reg["status"] == "registered"
    assert reg["registration_source"] == "api_alpha"
    assert reg["email"] == email
    assert reg["qr_token"].startswith("nitksaa_evt_"), (
        f"QR token must start with 'nitksaa_evt_', got: {reg['qr_token']}"
    )
    # metadata must deserialise to an empty dict (not a raw string)
    assert isinstance(reg["metadata"], dict)

    # Auth context injected: firebase_uid and ref_id populated from dev user
    assert reg["firebase_uid"] == "dev-attendee-firebase-uid"
    assert reg["ref_id"] == ref_id

    # --- Duplicate by email (same event) → 409 ---
    r = client.post(
        f"/api/v1/events/{event_id}/register",
        json={"full_name": "Same Email Different Name", "email": email},
        headers=ATTENDEE,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "registration_duplicate"

    # --- Duplicate by ref_id (different email, same ref_id) → 409 ---
    r = client.post(
        f"/api/v1/events/{event_id}/register",
        json={
            "full_name": "Different Email Same Ref",
            "email": f"other-{uid()}@example.com",
            "ref_id": ref_id,
        },
        headers=ATTENDEE,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "registration_duplicate"

    # --- Same email on a DIFFERENT event is allowed ---
    event2 = _make_event(client, publish=True)
    r = client.post(
        f"/api/v1/events/{event2['event_id']}/register",
        json={"full_name": "Rajesh Different Event", "email": email},
        headers=ATTENDEE,
    )
    assert r.status_code == 201, (
        f"same email on different event should succeed, got {r.status_code}: {r.text}"
    )

    # --- Registration detail accessible by authenticated user ---
    reg_id = reg["registration_id"]
    r = client.get(
        f"/api/v1/events/{event_id}/registrations/{reg_id}",
        headers=ATTENDEE,
    )
    assert r.status_code == 200
    assert r.json()["registration_id"] == reg_id


# ─────────────────────────────────────────────────────────────────────────────
# D. QR verify → check-in → status change → duplicates → attempt audit log
# ─────────────────────────────────────────────────────────────────────────────

def test_qr_verify_checkin_and_duplicate_attempts(client):
    event = _make_event(client, publish=True)
    event_id = event["event_id"]
    reg = _make_registration(client, event_id)
    reg_id = reg["registration_id"]
    qr = reg["qr_token"]

    # 1 ── Verify QR before check-in ─────────────────────────────────────────
    r = client.get(
        f"/api/v1/admin/events/{event_id}/check-ins/verify",
        params={"qr_token": qr},
        headers=ADMIN,
    )
    assert r.status_code == 200
    v = r.json()
    assert v["valid"] is True
    assert v["already_checked_in"] is False
    assert v["message"] == "ready_to_checkin"
    assert v["registration_id"] == reg_id
    assert v["full_name"] == reg["full_name"]
    assert v["registration_status"] == "registered"

    # 2 ── Check-in succeeds ──────────────────────────────────────────────────
    r = client.post(
        f"/api/v1/admin/events/{event_id}/check-ins",
        json={"qr_token": qr},
        headers=ADMIN,
    )
    assert r.status_code == 201, r.text
    ci = r.json()
    assert ci["qr_token"] == qr
    assert ci["registration_id"] == reg_id
    assert ci["event_id"] == event_id
    assert ci["method"] == "qr"
    assert ci["checked_in_by"] == "dev-admin-firebase-uid"
    assert isinstance(ci["metadata"], dict)

    # 3 ── Registration status changed to checked_in ──────────────────────────
    regs = client.get(
        f"/api/v1/admin/events/{event_id}/registrations",
        headers=ADMIN,
    ).json()
    status_map = {r["registration_id"]: r["status"] for r in regs}
    assert status_map[reg_id] == "checked_in", (
        f"Expected registration {reg_id} status='checked_in', got '{status_map.get(reg_id)}'"
    )

    # 4 ── Duplicate check-in → 409 ──────────────────────────────────────────
    r = client.post(
        f"/api/v1/admin/events/{event_id}/check-ins",
        json={"qr_token": qr},
        headers=ADMIN,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "already_checked_in"

    # 5 ── Invalid QR token → 404 ─────────────────────────────────────────────
    r = client.post(
        f"/api/v1/admin/events/{event_id}/check-ins",
        json={"qr_token": "nitksaa_evt_INVALID_TOKEN_PYTEST_XYZ"},
        headers=ADMIN,
    )
    assert r.status_code == 404
    assert r.json()["detail"] == "invalid_qr_token"

    # 6 ── Verify QR after check-in reflects new state ────────────────────────
    r = client.get(
        f"/api/v1/admin/events/{event_id}/check-ins/verify",
        params={"qr_token": qr},
        headers=ADMIN,
    )
    assert r.status_code == 200
    v = r.json()
    assert v["valid"] is True
    assert v["already_checked_in"] is True
    assert v["registration_status"] == "checked_in"
    assert v["message"] == "already_checked_in"

    # 7 ── Check-in list contains the record ─────────────────────────────────
    r = client.get(
        f"/api/v1/admin/events/{event_id}/check-ins",
        headers=ADMIN,
    )
    assert r.status_code == 200
    checkins = r.json()
    ci_reg_ids = [c["registration_id"] for c in checkins]
    assert reg_id in ci_reg_ids

    # 8 ── Attempt audit log contains success, duplicate, and invalid ─────────
    r = client.get(
        f"/api/v1/admin/events/{event_id}/check-in-attempts",
        headers=ADMIN,
    )
    assert r.status_code == 200
    attempts = r.json()
    logged_statuses = {a["attempt_status"] for a in attempts}
    assert "success" in logged_statuses, (
        f"'success' not found in attempt log statuses: {logged_statuses}"
    )
    assert "duplicate" in logged_statuses, (
        f"'duplicate' not found in attempt log statuses: {logged_statuses}"
    )
    assert "invalid" in logged_statuses, (
        f"'invalid' not found in attempt log statuses: {logged_statuses}"
    )

    # Verify successful attempt has correct qr_token logged
    success_attempts = [a for a in attempts if a["attempt_status"] == "success"]
    assert any(a["qr_token"] == qr for a in success_attempts), (
        "success attempt must record the correct qr_token"
    )


# ─────────────────────────────────────────────────────────────────────────────
# E. Closed event blocks further registration
# ─────────────────────────────────────────────────────────────────────────────

def test_closed_event_blocks_registration(client):
    event = _make_event(client, publish=True)
    event_id = event["event_id"]

    # Register one attendee before closing (proves it works while open)
    reg = _make_registration(client, event_id)
    assert reg["status"] == "registered"

    # Close the event
    r = client.post(f"/api/v1/admin/events/{event_id}/close", headers=ADMIN)
    assert r.status_code == 200
    assert r.json()["status"] == "closed"

    # Closing again must fail (not a valid transition from closed)
    r = client.post(f"/api/v1/admin/events/{event_id}/close", headers=ADMIN)
    assert r.status_code == 400
    assert r.json()["detail"] == "event_cannot_be_closed"

    # Registration on closed event must be blocked
    r = client.post(
        f"/api/v1/events/{event_id}/register",
        json={"full_name": "Late Comer", "email": f"late-{uid()}@example.com"},
        headers=ATTENDEE,
    )
    assert r.status_code == 400
    assert r.json()["detail"] == "event_not_published"

    # Public detail must also return 400 (closed ≠ published)
    r = client.get(f"/api/v1/events/{event_id}")
    assert r.status_code == 400
    assert r.json()["detail"] == "event_not_published"


# ─────────────────────────────────────────────────────────────────────────────
# F. Access control
# ─────────────────────────────────────────────────────────────────────────────

def test_access_control(client):
    event = _make_event(client, publish=True)
    event_id = event["event_id"]

    # Attendee → create event (admin endpoint) → 403
    r = client.post(
        "/api/v1/admin/events",
        json={"slug": f"blocked-{uid()}", "title": "Blocked", "starts_at": _FUTURE},
        headers=ATTENDEE,
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "admin_required"

    # Attendee → list registrations (admin endpoint) → 403
    r = client.get(
        f"/api/v1/admin/events/{event_id}/registrations",
        headers=ATTENDEE,
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "admin_required"

    # Attendee → check-in (admin endpoint) → 403
    r = client.post(
        f"/api/v1/admin/events/{event_id}/check-ins",
        json={"qr_token": "nitksaa_evt_whatever"},
        headers=ATTENDEE,
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "admin_required"

    # No auth → register → 401
    r = client.post(
        f"/api/v1/events/{event_id}/register",
        json={"full_name": "No Auth User", "email": f"noauth-{uid()}@example.com"},
    )
    assert r.status_code == 401

    # No auth → public event list → 200 (no auth required)
    r = client.get("/api/v1/events")
    assert r.status_code == 200
    assert isinstance(r.json(), list)

    # No auth → public event detail → 200 (no auth required)
    r = client.get(f"/api/v1/events/{event_id}")
    assert r.status_code == 200
    assert r.json()["event_id"] == event_id

    # No auth → public sessions list → 200 (no auth required)
    r = client.get(f"/api/v1/events/{event_id}/sessions")
    assert r.status_code == 200
    assert isinstance(r.json(), list)


# ─────────────────────────────────────────────────────────────────────────────
# G. Admin listings: sessions, attendees, update event, admin event list
# ─────────────────────────────────────────────────────────────────────────────

def test_admin_listings_and_sessions(client):
    event = _make_event(client, publish=True)
    event_id = event["event_id"]

    # ── Sessions ─────────────────────────────────────────────────────────────
    # No sessions yet — public endpoint returns empty list
    r = client.get(f"/api/v1/events/{event_id}/sessions")
    assert r.status_code == 200
    assert r.json() == []

    # Create a session (admin)
    r = client.post(
        f"/api/v1/admin/events/{event_id}/sessions",
        json={
            "title": "Opening Keynote",
            "speaker_name": "Prof. Ramesh Kumar",
            "location": "Main Auditorium",
            "starts_at": _FUTURE,
            "sort_order": 1,
        },
        headers=ADMIN,
    )
    assert r.status_code == 201, r.text
    session = r.json()
    assert session["session_id"] > 0
    assert session["event_id"] == event_id
    assert session["title"] == "Opening Keynote"
    assert session["status"] == "scheduled"
    assert session["sort_order"] == 1

    # Session now appears in public sessions list
    r = client.get(f"/api/v1/events/{event_id}/sessions")
    assert r.status_code == 200
    sessions = r.json()
    assert len(sessions) == 1
    assert sessions[0]["session_id"] == session["session_id"]

    # ── Event update (PATCH) ──────────────────────────────────────────────────
    r = client.patch(
        f"/api/v1/admin/events/{event_id}",
        json={"description": "Updated by pytest PATCH test"},
        headers=ADMIN,
    )
    assert r.status_code == 200
    assert r.json()["description"] == "Updated by pytest PATCH test"

    # ── Attendees list ────────────────────────────────────────────────────────
    # No registrations yet — attendee list is empty
    r = client.get(f"/api/v1/admin/events/{event_id}/attendees", headers=ADMIN)
    assert r.status_code == 200
    assert r.json() == []

    # Register two attendees
    reg1 = _make_registration(client, event_id)
    reg2 = _make_registration(client, event_id)

    r = client.get(f"/api/v1/admin/events/{event_id}/attendees", headers=ADMIN)
    assert r.status_code == 200
    attendees = r.json()
    assert len(attendees) == 2
    for a in attendees:
        assert a["event_id"] == event_id
        assert a["attendee_type"] == "alumni"
        assert a["display_name"]  # not empty

    attendee_reg_ids = {a["registration_id"] for a in attendees}
    assert reg1["registration_id"] in attendee_reg_ids
    assert reg2["registration_id"] in attendee_reg_ids

    # ── Admin registrations list ──────────────────────────────────────────────
    r = client.get(f"/api/v1/admin/events/{event_id}/registrations", headers=ADMIN)
    assert r.status_code == 200
    regs = r.json()
    assert len(regs) == 2
    for reg in regs:
        assert reg["event_id"] == event_id
        assert reg["qr_token"].startswith("nitksaa_evt_")
        assert isinstance(reg["metadata"], dict)

    # ── Admin all-events list includes this event ─────────────────────────────
    r = client.get("/api/v1/admin/events", headers=ADMIN)
    assert r.status_code == 200
    all_ids = [e["event_id"] for e in r.json()]
    assert event_id in all_ids

    # ── Check-in with session_id ──────────────────────────────────────────────
    session_id = session["session_id"]
    qr = reg1["qr_token"]
    r = client.post(
        f"/api/v1/admin/events/{event_id}/check-ins",
        json={"qr_token": qr, "session_id": session_id, "notes": "pytest checkin"},
        headers=ADMIN,
    )
    assert r.status_code == 201, r.text
    ci = r.json()
    assert ci["session_id"] == session_id
    assert ci["notes"] == "pytest checkin"
