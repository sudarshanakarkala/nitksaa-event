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


# ── Attachments ───────────────────────────────────────────────────────────────
import base64  # noqa: E402

_PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
_JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
_MOV = b"\x00\x00\x00\x14ftypqt  " + b"\x00" * 64
_HEIC = b"\x00\x00\x00\x18ftypheic" + b"\x00" * 64
_PDF = b"%PDF-1.7\n" + b"\x00" * 64


def _file(data, filename="screenshot.png", content_type="image/png"):
    return {"filename": filename, "content_type": content_type,
            "data_base64": base64.b64encode(data).decode()}


def _attached(msg):
    return [(p.get_filename(), p.get_content_type(), p.get_payload(decode=True))
            for p in msg.iter_attachments()]


def test_feedback_with_attachments_sends_mixed_email(client, smtp):
    files = [_file(_PNG), _file(_MOV, "Screen Recording.mov", "video/quicktime"),
             _file(_HEIC, "IMG_0001.HEIC", "image/heic")]
    r = client.post(_PATH, json=_body(attachments=files), headers=_bearer(_ATTENDEE))
    assert r.status_code == 204, r.text
    (msg, _, _), = smtp
    assert msg.get_content_type() == "multipart/mixed"
    assert _attached(msg) == [
        ("screenshot.png", "image/png", _PNG),
        ("Screen Recording.mov", "video/quicktime", _MOV),
        ("IMG_0001.heic", "image/heic", _HEIC),
    ]
    # The text and HTML parts are still there, and list the files.
    plain = msg.get_body(preferencelist=("plain",)).get_content()
    page = msg.get_body(preferencelist=("html",)).get_content()
    assert "I paid but My Events" in plain
    assert "Attached: screenshot.png" in plain and "Screen Recording.mov" in page


def test_feedback_without_attachments_is_unchanged(client, smtp):
    for extra in ({}, {"attachments": None}, {"attachments": []}):
        r = client.post(_PATH, json=_body(**extra), headers=_bearer(_ATTENDEE))
        assert r.status_code == 204, r.text
    assert all(m.get_content_type() == "multipart/alternative" for m, _, _ in smtp)


def test_feedback_type_comes_from_the_file_not_the_browser(client, smtp):
    # A JPEG called .png and sent as image/png is attached as a JPEG.
    r = client.post(_PATH, json=_body(attachments=[_file(_JPEG, "photo.png")]),
                    headers=_bearer(_ATTENDEE))
    assert r.status_code == 204, r.text
    assert _attached(smtp[0][0]) == [("photo.png.jpg", "image/jpeg", _JPEG)]


@pytest.mark.parametrize("files, code", [
    ([_file(_PNG)] * 4, "too_many_attachments"),
    ([_file(_PDF, "report.png")], "attachment_type_not_allowed"),
    ([{"filename": "a.png", "content_type": "image/png", "data_base64": "not base64!"}],
     "attachment_invalid"),
    ([{"filename": "a.png", "content_type": "image/png", "data_base64": ""}], "attachment_invalid"),
    ([{"filename": "a.png"}], "attachment_invalid"),
    ("not a list", "attachment_invalid"),
])
def test_feedback_refuses_bad_attachments(client, smtp, files, code):
    r = client.post(_PATH, json=_body(attachments=files), headers=_bearer(_ATTENDEE))
    assert r.status_code == 400
    assert r.json()["detail"] == code
    assert smtp == []


def test_feedback_size_limit_is_15_mb_in_total(client, smtp):
    from app.api.feedback import MAX_ATTACHMENT_BYTES

    half = _PNG + b"\x00" * (MAX_ATTACHMENT_BYTES // 2 - len(_PNG))
    rest = _PNG + b"\x00" * (MAX_ATTACHMENT_BYTES - len(half) - len(_PNG))
    ok = client.post(_PATH, json=_body(attachments=[_file(half), _file(rest)]),
                     headers=_bearer(_ATTENDEE))
    assert ok.status_code == 204, ok.text

    over = client.post(_PATH, json=_body(attachments=[_file(half), _file(rest + b"\x00")]),
                       headers=_bearer(_ATTENDEE))
    assert over.status_code == 400
    assert over.json()["detail"] == "attachment_too_large"
    assert len(smtp) == 1


def test_feedback_refusals_never_echo_file_data(client, smtp):
    marker = base64.b64encode(_PDF).decode()
    for body in (_body(attachments=[_file(_PDF)]),
                 _body(message="short", attachments=[_file(_PNG)]),
                 _body(attachments=[{"data_base64": 12345, "filename": marker}])):
        r = client.post(_PATH, json=body, headers=_bearer(_ATTENDEE))
        assert r.status_code in (400, 422)
        assert marker not in r.text and base64.b64encode(_PNG).decode() not in r.text


def test_feedback_502_log_names_files_but_not_contents(client, smtp, monkeypatch, caplog):
    from app.api import feedback

    def fail(*_):
        raise OSError("smtp down")

    monkeypatch.setattr(feedback, "_send", fail)
    r = client.post(_PATH, json=_body(attachments=[_file(_PNG)]), headers=_bearer(_ATTENDEE))
    assert r.status_code == 502
    assert "screenshot.png" in caplog.text
    assert base64.b64encode(_PNG).decode() not in caplog.text


@pytest.mark.parametrize("name, expected", [
    ("../../etc/passwd.png", "passwd.png"),
    ("C:\\Users\\me\\shot.PNG", "shot.png"),
    ("bad\x00name\n.png", "badname.png"),
    ("", "attachment-1.png"),
    (None, "attachment-1.png"),
    ("noext", "noext.png"),
    ("x" * 300 + ".png", "x" * 96 + ".png"),
    ("स्क्रीनशॉट.png", "स्क्रीनशॉट.png"),
])
def test_safe_filename(name, expected):
    from app.api.feedback import safe_filename

    assert safe_filename(name, "png", 1) == expected
