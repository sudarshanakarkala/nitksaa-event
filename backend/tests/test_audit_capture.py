"""Admin revamp step 10a: payment lifecycle capture.

- How a payment was made / why it failed is stored on the attempt and in its
  audit entry, with no personal data from the provider.
- Razorpay refund webhooks (refund.created / processed / failed) update the
  refund, record the bank reference (ARN), never move a refund backwards,
  and go through the same gates as payment webhooks.
- Event edits and status changes say what changed.

Uses the Razorpay fakes and helpers of test_razorpay_checkout_and_webhook.
"""
import json
import time
import uuid

from tests import _razorpay_fakes as fakes
from tests.test_razorpay_checkout_and_webhook import (  # noqa: F401  (autouse fixture)
    _FIXTURE_ADMIN,
    _bearer,
    _db_fetchrow,
    _db_fetchval,
    _paid_setup,
    _post,
    _seed_and_fakes,
    _signed,
)

PERSONAL = ("payer@example.com", "9876543210", "payer@okhdfc")


def _payment_body(event, *, order_ref, payment_id, status, **extra):
    entity = {
        "id": payment_id, "order_id": order_ref, "amount": 100, "currency": "INR",
        "status": status,
        # Personal data Razorpay sends that we must not keep:
        "email": PERSONAL[0], "contact": PERSONAL[1], "vpa": PERSONAL[2],
        **extra,
    }
    return {"entity": "event", "event": event, "contains": ["payment"],
            "payload": {"payment": {"entity": entity}}, "created_at": int(time.time())}


def _refund_body(event, *, refund_id, payment_id, amount=100, **extra):
    entity = {"id": refund_id, "payment_id": payment_id, "amount": amount, "currency": "INR", **extra}
    return {"entity": "event", "event": event, "contains": ["refund", "payment"],
            "payload": {"refund": {"entity": entity},
                        "payment": {"entity": {"id": payment_id, "amount": amount, "currency": "INR"}}},
            "created_at": int(time.time())}


def _send(client, body, event_id=None):
    raw, sig = _signed(body)
    return _post(client, raw, signature=sig, event_id=event_id or f"evt_{uuid.uuid4().hex}")


def _attempt(attempt):
    return _db_fetchrow("SELECT * FROM payment_attempts WHERE public_attempt_number = $1", attempt["attempt_id"])


def _last_audit(event_type, entity_type, entity_id):
    row = _db_fetchrow(
        "SELECT context FROM event_audit_log WHERE event_type = $1 AND entity_type = $2 AND entity_id = $3 "
        "ORDER BY log_id DESC LIMIT 1", event_type, entity_type, entity_id)
    return json.loads(row["context"]) if row and row["context"] else None


def _captured(client):
    """A paid, registered attendee with a captured Razorpay payment."""
    reg, order, attempt, order_ref = _paid_setup(client)
    payment_id = f"pay_{uuid.uuid4().hex[:14]}"
    r = _send(client, _payment_body(
        "payment.captured", order_ref=order_ref, payment_id=payment_id, status="captured",
        method="upi", bank="HDFC", international=False, fee=236, tax=36,
        acquirer_data={"rrn": "429112345678"}))
    assert r.status_code == 200 and r.json()["processing_status"] == "processed", r.text
    return reg, order, attempt, payment_id


# ── Payment details ──────────────────────────────────────────────────────

def test_capture_stores_how_it_was_paid_without_personal_data(client):
    reg, order, attempt, payment_id = _captured(client)
    row = _attempt(attempt)
    assert row["status"] == "captured"
    assert row["payment_method"] == "upi"
    assert row["payment_instrument"] == "HDFC"
    assert row["is_international"] is False
    assert str(row["provider_fee"]) == "2.36" and str(row["provider_tax"]) == "0.36"
    assert row["bank_reference"] == "429112345678"

    ctx = _last_audit("payment_captured", "payment_attempt", row["id"])
    assert ctx["method"] == "upi" and ctx["instrument"] == "HDFC"
    assert ctx["provider"] == "razorpay" and ctx["provider_event"] == "payment.captured"
    assert ctx["provider_payment_id"] == payment_id
    assert ctx["fee"] == "2.36"
    for value in PERSONAL:
        assert value not in json.dumps(ctx)


