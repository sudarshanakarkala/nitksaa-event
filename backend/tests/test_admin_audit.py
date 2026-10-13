"""Admin revamp step 10b: GET /api/v1/admin/audit-log.

Scope (overall admins: everything; event admins: their events), the
website's filters plus category / who / search, entries for deleted events,
and that no uids reach the app.
"""
import uuid

from tests.test_payment_refunds import _TEST_ALUMNI, _bearer, _db  # noqa: F401
from tests.test_refund_reliability import (  # noqa: F401  (fixtures)
    _FIXTURE_ADMIN,
    _OTHER_EVENT_ADMIN,
    _PLAIN_USER,
    _cancelled_with_refund,
    _ensure_user,
    _seed,
    provider,
)

_PATH = "/api/v1/admin/audit-log"


def _get(client, identity=_FIXTURE_ADMIN, **params):
    r = client.get(_PATH, params=params, headers=_bearer(identity))
    assert r.status_code == 200, r.text
    return r.json()


def _delayed_refund_event(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    eid = _db("SELECT event_id FROM registrations WHERE registration_id = $1", rid, val=True)
    return eid, rid, row


def test_denied_without_admin_rights(client):
    assert client.get(_PATH).status_code in (401, 403)
    _ensure_user(_PLAIN_USER)
    assert client.get(_PATH, headers=_bearer(_PLAIN_USER)).status_code == 403


def test_overall_admin_sees_an_events_history_in_words(client, provider):
    eid, _rid, row = _delayed_refund_event(client, provider)
    body = _get(client, event_id=eid, page_size=200)
    assert {"rows", "total", "page", "page_size", "pages", "types"} <= set(body)
    by_type = {r["event_type"]: r for r in body["rows"]}

    delayed = by_type["payment_refund_delayed"]
    assert delayed["event_label"] == "Refund delayed" and delayed["category"] == "payments"
    assert delayed["who"] == "system" and delayed["actor_fullname"] == "System"
    reason = next(d["value"] for d in delayed["details"] if d["label"] == "Reason")
    assert reason.startswith("Razorpay balance too low")
    assert delayed["registration_number"] and delayed["order_number"]

    # The attendee cancelled their own registration: an attendee entry.
    assert by_type["payment_refund_requested"]["who"] == "attendee"
    assert by_type["event_created"]["who"] == "admin" and by_type["event_created"]["category"] == "events"

    # People appear by name only; no uids leave the server.
    assert _TEST_ALUMNI["firebase_uid"] not in str(body)
    assert row["public_refund_number"]


def test_event_admins_see_only_their_events(client, provider):
    eid, _rid, _row = _delayed_refund_event(client, provider)
    other_eid, _r2, _row2 = _delayed_refund_event(client, provider)
    admin = _OTHER_EVENT_ADMIN
    _ensure_user(admin)
    _db("""INSERT INTO event_members (event_id, firebase_uid, role, status)
           VALUES ($1,$2,'event_admin','active') ON CONFLICT DO NOTHING""", eid, admin["firebase_uid"])

    mine = _get(client, admin, event_id=eid, page_size=200)
    assert mine["total"] > 0 and {r["event_id"] for r in mine["rows"]} == {eid}

    assert _get(client, admin, event_id=other_eid)["total"] == 0
    everything = _get(client, admin, page_size=200)
    assert other_eid not in {r["event_id"] for r in everything["rows"]}
    assert None not in {r["event_id"] for r in everything["rows"]}   # no all-events role entries


def test_category_who_and_search_filters(client, provider):
    eid, _rid, _row = _delayed_refund_event(client, provider)
    title = _db("SELECT title FROM events WHERE event_id = $1", eid, val=True)

    payments = _get(client, event_id=eid, category="payments", page_size=200)["rows"]
    assert payments and all(r["category"] == "payments" for r in payments)
    system = _get(client, event_id=eid, who="system", page_size=200)["rows"]
    assert system and all(r["who"] == "system" for r in system)
    found = _get(client, q=title[:20], page_size=200)["rows"]
    assert found and all(r["event_id"] == eid for r in found if r["event_title"] == title)
    assert client.get(_PATH, params={"category": "nonsense"}, headers=_bearer(_FIXTURE_ADMIN)).status_code == 422


def test_deleted_event_entries_stay(client):
    gone = 900_000_000 + int(uuid.uuid4().int % 1_000_000)
    _db("""INSERT INTO event_audit_log (actor_uid, event_type, entity_type, entity_id, context)
           VALUES ($1, 'event_deleted', 'event', $2, $3::jsonb)""",
        _FIXTURE_ADMIN["firebase_uid"], gone, '{"title": "Old draft"}')
    row = _get(client, event_id=gone)["rows"][0]
    assert row["event_deleted"] and row["event_title"] == f"Deleted event #{gone}"
    assert row["event_label"] == "Event deleted"


# ── Payments → Orders: one order's details and history ─────────────────────────

def _order_number(rid):
    return _db("SELECT public_order_number FROM payment_orders WHERE registration_id = $1", rid, val=True)


def test_order_details_have_tries_refunds_and_history(client, provider):
    eid, rid, row = _delayed_refund_event(client, provider)
    number = _order_number(rid)
    r = client.get(f"/api/v1/admin/payments/orders/{number}", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["order"]["public_order_number"] == number and body["order"]["event_id"] == eid
    assert body["attempts"] and body["attempts"][0]["status"] == "captured"
    assert body["attempts"][0]["gateway_payment_ref"]
    assert body["refunds"][0]["status"] == "delayed"
    assert body["refunds"][0]["reason_text"].startswith("Razorpay balance too low")
    kinds = [t["event_type"] for t in body["timeline"]]
    assert kinds.index("payment_order_created") < kinds.index("payment_captured") < kinds.index("payment_refund_delayed")
    assert "registration_seat_held" in kinds                       # the registration's own entries too
    assert _TEST_ALUMNI["firebase_uid"] not in r.text


def test_order_details_respect_scope(client, provider):
    _eid, rid, _row = _delayed_refund_event(client, provider)
    other_eid, _r2, _row2 = _delayed_refund_event(client, provider)
    admin = _OTHER_EVENT_ADMIN
    _ensure_user(admin)
    _db("""INSERT INTO event_members (event_id, firebase_uid, role, status)
           VALUES ($1,$2,'event_admin','active') ON CONFLICT DO NOTHING""", other_eid, admin["firebase_uid"])
    r = client.get(f"/api/v1/admin/payments/orders/{_order_number(rid)}", headers=_bearer(admin))
    assert r.status_code == 404
    assert client.get("/api/v1/admin/payments/orders/ORD-nope", headers=_bearer(_FIXTURE_ADMIN)).status_code == 404


def test_orders_list_carries_razorpay_ids_for_search(client, provider):
    eid, rid, _row = _delayed_refund_event(client, provider)
    r = client.get("/api/v1/admin/payments/orders", params={"event_id": eid}, headers=_bearer(_FIXTURE_ADMIN))
    order = next(o for o in r.json()["orders"] if o["registration_id"] == rid)
    pay_ref = _db("""SELECT a.gateway_payment_ref FROM payment_attempts a JOIN payment_orders o ON o.id = a.order_id
                     WHERE o.registration_id = $1""", rid, val=True)
    assert pay_ref in order["provider_refs"]
