"""POST /api/v1/feedback: the events app's feedback form.

SMTP is faked: the tests check who may send, the checks on the message, and
what goes into the email (to, Reply-To, subject, escaped body). Uses the
fixture identities and token helper from test_admin_rbac.py.
"""
import pytest

from tests.test_admin_rbac import (  # noqa: F401  (autouse fixture)
    _ATTENDEE,
    _bearer,
    _seed_test_identities,
)

_PATH = "/api/v1/feedback"


@pytest.fixture
def smtp(monkeypatch):
    """SMTP configured and faked; returns the list of sent messages."""
    from app.api import feedback
    from app.config import get_settings

    monkeypatch.setenv("SMTP_USER", "nitksaa.infra@gmail.com")
    monkeypatch.setenv("SMTP_PASSWORD", "app-password")
    monkeypatch.setenv("EMAIL_MODE", "log")  # attendee emails off; feedback still sends
    get_settings.cache_clear()
    sent = []
    monkeypatch.setattr(feedback, "_send", lambda msg, sender, to: sent.append((msg, sender, to)))
    yield sent
    get_settings.cache_clear()


def _body(**kw):
    return {"area": "registration", "category": "bug",
            "message": "I paid but My Events doesn't show it.", **kw}


def test_feedback_needs_sign_in(client, smtp):
    assert client.post(_PATH, json=_body()).status_code in (401, 403)
    assert smtp == []


def test_feedback_sends_email(client, smtp):
    r = client.post(_PATH, json=_body(message="<b>Paid</b> but nothing shows & no QR"),
                    headers=_bearer(_ATTENDEE))
    assert r.status_code == 204, r.text
    (msg, sender, to), = smtp
    assert to == "nitksaa.infra@gmail.com"
    assert sender == "nitksaa.infra@gmail.com"
    assert msg["Subject"] == "[NITKSAA Events Feedback] Registration / payment — Something is broken"
    assert _ATTENDEE["email"] in msg["Reply-To"]
    plain, page = [p.get_payload(decode=True).decode() for p in msg.get_payload()]
    assert "<b>Paid</b> but nothing shows & no QR" in plain
    assert "&lt;b&gt;Paid&lt;/b&gt;" in page  # the message is escaped in the HTML


def test_feedback_unknown_area_and_type_become_defaults(client, smtp):
    r = client.post(_PATH, json=_body(area="nope", category="nope"), headers=_bearer(_ATTENDEE))
    assert r.status_code == 204, r.text
    assert smtp[0][0]["Subject"] == "[NITKSAA Events Feedback] General / Platform — Other"


@pytest.mark.parametrize("message", ["too short", "x" * 2001])
def test_feedback_checks_length(client, smtp, message):
    r = client.post(_PATH, json=_body(message=message), headers=_bearer(_ATTENDEE))
    assert r.status_code == 422
    assert smtp == []


def test_feedback_502_when_email_fails(client, smtp, monkeypatch):
    from app.api import feedback

    def fail(*_):
        raise OSError("smtp down")

    monkeypatch.setattr(feedback, "_send", fail)
    r = client.post(_PATH, json=_body(), headers=_bearer(_ATTENDEE))
    assert r.status_code == 502


def test_feedback_503_without_smtp(client, monkeypatch):
    from app.config import get_settings

    monkeypatch.delenv("SMTP_USER", raising=False)
    monkeypatch.setenv("SMTP_PASSWORD", "")
    get_settings.cache_clear()
    try:
        r = client.post(_PATH, json=_body(), headers=_bearer(_ATTENDEE))
        assert r.status_code == 503
    finally:
        get_settings.cache_clear()
