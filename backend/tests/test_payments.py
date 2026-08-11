"""Payment Phase 0 test suite — deterministic sandbox gateway.

Two layers:
 - Pure unit tests of pricing_service.calculate_price (no DB, no auth).
 - One end-to-end integration check that drives the whole sandbox flow
   (paid event + config setup, pricing, seat-hold registration, order
   creation + idempotency, failed payment, retry success, duplicate-webhook
   idempotency, cross-user access denial) via the dev payments diagnostics
   endpoint (/api/v1/dev/diagnostics/payments), which exercises the real
   services end to end rather than re-implementing the flow in the test.

Auth note: app/api/payments.py endpoints use the production Firebase-token
auth dependency (app.middleware.auth.get_current_user), not the
X-Dev-User dev_auth shortcut used elsewhere in this test suite. A valid
internal access token is minted directly via make_access_token() (the same
helper POST /api/v1/auth/firebase uses after verifying a real Firebase
token) for one of the seeded alumni_db/event_users test identities, so
these tests don't need a real Firebase ID token.
"""
from decimal import Decimal

import pytest

# Seeded in both alumni_db (alumni.alumni_id) and events_db (event_users) —
# see backend/migrations and dev seed data. Active alumni, safe to register
# repeatedly across test runs (uid() suffixes keep events unique).
_TEST_ALUMNI = {
    "firebase_uid": "TEST_ALUMNI_UID_001",
    "sub": "ravi.test@nitksaa.dev",
    "email": "ravi.test@nitksaa.dev",
    "fullname": "Ravi Shankar Test",
    "user_type": "alumni",
    "ref_id": "NITK2020CS001",
    "graduation_year": 2020,
}

_TEST_ALUMNI_2 = {
    "firebase_uid": "TEST_ALUMNI_UID_002",
    "sub": "priya.test@nitksaa.dev",
    "email": "priya.test@nitksaa.dev",
    "fullname": "Priya Kumari Test",
    "user_type": "alumni",
    "ref_id": "NITK2019EC002",
    "graduation_year": 2019,
}

_ADMIN = {"X-Dev-User": "admin"}

# Dedicated fixture-only identity, permanently granted platform_admin via a
# direct DB row (see _seed_fixture_admin below) — used ONLY to create the
# throwaway events these tests exercise, via admin_events.py's real-RBAC
# create/publish routes. events.py's own admin routes (POST /api/v1/events,
# PATCH /api/v1/events/{id}/status) were migrated off dev-auth in the
# admin-auth-unification sprint, so the previous X-Dev-User-based fixture
# setup here no longer works; admin_events.py's equivalent routes (already
# fully functional per the admin-event-schema-alignment sprint) are the
# real-RBAC replacement. Same identity/UID as test_admin_rbac.py's
# _FIXTURE_ADMIN — same row, reused across files, not a new concept.
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
    """Create + publish a throwaway paid event with a published payment config.
    Returns the event_id. Uses the same live services a real admin call would
    (not a direct DB write) — see app/api/admin_events.py + dev_diagnostics.py."""
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST PAID EVENT {uid_suffix}",
            "description": "Created by pytest",
            "start_datetime": "2027-03-01T08:00:00+05:30",
            "end_datetime": "2027-03-01T10:00:00+05:30",
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
            "configuration_key": f"test-{uid_suffix}",
            "event_id": event_id,
            "base_amount": base_amount,
            "gst_enabled": True,
            "gst_rate": "18.00",
            "gst_mode": "exclusive",
            "convenience_fee_enabled": False,
            "seat_hold_minutes": 15,
            "payment_session_expiry_minutes": 15,
        },
        headers=_ADMIN,
    )
    assert r.status_code == 200, r.text
    return event_id


def _db_fetch(query: str, *args) -> list:
    """Direct DB read for assertions the API doesn't expose (e.g. payment_exceptions
    rows) or setup the API deliberately has no endpoint for (backdating timestamps —
    a real client must never be able to do this; only test setup should)."""
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


def _force_hold_expired(registration_id: int) -> None:
    _db_exec(
        "UPDATE registrations SET hold_expires_at = now() - interval '1 minute' WHERE registration_id = $1",
        registration_id,
    )