def test_failure_stores_why_it_failed(client):
    reg, order, attempt, order_ref = _paid_setup(client)
    r = _send(client, _payment_body(
        "payment.failed", order_ref=order_ref, payment_id=f"pay_{uuid.uuid4().hex[:14]}", status="failed",
        method="card", error_code="BAD_REQUEST_ERROR", error_description="Wrong OTP",
        error_source="customer", error_step="payment_authentication", error_reason="incorrect_otp"))
    assert r.status_code == 200, r.text
    row = _attempt(attempt)
    assert row["status"] == "failed"
    assert (row["failure_source"], row["failure_step"], row["failure_reason"]) == (
        "customer", "payment_authentication", "incorrect_otp")
    ctx = _last_audit("payment_failed", "payment_attempt", row["id"])
    assert ctx["failure"] == {"source": "customer", "step": "payment_authentication", "reason": "incorrect_otp"}
    assert ctx["failure_code"] == "BAD_REQUEST_ERROR"
    for value in PERSONAL:
        assert value not in json.dumps(ctx)


def test_attendee_timeline_hides_provider_ids_and_fees(client):
    reg, order, attempt, payment_id = _captured(client)
    r = client.get(f"/api/v1/payment-orders/{order['order_id']}/timeline", headers=_bearer())
    assert r.status_code == 200, r.text
    assert payment_id not in r.text
    assert '"fee"' not in r.text and '"provider"' not in r.text


# ── Refund webhooks ──────────────────────────────────────────────────────

def _cancelled_with_pending_refund(client):
    reg, order, attempt, payment_id = _captured(client)
    fakes.STATE["refund_status"] = "pending"
    r = client.post(f"/api/v1/registrations/{reg['registration_id']}/cancel",
                    json={"idempotency_key": f"cx-{uuid.uuid4().hex}"}, headers=_bearer())
    assert r.status_code == 200, r.text
    refund = _db_fetchrow("SELECT * FROM payment_refunds WHERE registration_id = $1", reg["registration_id"])
    assert refund["status"] == "processing" and refund["provider_refund_id"]
    return reg, refund, payment_id


def _refund(refund_id):
    return _db_fetchrow("SELECT * FROM payment_refunds WHERE id = $1", refund_id)


def test_refund_processed_webhook_records_arn_and_finishes_refund(client):
    reg, refund, payment_id = _cancelled_with_pending_refund(client)
    r = _send(client, _refund_body(
        "refund.processed", refund_id=refund["provider_refund_id"], payment_id=payment_id,
        status="processed", speed_processed="normal", acquirer_data={"arn": "74512345678901234567890"}))
    assert r.status_code == 200 and r.json()["processing_status"] == "processed", r.text
    row = _refund(refund["id"])
    assert row["status"] == "processed"
    assert row["bank_reference"] == "74512345678901234567890"
    assert row["speed_processed"] == "normal"
    assert row["finalized_at"] is not None
    ctx = _last_audit("payment_refund_processed", "payment_refund", refund["id"])
    assert ctx["bank_reference"] == "74512345678901234567890"
    assert ctx["source"] == "webhook" and ctx["provider_event"] == "refund.processed"

    # Attendee sees it as processed.
    r = client.get(f"/api/v1/registrations/{reg['registration_id']}/refund", headers=_bearer())
    assert r.json()["status"] == "refund_processed"


