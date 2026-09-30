"""WP1 — production payment configuration lifecycle tests.

Covers the new production-safe write path to payment_configurations
(draft -> validate -> publish -> published, append-only versioning, safe
retirement) added in app/services/payment_config_service.py and
app/api/admin_payments.py. Does not touch or re-test the pre-existing
dev-diagnostics import path (app/api/dev_diagnostics.py) — that stays
development-only and is already covered by test_payments.py.
"""
import uuid
from decimal import Decimal

import pytest

from app.services.payment_config_service import validate_configuration
from tests import _razorpay_fakes as fakes

_PLATFORM_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_010",
    "sub": "platform.admin.wp1@nitksaa.dev",
    "email": "platform.admin.wp1@nitksaa.dev",
    "fullname": "Platform Admin WP1 Test",
    "user_type": "alumni",
    "ref_id": "NITK2018CS010",
    "graduation_year": 2018,
}

_EVENT_ADMIN = {
    "firebase_uid": "TEST_ALUMNI_UID_011",
    "sub": "event.admin.wp1@nitksaa.dev",
    "email": "event.admin.wp1@nitksaa.dev",
    "fullname": "Event Admin WP1 Test",
    "user_type": "alumni",
    "ref_id": "NITK2019CS011",
    "graduation_year": 2019,
}

_OUTSIDER = {
    "firebase_uid": "TEST_ALUMNI_UID_012",
    "sub": "outsider.wp1@nitksaa.dev",
    "email": "outsider.wp1@nitksaa.dev",
    "fullname": "Outsider WP1 Test",
    "user_type": "alumni",
    "ref_id": "NITK2020CS012",
    "graduation_year": 2020,
}

