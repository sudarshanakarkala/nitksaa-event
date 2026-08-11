"""WP3 — webhook freshness / replay-age hardening tests.

Exercises the new issued_at field (app/gateways/deterministic_sandbox.py)
and the freshness gate in app/services/payment_service.process_webhook.
Reuses test_payments.py's established helper pattern (_mk_paid_event via
the dev-diagnostics import path, _TEST_ALUMNI seeded identity) since this
file is about webhook processing, not the WP1/WP2 admin surface.
"""
import json
import time
import uuid
from decimal import Decimal

import pytest

_TEST_ALUMNI = {
    "firebase_uid": "TEST_ALUMNI_UID_001",
    "sub": "ravi.test@nitksaa.dev",
    "email": "ravi.test@nitksaa.dev",
    "fullname": "Ravi Shankar Test",
    "user_type": "alumni",
    "ref_id": "NITK2020CS001",
    "graduation_year": 2020,
}

_ADMIN = {"X-Dev-User": "admin"}

# See test_payments.py's _FIXTURE_ADMIN docstring — same identity/UID,
# reused across files (same DB row). Needed because events.py's own admin
# routes were migrated off dev-auth in the admin-auth-unification sprint;
# admin_events.py's real-RBAC create/publish routes are the replacement.
_FIXTURE_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_043",
    "sub": "fixture.admin.rbac@nitksaa.dev",
    "email": "fixture.admin.rbac@nitksaa.dev",
    "fullname": "Fixture Admin RBAC Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS043",
    "graduation_year": 2018,
}


def _alumni_bearer_headers(identity: dict = _TEST_ALUMNI) -> dict:
    from app.middleware.auth import make_access_token

    token = make_access_token(dict(identity))
    return {"Authorization": f"Bearer {token}"}


def _db_exec(query: str, *args) -> None:
    import asyncio

    import asyncpg

    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            await conn.execute(query, *args)
        finally:
            await conn.close()

    asyncio.run(_run())


@pytest.fixture(autouse=True)
def _seed_fixture_admin():
    _db_exec(
        """
        INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (firebase_uid) DO NOTHING
        """,
        _FIXTURE_ADMIN["firebase_uid"], _FIXTURE_ADMIN["email"], _FIXTURE_ADMIN["fullname"],
        _FIXTURE_ADMIN["user_type"], _FIXTURE_ADMIN["ref_id"], _FIXTURE_ADMIN["graduation_year"],
    )
    _db_exec(
        """
        INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
        VALUES ($1, 'platform_admin', 'test_fixture_bootstrap')
        ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING
        """,
        _FIXTURE_ADMIN["firebase_uid"],
    )


