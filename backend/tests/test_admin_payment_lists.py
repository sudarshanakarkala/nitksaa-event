"""Admin revamp step 9 — read-only order and refund lists for the Payments tab.

Checks who may call them and the response shape. Uses the fixture
identities and token helper from test_admin_rbac.py.
"""
import pytest

from tests.test_admin_rbac import (  # noqa: F401  (autouse fixture)
    _ATTENDEE,
    _FIXTURE_ADMIN,
    _bearer,
    _seed_test_identities,
)


@pytest.mark.parametrize("path", ["/api/v1/admin/payments/orders", "/api/v1/admin/payments/refunds"])
def test_payment_lists_deny_unauthenticated(client, path):
    assert client.get(path).status_code in (401, 403)


@pytest.mark.parametrize("path", ["/api/v1/admin/payments/orders", "/api/v1/admin/payments/refunds"])
def test_payment_lists_deny_plain_user(client, path):
    assert client.get(path, headers=_bearer(_ATTENDEE)).status_code == 403


def test_orders_shape_for_overall_admin(client):
    r = client.get("/api/v1/admin/payments/orders", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()
    assert {"orders", "total", "page", "per_page"} <= set(body)
    for o in body["orders"]:
        assert {"public_order_number", "event_id", "event_title", "final_amount",
                "status", "payment_mode", "created_at", "stuck"} <= set(o)


def test_refunds_shape_for_overall_admin(client):
    r = client.get("/api/v1/admin/payments/refunds", headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()
    assert {"refunds", "total", "page", "per_page"} <= set(body)
    for f in body["refunds"]:
        assert {"public_refund_number", "event_id", "amount", "status", "payment_mode"} <= set(f)