def _force_attempt_stale(attempt_id: int, minutes_ago: int) -> None:
    _db_exec(
        "UPDATE payment_attempts SET initiated_at = now() - make_interval(mins => $2) WHERE id = $1",
        attempt_id,
        minutes_ago,
    )


# ─────────────────────────────────────────────────────────────────────────────
# A. Pricing unit tests — no DB, no auth
# ─────────────────────────────────────────────────────────────────────────────

def _base_config(**overrides) -> dict:
    config = {
        "currency": "INR",
        "base_amount": Decimal("100.00"),
        "gst_enabled": False,
        "gst_rate": Decimal("0"),
        "gst_mode": "exclusive",
        "convenience_fee_enabled": False,
        "convenience_fee_type": "fixed",
        "convenience_fee_value": Decimal("0"),
    }
    config.update(overrides)
    return config


def test_pricing_gst_disabled():
    from app.services.pricing_service import calculate_price

    result = calculate_price(_base_config())
    assert result["tax_amount"] == Decimal("0.00")
    assert result["final_amount"] == Decimal("100.00")


def test_pricing_gst_exclusive():
    from app.services.pricing_service import calculate_price

    result = calculate_price(
        _base_config(gst_enabled=True, gst_rate=Decimal("18.00"), gst_mode="exclusive")
    )
    assert result["tax_amount"] == Decimal("18.00")
    assert result["final_amount"] == Decimal("118.00")


def test_pricing_gst_inclusive():
    from app.services.pricing_service import calculate_price

    result = calculate_price(
        _base_config(gst_enabled=True, gst_rate=Decimal("18.00"), gst_mode="inclusive")
    )
    # ₹100 inclusive of 18% GST → taxable value ₹84.75, tax ₹15.25, final unchanged at ₹100
    assert result["taxable_amount"] == Decimal("84.75")
    assert result["tax_amount"] == Decimal("15.25")
    assert result["final_amount"] == Decimal("100.00")


def test_pricing_convenience_fee_fixed():
    from app.services.pricing_service import calculate_price

    result = calculate_price(
        _base_config(convenience_fee_enabled=True, convenience_fee_type="fixed", convenience_fee_value=Decimal("10.00"))
    )
    assert result["convenience_fee"] == Decimal("10.00")
    assert result["final_amount"] == Decimal("110.00")


def test_pricing_convenience_fee_percentage():
    from app.services.pricing_service import calculate_price

    result = calculate_price(
        _base_config(
            gst_enabled=True, gst_rate=Decimal("18.00"), gst_mode="exclusive",
            convenience_fee_enabled=True, convenience_fee_type="percentage", convenience_fee_value=Decimal("2.00"),
        )
    )
    # payable before fee = 118.00; fee = 2% of 118.00 = 2.36
    assert result["convenience_fee"] == Decimal("2.36")
    assert result["final_amount"] == Decimal("120.36")


def test_pricing_rejects_negative_base_amount():
    from app.services.pricing_service import calculate_price

    with pytest.raises(ValueError):
        calculate_price(_base_config(base_amount=Decimal("-1.00")))


# ─────────────────────────────────────────────────────────────────────────────
# B. API-level access control — no paid event needed
# ─────────────────────────────────────────────────────────────────────────────

def test_payment_endpoints_require_authentication(client):
    # HTTPBearer with no Authorization header returns 403 in this FastAPI
    # version (same behavior as the existing /register endpoint's auth guard).
    r = client.get("/api/v1/events/1/payment-pricing")
    assert r.status_code == 403

    r = client.post("/api/v1/registrations/1/payment-order", json={"idempotency_key": "x" * 10})
    assert r.status_code == 403

    r = client.get("/api/v1/payment-orders/ORD-doesnotexist")
    assert r.status_code == 403


def test_pricing_for_unconfigured_event_returns_409(client):
    headers = _alumni_bearer_headers()
    # event_id 999999999 has no payment_configurations row (and likely no event row).
    r = client.get("/api/v1/events/999999999/payment-pricing", headers=headers)
    assert r.status_code == 409
    assert r.json()["detail"] == "payment_not_configured"


def test_webhook_endpoint_rejects_unknown_gateway(client):
    r = client.post("/api/v1/payment-gateways/some_other_gateway/webhook", content=b"{}")
    assert r.status_code == 404


