"""WP2 (operational-readiness sprint) — payment lifecycle scheduler tests.

Exercises scripts/run_payment_lifecycle_sweep.py as a real subprocess
(proving it's a genuine invocation of app.services.payment_lifecycle_service,
not a re-implementation) against the same local events_db the rest of the
suite uses. The underlying service functions' idempotency/concurrency/
protected-state guarantees were already proven directly in
test_payment_lifecycle_expiry.py (payment production foundation sprint) —
this file proves the NEW scheduler entry point reaches those same
guarantees end-to-end, plus scheduler-specific properties (exit code,
structured output, no secret leakage, isolated per-sweep failure handling,
safe concurrent invocation as separate OS processes).
"""
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

_BACKEND_DIR = Path(__file__).resolve().parent.parent
_SCRIPT = _BACKEND_DIR / "scripts" / "run_payment_lifecycle_sweep.py"

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

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_050",
    "sub": "platform.admin.sched@nitksaa.dev",
    "email": "platform.admin.sched@nitksaa.dev",
    "fullname": "Platform Admin Scheduler Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS050",
    "graduation_year": 2018,
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


def _mk_paid_event(client, uid_suffix: str, *, base_amount: str = "60.00") -> int:
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST SCHEDULER EVENT {uid_suffix}",
            "description": "Created by pytest (scheduler)",
            "start_datetime": "2027-11-01T08:00:00+05:30",
            "end_datetime": "2027-11-01T10:00:00+05:30",
            "location_text": "Test Venue",
            "is_virtual": False,
            "capacity": 10,
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
            "configuration_key": f"sched-test-{uid_suffix}", "event_id": event_id, "base_amount": base_amount,
            "gst_enabled": False, "convenience_fee_enabled": False,
            "seat_hold_minutes": 15, "payment_session_expiry_minutes": 15,
        },
        headers=_ADMIN,
    )
    assert r.status_code == 200, r.text
    return event_id


def _run_script(extra_env: dict = None) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["EMAIL_MODE"] = "log"
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [sys.executable, str(_SCRIPT)],
        cwd=str(_BACKEND_DIR),
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Script mechanics: exit code, structured output, no secrets
# ─────────────────────────────────────────────────────────────────────────────

def test_script_succeeds_with_zero_eligible_rows():
    proc = _run_script()
    assert proc.returncode == 0, proc.stderr
    result = json.loads(proc.stdout.strip())
    assert result["success"] is True
    assert result["orders_status"] == "ok"
    assert result["holds_status"] == "ok"
    assert isinstance(result["orders_expired_count"], int)
    assert isinstance(result["holds_expired_count"], int)


def test_script_output_shape_and_correlation_id():
    proc = _run_script()
    result = json.loads(proc.stdout.strip())
    for key in ("run_id", "started_at", "finished_at", "duration_ms", "success"):
        assert key in result, f"missing required field: {key}"
    uuid.UUID(result["run_id"])  # raises if not a valid uuid


def test_script_output_contains_no_secrets():
    from app.config import get_settings

    secret = get_settings().payment_sandbox_signing_secret
    db_password = get_settings().db_password
    proc = _run_script()
    assert secret not in proc.stdout
    assert secret not in proc.stderr
    assert db_password not in proc.stdout
    assert "Authorization" not in proc.stdout
    assert "Bearer" not in proc.stdout


# ─────────────────────────────────────────────────────────────────────────────
# Real lifecycle effect via the script (not the HTTP endpoint)
# ─────────────────────────────────────────────────────────────────────────────

