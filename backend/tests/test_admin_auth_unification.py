"""Admin-auth-unification sprint — RBAC/adversarial/functional/audit tests
for the three routers migrated off app.middleware.dev_auth in this sprint:
app/api/events.py (admin routes only — the public routes are unauthenticated
by design and unchanged), app/api/people.py, app/api/sponsors_partners.py.

Methodology mirrors tests/test_admin_rbac.py (the admin_events.py RBAC
suite from the prior operational-readiness sprint): real HTTP requests
through TestClient, real Firebase-JWT bearer tokens, real DB-state and
audit assertions — never a dependency-level unit test standing in for an
actual request.

Pre-migration, this whole surface trusted only an unauthenticated
X-Dev-User header (see docs/payments/ADMIN_AUTH_UNIFICATION_SPRINT_REPORT.md
for the concrete before/after reproduction) — every test in this file
encodes the POST-migration behavior; the defect itself is not re-asserted
as passing anywhere here.
"""
import uuid

import pytest

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_090",
    "sub": "platform.admin.authunify@nitksaa.dev",
    "email": "platform.admin.authunify@nitksaa.dev",
    "fullname": "Platform Admin AuthUnify Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS090",
    "graduation_year": 2018,
}
_EVENT_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_091",
    "sub": "event.admin.authunify@nitksaa.dev",
    "email": "event.admin.authunify@nitksaa.dev",
    "fullname": "Event Admin AuthUnify Test",
    "user_type": "alumni",
    "ref_id": "NITK2019CS091",
    "graduation_year": 2019,
}
_ATTENDEE = {
    "firebase_uid": "TEST_ALUMNI_UID_092",
    "sub": "attendee.authunify@nitksaa.dev",
    "email": "attendee.authunify@nitksaa.dev",
    "fullname": "Attendee AuthUnify Test",
    "user_type": "alumni",
    "ref_id": "NITK2020CS092",
    "graduation_year": 2020,
}

_FUTURE_START = "2027-11-01T08:00:00+05:30"
_FUTURE_END = "2027-11-01T10:00:00+05:30"


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


def _db_fetch(query: str, *args):
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


