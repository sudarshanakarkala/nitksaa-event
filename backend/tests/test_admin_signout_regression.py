"""Regression coverage for the admin *unexpected sign-out* bug.

Symptom: an authenticated administrator was signed out the moment they hit
almost any admin action (Create Event, list events, enrichment, …).

Root cause had two layers:
  1. Frontend (admin/event_admin/src/api/apiClient.js): `request()` treated
     `401 || 403` identically — clearSession() + hard redirect to /login. A
     403 from ordinary RBAC / event-scope denial therefore destroyed a valid
     session. (Fixed in the frontend + covered by
     admin/event_admin/src/api/apiClient.test.js.)
  2. Environment: the signed-in Firebase admin held no platform_admin grant
     (PLATFORM_ADMIN_FIREBASE_UIDS unset, no payment_platform_roles row), so
     every platform-scoped admin call correctly returned 403.

This suite pins the *backend* half of the contract the frontend fix relies
on: authorization failures for a *validly authenticated* caller must be a
clean, self-describing 403 (never 401), while genuinely broken/absent
authentication stays a fail-closed 401 — so the client can tell "not
allowed" apart from "not signed in" and only sign out for the latter.
"""
import asyncio
import time
import uuid

import asyncpg
import pytest

from app.config import get_settings
from app.middleware.auth import ALGORITHM, make_access_token

_NON_ADMIN = {
    "firebase_uid": "TEST_SIGNOUT_REGRESSION_UID_200",
    "sub": "signout.regression.plain@nitksaa.dev",
    "email": "signout.regression.plain@nitksaa.dev",
    "fullname": "Signout Regression Plain User",
    "user_type": "alumni",
    "ref_id": "NITK2018CS200",
    "graduation_year": 2018,
}
_ADMIN = {
    "firebase_uid": "TEST_SIGNOUT_REGRESSION_UID_201",
    "sub": "signout.regression.admin@nitksaa.dev",
    "email": "signout.regression.admin@nitksaa.dev",
    "fullname": "Signout Regression Admin",
    "user_type": "alumni",
    "ref_id": "NITK2018CS201",
    "graduation_year": 2018,
}

_FUTURE_START = "2027-12-01T08:00:00+05:30"
_FUTURE_END = "2027-12-01T10:00:00+05:30"


def _db_exec(query: str, *args) -> None:
    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            await conn.execute(query, *args)
        finally:
            await conn.close()

    asyncio.run(_run())


