"""Roles tab — GET /api/v1/admin/users with `role=` and per-role counts.

Each test makes its own people under a unique search word, so the shared
test database's other users don't change the numbers. Uses the fixture
identities and token helper from test_admin_rbac.py.
"""
import uuid

from tests.test_admin_rbac import (  # noqa: F401  (autouse fixture)
    _ATTENDEE,
    _FIXTURE_ADMIN,
    _bearer,
    _db_exec,
    _seed_test_identities,
)

_PATH = "/api/v1/admin/users"


def _people(word: str) -> dict:
    """Five people whose names contain [word]: plain, overall admin, can
    create events, event admin, finance. Returns role → uid."""
    uids = {k: f"ROLES_{k}_{uuid.uuid4().hex[:10]}" for k in
            ("plain", "overall", "creator", "event_admin", "finance")}
    for kind, uid in uids.items():
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, is_admin, is_event_creator)
            VALUES ($1, $2, $3, 'guest', $4, $5)
            """,
            uid, f"{uid.lower()}@example.invalid", f"{word} {kind}",
            kind == "overall", kind == "creator",
        )
    _db_exec(
        """
        INSERT INTO events (slug, title, start_datetime, end_datetime, status, capacity,
                            created_by_firebase_uid)
        VALUES (lower($1), $1, now() + interval '10 days', now() + interval '10 days 2 hours',
                'draft', 10, $2)
        """,
        f"{word}-event", uids["event_admin"],
    )
    _db_exec(
        """
        INSERT INTO event_members (event_id, firebase_uid, role, status)
        SELECT event_id, $2, 'event_admin', 'active' FROM events WHERE title = $1
        """,
        f"{word}-event", uids["event_admin"],
    )
    _db_exec(
        """
        INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
        VALUES ($1, 'finance_operator', $2)
        """,
        uids["finance"], _FIXTURE_ADMIN["firebase_uid"],
    )
    return uids


def test_users_denies_plain_user(client):
    assert client.get(_PATH, headers=_bearer(_ATTENDEE)).status_code == 403


def test_users_rejects_unknown_role(client):
    r = client.get(_PATH, params={"role": "auditor"}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 422


def test_users_counts_and_role_filters(client):
    word = f"Rolestest{uuid.uuid4().hex[:8]}"
    uids = _people(word)
    headers = _bearer(_FIXTURE_ADMIN)

    r = client.get(_PATH, params={"query": word}, headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["counts"] == {
        "overall_admin": 1, "event_admin": 1, "finance": 1, "any": 4, "everyone": 5,
    }
    # No role: everyone matching the search, overall admins first.
    assert body["total"] == 5
    assert len(body["users"]) == 5
    assert body["users"][0]["firebase_uid"] == uids["overall"]

    expected = {
        "overall_admin": {uids["overall"]},
        "event_admin": {uids["event_admin"]},
        "finance": {uids["finance"]},
        "any": {uids["overall"], uids["creator"], uids["event_admin"], uids["finance"]},
    }
    for role, want in expected.items():
        r = client.get(_PATH, params={"query": word, "role": role}, headers=headers)
        assert r.status_code == 200, r.text
        body = r.json()
        assert {u["firebase_uid"] for u in body["users"]} == want, role
        assert body["total"] == len(want), role
        # Counts follow the search, not the role filter.
        assert body["counts"]["everyone"] == 5


def test_users_role_ignores_revoked_grants(client):
    word = f"Rolesrevoked{uuid.uuid4().hex[:8]}"
    uids = _people(word)
    _db_exec(
        "UPDATE payment_platform_roles SET revoked_at = now() WHERE firebase_uid = $1",
        uids["finance"],
    )
    _db_exec(
        "UPDATE event_members SET status = 'revoked' WHERE firebase_uid = $1",
        uids["event_admin"],
    )
    r = client.get(_PATH, params={"query": word}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    counts = r.json()["counts"]
    assert counts["finance"] == 0
    assert counts["event_admin"] == 0
    assert counts["any"] == 2  # overall admin and can create events


def test_users_without_search_has_counts_and_pages(client):
    r = client.get(_PATH, params={"role": "any", "per_page": 2}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body["counts"]) == {"overall_admin", "event_admin", "finance", "any", "everyone"}
    assert body["total"] == body["counts"]["any"]
    assert len(body["users"]) == min(2, body["total"])
