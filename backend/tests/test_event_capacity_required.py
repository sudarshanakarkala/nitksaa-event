"""Every event has a capacity; there is no "unlimited" (decision, 11 Oct 2026).

EventCreate requires a positive capacity. EventUpdate lets a PATCH leave
capacity out, but rejects an explicit null, because update_event writes
model_dump(exclude_unset=True) and a null would otherwise reach the
database. Migration 025 makes events.capacity NOT NULL with CHECK > 0.

These are schema-level tests: they need no database. In the API, a
ValidationError from these models is FastAPI's 422.
"""
import pytest
from pydantic import ValidationError

from app.schemas.event_create import EventCreate
from app.schemas.event_update import EventUpdate

_BASE = {
    "title": "Capacity test",
    "description": "Created by pytest",
    "start_datetime": "2027-11-01T08:00:00+05:30",
    "end_datetime": "2027-11-01T10:00:00+05:30",
    "location_text": "Test Venue",
    "is_virtual": False,
}


def _errors(exc: ValidationError) -> str:
    return " | ".join(f"{e['loc']}: {e['msg']}" for e in exc.errors())


# ── Create ───────────────────────────────────────────────────────────────────

def test_create_without_capacity_is_rejected():
    with pytest.raises(ValidationError) as exc:
        EventCreate(**_BASE)
    assert "capacity" in _errors(exc.value)


def test_create_with_null_capacity_is_rejected():
    with pytest.raises(ValidationError) as exc:
        EventCreate(**_BASE, capacity=None)
    assert "capacity" in _errors(exc.value)


@pytest.mark.parametrize("bad", [0, -1])
def test_create_with_non_positive_capacity_is_rejected(bad):
    with pytest.raises(ValidationError) as exc:
        EventCreate(**_BASE, capacity=bad)
    assert "capacity" in _errors(exc.value)


def test_create_with_positive_capacity_is_accepted():
    assert EventCreate(**_BASE, capacity=50).capacity == 50


# ── Update (PATCH) ───────────────────────────────────────────────────────────

def test_patch_with_explicit_null_capacity_is_rejected():
    with pytest.raises(ValidationError) as exc:
        EventUpdate(capacity=None)
    assert "capacity cannot be empty" in _errors(exc.value)


def test_patch_without_capacity_leaves_it_unchanged():
    update = EventUpdate(title="New title")
    assert "capacity" not in update.model_dump(exclude_unset=True)


def test_patch_with_zero_capacity_is_rejected():
    with pytest.raises(ValidationError) as exc:
        EventUpdate(capacity=0)
    assert "capacity" in _errors(exc.value)


def test_patch_with_positive_capacity_is_accepted():
    assert EventUpdate(capacity=200).model_dump(exclude_unset=True) == {"capacity": 200}


# ── Over HTTP ────────────────────────────────────────────────────────────────

def test_api_create_without_capacity_is_422(client, monkeypatch):
    from tests.test_admin_event_management import _PLATFORM_ADMIN, _as_platform_admin, _bearer

    _as_platform_admin(monkeypatch)
    r = client.post("/api/v1/admin/events", json=_BASE, headers=_bearer(_PLATFORM_ADMIN))
    assert r.status_code == 422, r.text
    locs = [tuple(e["loc"]) for e in r.json()["detail"]]
    assert ("body", "capacity") in locs
