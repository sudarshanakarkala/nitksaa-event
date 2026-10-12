"""Admin revamp step 7 — GET /api/v1/admin/dashboard.

Read-only summary. Checks who may call it, the response shape for each
period, and that a plain user is refused. Uses the same fixture identities
and token helper as test_admin_rbac.py.
"""
import pytest

from tests.test_admin_rbac import (  # noqa: F401  (autouse fixture)
    _ATTENDEE,
    _FIXTURE_ADMIN,
    _bearer,
    _seed_test_identities,
)

_PATH = "/api/v1/admin/dashboard"


def test_dashboard_denies_unauthenticated(client):
    assert client.get(_PATH).status_code in (401, 403)


def test_dashboard_denies_plain_user(client):
    r = client.get(_PATH, headers=_bearer(_ATTENDEE))
    assert r.status_code == 403


def test_dashboard_rejects_unknown_period(client):
    r = client.get(_PATH, params={"period": "decade"}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 422


@pytest.mark.parametrize("period", ["30d", "90d", "year", "all"])
def test_dashboard_shape_for_overall_admin(client, period):
    r = client.get(_PATH, params={"period": period}, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()

    assert body["period"] == period
    assert (body["since"] is None) == (period == "all")
    assert set(body["tiles"]) == {
        "upcoming_events", "registrations", "cancellations", "money_collected",
    }
    assert len(body["weekly"]) == 12
    assert all({"week", "registrations", "cancellations"} <= set(w) for w in body["weekly"])
    assert len(body["upcoming"]) <= 8
    assert len(body["recent"]) <= 5
    for row in body["upcoming"]:
        assert {"event_id", "title", "start_datetime", "capacity", "registered",
                "new_7d", "checked_in", "registration_status"} <= set(row)
    for row in body["recent"]:
        assert row["no_shows"] == max(row["registered"] - row["checked_in"], 0)
    for row in body["by_decade"]:
        assert row["decade"] % 10 == 0
