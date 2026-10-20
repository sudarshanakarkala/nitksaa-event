"""Session details: type, pillar, hall, subtitle, the people on each
session and the sponsors presenting it, saved through the event form's
details endpoint; a sponsor's label.

- Fields the request leaves out are kept (an older app can't wipe them).
- People and sponsors are named, matched ignoring case; an unknown name is
  refused and nothing is saved.
- The event data carries `session_type`, `pillar` and `presented_by` (visible
  sponsors' ids) on each session, and `label` on each sponsor.
"""
from tests.test_event_links import _draft
from tests.test_payment_refunds import (
    _FIXTURE_ADMIN,
    _bearer,
    _db,
    _seed,  # noqa: F401  (autouse fixture: the test users and admin)
)

_ADMIN = None


def _admin():
    return _bearer(_FIXTURE_ADMIN)


def _details(eid):
    return f"/api/v1/admin/events/{eid}/details"


def _sponsor(client, eid, name, tier="GOLD_SPONSOR", label=None, visible=True):
    body = {"sponsor_type": tier, "name": name, "is_visible": visible}
    if label is not None:
        body["label"] = label
    r = client.post(f"/api/v1/events/{eid}/sponsors", json=body, headers=_admin())
    assert r.status_code == 201, r.text
    return r.json()


def _session(title="Panel", **extra):
    return {
        "title": title,
        "start_datetime": "2027-03-01T10:00:00+05:30",
        "end_datetime": "2027-03-01T11:00:00+05:30",
        **extra,
    }


def _event(client, eid):
    r = client.get(f"/api/v1/events/{eid}", headers=_admin())
    assert r.status_code == 200, r.text
    return r.json()["event"]


def test_details_save_and_read_session_fields(client):
    eid = _draft(client)["event_id"]
    _sponsor(client, eid, "Acme Corp")
    _sponsor(client, eid, "Beta Labs")
    r = client.put(
        _details(eid),
        json={
            "speakers": [
                {"fullname": "Asha Rao"},
                {"fullname": "Vikram Shenoy"},
                {"fullname": "Meera Nayak", "role": "MODERATOR"},
            ],
            "sessions": [
                _session(
                    "Future of Work",
                    session_type="panel",
                    pillar=" Career Konnect ",
                    track="Hall B",
                    description="Hiring in 2027",
                    people=[
                        {"name": "meera nayak", "moderator": True},
                        {"name": "Asha Rao"},
                        {"name": "VIKRAM SHENOY"},
                    ],
                    presented_by=["beta labs", "Acme Corp"],
                ),
                _session("Lunch", session_type="BREAK", people=[]),
            ],
        },
        headers=_admin(),
    )
    assert r.status_code == 200, r.text
    sessions = {s["title"]: s for s in r.json()["sessions"]}
    panel = sessions["Future of Work"]
    assert (panel["session_type"], panel["pillar"], panel["track"], panel["description"]) == (
        "PANEL", "Career Konnect", "Hall B", "Hiring in 2027",
    )
    assert panel["people"] == [
        {"name": "Meera Nayak", "moderator": True},
        {"name": "Asha Rao", "moderator": False},
        {"name": "Vikram Shenoy", "moderator": False},
    ]
    assert panel["presented_by"] == ["Beta Labs", "Acme Corp"]
    assert sessions["Lunch"]["session_type"] == "BREAK"
    assert sessions["Lunch"]["people"] == []
    roles = {s["fullname"]: s["role"] for s in r.json()["speakers"]}
    assert roles["Meera Nayak"] == "MODERATOR"
    assert roles["Asha Rao"] == "SPEAKER"

    # The event data: type, pillar, presenting sponsors by id, people as under each session.
    event = _event(client, eid)
    by_title = {s["title"]: s for s in event["sessions"]}
    ids = {s["name"]: s["sponsor_id"] for s in event["sponsors"]}
    assert by_title["Future of Work"]["session_type"] == "PANEL"
    assert by_title["Future of Work"]["pillar"] == "Career Konnect"
    assert by_title["Future of Work"]["presented_by"] == [ids["Beta Labs"], ids["Acme Corp"]]
    assert [p["role"] for p in by_title["Future of Work"]["people"]] == [
        "MODERATOR", "SPEAKER", "SPEAKER",
    ]
    assert by_title["Lunch"]["presented_by"] == []