# The registration flow additionally checks alumni_db (not just
# events_db.event_users), and only the identities test_payments.py already
# seeds there are usable for an actual register() call — see that file's
# _TEST_ALUMNI docstring. _OUTSIDER above is fine for pure
# authorization-boundary checks (which never reach alumni_db) but not for
# tests that need a real registration to go through.
_REGISTERING_ALUMNI = {
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


def _bearer(identity: dict = _PLATFORM_ADMIN) -> dict:
    from app.middleware.auth import make_access_token

    token = make_access_token(dict(identity))
    return {"Authorization": f"Bearer {token}"}


def _as_platform_admin(monkeypatch) -> None:
    """Bootstrap _PLATFORM_ADMIN as platform_admin via the env-var list —
    same monkeypatch + settings-cache-clear pattern already used by
    test_resolve_pending_attempt_endpoint_requires_development_env in
    test_payments.py."""
    from app.config import get_settings

    monkeypatch.setenv("PLATFORM_ADMIN_FIREBASE_UIDS", _PLATFORM_ADMIN["firebase_uid"])
    get_settings.cache_clear()


def _clear_bootstrap(monkeypatch) -> None:
    from app.config import get_settings

    monkeypatch.delenv("PLATFORM_ADMIN_FIREBASE_UIDS", raising=False)
    get_settings.cache_clear()


def _mk_unpaid_event(client, uid_suffix: str, *, capacity: int = 10) -> int:
    """A published event with NO payment configuration yet — the starting
    point for the WP1 draft/publish flow (unlike test_payments.py's
    _mk_paid_event, which uses the dev-diagnostics import shortcut)."""
    r = client.post(
        "/api/v1/admin/events",
        json={
            "title": f"TEST WP1 EVENT {uid_suffix}",
            "description": "Created by pytest (WP1 config lifecycle)",
            "start_datetime": "2027-04-01T08:00:00+05:30",
            "end_datetime": "2027-04-01T10:00:00+05:30",
            "location_text": "Test Venue",
            "is_virtual": False,
            "capacity": capacity,
            "is_free": True,
        },
        headers=_bearer(_FIXTURE_ADMIN),
    )
    assert r.status_code == 201, r.text
    event_id = r.json()["event_id"]
    r = client.post(f"/api/v1/admin/events/{event_id}/publish", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    return event_id


def _draft_payload(uid_suffix: str, **overrides) -> dict:
    payload = {
        "configuration_key": f"wp1-test-{uid_suffix}",
        "base_amount": "100.00",
        "gst_enabled": True,
        "gst_rate": "18.00",
        "gst_mode": "exclusive",
        "convenience_fee_enabled": False,
        "seat_hold_minutes": 15,
        "payment_session_expiry_minutes": 15,
    }
    payload.update(overrides)
    return payload


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
def _seed_test_identities():
    """payment_platform_roles.firebase_uid and event_members.firebase_uid
    both FK-reference event_users — unlike test_payments.py's pre-seeded
    _TEST_ALUMNI identities, these synthetic WP1-test identities have no
    seed data, so role/membership grants against them would otherwise fail
    with a foreign-key violation. Direct DB insert is test setup the API
    has no (and should have no) endpoint for, same rationale as
    test_payments.py's _force_hold_expired."""
    for identity in (_PLATFORM_ADMIN, _EVENT_ADMIN, _OUTSIDER, _REGISTERING_ALUMNI, _FIXTURE_ADMIN):
        _db_exec(
            """
            INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id, graduation_year)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (firebase_uid) DO NOTHING
            """,
            identity["firebase_uid"],
            identity["email"],
            identity["fullname"],
            identity["user_type"],
            identity["ref_id"],
            identity["graduation_year"],
        )
    _db_exec(
        """
        INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
        VALUES ($1, 'platform_admin', 'test_fixture_bootstrap')
        ON CONFLICT (firebase_uid, role) WHERE revoked_at IS NULL DO NOTHING
        """,
        _FIXTURE_ADMIN["firebase_uid"],
    )


# ─────────────────────────────────────────────────────────────────────────────
# A. Pure unit tests of validate_configuration — no DB, no auth
# ─────────────────────────────────────────────────────────────────────────────

def test_validate_configuration_accepts_valid_payload():
    errors = validate_configuration(_draft_payload("unit"))
    assert errors == []


def test_validate_configuration_rejects_negative_base_amount():
    errors = validate_configuration(_draft_payload("unit", base_amount=Decimal("-1")))
    assert any("base_amount" in e for e in errors)


def test_validate_configuration_rejects_bad_gst_mode():
    errors = validate_configuration(_draft_payload("unit", gst_mode="bogus"))
    assert any("gst_mode" in e for e in errors)


def test_validate_configuration_rejects_gst_rate_out_of_range():
    errors = validate_configuration(_draft_payload("unit", gst_enabled=True, gst_rate=Decimal("150")))
    assert any("gst_rate" in e for e in errors)


def test_validate_configuration_rejects_bad_fee_type():
    errors = validate_configuration(
        _draft_payload("unit", convenience_fee_enabled=True, convenience_fee_type="bogus")
    )
    assert any("convenience_fee_type" in e for e in errors)


def test_validate_configuration_rejects_percentage_fee_over_100():
    errors = validate_configuration(
        _draft_payload(
            "unit",
            convenience_fee_enabled=True,
            convenience_fee_type="percentage",
            convenience_fee_value=Decimal("150"),
        )
    )
    assert any("convenience_fee_value" in e for e in errors)


def test_validate_configuration_rejects_non_positive_durations():
    errors = validate_configuration(_draft_payload("unit", seat_hold_minutes=0))
    assert any("seat_hold_minutes" in e for e in errors)
    errors = validate_configuration(_draft_payload("unit", payment_session_expiry_minutes=0))
    assert any("payment_session_expiry_minutes" in e for e in errors)


_MIN_AMOUNT_ERROR = "at least INR 1.00"


@pytest.mark.parametrize("base_amount,accepted", [
    ("0.00", False), ("0.99", False), ("1.00", True), ("250.00", True),
])
def test_validate_configuration_razorpay_minimum_final_amount(base_amount, accepted):
    errors = validate_configuration(_draft_payload(
        "unit", gateway="razorpay", payment_mode="test", base_amount=base_amount, gst_enabled=False,
    ))
    if accepted:
        assert errors == []
    else:
        assert any(_MIN_AMOUNT_ERROR in e for e in errors), errors


@pytest.mark.parametrize("overrides,accepted", [
    # 0.90 + 18% exclusive GST = 1.06: base below 1.00, final payable above.
    ({"base_amount": "0.90", "gst_enabled": True, "gst_rate": "18.00", "gst_mode": "exclusive"}, True),
    # 0.50 + fixed 0.50 convenience fee = exactly 1.00.
    ({"base_amount": "0.50", "gst_enabled": False, "convenience_fee_enabled": True,
      "convenience_fee_type": "fixed", "convenience_fee_value": "0.50"}, True),
    # 0.50 + fixed 0.49 convenience fee = 0.99.
    ({"base_amount": "0.50", "gst_enabled": False, "convenience_fee_enabled": True,
      "convenience_fee_type": "fixed", "convenience_fee_value": "0.49"}, False),
    # 0.99 inclusive GST stays 0.99 payable.
    ({"base_amount": "0.99", "gst_enabled": True, "gst_rate": "18.00", "gst_mode": "inclusive"}, False),
])
def test_validate_configuration_razorpay_minimum_checks_final_payable_amount(overrides, accepted):
    errors = validate_configuration(_draft_payload("unit", gateway="razorpay", payment_mode="test", **overrides))
    assert (not any(_MIN_AMOUNT_ERROR in e for e in errors)) is accepted, errors


@pytest.mark.parametrize("base_amount", ["0.00", "0.50"])
def test_validate_configuration_minimum_does_not_apply_to_sandbox(base_amount):
    errors = validate_configuration(_draft_payload(
        "unit", gateway="deterministic_sandbox", base_amount=base_amount, gst_enabled=False,
    ))
    assert errors == []


def test_validate_configuration_rejects_live_razorpay_without_live_credentials(monkeypatch):
    from app.config import get_settings

    fakes.clear_razorpay_env(monkeypatch)
    try:
        errors = validate_configuration(_draft_payload("unit", gateway="razorpay", payment_mode="live"))
        assert any("RAZORPAY_MODE=live" in e for e in errors)
    finally:
        get_settings.cache_clear()


def test_validate_configuration_rejects_live_razorpay_on_test_deployment(monkeypatch):
    """Complete, valid TEST credentials must not make a LIVE config
    publishable — the deployment itself has to run RAZORPAY_MODE=live."""
    from app.config import get_settings

    fakes.set_razorpay_env(monkeypatch)
    try:
        errors = validate_configuration(_draft_payload("unit", gateway="razorpay", payment_mode="live"))
        assert any("RAZORPAY_MODE=live" in e for e in errors)
    finally:
        get_settings.cache_clear()


def test_validate_configuration_rejects_live_razorpay_with_test_prefixed_live_key(monkeypatch):
    from app.config import get_settings

    fakes.set_razorpay_live_env(monkeypatch, key_id="rzp_test_wrongprefix")
    try:
        errors = validate_configuration(_draft_payload("unit", gateway="razorpay", payment_mode="live"))
        assert any("rzp_live_" in e for e in errors)
    finally:
        get_settings.cache_clear()


def test_validate_configuration_accepts_live_razorpay_with_valid_live_credentials(monkeypatch):
    from app.config import get_settings

    fakes.set_razorpay_live_env(monkeypatch)
    try:
        errors = validate_configuration(_draft_payload("unit", gateway="razorpay", payment_mode="live"))
        assert errors == []
    finally:
        get_settings.cache_clear()


def test_validate_configuration_test_mode_never_requires_live_credentials(monkeypatch):
    from app.config import get_settings

    fakes.clear_razorpay_env(monkeypatch)
    try:
        errors = validate_configuration(_draft_payload("unit", gateway="razorpay", payment_mode="test"))
        assert errors == []
    finally:
        get_settings.cache_clear()


# ─────────────────────────────────────────────────────────────────────────────
# B. API-level authorization + draft/validate/publish lifecycle
# ─────────────────────────────────────────────────────────────────────────────

def test_create_draft_requires_authentication_and_authorization(client, monkeypatch):
    uid = uuid.uuid4().hex[:8]
    event_id = _mk_unpaid_event(client, f"authz-{uid}")

    # No Authorization header at all.
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-configurations",
        json=_draft_payload(f"authz-noauth-{uid}"),
    )
    assert r.status_code == 403

    # A real, but unprivileged, attendee identity.
    r = client.post(
        f"/api/v1/admin/events/{event_id}/payment-configurations",
        json=_draft_payload(f"authz-attendee-{uid}"),
        headers=_bearer(_OUTSIDER),
    )
    assert r.status_code == 403

    # Bootstrap platform_admin succeeds. Fresh configuration_key (uuid
    # suffixed) so version is deterministically 1 regardless of how many
    # times this test has run against a persistent dev DB.
    try:
        _as_platform_admin(monkeypatch)
        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(f"authz-admin-{uid}"),
            headers=_bearer(_PLATFORM_ADMIN),
        )
        assert r.status_code == 201, r.text
        body = r.json()
        assert body["status"] == "draft"
        assert body["version"] == 1
    finally:
        _clear_bootstrap(monkeypatch)


