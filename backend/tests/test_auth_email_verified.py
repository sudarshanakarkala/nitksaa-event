"""POST /api/v1/auth/firebase — reject unverified emails at login
(EVENT_API_fix_email_verified.md).

verify_firebase_token is mocked, so no real Firebase ID token is needed.
Spies on find_alumni_by_email and _upsert_event_user (the only database
write in this flow) prove an unverified account is rejected before any
alumni lookup or database write.
"""
import pytest

import app.api.auth as auth_api

_URL = "/api/v1/auth/firebase"


@pytest.fixture
def login(monkeypatch):
    """Returns a function that logs in with the given mocked claims and
    reports which downstream steps ran."""
    calls = {"alumni_lookup": 0, "db_write": 0}
    real_lookup = auth_api.find_alumni_by_email
    real_upsert = auth_api._upsert_event_user

    async def _lookup_spy(email):
        calls["alumni_lookup"] += 1
        return await real_lookup(email)

    async def _upsert_spy(**kwargs):
        calls["db_write"] += 1
        return await real_upsert(**kwargs)

    monkeypatch.setattr(auth_api, "find_alumni_by_email", _lookup_spy)
    monkeypatch.setattr(auth_api, "_upsert_event_user", _upsert_spy)

    def _login(client, claims):
        monkeypatch.setattr(auth_api, "verify_firebase_token", lambda token: dict(claims))
        return client.post(_URL, json={"token": "mocked-firebase-id-token"}), calls

    return _login


# ── Product-owner cases ────────────────────────────────────────────────

def test_email_verified_false_is_rejected_before_lookup_or_write(client, login):    # case 1
    r, calls = login(client, {"uid": "u1", "email": "a@example.com", "email_verified": False})
    assert r.status_code == 403
    assert r.json() == {"detail": "email_not_verified"}
    assert calls == {"alumni_lookup": 0, "db_write": 0}


def test_email_verified_absent_is_rejected(client, login):                          # case 2
    r, calls = login(client, {"uid": "u1", "email": "a@example.com"})
    assert r.status_code == 403
    assert r.json() == {"detail": "email_not_verified"}
    assert calls == {"alumni_lookup": 0, "db_write": 0}


def test_email_verified_true_follows_normal_login(client, login):                   # case 3
    r, calls = login(client, {"uid": "u1", "email": "a@example.com", "email_verified": True})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "ok" and body["token_type"] == "bearer"
    assert body["firebase_uid"] == "u1" and body["access_token"]
    assert calls == {"alumni_lookup": 1, "db_write": 1}


# ── Only the boolean True counts as verified ───────────────────────────

@pytest.mark.parametrize("value", [None, "true", "True", 1, "yes"])
def test_non_boolean_true_values_are_not_verified(client, login, value):
    r, calls = login(client, {"uid": "u1", "email": "a@example.com", "email_verified": value})
    assert r.status_code == 403
    assert r.json() == {"detail": "email_not_verified"}
    assert calls == {"alumni_lookup": 0, "db_write": 0}


# ── Existing checks still run first ────────────────────────────────────

def test_missing_uid_is_still_firebase_uid_missing(client, login):
    r, calls = login(client, {"email": "a@example.com", "email_verified": False})
    assert r.status_code == 400 and r.json() == {"detail": "firebase_uid_missing"}
    assert calls == {"alumni_lookup": 0, "db_write": 0}


def test_missing_email_is_still_email_missing(client, login):
    r, calls = login(client, {"uid": "u1", "email_verified": False})
    assert r.status_code == 400 and r.json() == {"detail": "email_missing"}
    assert calls == {"alumni_lookup": 0, "db_write": 0}