def _mk_paid_event(client, uid_suffix: str, *, capacity: int = 10, base_amount: str = "100.00") -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST WP3 EVENT {uid_suffix}",
            "description": "Created by pytest (WP3 freshness)",
            "start_datetime": "2027-06-01T08:00:00+05:30",
            "end_datetime": "2027-06-01T10:00:00+05:30",
            "location_text": "Test Venue",
            "is_virtual": False,
            "capacity": capacity,
            "is_free": False,
            "ticket_price": base_amount,
        },
        headers=_alumni_bearer_headers(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    event_id = r.json()["event_id"]
    r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=_alumni_bearer_headers(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    r = client.post(
        "/api/v1/dev/diagnostics/payments/configuration/import",
        json={
            "configuration_key": f"wp3-test-{uid_suffix}",
            "event_id": event_id,
            "base_amount": base_amount,
            "gst_enabled": False,
            "convenience_fee_enabled": False,
            "seat_hold_minutes": 15,
            "payment_session_expiry_minutes": 15,
        },
        headers=_ADMIN,
    )
    assert r.status_code == 200, r.text
    return event_id


def _db_fetch(query: str, *args) -> list:
    import asyncio

    import asyncpg

    from app.config import get_settings

    async def _run():
        conn = await asyncpg.connect(dsn=get_settings().events_db_dsn)
        try:
            return await conn.fetch(query, *args)
        finally:
            await conn.close()

    return asyncio.run(_run())


def _mk_pending_attempt(client, headers: dict, uid_suffix: str):
    """Register + order + a PENDING attempt, so we have a live
    gateway_order_ref/amount/currency to build custom webhook deliveries
    against without an existing terminal state in the way."""
    event_id = _mk_paid_event(client, uid_suffix)
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"{uid_suffix}-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    attempt = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "PENDING"},
        headers=headers,
    ).json()
    row = _db_fetch(
        "SELECT gateway_order_ref, amount, currency FROM payment_attempts WHERE public_attempt_number = $1",
        attempt["attempt_id"],
    )[0]
    return order, attempt, row


def _custom_payload(
    gateway_order_ref: str,
    amount,
    currency: str,
    *,
    event_type: str = "payment.captured",
    issued_at=None,
    omit_issued_at: bool = False,
) -> dict:
    payload = {
        "event_id": str(uuid.uuid4()),
        "event_type": event_type,
        "gateway": "deterministic_sandbox",
        "gateway_order_ref": gateway_order_ref,
        "amount": str(amount),
        "currency": currency,
    }
    if event_type == "payment.captured":
        payload["gateway_payment_ref"] = f"sbx_pay_{uuid.uuid4().hex[:16]}"
    if not omit_issued_at:
        payload["issued_at"] = int(time.time()) if issued_at is None else issued_at
    return payload


def _sign(payload: dict) -> tuple:
    from app.gateways.deterministic_sandbox import canonicalize, sign
    from app.config import get_settings

    raw_body = canonicalize(payload)
    signature = sign(raw_body, get_settings().payment_sandbox_signing_secret)
    return raw_body, signature


def _deliver(client, raw_body: bytes, signature: str):
    return client.post(
        "/api/v1/payment-gateways/deterministic_sandbox/webhook",
        content=raw_body,
        headers={"X-Sandbox-Signature": signature},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Freshness gate
# ─────────────────────────────────────────────────────────────────────────────

def test_current_timestamp_accepted(client):
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"fresh-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(row["gateway_order_ref"], row["amount"], row["currency"])
    raw_body, sig = _sign(payload)
    r = _deliver(client, raw_body, sig)
    assert r.json()["processing_status"] == "processed"
    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["status"] == "paid"


def test_just_inside_max_age_accepted(client):
    from app.config import get_settings

    max_age = get_settings().payment_webhook_max_age_seconds
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"insideage-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(
        row["gateway_order_ref"], row["amount"], row["currency"],
        issued_at=int(time.time()) - (max_age - 5),
    )
    raw_body, sig = _sign(payload)
    r = _deliver(client, raw_body, sig)
    assert r.json()["processing_status"] == "processed"


def test_stale_timestamp_rejected(client):
    from app.config import get_settings

    max_age = get_settings().payment_webhook_max_age_seconds
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"stale-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(
        row["gateway_order_ref"], row["amount"], row["currency"],
        issued_at=int(time.time()) - (max_age + 60),
    )
    raw_body, sig = _sign(payload)
    r = _deliver(client, raw_body, sig)
    assert r.json()["processing_status"] == "rejected"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] == "0.00"
    assert order_after["status"] != "paid"
    assert order_after["registration_status"] != "registered"

    webhook_rows = _db_fetch(
        "SELECT error_code FROM payment_webhook_events WHERE gateway_event_id = $1", payload["event_id"]
    )
    assert webhook_rows[0]["error_code"] == "timestamp_stale"


def test_far_future_timestamp_rejected(client):
    from app.config import get_settings

    skew = get_settings().payment_webhook_max_future_skew_seconds
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"future-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(
        row["gateway_order_ref"], row["amount"], row["currency"],
        issued_at=int(time.time()) + skew + 3600,
    )
    raw_body, sig = _sign(payload)
    r = _deliver(client, raw_body, sig)
    assert r.json()["processing_status"] == "rejected"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] == "0.00"

    webhook_rows = _db_fetch(
        "SELECT error_code FROM payment_webhook_events WHERE gateway_event_id = $1", payload["event_id"]
    )
    assert webhook_rows[0]["error_code"] == "timestamp_future_skew"


