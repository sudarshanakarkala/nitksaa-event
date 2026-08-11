"""WP4 — explicit order/seat expiry lifecycle tests.

Exercises app/services/payment_lifecycle_service.py via the admin trigger
endpoints in app/api/admin_payments.py
(POST /api/v1/admin/payments/lifecycle/expire-orders and
.../expire-registration-holds).
"""
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

import pytest

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_030",
    "sub": "platform.admin.wp4@nitksaa.dev",
    "email": "platform.admin.wp4@nitksaa.dev",
    "fullname": "Platform Admin WP4 Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS030",
    "graduation_year": 2018,
}

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


def _bearer(identity: dict) -> dict:
    from app.middleware.auth import make_access_token

    token = make_access_token(dict(identity))
    return {"Authorization": f"Bearer {token}"}


def _as_platform_admin(monkeypatch) -> None:
    from app.config import get_settings

    monkeypatch.setenv("PLATFORM_ADMIN_FIREBASE_UIDS", _PLATFORM_ADMIN["firebase_uid"])
    get_settings.cache_clear()


def _clear_bootstrap(monkeypatch) -> None:
    from app.config import get_settings

    monkeypatch.delenv("PLATFORM_ADMIN_FIREBASE_UIDS", raising=False)
    get_settings.cache_clear()


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
def _seed_platform_admin():
    for identity in (_PLATFORM_ADMIN, _FIXTURE_ADMIN):
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


def _mk_paid_event(client, uid_suffix: str, *, capacity: int = 10, base_amount: str = "50.00") -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST WP4 EVENT {uid_suffix}",
            "description": "Created by pytest (WP4 lifecycle)",
            "start_datetime": "2027-07-01T08:00:00+05:30",
            "end_datetime": "2027-07-01T10:00:00+05:30",
            "location_text": "Test Venue",
            "is_virtual": False,
            "capacity": capacity,
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
            "configuration_key": f"wp4-test-{uid_suffix}",
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


def _force_order_expired_in_past(public_order_number: str) -> None:
    _db_exec(
        "UPDATE payment_orders SET expires_at = now() - interval '1 hour' WHERE public_order_number = $1",
        public_order_number,
    )


def _force_hold_expired(registration_id: int) -> None:
    _db_exec(
        "UPDATE registrations SET hold_expires_at = now() - interval '1 minute' WHERE registration_id = $1",
        registration_id,
    )


def _trigger_expire_orders(client, headers: dict):
    return client.post("/api/v1/admin/payments/lifecycle/expire-orders", headers=headers)


def _trigger_expire_holds(client, headers: dict):
    return client.post("/api/v1/admin/payments/lifecycle/expire-registration-holds", headers=headers)


# ─────────────────────────────────────────────────────────────────────────────
# Order expiry
# ─────────────────────────────────────────────────────────────────────────────

def test_eligible_created_order_expires(client, monkeypatch):
    headers = _bearer(_TEST_ALUMNI)
    event_id = _mk_paid_event(client, f"expcreated-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"expcreated-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    assert order["status"] == "created"
    _force_order_expired_in_past(order["order_id"])

    try:
        _as_platform_admin(monkeypatch)
        r = _trigger_expire_orders(client, _bearer(_PLATFORM_ADMIN))
        assert r.status_code == 200, r.text
        assert order["order_id"] in r.json()["expired_order_ids"]

        row = _db_fetch(
            "SELECT status FROM payment_orders WHERE public_order_number = $1", order["order_id"]
        )[0]
        assert row["status"] == "expired"

        audit_rows = _db_fetch(
            """SELECT count(*) AS n FROM event_audit_log
               WHERE event_type = 'payment_order_expired' AND entity_type = 'payment_order'
                 AND entity_id = (SELECT id FROM payment_orders WHERE public_order_number = $1)""",
            order["order_id"],
        )
        assert audit_rows[0]["n"] == 1
    finally:
        _clear_bootstrap(monkeypatch)


def test_order_with_in_flight_attempt_is_protected(client, monkeypatch):
    """An order past expires_at but with a still-in-flight (pending)
    attempt must not be expired out from under it — same race class as
    PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY, applied to the order row."""
    headers = _bearer(_TEST_ALUMNI)
    event_id = _mk_paid_event(client, f"expprotected-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"expprotected-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "PENDING"},
        headers=headers,
    )
    _force_order_expired_in_past(order["order_id"])

    try:
        _as_platform_admin(monkeypatch)
        r = _trigger_expire_orders(client, _bearer(_PLATFORM_ADMIN))
        assert r.status_code == 200, r.text
        assert order["order_id"] not in r.json()["expired_order_ids"]

        row = _db_fetch(
            "SELECT status FROM payment_orders WHERE public_order_number = $1", order["order_id"]
        )[0]
        assert row["status"] in ("created", "payment_pending")
    finally:
        _clear_bootstrap(monkeypatch)


def test_paid_order_never_expired(client, monkeypatch):
    headers = _bearer(_TEST_ALUMNI)
    event_id = _mk_paid_event(client, f"exppaid-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"exppaid-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "SUCCESS"},
        headers=headers,
    )
    # Force expires_at into the past even though it's paid — the guard must
    # hold on the status filter alone (defense in depth), not just because
    # a naturally-paid order rarely has a past expires_at in practice.
    _force_order_expired_in_past(order["order_id"])

    try:
        _as_platform_admin(monkeypatch)
        r = _trigger_expire_orders(client, _bearer(_PLATFORM_ADMIN))
        assert order["order_id"] not in r.json()["expired_order_ids"]

        row = _db_fetch(
            "SELECT status, amount_paid FROM payment_orders WHERE public_order_number = $1", order["order_id"]
        )[0]
        assert row["status"] == "paid"
        assert str(row["amount_paid"]) == "50.00"
    finally:
        _clear_bootstrap(monkeypatch)


