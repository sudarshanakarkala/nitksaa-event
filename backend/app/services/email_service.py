"""Registration confirmation email service.

EMAIL_MODE=log  (default, development) — writes to Python logger, returns status='sent'.
EMAIL_MODE=send — sends via SMTP (smtplib); requires smtp_user, smtp_password in settings.

send_confirmation_email() never raises. Email failure returns a failed EmailResult
and must never roll back the registration transaction.
"""
import asyncio
import logging
import smtplib
from dataclasses import dataclass
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional

from app.config import get_settings

_log = logging.getLogger(__name__)


@dataclass
class EmailResult:
    status: str  # "sent" | "failed" | "skipped"
    sent_at: Optional[datetime]
    error: Optional[str]


def _build_plain(
    fullname: str,
    event_title: str,
    registration_number: str,
    join_url: Optional[str],
) -> str:
    join_line = (
        f"Virtual join link: {join_url}"
        if join_url
        else "This is an in-person event. Location details are on the event page."
    )
    return (
        f"Registration Confirmed\n\n"
        f"Hi {fullname},\n\n"
        f"Your registration for {event_title} is confirmed.\n"
        f"Registration number: {registration_number}\n\n"
        f"{join_line}\n\n"
        f"— NITKSAA Team"
    )


def _build_html(
    fullname: str,
    event_title: str,
    registration_number: str,
    join_url: Optional[str],
) -> str:
    join_section = (
        f'<p>Virtual join link: <a href="{join_url}">{join_url}</a></p>'
        if join_url
        else "<p>This is an in-person event. Location details are on the event page.</p>"
    )
    return f"""<html><body>
<h2>Registration Confirmed</h2>
<p>Hi {fullname},</p>
<p>Your registration for <strong>{event_title}</strong> is confirmed.</p>
<p>Registration number: <strong>{registration_number}</strong></p>
{join_section}
<p>— NITKSAA Team</p>
</body></html>"""


def _send_smtp_sync(
    msg_string: str,
    smtp_host: str,
    smtp_port: int,
    smtp_user: str,
    smtp_password: str,
    from_addr: str,
    email_to: str,
) -> None:
    """Synchronous SMTP send. Called via asyncio.to_thread to avoid blocking the event loop."""
    with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as smtp:
        smtp.starttls()
        smtp.login(smtp_user, smtp_password)
        smtp.sendmail(from_addr, [email_to], msg_string)


async def send_confirmation_email(
    email_to: str,
    fullname: str,
    event_title: str,
    registration_number: str,
    join_url: Optional[str] = None,
) -> EmailResult:
    """Send a confirmation email. Never raises."""
    settings = get_settings()
    mode = settings.email_mode

    if mode == "log":
        _log.info(
            "[email/log] confirmation to=%s reg=%s event=%r virtual=%s",
            email_to, registration_number, event_title, bool(join_url),
        )
        return EmailResult(status="sent", sent_at=datetime.now(timezone.utc), error=None)

    if mode != "send":
        _log.warning("[email] unknown EMAIL_MODE=%r — skipping send", mode)
        return EmailResult(status="skipped", sent_at=None, error=f"unknown mode: {mode}")

    from_addr = settings.email_from or settings.smtp_user
    if not from_addr or not settings.smtp_user or not settings.smtp_password:
        err = "smtp credentials not configured"
        _log.error("[email] %s", err)
        return EmailResult(status="failed", sent_at=None, error=err)

    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = f"Registration confirmed — {event_title}"
        msg["From"] = from_addr
        msg["To"] = email_to
        if settings.email_reply_to:
            msg["Reply-To"] = settings.email_reply_to
        msg.attach(MIMEText(_build_plain(fullname, event_title, registration_number, join_url), "plain"))
        msg.attach(MIMEText(_build_html(fullname, event_title, registration_number, join_url), "html"))

        await asyncio.to_thread(
            _send_smtp_sync,
            msg.as_string(),
            settings.smtp_host,
            settings.smtp_port,
            settings.smtp_user,
            settings.smtp_password,
            from_addr,
            email_to,
        )

        return EmailResult(status="sent", sent_at=datetime.now(timezone.utc), error=None)

    except Exception as exc:
        err = str(exc)
        _log.error("[email] send failed to=%s: %s", email_to, err)
        return EmailResult(status="failed", sent_at=None, error=err)