def test_webhook_endpoint_rejects_invalid_signature(client):
    import uuid

    payload = (
        b'{"event_id":"%b","event_type":"payment.captured","gateway_order_ref":"sbx_ord_doesnotexist"}'
        % uuid.uuid4().hex.encode()
    )
    r = client.post(
        "/api/v1/payment-gateways/deterministic_sandbox/webhook",
        content=payload,
        headers={"X-Sandbox-Signature": "not-a-real-signature"},
    )
    assert r.status_code == 200  # webhook acks even on rejection — never 4xx to the gateway
    body = r.json()
    assert body["processing_status"] == "rejected"


# ─────────────────────────────────────────────────────────────────────────────
# D. Concurrency — duplicate-registration self-deadlock regression guard
#
# register_for_event holds SELECT ... FOR UPDATE on the events row inside a
# transaction. The pre-fix code awaited analytics_service.log_event_activity()
# — which needs a lock on that same row for its FK check — from a second
# pooled connection while still inside that transaction. Since the first
# connection wasn't blocked on a DB lock (it was blocked on the Python await),
# Postgres's deadlock detector never fired: the request hung forever, not just
# until a lock-wait timeout. These tests fail by hanging (past the bound) if
# the fix regresses, not by a clean assertion — that IS the point: a bounded
# wall-clock check is the only way to prove "does not hang" rather than
# "eventually raises the right exception".
# ─────────────────────────────────────────────────────────────────────────────

def test_duplicate_registration_returns_promptly_no_hang(client):
    import time
    import uuid
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

    event_id = _mk_paid_event(client, f"dup-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()

    r1 = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    assert r1.status_code == 201, r1.text
    assert r1.json()["status"] == "seat_held"

    def _second_register():
        return client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)

    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(_second_register)
        start = time.monotonic()
        try:
            r2 = future.result(timeout=10)
        except FutureTimeoutError:
            pytest.fail(
                "Duplicate registration did not return within 10s — the "
                "self-deadlock regressed (analytics call awaited while "
                "holding FOR UPDATE on the events row)."
            )
        elapsed = time.monotonic() - start

    assert r2.status_code == 409
    assert r2.json()["detail"] == "already_registered"
    assert elapsed < 5, f"duplicate registration took {elapsed:.2f}s — should be near-instant"


def test_concurrent_double_click_registration_only_one_succeeds(client):
    """True concurrency: two threads race to register the same user for the
    same event at (as close as possible to) the same instant. Exactly one
    must win with 201; the other must lose cleanly with 409 — never both
    succeeding, never a hang."""
    import time
    import uuid
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

    event_id = _mk_paid_event(client, f"dblclick-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers(_TEST_ALUMNI_2)

    def _register():
        return client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)

    with ThreadPoolExecutor(max_workers=2) as pool:
        f1 = pool.submit(_register)
        f2 = pool.submit(_register)
        try:
            r1 = f1.result(timeout=10)
            r2 = f2.result(timeout=10)
        except FutureTimeoutError:
            pytest.fail("Concurrent double-click registration hung past 10s.")

    statuses = sorted([r1.status_code, r2.status_code])
    assert statuses == [201, 409], f"expected exactly one 201 and one 409, got {statuses}"


# ─────────────────────────────────────────────────────────────────────────────
# C. Full sandbox flow via the dev payments diagnostics endpoint
# ─────────────────────────────────────────────────────────────────────────────

