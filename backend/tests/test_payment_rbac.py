"""WP2 — production payment RBAC boundary tests.

Exercises app/middleware/admin_auth.py (renamed from payment_auth.py in the
operational-readiness sprint, now shared with admin_events.py) against the
WP1/WP4 admin routes in app/api/admin_payments.py. Identity is always the
real Firebase-JWT pipeline (make_access_token / get_current_user) — never
app.middleware.dev_auth's X-Dev-User placeholder, which this RBAC layer
deliberately never trusts.
"""
import uuid

import pytest

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_020",
    "sub": "platform.admin.wp2@nitksaa.dev",
    "email": "platform.admin.wp2@nitksaa.dev",
    "fullname": "Platform Admin WP2 Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS020",
    "graduation_year": 2018,
}

_ATTENDEE = {
    "firebase_uid": "TEST_ALUMNI_UID_021",
    "sub": "attendee.wp2@nitksaa.dev",
    "email": "attendee.wp2@nitksaa.dev",
    "fullname": "Attendee WP2 Test",
    "user_type": "alumni",
    "ref_id": "NITK2019CS021",
    "graduation_year": 2019,
}

_FINANCE = {
    "firebase_uid": "TEST_ALUMNI_UID_022",
    "sub": "finance.wp2@nitksaa.dev",
    "email": "finance.wp2@nitksaa.dev",
    "fullname": "Finance Operator WP2 Test",
    "user_type": "alumni",
    "ref_id": "NITK2017CS022",
    "graduation_year": 2017,
}

_AUDITOR = {
    "firebase_uid": "TEST_ALUMNI_UID_023",
    "sub": "auditor.wp2@nitksaa.dev",
    "email": "auditor.wp2@nitksaa.dev",
    "fullname": "Auditor WP2 Test",
    "user_type": "alumni",
    "ref_id": "NITK2016CS023",
    "graduation_year": 2016,
}

_SUPPORT = {
    "firebase_uid": "TEST_ALUMNI_UID_024",
    "sub": "support.wp2@nitksaa.dev",
    "email": "support.wp2@nitksaa.dev",
    "fullname": "Support WP2 Test",
    "user_type": "alumni",
    "ref_id": "NITK2015CS024",
    "graduation_year": 2015,
}

_ADMIN = {"X-Dev-User": "admin"}

# See test_payments.py's _FIXTURE_ADMIN docstring — same identity/UID,
# reused across files (same DB row). Needed because events.py's own admin
# routes were migrated off dev-auth in the admin-auth-unification sprint;
# admin_events.py's real-RBAC create/publish routes are the replacement.
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


def _mk_event(client, uid_suffix: str) -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST WP2 EVENT {uid_suffix}",
            "description": "Created by pytest (WP2 RBAC)",
            "start_datetime": "2027-05-01T08:00:00+05:30",
            "end_datetime": "2027-05-01T10:00:00+05:30",
            "location_text": "Test Venue",
            "is_virtual": False,
            "capacity": 10,
            "is_free": True,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    event_id = r.json()["event_id"]
    r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    return event_id


def _draft_payload(key: str) -> dict:
    return {
        "configuration_key": key,
        "base_amount": "50.00",
        "gst_enabled": False,
        "seat_hold_minutes": 15,
        "payment_session_expiry_minutes": 15,
    }


def _grant_platform_role(client, admin_headers: dict, firebase_uid: str, role: str) -> None:
    """Idempotent from the test's point of view: these RBAC tests reuse a
    small set of static identities across multiple test functions in this
    file, so a role may already be actively granted from an earlier test in
    the same session — 409 payment_role_already_active is treated the same
    as a fresh 201, since either way the role is now active."""
    r = client.post(
        "/api/v1/admin/payment-roles",
        json={"firebase_uid": firebase_uid, "role": role},
        headers=admin_headers,
    )
    assert r.status_code in (201, 409), r.text


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
    """payment_platform_roles.firebase_uid FK-references event_users —
    these synthetic RBAC-test identities have no seed data, so a role grant
    against them would otherwise fail with a foreign-key violation. See the
    identical rationale in test_payment_admin_config.py."""
    for identity in (_PLATFORM_ADMIN, _ATTENDEE, _FINANCE, _AUDITOR, _SUPPORT, _FIXTURE_ADMIN):
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


# ─────────────────────────────────────────────────────────────────────────────
# A. Identity boundaries on a write endpoint (create draft config)
# ─────────────────────────────────────────────────────────────────────────────

def test_unauthenticated_denied(client):
    event_id = _mk_event(client, f"unauth-{uuid.uuid4().hex[:8]}")
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-configurations",
        json=_draft_payload(f"unauth-{uuid.uuid4().hex[:6]}"),
    )
    assert r.status_code == 403


def test_invalid_token_denied(client):
    event_id = _mk_event(client, f"invalidtok-{uuid.uuid4().hex[:8]}")
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-configurations",
        json=_draft_payload(f"invalidtok-{uuid.uuid4().hex[:6]}"),
        headers={"Authorization": "Bearer not-a-real-jwt"},
    )
    assert r.status_code == 401


def test_attendee_with_no_roles_denied(client):
    event_id = _mk_event(client, f"attendee-{uuid.uuid4().hex[:8]}")
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-configurations",
        json=_draft_payload(f"attendee-{uuid.uuid4().hex[:6]}"),
        headers=_bearer(_ATTENDEE),
    )
    assert r.status_code == 403


