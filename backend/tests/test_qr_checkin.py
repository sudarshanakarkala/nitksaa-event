"""QR check-in: the attendee gets their own token (their entry pass) once
registered, and an event admin checks them in with it."""
import uuid

from tests.test_non_alumni_registration import (
    _FIXTURE_ADMIN,
    _bearer,
    _mk_free_event,
    _non_alumnus,
    _register,
    _seed,  # noqa: F401  (autouse fixture: seeds the admin and test alumnus)
    _seed_user,
)
from tests.test_payments import _mk_paid_event


def test_registered_attendee_gets_their_token_and_is_checked_in(client):
    who = _non_alumnus()
    _seed_user(who)
    eid = _mk_free_event(client)
    reg = _register(client, eid, who, fullname="Asha Rao", phone="9845012345").json()
    token = reg["qr_token"]
    assert token

    # The same token comes back on the attendee's own registration views.
    mine = client.get(f"/api/v1/events/{eid}/my-registration", headers=_bearer(who)).json()
    assert mine["qr_token"] == token

    admin = _bearer(_FIXTURE_ADMIN)
    v = client.get(f"/api/v1/admin/events/{eid}/check-ins/verify",
                   params={"qr_token": token}, headers=admin)
    assert v.status_code == 200, v.text
    assert v.json()["full_name"] == "Asha Rao"
    assert v.json()["message"] == "ready_to_checkin"

    c = client.post(f"/api/v1/admin/events/{eid}/check-ins", json={"qr_token": token}, headers=admin)
    assert c.status_code == 201, c.text
    again = client.get(f"/api/v1/admin/events/{eid}/check-ins/verify",
                       params={"qr_token": token}, headers=admin)
    assert again.json()["already_checked_in"] is True


def test_held_seat_has_no_entry_pass(client):
    who = _non_alumnus()
    _seed_user(who)
    eid = _mk_paid_event(client, f"qr-{uuid.uuid4().hex[:8]}")
    reg = _register(client, eid, who, fullname="Asha Rao", phone="9845012345").json()
    assert reg["status"] == "seat_held"
    assert reg["qr_token"] is None


def test_attendee_cannot_check_themselves_in(client):
    who = _non_alumnus()
    _seed_user(who)
    eid = _mk_free_event(client)
    token = _register(client, eid, who, fullname="Asha Rao", phone="9845012345").json()["qr_token"]
    r = client.post(f"/api/v1/admin/events/{eid}/check-ins", json={"qr_token": token}, headers=_bearer(who))
    assert r.status_code in (401, 403)
