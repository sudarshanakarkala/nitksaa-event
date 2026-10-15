"""Guests (step 4): one registrations row per person, grouped by group_head_id.

Through the ASGI app against local Postgres with the deterministic sandbox
gateway: registering with guests, seats counted per person, price x people,
each guest's own QR at the door, cancelling one guest (one share refunded)
and then the rest, and Razorpay refunds told apart by our refund number.
"""
import uuid
from decimal import Decimal

import pytest

from tests.test_payment_refunds import (
    _ADMIN,
    _FIXTURE_ADMIN,
    _TEST_ALUMNI,
    _TEST_ALUMNI_2,
    _bearer,
    _db,
    _seed,  # noqa: F401  (autouse fixture: the test users and admin)
)


def _event(client, *, is_free, capacity=20, max_guests=4, price="500.00"):
    suffix = uuid.uuid4().hex[:8]
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"GUESTS {suffix}", "description": "pytest",
            "start_datetime": "2027-03-01T08:00:00+05:30",
            "end_datetime": "2027-03-01T10:00:00+05:30",
            "location_text": "V", "is_virtual": False, "capacity": capacity,
            "is_free": is_free, "ticket_price": None if is_free else price,
            "max_guests": max_guests,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    assert r.json()["max_guests"] == max_guests
    eid = r.json()["event_id"]
    assert client.post(f"/api/v1/admin/events/{eid}/publish", headers=_bearer(_FIXTURE_ADMIN)).status_code == 200
    if not is_free:
        r = client.post(
            "/api/v1/dev/diagnostics/payments/configuration/import",
            json={
                "configuration_key": f"g-{suffix}", "event_id": eid,
                "base_amount": price, "gst_enabled": False,
                "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15,
                "gateway": "deterministic_sandbox",
            },
            headers=_ADMIN,
        )
        assert r.status_code == 200, r.text
    return eid


def _register(client, eid, guests, identity=_TEST_ALUMNI):
    return client.post(
        f"/api/v1/events/{eid}/register",
        json={"guests": [{"name": g} for g in guests]},
        headers=_bearer(identity),
    )


def _pay(client, reg, identity=_TEST_ALUMNI):
    h = _bearer(identity)
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"k-{uuid.uuid4().hex}"}, headers=h,
    ).json()
    att = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "SUCCESS"}, headers=h,
    ).json()
    assert att["status"] == "captured", att
    return order


def _cancel(client, registration_id, identity=_TEST_ALUMNI):
    return client.post(
        f"/api/v1/registrations/{registration_id}/cancel",
        json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=_bearer(identity),
    )


def _seats(eid):
    return _db(
        "SELECT count(*) FROM registrations WHERE event_id=$1 AND status <> 'cancelled'",
        eid, val=True,
    )


