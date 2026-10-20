"""Speakers under each session.

Each session in the event data carries `people`: person id and role, in
the link's order, visible people only. A session without links has an
empty list. The people's details stay in the event's `people`.
"""
from datetime import datetime

from tests.test_event_links import _draft
from tests.test_payment_refunds import (
    _FIXTURE_ADMIN,
    _bearer,
    _db,
    _seed,  # noqa: F401  (autouse fixture: the test users and admin)
)


def _insert_session(eid, title, start, end):
    _db(
        "INSERT INTO sessions (event_id, title, start_datetime, end_datetime)"
        " VALUES ($1, $2, $3, $4)",
        eid, title, datetime.fromisoformat(start), datetime.fromisoformat(end),
    )
    return _db(
        "SELECT session_id FROM sessions WHERE event_id = $1 AND title = $2",
        eid, title, val=True,
    )


def _insert_person(eid, name, role="PANELIST", visible=True):
    _db(
        "INSERT INTO event_people (event_id, role, fullname, title, organisation, is_visible)"
        " VALUES ($1, $2::person_role, $3, 'CTO', 'Acme', $4)",
        eid, role, name, visible,
    )
    return _db(
        "SELECT person_id FROM event_people WHERE event_id = $1 AND fullname = $2",
        eid, name, val=True,
    )


def _link(session_id, person_id, role, order):
    _db(
        "INSERT INTO session_people (session_id, person_id, role, display_order)"
        " VALUES ($1, $2, $3::person_role, $4)",
        session_id, person_id, role, order,
    )


def _sessions(client, eid):
    r = client.get(f"/api/v1/events/{eid}", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    return {s["title"]: s for s in r.json()["event"]["sessions"]}


def test_each_session_lists_its_people_in_order(client):
    eid = _draft(client)["event_id"]
    panel = _insert_session(eid, "Panel", "2027-03-01T10:00:00+05:30", "2027-03-01T11:00:00+05:30")
    _insert_session(eid, "Talk", "2027-03-01T11:00:00+05:30", "2027-03-01T11:30:00+05:30")
    mod = _insert_person(eid, "Moderator One", role="MODERATOR")
    a = _insert_person(eid, "Panelist A")
    b = _insert_person(eid, "Panelist B")
    _link(panel, b, "PANELIST", 2)
    _link(panel, mod, "MODERATOR", 0)
    _link(panel, a, "PANELIST", 1)

    sessions = _sessions(client, eid)
    assert sessions["Panel"]["people"] == [
        {"person_id": mod, "role": "MODERATOR"},
        {"person_id": a, "role": "PANELIST"},
        {"person_id": b, "role": "PANELIST"},
    ]
    assert sessions["Talk"]["people"] == []


def test_hidden_people_are_left_out(client):
    eid = _draft(client)["event_id"]
    panel = _insert_session(eid, "Panel", "2027-03-01T10:00:00+05:30", "2027-03-01T11:00:00+05:30")
    shown = _insert_person(eid, "Shown")
    hidden = _insert_person(eid, "Hidden", visible=False)
    _link(panel, shown, "PANELIST", 0)
    _link(panel, hidden, "PANELIST", 1)

    assert _sessions(client, eid)["Panel"]["people"] == [{"person_id": shown, "role": "PANELIST"}]


def test_an_event_without_links_has_empty_lists(client):
    eid = _draft(client)["event_id"]
    _insert_session(eid, "Welcome", "2027-03-01T08:00:00+05:30", "2027-03-01T08:30:00+05:30")
    assert _sessions(client, eid)["Welcome"]["people"] == []