def test_payment_diagnostics_full_flow(client):
    """Runs the real success/failure/retry/idempotency/access-control scenarios
    end to end against the live services (see app/api/dev_diagnostics.py:
    run_payment_diagnostics). Every individual scenario must PASS."""
    headers = _alumni_bearer_headers()
    r = client.get("/api/v1/dev/diagnostics/payments", headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()

    failed = [res for res in body["results"] if res["status"] == "FAIL"]
    assert not failed, f"payment diagnostics had failures: {failed}"
    assert body["passed"] == body["total"]
    assert body["total"] >= 6  # setup + pricing + seat-hold + order + failed + retry + duplicate + cross-user


def test_latest_order_id_tracks_registration_through_payment_lifecycle(client):
    """RegistrationResponse.latest_order_id (returning-attendee sprint
    addition): a registration with no order yet reports None; once an
    order exists it's reported even after the registration moves past the
    payable window (registered/paid) — this is the whole point of the
    field, since POST /payment-order's create-or-reuse behavior stops
    applying once status leaves seat_held/payment_pending/payment_failed."""
    import uuid

    event_id = _mk_paid_event(client, f"latestorder-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()

    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    assert r.status_code == 201, r.text
    reg = r.json()
    assert reg["status"] == "seat_held"
    assert reg["latest_order_id"] is None

    r = client.get(f"/api/v1/events/{event_id}/my-registration", headers=headers)
    assert r.json()["latest_order_id"] is None

    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"latestorder-key-{reg['registration_id']}"},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    order_id = r.json()["order_id"]

    r = client.post(
        f"/api/v1/payment-orders/{order_id}/attempts",
        json={"scenario": "SUCCESS"},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "captured"

    r = client.get(f"/api/v1/events/{event_id}/my-registration", headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "registered"
    assert body["latest_order_id"] == order_id

    r = client.get("/api/v1/my/registrations", headers=headers)
    assert r.status_code == 200, r.text
    mine = next(x for x in r.json()["registrations"] if x["registration_id"] == reg["registration_id"])
    assert mine["latest_order_id"] == order_id

    # And the order it points to is reachable + correctly owned.
    r = client.get(f"/api/v1/payment-orders/{order_id}", headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "paid"


# ─────────────────────────────────────────────────────────────────────────────
# E. Seat-hold expiry, PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY, verification workflow
# ─────────────────────────────────────────────────────────────────────────────

def test_seat_hold_expiry_blocks_new_order(client):
    import uuid

    event_id = _mk_paid_event(client, f"expiry-order-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    assert reg["status"] == "seat_held"

    _force_hold_expired(reg["registration_id"])

    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"expiry-order-key-{reg['registration_id']}"},
        headers=headers,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "seat_hold_expired"

    rows = _db_fetch("SELECT status FROM registrations WHERE registration_id = $1", reg["registration_id"])
    assert rows[0]["status"] == "cancelled"


def test_seat_hold_expiry_blocks_new_attempt(client):
    import uuid

    event_id = _mk_paid_event(client, f"expiry-attempt-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"expiry-attempt-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()
    assert r.status_code == 201

    _force_hold_expired(reg["registration_id"])

    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "SUCCESS"},
        headers=headers,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "seat_hold_expired"


def test_payment_captured_after_seat_expiry_creates_exception(client):
    """A payment that was already in flight with the gateway before the seat
    expired must not be discarded (financial state preserved as 'paid') and
    must not silently reconfirm/overbook the expired seat — instead it opens
    a PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY exception.

    Setup (attempt row insert, forcing the hold into the past) goes through
    a standalone one-shot DB connection, same as _force_hold_expired — never
    the app's shared pool from a foreign event loop. Delivery goes through
    the real HTTP webhook endpoint so it runs on the app's actual loop, same
    as every other webhook test in this file."""
    import uuid

    from app.config import get_settings
    from app.gateways import deterministic_sandbox as sandbox

    event_id = _mk_paid_event(client, f"captured-after-expiry-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"captured-after-expiry-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()

    order_row = _db_fetch(
        "SELECT id, final_amount, currency FROM payment_orders WHERE public_order_number = $1",
        order["order_id"],
    )[0]
    gw_ref = sandbox.create_gateway_order_ref()
    next_num = _db_fetch(
        "SELECT COALESCE(MAX(attempt_number), 0) + 1 AS n FROM payment_attempts WHERE order_id = $1",
        order_row["id"],
    )[0]["n"]
    _db_exec(
        """
        INSERT INTO payment_attempts (
            public_attempt_number, order_id, attempt_number, gateway, scenario,
            amount, currency, gateway_order_ref, status
        ) VALUES ($1, $2, $3, $4, 'SUCCESS', $5, $6, $7, 'initiated')
        """,
        f"ATT-{uuid.uuid4().hex[:12]}",
        order_row["id"],
        next_num,
        sandbox.GATEWAY_NAME,
        order_row["final_amount"],
        order_row["currency"],
        gw_ref,
    )

    # Seat hold expires WHILE this attempt is still in flight with the
    # gateway — this is exactly the race the exception exists to catch.
    _force_hold_expired(reg["registration_id"])

    settings = get_settings()
    raw_body, sig = sandbox.build_signed_delivery(
        gw_ref, "SUCCESS", order_row["final_amount"], order_row["currency"], settings.payment_sandbox_signing_secret
    )
    r = client.post(
        "/api/v1/payment-gateways/deterministic_sandbox/webhook",
        content=raw_body,
        headers={"X-Sandbox-Signature": sig},
    )
    assert r.json()["processing_status"] == "processed"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["status"] == "paid", "captured funds must be preserved, not discarded"
    assert order_after["registration_status"] != "registered", "an expired seat must not be silently reconfirmed"

    exc_rows = _db_fetch(
        "SELECT exception_type, status FROM payment_exceptions WHERE registration_id = $1",
        reg["registration_id"],
    )
    assert any(row["exception_type"] == "PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY" and row["status"] == "open" for row in exc_rows)


def test_verification_workflow_escalates_and_blocks_retry(client):
    import uuid

    event_id = _mk_paid_event(client, f"verify-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"verify-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()

    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "PENDING"},
        headers=headers,
    )
    assert r.status_code == 201
    attempt = r.json()
    assert attempt["status"] == "pending"

    order_after_pending = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after_pending["registration_status"] == "payment_verification"

    # Retry must be blocked while an attempt is pending/unresolved.
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "SUCCESS"},
        headers=headers,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "payment_verification_in_progress"

    # A fresh verify() call, still within the window, reports 'pending' unchanged.
    r = client.post(f"/api/v1/payment-attempts/{attempt['attempt_id']}/verify", headers=headers)
    assert r.status_code == 200
    assert r.json()["status"] == "pending"

    # Simulate the attempt having sat pending well past the verification window.
    attempt_row = _db_fetch(
        "SELECT id FROM payment_attempts WHERE public_attempt_number = $1", attempt["attempt_id"]
    )
    _force_attempt_stale(attempt_row[0]["id"], minutes_ago=60)

    r = client.post(f"/api/v1/payment-attempts/{attempt['attempt_id']}/verify", headers=headers)
    assert r.status_code == 200
    assert r.json()["status"] == "requires_verification"

    exc_rows = _db_fetch(
        "SELECT exception_type FROM payment_exceptions WHERE attempt_id = $1", attempt_row[0]["id"]
    )
    assert any(row["exception_type"] == "VERIFICATION_UNRESOLVED" for row in exc_rows)

    # Still blocked after escalation — requires_verification also counts as unresolved.
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "SUCCESS"},
        headers=headers,
    )
    assert r.status_code == 409


def test_configuration_versioning_never_mutates_existing_order(client):
    """Re-importing a configuration under the same key must create a NEW
    version, not rewrite the row an existing order's configuration_id points
    at — and the order must record which version it was priced against."""
    import uuid

    key = f"version-test-{uuid.uuid4().hex[:8]}"
    event_id = _mk_paid_event(client, key)  # configuration_key becomes f"test-{key}"

    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"version-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()
    assert order["final_amount"] == "118.00"  # base 100 + 18% GST from _mk_paid_event

    order_row = _db_fetch(
        "SELECT configuration_id, configuration_version FROM payment_orders WHERE public_order_number = $1",
        order["order_id"],
    )[0]
    assert order_row["configuration_version"] == 1

    # Re-import the SAME configuration_key with a different GST rate.
    r = client.post(
        "/api/v1/dev/diagnostics/payments/configuration/import",
        json={
            "configuration_key": f"test-{key}",
            "event_id": event_id,
            "base_amount": "100.00",
            "gst_enabled": True,
            "gst_rate": "5.00",
            "gst_mode": "exclusive",
            "convenience_fee_enabled": False,
            "seat_hold_minutes": 15,
            "payment_session_expiry_minutes": 15,
        },
        headers=_ADMIN,
    )
    assert r.status_code == 200
    assert r.json()["configuration_version"] == 2

    # The existing order's amounts and configuration_id/version are untouched.
    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["final_amount"] == "118.00"

    unchanged_row = _db_fetch(
        "SELECT configuration_id, configuration_version FROM payment_orders WHERE public_order_number = $1",
        order["order_id"],
    )[0]
    assert unchanged_row["configuration_id"] == order_row["configuration_id"]
    assert unchanged_row["configuration_version"] == 1

    # A NEW pricing request for the event now reflects version 2's rate.
    new_pricing = client.get(f"/api/v1/events/{event_id}/payment-pricing", headers=headers).json()
    assert new_pricing["gst_rate"] == "5.00"


# ─────────────────────────────────────────────────────────────────────────────
# F. Security & concurrency (Priority 4)
# ─────────────────────────────────────────────────────────────────────────────

def test_client_supplied_amount_gst_currency_are_ignored(client):
    """Never trust frontend amount/GST/currency: even if a client stuffs
    extra fields into the order-creation body, the server-computed price is
    what's actually charged — extras are silently ignored (Pydantic v2
    default: unknown fields dropped, not applied, not an error)."""
    import uuid

    event_id = _mk_paid_event(client, f"tamper-create-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()

    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={
            "idempotency_key": f"tamper-key-{reg['registration_id']}",
            "final_amount": "1.00",
            "amount": "1.00",
            "gst_rate": "0.00",
            "currency": "USD",
            "status": "paid",
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text
    order = r.json()
    assert order["final_amount"] == "118.00"
    assert order["currency"] == "INR"
    assert order["status"] == "created"


def test_amount_tampering_on_webhook_rejected(client):
    import uuid

    from app.config import get_settings
    from app.gateways import deterministic_sandbox as sandbox

    event_id = _mk_paid_event(client, f"tamper-webhook-amt-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"tamper-amt-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts", json={"scenario": "PENDING"}, headers=headers
    )
    attempt = r.json()

    gw_ref_row = _db_fetch(
        "SELECT gateway_order_ref, currency FROM payment_attempts WHERE public_attempt_number = $1",
        attempt["attempt_id"],
    )[0]

    settings = get_settings()
    # Real order total is 118.00 — attacker claims only 1.00 was paid.
    raw_body, sig = sandbox.build_signed_delivery(
        gw_ref_row["gateway_order_ref"], "SUCCESS", Decimal("1.00"), gw_ref_row["currency"],
        settings.payment_sandbox_signing_secret,
    )
    r = client.post(
        "/api/v1/payment-gateways/deterministic_sandbox/webhook",
        content=raw_body,
        headers={"X-Sandbox-Signature": sig},
    )
    assert r.json()["processing_status"] == "rejected"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] == "0.00"
    assert order_after["status"] != "paid"


def test_currency_tampering_on_webhook_rejected(client):
    import uuid

    from app.config import get_settings
    from app.gateways import deterministic_sandbox as sandbox

    event_id = _mk_paid_event(client, f"tamper-webhook-cur-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"tamper-cur-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts", json={"scenario": "PENDING"}, headers=headers
    )
    attempt = r.json()
    gw_ref_row = _db_fetch(
        "SELECT gateway_order_ref, amount FROM payment_attempts WHERE public_attempt_number = $1",
        attempt["attempt_id"],
    )[0]

    settings = get_settings()
    raw_body, sig = sandbox.build_signed_delivery(
        gw_ref_row["gateway_order_ref"], "SUCCESS", gw_ref_row["amount"], "USD",
        settings.payment_sandbox_signing_secret,
    )
    r = client.post(
        "/api/v1/payment-gateways/deterministic_sandbox/webhook",
        content=raw_body,
        headers={"X-Sandbox-Signature": sig},
    )
    assert r.json()["processing_status"] == "rejected"
    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] == "0.00"


def test_replay_attack_after_successful_capture_no_effect(client):
    """Replaying the exact bytes+signature of an already-processed successful
    webhook must not re-charge, re-confirm, or otherwise change state."""
    import uuid

    event_id = _mk_paid_event(client, f"replay-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"replay-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts", json={"scenario": "SUCCESS"}, headers=headers
    )
    assert r.json()["status"] == "captured"

    captured = _db_fetch(
        """SELECT a.gateway_order_ref, a.gateway_payment_ref, a.amount, a.currency
           FROM payment_attempts a JOIN payment_orders o ON a.order_id = o.id
           WHERE o.public_order_number = $1 AND a.status = 'captured'""",
        order["order_id"],
    )[0]

    from app.config import get_settings
    from app.gateways import deterministic_sandbox as sandbox

    settings = get_settings()
    raw_body, sig = sandbox.build_signed_delivery(
        captured["gateway_order_ref"], "SUCCESS", captured["amount"], captured["currency"],
        settings.payment_sandbox_signing_secret,
    )
    # First replay attempt uses a freshly-built (but semantically identical
    # outcome) payload — different event_id, so it exercises the
    # already-captured / stale-attempt branch rather than the raw duplicate
    # (gateway,event_id) short-circuit already covered elsewhere.
    r = client.post(
        "/api/v1/payment-gateways/deterministic_sandbox/webhook",
        content=raw_body,
        headers={"X-Sandbox-Signature": sig},
    )
    assert r.json()["processing_status"] == "duplicate"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] == "118.00"  # unchanged, not doubled


