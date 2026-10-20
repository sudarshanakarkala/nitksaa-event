"""Event branding: logos for light and dark backgrounds and a page
colour (stored as brand_accent).

All optional: an event without them reads as before (nulls). Set with the
event's PATCH, shown on the admin and public event; the accent must be
#RRGGBB; blank logos clear them.
"""
from tests.test_event_links import _draft, _publish
from tests.test_payment_refunds import (
    _FIXTURE_ADMIN,
    _bearer,
    _seed,  # noqa: F401  (autouse fixture: the test users and admin)
)

_BRAND = {
    "brand_logo_url": "/brand/nitkonnect/logo.png",
    "brand_logo_dark_url": "/brand/nitkonnect/logo_white.png",
    "brand_accent": "#2A1A4F",
}


def _patch(client, eid, body):
    return client.patch(f"/api/v1/events/{eid}", json=body,
                        headers=_bearer(_FIXTURE_ADMIN))


def test_an_event_without_branding_reads_nulls(client):
    ev = _draft(client)
    for key in _BRAND:
        assert ev[key] is None


def test_branding_is_saved_and_shown_publicly(client):
    ev = _draft(client)
    r = _patch(client, ev["event_id"], _BRAND)
    assert r.status_code == 200, r.text
    saved = r.json()["event"]
    for key, value in _BRAND.items():
        assert saved[key] == value

    _publish(client, ev["event_id"])
    public = client.get(f"/api/v1/events/public/{ev['event_id']}")
    assert public.status_code == 200, public.text
    body = public.json()
    event = body.get("event", body)
    for key, value in _BRAND.items():
        assert event[key] == value


def test_a_bad_accent_is_refused(client):
    ev = _draft(client)
    for bad in ["yellow", "#FFF", "FEEF00", "#GGGGGG"]:
        r = _patch(client, ev["event_id"], {"brand_accent": bad})
        assert r.status_code == 422, (bad, r.text)


def test_branding_can_be_cleared(client):
    ev = _draft(client)
    _patch(client, ev["event_id"], _BRAND)
    r = _patch(client, ev["event_id"], {
        "brand_logo_url": "  ", "brand_logo_dark_url": None, "brand_accent": None,
    })
    assert r.status_code == 200, r.text
    saved = r.json()["event"]
    for key in _BRAND:
        assert saved[key] is None
