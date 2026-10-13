"""Refund reliability (admin revamp step 10c).

A refund the provider refuses for a temporary reason becomes 'delayed' and is
retried; a final reason (or the retry window running out) makes it 'failed'
and a person is told. Retries ask the provider what already exists first, so
a payment is never refunded twice. Emails go out once each.

Driven end-to-end through the ASGI app with the deterministic sandbox
gateway; its refund() and a list_refunds() are replaced per test. Background
side tasks are off in tests (conftest), so the maintenance run is what sends
emails and runs scheduled retries here, as it does in production.
"""
import asyncio
import uuid

import pytest

from tests.test_payment_refunds import (  # noqa: F401  (_seed is an autouse fixture)
    _FIXTURE_ADMIN,
    _TEST_ALUMNI,
    _bearer,
    _db,
    _mk_event,
    _paid_registered,
    _seed,
)

_OTHER_EVENT_ADMIN = {
    "firebase_uid": "TEST_REFUND_EVADMIN_001", "sub": "refund.evadmin@nitksaa.dev",
    "email": "refund.evadmin@nitksaa.dev", "fullname": "Refund Event Admin Test",
    "user_type": "alumni", "ref_id": None, "graduation_year": 2016,
}

_PLAIN_USER = {
    "firebase_uid": "TEST_REFUND_PLAIN_001", "sub": "refund.plain@nitksaa.dev",
    "email": "refund.plain@nitksaa.dev", "fullname": "Refund Plain User Test",
    "user_type": "alumni", "ref_id": None, "graduation_year": 2016,
}


def _ensure_user(ident):
    _db("""INSERT INTO event_users (firebase_uid, email, fullname, user_type, graduation_year)
           VALUES ($1,$2,$3,$4,$5) ON CONFLICT (firebase_uid) DO NOTHING""",
        ident["firebase_uid"], ident["email"], ident["fullname"], ident["user_type"], ident["graduation_year"])


# ── fakes ────────────────────────────────────────────────────────────

class _Provider:
    """Stands in for the provider's refund API on the sandbox gateway.

    `refuse`: a RefundFailureReason to refuse with, or None to succeed.
    `existing`: provider_payment_id -> refunds the provider already holds.
    Only payments this test made are refused, so other tests' leftover
    refunds picked up by a maintenance run are left alone.
    """

    def __init__(self, monkeypatch):
        from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

        self.refuse = None
        self.existing = {}
        self.ours = set()
        self.refund_calls = []
        original = DeterministicSandboxGateway.refund
        provider = self

        def refund(gw_self, **kw):
            from app.gateways.base import GatewayRefundRefusedError
            if kw["provider_payment_id"] in provider.ours:
                provider.refund_calls.append(kw)
                if provider.refuse is not None:
                    raise GatewayRefundRefusedError(provider.refuse)
            return original(gw_self, **kw)

        def list_refunds(gw_self, *, provider_payment_id, payment_mode=None):
            return list(provider.existing.get(provider_payment_id, []))

        monkeypatch.setattr(DeterministicSandboxGateway, "refund", refund)
        monkeypatch.setattr(DeterministicSandboxGateway, "list_refunds", list_refunds, raising=False)

    def found(self, payment_id, amount_minor, refund_id="rfnd_found_at_provider"):
        from app.gateways.base import NormalizedRefundResult, NormalizedRefundStatus
        self.existing.setdefault(payment_id, []).append(NormalizedRefundResult(
            provider_refund_id=refund_id, status=NormalizedRefundStatus.REFUND_PROCESSED,
            amount_minor=amount_minor, currency="INR", raw_status="processed",
            bank_reference="ARN123456", provider_payment_id=payment_id,
        ))


@pytest.fixture
def provider(monkeypatch):
    return _Provider(monkeypatch)


@pytest.fixture
def mails(monkeypatch):
    """Records refund emails as (kind, to, refund_number)."""
    from app.services import email_service

    sent = []

    def recorder(kind):
        async def _send(email_to, d):
            sent.append((kind, email_to, d.get("refund_number")))
            return email_service.EmailResult(status="sent", sent_at=None, error=None)
        return _send

    for kind in ("delayed", "processed", "failed"):
        monkeypatch.setattr(email_service, f"send_refund_{kind}_email", recorder(kind))
    monkeypatch.setattr(email_service, "send_refund_admin_alert", recorder("admin"))
    return sent


# ── helpers ──────────────────────────────────────────────────────────

