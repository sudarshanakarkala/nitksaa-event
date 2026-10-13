"""Admin Audit tab (admin revamp step 10b).

Same contract as the website's GET /api/v1/admin/audit-log (filters
event_type, actor, entity_type, from, to; paged {rows,total,page,page_size,
pages}), plus the step-10 decisions: an event filter, category and "who"
filters, a name/event search, and scoping (overall admins: everything;
event admins: their events' entries).

The log has no event column, so each entry's event, order and registration
come from what it points at. Who: "system" for automatic entries,
"attendee" when someone acts on their own registration/payment/refund,
"admin" otherwise.
"""
import json
import math
from datetime import date
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Query

from app.database import get_pool
from app.middleware.admin_auth import require_any_admin
from app.services.refund_service import REASON_ADMIN

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

# Like the website's _EVENT_LABELS. Unknown types fall back to the type
# with underscores as spaces.
LABELS = {
    "event_created": "Event created",
    "event_updated": "Event edited",
    "event_details_updated": "Speakers, sessions or fees edited",
    "event_published": "Event published",
    "event_unpublished": "Event unpublished",
    "event_cancelled": "Event cancelled",
    "event_completed": "Event completed",
    "event_deleted": "Event deleted",
    "session_created": "Session added",
    "person_created": "Speaker added",
    "person_updated": "Speaker edited",
    "person_deleted": "Speaker removed",
    "sponsor_created": "Sponsor added",
    "sponsor_updated": "Sponsor edited",
    "sponsor_deleted": "Sponsor removed",
    "partner_created": "Partner added",
    "partner_updated": "Partner edited",
    "partner_deleted": "Partner removed",
    "role_granted": "Role granted",
    "role_revoked": "Role removed",
    "event_admin_granted": "Event admin added",
    "event_payment_admin_granted": "Event payments access given",
    "payment_role_granted": "Payment role granted",
    "payment_role_revoked": "Payment role removed",
    "registration_seat_held": "Seat held",
    "registration_created": "Registered",
    "registration_confirmed_by_payment": "Registration confirmed by payment",
    "registration_cancelled": "Registration cancelled",
    "registration_hold_expired": "Seat hold expired",
    "check_in_created": "Checked in",
    "payment_configuration_synced": "Payment setup updated",
    "payment_configuration_draft_created": "Payment setup drafted",
    "payment_configuration_published": "Payment setup published",
    "payment_order_created": "Order started",
    "payment_order_expired": "Order expired",
    "payment_attempt_initiated": "Payment try started",
    "payment_captured": "Payment received",
    "payment_captured_after_seat_expiry": "Payment received after the seat hold expired",
    "payment_failed": "Payment failed",
    "payment_pending": "Payment pending",
    "payment_cancelled": "Payment cancelled",
    "payment_verification_checked": "Payment status checked",
    "payment_verification_unresolved": "Payment status still unknown",
    "payment_checkout_signature_invalid": "Checkout signature invalid",
    "payment_checkout_amount_mismatch": "Checkout amount mismatch",
    "payment_verification_amount_mismatch": "Amount mismatch on check",
    "payment_refund_requested": "Refund requested",
    "payment_refund_delayed": "Refund delayed",
    "payment_refund_retried": "Refund retried",
    "payment_refund_failed": "Refund needs attention",
    "payment_refund_processed": "Refund sent",
    "payment_refund_updated": "Refund updated",
    "payment_webhook_duplicate": "Razorpay message repeated",
    "payment_webhook_invalid_signature": "Razorpay message rejected (signature)",
    "payment_webhook_timestamp_rejected": "Razorpay message rejected (too old)",
    "payment_webhook_unknown_order": "Razorpay message for an unknown order",
    "payment_webhook_unknown_refund": "Razorpay message for an unknown refund",
    "payment_webhook_unknown_gateway": "Message from an unknown gateway",
    "payment_webhook_unparseable": "Razorpay message unreadable",
    "payment_webhook_mode_mismatch": "Razorpay message in the wrong mode",
    "payment_webhook_amount_mismatch": "Razorpay message amount mismatch",
    "payment_webhook_ignored_stale_attempt": "Razorpay message for an old try ignored",
}