def _verify(client, eid, token):
    r = client.get(f"/api/v1/admin/events/{eid}/check-ins/verify",
                   params={"qr_token": token}, headers=_bearer(_FIXTURE_ADMIN))
    if r.status_code == 404:  # older route shape
        r = client.post(f"/api/v1/admin/events/{eid}/check-ins/verify",
                        json={"qr_token": token}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    return r.json()


def _check_in(client, eid, token):
    return client.post(f"/api/v1/admin/events/{eid}/check-ins",
                       json={"qr_token": token}, headers=_bearer(_FIXTURE_ADMIN))


# ── registering ───────────────────────────────────────────────────────

def test_solo_registration_is_its_own_group(client):
    eid = _event(client, is_free=True)
    r = _register(client, eid, [])
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["guests"] == []
    rid = body["registration_id"]
    assert _db("SELECT group_head_id FROM registrations WHERE registration_id=$1", rid, val=True) == rid


def test_free_event_with_guests_one_row_and_qr_each(client):
    eid = _event(client, is_free=True)
    r = _register(client, eid, ["Asha Warrier", "Kiran Warrier"])
    assert r.status_code == 201, r.text
    body = r.json()
    assert [g["name"] for g in body["guests"]] == ["Asha Warrier", "Kiran Warrier"]
    assert all(g["status"] == "registered" for g in body["guests"])
    tokens = {body["qr_token"], *(g["qr_token"] for g in body["guests"])}
    assert len(tokens) == 3 and None not in tokens
    assert all(g["registration_number"] for g in body["guests"])
    assert _seats(eid) == 3

    # My registration and My Events: the leader, with the guests under them.
    mine = client.get(f"/api/v1/events/{eid}/my-registration", headers=_bearer()).json()
    assert mine["registration_id"] == body["registration_id"]
    assert len(mine["guests"]) == 2
    listed = [x for x in client.get("/api/v1/my/registrations", headers=_bearer()).json()["registrations"]
              if x["event_id"] == eid]
    assert len(listed) == 1 and len(listed[0]["guests"]) == 2


def test_guests_need_names_and_respect_the_event_limit(client):
    eid = _event(client, is_free=True, max_guests=1)
    r = _register(client, eid, ["One", "Two"])
    assert r.status_code == 422 and r.json()["detail"] == "too_many_guests"
    r = _register(client, eid, ["  "])
    assert r.status_code == 422 and r.json()["detail"] == "guest_name_required"
    no_guests = _event(client, is_free=True, max_guests=0)
    r = _register(client, no_guests, ["One"])
    assert r.status_code == 422
    assert _seats(eid) == 0 and _seats(no_guests) == 0


def test_group_too_big_for_the_seats_left_is_refused_whole(client):
    eid = _event(client, is_free=True, capacity=3)
    assert _register(client, eid, [], identity=_TEST_ALUMNI_2).status_code == 201
    r = _register(client, eid, ["A", "B"])  # 3 people, 2 seats left
    assert r.status_code == 409 and r.json()["detail"] == "not_enough_seats"
    assert _seats(eid) == 1
    assert _register(client, eid, ["A"]).status_code == 201  # 2 people fit
    assert _seats(eid) == 3


# ── paying ────────────────────────────────────────────────────────────

def test_paid_group_pays_price_times_people_and_guests_follow(client):
    eid = _event(client, is_free=False, price="500.00")
    pricing = client.get(f"/api/v1/events/{eid}/payment-pricing", params={"people": 3},
                         headers=_bearer()).json()
    assert Decimal(pricing["final_amount"]) == Decimal("1500.00") and pricing["people"] == 3

    reg = _register(client, eid, ["Asha", "Kiran"]).json()
    assert all(g["status"] == "seat_held" for g in reg["guests"])
    assert _seats(eid) == 3  # held seats count
    order = _pay(client, reg)
    assert Decimal(str(order["final_amount"])) == Decimal("1500.00")
    statuses = _db("SELECT status FROM registrations WHERE group_head_id=$1", reg["registration_id"])
    assert {s["status"] for s in statuses} == {"registered"}
    assert _db("SELECT quantity FROM payment_orders WHERE public_order_number=$1",
               order["order_id"], val=True) == 3


# ── cancelling and refunds ────────────────────────────────────────────

def test_cancel_one_guest_then_the_rest_refunds_add_up(client):
    eid = _event(client, is_free=False, price="500.00")
    reg = _register(client, eid, ["Asha", "Kiran"]).json()
    order = _pay(client, reg)
    asha = reg["guests"][0]["registration_id"]

    r = _cancel(client, asha)
    assert r.status_code == 200, r.text
    assert Decimal(str(r.json()["amount"])) == Decimal("500.00")
    rows = {x["fullname_snapshot"]: x["status"] for x in _db(
        "SELECT fullname_snapshot, status FROM registrations WHERE group_head_id=$1",
        reg["registration_id"])}
    assert rows["Asha"] == "cancelled" and rows["Kiran"] == "registered"
    assert _seats(eid) == 2

    r = _cancel(client, reg["registration_id"])  # the leader: everyone left
    assert r.status_code == 200, r.text
    assert Decimal(str(r.json()["amount"])) == Decimal("1000.00")
    assert _seats(eid) == 0
    refunds = _db("SELECT amount FROM payment_refunds WHERE payment_order_id="
                  "(SELECT id FROM payment_orders WHERE public_order_number=$1)", order["order_id"])
    assert sum(Decimal(x["amount"]) for x in refunds) == Decimal("1500.00")

    # Cancelling again changes nothing.
    assert _cancel(client, asha).status_code == 200
    assert len(_db("SELECT id FROM payment_refunds WHERE payment_order_id="
                   "(SELECT id FROM payment_orders WHERE public_order_number=$1)", order["order_id"])) == 2


def test_two_equal_guest_refunds_are_two_refunds(client):
    eid = _event(client, is_free=False, price="500.00")
    reg = _register(client, eid, ["Asha", "Kiran"]).json()
    _pay(client, reg)
    a = _cancel(client, reg["guests"][0]["registration_id"]).json()
    b = _cancel(client, reg["guests"][1]["registration_id"]).json()
    assert a["refund_id"] != b["refund_id"]
    assert Decimal(str(a["amount"])) == Decimal(str(b["amount"])) == Decimal("500.00")
    assert _db("SELECT status FROM registrations WHERE registration_id=$1",
               reg["registration_id"], val=True) == "registered"


def test_only_the_leader_cancels_a_guest(client):
    eid = _event(client, is_free=True)
    reg = _register(client, eid, ["Asha"]).json()
    r = _cancel(client, reg["guests"][0]["registration_id"], identity=_TEST_ALUMNI_2)
    assert r.status_code == 404
    assert _seats(eid) == 2


def test_free_group_leader_unregistering_cancels_everyone(client):
    eid = _event(client, is_free=True)
    reg = _register(client, eid, ["Asha", "Kiran"]).json()
    assert _cancel(client, reg["registration_id"]).status_code == 200
    assert _seats(eid) == 0
    # And they can register again.
    assert _register(client, eid, ["Asha"]).status_code == 201


# ── at the door ───────────────────────────────────────────────────────

def test_each_guest_checks_in_alone_and_a_cancelled_guest_is_refused(client):
    eid = _event(client, is_free=True)
    reg = _register(client, eid, ["Asha", "Kiran"]).json()
    asha, kiran = reg["guests"]

    v = _verify(client, eid, kiran["qr_token"])
    assert v["valid"] is True and v["full_name"] == "Kiran"
    assert v["guest_of"] == reg["fullname_snapshot"]
    assert _verify(client, eid, reg["qr_token"])["guest_of"] is None

    assert _check_in(client, eid, kiran["qr_token"]).status_code in (200, 201)
    assert _verify(client, eid, kiran["qr_token"])["already_checked_in"] is True
    assert _verify(client, eid, reg["qr_token"])["already_checked_in"] is False

    assert _cancel(client, asha["registration_id"]).status_code == 200
    v = _verify(client, eid, asha["qr_token"])
    assert v["valid"] is False and v["message"] == "registration_not_eligible"
    assert _check_in(client, eid, asha["qr_token"]).status_code == 403


def test_admin_lists_show_guest_of(client):
    eid = _event(client, is_free=True)
    reg = _register(client, eid, ["Asha"]).json()
    r = client.get(f"/api/v1/admin/events/{eid}/attendees", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    by_name = {a["fullname_snapshot"]: a for a in r.json()["attendees"]}
    assert by_name["Asha"]["guest_of"] == reg["fullname_snapshot"]
    assert by_name[reg["fullname_snapshot"]]["guest_of"] is None
    csv = client.get(f"/api/v1/admin/events/{eid}/attendees/export", headers=_bearer(_FIXTURE_ADMIN))
    assert csv.status_code == 200
    assert "guest_of" in csv.text.splitlines()[0]


# ── Razorpay: refunds told apart by our refund number ─────────────────

def test_retry_adopts_only_its_own_refund_at_the_provider(client, monkeypatch):
    """Two ₹500 refunds on one payment: a retry of the second must not take
    the first one's provider refund for its own (same amount), and must
    find its own by our refund number."""
    from app.gateways.base import GatewayError, NormalizedRefundResult, NormalizedRefundStatus
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

    eid = _event(client, is_free=False, price="500.00")
    reg = _register(client, eid, ["Asha", "Kiran"]).json()
    _pay(client, reg)
    first = _cancel(client, reg["guests"][0]["registration_id"]).json()  # processed

    provider_holds = [NormalizedRefundResult(
        provider_refund_id=_db("SELECT provider_refund_id FROM payment_refunds WHERE public_refund_number=$1",
                               first["refund_id"], val=True),
        status=NormalizedRefundStatus.REFUND_PROCESSED, amount_minor=50000, currency="INR",
        refund_number=first["refund_id"],
    )]

    def _down(self, **kw):
        raise GatewayError("simulated outage")

    monkeypatch.setattr(DeterministicSandboxGateway, "refund", _down)
    second = _cancel(client, reg["guests"][1]["registration_id"]).json()
    assert second["status"] == "refund_delayed"
    refund_id = _db("SELECT id FROM payment_refunds WHERE public_refund_number=$1", second["refund_id"], val=True)

    def _retry_now():
        r = client.post(f"/api/v1/admin/payments/refunds/{second['refund_id']}/retry",
                        headers=_bearer(_FIXTURE_ADMIN))
        assert r.status_code == 200, r.text
        return _db("SELECT status, provider_refund_id FROM payment_refunds WHERE id=$1", refund_id)[0]

    sent = []

    def _refund(self, **kw):
        sent.append(kw)
        return NormalizedRefundResult(provider_refund_id="sbx_second", status=NormalizedRefundStatus.REFUND_PROCESSED,
                                      amount_minor=kw["amount_minor"], currency="INR",
                                      refund_number=kw.get("refund_number"))

    monkeypatch.setattr(DeterministicSandboxGateway, "refund", _refund)
    monkeypatch.setattr(DeterministicSandboxGateway, "list_refunds",
                        lambda self, **kw: list(provider_holds), raising=False)

    row = _retry_now()
    # The first refund wasn't taken for this one: a new refund was sent,
    # carrying this refund's number.
    assert len(sent) == 1 and sent[0]["refund_number"] == second["refund_id"]
    assert row["status"] == "processed" and row["provider_refund_id"] == "sbx_second"

    # Had the provider already held this refund (response lost), the retry
    # takes it instead of refunding twice.
    _db("UPDATE payment_refunds SET status='delayed', provider_refund_id=NULL WHERE id=$1", refund_id)
    provider_holds.append(NormalizedRefundResult(
        provider_refund_id="sbx_second", status=NormalizedRefundStatus.REFUND_PROCESSED,
        amount_minor=50000, currency="INR", refund_number=second["refund_id"]))
    sent.clear()
    row = _retry_now()
    assert sent == [] and row["status"] == "processed"