@pytest.fixture(autouse=True)
def _seed_test_identities():
    for identity in (_PLATFORM_ADMIN, _EVENT_ADMIN, _ATTENDEE):
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (firebase_uid) DO NOTHING
            """,
            identity["firebase_uid"], identity["email"], identity["fullname"],
            identity["user_type"], identity["ref_id"], identity["graduation_year"],
        )


def _grant_event_admin(client, admin_headers: dict, event_id: int, firebase_uid: str) -> None:
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-admins",
        json={"firebase_uid": firebase_uid},
        headers=admin_headers,
    )
    assert r.status_code == 201, r.text


def _mk_event(client, admin_headers: dict, uid_suffix: str, *, publish: bool = False) -> int:
    """Real event, created via admin_events.py's own working create route
    (real RBAC) — not events.py's, since these tests exist specifically to
    prove events.py's OWN admin routes now also require real RBAC; using it
    for fixture setup would make that circular."""
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST AUTHUNIFY EVENT {uid_suffix}", "description": "Created by pytest",
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


def _audit_count(entity_type: str, entity_id: int) -> int:
    return _db_fetch(
        "SELECT count(*) AS n FROM event_audit_log WHERE entity_type = $1 AND entity_id = $2",
        entity_type, entity_id,
    )[0]["n"]


def _latest_audit_actor(entity_type: str, entity_id: int, event_type: str) -> str:
    rows = _db_fetch(
        """
        SELECT actor_uid FROM event_audit_log
        WHERE entity_type = $1 AND entity_id = $2 AND event_type = $3
        ORDER BY created_at DESC LIMIT 1
        """,
        entity_type, entity_id, event_type,
    )
    assert rows, f"no audit row found for {entity_type}/{entity_id}/{event_type}"
    return rows[0]["actor_uid"]


# Route registry across all three migrated routers.
# (label, method, path template, body-or-None, has_event_id)
# path template takes {event_id} and, where relevant, {person_id}/
# {sponsor_id}/{partner_id} — bogus sentinel IDs are fine for pure
# denial coverage since auth runs before any DB lookup for that resource.
_PERSON_BODY = {"role": "SPEAKER", "fullname": "Test Speaker"}
_SPONSOR_BODY = {"sponsor_type": "GOLD_SPONSOR", "name": "Test Sponsor"}
_PARTNER_BODY = {"partner_type": "TECHNOLOGY_PARTNER", "name": "Test Partner"}

_PLATFORM_ONLY_ROUTES = [
    ("events_create", "POST", "/api/v1/events", {
        "title": "Test Event Title", "description": "d", "start_datetime": _FUTURE_START,
        "end_datetime": _FUTURE_END, "location_text": "Venue", "is_virtual": False, "capacity": 10,
    }, False),
    ("events_list", "GET", "/api/v1/events", None, False),
]

_EVENT_SCOPED_ROUTES = [
    ("events_get", "GET", "/api/v1/events/{event_id}", None),
    ("events_update_status", "PATCH", "/api/v1/events/{event_id}/status", {"status": "published"}),
    ("events_update", "PATCH", "/api/v1/events/{event_id}", {"title": "Updated Title"}),
    ("people_list", "GET", "/api/v1/events/{event_id}/people", None),
    ("people_create", "POST", "/api/v1/events/{event_id}/people", _PERSON_BODY),
    ("people_update", "PUT", "/api/v1/events/{event_id}/people/999999999", {"fullname": "X"}),
    ("people_delete", "DELETE", "/api/v1/events/{event_id}/people/999999999", None),
    ("sponsors_list", "GET", "/api/v1/events/{event_id}/sponsors", None),
    ("sponsors_create", "POST", "/api/v1/events/{event_id}/sponsors", _SPONSOR_BODY),
    ("sponsors_update", "PUT", "/api/v1/events/{event_id}/sponsors/999999999", {"name": "X"}),
    ("sponsors_delete", "DELETE", "/api/v1/events/{event_id}/sponsors/999999999", None),
    ("partners_list", "GET", "/api/v1/events/{event_id}/partners", None),
    ("partners_create", "POST", "/api/v1/events/{event_id}/partners", _PARTNER_BODY),
    ("partners_update", "PUT", "/api/v1/events/{event_id}/partners/999999999", {"name": "X"}),
    ("partners_delete", "DELETE", "/api/v1/events/{event_id}/partners/999999999", None),
]

_ALL_LABELS_EVENT_SCOPED = [r[0] for r in _EVENT_SCOPED_ROUTES]
_ALL_LABELS_PLATFORM_ONLY = [r[0] for r in _PLATFORM_ONLY_ROUTES]


def _call(client, method, path, event_id, body, headers):
    url = path.format(event_id=event_id) if event_id is not None else path
    if method == "GET":
        return client.get(url, headers=headers)
    if method == "POST":
        return client.post(url, json=body or {}, headers=headers)
    if method == "PUT":
        return client.put(url, json=body or {}, headers=headers)
    if method == "PATCH":
        return client.patch(url, json=body or {}, headers=headers)
    if method == "DELETE":
        return client.delete(url, headers=headers)
    raise ValueError(method)


# ═════════════════════════════════════════════════════════════════════════════
# A. Negative/denial coverage — every migrated route, real HTTP requests
# ═════════════════════════════════════════════════════════════════════════════

@pytest.mark.parametrize("label,method,path,body", _EVENT_SCOPED_ROUTES, ids=_ALL_LABELS_EVENT_SCOPED)
def test_event_scoped_route_denies_unauthenticated(client, monkeypatch, label, method, path, body):
    try:
        _as_platform_admin(monkeypatch)
        event_id = _mk_event(client, _bearer(_PLATFORM_ADMIN), f"denyunauth-{label}-{uid()}")
    finally:
        _clear_bootstrap(monkeypatch)
    r = _call(client, method, path, event_id, body, headers={})
    assert r.status_code == 403, f"{label}: expected 403 unauthenticated, got {r.status_code}: {r.text}"


@pytest.mark.parametrize("label,method,path,body", _EVENT_SCOPED_ROUTES, ids=_ALL_LABELS_EVENT_SCOPED)
def test_event_scoped_route_denies_invalid_token(client, monkeypatch, label, method, path, body):
    try:
        _as_platform_admin(monkeypatch)
        event_id = _mk_event(client, _bearer(_PLATFORM_ADMIN), f"denyinvalid-{label}-{uid()}")
    finally:
        _clear_bootstrap(monkeypatch)
    r = _call(client, method, path, event_id, body, headers={"Authorization": "Bearer not-a-real-jwt"})
    assert r.status_code == 401, f"{label}: expected 401 invalid token, got {r.status_code}: {r.text}"


@pytest.mark.parametrize("label,method,path,body", _EVENT_SCOPED_ROUTES, ids=_ALL_LABELS_EVENT_SCOPED)
def test_event_scoped_route_denies_attendee(client, monkeypatch, label, method, path, body):
    try:
        _as_platform_admin(monkeypatch)
        event_id = _mk_event(client, _bearer(_PLATFORM_ADMIN), f"denyattendee-{label}-{uid()}")
    finally:
        _clear_bootstrap(monkeypatch)
    r = _call(client, method, path, event_id, body, headers=_bearer(_ATTENDEE))
    assert r.status_code == 403, f"{label}: expected 403 for plain attendee, got {r.status_code}: {r.text}"


@pytest.mark.parametrize("label,method,path,body", _EVENT_SCOPED_ROUTES, ids=_ALL_LABELS_EVENT_SCOPED)
def test_event_scoped_route_denies_spoofed_dev_header(client, monkeypatch, label, method, path, body):
    """The core regression check for this sprint: a spoofed X-Dev-User:
    admin header — which, pre-migration, was ALONE sufficient to reach
    every one of these routes with zero real authentication (see the
    sprint report's before/after reproduction) — must now be denied."""
    try:
        _as_platform_admin(monkeypatch)
        event_id = _mk_event(client, _bearer(_PLATFORM_ADMIN), f"denyspoof-{label}-{uid()}")
    finally:
        _clear_bootstrap(monkeypatch)
    headers = _bearer(_ATTENDEE)
    headers["X-Dev-User"] = "admin"
    r = _call(client, method, path, event_id, body, headers=headers)
    assert r.status_code == 403, f"{label}: expected 403 for spoofed X-Dev-User, got {r.status_code}: {r.text}"


@pytest.mark.parametrize("label,method,path,body", _EVENT_SCOPED_ROUTES, ids=_ALL_LABELS_EVENT_SCOPED)
def test_event_scoped_route_denies_wrong_event_admin(client, monkeypatch, label, method, path, body):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        own_event_id = _mk_event(client, admin_headers, f"wrongevt-own-{label}-{uid()}")
        other_event_id = _mk_event(client, admin_headers, f"wrongevt-other-{label}-{uid()}")
        _grant_event_admin(client, admin_headers, own_event_id, _EVENT_ADMIN["firebase_uid"])
        r = _call(client, method, path, other_event_id, body, headers=_bearer(_EVENT_ADMIN))
        assert r.status_code == 403, f"{label}: expected 403 on a non-owned event, got {r.status_code}: {r.text}"
    finally:
        _clear_bootstrap(monkeypatch)


@pytest.mark.parametrize("label,method,path,body,has_event_id", _PLATFORM_ONLY_ROUTES, ids=_ALL_LABELS_PLATFORM_ONLY)
def test_platform_only_route_denies_event_admin(client, monkeypatch, label, method, path, body, has_event_id):
    """create/list have no event_id to scope to — event_admin (even for a
    real, owned event) must not satisfy them; platform_admin only."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"platonly-{label}-{uid()}")
        _grant_event_admin(client, admin_headers, event_id, _EVENT_ADMIN["firebase_uid"])
        r = _call(client, method, path, None, body, headers=_bearer(_EVENT_ADMIN))
        assert r.status_code == 403, f"{label}: expected 403 for event_admin, got {r.status_code}: {r.text}"
    finally:
        _clear_bootstrap(monkeypatch)


@pytest.mark.parametrize("label,method,path,body,has_event_id", _PLATFORM_ONLY_ROUTES, ids=_ALL_LABELS_PLATFORM_ONLY)
def test_platform_only_route_denies_spoofed_dev_header(client, label, method, path, body, has_event_id):
    headers = _bearer(_ATTENDEE)
    headers["X-Dev-User"] = "admin"
    r = _call(client, method, path, None, body, headers=headers)
    assert r.status_code == 403, f"{label}: expected 403 for spoofed X-Dev-User, got {r.status_code}: {r.text}"


def test_revoked_event_admin_denied_on_migrated_routes(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"revoke-{uid()}")
        _grant_event_admin(client, admin_headers, event_id, _EVENT_ADMIN["firebase_uid"])

        r = client.get(f"/api/v1/events/{event_id}/people", headers=_bearer(_EVENT_ADMIN))
        assert r.status_code == 200, r.text

        _db_exec(
            "UPDATE event_members SET status = 'revoked' WHERE event_id = $1 AND firebase_uid = $2",
            event_id, _EVENT_ADMIN["firebase_uid"],
        )

        r2 = client.get(f"/api/v1/events/{event_id}/people", headers=_bearer(_EVENT_ADMIN))
        assert r2.status_code == 403, r2.text
        r3 = client.post(f"/api/v1/events/{event_id}/sponsors", json=_SPONSOR_BODY, headers=_bearer(_EVENT_ADMIN))
        assert r3.status_code == 403, r3.text
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# B. Positive coverage — platform_admin and own-event event_admin succeed
# ═════════════════════════════════════════════════════════════════════════════

def test_platform_admin_full_events_admin_flow(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)

        r = client.post("/api/v1/events", json={
            "title": f"Full flow event {uid()}", "description": "d", "start_datetime": _FUTURE_START,
            "end_datetime": _FUTURE_END, "location_text": "Venue", "is_virtual": False, "capacity": 10,
        }, headers=admin_headers)
        assert r.status_code == 201, r.text
        event_id = r.json()["event"]["event_id"]
        assert r.json()["event"]["created_by_firebase_uid"] == _PLATFORM_ADMIN["firebase_uid"]

        r = client.get("/api/v1/events", headers=admin_headers)
        assert r.status_code == 200, r.text
        assert event_id in [e["event_id"] for e in r.json()["events"]]

        r = client.get(f"/api/v1/events/{event_id}", headers=admin_headers)
        assert r.status_code == 200, r.text
        assert r.json()["event"]["event_id"] == event_id

        r = client.patch(f"/api/v1/events/{event_id}", json={"tagline": "Updated tagline"}, headers=admin_headers)
        assert r.status_code == 200, r.text
        assert r.json()["event"]["tagline"] == "Updated tagline"

        r = client.patch(f"/api/v1/events/{event_id}/status", json={"status": "published"}, headers=admin_headers)
        assert r.status_code == 200, r.text
        assert r.json()["event"]["status"] == "published"
    finally:
        _clear_bootstrap(monkeypatch)


def test_own_event_admin_people_sponsors_partners_crud(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"ownevtadmin-{uid()}")
        _grant_event_admin(client, admin_headers, event_id, _EVENT_ADMIN["firebase_uid"])
        event_admin_headers = _bearer(_EVENT_ADMIN)

        r = client.post(f"/api/v1/events/{event_id}/people", json=_PERSON_BODY, headers=event_admin_headers)
        assert r.status_code == 201, r.text
        person_id = r.json()["person_id"]

        r = client.get(f"/api/v1/events/{event_id}/people", headers=event_admin_headers)
        assert r.status_code == 200, r.text
        assert person_id in [p["person_id"] for p in r.json()]

        r = client.put(f"/api/v1/events/{event_id}/people/{person_id}", json={"fullname": "Renamed Speaker"}, headers=event_admin_headers)
        assert r.status_code == 200, r.text
        assert r.json()["fullname"] == "Renamed Speaker"

        r = client.delete(f"/api/v1/events/{event_id}/people/{person_id}", headers=event_admin_headers)
        assert r.status_code == 204, r.text

        r = client.post(f"/api/v1/events/{event_id}/sponsors", json=_SPONSOR_BODY, headers=event_admin_headers)
        assert r.status_code == 201, r.text
        sponsor_id = r.json()["sponsor_id"]
        r = client.put(f"/api/v1/events/{event_id}/sponsors/{sponsor_id}", json={"name": "Renamed Sponsor"}, headers=event_admin_headers)
        assert r.status_code == 200, r.text
        r = client.delete(f"/api/v1/events/{event_id}/sponsors/{sponsor_id}", headers=event_admin_headers)
        assert r.status_code == 204, r.text

        r = client.post(f"/api/v1/events/{event_id}/partners", json=_PARTNER_BODY, headers=event_admin_headers)
        assert r.status_code == 201, r.text
        partner_id = r.json()["partner_id"]
        r = client.put(f"/api/v1/events/{event_id}/partners/{partner_id}", json={"name": "Renamed Partner"}, headers=event_admin_headers)
        assert r.status_code == 200, r.text
        r = client.delete(f"/api/v1/events/{event_id}/partners/{partner_id}", headers=event_admin_headers)
        assert r.status_code == 204, r.text
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# C. Cross-event isolation — resource belongs to a different event
# ═════════════════════════════════════════════════════════════════════════════

def test_person_cross_event_mutation_rejected(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_a = _mk_event(client, admin_headers, f"crossA-{uid()}")
        event_b = _mk_event(client, admin_headers, f"crossB-{uid()}")

        r = client.post(f"/api/v1/events/{event_a}/people", json=_PERSON_BODY, headers=admin_headers)
        assert r.status_code == 201, r.text
        person_id = r.json()["person_id"]

        # Same platform_admin, but targeting event_b's path with event_a's person_id.
        r = client.put(f"/api/v1/events/{event_b}/people/{person_id}", json={"fullname": "Hijacked"}, headers=admin_headers)
        assert r.status_code == 404, r.text
        r = client.delete(f"/api/v1/events/{event_b}/people/{person_id}", headers=admin_headers)
        assert r.status_code == 404, r.text

        row = _db_fetch("SELECT fullname FROM event_people WHERE person_id = $1", person_id)
        assert row[0]["fullname"] == "Test Speaker"
    finally:
        _clear_bootstrap(monkeypatch)


def test_sponsor_cross_event_mutation_rejected(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_a = _mk_event(client, admin_headers, f"crossA-sp-{uid()}")
        event_b = _mk_event(client, admin_headers, f"crossB-sp-{uid()}")

        r = client.post(f"/api/v1/events/{event_a}/sponsors", json=_SPONSOR_BODY, headers=admin_headers)
        assert r.status_code == 201, r.text
        sponsor_id = r.json()["sponsor_id"]

        r = client.put(f"/api/v1/events/{event_b}/sponsors/{sponsor_id}", json={"name": "Hijacked"}, headers=admin_headers)
        assert r.status_code == 404, r.text
        r = client.delete(f"/api/v1/events/{event_b}/sponsors/{sponsor_id}", headers=admin_headers)
        assert r.status_code == 404, r.text
    finally:
        _clear_bootstrap(monkeypatch)


def test_event_admin_a_cannot_administer_event_b_people(client, monkeypatch):
    """Horizontal escalation: an event_admin granted on event A must not be
    able to read/mutate event B's people even with a real, valid JWT."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_a = _mk_event(client, admin_headers, f"horiza-{uid()}")
        event_b = _mk_event(client, admin_headers, f"horizb-{uid()}")
        _grant_event_admin(client, admin_headers, event_a, _EVENT_ADMIN["firebase_uid"])

        r = client.post(f"/api/v1/events/{event_b}/people", json=_PERSON_BODY, headers=_bearer(_EVENT_ADMIN))
        assert r.status_code == 403, r.text
        r = client.get(f"/api/v1/events/{event_b}/people", headers=_bearer(_EVENT_ADMIN))
        assert r.status_code == 403, r.text
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# D. Adversarial privilege / identity-injection
# ═════════════════════════════════════════════════════════════════════════════

# Deliberately excludes "role"/"roles" as top-level keys: PersonCreate
# already declares a legitimate (unrelated) presentation-role enum field
# named "role" — injecting an RBAC-style value there would collide with
# real schema validation and test something else entirely (malformed
# input, already covered by test_malformed_person_create_rejected_safely)
# rather than privilege injection. platform_admin/roles injection is
# still exercised structurally via is_admin/event_admin below.
_FORGED_FIELDS = {
    "is_admin": True, "platform_admin": True,
    "firebase_uid": "forged-admin", "actor_uid": "forged-admin",
    "created_by": "forged-admin", "updated_by": "forged-admin",
    "event_admin": True, "owner_uid": "forged-admin",
}


def test_event_admin_cannot_elevate_via_forged_fields_on_person_create(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"forge-person-{uid()}")
        _grant_event_admin(client, admin_headers, event_id, _EVENT_ADMIN["firebase_uid"])

        body = {**_PERSON_BODY, **_FORGED_FIELDS}
        r = client.post(f"/api/v1/events/{event_id}/people", json=body, headers=_bearer(_EVENT_ADMIN))
        assert r.status_code == 201, r.text
        person_id = r.json()["person_id"]

        actor = _latest_audit_actor("person", person_id, "person_created")
        assert actor == _EVENT_ADMIN["firebase_uid"]
        assert actor != "forged-admin"

        # No route on events.py/people.py/sponsors_partners.py grants
        # platform authority — confirm the forged role had zero effect by
        # verifying the same identity is still denied on a platform-only route.
        r2 = client.post("/api/v1/events", json={
            "title": "should still be denied", "description": "d", "start_datetime": _FUTURE_START,
            "end_datetime": _FUTURE_END, "location_text": "Venue", "is_virtual": False, "capacity": 10,
        }, headers=_bearer(_EVENT_ADMIN))
        assert r2.status_code == 403, r2.text
    finally:
        _clear_bootstrap(monkeypatch)


def test_attendee_cannot_elevate_via_forged_fields_on_sponsor_create(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"forge-sponsor-{uid()}")
    finally:
        _clear_bootstrap(monkeypatch)

    body = {**_SPONSOR_BODY, **_FORGED_FIELDS}
    r = client.post(f"/api/v1/events/{event_id}/sponsors", json=body, headers=_bearer(_ATTENDEE))
    assert r.status_code == 403, r.text
    rows = _db_fetch("SELECT count(*) AS n FROM event_sponsors WHERE event_id = $1", event_id)
    assert rows[0]["n"] == 0


def test_event_update_status_field_not_forgeable_via_body(client, monkeypatch):
    """events.py's PATCH /events/{id} (general update) must not accept a
    'status' field as a backdoor around the dedicated, validated
    /events/{id}/status transition route."""
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"statusforge-{uid()}")

        r = client.patch(f"/api/v1/events/{event_id}", json={"title": "X", "status": "published"}, headers=admin_headers)
        assert r.status_code == 200, r.text

        row = _db_fetch("SELECT status FROM events WHERE event_id = $1", event_id)
        assert row[0]["status"] == "draft"
    finally:
        _clear_bootstrap(monkeypatch)


