"""Feedback form: POST /api/v1/feedback (signed-in users).

The same contract as the website's feedback endpoint: {area, category,
message}, message 10-2000 characters, unknown area or category coerced to
the default. Emails FEEDBACK_EMAIL_TO (nitksaa.infra@gmail.com) through the
SMTP settings (SMTP_USER / SMTP_PASSWORD), whatever EMAIL_MODE says: the
attendee emails stay off while feedback still arrives. Reply-To is the
sender, so a reply goes straight to them.

Attachments (optional): up to 3 screenshots or short recordings, 15 MB in
total, sent as `attachments: [{filename, content_type, data_base64}]` and
attached to the email. Nothing is stored. The server checks the count, the
size (before and after decoding) and the file's own first bytes; the type the
browser sent is ignored. Refusals are 400 with `too_many_attachments`,
`attachment_too_large`, `attachment_type_not_allowed` or `attachment_invalid`.
Attachments are checked by hand, not by the request model, so a refused
request never echoes file data back in a 422.

204 on success; 502 when the email can't be sent (the app then shows
"please email us"); 503 when SMTP isn't configured.
"""
import asyncio
import base64
import binascii
import html
import logging
import os
import re
import smtplib
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone
from email.message import EmailMessage
from email.utils import formataddr
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, field_validator

from app.config import get_settings
from app.middleware.auth import get_current_user

_log = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["feedback"])

AREA_LABELS = {
    "events": "Events list",
    "event_details": "Event details",
    "registration": "Registration / payment",
    "my_events": "My Events / badge",
    "account": "My Account / Sign-in",
    "general": "General / Platform",
}

CATEGORY_LABELS = {
    "bug": "Something is broken",
    "suggestion": "Suggestion / feature request",
    "data": "My data is wrong",
    "other": "Other",
}

MAX_ATTACHMENTS = 3
MAX_ATTACHMENT_BYTES = 15 * 1024 * 1024  # decoded total; ~20 MB in the email
# base64 of the total, plus a little slack for padding on each file.
_MAX_BASE64_CHARS = (MAX_ATTACHMENT_BYTES + 2) // 3 * 4 + 4 * MAX_ATTACHMENTS
_MAX_FILENAME = 100

# Detected type → (MIME type, extensions a filename may keep).
_TYPES = {
    "png": ("image/png", (".png",)),
    "jpeg": ("image/jpeg", (".jpg", ".jpeg")),
    "gif": ("image/gif", (".gif",)),
    "webp": ("image/webp", (".webp",)),
    "heic": ("image/heic", (".heic", ".heif")),
    "mp4": ("video/mp4", (".mp4", ".m4v")),
    "mov": ("video/quicktime", (".mov",)),
    "webm": ("video/webm", (".webm",)),
}
_HEIC_BRANDS = {b"heic", b"heix", b"hevc", b"hevx", b"heim", b"heis", b"mif1", b"msf1"}


class FeedbackRequest(BaseModel):
    message: str
    category: str = "other"
    area: str = "general"
    source: Optional[str] = None
    # Checked by _attachments(), not here: see the module docstring.
    attachments: Any = None

    @field_validator("message")
    @classmethod
    def _message(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 10:
            raise ValueError("Message must be at least 10 characters")
        if len(v) > 2000:
            raise ValueError("Message must be under 2000 characters")
        return v

    @field_validator("category")
    @classmethod
    def _category(cls, v: str) -> str:
        return v if v in CATEGORY_LABELS else "other"

    @field_validator("area")
    @classmethod
    def _area(cls, v: str) -> str:
        return v if v in AREA_LABELS else "general"


@dataclass
class Attachment:
    filename: str
    content_type: str
    data: bytes


def detect_type(data: bytes) -> Optional[str]:
    """The file's type from its first bytes, or None if it isn't allowed."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data.startswith(b"\x1a\x45\xdf\xa3"):
        return "webm"
    if data[4:8] == b"ftyp":
        brand = data[8:12]
        if brand in _HEIC_BRANDS:
            return "heic"
        if brand == b"qt  ":
            return "mov"
        if brand in (b"avif", b"avis", b"crx "):
            return None
        return "mp4"
    return None


def safe_filename(name: Any, kind: str, index: int) -> str:
    """The sender's file name without paths or control characters, at most
    100 characters, ending in an extension that matches the file's type."""
    raw = name if isinstance(name, str) else ""
    raw = raw.replace("\\", "/").rsplit("/", 1)[-1]
    raw = "".join(c for c in unicodedata.normalize("NFC", raw)
                  if unicodedata.category(c)[0] != "C")
    raw = re.sub(r"\s+", " ", raw).strip(" .")
    stem, ext = os.path.splitext(raw)
    allowed = _TYPES[kind][1]
    if ext.lower() not in allowed:
        stem, ext = raw, allowed[0]
    stem = stem[: _MAX_FILENAME - len(ext)].strip(" .")
    return f"{stem or f'attachment-{index}'}{ext.lower()}"


def _refuse(code: str) -> HTTPException:
    return HTTPException(status_code=400, detail=code)


def parse_attachments(raw: Any) -> List[Attachment]:
    """Checks and decodes the attachments. Raises a 400 with a code."""
    if raw is None:
        return []
    if not isinstance(raw, list):
        raise _refuse("attachment_invalid")
    if len(raw) > MAX_ATTACHMENTS:
        raise _refuse("too_many_attachments")
    items = []
    for item in raw:
        if not isinstance(item, dict) or not isinstance(item.get("data_base64"), str):
            raise _refuse("attachment_invalid")
        items.append(item)
    # Refuse an oversized total before decoding anything.
    if sum(len(i["data_base64"]) for i in items) > _MAX_BASE64_CHARS:
        raise _refuse("attachment_too_large")

    out: List[Attachment] = []
    total = 0
    for index, item in enumerate(items, start=1):
        try:
            data = base64.b64decode(item["data_base64"], validate=True)
        except (binascii.Error, ValueError):
            raise _refuse("attachment_invalid")
        if not data:
            raise _refuse("attachment_invalid")
        total += len(data)
        if total > MAX_ATTACHMENT_BYTES:
            raise _refuse("attachment_too_large")
        kind = detect_type(data)
        if kind is None:
            raise _refuse("attachment_type_not_allowed")
        out.append(Attachment(
            filename=safe_filename(item.get("filename"), kind, index),
            content_type=_TYPES[kind][0],
            data=data,
        ))
    return out


def _size(n: int) -> str:
    if n >= 1024 * 1024:
        return f"{n / (1024 * 1024):.1f} MB"
    return f"{max(1, round(n / 1024))} KB"


def _send(msg: EmailMessage, sender: str, to: str) -> None:
    """Gmail SMTP (STARTTLS). Raises on failure. Run in a thread.

    The timeout is a socket timeout, and Python counts it over the whole of a
    large send, so emails with files get longer.
    """
    s = get_settings()
    timeout = 120 if msg.is_multipart() and msg.get_content_type() == "multipart/mixed" else 10
    with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=timeout) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.login(s.smtp_user, s.smtp_password)
        smtp.sendmail(sender, [to], msg.as_bytes())


