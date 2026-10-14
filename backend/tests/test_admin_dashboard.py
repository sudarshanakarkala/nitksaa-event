"""Admin revamp step 7 — GET /api/v1/admin/dashboard.

Read-only summary. Checks who may call it, the response shape for each
period, and that a plain user is refused. Uses the same fixture identities
and token helper as test_admin_rbac.py.
"""
import pytest

from tests.test_admin_rbac import (  # noqa: F401  (autouse fixture)
    _ATTENDEE,
    _FIXTURE_ADMIN,
    _bearer,
    _seed_test_identities,
)

_PATH = "/api/v1/admin/dashboard"


def test_dashboard_denies_unauthenticated(client):
    assert client.get(_PATH).status_code in (401, 403)


def test_dashboard_denies_plain_user(client):
    r = client.get(_PATH, headers=_bearer(_ATTENDEE))
    assert r.status_code == 403


def test_dashboard_rejects_unknown_period(client):
    r = client.get(_PATH, params={"period": "decade"}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 422


@pytest.mark.parametrize("period", ["30d", "90d", "year", "all"])
def test_dashboard_shape_for_overall_admin(client, period):
    r = client.get(_PATH, params={"period": period}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()

    assert body["period"] == period
    assert (body["since"] is None) == (period == "all")
    assert set(body["tiles"]) == {
        "upcoming_events", "registrations", "cancellations", "money_collected",
    }
    assert len(body["weekly"]) == 12
    assert all({"week", "registrations", "cancellations"} <= set(w) for w in body["weekly"])
    assert len(body["upcoming"]) <= 8
    assert len(body["recent"]) <= 5
    for row in body["upcoming"]:
        assert {"event_id", "title", "start_datetime", "capacity", "registered",
                "new_7d", "checked_in", "registration_status"} <= set(row)
    for row in body["recent"]:
        assert row["no_shows"] == max(row["registered"] - row["checked_in"], 0)
    for row in body["by_decade"]:
        assert row["decade"] % 10 == 0


# ── One event (event_id=) ────────────────────────────────────────────────

def _mk_event(creator_uid: str, *, days: int = 20) -> int:
    """A published event with no registrations, made directly in the db."""
    import asyncio
    import uuid

    import asyncpg

    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            slug = f"dash-{uuid.uuid4().hex[:10]}"
            return await conn.fetchval(
                """
                INSERT INTO events (slug, title, start_datetime, end_datetime, status,
                                    capacity, created_by_firebase_uid)
                VALUES ($1, $1, now() + make_interval(days => $2::int),
                        now() + make_interval(days => $2::int, hours => 2),
                        'published', 50, $3)
                RETURNING event_id
                """,
                slug, days, creator_uid,
            )
        finally:
            await conn.close()

    return asyncio.run(_run())


def test_dashboard_one_event_narrows_everything(client):
    from tests.test_admin_rbac import _db_exec

    event_id = _mk_event(_FIXTURE_ADMIN["firebase_uid"])
    r = client.get(_PATH, params={"event_id": event_id, "period": "all"}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["event_id"] == event_id
    assert body["tiles"]["upcoming_events"] == 1
    assert body["tiles"]["registrations"] == 0
    assert [u["event_id"] for u in body["upcoming"]] == [event_id]
    assert all(w["registrations"] == 0 for w in body["weekly"])
    assert body["by_decade"] == []
    _db_exec("DELETE FROM events WHERE event_id = $1", event_id)


def test_dashboard_one_event_refuses_someone_elses_event(client):
    from tests.test_admin_rbac import _EVENT_ADMIN, _db_exec

    mine = _mk_event(_FIXTURE_ADMIN["firebase_uid"])
    other = _mk_event(_FIXTURE_ADMIN["firebase_uid"])
    _db_exec(
        """
        INSERT INTO event_members (event_id, firebase_uid, role, status)
        VALUES ($1, $2, 'event_admin', 'active')
        """,
        mine, _EVENT_ADMIN["firebase_uid"],
    )
    headers = _bearer(_EVENT_ADMIN)
    assert client.get(_PATH, params={"event_id": mine}, headers=headers).status_code == 200
    r = client.get(_PATH, params={"event_id": other}, headers=headers)
    assert r.status_code == 403
    _db_exec("DELETE FROM event_members WHERE event_id = $1", mine)
    _db_exec("DELETE FROM events WHERE event_id = ANY($1::int[])", [mine, other])