def _cancelled_with_refund(client, provider, *, refuse=None):
    """A paid registration, cancelled; returns (registration_id, refund row,
    cancel response). `refuse` makes the first refund call fail."""
    from app.gateways.base import RefundFailureReason

    eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    reg, _order = _paid_registered(client, eid)
    rid = reg["registration_id"]
    payment_id = _db(
        """SELECT a.gateway_payment_ref FROM payment_attempts a
           JOIN payment_orders o ON o.id = a.order_id
           WHERE o.registration_id = $1 AND a.status = 'captured'""", rid, val=True)
    provider.ours.add(payment_id)
    provider.refuse = RefundFailureReason(refuse) if refuse else None
    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 200, r.text
    return rid, _refund(rid), r.json()


def _refund(rid):
    return _db("SELECT * FROM payment_refunds WHERE registration_id = $1", rid)[0]


def _make_due(rid, *, days_old=None):
    # The earliest possible next try, so this row is first in the run's batch.
    _db("UPDATE payment_refunds SET next_retry_at = '2000-01-01' WHERE registration_id = $1", rid)
    if days_old:
        _db(f"UPDATE payment_refunds SET requested_at = now() - interval '{int(days_old)} days' "
            "WHERE registration_id = $1", rid)


def _maintenance(client, headers=None):
    r = client.post("/api/v1/internal/maintenance", headers=_bearer(_FIXTURE_ADMIN) if headers is None else headers)
    assert r.status_code == 200, r.text
    return r.json()


def _retry_now(client, refund_number, identity=_FIXTURE_ADMIN):
    return client.post(f"/api/v1/admin/payments/refunds/{refund_number}/retry", headers=_bearer(identity))


# ── delayed vs failed ────────────────────────────────────────────────

def test_low_balance_refusal_delays_the_refund(client, provider):
    rid, row, body = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    assert row["status"] == "delayed"
    assert row["failure_reason"] == "insufficient_balance"
    assert row["next_retry_at"] is not None and row["finalized_at"] is None
    assert body["status"] == "refund_delayed"
    assert "retrying automatically" in body["safe_message"]
    assert body["payment_reference"] == row["provider_payment_id"]
    # The registration stays cancelled.
    assert _db("SELECT status FROM registrations WHERE registration_id=$1", rid, val=True) == "cancelled"
    # And the attendee sees the same on the refund page.
    g = client.get(f"/api/v1/registrations/{rid}/refund", headers=_bearer())
    assert g.json()["status"] == "refund_delayed"


def test_final_refusal_fails_at_once(client, provider):
    rid, row, body = _cancelled_with_refund(client, provider, refuse="payment_too_old")
    assert row["status"] == "failed"
    assert row["failure_reason"] == "payment_too_old"
    assert row["next_retry_at"] is None and row["finalized_at"] is not None
    assert body["status"] == "refund_failed"
    assert "contact you within 2 working days" in body["safe_message"]


