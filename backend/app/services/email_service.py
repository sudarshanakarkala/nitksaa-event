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


# ── General sending (refund notifications, admin alerts) ────────────────────

async def send_email(email_to: str, subject: str, plain: str, html: str) -> EmailResult:
    """Send one email (same modes and safety as the confirmation email).
    Never raises. Addresses ending in example.invalid (demo data) are
    skipped, so demo people are never emailed."""
    settings = get_settings()
    if not email_to or email_to.lower().endswith("example.invalid"):
        return EmailResult(status="skipped", sent_at=None, error="no deliverable address")
    if settings.email_mode == "log":
        _log.info("[email/log] to=%s subject=%r", email_to, subject)
        return EmailResult(status="sent", sent_at=datetime.now(timezone.utc), error=None)
    if settings.email_mode != "send":
        return EmailResult(status="skipped", sent_at=None, error=f"unknown mode: {settings.email_mode}")
    from_addr = settings.email_from or settings.smtp_user
    if not from_addr or not settings.smtp_user or not settings.smtp_password:
        _log.error("[email] smtp credentials not configured")
        return EmailResult(status="failed", sent_at=None, error="smtp credentials not configured")
    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = from_addr
        msg["To"] = email_to
        if settings.email_reply_to:
            msg["Reply-To"] = settings.email_reply_to
        msg.attach(MIMEText(plain, "plain"))
        msg.attach(MIMEText(html, "html"))
        await asyncio.to_thread(
            _send_smtp_sync, msg.as_string(), settings.smtp_host, settings.smtp_port,
            settings.smtp_user, settings.smtp_password, from_addr, email_to,
        )
        return EmailResult(status="sent", sent_at=datetime.now(timezone.utc), error=None)
    except Exception as exc:  # noqa: BLE001 — never raise from email
        _log.error("[email] send failed to=%s: %s", email_to, type(exc).__name__)
        return EmailResult(status="failed", sent_at=None, error=type(exc).__name__)


def _esc(text: str) -> str:
    import html as _html
    return _html.escape(str(text or ""))


def _refund_lines(d: dict) -> list:
    lines = [
        ("Event", d.get("event_title")),
        ("Amount", d.get("amount")),
        ("Refund reference", d.get("refund_number")),
        ("Payment reference", d.get("payment_reference")),
        ("Bank reference", d.get("bank_reference")),
    ]
    return [(k, v) for k, v in lines if v]


def _render(greeting: str, paragraphs: list, details: list) -> tuple:
    plain = "\n\n".join([greeting, *paragraphs]) + "\n\n" + "\n".join(f"{k}: {v}" for k, v in details) \
        + "\n\n— NITKSAA Team"
    html_rows = "".join(f"<tr><td>{_esc(k)}</td><td><strong>{_esc(v)}</strong></td></tr>" for k, v in details)
    html_body = "".join(f"<p>{_esc(p)}</p>" for p in paragraphs)
    html = (f"<html><body><p>{_esc(greeting)}</p>{html_body}"
            f"<table cellpadding='4'>{html_rows}</table><p>— NITKSAA Team</p></body></html>")
    return plain, html


async def send_refund_delayed_email(email_to: str, d: dict) -> EmailResult:
    plain, html = _render(
        f"Hi {d.get('fullname') or 'there'},",
        [f"Your registration for {d.get('event_title')} is cancelled. Your refund couldn't be sent yet because "
         "of a temporary issue with the payment provider.",
         "We're retrying automatically and will email you as soon as it's on its way. You don't need to do anything."],
        _refund_lines(d),
    )
    return await send_email(email_to, f"Your refund is delayed — {d.get('event_title')}", plain, html)


async def send_refund_processed_email(email_to: str, d: dict) -> EmailResult:
    paragraphs = [f"Your refund for {d.get('event_title')} has been sent. Banks usually show it within 5–7 working days."]
    if d.get("bank_reference"):
        paragraphs.append("If it doesn't appear, give your bank the bank reference below.")
    plain, html = _render(f"Hi {d.get('fullname') or 'there'},", paragraphs, _refund_lines(d))
    return await send_email(email_to, f"Your refund has been sent — {d.get('event_title')}", plain, html)


async def send_refund_failed_email(email_to: str, d: dict) -> EmailResult:
    plain, html = _render(
        f"Hi {d.get('fullname') or 'there'},",
        [f"Your registration for {d.get('event_title')} is cancelled, but we couldn't send your refund automatically.",
         "Someone from NITKSAA will contact you within 2 working days. Please quote your refund reference."],
        _refund_lines(d),
    )
    return await send_email(email_to, f"About your refund — {d.get('event_title')}", plain, html)


async def send_refund_admin_alert(email_to: str, d: dict) -> EmailResult:
    details = _refund_lines(d) + [("Attendee", d.get("attendee")), ("Reason", d.get("reason_text")),
                                  ("Tries", d.get("attempts"))]
    plain, html = _render(
        "Hello,",
        [f"A refund for {d.get('event_title')} needs attention: it could not be sent automatically.",
         "Open Admin → Payments → Refunds to see it and retry, or refund the person another way."],
        [(k, v) for k, v in details if v],
    )
    return await send_email(email_to, f"Refund needs attention — {d.get('event_title')}", plain, html)
