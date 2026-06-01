"""
backend/src/services/notify.py

Single-function notification & audit plumbing.
Callers only ever import and call emit(). Everything else is internal.

Three internal layers — all exceptions swallowed to protect the primary request:
  _write_audit    — always; fires even when recipient_uid is None
  _write_in_app   — when recipient_uid is set
  _dispatch_push  — when recipient_uid is set + Gmail configured + user not muted
                    Email is dispatched in a background thread so it never
                    blocks the HTTP response.
"""

import logging
import smtplib
import threading
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from config.settings import settings
from services.db import get_db

logger = logging.getLogger(__name__)

_GMAIL_FROM = "nitksaa.infra@gmail.com"
_SMTP_HOST  = "smtp.gmail.com"
_SMTP_PORT  = 587

# ---------------------------------------------------------------------------
# Message templates — (title, plain_message) for in-app notifications
# Push emails use _build_email_body() for rich HTML matching the portal style
# ---------------------------------------------------------------------------

_TEMPLATES: dict[str, tuple[str, str]] = {
    "contact_request_received":   ("New connection request",              "{sender_name} wants to connect with you"),
    "contact_request_accepted":   ("Connection request accepted",         "{recipient_name} accepted your connection request"),
    "connection_established":     ("You have a new connection",           "You are now connected with {sender_name}"),
    "contact_request_declined":   ("Connection request declined",         "{recipient_name} declined your connection request"),
    "contact_request_expired":    ("Connection request expired",          "Your request to {recipient_name} expired with no response"),
    "connection_expiring_soon":   ("Connection expiring soon",            "One of your connections expires in 3 days — visit your connections page"),
    "mentorship_request_received":("New mentorship request",              "{mentee_name} has requested you as their mentor"),
    "mentorship_request_accepted":("Mentorship request accepted",         "{mentor_name} has accepted your mentorship request"),
    "mentorship_request_declined":("Mentorship request declined",         "{mentor_name} declined your mentorship request"),
    "mentorship_closed":          ("Mentorship ended",                    "Your mentorship with {other_name} has been closed"),
    "mentorship_flagged":         ("Mentorship flagged for review",       "A mentorship involving {mentor_name} and {mentee_name} has been flagged"),
    "story_submitted":            ("New story submitted for review",      '"{story_title}" has been submitted for review'),
    "story_published":            ("Your story has been published",       '"{story_title}" is now live on the platform'),
    "story_rejected":             ("Story returned for revision",         '"{story_title}" needs revision — see reviewer note'),
    "startup_published":          ("Your startup has been published",     '"{startup_name}" is now live on the Innovation board'),
    "startup_rejected":           ("Startup returned for revision",       '"{startup_name}" needs revision — see reviewer note'),
    "giving_project_published":   ("Your giving project is live",         '"{project_title}" has been published'),
    "giving_project_rejected":    ("Giving project returned for revision",'"{project_title}" needs revision — see reviewer note'),
    "community_join_approved":    ("Community join approved",             "You are now a member of {community_name}"),
    "community_join_rejected":    ("Community join declined",             "Your request to join {community_name} was not approved"),
    "community_join_requested":   ("New community join request",          "{member_name} has requested to join {community_name}"),
    "job_application_received":   ("New application for your job",        '{applicant_name} applied to "{job_title}"'),
    "job_application_contacted":  ("Employer wants to connect",           '{poster_name} has contacted you regarding "{job_title}"'),
    "job_application_declined":   ("Application not progressed",          '{poster_name} has declined your application to "{job_title}"'),
    "job_expired":                ("Your job listing has expired",        '"{job_title}" has been closed after 60 days'),
    "community_member_promoted":  ("You've been made a community admin",  "You are now an admin of {community_name}"),
    "community_member_demoted":   ("Community admin role removed",        "Your admin role in {community_name} has been removed"),
    "mentor_deactivated":         ("Mentor profile deactivated",          "Your mentor profile has been deactivated by an admin"),
    "mentor_reactivated":         ("Mentor profile reactivated",          "Your mentor profile has been reactivated — visit Mentorship to update your settings"),
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def emit(
    event_type:    str,
    actor_uid:     str | None,
    recipient_uid: str | None,
    entity_type:   str,
    entity_id:     int | None,
    context:       dict,
) -> None:
    _write_audit(event_type, actor_uid, entity_type, entity_id)
    if recipient_uid:
        _write_in_app(event_type, recipient_uid, entity_type, entity_id, context)
        # Dispatch email in a background thread — SMTP takes 1-3s and must
        # never block the HTTP response.
        threading.Thread(
            target=_dispatch_push,
            args=(event_type, recipient_uid, context),
            daemon=True,
        ).start()


# ---------------------------------------------------------------------------
# Internal: render (in-app title + plain message)
# ---------------------------------------------------------------------------

def _render(event_type: str, context: dict) -> tuple[str, str]:
    if event_type not in _TEMPLATES:
        logger.warning(f"[notify] unknown event_type '{event_type}' — using fallback")
        return (event_type.replace("_", " ").title(), "")
    title_tpl, msg_tpl = _TEMPLATES[event_type]
    return title_tpl.format_map(context), msg_tpl.format_map(context)


# ---------------------------------------------------------------------------
# Internal: rich email builder — matches portal style
# ---------------------------------------------------------------------------

def _build_email_body(event_type: str, context: dict, base_url: str) -> tuple[str, str, str] | None:
    """
    Return (subject, plain_text, html) for events that warrant a rich email.
    Returns None for events that use the generic fallback.
    Matches portal email style: greeting, bold name + meta, message quote,
    CTA link, expiry line where applicable, NITKSAA Team sign-off.
    """
    def _meta(branch, year):
        parts = [p for p in [branch, str(year) if year else None] if p]
        return f" ({', '.join(parts)})" if parts else ""

    if event_type == "contact_request_received":
        sender     = context.get("sender_name", "An alumnus")
        branch     = context.get("sender_branch")
        year       = context.get("sender_year")
        message    = context.get("message", "")
        recipient  = context.get("recipient_name", "")
        meta       = _meta(branch, year)
        subject    = f"{sender} wants to connect on the NITKSAA Alumni Platform"
        plain = (
            f"Hi {recipient},\n\n"
            f"{sender}{meta} has sent you a contact request on the NITKSAA Alumni Platform.\n\n"
            f'Their message: "{message}"\n\n'
            f"Sign in to accept or decline: {base_url}/connections\n\n"
            f"This request expires in 14 days.\n\n"
            f"NITKSAA Team"
        )
        html = (
            f"<p>Hi {recipient},</p>"
            f"<p><strong>{sender}</strong>{meta} has sent you a contact request "
            f"on the NITKSAA Alumni Platform.</p>"
            f"<blockquote style='border-left:3px solid #e5e7eb;margin:16px 0;padding:8px 16px;"
            f"color:#374151'>{message}</blockquote>"
            f"<p><a href='{base_url}/connections'>Sign in to accept or decline →</a></p>"
            f"<p>This request expires in 14 days.</p>"
            f"<p>NITKSAA Team</p>"
        )
        return subject, plain, html

    if event_type == "contact_request_accepted":
        accepter   = context.get("recipient_name", "An alumnus")
        branch     = context.get("recipient_branch")
        year       = context.get("recipient_year")
        sender     = context.get("sender_name", "")
        meta       = _meta(branch, year)
        subject    = f"{accepter} accepted your connection request"
        plain = (
            f"Hi {sender},\n\n"
            f"{accepter}{meta} has accepted your contact request "
            f"on the NITKSAA Alumni Platform.\n\n"
            f"You can now see each other's contact details for 30 days.\n\n"
            f"Sign in to view: {base_url}/connections\n\n"
            f"NITKSAA Team"
        )
        html = (
            f"<p>Hi {sender},</p>"
            f"<p><strong>{accepter}</strong>{meta} has accepted your contact request "
            f"on the NITKSAA Alumni Platform.</p>"
            f"<p>You can now see each other's contact details for 30 days.</p>"
            f"<p><a href='{base_url}/connections'>Sign in to view →</a></p>"
            f"<p>NITKSAA Team</p>"
        )
        return subject, plain, html

    if event_type == "contact_request_declined":
        decliner  = context.get("recipient_name", "An alumnus")
        sender    = context.get("sender_name", "")
        subject   = f"{decliner} declined your connection request"
        plain = (
            f"Hi {sender},\n\n"
            f"{decliner} has declined your contact request on the NITKSAA Alumni Platform.\n\n"
            f"NITKSAA Team"
        )
        html = (
            f"<p>Hi {sender},</p>"
            f"<p><strong>{decliner}</strong> has declined your contact request "
            f"on the NITKSAA Alumni Platform.</p>"
            f"<p>NITKSAA Team</p>"
        )
        return subject, plain, html

    # All other events — use generic fallback (handled in _dispatch_push)
    return None


# ---------------------------------------------------------------------------
# Internal: Layer 1 — audit log (always)
# ---------------------------------------------------------------------------

def _write_audit(event_type, actor_uid, entity_type, entity_id) -> None:
    try:
        with get_db() as cur:
            cur.execute(
                """
                INSERT INTO website_audit_log
                    (event_type, actor_uid, entity_type, entity_id)
                VALUES (%s, %s, %s, %s)
                """,
                (event_type, actor_uid, entity_type, entity_id),
            )
    except Exception as e:
        logger.error(f"[notify] audit write failed: {e}")


# ---------------------------------------------------------------------------
# Internal: Layer 2 — in-app notification (always when recipient set)
# ---------------------------------------------------------------------------

def _write_in_app(event_type, recipient_uid, entity_type, entity_id, context) -> None:
    try:
        title, message = _render(event_type, context)
        with get_db() as cur:
            cur.execute(
                """
                INSERT INTO notifications
                    (firebase_uid, event_type, entity_type, entity_id, title, message, is_read)
                VALUES (%s, %s, %s, %s, %s, %s, false)
                """,
                (recipient_uid, event_type, entity_type, entity_id, title, message),
            )
    except Exception as e:
        logger.error(f"[notify] in_app write failed: {e}")


# ---------------------------------------------------------------------------
# Internal: Layer 3 — email push (conditional, runs in background thread)
# ---------------------------------------------------------------------------

def _dispatch_push(event_type, recipient_uid, context) -> None:
    app_password = settings.gmail_app_password.strip()
    if not app_password:
        return
    if _is_muted(event_type, recipient_uid):
        return
    recipient_email = _get_email(recipient_uid)
    if not recipient_email:
        return
    try:
        base_url = settings.app_base_url.rstrip("/")
        rich = _build_email_body(event_type, context, base_url)
        if rich:
            subject, plain, html = rich
        else:
            # Generic fallback for events without a rich template
            title, message = _render(event_type, context)
            subject = f"NITKSAA — {title}"
            plain   = message
            html    = (
                f"<p>{message}</p>"
                f"<p><a href='{base_url}/me/actions'>View your notifications →</a></p>"
                f"<p>NITKSAA Team</p>"
            )
        _send_email(to=recipient_email, subject=subject, plain=plain, html=html)
    except Exception as e:
        logger.error(f"[notify] push dispatch failed for {event_type}: {e}")


def _send_email(to: str, subject: str, plain: str, html: str) -> None:
    """Send via Gmail SMTP. Raises on failure — caller swallows."""
    app_password = settings.gmail_app_password.strip()
    # Wrap html in a minimal consistent shell matching portal style
    html_wrapped = f"""
    <div style="font-family:sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#111827">
      <p style="color:#6b7280;font-size:12px;margin-bottom:20px">NITKSAA Alumni Platform</p>
      {html}
      <hr style="border:none;border-top:1px solid #e5e7eb;margin:24px 0">
      <p style="color:#9ca3af;font-size:11px">
        You're receiving this because you're a member of the NITKSAA platform.
        <a href="{settings.app_base_url}/me/actions" style="color:#9ca3af">Manage notifications</a>
      </p>
    </div>
    """
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = _GMAIL_FROM
    msg["To"]      = to
    msg.attach(MIMEText(plain, "plain"))
    msg.attach(MIMEText(html_wrapped, "html"))
    with smtplib.SMTP(_SMTP_HOST, _SMTP_PORT, timeout=10) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.login(_GMAIL_FROM, app_password)
        smtp.sendmail(_GMAIL_FROM, to, msg.as_string())


# ---------------------------------------------------------------------------
# Internal: helpers
# ---------------------------------------------------------------------------

def _is_muted(event_type: str, recipient_uid: str) -> bool:
    try:
        with get_db() as cur:
            cur.execute(
                """
                SELECT push_enabled FROM notification_preferences
                WHERE firebase_uid = %s AND event_type = %s
                """,
                (recipient_uid, event_type),
            )
            row = cur.fetchone()
            return row is not None and not row["push_enabled"]
    except Exception:
        return False


def _get_email(recipient_uid: str) -> str | None:
    try:
        with get_db() as cur:
            cur.execute(
                "SELECT email FROM website_users WHERE firebase_uid = %s",
                (recipient_uid,),
            )
            row = cur.fetchone()
            return row["email"] if row else None
    except Exception:
        return None
