"""S-1: the public seat count agrees with Register.

A seat being paid for (a hold that hasn't run out) counts as taken on the
Events list and the event page, as it does for Register. A hold that has
run out doesn't count. The Dashboard keeps counting paid registrations only.
"""
from tests.test_guests import _event, _pay, _register
from tests.test_payment_refunds import _TEST_ALUMNI_2, _db, _seed  # noqa: F401  (autouse)


def _public(client, eid):
    r = client.get(f"/api/v1/events/public/{eid}")
    assert r.status_code == 200, r.text
    return r.json()["event"]


def test_a_seat_being_paid_for_counts_everywhere(client):
    eid = _event(client, is_free=False, price="500.00", capacity=1, max_guests=0)
    reg = _register(client, eid, []).json()
    assert reg["status"] != "registered"  # held while paying

    ev = _public(client, eid)
    assert ev["registered_count"] == 1
    assert ev["registration_status"] == "full"
    # Register agrees: nobody else gets the seat.
    assert _register(client, eid, [], identity=_TEST_ALUMNI_2).status_code != 201


def test_paid_seat_still_counts(client):
    eid = _event(client, is_free=False, price="500.00", capacity=2, max_guests=0)
    reg = _register(client, eid, []).json()
    _pay(client, reg)
    ev = _public(client, eid)
    assert ev["registered_count"] == 1
    assert ev["registration_status"] == "open"


def test_a_hold_that_ran_out_doesnt_count(client):
    eid = _event(client, is_free=False, price="500.00", capacity=1, max_guests=0)
    reg = _register(client, eid, []).json()
    _db("UPDATE registrations SET hold_expires_at = now() - interval '1 minute'"
        " WHERE registration_id = $1", reg["registration_id"])

    ev = _public(client, eid)
    assert ev["registered_count"] == 0
    assert ev["registration_status"] == "open"
    # Register agrees: the seat is free again.
    assert _register(client, eid, [], identity=_TEST_ALUMNI_2).status_code == 201


def test_free_event_counts_as_before(client):
    eid = _event(client, is_free=True, capacity=5)
    _register(client, eid, ["Asha"])
    assert _public(client, eid)["registered_count"] == 2
