"""Sprint 7 — Real Payment Gateway Foundation.

Covers the new gateway-neutral architecture (app/gateways/base.py,
app/gateways/registry.py, DeterministicSandboxGateway) and the adversarial
properties the sprint prompt requires evidence for: gateway selection is
server-authoritative (never client-supplied), unknown/disabled gateways
fail closed, capability gaps (refund, query_payment_status, verify_payment)
raise cleanly instead of faking a response, and the sandbox stays disabled
by default in a production environment so no-real-money payments can never
be silently reachable there.

Deliberately does NOT re-test what test_payments.py /
test_payment_webhook_freshness.py already cover end-to-end (signature
verification, freshness, amount/currency mismatch, duplicate webhooks,
seat-hold interactions) — those pass unmodified through this refactor and
remain the regression guard for it.
"""
import uuid
from decimal import Decimal

import pytest

# Same identity test_payments.py uses — seeded in both alumni_db
# (alumni.alumni_id, required for the /register eligibility check) and
# events_db (event_users). A fresh synthetic UID here would only exist in
# event_users and fail /register with alumni_not_found.
_TEST_ALUMNI = {
    "firebase_uid": "TEST_ALUMNI_UID_001",
    "sub": "ravi.test@nitksaa.dev",
    "email": "ravi.test@nitksaa.dev",
    "fullname": "Ravi Shankar Test",
    "user_type": "alumni",
    "ref_id": "NITK2020CS001",
    "graduation_year": 2020,
}

_FIXTURE_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_043",
    "sub": "fixture.admin.rbac@nitksaa.dev",
    "email": "fixture.admin.rbac@nitksaa.dev",
    "fullname": "Fixture Admin RBAC Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS043",
    "graduation_year": 2018,
}

_ADMIN = {"X-Dev-User": "admin"}


def _bearer(identity: dict = _TEST_ALUMNI) -> dict:
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


