"""POST /api/v1/nitika/chat — the app's NITiKa panel, through this backend.

NITiKa itself is faked with an httpx MockTransport: these tests check what
this backend sends it (above all, that the user and admin scope come only
from the session and the role tables) and what the app gets back.
"""
import json
import uuid

import httpx
import pytest

from app.services import nitika_service

NITIKA_URL = "https://nitika.example.run.app"

_MEMBER = {
    "firebase_uid": "TEST_NITIKA_UID_050",
    "sub": "member.nitika@nitksaa.dev",
    "email": "member.nitika@nitksaa.dev",
    "fullname": "Member NITiKa Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS050",
    "graduation_year": 2018,
}
_PLATFORM_ADMIN = {**_MEMBER, "firebase_uid": "TEST_NITIKA_UID_051", "email": "pa.nitika@nitksaa.dev"}
_EVENT_ADMIN = {**_MEMBER, "firebase_uid": "TEST_NITIKA_UID_052", "email": "ea.nitika@nitksaa.dev"}
_FINANCE = {**_MEMBER, "firebase_uid": "TEST_NITIKA_UID_053", "email": "fin.nitika@nitksaa.dev"}
_FIXTURE_ADMIN = {**_MEMBER, "firebase_uid": "TEST_NITIKA_UID_054", "email": "fixture.nitika@nitksaa.dev"}

ANSWER = {
    "request_id": "req-1",
    "mode": "assistant",
    "intent": "list_events",
    "answer": "**Two** events.",
    "table": None,
    "links": [{"label": "Pune Alumni Meet", "path": "/events/1"}],
    "sources": [],
    "truncated": False,
    "rate_limit": None,
}


# ── helpers ──────────────────────────────────────────────────────────────────

def _bearer(identity: dict) -> dict:
    from app.middleware.auth import make_access_token

    return {"Authorization": f"Bearer {make_access_token(dict(identity))}"}


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


class FakeNitika:
    """Stands in for NITiKa: records each request, answers with `reply`."""

    def __init__(self):
        self.requests: list[httpx.Request] = []
        self.reply = lambda request: httpx.Response(200, json=ANSWER)

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self.reply(request)

    @property
    def body(self) -> dict:
        return json.loads(self.requests[-1].content)


@pytest.fixture
def nitika(monkeypatch):
    """NITiKa configured and faked; ID tokens faked."""
    from app.config import get_settings

    fake = FakeNitika()
    real_client = httpx.AsyncClient
    monkeypatch.setattr(
        nitika_service.httpx,
        "AsyncClient",
        lambda **kw: real_client(transport=httpx.MockTransport(fake.handler), **kw),
    )
    monkeypatch.setattr(nitika_service, "_fetch_id_token", lambda audience: f"id-token-for-{audience}")
    nitika_service._token_cache.clear()
    monkeypatch.setenv("NITIKA_URL", NITIKA_URL)
    monkeypatch.setenv("NITIKA_CLIENT_KEY", "client-key-events")
    monkeypatch.delenv("PLATFORM_ADMIN_FIREBASE_UIDS", raising=False)
    get_settings.cache_clear()
    yield fake
    monkeypatch.undo()
    get_settings.cache_clear()
    nitika_service._token_cache.clear()


