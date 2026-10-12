"""Admin Dashboard (admin revamp step 7): one read-only summary of how the
events you administer are doing — before, on and after the day.

Scoped like the admin event list: overall admins see every event, anyone
else only the events they administer (Access.scope_event_ids()).
Cancelled events are left out of the upcoming and recent lists.
Money counts LIVE payments only (TEST orders are practice runs).
"""
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Query

from app.database import get_pool
from app.middleware.admin_auth import require_any_admin
from app.services.events_service import _compute_registration_status

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

_PERIOD_DAYS = {"30d": 30, "90d": 90}
_UPCOMING_LIMIT = 8
_RECENT_LIMIT = 5
_WEEKS = 12

# "$1::int[] IS NULL" = overall admin (every event).
_SCOPE = "($1::int[] IS NULL OR e.event_id = ANY($1::int[]))"


def _since(period: str, now: datetime) -> Optional[datetime]:
    if period in _PERIOD_DAYS:
        return now - timedelta(days=_PERIOD_DAYS[period])
    if period == "year":
        return datetime(now.year, 1, 1, tzinfo=timezone.utc)
    return None  # all time


@router.get("/dashboard")
async def dashboard(
    period: str = Query("30d", pattern="^(30d|90d|year|all)$"),
    user: Dict[str, Any] = Depends(require_any_admin),
) -> Dict[str, Any]:
    scope = user["access"].scope_event_ids()
    now = datetime.now(timezone.utc)
    since = _since(period, now)

    pool = await get_pool()
    async with pool.acquire() as conn:
        tiles = await conn.fetchrow(
            f"""
            SELECT
              (SELECT COUNT(*) FROM events e
                WHERE {_SCOPE} AND e.status IN ('draft', 'published')
                  AND COALESCE(e.end_datetime, e.start_datetime) >= $2) AS upcoming_events,
              (SELECT COUNT(*) FROM registrations r JOIN events e ON e.event_id = r.event_id
                WHERE {_SCOPE} AND ($3::timestamptz IS NULL OR r.registered_at >= $3)) AS registrations,
              (SELECT COUNT(*) FROM registrations r JOIN events e ON e.event_id = r.event_id
                WHERE {_SCOPE} AND r.status = 'cancelled'
                  AND ($3::timestamptz IS NULL OR r.cancelled_at >= $3)) AS cancellations,
              (SELECT COALESCE(SUM(o.amount_paid), 0) FROM payment_orders o JOIN events e ON e.event_id = o.event_id
                WHERE {_SCOPE} AND o.status = 'paid' AND o.payment_mode = 'live'
                  AND ($3::timestamptz IS NULL OR o.paid_at >= $3)) AS money_collected
            """,
            scope, now, since,
        )

        upcoming = await conn.fetch(
            f"""
            SELECT e.event_id, e.title, e.start_datetime, e.end_datetime, e.status,
                   e.capacity, e.registration_opens_at, e.registration_closes_at,
                   (SELECT COUNT(*) FROM registrations r
                     WHERE r.event_id = e.event_id AND r.status = 'registered') AS registered,
                   (SELECT COUNT(*) FROM registrations r
                     WHERE r.event_id = e.event_id AND r.status = 'registered'
                       AND r.registered_at >= $2 - INTERVAL '7 days') AS new_7d,
                   (SELECT COUNT(DISTINCT c.registration_id) FROM check_ins c
                     WHERE c.event_id = e.event_id) AS checked_in
            FROM events e
            WHERE {_SCOPE} AND e.status IN ('draft', 'published')
              AND COALESCE(e.end_datetime, e.start_datetime) >= $2
            ORDER BY e.start_datetime ASC
            LIMIT {_UPCOMING_LIMIT}
            """,
            scope, now,
        )

        recent = await conn.fetch(
            f"""
            SELECT e.event_id, e.title, e.start_datetime,
                   (SELECT COUNT(*) FROM registrations r
                     WHERE r.event_id = e.event_id AND r.status = 'registered') AS registered,
                   (SELECT COUNT(DISTINCT c.registration_id) FROM check_ins c
                     WHERE c.event_id = e.event_id) AS checked_in,
                   (SELECT COALESCE(SUM(o.amount_paid), 0) FROM payment_orders o
                     WHERE o.event_id = e.event_id AND o.status = 'paid'
                       AND o.payment_mode = 'live') AS money_collected
            FROM events e
            WHERE {_SCOPE} AND e.status IN ('published', 'completed')
              AND COALESCE(e.end_datetime, e.start_datetime) < $2
            ORDER BY e.start_datetime DESC
            LIMIT {_RECENT_LIMIT}
            """,
            scope, now,
        )

        week_start = (now - timedelta(weeks=_WEEKS - 1)).date()
        weekly = await conn.fetch(
            f"""
            WITH weeks AS (
              SELECT generate_series(date_trunc('week', $2::timestamptz),
                                     date_trunc('week', $3::timestamptz),
                                     INTERVAL '1 week') AS week
            )
            SELECT w.week,
                   (SELECT COUNT(*) FROM registrations r JOIN events e ON e.event_id = r.event_id
                     WHERE {_SCOPE} AND date_trunc('week', r.registered_at) = w.week) AS registrations,
                   (SELECT COUNT(*) FROM registrations r JOIN events e ON e.event_id = r.event_id
                     WHERE {_SCOPE} AND r.status = 'cancelled'
                       AND date_trunc('week', r.cancelled_at) = w.week) AS cancellations
            FROM weeks w
            ORDER BY w.week
            """,
            scope, datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc), now,
        )

        by_decade = await conn.fetch(
            f"""
            SELECT (r.batch_year_snapshot / 10) * 10 AS decade, COUNT(*) AS count
            FROM registrations r JOIN events e ON e.event_id = r.event_id
            WHERE {_SCOPE} AND r.status = 'registered' AND r.batch_year_snapshot IS NOT NULL
              AND ($2::timestamptz IS NULL OR r.registered_at >= $2)
            GROUP BY 1
            ORDER BY 1
            """,
            scope, since,
        )

    def upcoming_row(r) -> Dict[str, Any]:
        d = dict(r)
        d["registration_status"] = _compute_registration_status(
            {**d, "registered_count": d["registered"]}
        )
        for key in ("registration_opens_at", "registration_closes_at"):
            d.pop(key, None)
        return d

    return {
        "period": period,
        "since": since.isoformat() if since else None,
        "tiles": {
            "upcoming_events": tiles["upcoming_events"],
            "registrations": tiles["registrations"],
            "cancellations": tiles["cancellations"],
            "money_collected": float(tiles["money_collected"]),
        },
        "upcoming": [upcoming_row(r) for r in upcoming],
        "recent": [
            {
                **dict(r),
                "no_shows": max(r["registered"] - r["checked_in"], 0),
                "money_collected": float(r["money_collected"]),
            }
            for r in recent
        ],
        "weekly": [
            {
                "week": r["week"].date().isoformat(),
                "registrations": r["registrations"],
                "cancellations": r["cancellations"],
            }
            for r in weekly
        ],
        "by_decade": [{"decade": r["decade"], "count": r["count"]} for r in by_decade],
    }