ROLE_TYPES = ("role_granted", "role_revoked", "event_admin_granted", "event_payment_admin_granted",
              "payment_role_granted", "payment_role_revoked")


def label(event_type: str) -> str:
    return LABELS.get(event_type) or event_type.replace("_", " ").capitalize()


_ROLES_SQL = ", ".join(f"'{t}'" for t in ROLE_TYPES)
_NUM = "'^[0-9]{1,9}$'"

# Every entry with its event, order, registration, category and who.
RESOLVED_SQL = f"""
WITH b AS (
  SELECT l.log_id, l.created_at, l.actor_uid, l.event_type, l.entity_type, l.entity_id, l.context,
         CASE WHEN l.entity_type = 'event' THEN l.entity_id END AS ev_direct,
         CASE WHEN l.context->>'event_id' ~ {_NUM} THEN (l.context->>'event_id')::int END AS ev_ctx,
         CASE WHEN l.entity_type = 'registration' THEN l.entity_id END AS reg_direct,
         COALESCE(CASE WHEN l.entity_type = 'payment_order' THEN l.entity_id END,
                  pa.order_id, pr.payment_order_id,
                  CASE WHEN l.context->>'order_id' ~ {_NUM} THEN (l.context->>'order_id')::bigint END) AS order_id,
         pc.event_id AS ev_cfg
  FROM event_audit_log l
  LEFT JOIN payment_attempts pa ON l.entity_type = 'payment_attempt' AND pa.id = l.entity_id
  LEFT JOIN payment_refunds pr ON l.entity_type = 'payment_refund' AND pr.id = l.entity_id
  LEFT JOIN payment_configurations pc ON l.entity_type = 'payment_configuration' AND pc.id = l.entity_id
), x AS (
  SELECT b.log_id, b.created_at, b.actor_uid, b.event_type, b.entity_type, b.entity_id, b.context,
         b.order_id, COALESCE(b.reg_direct, o.registration_id) AS registration_id,
         COALESCE(b.ev_direct, b.ev_ctx, r.event_id, o.event_id, b.ev_cfg) AS event_id,
         o.public_order_number AS order_number, r.registration_number,
         CASE WHEN b.actor_uid IS NULL OR b.actor_uid = 'system' THEN 'system'
              WHEN b.actor_uid = COALESCE(r.firebase_uid, o.payer_firebase_uid) THEN 'attendee'
              ELSE 'admin' END AS who,
         CASE WHEN b.event_type IN ({_ROLES_SQL}) THEN 'roles'
              WHEN b.event_type LIKE 'payment%' THEN 'payments'
              WHEN b.event_type LIKE 'registration%' OR b.event_type = 'check_in_created' THEN 'registrations'
              ELSE 'events' END AS category
  FROM b
  LEFT JOIN payment_orders o ON o.id = b.order_id
  LEFT JOIN registrations r ON r.registration_id = COALESCE(b.reg_direct, o.registration_id)
)
"""

_SELECT = """
SELECT x.log_id, x.created_at, x.event_type, x.entity_type, x.entity_id, x.context, x.event_id,
       x.who, x.category, x.order_number, x.registration_number,
       e.title AS event_title, u.fullname AS actor_name, x.actor_uid
FROM x
LEFT JOIN events e ON e.event_id = x.event_id
LEFT JOIN event_users u ON u.firebase_uid = x.actor_uid
"""