def test_platform_admin_allowed(client, monkeypatch):
    event_id = _mk_event(client, f"platadmin-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(f"platadmin-{uuid.uuid4().hex[:6]}"),
            headers=_bearer(_PLATFORM_ADMIN),
        )
        assert r.status_code == 201, r.text
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# B. Read vs. write boundaries for finance_operator / auditor / support
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("identity", [_FINANCE, _AUDITOR, _SUPPORT])
def test_operational_roles_get_read_access_but_not_write(client, monkeypatch, identity):
    role_by_identity = {
        _FINANCE["firebase_uid"]: "finance_operator",
        _AUDITOR["firebase_uid"]: "auditor",
        _SUPPORT["firebase_uid"]: "support",
    }
    role = role_by_identity[identity["firebase_uid"]]
    event_id = _mk_event(client, f"opsrole-{role}-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_platform_role(client, admin_headers, identity["firebase_uid"], role)

        role_headers = _bearer(identity)

        # Read access: allowed.
        r = client.get(f"/api/v1/admin/events/{event_id}/payment-configurations", headers=role_headers)
        assert r.status_code == 200, r.text

        # Write (create draft): denied — none of these roles carry
        # configuration-mutation rights, only platform_admin/event_admin do.
        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(f"opsrole-{role}-{uuid.uuid4().hex[:6]}"),
            headers=role_headers,
        )
        assert r.status_code == 403

        # Lifecycle-expiry trigger (platform_admin-only mutation): denied
        # even for finance_operator — "finance cannot inherit unrelated
        # platform powers".
        r = client.post("/api/v1/admin/payments/lifecycle/expire-orders", headers=role_headers)
        assert r.status_code == 403
    finally:
        _clear_bootstrap(monkeypatch)


def test_auditor_can_list_roles_finance_and_support_cannot(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        _grant_platform_role(client, admin_headers, _AUDITOR["firebase_uid"], "auditor")
        _grant_platform_role(client, admin_headers, _FINANCE["firebase_uid"], "finance_operator")

        r = client.get("/api/v1/admin/payment-roles", headers=_bearer(_AUDITOR))
        assert r.status_code == 200, r.text

        r = client.get("/api/v1/admin/payment-roles", headers=_bearer(_FINANCE))
        assert r.status_code == 403
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# C. Fabricated / client-supplied role cannot escalate
# ─────────────────────────────────────────────────────────────────────────────

def test_fabricated_role_in_request_body_has_no_effect(client):
    """A plain attendee stuffing a 'role' field into the request body (or
    any other client-controlled channel) must not gain any authorization —
    roles come only from the DB / bootstrap settings, keyed off the
    JWT-verified firebase_uid."""
    event_id = _mk_event(client, f"fabricated-{uuid.uuid4().hex[:8]}")
    payload = _draft_payload(f"fabricated-{uuid.uuid4().hex[:6]}")
    payload["role"] = "platform_admin"  # extraneous field — must be ignored
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-configurations",
        json=payload,
        headers=_bearer(_ATTENDEE),
    )
    assert r.status_code == 403


def test_fabricated_role_header_has_no_effect(client):
    """A spoofed X-Dev-User: admin header must not grant any production
    payment-admin authorization — that header is only ever consulted by
    app.middleware.dev_auth (a development-only placeholder used elsewhere
    in this codebase), which app.middleware.admin_auth never imports or
    calls."""
    event_id = _mk_event(client, f"fabricatedhdr-{uuid.uuid4().hex[:8]}")
    headers = _bearer(_ATTENDEE)
    headers["X-Dev-User"] = "admin"
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-configurations",
        json=_draft_payload(f"fabricatedhdr-{uuid.uuid4().hex[:6]}"),
        headers=headers,
    )
    assert r.status_code == 403


# ─────────────────────────────────────────────────────────────────────────────
# D. Role grant/revoke lifecycle
# ─────────────────────────────────────────────────────────────────────────────

def test_role_grant_and_revoke_lifecycle(client, monkeypatch):
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)

        # payment_platform_roles.firebase_uid FKs to event_users — _ATTENDEE
        # is seeded by the _seed_test_identities autouse fixture, so it's a
        # valid grant target.
        grant = client.post(
            "/api/v1/admin/payment-roles",
            json={"firebase_uid": _ATTENDEE["firebase_uid"], "role": "support"},
            headers=admin_headers,
        )
        assert grant.status_code == 201, grant.text
        grant_id = grant.json()["id"]

        roles = client.get("/api/v1/admin/payment-roles", headers=admin_headers).json()["roles"]
        assert any(r["id"] == grant_id and r["revoked_at"] is None for r in roles)

        revoke = client.post(f"/api/v1/admin/payment-roles/{grant_id}/revoke", headers=admin_headers)
        assert revoke.status_code == 200, revoke.text

        roles_after = client.get("/api/v1/admin/payment-roles", headers=admin_headers).json()["roles"]
        assert all(r["id"] != grant_id for r in roles_after)
    finally:
        _clear_bootstrap(monkeypatch)


def test_non_platform_admin_cannot_grant_roles(client):
    r = client.post(
        "/api/v1/admin/payment-roles",
        json={"firebase_uid": _ATTENDEE["firebase_uid"], "role": "support"},
        headers=_bearer(_ATTENDEE),
    )
    assert r.status_code == 403