def test_create_draft_rejects_custom_validation_failure_not_caught_by_schema(client, monkeypatch):
    """convenience_fee_value has no upper bound in the Pydantic schema (only
    ge=0) — a percentage fee over 100% is only caught by
    validate_configuration's cross-field rule, proving the service-level
    validation actually runs, not just FastAPI's schema validation."""
    event_id = _mk_unpaid_event(client, f"customval-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(
                "customval",
                convenience_fee_enabled=True,
                convenience_fee_type="percentage",
                convenience_fee_value="150.00",
            ),
            headers=_bearer(_PLATFORM_ADMIN),
        )
        assert r.status_code == 422, r.text
        assert any("convenience_fee_value" in e for e in r.json()["detail"]["errors"])
    finally:
        _clear_bootstrap(monkeypatch)


def test_publish_requires_draft_status(client, monkeypatch):
    event_id = _mk_unpaid_event(client, f"pubstatus-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        headers = _bearer(_PLATFORM_ADMIN)
        draft = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload("pubstatus"),
            headers=headers,
        ).json()

        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{draft['configuration_id']}/publish",
            headers=headers,
        )
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "published"

        # Publishing the same (already-published) row again must be a
        # clean conflict, not a silent no-op or a 500.
        r2 = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{draft['configuration_id']}/publish",
            headers=headers,
        )
        assert r2.status_code == 409
        assert r2.json()["detail"] == "payment_configuration_not_a_draft"
    finally:
        _clear_bootstrap(monkeypatch)


