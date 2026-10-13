"""Admin Actions tab and badge count (admin revamp step 8).

Modelled on the website's "Needs attention": a few queues, each a count,
scoped like every admin tab (overall admins: every event; anyone else:
the events they administer).

Queues:
  drafts          events still in draft (any date; old drafts need deleting
                  or moving to a new date)
  closing_soon    published, registration closes within 72 hours, not full
  near_capacity   published, not over, at least 90 % of capacity taken
  failed_emails   active registrations whose confirmation email failed, on
                  published events that haven't ended
  stuck_payments  orders still started/pending after 30 minutes
  failed_refunds  refunds that failed

`total` is the badge: only the queues that need someone to act (drafts,
failed emails, stuck payments, failed refunds). Closing soon and nearly
full are shown in the tab for information but don't count.

The three per-event queues also list their events, so the tab can link to
each one.
"""
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

from fastapi import APIRouter, Depends

from app.database import get_pool
from app.middleware.admin_auth import require_any_admin

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

CLOSING_WITHIN = timedelta(hours=72)
NEAR_CAPACITY_PCT = 90
# Same rule as the Payments tab (admin_payment_lists._STUCK_AFTER).
STUCK_AFTER = timedelta(minutes=30)

BADGE_QUEUES = ("drafts", "failed_emails", "stuck_payments", "failed_refunds")

# "$1::int[] IS NULL" = overall admin (every event).
_SCOPE = "($1::int[] IS NULL OR e.event_id = ANY($1::int[]))"

_REGISTERED = (
    "(SELECT COUNT(*) FROM registrations r"
    " WHERE r.event_id = e.event_id AND r.status = 'registered')"
)

COUNTS_SQL = f"""
SELECT
  (SELECT COUNT(*) FROM events e
    WHERE {_SCOPE} AND e.status = 'draft') AS drafts,
  (SELECT COUNT(*) FROM payment_orders o JOIN events e ON e.event_id = o.event_id
    WHERE {_SCOPE} AND o.status IN ('created', 'payment_pending')
      AND o.created_at < $2::timestamptz) AS stuck_payments,
  (SELECT COUNT(*) FROM payment_refunds f
     JOIN payment_orders o ON o.id = f.payment_order_id
     JOIN events e ON e.event_id = o.event_id
    WHERE {_SCOPE} AND f.status = 'failed') AS failed_refunds
"""

CLOSING_SOON_SQL = f"""
SELECT * FROM (
  SELECT e.event_id, e.title, e.start_datetime, e.registration_closes_at,
         e.capacity, {_REGISTERED} AS registered
  FROM events e
  WHERE {_SCOPE} AND e.status = 'published'
    AND e.registration_closes_at > $2::timestamptz
    AND e.registration_closes_at <= $3::timestamptz
) x
WHERE x.capacity IS NULL OR x.registered < x.capacity
ORDER BY x.registration_closes_at ASC
"""

NEAR_CAPACITY_SQL = f"""
SELECT * FROM (
  SELECT e.event_id, e.title, e.start_datetime, e.capacity,
         {_REGISTERED} AS registered
  FROM events e
  WHERE {_SCOPE} AND e.status = 'published'
    AND e.capacity > 0
    AND COALESCE(e.end_datetime, e.start_datetime) >= $2::timestamptz
) x
WHERE x.registered * 100 >= x.capacity * $3::int
ORDER BY x.start_datetime ASC
"""

FAILED_EMAILS_SQL = f"""
SELECT e.event_id, e.title, e.start_datetime, COUNT(*) AS failed
FROM registrations r JOIN events e ON e.event_id = r.event_id
WHERE {_SCOPE} AND e.status = 'published'
  AND COALESCE(e.end_datetime, e.start_datetime) >= $2::timestamptz
  AND r.status = 'registered' AND r.confirmation_email_status = 'failed'
GROUP BY e.event_id, e.title, e.start_datetime
ORDER BY e.start_datetime ASC
"""


def _event_row(r) -> Dict[str, Any]:
    d = dict(r)
    for key in ("start_datetime", "registration_closes_at"):
        if d.get(key) is not None:
            d[key] = d[key].isoformat()
    return d


@router.get("/pending-count")
async def pending_count(
    user: Dict[str, Any] = Depends(require_any_admin),
) -> Dict[str, Any]:
    scope = user["access"].scope_event_ids()
    now = datetime.now(timezone.utc)

    pool = await get_pool()
    async with pool.acquire() as conn:
        counts = await conn.fetchrow(COUNTS_SQL, scope, now - STUCK_AFTER)
        closing = await conn.fetch(CLOSING_SOON_SQL, scope, now, now + CLOSING_WITHIN)
        near = await conn.fetch(NEAR_CAPACITY_SQL, scope, now, NEAR_CAPACITY_PCT)
        emails = await conn.fetch(FAILED_EMAILS_SQL, scope, now)

    queues = {
        "drafts": counts["drafts"],
        "closing_soon": len(closing),
        "near_capacity": len(near),
        "failed_emails": sum(r["failed"] for r in emails),
        "stuck_payments": counts["stuck_payments"],
        "failed_refunds": counts["failed_refunds"],
    }
    return {
        "total": sum(queues[k] for k in BADGE_QUEUES),
        **queues,
        "events": {
            "closing_soon": [_event_row(r) for r in closing],
            "near_capacity": [_event_row(r) for r in near],
            "failed_emails": [_event_row(r) for r in emails],
        },
    }
