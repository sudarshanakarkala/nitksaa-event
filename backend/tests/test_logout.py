"""Sign out ends this browser's session on the server (POST /auth/logout).

- After logout, that token is refused (401 invalid_or_expired_token).
- Another device's token for the same person still works.
- A new sign-in gets a new token, which works.
- Logout always answers 204: with no token, an expired or broken one, a
  token from before ids were added, or twice.
"""
from datetime import datetime, timedelta, timezone

from tests.test_payment_refunds import _TEST_ALUMNI, _db, _seed  # noqa: F401  (autouse)


def _token(identity=_TEST_ALUMNI):
    from app.middleware.auth import make_access_token
    return make_access_token(dict(identity))


def _h(token):
    return {"Authorization": f"Bearer {token}"}


def _me(client, token):
    return client.get("/api/v1/auth/me", headers=_h(token))


def test_logout_ends_this_token_only(client):
    laptop, phone = _token(), _token()
    assert _me(client, laptop).status_code == 200

    assert client.post("/api/v1/auth/logout", headers=_h(laptop)).status_code == 204

    r = _me(client, laptop)
    assert r.status_code == 401
    assert r.json()["detail"] == "invalid_or_expired_token"
    # Other endpoints refuse it too.
    assert client.get("/api/v1/my/registrations", headers=_h(laptop)).status_code == 401
    # The phone stays signed in.
    assert _me(client, phone).status_code == 200


def test_a_new_sign_in_after_logout_works(client):
    old = _token()
    client.post("/api/v1/auth/logout", headers=_h(old))
    assert _me(client, _token()).status_code == 200


def test_logout_always_204(client):
    from jose import jwt
    from app.config import get_settings

    expired = jwt.encode(
        {**_TEST_ALUMNI, "jti": "x-expired",
         "exp": datetime.now(timezone.utc) - timedelta(minutes=1)},
        get_settings().secret_key, algorithm="HS256",
    )
    no_id = jwt.encode(
        {**_TEST_ALUMNI, "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
        get_settings().secret_key, algorithm="HS256",
    )
    token = _token()
    for headers in ({}, _h("not-a-token"), _h(expired), _h(no_id), _h(token), _h(token)):
        assert client.post("/api/v1/auth/logout", headers=headers).status_code == 204
    # A token from before ids were added keeps working until it runs out.
    assert _me(client, no_id).status_code == 200


def test_logout_clears_ids_whose_tokens_have_run_out(client):
    _db(
        "INSERT INTO revoked_tokens (jti, firebase_uid, expires_at)"
        " VALUES ('old-id', 'x', now() - interval '1 hour') ON CONFLICT DO NOTHING"
    )
    client.post("/api/v1/auth/logout", headers=_h(_token()))
    assert _db("SELECT count(*) FROM revoked_tokens WHERE jti='old-id'", val=True) == 0