def test_versioning_retires_previous_published_and_history_is_immutable(client, monkeypatch):
    event_id = _mk_unpaid_event(client, f"version-{uuid.uuid4().hex[:8]}")
    key = f"wp1-version-{uuid.uuid4().hex[:8]}"
    try:
        _as_platform_admin(monkeypatch)
        headers = _bearer(_PLATFORM_ADMIN)

        v1_draft = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(key, configuration_key=key, gst_rate="18.00"),
            headers=headers,
        ).json()
        v1 = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{v1_draft['configuration_id']}/publish",
            headers=headers,
        ).json()
        assert v1["version"] == 1
        assert v1["status"] == "published"
        v1_snapshot = dict(v1)

        v2_draft = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(key, configuration_key=key, gst_rate="5.00"),
            headers=headers,
        ).json()
        assert v2_draft["version"] == 2
        v2 = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{v2_draft['configuration_id']}/publish",
            headers=headers,
        ).json()
        assert v2["version"] == 2
        assert v2["status"] == "published"

        # v1's own row is now retired, and its stored fields are unchanged
        # (immutable published history).
        v1_after = client.get(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{v1_draft['configuration_id']}",
            headers=headers,
        ).json()
        assert v1_after["status"] == "retired"
        assert v1_after["gst_rate"] == v1_snapshot["gst_rate"] == "18.00"

        history = client.get(
            f"/api/v1/admin/events/{event_id}/payment-configurations", headers=headers
        ).json()["configurations"]
        statuses = {c["configuration_id"]: c["status"] for c in history}
        assert statuses[v1["configuration_id"]] == "retired"
        assert statuses[v2["configuration_id"]] == "published"

        # Attendee-facing pricing now reflects v2.
        pricing = client.get(f"/api/v1/events/{event_id}/payment-pricing", headers=headers).json()
        assert pricing["gst_rate"] == "5.00"
    finally:
        _clear_bootstrap(monkeypatch)


def test_existing_order_retains_old_configuration_after_republish(client, monkeypatch):
    event_id = _mk_unpaid_event(client, f"orderpin-{uuid.uuid4().hex[:8]}")
    key = f"wp1-orderpin-{uuid.uuid4().hex[:8]}"
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)

        v1_draft = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(key, configuration_key=key, gst_rate="18.00"),
            headers=admin_headers,
        ).json()
        client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{v1_draft['configuration_id']}/publish",
            headers=admin_headers,
        )

        attendee_headers = _bearer(_REGISTERING_ALUMNI)
        reg = client.post(f"/api/v1/events/{event_id}/register", json={}, headers=attendee_headers).json()
        order = client.post(
            f"/api/v1/registrations/{reg['registration_id']}/payment-order",
            json={"idempotency_key": f"orderpin-key-{reg['registration_id']}"},
            headers=attendee_headers,
        ).json()
        assert order["final_amount"] == "118.00"

        v2_draft = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(key, configuration_key=key, gst_rate="5.00"),
            headers=admin_headers,
        ).json()
        client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{v2_draft['configuration_id']}/publish",
            headers=admin_headers,
        )

        order_after = client.get(f"/api/v1/payment-orders/{order['order_id']}", headers=attendee_headers).json()
        assert order_after["final_amount"] == "118.00"

        order_row = _db_fetch(
            "SELECT configuration_id, configuration_version FROM payment_orders WHERE public_order_number = $1",
            order["order_id"],
        )[0]
        assert order_row["configuration_id"] == v1_draft["configuration_id"]
        assert order_row["configuration_version"] == 1
    finally:
        _clear_bootstrap(monkeypatch)