def test_expiry_sweep_is_idempotent(client, monkeypatch):
    headers = _bearer(_TEST_ALUMNI)
    event_id = _mk_paid_event(client, f"expidem-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"expidem-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    _force_order_expired_in_past(order["order_id"])

    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        r1 = _trigger_expire_orders(client, admin_headers)
        assert order["order_id"] in r1.json()["expired_order_ids"]

        r2 = _trigger_expire_orders(client, admin_headers)
        assert order["order_id"] not in r2.json()["expired_order_ids"]

        audit_rows = _db_fetch(
            """SELECT count(*) AS n FROM event_audit_log
               WHERE event_type = 'payment_order_expired' AND entity_type = 'payment_order'
                 AND entity_id = (SELECT id FROM payment_orders WHERE public_order_number = $1)""",
            order["order_id"],
        )
        assert audit_rows[0]["n"] == 1
    finally:
        _clear_bootstrap(monkeypatch)


def test_concurrent_expiry_calls_no_double_processing(client, monkeypatch):
    headers = _bearer(_TEST_ALUMNI)
    order_ids = []
    for i in range(4):
        event_id = _mk_paid_event(client, f"expconc-{i}-{uuid.uuid4().hex[:6]}")
        reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
        order = client.post(
            f"/api/v1/registrations/{reg['registration_id']}/payment-order",
            json={"idempotency_key": f"expconc-key-{reg['registration_id']}"},
            headers=headers,
        ).json()
        _force_order_expired_in_past(order["order_id"])
        order_ids.append(order["order_id"])

    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)

        with ThreadPoolExecutor(max_workers=2) as pool:
            f1 = pool.submit(_trigger_expire_orders, client, admin_headers)
            f2 = pool.submit(_trigger_expire_orders, client, admin_headers)
            try:
                r1, r2 = f1.result(timeout=10), f2.result(timeout=10)
            except FutureTimeoutError:
                pytest.fail("Concurrent expiry sweep hung past 10s.")

        assert r1.status_code == 200 and r2.status_code == 200
        combined_expired = set(r1.json()["expired_order_ids"]) | set(r2.json()["expired_order_ids"])
        # No double-reporting across the two concurrent calls.
        assert len(r1.json()["expired_order_ids"]) + len(r2.json()["expired_order_ids"]) == len(combined_expired)
        assert set(order_ids) <= combined_expired

        rows = _db_fetch(
            "SELECT public_order_number, status FROM payment_orders WHERE public_order_number = ANY($1::text[])",
            order_ids,
        )
        assert all(row["status"] == "expired" for row in rows)

        for oid in order_ids:
            audit_rows = _db_fetch(
                """SELECT count(*) AS n FROM event_audit_log
                   WHERE event_type = 'payment_order_expired' AND entity_type = 'payment_order'
                     AND entity_id = (SELECT id FROM payment_orders WHERE public_order_number = $1)""",
                oid,
            )
            assert audit_rows[0]["n"] == 1, f"order {oid} audited more than once"
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# Registration hold expiry
# ─────────────────────────────────────────────────────────────────────────────

def test_stale_seat_hold_expires(client, monkeypatch):
    headers = _bearer(_TEST_ALUMNI)
    event_id = _mk_paid_event(client, f"holdexp-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    assert reg["status"] == "seat_held"
    _force_hold_expired(reg["registration_id"])

    try:
        _as_platform_admin(monkeypatch)
        r = _trigger_expire_holds(client, _bearer(_PLATFORM_ADMIN))
        assert r.status_code == 200, r.text
        assert reg["registration_id"] in r.json()["expired_registration_ids"]

        row = _db_fetch(
            "SELECT status FROM registrations WHERE registration_id = $1", reg["registration_id"]
        )[0]
        assert row["status"] == "cancelled"
    finally:
        _clear_bootstrap(monkeypatch)


def test_confirmed_registration_never_expired(client, monkeypatch):
    headers = _bearer(_TEST_ALUMNI_2)
    event_id = _mk_paid_event(client, f"holdconfirmed-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"holdconfirmed-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    client.post(
        f"/api/v1/payment-orders/{order['order_id']}/attempts",
        json={"scenario": "SUCCESS"},
        headers=headers,
    )
    row = _db_fetch("SELECT status FROM registrations WHERE registration_id = $1", reg["registration_id"])[0]
    assert row["status"] == "registered"

    # Force hold_expires_at into the past even though confirmed — the
    # WHERE clause's status filter (never matches 'registered') is the
    # actual guard, not the natural absence of a past hold_expires_at.
    _force_hold_expired(reg["registration_id"])

    try:
        _as_platform_admin(monkeypatch)
        r = _trigger_expire_holds(client, _bearer(_PLATFORM_ADMIN))
        assert reg["registration_id"] not in r.json()["expired_registration_ids"]

        row_after = _db_fetch(
            "SELECT status FROM registrations WHERE registration_id = $1", reg["registration_id"]
        )[0]
        assert row_after["status"] == "registered"
    finally:
        _clear_bootstrap(monkeypatch)


def test_expire_holds_requires_platform_admin(client):
    from app.middleware.auth import make_access_token

    token = make_access_token(dict(_TEST_ALUMNI))
    r = client.post(
        "/api/v1/admin/payments/lifecycle/expire-registration-holds",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 403