LIST_SQL = RESOLVED_SQL + _SELECT + """
WHERE ($1::int[] IS NULL OR x.event_id = ANY($1::int[]))
  AND ($2::text IS NULL OR x.event_type = $2::text)
  AND ($3::text IS NULL OR u.fullname ILIKE '%' || $3::text || '%')
  AND ($4::text IS NULL OR x.entity_type = $4::text)
  AND ($5::int IS NULL OR x.event_id = $5::int)
  AND ($6::date IS NULL OR x.created_at >= ($6::date::timestamp AT TIME ZONE 'Asia/Kolkata'))
  AND ($7::date IS NULL OR x.created_at < (($7::date + 1)::timestamp AT TIME ZONE 'Asia/Kolkata'))
  AND ($8::text IS NULL OR x.category = $8::text)
  AND ($9::text IS NULL OR x.who = $9::text)
  AND ($10::text IS NULL OR u.fullname ILIKE '%' || $10::text || '%' OR e.title ILIKE '%' || $10::text || '%')
ORDER BY x.created_at DESC, x.log_id DESC
LIMIT $11::int OFFSET $12::int
"""

COUNT_SQL = RESOLVED_SQL + """
SELECT COUNT(*) FROM x
LEFT JOIN events e ON e.event_id = x.event_id
LEFT JOIN event_users u ON u.firebase_uid = x.actor_uid
WHERE ($1::int[] IS NULL OR x.event_id = ANY($1::int[]))
  AND ($2::text IS NULL OR x.event_type = $2::text)
  AND ($3::text IS NULL OR u.fullname ILIKE '%' || $3::text || '%')
  AND ($4::text IS NULL OR x.entity_type = $4::text)
  AND ($5::int IS NULL OR x.event_id = $5::int)
  AND ($6::date IS NULL OR x.created_at >= ($6::date::timestamp AT TIME ZONE 'Asia/Kolkata'))
  AND ($7::date IS NULL OR x.created_at < (($7::date + 1)::timestamp AT TIME ZONE 'Asia/Kolkata'))
  AND ($8::text IS NULL OR x.category = $8::text)
  AND ($9::text IS NULL OR x.who = $9::text)
  AND ($10::text IS NULL OR u.fullname ILIKE '%' || $10::text || '%' OR e.title ILIKE '%' || $10::text || '%')
"""

# One order's history: its own entries and its registration's, oldest first.
ORDER_TIMELINE_SQL = RESOLVED_SQL + _SELECT + """
WHERE x.order_id = $1::bigint OR ($2::int IS NOT NULL AND x.registration_id = $2::int)
ORDER BY x.created_at, x.log_id
"""

# ── Details: the entry's recorded context as "label: value" lines ────────────

_HIDE = {"event_id", "order_id", "registration_id", "checkin_id", "attempt_id", "refund_id",
         "scenario", "provider", "configuration_key", "status"}
_PEOPLE = {"target_uid", "granted_to", "revoked_from"}
_MONEY = {"amount", "fee", "tax", "final_amount", "price"}
_COPY = {"provider_payment_id", "provider_refund_id", "bank_reference", "gateway_order_ref", "gateway_event_id"}
_KEY_LABELS = {
    "target_uid": "Person", "granted_to": "Person", "revoked_from": "Person",
    "provider_payment_id": "Razorpay payment id", "provider_refund_id": "Razorpay refund id",
    "gateway_order_ref": "Razorpay order id", "gateway_event_id": "Razorpay message id",
    "bank_reference": "Bank reference", "provider_event": "Razorpay event", "failure_code": "Error code",
    "failure": "Why it failed", "instrument": "Bank or wallet", "fields": "Changed", "attempt": "Try",
}


def _money(v: Any) -> str:
    if v in (None, ""):
        return "—"
    if v == "free":
        return "Free"
    try:
        n = float(v)
    except (TypeError, ValueError):
        return str(v)
    return f"₹{n:,.0f}" if n == int(n) else f"₹{n:,.2f}"