def test_concurrent_publish_exactly_one_winner(client, monkeypatch):
    """Two different drafts for the same event race to publish. Exactly one
    must win (200); the other must get a clean 409, never a 500 — and the
    DB must end up with exactly one published row for the event."""
    from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

    event_id = _mk_unpaid_event(client, f"concpub-{uuid.uuid4().hex[:8]}")
    key = f"wp1-concpub-{uuid.uuid4().hex[:8]}"
    try:
        _as_platform_admin(monkeypatch)
        headers = _bearer(_PLATFORM_ADMIN)

        draft_a = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(key, configuration_key=key),
            headers=headers,
        ).json()
        draft_b = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload(key, configuration_key=key),
            headers=headers,
        ).json()
        assert draft_a["version"] == 1
        assert draft_b["version"] == 2

        def _publish(config_id):
            return client.post(
                f"/api/v1/admin/events/{event_id}/payment-configurations/{config_id}/publish",
                headers=headers,
            )

        with ThreadPoolExecutor(max_workers=2) as pool:
            f1 = pool.submit(_publish, draft_a["configuration_id"])
            f2 = pool.submit(_publish, draft_b["configuration_id"])
            try:
                r1, r2 = f1.result(timeout=10), f2.result(timeout=10)
            except FutureTimeoutError:
                pytest.fail("Concurrent publish hung past 10s.")

        statuses = sorted([r1.status_code, r2.status_code])
        # Two legitimate outcomes depending on whether the two publishes
        # actually overlap in time: full serialization (each one cleanly
        # retires the other's now-published row in turn -> [200, 200]) or a
        # genuine race caught by the partial unique index -> [200, 409].
        # Never a 500, and never two simultaneously-published rows — that
        # is the actual safety property, checked below regardless of which
        # status pair occurred.
        assert statuses in ([200, 200], [200, 409]), f"unexpected outcome: {statuses}"

        published_rows = _db_fetch(
            "SELECT id FROM payment_configurations WHERE event_id = $1 AND status = 'published'",
            event_id,
        )
        assert len(published_rows) == 1
    finally:
        _clear_bootstrap(monkeypatch)


def test_event_admin_scoped_to_own_event_only(client, monkeypatch):
    event_a = _mk_unpaid_event(client, f"scopea-{uuid.uuid4().hex[:8]}")
    event_b = _mk_unpaid_event(client, f"scopeb-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)

        r = client.post(
            f"/api/v1/admin/events/{event_a}/payment-admins",
            json={"firebase_uid": _EVENT_ADMIN["firebase_uid"]},
            headers=admin_headers,
        )
        assert r.status_code == 201, r.text

        event_admin_headers = _bearer(_EVENT_ADMIN)

        # Own event: allowed.
        r = client.post(
            f"/api/v1/admin/events/{event_a}/payment-configurations",
            json=_draft_payload(f"scope-own-{uuid.uuid4().hex[:6]}"),
            headers=event_admin_headers,
        )
        assert r.status_code == 201, r.text

        # A different event they were never granted on: denied.
        r = client.post(
            f"/api/v1/admin/events/{event_b}/payment-configurations",
            json=_draft_payload(f"scope-other-{uuid.uuid4().hex[:6]}"),
            headers=event_admin_headers,
        )
        assert r.status_code == 403
    finally:
        _clear_bootstrap(monkeypatch)


# ─────────────────────────────────────────────────────────────────────────────
# C. TEST/LIVE mode separation — publish-time gates
# ─────────────────────────────────────────────────────────────────────────────

def test_live_draft_can_be_created_without_live_credentials(client, monkeypatch):
    """Preparing a LIVE draft ahead of receiving real Live credentials must
    be possible — that is the whole point of "prepare LIVE mode safely"
    (spec §7/§20). Only *publishing* LIVE requires credentials; drafting it
    does not."""
    fakes.clear_razorpay_env(monkeypatch)
    event_id = _mk_unpaid_event(client, f"livedraftok-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        headers = _bearer(_PLATFORM_ADMIN)
        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload("livedraftok", gateway="razorpay", payment_mode="live"),
            headers=headers,
        )
        assert r.status_code == 201, r.text
        assert r.json()["payment_mode"] == "live"
        assert r.json()["status"] == "draft"
    finally:
        _clear_bootstrap(monkeypatch)


def test_razorpay_draft_below_one_rupee_is_rejected(client, monkeypatch):
    event_id = _mk_unpaid_event(client, f"rzpmin-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload("rzpmin", gateway="razorpay", payment_mode="test",
                                base_amount="0.99", gst_enabled=False),
            headers=_bearer(_PLATFORM_ADMIN),
        )
        assert r.status_code == 422, r.text
        assert any(_MIN_AMOUNT_ERROR in e for e in r.json()["detail"]["errors"])
    finally:
        _clear_bootstrap(monkeypatch)


