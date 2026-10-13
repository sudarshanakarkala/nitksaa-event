"""Refund reliability (admin revamp step 10c).

A refund the provider refuses for a temporary reason becomes 'delayed' and is
retried after each captured payment and on an admin's Retry now; a final
reason (or a retry after the retry window) makes it 'failed' and a person is
told. Retries ask the provider what already exists first, so a payment is
never refunded twice. Emails go out once each.

Driven end-to-end through the ASGI app with the deterministic sandbox
gateway; its refund() and a list_refunds() are replaced per test. Background
side tasks are off in tests (conftest); tests that check them switch them on
with the `background` fixture.
"""
import asyncio
import time
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
    delayed refunds retried after a capture are left to succeed.
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
def background(monkeypatch):
    """Runs refund side tasks (emails, retries after a capture) for real, at
    once instead of after the usual short delay."""
    from app.services import refund_service

    def run_soon(coro, delay_seconds=2.0):
        asyncio.get_running_loop().create_task(coro)

    monkeypatch.setattr(refund_service, "_spawn", run_soon)


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


def _wait_for(check, seconds=10.0):
    """Background tasks run on the app's loop; wait for their effect."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.1)
    raise AssertionError("background task didn't finish in time")


def _retry_now(client, refund_number, identity=_FIXTURE_ADMIN):
    return client.post(f"/api/v1/admin/payments/refunds/{refund_number}/retry", headers=_bearer(identity))


# ── delayed vs failed ────────────────────────────────────────────────

def test_low_balance_refusal_delays_the_refund(client, provider):
    rid, row, body = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    assert row["status"] == "delayed"
    assert row["failure_reason"] == "insufficient_balance"
    assert row["finalized_at"] is None
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
    assert row["finalized_at"] is not None
    assert body["status"] == "refund_failed"
    assert "contact you within 2 working days" in body["safe_message"]


def test_a_delayed_refund_blocks_a_second_refund(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    r = client.post(f"/api/v1/registrations/{rid}/cancel",
                    json={"idempotency_key": f"c-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 200
    assert _db("SELECT count(*) FROM payment_refunds WHERE registration_id=$1", rid, val=True) == 1


# ── retries ──────────────────────────────────────────────────────────

def test_a_new_payment_retries_delayed_refunds(client, provider, background):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    provider.refuse = None
    # Someone pays for something: the balance grew, so delayed refunds are retried.
    other_event = _mk_event(client, uuid.uuid4().hex[:8], is_free=False)
    _paid_registered(client, other_event)
    _wait_for(lambda: _refund(rid)["status"] == "processed")
    after = _refund(rid)
    assert after["attempt_count"] == 2
    assert after["provider_refund_id"]
    # A fresh key per try: the provider remembers a refused key's answer.
    assert provider.refund_calls[-1]["idempotency_key"] == f"{row['idempotency_key']}:try2"
    assert client.get(f"/api/v1/registrations/{rid}/refund", headers=_bearer()).json()["status"] == "refund_processed"


def test_still_refused_stays_delayed(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    r = _retry_now(client, row["public_refund_number"])
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "delayed"
    after = _refund(rid)
    assert after["status"] == "delayed"
    assert after["attempt_count"] == 2


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


def test_a_retry_after_the_window_hands_it_to_a_person(client, provider):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    _db("UPDATE payment_refunds SET requested_at = now() - interval '8 days' WHERE registration_id = $1", rid)
    assert _retry_now(client, row["public_refund_number"]).json()["status"] == "failed"
    after = _refund(rid)
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

def test_delayed_then_sent_emails_go_out_once_each(client, provider, mails, background):
    rid, row, _ = _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    number = row["public_refund_number"]
    _wait_for(lambda: _refund(rid)["attendee_notified_delay_at"] is not None)

    # Still refused: no second "delayed" email.
    assert _retry_now(client, number).json()["status"] == "delayed"

    provider.refuse = None
    assert _retry_now(client, number).json()["status"] == "processed"
    _wait_for(lambda: _refund(rid)["attendee_notified_result_at"] is not None)
    time.sleep(0.3)  # anything extra would have arrived by now
    assert [m for m in mails if m[2] == number] == [
        ("delayed", _TEST_ALUMNI["email"], number),
        ("processed", _TEST_ALUMNI["email"], number),
    ]


def test_final_failure_tells_the_attendee_admins_and_finance(client, provider, mails, background, monkeypatch):
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "finance_alert_email", "finance.one@nitksaa.dev, finance.two@nitksaa.dev")

    rid, row, _ = _cancelled_with_refund(client, provider, refuse="payment_too_old")
    number = row["public_refund_number"]
    _wait_for(lambda: _refund(rid)["admins_notified_at"] is not None)

    # Retry now on it again (still refused): nobody is told twice.
    assert _retry_now(client, number).json()["status"] == "failed"
    time.sleep(0.3)

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
    assert item["attempt_count"] == 1 and item["last_attempt_at"]
    assert item["provider_payment_id"] == row["provider_payment_id"]
    assert "next_retry_at" not in item


def test_actions_count_delayed_refunds_as_information_only(client, provider):
    _cancelled_with_refund(client, provider, refuse="insufficient_balance")
    r = client.get("/api/v1/admin/pending-count", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["delayed_refunds"] >= 1
    badge = sum(body[k] for k in ("drafts", "failed_emails", "stuck_payments", "failed_refunds"))
    assert body["total"] == badge
