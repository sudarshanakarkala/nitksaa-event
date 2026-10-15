"""Feedback form: POST /api/v1/feedback (signed-in users).

The same contract as the website's feedback endpoint: {area, category,
message}, message 10-2000 characters, unknown area or category coerced to
the default. Emails FEEDBACK_EMAIL_TO (nitksaa.infra@gmail.com) through the
SMTP settings (SMTP_USER / SMTP_PASSWORD), whatever EMAIL_MODE says: the
attendee emails stay off while feedback still arrives. Reply-To is the
sender, so a reply goes straight to them.

204 on success; 502 when the email can't be sent (the app then shows
"please email us"); 503 when SMTP isn't configured.
"""
import asyncio
import html
import logging
import smtplib
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr
from typing import Any, Dict, Optional

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


class FeedbackRequest(BaseModel):
    message: str
    category: str = "other"
    area: str = "general"
    source: Optional[str] = None

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


def _send(msg: MIMEMultipart, sender: str, to: str) -> None:
    """Gmail SMTP (STARTTLS). Raises on failure. Run in a thread."""
    s = get_settings()
    with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=10) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.login(s.smtp_user, s.smtp_password)
        smtp.sendmail(sender, [to], msg.as_string())


def build_message(body: FeedbackRequest, user: Dict[str, Any], sender: str, to: str) -> MIMEMultipart:
    area = AREA_LABELS[body.area]
    category = CATEGORY_LABELS[body.category]
    when = datetime.now(timezone.utc).strftime("%d %b %Y, %H:%M UTC")
    email = user.get("email") or "—"
    name = user.get("fullname") or "—"
    kind = "Alumni" if (user.get("user_type") or "").lower() == "alumni" else "Non-alumni"
    ref = user.get("ref_id") or "—"

    msg = MIMEMultipart("alternative")
    msg["Subject"] = f"[NITKSAA Events Feedback] {area} — {category}"
    msg["From"] = formataddr(("NITKSAA Events", sender))
    msg["To"] = to
    if user.get("email"):
        msg["Reply-To"] = formataddr((user.get("fullname") or "", user["email"]))

    text = (
        f"Area: {area}  |  Type: {category}\n"
        f"Submitted: {when}\n"
        f"From: {name} <{email}>  |  {kind}  |  {ref}\n"
        f"\n---\n{body.message}\n"
    )
    e = html.escape
    rows = "".join(
        f'<tr><td style="padding:4px 12px 4px 0;color:#666">{k}</td>'
        f'<td style="padding:4px 0">{e(v)}</td></tr>'
        for k, v in [("Area", area), ("Type", category), ("Submitted", when),
                     ("Name", name), ("Email", email), ("Who", kind), ("ID", ref)]
    )
    page = f"""<html><body style="font-family:sans-serif;color:#222;max-width:600px">
<h2 style="color:#0f2744;border-bottom:2px solid #c9a84c;padding-bottom:8px">NITKSAA Events feedback</h2>
<table style="border-collapse:collapse;margin-bottom:16px">{rows}</table>
<div style="background:#f5f3ef;border-left:4px solid #c9a84c;padding:16px;border-radius:4px;white-space:pre-wrap;font-size:15px">{e(body.message)}</div>
<p style="color:#999;font-size:12px;margin-top:24px">Sent from the NITKSAA Events app. Reply to this email to answer the sender.</p>
</body></html>"""
    msg.attach(MIMEText(text, "plain", "utf-8"))
    msg.attach(MIMEText(page, "html", "utf-8"))
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
    sender = s.email_from or s.smtp_user
    msg = build_message(body, user, sender, s.feedback_email_to)
    try:
        await asyncio.to_thread(_send, msg, sender, s.feedback_email_to)
    except Exception as exc:  # noqa: BLE001 — any SMTP failure is a 502
        # Keep the feedback in the server log so it isn't lost.
        _log.error("Feedback email failed (%s) from %s: %s", exc, user.get("email"), body.message)
        raise HTTPException(status_code=502, detail="feedback_send_failed")
    return Response(status_code=204)