@pytest.fixture(autouse=True)
def _seed_fixture_identities():
    for identity in (_TEST_ALUMNI, _FIXTURE_ADMIN):
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (firebase_uid) DO NOTHING
            """,
            identity["firebase_uid"], identity["email"], identity["fullname"],
            identity["user_type"], identity["ref_id"], identity["graduation_year"],
        )
    _db_exec(
        """
        INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
        VALUES ($1, 'platform_admin', 'test_fixture_bootstrap')
        ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING
        """,
        _FIXTURE_ADMIN["firebase_uid"],
    )


def _mk_paid_event(client, uid_suffix: str, *, base_amount: str = "100.00",
                   gateway: str = "deterministic_sandbox") -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST GATEWAY EVENT {uid_suffix}",
            "description": "Created by pytest (gateway foundation)",
            "start_datetime": "2027-03-01T08:00:00+05:30",
            "end_datetime": "2027-03-01T10:00:00+05:30",
            "location_text": "Test Venue",
            "is_virtual": False,
            "capacity": 20,
            "is_free": False,
            "ticket_price": base_amount,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    event_id = r.json()["event_id"]
    r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    r = client.post(
        "/api/v1/dev/diagnostics/payments/configuration/import",
        json={
            "configuration_key": f"gwtest-{uid_suffix}",
            "event_id": event_id,
            "base_amount": base_amount,
            "gst_enabled": False,
            "seat_hold_minutes": 15,
            "payment_session_expiry_minutes": 15,
            "gateway": gateway,
        },
        headers=_ADMIN,
    )
    assert r.status_code == 200, r.text
    return event_id


# ─────────────────────────────────────────────────────────────────────────────
# A. Gateway abstraction — pure unit tests, no DB/client
# ─────────────────────────────────────────────────────────────────────────────

def test_sandbox_gateway_conforms_to_interface():
    from app.gateways.base import GatewayCapability, PaymentGateway
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

    gateway = DeterministicSandboxGateway()
    assert isinstance(gateway, PaymentGateway)
    assert gateway.name == "deterministic_sandbox"
    assert GatewayCapability.CREATE_PAYMENT in gateway.capabilities
    assert GatewayCapability.VERIFY_WEBHOOK in gateway.capabilities
    assert GatewayCapability.PROCESS_WEBHOOK in gateway.capabilities
    # Deterministic sandbox refunds were added in the Razorpay Test Mode
    # sprint so the refund domain is exercisable without a real provider.
    assert GatewayCapability.REFUND in gateway.capabilities
    assert GatewayCapability.QUERY_REFUND in gateway.capabilities
    # Still not supported: the sandbox has no separate provider-side state to
    # query, and never treats a client-return as authoritative.
    assert GatewayCapability.QUERY_PAYMENT_STATUS not in gateway.capabilities
    assert GatewayCapability.VERIFY_PAYMENT not in gateway.capabilities
    assert "SUCCESS" in gateway.supported_scenarios


def test_unsupported_capability_raises_cleanly_not_a_fake_response():
    """A capability the sandbox does NOT declare must raise, never return a
    fabricated response. query_payment_status and verify_payment remain
    unsupported on the sandbox (no separate provider-side state; never
    trusts a client-return)."""
    from app.gateways.base import GatewayCapabilityNotSupportedError
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

    gateway = DeterministicSandboxGateway()
    with pytest.raises(GatewayCapabilityNotSupportedError):
        gateway.query_payment_status("sbx_ord_whatever")
    with pytest.raises(GatewayCapabilityNotSupportedError):
        gateway.verify_payment()
    with pytest.raises(GatewayCapabilityNotSupportedError):
        gateway.verify_checkout_signature(
            provider_order_id="x", provider_payment_id="y", signature="z"
        )


def test_sandbox_refund_is_deterministic_processed():
    """The sandbox's declared REFUND/QUERY_REFUND return a real
    NormalizedRefundResult (processed at once — no settlement delay to
    simulate), not GatewayCapabilityNotSupportedError."""
    from app.gateways.base import NormalizedRefundStatus
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

    gateway = DeterministicSandboxGateway()
    result = gateway.refund(
        provider_payment_id="sbx_pay_x", amount_minor=100, currency="INR",
        idempotency_key="refund:order:1",
    )
    assert result.status == NormalizedRefundStatus.REFUND_PROCESSED
    assert result.amount_minor == 100
    assert result.provider_refund_id.startswith("sbx_rfnd_")
    q = gateway.query_refund(provider_payment_id="sbx_pay_x", provider_refund_id=result.provider_refund_id)
    assert q.status == NormalizedRefundStatus.REFUND_PROCESSED


def test_parse_webhook_normalizes_provider_vocabulary():
    """The domain layer must only ever see NormalizedStatus, never raw
    provider event-type strings (e.g. 'payment.captured')."""
    from app.gateways.base import NormalizedStatus
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway, canonicalize

    gateway = DeterministicSandboxGateway()
    payload = {
        "event_id": "evt-1", "event_type": "payment.captured", "gateway": "deterministic_sandbox",
        "gateway_order_ref": "sbx_ord_x", "amount": "100.00", "currency": "INR", "issued_at": 1700000000,
        "gateway_payment_ref": "sbx_pay_x",
    }
    event = gateway.parse_webhook(canonicalize(payload))
    assert event.status == NormalizedStatus.PAYMENT_SUCCESS
    assert event.raw_event_type == "payment.captured"
    assert event.gateway_payment_ref == "sbx_pay_x"


def test_parse_webhook_unrecognized_event_type_is_unknown_not_a_crash():
    from app.gateways.base import NormalizedStatus
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway, canonicalize

    gateway = DeterministicSandboxGateway()
    payload = {"event_id": "evt-2", "event_type": "something.else", "gateway_order_ref": "sbx_ord_y"}
    event = gateway.parse_webhook(canonicalize(payload))
    assert event.status == NormalizedStatus.UNKNOWN


def test_parse_webhook_unparseable_body_raises():
    from app.gateways.base import GatewayWebhookUnparseableError
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

    gateway = DeterministicSandboxGateway()
    with pytest.raises(GatewayWebhookUnparseableError):
        gateway.parse_webhook(b"not json")


# ─────────────────────────────────────────────────────────────────────────────
# B. Registry — server-controlled selection, fail-closed
# ─────────────────────────────────────────────────────────────────────────────

def test_registry_unknown_gateway_name_raises():
    from app.gateways import registry

    with pytest.raises(registry.UnknownGatewayError):
        registry.get_gateway("attacker_supplied_gateway")


def test_registry_never_falls_back_to_a_default_gateway(monkeypatch):
    """A misconfigured settings.payment_gateway_mode must fail closed, not
    silently resolve to deterministic_sandbox or any other registered
    gateway."""
    from app.config import get_settings
    from app.gateways import registry

    monkeypatch.setenv("PAYMENT_GATEWAY_MODE", "not_a_real_gateway")
    get_settings.cache_clear()
    try:
        with pytest.raises(registry.UnknownGatewayError):
            registry.get_active_gateway(get_settings())
    finally:
        monkeypatch.delenv("PAYMENT_GATEWAY_MODE", raising=False)
        get_settings.cache_clear()


def test_sandbox_disabled_in_production_by_default(monkeypatch):
    """The no-real-money sandbox must never be silently reachable in a real
    production deployment — fail closed unless explicitly opted in."""
    from app.config import get_settings
    from app.gateways import registry

    monkeypatch.setenv("APP_ENV", "production")
    get_settings.cache_clear()
    try:
        with pytest.raises(registry.GatewayDisabledError):
            registry.get_active_gateway(get_settings())
    finally:
        monkeypatch.delenv("APP_ENV", raising=False)
        get_settings.cache_clear()


def test_sandbox_enabled_in_production_with_explicit_opt_in(monkeypatch):
    from app.config import get_settings
    from app.gateways import registry

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("PAYMENT_SANDBOX_ALLOW_IN_PRODUCTION", "true")
    get_settings.cache_clear()
    try:
        gateway = registry.get_active_gateway(get_settings())
        assert gateway.name == "deterministic_sandbox"
    finally:
        monkeypatch.delenv("APP_ENV", raising=False)
        monkeypatch.delenv("PAYMENT_SANDBOX_ALLOW_IN_PRODUCTION", raising=False)
        get_settings.cache_clear()


# ─────────────────────────────────────────────────────────────────────────────
# C. API-level: gateway selection is server-authoritative, fails closed
# ─────────────────────────────────────────────────────────────────────────────

def test_attempt_creation_fails_closed_when_order_gateway_is_unusable(client, monkeypatch):
    """Gateway dispatch is per-order (payment_orders.gateway, snapshotted
    from the published config). If that gateway is disabled/misconfigured
    (razorpay with no credentials -> is_enabled() False), attempt creation
    fails closed with 503 and never mutates order/attempt state — no 500,
    no partial row, and it never silently falls back to another gateway."""
    from app.config import get_settings

    # Ensure razorpay has no usable credentials for this test. An explicit
    # empty env var overrides any real value in backend/.env (env source
    # outranks the dotenv source in pydantic-settings).
    for var in ("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET"):
        monkeypatch.setenv(var, "")
    get_settings.cache_clear()

    event_id = _mk_paid_event(
        client, f"failclosed-{uuid.uuid4().hex[:8]}", gateway="razorpay"
    )
    headers = _bearer()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"failclosed-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()
    assert order["order_id"], order

    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts", json={}, headers=headers
    )
    assert r.status_code == 503, r.text
    assert r.json()["detail"] == "payment_gateway_unavailable"

    get_settings.cache_clear()
    attempts = _db_fetch(
        "SELECT pa.id FROM payment_attempts pa JOIN payment_orders po ON pa.order_id = po.id "
        "WHERE po.public_order_number = $1",
        order["order_id"],
    )
    assert attempts == []


def test_client_supplied_gateway_field_on_attempt_request_has_no_effect(client):
    """Gateway Tampering (§21): CreatePaymentAttemptRequest has no `gateway`
    field at all — an attacker-supplied one is dropped by Pydantic before it
    ever reaches the service layer, and the attempt is always created
    against the server-configured active gateway."""
    event_id = _mk_paid_event(client, f"gwtamper-{uuid.uuid4().hex[:8]}")
    headers = _bearer()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"gwtamper-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()

    r = client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "FAILURE", "gateway": "attacker_gateway", "gateway_order_ref": "forged"},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    assert r.json()["gateway"] == "deterministic_sandbox"


def test_webhook_endpoint_rejects_gateway_disabled_in_production(client, monkeypatch):
    from app.config import get_settings

    monkeypatch.setenv("APP_ENV", "production")
    get_settings.cache_clear()
    try:
        r = client.post(
            "/api/v1/payment-gateways/deterministic_sandbox/webhook",
            content=b"{}",
            headers={"X-Sandbox-Signature": "irrelevant"},
        )
        assert r.status_code == 404
        assert r.json()["detail"] == "unknown_gateway"
    finally:
        monkeypatch.delenv("APP_ENV", raising=False)
        get_settings.cache_clear()


def test_gateway_config_diagnostics_requires_platform_role(client):
    r = client.get("/api/v1/admin/payments/gateway-config")
    assert r.status_code == 403


def test_gateway_config_diagnostics_exposes_no_secrets(client):
    r = client.get("/api/v1/admin/payments/gateway-config", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["active_gateway"] == "deterministic_sandbox"
    assert body["environment"] == "development"
    names = [g["name"] for g in body["gateways"]]
    assert "deterministic_sandbox" in names
    dumped = str(body)
    from app.config import get_settings

    assert get_settings().payment_sandbox_signing_secret not in dumped


# ─────────────────────────────────────────────────────────────────────────────
# D. Concurrency — 5 simultaneous requests, single logical financial state
# ─────────────────────────────────────────────────────────────────────────────

def test_five_concurrent_order_creation_requests_produce_one_order(client):
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

    event_id = _mk_paid_event(client, f"concurrent5-{uuid.uuid4().hex[:8]}")
    headers = _bearer()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    idem_key = f"concurrent5-key-{reg['registration_id']}"

    def _create():
        return client.post(
            f"/api/v1/registrations/{reg['registration_id']}/payment-order",
            json={"idempotency_key": idem_key},
            headers=headers,
        )

    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = [pool.submit(_create) for _ in range(5)]
        responses = []
        for f in futures:
            try:
                responses.append(f.result(timeout=15))
            except FutureTimeoutError:
                pytest.fail("concurrent order creation hung")

    assert all(r.status_code == 201 for r in responses), [r.text for r in responses]
    order_ids = {r.json()["order_id"] for r in responses}
    assert len(order_ids) == 1

    rows = _db_fetch(
        "SELECT id FROM payment_orders WHERE registration_id = $1",
        reg["registration_id"],
    )
    assert len(rows) == 1


def test_five_concurrent_attempt_creation_requests_only_one_succeeds(client):
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

    event_id = _mk_paid_event(client, f"concurrent5att-{uuid.uuid4().hex[:8]}")
    headers = _bearer()
    r = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers)
    reg = r.json()
    r = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"concurrent5att-key-{reg['registration_id']}"},
        headers=headers,
    )
    order = r.json()

    def _attempt():
        return client.post(
            f"/api/v1/payment-orders/{order['order_id']}/attempts",
            json={"scenario": "PENDING"},
            headers=headers,
        )

    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = [pool.submit(_attempt) for _ in range(5)]
        responses = []
        for f in futures:
            try:
                responses.append(f.result(timeout=15))
            except FutureTimeoutError:
                pytest.fail("concurrent attempt creation hung")

    successes = [r for r in responses if r.status_code == 201]
    conflicts = [r for r in responses if r.status_code == 409]
    assert len(successes) == 1, [r.text for r in responses]
    assert len(conflicts) == 4

    rows = _db_fetch(
        "SELECT pa.id FROM payment_attempts pa JOIN payment_orders po ON pa.order_id = po.id "
        "WHERE po.public_order_number = $1",
        order["order_id"],
    )
    assert len(rows) == 1