def _value(key: str, v: Any, names: Dict[str, str]) -> str:
    if key in _PEOPLE:
        return names.get(v) or "Unknown user"
    if key == "price" and isinstance(v, dict):
        return f"{_money(v.get('from'))} → {_money(v.get('to'))}"
    if key in _MONEY:
        return _money(v)
    if key == "reason" and v in REASON_ADMIN:
        return REASON_ADMIN[v]
    if key == "failure" and isinstance(v, dict):
        return str(v.get("reason") or "").replace("_", " ")
    if isinstance(v, bool):
        return "Yes" if v else "No"
    if isinstance(v, list):
        return ", ".join(str(i).replace("_", " ") for i in v)
    if isinstance(v, dict):
        return ", ".join(f"{k}: {x}" for k, x in v.items())
    return str(v).replace("_", " ") if key in ("role", "source", "reason", "registration") else str(v)


def _details(ctx: Any, names: Dict[str, str]) -> List[Dict[str, Any]]:
    if not isinstance(ctx, dict):
        return []
    out = []
    for k, v in ctx.items():
        if k in _HIDE or v in (None, "", []):
            continue
        out.append({"label": _KEY_LABELS.get(k) or k.replace("_", " ").capitalize(),
                    "value": _value(k, v, names), "copy": k in _COPY})
    return out


async def format_rows(conn, rows) -> List[Dict[str, Any]]:
    """Rows from RESOLVED_SQL + _SELECT, ready for the app. People are shown
    by name; no uids leave the server."""

    ctxs = [json.loads(r["context"]) if isinstance(r["context"], str) else r["context"] for r in rows]
    uids = {c[k] for c in ctxs if isinstance(c, dict) for k in _PEOPLE if isinstance(c.get(k), str)}
    names: Dict[str, str] = {}
    if uids:
        for u in await conn.fetch(
            "SELECT firebase_uid, COALESCE(fullname, email) AS name FROM event_users "
            "WHERE firebase_uid = ANY($1::text[])", list(uids)
        ):
            names[u["firebase_uid"]] = u["name"]
    out = []
    for r, ctx in zip(rows, ctxs):
        if r["who"] == "system":
            actor = "System"
        else:
            actor = r["actor_name"] or "Unknown user"
        deleted = r["event_id"] is not None and r["event_title"] is None
        out.append({
            "log_id": r["log_id"],
            "created_at": r["created_at"].isoformat() if r["created_at"] else None,
            "event_type": r["event_type"],
            "event_label": label(r["event_type"]),
            "category": r["category"],
            "who": r["who"],
            "actor_fullname": actor,
            "entity_type": r["entity_type"],
            "entity_id": r["entity_id"],
            "event_id": r["event_id"],
            "event_title": f"Deleted event #{r['event_id']}" if deleted else r["event_title"],
            "event_deleted": deleted,
            "registration_number": r["registration_number"],
            "order_number": r["order_number"],
            "details": _details(ctx, names),
        })
    return out


@router.get("/audit-log")
async def get_audit_log(
    event_type: Optional[str] = Query(None),
    actor: Optional[str] = Query(None),
    entity_type: Optional[str] = Query(None),
    event_id: Optional[int] = Query(None),
    from_date: Optional[date] = Query(None, alias="from"),
    to_date: Optional[date] = Query(None, alias="to"),
    category: Optional[str] = Query(None, pattern="^(events|registrations|payments|roles)$"),
    who: Optional[str] = Query(None, pattern="^(admin|attendee|system)$"),
    q: Optional[str] = Query(None, max_length=100),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    user: Dict[str, Any] = Depends(require_any_admin),
) -> Dict[str, Any]:
    scope = user["access"].scope_event_ids()
    args = [scope, event_type or None, actor or None, entity_type or None, event_id,
            from_date, to_date, category, who, (q or "").strip() or None]
    pool = await get_pool()
    async with pool.acquire() as conn:
        total = await conn.fetchval(COUNT_SQL, *args)
        rows = await conn.fetch(LIST_SQL, *args, page_size, (page - 1) * page_size)
        result = await format_rows(conn, rows)
    return {
        "rows": result,
        "total": total,
        "page": page,
        "page_size": page_size,
        "pages": math.ceil(total / page_size) if total else 1,
        "types": [{"event_type": t, "label": l} for t, l in LABELS.items()],
    }