def test_live_publish_rejected_without_live_credentials_even_for_platform_admin(client, monkeypatch):
    fakes.clear_razorpay_env(monkeypatch)
    event_id = _mk_unpaid_event(client, f"livenocreds-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        headers = _bearer(_PLATFORM_ADMIN)
        draft = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload("livenocreds", gateway="razorpay", payment_mode="live"),
            headers=headers,
        ).json()
        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{draft['configuration_id']}/publish",
            headers=headers,
        )
        assert r.status_code == 422, r.text
        assert any("RAZORPAY_MODE=live" in e for e in r.json()["detail"]["errors"])
    finally:
        _clear_bootstrap(monkeypatch)


def test_live_publish_requires_platform_admin_not_just_event_admin(client, monkeypatch):
    """Even with valid Live credentials configured, an event_admin (who is
    sufficient for every other publish) must not be able to publish a LIVE
    config — only platform_admin may."""
    fakes.set_razorpay_live_env(monkeypatch)
    event_id = _mk_unpaid_event(client, f"liverbac-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        client.post(
            f"/api/v1/admin/events/{event_id}/payment-admins",
            json={"firebase_uid": _EVENT_ADMIN["firebase_uid"]},
            headers=admin_headers,
        )
        event_admin_headers = _bearer(_EVENT_ADMIN)
        draft = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload("liverbac", gateway="razorpay", payment_mode="live"),
            headers=event_admin_headers,
        ).json()
        assert draft["payment_mode"] == "live"

        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{draft['configuration_id']}/publish",
            headers=event_admin_headers,
        )
        assert r.status_code == 403, r.text
        assert r.json()["detail"] == "live_publish_requires_platform_admin"

        r2 = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{draft['configuration_id']}/publish",
            headers=admin_headers,
        )
        assert r2.status_code == 200, r2.text
        assert r2.json()["status"] == "published"
        assert r2.json()["real_money"] is True
    finally:
        _clear_bootstrap(monkeypatch)


def test_test_mode_publish_does_not_require_platform_admin(client, monkeypatch):
    """Sanity check that the new LIVE-only gate didn't accidentally tighten
    the existing TEST-mode publish path — event_admin remains sufficient."""
    event_id = _mk_unpaid_event(client, f"testrbac-{uuid.uuid4().hex[:8]}")
    try:
        _as_platform_admin(monkeypatch)
        admin_headers = _bearer(_PLATFORM_ADMIN)
        client.post(
            f"/api/v1/admin/events/{event_id}/payment-admins",
            json={"firebase_uid": _EVENT_ADMIN["firebase_uid"]},
            headers=admin_headers,
        )
        event_admin_headers = _bearer(_EVENT_ADMIN)
        draft = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations",
            json=_draft_payload("testrbac", gateway="razorpay", payment_mode="test"),
            headers=event_admin_headers,
        ).json()
        r = client.post(
            f"/api/v1/admin/events/{event_id}/payment-configurations/{draft['configuration_id']}/publish",
            headers=event_admin_headers,
        )
        assert r.status_code == 200, r.text
        assert r.json()["real_money"] is False
    finally:
        _clear_bootstrap(monkeypatch)