# ═════════════════════════════════════════════════════════════════════════════
# E. Public-route preservation — events.py's public routes are unaffected
# ═════════════════════════════════════════════════════════════════════════════

def test_public_event_routes_still_unauthenticated_after_migration(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"pubcheck-{uid()}", publish=True)
    finally:
        _clear_bootstrap(monkeypatch)

    r = client.get("/api/v1/events/public")
    assert r.status_code == 200, r.text
    r = client.get(f"/api/v1/events/public/{event_id}")
    assert r.status_code == 200, r.text
    assert r.json()["event"]["event_id"] == event_id


def test_public_event_payload_leaks_no_admin_or_private_fields(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"pubfields-{uid()}", publish=True)
        client.post(f"/api/v1/events/{event_id}/people", json=_PERSON_BODY, headers=admin_headers)
        client.post(f"/api/v1/events/{event_id}/sponsors", json=_SPONSOR_BODY, headers=admin_headers)
    finally:
        _clear_bootstrap(monkeypatch)

    r = client.get(f"/api/v1/events/public/{event_id}")
    assert r.status_code == 200, r.text
    body = r.json()["event"]
    assert "created_by_firebase_uid" not in body
    for person in body.get("people", []):
        assert set(person.keys()) <= {
            "person_id", "event_id", "role", "fullname", "title", "organisation",
            "bio", "photo_url", "linkedin_url", "display_order",
        }
    for sponsor in body.get("sponsors", []):
        assert set(sponsor.keys()) <= {
            "sponsor_id", "event_id", "sponsor_type", "name", "logo_url",
            "website_url", "description", "display_order",
        }