def test_refund_never_moves_backwards(client):
    reg, refund, payment_id = _cancelled_with_pending_refund(client)
    assert _send(client, _refund_body("refund.processed", refund_id=refund["provider_refund_id"],
                                      payment_id=payment_id, status="processed")).status_code == 200
    # A late refund.created (pending) delivered after processed.
    r = _send(client, _refund_body("refund.created", refund_id=refund["provider_refund_id"],
                                   payment_id=payment_id, status="pending"))
    assert r.status_code == 200, r.text
    assert _refund(refund["id"])["status"] == "processed"


def test_refund_failed_webhook_marks_failed_with_reason(client):
    reg, refund, payment_id = _cancelled_with_pending_refund(client)
    r = _send(client, _refund_body("refund.failed", refund_id=refund["provider_refund_id"],
                                   payment_id=payment_id, status="failed"))
    assert r.status_code == 200, r.text
    row = _refund(refund["id"])
    assert row["status"] == "failed" and row["failure_reason"]
    assert _last_audit("payment_refund_failed", "payment_refund", refund["id"])["status"] == "failed"


def test_duplicate_refund_webhook_is_a_no_op(client):
    reg, refund, payment_id = _cancelled_with_pending_refund(client)
    body = _refund_body("refund.processed", refund_id=refund["provider_refund_id"],
                        payment_id=payment_id, status="processed")
    event_id = f"evt_{uuid.uuid4().hex}"
    assert _send(client, body, event_id).json()["processing_status"] == "processed"
    assert _send(client, body, event_id).json()["processing_status"] == "duplicate"


def test_refund_webhook_before_we_stored_the_refund_id_still_matches(client):
    reg, refund, payment_id = _cancelled_with_pending_refund(client)
    provider_refund_id = refund["provider_refund_id"]
    # As if the webhook raced ahead of our refund call returning.
    _db_fetchval("UPDATE payment_refunds SET provider_refund_id = NULL WHERE id = $1 RETURNING id", refund["id"])
    r = _send(client, _refund_body("refund.processed", refund_id=provider_refund_id,
                                   payment_id=payment_id, status="processed"))
    assert r.status_code == 200 and r.json()["processing_status"] == "processed", r.text
    row = _refund(refund["id"])
    assert row["status"] == "processed" and row["provider_refund_id"] == provider_refund_id


def test_unknown_refund_is_rejected_safely(client):
    r = _send(client, _refund_body("refund.processed", refund_id=f"rfnd_{uuid.uuid4().hex[:12]}",
                                   payment_id=f"pay_{uuid.uuid4().hex[:12]}", status="processed"))
    assert r.status_code == 200 and r.json()["processing_status"] == "rejected"


def test_refund_webhook_with_wrong_amount_is_rejected(client):
    reg, refund, payment_id = _cancelled_with_pending_refund(client)
    r = _send(client, _refund_body("refund.processed", refund_id=refund["provider_refund_id"],
                                   payment_id=payment_id, status="processed", amount=999))
    assert r.json()["processing_status"] == "rejected"
    assert _refund(refund["id"])["status"] == "processing"


def test_refund_webhook_with_bad_signature_changes_nothing(client):
    reg, refund, payment_id = _cancelled_with_pending_refund(client)
    raw, _ = _signed(_refund_body("refund.processed", refund_id=refund["provider_refund_id"],
                                  payment_id=payment_id, status="processed"))
    r = _post(client, raw, signature="deadbeef", event_id=f"evt_{uuid.uuid4().hex}")
    assert r.status_code == 400
    assert _refund(refund["id"])["status"] == "processing"


# ── Event changes say what changed ───────────────────────────────────────