def test_fields_left_out_are_kept(client):
    """An older app sends only title, speaker and times: no session detail is lost."""
    eid = _draft(client)["event_id"]
    _sponsor(client, eid, "Acme Corp")
    first = client.put(
        _details(eid),
        json={
            "speakers": [{"fullname": "Asha Rao"}],
            "sessions": [
                _session(
                    "Keynote", session_type="KEYNOTE", pillar="Main Event",
                    track="Main hall", description="Opening",
                    people=[{"name": "Asha Rao"}], presented_by=["Acme Corp"],
                ),
            ],
        },
        headers=_admin(),
    ).json()
    session = first["sessions"][0]
    speaker = first["speakers"][0]
    old_app = client.put(
        _details(eid),
        json={
            "speakers": [{"person_id": speaker["person_id"], "fullname": "Asha Rao"}],
            "sessions": [
                {
                    "session_id": session["session_id"],
                    "title": "Opening keynote",
                    "speaker_name": "Asha Rao",
                    "start_datetime": session["start_datetime"],
                    "end_datetime": session["end_datetime"],
                },
            ],
        },
        headers=_admin(),
    )
    assert old_app.status_code == 200, old_app.text
    after = old_app.json()["sessions"][0]
    assert after["title"] == "Opening keynote"
    assert (after["session_type"], after["pillar"], after["track"], after["description"]) == (
        "KEYNOTE", "Main Event", "Main hall", "Opening",
    )
    assert after["people"] == [{"name": "Asha Rao", "moderator": False}]
    assert after["presented_by"] == ["Acme Corp"]


def test_blank_fields_clear(client):
    eid = _draft(client)["event_id"]
    first = client.put(
        _details(eid),
        json={"sessions": [_session("Talk", session_type="TALK", pillar="Main Event")]},
        headers=_admin(),
    ).json()["sessions"][0]
    second = client.put(
        _details(eid),
        json={"sessions": [{**first, "session_type": "", "pillar": "  "}]},
        headers=_admin(),
    )
    assert second.status_code == 200, second.text
    after = second.json()["sessions"][0]
    assert (after["session_type"], after["pillar"]) == (None, None)


def test_unknown_names_and_types_are_refused(client):
    eid = _draft(client)["event_id"]
    before = client.get(_details(eid), headers=_admin()).json()

    speaker = client.put(
        _details(eid),
        json={
            "speakers": [{"fullname": "Asha Rao"}],
            "sessions": [_session(people=[{"name": "Nobody Here"}])],
        },
        headers=_admin(),
    )
    assert speaker.status_code == 422
    assert speaker.json()["detail"] == "unknown_speaker: Nobody Here"

    sponsor = client.put(
        _details(eid),
        json={"sessions": [_session(presented_by=["Ghost Inc"])]},
        headers=_admin(),
    )
    assert sponsor.status_code == 422
    assert sponsor.json()["detail"] == "unknown_sponsor: Ghost Inc"

    bad_type = client.put(
        _details(eid), json={"sessions": [_session(session_type="party")]}, headers=_admin()
    )
    assert bad_type.status_code == 422

    # Nothing was saved by the refused requests.
    assert client.get(_details(eid), headers=_admin()).json() == before


def test_existing_link_roles_are_kept(client):
    """A panelist linked by the seed stays a panelist when the form re-saves."""
    eid = _draft(client)["event_id"]
    saved = client.put(
        _details(eid),
        json={
            "speakers": [{"fullname": "Panelist A", "role": "PANELIST"}],
            "sessions": [_session(people=[{"name": "Panelist A"}])],
        },
        headers=_admin(),
    ).json()
    session = saved["sessions"][0]
    again = client.put(
        _details(eid),
        json={"speakers": saved["speakers"], "sessions": [session]},
        headers=_admin(),
    )
    assert again.status_code == 200, again.text
    role = _db(
        "SELECT role::text FROM session_people WHERE session_id = $1",
        session["session_id"], val=True,
    )
    assert role == "PANELIST"


def test_sponsor_label_and_hidden_presenters(client):
    eid = _draft(client)["event_id"]
    shown = _sponsor(client, eid, "Acme Corp", label="  Co-presenter ")
    _sponsor(client, eid, "Hidden Co", visible=False)
    assert shown["label"] == "Co-presenter"
    client.put(
        _details(eid),
        json={"sessions": [_session(presented_by=["Acme Corp", "Hidden Co"])]},
        headers=_admin(),
    )
    event = _event(client, eid)
    assert event["sessions"][0]["presented_by"] == [shown["sponsor_id"]]
    assert [(s["name"], s["label"]) for s in event["sponsors"]] == [("Acme Corp", "Co-presenter")]

    cleared = client.put(
        f"/api/v1/events/{eid}/sponsors/{shown['sponsor_id']}",
        json={"label": ""},
        headers=_admin(),
    )
    assert cleared.status_code == 200, cleared.text
    assert cleared.json()["label"] is None