def test_predictable_id_enumeration_fails(client):
    """Public order/attempt IDs are opaque tokens, not sequential integers —
    guessing a neighboring or small-integer-based ID must not resolve."""
    headers = _alumni_bearer_headers()
    for guess in ("ORD-1", "ORD-000001", "ORD-0", "1", "ORD-", "ATT-1"):
        r = client.get(f"/api/v1/payment-orders/{guess}", headers=headers)
        assert r.status_code == 404, f"guessable id {guess!r} unexpectedly resolved"


def test_no_secret_leakage_in_responses(client):
    """The sandbox HMAC signing secret must never appear in any attendee- or
    diagnostics-facing response body."""
    import uuid

    from app.config import get_settings

    secret = get_settings().payment_sandbox_signing_secret
    event_id = _mk_paid_event(client, f"leak-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()

    responses = [
        client.get(f"/api/v1/events/{event_id}/payment-pricing", headers=headers),
        client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers),
    ]
    reg = responses[-1].json()
    responses.append(
        client.post(
            f"/api/v1/registrations/{reg['registration_id']}/payment-order",
            json={"idempotency_key": f"leak-key-{reg['registration_id']}"},
            headers=headers,
        )
    )
    order = responses[-1].json()
    responses.append(
        client.post(f"/api/v1/payment-orders/{order['order_id']}/attempts", json={"scenario": "SUCCESS"}, headers=headers)
    )
    responses.append(client.get(f"/api/v1/payment-orders/{order['order_id']}/timeline", headers=headers))
    responses.append(client.get("/api/v1/dev/diagnostics/payments", headers=headers))

    for r in responses:
        assert secret not in r.text, f"signing secret leaked in response: {r.request.url}"


