"""Readable event links (/e/<slug>).

The public lookup finds published events only. An organiser can change the
link while the event has never been published; once it has been published
(even if unpublished since) the link is fixed, so links already shared keep
working. A link must be unused and in the right format.
"""
import uuid

from tests.test_payment_refunds import (
    _FIXTURE_ADMIN,
    _bearer,
    _db,
    _seed,  # noqa: F401  (autouse fixture: the test users and admin)
)


def _draft(client, title=None):
    title = title or f"LINKS {uuid.uuid4().hex[:8]}"
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": title, "description": "pytest",
            "start_datetime": "2027-03-01T08:00:00+05:30",
            "end_datetime": "2027-03-01T10:00:00+05:30",
            "location_text": "V", "is_virtual": False, "capacity": 20,
            "is_free": True,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    return r.json()


def _publish(client, eid):
    r = client.post(f"/api/v1/admin/events/{eid}/publish",
                    headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text


def _set_slug(client, eid, slug):
    return client.patch(f"/api/v1/events/{eid}", json={"slug": slug},
                        headers=_bearer(_FIXTURE_ADMIN))


def _lookup(client, slug):
    return client.get(f"/api/v1/events/public/by-slug/{slug}")


def _new_slug():
    return f"bangalore-breakfast-{uuid.uuid4().hex[:8]}"


def test_published_event_is_found_by_its_link(client):
    ev = _draft(client)
    _publish(client, ev["event_id"])
    r = _lookup(client, ev["slug"])
    assert r.status_code == 200, r.text
    assert r.json() == {"event_id": ev["event_id"]}
    # Typed with capitals, still found.
    assert _lookup(client, ev["slug"].upper()).json()["event_id"] == ev["event_id"]


def test_draft_and_unknown_links_are_not_found(client):
    ev = _draft(client)
    assert _lookup(client, ev["slug"]).status_code == 404
    assert _lookup(client, "no-such-event-" + uuid.uuid4().hex[:8]).status_code == 404


def test_draft_link_can_be_changed(client):
    ev = _draft(client)
    slug = _new_slug()
    r = _set_slug(client, ev["event_id"], slug)
    assert r.status_code == 200, r.text
    assert r.json()["event"]["slug"] == slug
    _publish(client, ev["event_id"])
    assert _lookup(client, slug).json()["event_id"] == ev["event_id"]
    ctx = _db(
        "SELECT context::text FROM event_audit_log WHERE entity_id = $1"
        " AND event_type = 'event_updated' ORDER BY created_at DESC LIMIT 1",
        ev["event_id"], val=True,
    )
    assert slug in str(ctx)


def test_a_link_in_use_is_refused(client):
    first = _draft(client)
    second = _draft(client)
    r = _set_slug(client, second["event_id"], first["slug"])
    assert r.status_code == 409
    assert r.json()["detail"] == "slug_taken"


def test_published_link_is_locked_even_after_unpublishing(client):
    ev = _draft(client)
    _publish(client, ev["event_id"])
    r = _set_slug(client, ev["event_id"], _new_slug())
    assert r.status_code == 409
    assert r.json()["detail"] == "slug_locked"

    r = client.patch(f"/api/v1/events/{ev['event_id']}/status",
                     json={"status": "draft"}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    r = _set_slug(client, ev["event_id"], _new_slug())
    assert r.status_code == 409
    assert r.json()["detail"] == "slug_locked"


def test_sending_the_same_link_back_is_fine_when_locked(client):
    # The form sends every field on save; an unchanged link is not a change.
    ev = _draft(client)
    _publish(client, ev["event_id"])
    r = _set_slug(client, ev["event_id"], ev["slug"])
    assert r.status_code == 200, r.text


def test_bad_links_are_refused(client):
    ev = _draft(client)
    for bad in ("ab", "Has-Capitals", "two--hyphens", "-starts", "ends-",
                "has space", "x" * 61, ""):
        r = _set_slug(client, ev["event_id"], bad)
        assert r.status_code == 422, (bad, r.text)
    r = client.patch(f"/api/v1/events/{ev['event_id']}", json={"slug": None},
                     headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 422


def test_copied_title_gets_a_numbered_link_that_can_be_fixed(client):
    title = f"Breakfast {uuid.uuid4().hex[:6]}"
    first = _draft(client, title)
    second = _draft(client, title)
    assert second["slug"] == f"{first['slug']}-2"
    fixed = f"{first['slug']}-oct"
    assert _set_slug(client, second["event_id"], fixed).status_code == 200