# ═════════════════════════════════════════════════════════════════════════════
# F. Audit verification
# ═════════════════════════════════════════════════════════════════════════════

def test_denied_person_mutation_creates_no_audit_row(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"noauditdeny-{uid()}")
    finally:
        _clear_bootstrap(monkeypatch)

    before = _db_fetch("SELECT count(*) AS n FROM event_audit_log WHERE event_type = 'person_created'")[0]["n"]
    r = client.post(f"/api/v1/events/{event_id}/people", json=_PERSON_BODY, headers=_bearer(_ATTENDEE))
    assert r.status_code == 403, r.text
    after = _db_fetch("SELECT count(*) AS n FROM event_audit_log WHERE event_type = 'person_created'")[0]["n"]
    assert after == before


def test_sponsor_update_delete_audited_with_real_actor(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"auditsponsor-{uid()}")
        _grant_event_admin(client, admin_headers, event_id, _EVENT_ADMIN["firebase_uid"])
        event_admin_headers = _bearer(_EVENT_ADMIN)

        r = client.post(f"/api/v1/events/{event_id}/sponsors", json=_SPONSOR_BODY, headers=event_admin_headers)
        sponsor_id = r.json()["sponsor_id"]
        assert _audit_count("sponsor", sponsor_id) == 1
        assert _latest_audit_actor("sponsor", sponsor_id, "sponsor_created") == _EVENT_ADMIN["firebase_uid"]

        client.put(f"/api/v1/events/{event_id}/sponsors/{sponsor_id}", json={"name": "Y"}, headers=event_admin_headers)
        assert _audit_count("sponsor", sponsor_id) == 2
        assert _latest_audit_actor("sponsor", sponsor_id, "sponsor_updated") == _EVENT_ADMIN["firebase_uid"]

        client.delete(f"/api/v1/events/{event_id}/sponsors/{sponsor_id}", headers=event_admin_headers)
        assert _audit_count("sponsor", sponsor_id) == 3
        assert _latest_audit_actor("sponsor", sponsor_id, "sponsor_deleted") == _EVENT_ADMIN["firebase_uid"]
    finally:
        _clear_bootstrap(monkeypatch)


