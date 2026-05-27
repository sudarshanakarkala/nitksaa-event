"""
Alpha event flow tests.

These tests use FastAPI's TestClient with a real PostgreSQL events_db.
Set EVENTS_DB_URL in your environment or .env before running.

Run:
    cd backend
    pytest tests/test_event_flow.py -v

If DB is not available these tests will be skipped automatically.
"""
import os
import pytest
import asyncio
import asyncpg
from fastapi.testclient import TestClient

# Attempt DB import; skip all if not available
try:
    from app.main import app
    from app.config import get_settings
    IMPORT_OK = True
except Exception:
    IMPORT_OK = False

pytestmark = pytest.mark.skipif(not IMPORT_OK, reason="app import failed — check dependencies")

ADMIN_HEADERS = {"X-Dev-User": "admin"}
ATTENDEE_HEADERS = {"X-Dev-User": "attendee"}


@pytest.fixture(scope="module")
def client():
    with TestClient(app, raise_server_exceptions=True) as c:
        yield c


# ── Helpers ───────────────────────────────────────────────────────────────────

def _check_db_available(client: TestClient) -> bool:
    r = client.get("/api/v1/health")
    return r.status_code == 200 and r.json().get("db") == "ok"


# ── Health ────────────────────────────────────────────────────────────────────

def test_root_health(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_api_health(client):
    r = client.get("/api/v1/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert "version" in data


# ── Event lifecycle ───────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def created_event(client):
    if not _check_db_available(client):
        pytest.skip("events_db not available")
    payload = {
        "slug": f"test-event-pytest-{os.getpid()}",
        "title": "Pytest Test Event",
        "description": "Created by automated test",
        "starts_at": "2026-12-20T10:00:00+05:30",
        "capacity": 10,
    }
    r = client.post("/api/v1/admin/events", json=payload, headers=ADMIN_HEADERS)
    assert r.status_code == 201, r.text
    event = r.json()
    assert event["status"] == "draft"
    assert event["slug"] == payload["slug"]
    return event


def test_create_event(created_event):
    assert created_event["event_id"] > 0


def test_publish_event(client, created_event):
    event_id = created_event["event_id"]
    r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=ADMIN_HEADERS)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "published"


def test_list_public_events(client, created_event):
    r = client.get("/api/v1/events")
    assert r.status_code == 200
    ids = [e["event_id"] for e in r.json()]
    assert created_event["event_id"] in ids


def test_get_published_event(client, created_event):
    r = client.get(f"/api/v1/events/{created_event['event_id']}")
    assert r.status_code == 200
    assert r.json()["status"] == "published"


# ── Registration ──────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def registration(client, created_event):
    event_id = created_event["event_id"]
    payload = {
        "full_name": "Test Alumni",
        "email": f"test.alumni.{os.getpid()}@example.com",
        "ref_id": f"ALUMNI-TEST-{os.getpid()}",
    }
    r = client.post(
        f"/api/v1/events/{event_id}/register",
        json=payload,
        headers=ATTENDEE_HEADERS,
    )
    assert r.status_code == 201, r.text
    reg = r.json()
    assert reg["qr_token"].startswith("nitksaa_evt_")
    return reg


def test_register_attendee(registration):
    assert registration["registration_id"] > 0
    assert registration["status"] == "registered"


def test_duplicate_registration_blocked(client, created_event, registration):
    event_id = created_event["event_id"]
    payload = {
        "full_name": "Duplicate Attempt",
        "email": registration["email"],
    }
    r = client.post(
        f"/api/v1/events/{event_id}/register",
        json=payload,
        headers=ATTENDEE_HEADERS,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "registration_duplicate"


# ── Check-In ──────────────────────────────────────────────────────────────────

def test_verify_qr_before_checkin(client, created_event, registration):
    event_id = created_event["event_id"]
    qr = registration["qr_token"]
    r = client.get(
        f"/api/v1/admin/events/{event_id}/check-ins/verify",
        params={"qr_token": qr},
        headers=ADMIN_HEADERS,
    )
    assert r.status_code == 200
    data = r.json()
    assert data["valid"] is True
    assert data["already_checked_in"] is False
    assert data["message"] == "ready_to_checkin"


def test_checkin_succeeds(client, created_event, registration):
    event_id = created_event["event_id"]
    qr = registration["qr_token"]
    r = client.post(
        f"/api/v1/admin/events/{event_id}/check-ins",
        json={"qr_token": qr},
        headers=ADMIN_HEADERS,
    )
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["qr_token"] == qr


def test_duplicate_checkin_blocked(client, created_event, registration):
    event_id = created_event["event_id"]
    qr = registration["qr_token"]
    r = client.post(
        f"/api/v1/admin/events/{event_id}/check-ins",
        json={"qr_token": qr},
        headers=ADMIN_HEADERS,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "already_checked_in"


def test_invalid_qr_blocked(client, created_event):
    event_id = created_event["event_id"]
    r = client.post(
        f"/api/v1/admin/events/{event_id}/check-ins",
        json={"qr_token": "nitksaa_evt_INVALID_TOKEN_XYZ"},
        headers=ADMIN_HEADERS,
    )
    assert r.status_code == 404
    assert r.json()["detail"] == "invalid_qr_token"


def test_checkin_attempt_logged(client, created_event):
    event_id = created_event["event_id"]
    r = client.get(
        f"/api/v1/admin/events/{event_id}/check-in-attempts",
        headers=ADMIN_HEADERS,
    )
    assert r.status_code == 200
    attempts = r.json()
    statuses = {a["attempt_status"] for a in attempts}
    # After the test run we should see success, duplicate, and invalid
    assert "success" in statuses
    assert "duplicate" in statuses
    assert "invalid" in statuses


# ── Access control ────────────────────────────────────────────────────────────

def test_admin_endpoint_requires_admin(client, created_event):
    event_id = created_event["event_id"]
    r = client.get(
        f"/api/v1/admin/events/{event_id}/registrations",
        headers=ATTENDEE_HEADERS,
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "admin_required"


def test_no_auth_returns_401(client, created_event):
    event_id = created_event["event_id"]
    r = client.post(f"/api/v1/events/{event_id}/register", json={
        "full_name": "No Auth User",
        "email": "noauth@example.com",
    })
    assert r.status_code == 401