def test_concurrent_webhook_delivery_of_identical_payload_captures_once(client):
    """Two threads deliver the exact same signed captured-payment payload at
    the same time. The unique (gateway, gateway_event_id) constraint plus the
    FOR UPDATE lock on the order row must ensure exactly one capture, not a
    doubled amount_paid or two confirmation emails."""
    import uuid
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

    from app.config import get_settings
    from app.gateways import deterministic_sandbox as sandbox

    event_id = _mk_paid_event(client, f"concurrent-webhook-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"concurrent-webhook-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()
    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts", json={"scenario": "PENDING"}, headers=headers
    )
    attempt = r.json()
    row = _db_fetch(
        "SELECT gateway_order_ref, amount, currency FROM payment_attempts WHERE public_attempt_number = $1",
        attempt["attempt_id"],
    )[0]

    settings = get_settings()
    raw_body, sig = sandbox.build_signed_delivery(
        row["gateway_order_ref"], "SUCCESS", row["amount"], row["currency"], settings.payment_sandbox_signing_secret
    )

    def _deliver():
        return client.post(
            "/api/v1/payment-gateways/deterministic_sandbox/webhook",
            content=raw_body,
            headers={"X-Sandbox-Signature": sig},
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        f1 = pool.submit(_deliver)
        f2 = pool.submit(_deliver)
        try:
            r1, r2 = f1.result(timeout=10), f2.result(timeout=10)
        except FutureTimeoutError:
            pytest.fail("Concurrent webhook delivery hung past 10s.")

    statuses = sorted([r1.json()["processing_status"], r2.json()["processing_status"]])
    assert statuses == ["duplicate", "processed"], f"expected one processed + one duplicate, got {statuses}"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] == "118.00"
    assert order_after["status"] == "paid"