@pytest.fixture(autouse=True)
def _seed_identities():
    for identity in (_MEMBER, _PLATFORM_ADMIN, _EVENT_ADMIN, _FINANCE, _FIXTURE_ADMIN):
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (firebase_uid) DO NOTHING
            """,
            identity["firebase_uid"], identity["email"], identity["fullname"],
            identity["user_type"], identity["ref_id"], identity["graduation_year"],
        )
    for uid, role in ((_FIXTURE_ADMIN["firebase_uid"], "platform_admin"),
                      (_FINANCE["firebase_uid"], "finance_operator")):
        _db_exec(
            """
            INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
            VALUES ($1, $2, 'test_fixture_bootstrap')
            ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING
            """,
            uid, role,
        )


def _mk_event(client) -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST NITIKA EVENT {uuid.uuid4().hex[:6]}",
            "description": "Created by pytest (NITiKa)",
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


def _ask(client, identity=_MEMBER, **body):
    return client.post(
        "/api/v1/nitika/chat",
        json={"message": "What's coming up?", **body},
        headers=_bearer(identity),
    )


# ── admin scope mapping (no HTTP) ────────────────────────────────────────────

@pytest.mark.parametrize(
    "roles, event_ids, expected",
    [
        (set(), [], None),
        ({"platform_admin"}, [], {"event_ids": "all", "capabilities": ["registrations", "attendees", "payments", "sql"]}),
        ({"platform_admin", "auditor"}, [3], {"event_ids": "all", "capabilities": ["registrations", "attendees", "payments", "sql"]}),
        (set(), [15, 12, 12], {"event_ids": [12, 15], "capabilities": ["registrations", "attendees", "payments"]}),
        ({"finance_operator"}, [], {"event_ids": "all", "capabilities": ["payments"]}),
        ({"auditor"}, [], {"event_ids": "all", "capabilities": ["payments"]}),
        ({"support"}, [], {"event_ids": "all", "capabilities": ["payments"]}),
        # Both: the event_admin scope, never wider attendee access.
        ({"finance_operator"}, [7], {"event_ids": [7], "capabilities": ["registrations", "attendees", "payments"]}),
        ({"some_future_role"}, [], None),
    ],
)
def test_admin_scope_from_roles(roles, event_ids, expected):
    assert nitika_service.admin_scope_from_roles(roles, event_ids) == expected


# ── the route ────────────────────────────────────────────────────────────────

def test_not_configured_is_404_and_calls_nothing(client, nitika, monkeypatch):
    from app.config import get_settings

    monkeypatch.setenv("NITIKA_CLIENT_KEY", "")
    get_settings.cache_clear()
    r = _ask(client)
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "not_configured"
    assert nitika.requests == []


def test_needs_a_valid_session(client, nitika):
    r = client.post(
        "/api/v1/nitika/chat",
        json={"message": "hi"},
        headers={"Authorization": "Bearer not-a-token"},
    )
    assert r.status_code == 401
    assert nitika.requests == []


def test_member_message_is_forwarded_and_answer_passed_through(client, nitika):
    r = _ask(
        client,
        history=[{"role": "user", "text": "hi"}, {"role": "assistant", "text": "Hello"}],
        locale="en-IN",
        context={"page": "/events/12", "event_id": 12},
    )
    assert r.status_code == 200
    assert r.json() == ANSWER

    sent = nitika.requests[-1]
    assert str(sent.url) == f"{NITIKA_URL}/v1/chat"
    assert sent.headers["X-NITiKa-Client-Key"] == "client-key-events"
    assert sent.headers["Authorization"] == f"Bearer id-token-for-{NITIKA_URL}"
    assert nitika.body == {
        "user": {"id": _MEMBER["firebase_uid"], "role": "user", "user_type": "alumni"},
        "message": "What's coming up?",
        "history": [{"role": "user", "text": "hi"}, {"role": "assistant", "text": "Hello"}],
        "locale": "en-IN",
        "context": {"page": "/events/12", "event_id": 12},
    }


def test_a_user_or_role_in_the_body_is_ignored(client, nitika):
    r = _ask(
        client,
        user={"id": "someone-else", "role": "admin",
              "admin_scope": {"event_ids": "all", "capabilities": ["sql"]}},
        role="admin",
    )
    assert r.status_code == 200
    assert nitika.body["user"] == {
        "id": _MEMBER["firebase_uid"], "role": "user", "user_type": "alumni",
    }
    assert "role" not in nitika.body


def test_context_without_event_id_is_sent_without_it(client, nitika):
    _ask(client, context={"page": "/home"})
    assert nitika.body["context"] == {"page": "/home"}


def test_platform_admin_gets_every_event_and_sql(client, nitika, monkeypatch):
    from app.config import get_settings

    monkeypatch.setenv("PLATFORM_ADMIN_FIREBASE_UIDS", _PLATFORM_ADMIN["firebase_uid"])
    get_settings.cache_clear()
    _ask(client, identity=_PLATFORM_ADMIN)
    assert nitika.body["user"]["role"] == "admin"
    assert nitika.body["user"]["admin_scope"] == {
        "event_ids": "all",
        "capabilities": ["registrations", "attendees", "payments", "sql"],
    }


def test_event_admin_gets_their_events_only(client, nitika):
    mine, other = _mk_event(client), _mk_event(client)
    _db_exec(
        """
        INSERT INTO event_members (event_id, firebase_uid, role, status)
        VALUES ($1, $2, 'event_admin', 'active')
        ON CONFLICT (event_id, firebase_uid) DO UPDATE SET role = 'event_admin', status = 'active'
        """,
        mine, _EVENT_ADMIN["firebase_uid"],
    )
    _ask(client, identity=_EVENT_ADMIN)
    scope = nitika.body["user"]["admin_scope"]
    assert mine in scope["event_ids"]
    assert other not in scope["event_ids"]
    assert scope["capabilities"] == ["registrations", "attendees", "payments"]


def test_finance_operator_gets_payments_on_every_event(client, nitika):
    _ask(client, identity=_FINANCE)
    assert nitika.body["user"]["admin_scope"] == {"event_ids": "all", "capabilities": ["payments"]}


@pytest.mark.parametrize("status, code", [
    (400, "invalid_request"),
    (403, "scope_denied"),
    (429, "user_rate_limited"),
    (502, "model_failure"),
    (503, "not_ready"),
    (504, "timeout"),
])
def test_nitika_errors_are_passed_through(client, nitika, status, code):
    error = {"error": {"code": code, "message": "From NITiKa.", "request_id": "req-9"}}
    nitika.reply = lambda request: httpx.Response(status, json=error)
    r = _ask(client)
    assert r.status_code == status
    assert r.json() == error


def test_a_bad_client_key_is_our_fault_not_a_sign_in_problem(client, nitika):
    nitika.reply = lambda request: httpx.Response(
        401, json={"error": {"code": "invalid_client_key", "message": "x", "request_id": "req-2"}}
    )
    r = _ask(client)
    assert r.status_code == 502
    assert r.json()["error"]["code"] == "upstream_error"
    assert r.json()["error"]["request_id"] == "req-2"


def test_cloud_run_rejecting_the_token_is_502_and_drops_the_token(client, nitika):
    _ask(client)
    assert NITIKA_URL in nitika_service._token_cache

    nitika.reply = lambda request: httpx.Response(403, text="<html>Forbidden</html>")
    r = _ask(client)
    assert r.status_code == 502
    assert NITIKA_URL not in nitika_service._token_cache


def test_a_non_json_answer_is_502(client, nitika):
    nitika.reply = lambda request: httpx.Response(200, text="not json")
    assert _ask(client).status_code == 502


def test_timeout_is_504(client, nitika):
    def slow(request):
        raise httpx.ReadTimeout("slow", request=request)

    nitika.reply = slow
    r = _ask(client)
    assert r.status_code == 504
    assert r.json()["error"]["code"] == "timeout"


def test_unreachable_is_503(client, nitika):
    def down(request):
        raise httpx.ConnectError("down", request=request)

    nitika.reply = down
    r = _ask(client)
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "unreachable"


def test_no_id_token_means_no_call(client, nitika, monkeypatch):
    def no_token(audience):
        raise RuntimeError("no metadata server")

    monkeypatch.setattr(nitika_service, "_fetch_id_token", no_token)
    r = _ask(client)
    assert r.status_code == 502
    assert r.json()["error"]["code"] == "upstream_auth"
    assert nitika.requests == []


def test_the_id_token_is_reused(client, nitika, monkeypatch):
    calls = []
    monkeypatch.setattr(
        nitika_service, "_fetch_id_token",
        lambda audience: calls.append(audience) or "tok",
    )
    _ask(client)
    _ask(client)
    assert calls == [NITIKA_URL]


def test_a_local_nitika_gets_no_id_token(client, nitika, monkeypatch):
    from app.config import get_settings

    monkeypatch.setenv("NITIKA_URL", "http://localhost:8080/")
    get_settings.cache_clear()
    _ask(client)
    sent = nitika.requests[-1]
    assert str(sent.url) == "http://localhost:8080/v1/chat"
    assert "Authorization" not in sent.headers