def test_audit_context_contains_no_secrets_or_tokens(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"auditsafe-{uid()}")
        r = client.post(f"/api/v1/events/{event_id}/partners", json=_PARTNER_BODY, headers=admin_headers)
        partner_id = r.json()["partner_id"]
    finally:
        _clear_bootstrap(monkeypatch)

    rows = _db_fetch(
        "SELECT context::text AS ctx FROM event_audit_log WHERE entity_type = 'partner' AND entity_id = $1",
        partner_id,
    )
    for row in rows:
        ctx = row["ctx"] or ""
        assert "Bearer" not in ctx and "token" not in ctx.lower() and "secret" not in ctx.lower()


# ═════════════════════════════════════════════════════════════════════════════
# G. Malformed-input safety (no 500s, no leakage) — spot check
# ═════════════════════════════════════════════════════════════════════════════

def test_malformed_person_create_rejected_safely(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        event_id = _mk_event(client, admin_headers, f"malformed-{uid()}")

        r = client.post(f"/api/v1/events/{event_id}/people", json={"role": "NOT_A_REAL_ROLE", "fullname": "X"}, headers=admin_headers)
        assert r.status_code == 422, r.text
        assert "Traceback" not in r.text and "asyncpg" not in r.text

        r2 = client.post(f"/api/v1/events/{event_id}/people", json={"fullname": "Missing role"}, headers=admin_headers)
        assert r2.status_code == 422, r2.text
    finally:
        _clear_bootstrap(monkeypatch)