def build_message(
    body: FeedbackRequest,
    user: Dict[str, Any],
    sender: str,
    to: str,
    attachments: Optional[List[Attachment]] = None,
) -> EmailMessage:
    attachments = attachments or []
    area = AREA_LABELS[body.area]
    category = CATEGORY_LABELS[body.category]
    when = datetime.now(timezone.utc).strftime("%d %b %Y, %H:%M UTC")
    email = user.get("email") or "—"
    name = user.get("fullname") or "—"
    kind = "Alumni" if (user.get("user_type") or "").lower() == "alumni" else "Non-alumni"
    ref = user.get("ref_id") or "—"

    msg = EmailMessage()
    msg["Subject"] = f"[NITKSAA Events Feedback] {area} — {category}"
    msg["From"] = formataddr(("NITKSAA Events", sender))
    msg["To"] = to
    if user.get("email"):
        msg["Reply-To"] = formataddr((user.get("fullname") or "", user["email"]))

    files = ", ".join(f"{a.filename} ({_size(len(a.data))})" for a in attachments)
    text = (
        f"Area: {area}  |  Type: {category}\n"
        f"Submitted: {when}\n"
        f"From: {name} <{email}>  |  {kind}  |  {ref}\n"
        + (f"Attached: {files}\n" if attachments else "")
        + f"\n---\n{body.message}\n"
    )
    e = html.escape
    fields = [("Area", area), ("Type", category), ("Submitted", when),
              ("Name", name), ("Email", email), ("Who", kind), ("ID", ref)]
    if attachments:
        fields.append(("Attached", files))
    rows = "".join(
        f'<tr><td style="padding:4px 12px 4px 0;color:#666">{k}</td>'
        f'<td style="padding:4px 0">{e(v)}</td></tr>'
        for k, v in fields
    )
    page = f"""<html><body style="font-family:sans-serif;color:#222;max-width:600px">
<h2 style="color:#0f2744;border-bottom:2px solid #c9a84c;padding-bottom:8px">NITKSAA Events feedback</h2>
<table style="border-collapse:collapse;margin-bottom:16px">{rows}</table>
<div style="background:#f5f3ef;border-left:4px solid #c9a84c;padding:16px;border-radius:4px;white-space:pre-wrap;font-size:15px">{e(body.message)}</div>
<p style="color:#999;font-size:12px;margin-top:24px">Sent from the NITKSAA Events app. Reply to this email to answer the sender.</p>
</body></html>"""
    msg.set_content(text, subtype="plain", charset="utf-8")
    msg.add_alternative(page, subtype="html", charset="utf-8")
    for a in attachments:
        maintype, subtype = a.content_type.split("/", 1)
        msg.add_attachment(a.data, maintype=maintype, subtype=subtype, filename=a.filename)
    return msg


@router.post("/feedback", status_code=204)
async def submit_feedback(
    body: FeedbackRequest,
    user: Dict[str, Any] = Depends(get_current_user),
) -> Response:
    s = get_settings()
    if not s.smtp_user or not s.smtp_password:
        _log.error("Feedback not sent: SMTP_USER / SMTP_PASSWORD not configured")
        raise HTTPException(status_code=503, detail="feedback_not_configured")
    attachments = parse_attachments(body.attachments)
    body.attachments = None  # the decoded copies are all we need from here
    sender = s.email_from or s.smtp_user
    msg = build_message(body, user, sender, s.feedback_email_to, attachments)
    try:
        await asyncio.to_thread(_send, msg, sender, s.feedback_email_to)
    except Exception as exc:  # noqa: BLE001 — any SMTP failure is a 502
        # Keep the feedback in the server log so it isn't lost (file names
        # and sizes only, never the files).
        files = ", ".join(f"{a.filename} ({_size(len(a.data))})" for a in attachments) or "none"
        _log.error("Feedback email failed (%s) from %s, files: %s: %s",
                   exc, user.get("email"), files, body.message)
        raise HTTPException(status_code=502, detail="feedback_send_failed")
    return Response(status_code=204)