def _admin_event(client, **extra):
    r = client.post("/api/v1/admin/events", json={
        "title": f"AUDIT CTX {uuid.uuid4().hex[:8]}", "description": "pytest",
        "start_datetime": "2027-05-01T08:00:00+05:30", "end_datetime": "2027-05-01T10:00:00+05:30",
        "location_text": "Venue", "is_virtual": False, "capacity": 20, **extra,
    }, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 201, r.text
    return r.json()["event_id"]


def _event_audit(event_type, event_id):
    return _last_audit(event_type, "event", event_id)


def test_event_created_and_status_changes_carry_details(client):
    event_id = _admin_event(client)
    assert _event_audit("event_created", event_id)["status"] == "draft"
    assert client.post(f"/api/v1/admin/events/{event_id}/publish",
                       headers=_bearer(_FIXTURE_ADMIN)).status_code == 200
    assert _event_audit("event_published", event_id) == {"event_id": event_id, "from": "draft", "to": "published"}


def test_event_edit_lists_fields_price_and_registration_closing(client):
    event_id = _admin_event(client, is_free=False, ticket_price="500")
    r = client.patch(f"/api/v1/admin/events/{event_id}", json={
        "ticket_price": "750", "location_text": "New venue",
        "registration_closes_at": "2020-01-01T00:00:00+05:30",
    }, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    ctx = _event_audit("event_updated", event_id)
    assert ctx["fields"] == ["location_text", "registration_closes_at", "ticket_price"]
    assert ctx["price"] == {"from": "500.00", "to": "750.00"}
    assert ctx["registration"] == "closed"
    assert "New venue" not in json.dumps(ctx)  # field names only, not values


def test_close_registration_counts_as_closed_when_the_admins_clock_runs_ahead(client):
    """The app's "Close registration" sends the admin's own clock; a PC a
    little ahead of the server must still be recorded as "closed"."""
    from datetime import datetime, timedelta, timezone
    event_id = _admin_event(client)
    ahead = (datetime.now(timezone.utc) + timedelta(seconds=5)).isoformat()
    r = client.patch(f"/api/v1/admin/events/{event_id}", json={"registration_closes_at": ahead},
                     headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    assert _event_audit("event_updated", event_id)["registration"] == "closed"
    # Saved with the server's clock (not 5 s ahead), so it is closed already.
    saved = datetime.fromisoformat(r.json()["registration_closes_at"])
    assert saved <= datetime.now(timezone.utc)


def test_a_closing_date_further_ahead_is_not_a_close(client):
    from datetime import datetime, timedelta, timezone
    event_id = _admin_event(client)
    later = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    r = client.patch(f"/api/v1/admin/events/{event_id}", json={"registration_closes_at": later},
                     headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    ctx = _event_audit("event_updated", event_id)
    assert ctx["fields"] == ["registration_closes_at"]
    assert "registration" not in ctx


def test_retry_after_failure_in_same_checkout_clears_the_failure(client):
    """The person's first try fails, they retry in the same Razorpay window
    and it succeeds (one attempt row, two Razorpay payments)."""
    reg, order, attempt, order_ref = _paid_setup(client)
    assert _send(client, _payment_body(
        "payment.failed", order_ref=order_ref, payment_id=f"pay_{uuid.uuid4().hex[:14]}", status="failed",
        method="card", error_code="BAD_REQUEST_ERROR", error_description="Card not allowed",
        error_source="customer", error_step="payment_authorization",
        error_reason="international_transaction_not_allowed")).status_code == 200
    payment_id = f"pay_{uuid.uuid4().hex[:14]}"
    assert _send(client, _payment_body(
        "payment.captured", order_ref=order_ref, payment_id=payment_id, status="captured",
        method="card", fee=200, tax=0)).json()["processing_status"] == "processed"

    row = _attempt(attempt)
    assert row["status"] == "captured" and row["gateway_payment_ref"] == payment_id
    assert row["failure_code"] is None and row["gateway_failure_message"] is None
    assert row["failure_source"] is None and row["failure_step"] is None and row["failure_reason"] is None
    assert str(row["provider_fee"]) == "2.00"
    # The failed try is still in the history.
    failed = _last_audit("payment_failed", "payment_attempt", row["id"])
    assert failed["failure"]["reason"] == "international_transaction_not_allowed"
    assert _db_fetchval("SELECT status FROM registrations WHERE registration_id = $1",
                        reg["registration_id"]) == "registered"