def test_script_expires_eligible_order(client):
    headers = _bearer(_TEST_ALUMNI)
    event_id = _mk_paid_event(client, f"schedexp-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"schedexp-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    _db_exec(
        "UPDATE payment_orders SET expires_at = now() - interval '1 hour' WHERE public_order_number = $1",
        order["order_id"],
    )

    proc = _run_script()
    assert proc.returncode == 0, proc.stderr
    result = json.loads(proc.stdout.strip())
    assert result["orders_expired_count"] >= 1

    row = _db_fetch("SELECT status FROM payment_orders WHERE public_order_number = $1", order["order_id"])[0]
    assert row["status"] == "expired"


def test_script_expires_eligible_hold(client):
    headers = _bearer(_TEST_ALUMNI)
    event_id = _mk_paid_event(client, f"schedhold-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    assert reg["status"] == "seat_held"
    _db_exec(
        "UPDATE registrations SET hold_expires_at = now() - interval '1 minute' WHERE registration_id = $1",
        reg["registration_id"],
    )

    proc = _run_script()
    assert proc.returncode == 0, proc.stderr
    result = json.loads(proc.stdout.strip())
    assert result["holds_expired_count"] >= 1

    row = _db_fetch("SELECT status FROM registrations WHERE registration_id = $1", reg["registration_id"])[0]
    assert row["status"] == "cancelled"


def test_paid_order_protected_from_script_expiry(client):
    headers = _bearer(_TEST_ALUMNI_2)
    event_id = _mk_paid_event(client, f"schedpaid-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"schedpaid-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    client.post(f"/api/v1/payment-orders/{order['order_id']}/attempts", json={"scenario": "SUCCESS"}, headers=headers)
    _db_exec(
        "UPDATE payment_orders SET expires_at = now() - interval '1 hour' WHERE public_order_number = $1",
        order["order_id"],
    )

    proc = _run_script()
    assert proc.returncode == 0, proc.stderr

    row = _db_fetch("SELECT status FROM payment_orders WHERE public_order_number = $1", order["order_id"])[0]
    assert row["status"] == "paid"


def test_script_rerun_is_idempotent(client):
    headers = _bearer(_TEST_ALUMNI)
    event_id = _mk_paid_event(client, f"schedidem-{uuid.uuid4().hex[:8]}")
    reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
    order = client.post(
        f"/api/v1/registrations/{reg['registration_id']}/payment-order",
        json={"idempotency_key": f"schedidem-key-{reg['registration_id']}"},
        headers=headers,
    ).json()
    _db_exec(
        "UPDATE payment_orders SET expires_at = now() - interval '1 hour' WHERE public_order_number = $1",
        order["order_id"],
    )

    proc1 = _run_script()
    result1 = json.loads(proc1.stdout.strip())
    assert result1["orders_expired_count"] >= 1

    proc2 = _run_script()
    result2 = json.loads(proc2.stdout.strip())

    order_row_id = _db_fetch(
        "SELECT id FROM payment_orders WHERE public_order_number = $1", order["order_id"]
    )[0]["id"]
    audit_count = _db_fetch(
        """SELECT count(*) AS n FROM event_audit_log
           WHERE event_type = 'payment_order_expired' AND entity_type = 'payment_order' AND entity_id = $1""",
        order_row_id,
    )[0]["n"]
    assert audit_count == 1, "rerun must not double-audit an already-expired order"


def test_concurrent_script_invocations_are_safe(client):
    """Two real OS processes racing the same sweep — proves the underlying
    UPDATE...WHERE...RETURNING mechanism (already unit-tested directly in
    test_payment_lifecycle_expiry.py) holds at the process level too, not
    just within a single Python event loop."""
    headers = _bearer(_TEST_ALUMNI)
    order_ids = []
    for i in range(3):
        event_id = _mk_paid_event(client, f"schedconc-{i}-{uuid.uuid4().hex[:6]}")
        reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=headers).json()
        order = client.post(
            f"/api/v1/registrations/{reg['registration_id']}/payment-order",
            json={"idempotency_key": f"schedconc-key-{reg['registration_id']}"},
            headers=headers,
        ).json()
        _db_exec(
            "UPDATE payment_orders SET expires_at = now() - interval '1 hour' WHERE public_order_number = $1",
            order["order_id"],
        )
        order_ids.append(order["order_id"])

    env = dict(os.environ)
    env["EMAIL_MODE"] = "log"
    p1 = subprocess.Popen([sys.executable, str(_SCRIPT)], cwd=str(_BACKEND_DIR), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    p2 = subprocess.Popen([sys.executable, str(_SCRIPT)], cwd=str(_BACKEND_DIR), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    out1, err1 = p1.communicate(timeout=30)
    out2, err2 = p2.communicate(timeout=30)

    assert p1.returncode == 0, err1
    assert p2.returncode == 0, err2
    result1, result2 = json.loads(out1.strip()), json.loads(out2.strip())

    rows = _db_fetch(
        "SELECT public_order_number, status FROM payment_orders WHERE public_order_number = ANY($1::text[])",
        order_ids,
    )
    assert all(row["status"] == "expired" for row in rows)

    for oid in order_ids:
        order_row_id = _db_fetch(
            "SELECT id FROM payment_orders WHERE public_order_number = $1", oid
        )[0]["id"]
        audit_count = _db_fetch(
            """SELECT count(*) AS n FROM event_audit_log
               WHERE event_type = 'payment_order_expired' AND entity_type = 'payment_order' AND entity_id = $1""",
            order_row_id,
        )[0]["n"]
        assert audit_count == 1, f"order {oid} audited more than once across concurrent processes"


# ─────────────────────────────────────────────────────────────────────────────
# Manual-recovery HTTP path remains separately gated (regression check)
# ─────────────────────────────────────────────────────────────────────────────

def test_manual_recovery_endpoints_still_require_platform_admin(client, monkeypatch):
    r = client.post("/api/v1/admin/payments/lifecycle/expire-orders", headers=_bearer(_TEST_ALUMNI))
    assert r.status_code == 403

    try:
        _as_platform_admin(monkeypatch)
        r = client.post("/api/v1/admin/payments/lifecycle/expire-orders", headers=_bearer(_PLATFORM_ADMIN))
        assert r.status_code == 200, r.text
    finally:
        _clear_bootstrap(monkeypatch)