def test_malformed_timestamp_rejected(client):
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"malformed-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(row["gateway_order_ref"], row["amount"], row["currency"])
    payload["issued_at"] = "not-a-timestamp"
    raw_body, sig = _sign(payload)
    r = _deliver(client, raw_body, sig)
    assert r.json()["processing_status"] == "rejected"

    webhook_rows = _db_fetch(
        "SELECT error_code FROM payment_webhook_events WHERE gateway_event_id = $1", payload["event_id"]
    )
    assert webhook_rows[0]["error_code"] == "timestamp_malformed"


def test_missing_timestamp_rejected(client):
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"missing-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(
        row["gateway_order_ref"], row["amount"], row["currency"], omit_issued_at=True
    )
    raw_body, sig = _sign(payload)
    r = _deliver(client, raw_body, sig)
    assert r.json()["processing_status"] == "rejected"

    webhook_rows = _db_fetch(
        "SELECT error_code FROM payment_webhook_events WHERE gateway_event_id = $1", payload["event_id"]
    )
    assert webhook_rows[0]["error_code"] == "timestamp_missing"


def test_timestamp_changed_after_signing_rejected_via_signature(client):
    """issued_at is part of the signed body — mutating it post-signing
    invalidates the signature, so this is rejected as invalid_signature
    (proving the timestamp is actually covered by the HMAC), not as a
    timestamp error."""
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"tampertime-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(row["gateway_order_ref"], row["amount"], row["currency"])
    raw_body, sig = _sign(payload)

    tampered_payload = dict(payload)
    tampered_payload["issued_at"] = payload["issued_at"] + 1
    from app.gateways.deterministic_sandbox import canonicalize

    tampered_body = canonicalize(tampered_payload)

    r = _deliver(client, tampered_body, sig)  # original signature, tampered body
    assert r.json()["processing_status"] == "rejected"

    webhook_rows = _db_fetch(
        "SELECT error_code FROM payment_webhook_events WHERE gateway_event_id = $1", payload["event_id"]
    )
    assert webhook_rows[0]["error_code"] == "invalid_signature"


def test_invalid_signature_still_rejected(client):
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"badsig-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(row["gateway_order_ref"], row["amount"], row["currency"])
    raw_body, _ = _sign(payload)
    r = _deliver(client, raw_body, "0" * 64)
    assert r.json()["processing_status"] == "rejected"


def test_fresh_duplicate_delivery_is_idempotent(client):
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"dup-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(row["gateway_order_ref"], row["amount"], row["currency"])
    raw_body, sig = _sign(payload)

    r1 = _deliver(client, raw_body, sig)
    assert r1.json()["processing_status"] == "processed"
    r2 = _deliver(client, raw_body, sig)
    assert r2.json()["processing_status"] == "duplicate"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] == "100.00"


def test_old_duplicate_replay_causes_zero_additional_mutation(client):
    """A replay of an already-recorded event_id is classified 'duplicate'
    by the dedup check regardless of how stale it now is relative to
    'now' — the actual security property (no additional financial
    mutation) holds either way; see payment_service.process_webhook's
    docstring-level note on this ordering."""
    headers = _alumni_bearer_headers()
    order, attempt, row = _mk_pending_attempt(client, headers, f"olddup-{uuid.uuid4().hex[:8]}")
    payload = _custom_payload(row["gateway_order_ref"], row["amount"], row["currency"])
    raw_body, sig = _sign(payload)

    r1 = _deliver(client, raw_body, sig)
    assert r1.json()["processing_status"] == "processed"
    amount_after_first = client.get(
        f"/api/v1/payment-orders/{order['order_id']}", headers=headers
    ).json()["amount_paid"]

    # Replay the exact same (now effectively "old") bytes+signature again.
    r2 = _deliver(client, raw_body, sig)
    assert r2.json()["processing_status"] == "duplicate"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] == amount_after_first == "100.00"
