"""Admin revamp step 8 — GET /api/v1/admin/pending-count.

Checks who may call it and the response shape. The badge total counts only
the queues someone has to act on (drafts, failed emails, stuck payments,
failed refunds). Uses the same fixture identities and token helper as
test_admin_rbac.py.
"""
from tests.test_admin_rbac import (  # noqa: F401  (autouse fixture)
    _ATTENDEE,
    _FIXTURE_ADMIN,
    _bearer,
    _seed_test_identities,
)

_PATH = "/api/v1/admin/pending-count"

_QUEUES = {
    "drafts", "closing_soon", "near_capacity",
    "failed_emails", "stuck_payments", "failed_refunds",
}


def test_pending_count_denies_unauthenticated(client):
    assert client.get(_PATH).status_code in (401, 403)


def test_pending_count_denies_plain_user(client):
    r = client.get(_PATH, headers=_bearer(_ATTENDEE))
    assert r.status_code == 403


def test_pending_count_shape_for_overall_admin(client):
    r = client.get(_PATH, headers=_bearer(_FIXTURE_ADMIN))
    assert r.status_code == 200, r.text
    body = r.json()

    assert _QUEUES <= set(body)
    assert all(isinstance(body[q], int) and body[q] >= 0 for q in _QUEUES)
    assert body["total"] == (
        body["drafts"] + body["failed_emails"]
        + body["stuck_payments"] + body["failed_refunds"]
    )

    events = body["events"]
    assert len(events["closing_soon"]) == body["closing_soon"]
    assert len(events["near_capacity"]) == body["near_capacity"]
    assert sum(e["failed"] for e in events["failed_emails"]) == body["failed_emails"]
    for e in events["closing_soon"] + events["near_capacity"]:
        assert {"event_id", "title", "start_datetime", "capacity", "registered"} <= set(e)