@pytest.fixture(autouse=True)
def _seed_identities():
    for identity in (_NON_ADMIN, _ADMIN):
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (firebase_uid) DO NOTHING
            """,
            identity["firebase_uid"], identity["email"], identity["fullname"],
            identity["user_type"], identity["ref_id"], identity["graduation_year"],
        )


def _bearer(identity: dict) -> dict:
    return {"Authorization": f"Bearer {make_access_token(dict(identity))}"}


def _expired_bearer(identity: dict) -> dict:
    from jose import jwt

    payload = {**identity, "exp": int(time.time()) - 60}
    token = jwt.encode(payload, get_settings().secret_key, algorithm=ALGORITHM)
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def as_platform_admin(monkeypatch):
    monkeypatch.setenv("PLATFORM_ADMIN_FIREBASE_UIDS", _ADMIN["firebase_uid"])
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


# ── The authenticated-but-not-authorized caller: must be 403, never 401 ──────

@pytest.mark.parametrize(
    "method, path, body",
    [
        ("POST", "/api/v1/events", {
            "title": "Signout Regression Event", "description": "d",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Venue", "is_virtual": False, "capacity": 10,
        }),
        ("GET", "/api/v1/events", None),
        ("POST", "/api/v1/admin/events", {
            "title": "Signout Regression Event 2", "description": "d",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Venue", "is_virtual": False, "capacity": 10,
        }),
        ("GET", "/api/v1/admin/events", None),
    ],
)
def test_authenticated_non_admin_gets_403_not_401(client, method, path, body):
    resp = client.request(method, path, json=body, headers=_bearer(_NON_ADMIN))
    assert resp.status_code == 403, resp.text
    # Self-describing, non-auth detail — the frontend keeps the session on this.
    detail = resp.json()["detail"]
    assert detail in {"payment_role_required", "event_admin_required"}, detail


def test_event_scoped_denial_is_403_for_authenticated_non_admin(client, as_platform_admin):
    # Admin creates a real event…
    created = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"Scoped Denial {uuid.uuid4().hex[:8]}", "description": "d",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Venue", "is_virtual": False, "capacity": 10,
        },
        headers=_bearer(_ADMIN),
    )
    assert created.status_code == 201, created.text
    event_id = created.json()["event_id"]

    # …a validly-authenticated non-admin is refused with 403, not signed out.
    resp = client.get(f"/api/v1/events/{event_id}", headers=_bearer(_NON_ADMIN))
    assert resp.status_code == 403, resp.text
    assert resp.json()["detail"] == "event_admin_required"


# ── Genuinely broken / absent authentication: stays fail-closed ─────────────

def test_missing_bearer_is_rejected(client):
    resp = client.post("/api/v1/events", json={"title": "x"})
    assert resp.status_code in {401, 403}  # FastAPI HTTPBearer → 403 when header absent
    assert "access_token" not in resp.text


def test_invalid_bearer_is_401(client):
    resp = client.get("/api/v1/events", headers={"Authorization": "Bearer not-a-real-jwt"})
    assert resp.status_code == 401, resp.text
    assert resp.json()["detail"] == "invalid_or_expired_token"


def test_expired_bearer_is_401(client):
    resp = client.get("/api/v1/events", headers=_expired_bearer(_NON_ADMIN))
    assert resp.status_code == 401, resp.text
    assert resp.json()["detail"] == "invalid_or_expired_token"


def test_role_injection_via_headers_body_query_cannot_elevate(client):
    """A non-admin cannot become platform_admin by asserting it themselves."""
    resp = client.post(
        "/api/v1/events?role=platform_admin",
        json={
            "title": "Injection Attempt", "description": "d",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Venue", "is_virtual": False, "capacity": 10,
            "role": "platform_admin", "user_type": "platform_admin",
        },
        headers={**_bearer(_NON_ADMIN), "X-Dev-User": "admin", "X-Dev-Role": "platform_admin",
                 "X-Role": "platform_admin"},
    )
    assert resp.status_code == 403, resp.text


# ── The authorized admin: create → read → update → publish, no sign-out ─────

def test_platform_admin_full_event_lifecycle_stays_authorized(client, as_platform_admin):
    admin = _bearer(_ADMIN)

    create = client.post(
        "/api/v1/events",
        json={
            "title": f"Lifecycle {uuid.uuid4().hex[:8]}", "description": "d",
            "start_datetime": _FUTURE_START, "end_datetime": _FUTURE_END,
            "location_text": "Venue", "is_virtual": False, "capacity": 25,
        },
        headers=admin,
    )
    assert create.status_code == 201, create.text
    event_id = create.json()["event"]["event_id"]

    got = client.get(f"/api/v1/events/{event_id}", headers=admin)
    assert got.status_code == 200, got.text

    patched = client.patch(
        f"/api/v1/events/{event_id}", json={"title": "Lifecycle (edited)"}, headers=admin
    )
    assert patched.status_code == 200, patched.text

    published = client.patch(
        f"/api/v1/events/{event_id}/status", json={"status": "published"}, headers=admin
    )
    assert published.status_code == 200, published.text

    # Not one of those four calls was a 401/403 — the session is untouched.


def test_malformed_create_is_422_for_authorized_admin(client, as_platform_admin):
    resp = client.post(
        "/api/v1/events",
        json={"title": "", "start_datetime": "not-a-date"},
        headers=_bearer(_ADMIN),
    )
    assert resp.status_code == 422, resp.text