def test_a_delayed_refund_blocks_a_second_refund(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 200
    assert _db("SELECT count(*) FROM payment_refunds WHERE registration_id=$1", rid, val=True) == 1


# ── retries ──────────────────────────────────────────────────────────

def test_scheduled_retry_sends_the_refund_once_the_balance_is_there(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    provider.refuse = None
    _make_due(rid)
    _maintenance(client)
    after = _refund(rid)
    assert after["status"] == "processed"
    assert after["attempt_count"] == 2
    assert after["provider_refund_id"]
    # A fresh key per try: the provider remembers a refused key's answer.
    assert provider.refund_calls[-1]["idempotency_key"] == f"{row['idempotency_key']}:try2"
    assert client.get(f"/api/v1/registrations/{rid}/refund", headers=_bearer()).json()["status"] == "refund_processed"


def test_still_refused_stays_delayed_with_a_new_next_try(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    _make_due(rid)
    _maintenance(client)
    after = _refund(rid)
    assert after["status"] == "delayed"
    assert after["attempt_count"] == 2
    assert after["next_retry_at"].year > 2000


def test_a_refund_not_yet_due_is_left_alone(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    provider.refuse = None
    _maintenance(client)  # next try is 6 hours away
    after = _refund(rid)
    assert after["status"] == "delayed" and after["attempt_count"] == 1


def test_retry_adopts_a_refund_the_provider_already_made(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="provider_unavailable")
    assert row["status"] == "delayed"
    calls_before = len(provider.refund_calls)
    # The earlier call timed out on our side but did reach the provider.
    provider.found(row["provider_payment_id"], amount_minor=100)
    r = _retry_now(client, row["public_refund_number"])
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "processed"
    after = _refund(rid)
    assert after["provider_refund_id"] == "rfnd_found_at_provider"
    assert after["bank_reference"] == "ARN123456"
    assert len(provider.refund_calls) == calls_before  # never asked to refund again


def test_retry_stops_when_someone_refunded_outside_the_app(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    calls_before = len(provider.refund_calls)
    provider.found(row["provider_payment_id"], amount_minor=50, refund_id="rfnd_dashboard")
    r = _retry_now(client, row["public_refund_number"])
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "failed"
    assert r.json()["failure_reason"] == "refunded_outside_app"
    assert "outside the app" in r.json()["reason_text"]
    assert len(provider.refund_calls) == calls_before


def test_gives_up_after_the_retry_window(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    _make_due(rid, days_old=8)
    _maintenance(client)
    after = _refund(rid)
    assert after["status"] == "failed"
    assert after["failure_reason"] == "insufficient_balance"
    assert after["finalized_at"] is not None
    gave_up = _db(
        """SELECT count(*) FROM event_audit_log
           WHERE entity_type = 'payment_refund' AND entity_id = $1
             AND event_type = 'payment_refund_failed' AND (context->>'gave_up')::boolean""",
        row["id"], val=True)
    assert gave_up == 1


def test_retry_now_works_on_a_failed_refund(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="declined")
    assert row["status"] == "failed"
    provider.refuse = None
    r = _retry_now(client, row["public_refund_number"])
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "processed"
    assert r.json()["attempt_count"] == 2
    audit = _db("""SELECT context->>'source' FROM event_audit_log
                   WHERE entity_type = 'payment_refund' AND entity_id = $1
                     AND event_type = 'payment_refund_retried'""", row["id"], val=True)
    assert audit == "admin"


# ── Retry now: who may press it ──────────────────────────────────────

def test_retry_now_permissions(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    number = row["public_refund_number"]

    # Someone with no admin rights at all.
    _ensure_user(_PLAIN_USER)
    assert _retry_now(client, number, _PLAIN_USER).status_code == 403

    # Admin of a different event: looks like it doesn't exist.
    other = _OTHER_EVENT_ADMIN
    _ensure_user(other)
    other_eid = _mk_event(client, uuid.uuid4().hex[:8], is_free=True)
    _db("""INSERT INTO event_members (event_id, firebase_uid, role, status)
           VALUES ($1,$2,'event_admin','active') ON CONFLICT DO NOTHING""", other_eid, other["firebase_uid"])
    assert _retry_now(client, number, other).status_code == 404

    # Unknown refund.
    assert _retry_now(client, "RFND-does-not-exist").status_code == 404

    # The refund is still untouched.
    assert _refund(rid)["attempt_count"] == 1

    # A processed refund can't be retried.
    provider.refuse = None
    assert _retry_now(client, number).status_code == 200
    r = _retry_now(client, number)
    assert r.status_code == 409
    assert r.json()["detail"] == "refund_is_processed"


def test_event_admin_may_retry_their_own_events_refund(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    eid = _db("SELECT event_id FROM registrations WHERE registration_id = $1", rid, val=True)
    other = _OTHER_EVENT_ADMIN
    _ensure_user(other)
    _db("""INSERT INTO event_members (event_id, firebase_uid, role, status)
           VALUES ($1,$2,'event_admin','active') ON CONFLICT DO NOTHING""", eid, other["firebase_uid"])
    provider.refuse = None
    r = _retry_now(client, row["public_refund_number"], other)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "processed"


# ── emails ───────────────────────────────────────────────────────────

def _drain_emails(client, rid, column):
    # Each run handles a batch of the oldest unsent ones; other tests leave
    # plenty behind, so run until this refund's turn has come.
    for _ in range(30):
        _maintenance(client)
        if _refund(rid)[column] is not None:
            return
    raise AssertionError(f"{column} never set")


def test_delayed_then_sent_emails_go_out_once_each(client, provider, mails):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    number = row["public_refund_number"]
    _drain_emails(client, rid, "attendee_notified_delay_at")
    assert [m for m in mails if m[2] == number] == [("delayed", _TEST_ALUMNI["email"], number)]

    _maintenance(client)  # nothing new to say
    assert len([m for m in mails if m[2] == number]) == 1

    provider.refuse = None
    assert _retry_now(client, number).json()["status"] == "processed"
    _drain_emails(client, rid, "attendee_notified_result_at")
    _maintenance(client)
    assert [m for m in mails if m[2] == number] == [
        ("delayed", _TEST_ALUMNI["email"], number),
        ("processed", _TEST_ALUMNI["email"], number),
    ]


def test_final_failure_tells_the_attendee_admins_and_finance(client, provider, mails, monkeypatch):
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "finance_alert_email", "finance.one@nitksaa.dev, finance.two@nitksaa.dev")

    rid, row, _ = _cancelled_with_refund(client, provider, refuse="payment_too_old")
    number = row["public_refund_number"]
    _drain_emails(client, rid, "admins_notified_at")
    _maintenance(client)

    mine = [m for m in mails if m[2] == number]
    assert ("failed", _TEST_ALUMNI["email"], number) in mine
    admin_to = sorted(m[1] for m in mine if m[0] == "admin")
    # The event's admin (its creator) plus both finance addresses, once each.
    assert admin_to == sorted([_FIXTURE_ADMIN["email"], "finance.one@nitksaa.dev", "finance.two@nitksaa.dev"])
    assert len(mine) == 4


def test_demo_addresses_are_never_emailed():
    from app.services import email_service
    result = asyncio.run(email_service.send_email("someone.demo@example.invalid", "s", "p", "<p>h</p>"))
    assert result.status == "skipped"


# ── maintenance endpoint ─────────────────────────────────────────────

def test_maintenance_needs_an_overall_admin_or_the_scheduler(client):
    assert client.post("/api/v1/internal/maintenance").status_code == 401
    assert client.post("/api/v1/internal/maintenance",
                       headers={"Authorization": "Bearer not-a-token"}).status_code == 401
    _ensure_user(_PLAIN_USER)
    assert client.post("/api/v1/internal/maintenance", headers=_bearer(_PLAIN_USER)).status_code == 403
    body = _maintenance(client)
    assert body["run_by"] == "admin"
    for key in ("refunds_retried", "refunds_handed_to_a_person", "refunds_checked_with_provider",
                "orders_expired", "holds_expired", "refund_emails_sent"):
        assert key in body and body[key] != "error", body


def test_maintenance_accepts_the_schedulers_google_token(client, monkeypatch):
    from app.api import maintenance
    from app.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "maintenance_audience", "https://events-api.test")
    monkeypatch.setattr(settings, "maintenance_invoker_email", "scheduler@project.iam.gserviceaccount.com")

    def verify(token, audience):
        assert audience == "https://events-api.test"
        if token == "google-ok":
            return {"email": "scheduler@project.iam.gserviceaccount.com", "email_verified": True}
        if token == "google-other":
            return {"email": "someone.else@gmail.com", "email_verified": True}
        raise ValueError("not a google token")

    monkeypatch.setattr(maintenance, "_verify_google_token", verify)
    r = client.post("/api/v1/internal/maintenance", headers={"Authorization": "Bearer google-ok"})
    assert r.status_code == 200 and r.json()["run_by"] == "scheduler"
    # A valid Google token for anyone else isn't enough.
    assert client.post("/api/v1/internal/maintenance",
                       headers={"Authorization": "Bearer google-other"}).status_code == 401
    # An overall admin's app sign-in still works alongside.
    assert _maintenance(client)["run_by"] == "admin"


# ── admin views ──────────────────────────────────────────────────────

def test_refunds_list_explains_the_reason_and_offers_retry(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    eid = _db("SELECT event_id FROM registrations WHERE registration_id = $1", rid, val=True)
    r = client.get(f"/api/v1/admin/payments/refunds?event_id={eid}", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    item = next(f for f in r.json()["refunds"] if f["public_refund_number"] == row["public_refund_number"])
    assert item["status"] == "delayed"
    assert item["can_retry"] is True
    assert "balance too low" in item["reason_text"]
    assert item["attempt_count"] == 1 and item["next_retry_at"]
    assert item["provider_payment_id"] == row["provider_payment_id"]


def test_actions_count_delayed_refunds_as_information_only(client, provider):
    _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    r = client.get("/api/v1/admin/pending-count", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()
    queues = body.get("queues", body)
    assert queues["delayed_refunds"] >= 1
    badge = sum(queues[k] for k in ("drafts", "failed_emails", "stuck_payments", "failed_refunds"))
    assert body["total"] == badge