def test_double_click_attempt_creation_does_not_500(client):
    """Two threads click 'pay' at the same instant on a fresh order (no
    attempt yet). Whatever happens, it must resolve cleanly (201 or a clean
    4xx) — never an unhandled 500 from a lost unique-constraint race."""
    import uuid
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

    event_id = _mk_paid_event(client, f"dblclick-pay-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"dblclick-pay-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()

    def _attempt():
        return client.post(
            f"/api/v1/payment-orders/{order['order_id']}/attempts", json={"scenario": "SUCCESS"}, headers=headers
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        f1 = pool.submit(_attempt)
        f2 = pool.submit(_attempt)
        try:
            r1, r2 = f1.result(timeout=10), f2.result(timeout=10)
        except FutureTimeoutError:
            pytest.fail("Concurrent attempt creation hung past 10s.")

    assert r1.status_code < 500, f"double-click produced a 500: {r1.status_code} {r1.text}"
    assert r2.status_code < 500, f"double-click produced a 500: {r2.status_code} {r2.text}"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["amount_paid"] in ("0.00", "118.00")  # never partial/doubled


def test_registration_response_exposes_hold_expires_at(client):
    """RegistrationResponse must surface hold_expires_at so a client can show
    an accurate seat-hold countdown before any payment order exists — the
    field the Flutter payment demo app's Registration Review screen depends
    on."""
    import uuid

    event_id = _mk_paid_event(client, f"hold-expiry-field-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    assert r.status_code == 201, r.text
    reg = r.json()
    assert reg["status"] == "seat_held"
    assert reg["hold_expires_at"] is not None

    r = client.get(f"/api/v1/events/{event_id}/my-registration", headers=headers)
    assert r.status_code == 200
    assert r.json()["hold_expires_at"] is not None


def test_resolve_pending_attempt_endpoint_success_and_failure(client):
    """Dev-diagnostics endpoint that resolves a live 'pending' attempt to a
    terminal outcome over HTTP — the only client-safe way to demo
    'pending -> success' / 'pending -> failure' end-to-end, since a real
    client can never construct a validly-signed webhook delivery itself."""
    import uuid

    event_id = _mk_paid_event(client, f"resolve-success-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"resolve-success-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    attempt = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "PENDING"},
        headers=headers,
    ).json()
    assert attempt["status"] == "pending"

    r = client.post(
        f"/api/v1/dev/diagnostics/payments/attempts/{attempt['attempt_id']}/resolve",
        json={"outcome": "SUCCESS"},
        headers=_ADMIN,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["processing_status"] == "processed"
    assert body["order_status"] == "paid"
    assert body["registration_status"] == "registered"

    order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=headers).json()
    assert order_after["status"] == "paid"
    assert order_after["amount_paid"] == "118.00"

    # A second resolve call on the same (now-terminal) attempt must be
    # rejected, not silently re-processed.
    r2 = client.post(
        f"/api/v1/dev/diagnostics/payments/attempts/{attempt['attempt_id']}/resolve",
        json={"outcome": "SUCCESS"},
        headers=_ADMIN,
    )
    assert r2.status_code == 409
    assert r2.json()["detail"] == "attempt_not_resolvable"


def test_resolve_pending_attempt_endpoint_failure_outcome(client):
    import uuid

    event_id = _mk_paid_event(client, f"resolve-failure-{uuid.uuid4().hex[:8]}")
    headers = _alumni_bearer_headers()
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"resolve-failure-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    attempt = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "PENDING"},
        headers=headers,
    ).json()

    r = client.post(
        f"/api/v1/dev/diagnostics/payments/attempts/{attempt['attempt_id']}/resolve",
        json={"outcome": "FAILURE"},
        headers=_ADMIN,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["processing_status"] == "processed"
    assert body["registration_status"] == "payment_failed"


def test_resolve_pending_attempt_endpoint_requires_development_env(client, monkeypatch):
    """Same 404-if-not-development gate as every other payment diagnostics
    route — the new endpoint must not be reachable outside dev."""
    from app.config import get_settings

    get_settings.cache_clear()
    monkeypatch.setenv("APP_ENV", "production")
    try:
        r = client.post(
            "/api/v1/dev/diagnostics/payments/attempts/ATT-nonexistent/resolve",
            json={"outcome": "SUCCESS"},
            headers=_ADMIN,
        )
        assert r.status_code == 404
    finally:
        monkeypatch.delenv("APP_ENV", raising=False)
        get_settings.cache_clear()
