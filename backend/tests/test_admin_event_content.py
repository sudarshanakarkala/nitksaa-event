"""Admin revamp step 5b — the event form's speakers, sessions and fee tiers.

PUT replaces the three lists (adding, changing and removing to match);
GET reads them back with their ids. Uses the fixture identities and the
event helper from test_admin_rbac.py.
"""
import uuid

from tests.test_admin_rbac import (  # noqa: F401  (autouse fixture)
    _ATTENDEE,
    _FIXTURE_ADMIN,
    _bearer,
    _mk_event,
    _seed_test_identities,
)


def _path(event_id: int) -> str:
    return f"/api/v1/admin/events/{event_id}/content"


def test_content_denied_to_plain_user(client):
    event_id = _mk_event(client, uuid.uuid4().hex[:8])
    assert client.get(_path(event_id), headers=_bearer(_ATTENDEE)).status_code == 403


def test_content_round_trip_add_change_remove(client):
    event_id = _mk_event(client, uuid.uuid4().hex[:8])
    admin = _bearer(_FIXTURE_ADMIN)

    first = client.put(
        _path(event_id),
        json={
            "speakers": [
                {"fullname": "Asha Rao", "title": "CTO", "organisation": "Acme"},
                {"fullname": "Vikram Shenoy"},
            ],
            "sessions": [
                {
                    "title": "Keynote",
                    "speaker_name": "Asha Rao",
                    "start_datetime": "2027-10-01T08:30:00+05:30",
                    "end_datetime": "2027-10-01T09:00:00+05:30",
                },
            ],
            "fees": [
                {"name": "Participation", "fee_type": "participation", "amount": 500},
                {"name": "Food pass", "fee_type": "FOOD_PASS", "amount": 250},
            ],
        },
        headers=admin,
    )
    assert first.status_code == 200, first.text
    body = first.json()
    assert [s["fullname"] for s in body["speakers"]] == ["Asha Rao", "Vikram Shenoy"]
    assert len(body["sessions"]) == 1
    assert [(f["name"], f["fee_type"], f["amount"]) for f in body["fees"]] == [
        ("Participation", "participation", 500.0),
        ("Food pass", "food_pass", 250.0),
    ]

    # Change the first speaker, drop the second, keep the session, one fee.
    asha = body["speakers"][0]["person_id"]
    session = body["sessions"][0]
    second = client.put(
        _path(event_id),
        json={
            "speakers": [{"person_id": asha, "fullname": "Asha Rao", "title": "CEO"}],
            "sessions": [{**session, "title": "Opening keynote"}],
            "fees": [{"name": "Participation", "amount": 600}],
        },
        headers=admin,
    )
    assert second.status_code == 200, second.text
    body = second.json()
    assert [(s["person_id"], s["title"]) for s in body["speakers"]] == [(asha, "CEO")]
    assert [(s["session_id"], s["title"]) for s in body["sessions"]] == [
        (session["session_id"], "Opening keynote"),
    ]
    assert [f["amount"] for f in body["fees"]] == [600.0]

    read = client.get(_path(event_id), headers=admin)
    assert read.status_code == 200
    assert read.json() == body


def test_content_rejects_bad_fee_type_and_backwards_session(client):
    event_id = _mk_event(client, uuid.uuid4().hex[:8])
    admin = _bearer(_FIXTURE_ADMIN)
    bad_fee = client.put(
        _path(event_id),
        json={"fees": [{"name": "X", "fee_type": "tips", "amount": 1}]},
        headers=admin,
    )
    assert bad_fee.status_code == 422
    backwards = client.put(
        _path(event_id),
        json={
            "sessions": [
                {
                    "title": "Oops",
                    "start_datetime": "2027-10-01T10:00:00+05:30",
                    "end_datetime": "2027-10-01T09:00:00+05:30",
                },
            ],
        },
        headers=admin,
    )
    assert backwards.status_code == 422
