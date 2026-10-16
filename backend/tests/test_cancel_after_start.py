"""Attendees can't cancel once the event has started (409 event_started).

The app hides Unregister and a guest's ✕ from the start time; the server
refuses too, so an old tab or a direct call can't cancel and refund after
the start. For the attendee and their guests alike. An already-cancelled
registration still returns its refund view, so a repeated click after the
start is harmless.
"""
import uuid

from tests.test_guests import _cancel, _event, _pay, _register
from tests.test_payment_refunds import _TEST_ALUMNI_2, _bearer, _db, _seed  # noqa: F401  (autouse)


def _start_now(eid):
    """The event started a minute ago (it was registered for beforehand)."""
    _db(
        "UPDATE events SET start_datetime = now() - interval '1 minute',"
        " end_datetime = now() + interval '2 hours' WHERE event_id = $1",
        eid,
    )


def _refunds(reg_id):
    return _db(
        "SELECT count(*) FROM payment_refunds r JOIN payment_orders o"
        " ON o.id = r.payment_order_id WHERE o.registration_id = $1",
        reg_id, val=True,
    )


def _status(reg_id):
    return _db("SELECT status FROM registrations WHERE registration_id=$1",
               reg_id, val=True)


def test_paid_leader_and_guest_refused_after_the_start(client):
    eid = _event(client, is_free=False, price="500.00")
    reg = _register(client, eid, ["Asha"]).json()
    _pay(client, reg)
    _start_now(eid)

    for rid in (reg["guests"][0]["registration_id"], reg["registration_id"]):
        r = _cancel(client, rid)
        assert r.status_code == 409, r.text
        assert r.json()["detail"] == "event_started"
        assert _status(rid) == "registered"
    assert _refunds(reg["registration_id"]) == 0


def test_free_registration_refused_after_the_start(client):
    eid = _event(client, is_free=True)
    reg = _register(client, eid, []).json()
    _start_now(eid)

    r = _cancel(client, reg["registration_id"])
    assert r.status_code == 409
    assert r.json()["detail"] == "event_started"
    assert _status(reg["registration_id"]) == "registered"


def test_before_the_start_cancelling_still_works(client):
    eid = _event(client, is_free=False, price="500.00")
    reg = _register(client, eid, ["Asha"]).json()
    _pay(client, reg)

    r = _cancel(client, reg["guests"][0]["registration_id"])
    assert r.status_code == 200, r.text
    assert _refunds(reg["registration_id"]) == 1


def test_already_cancelled_still_shows_its_refund_after_the_start(client):
    eid = _event(client, is_free=False, price="500.00")
    reg = _register(client, eid, []).json()
    _pay(client, reg)
    first = _cancel(client, reg["registration_id"])
    assert first.status_code == 200, first.text
    _start_now(eid)

    again = _cancel(client, reg["registration_id"])
    assert again.status_code == 200, again.text
    assert again.json()["refund_id"] == first.json()["refund_id"]
    assert _refunds(reg["registration_id"]) == 1


def test_someone_elses_registration_is_still_not_found(client):
    eid = _event(client, is_free=True)
    reg = _register(client, eid, []).json()
    _start_now(eid)
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/cancel",
        json={"idempotency_key": f"c-{uuid.uuid4().hex}"},
        headers=_bearer(_TEST_ALUMNI_2),
    )
    # Ownership is checked first: no hint that the event has started.
    assert r.status_code == 404
