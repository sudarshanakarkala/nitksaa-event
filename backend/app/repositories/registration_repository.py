"""Registration repository — targets the 21-column Week 3 schema (migration 008).

Column mapping (DB → API alias where names differ):
  registrations.email  → email_snapshot  (alumni email at registration time)
  registrations.phone  → phone_snapshot
  registrations.notes  → attendee_note

Admin note: admin attendee/registration endpoints ignore show_attendee_list.
  show_attendee_list controls public visibility only; admins always have access.
"""
import secrets
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

import asyncpg

# Columns for admin attendee list/export (status='registered' rows only).
_ATTENDEE_COLS = """
    registration_id, registration_number, fullname_snapshot,
    email          AS email_snapshot,
    phone          AS phone_snapshot,
    batch_year_snapshot, branch_snapshot,
    registered_at, status, confirmation_email_status
"""

# Columns for admin registrations audit view (all statuses).
_REGISTRATION_AUDIT_COLS = """
    registration_id, registration_number, fullname_snapshot,
    email          AS email_snapshot,
    status, registered_at, cancelled_at
"""

# SELECT clause shared by queries that need event fields for join_url resolution.
_REG_WITH_EVENT = """
    SELECT
        r.registration_id,
        r.registration_number,
        r.event_id,
        r.firebase_uid,
        r.ref_id,
        r.status,
        r.email          AS email_snapshot,
        r.phone          AS phone_snapshot,
        r.fullname_snapshot,
        r.batch_year_snapshot,
        r.branch_snapshot,
        r.notes          AS attendee_note,
        r.registered_at,
        r.cancelled_at,
        r.confirmation_email_status,
        r.confirmation_email_sent_at,
        r.hold_expires_at,
        r.updated_at,
        (SELECT po.public_order_number FROM payment_orders po
         WHERE po.registration_id = r.registration_id
         ORDER BY po.created_at DESC LIMIT 1) AS latest_order_id,
        e.title          AS event_title,
        e.start_datetime,
        e.end_datetime,
        e.timezone,
        e.is_virtual,
        e.virtual_url,
        e.location_text,
        e.location_maps_url,
        e.status         AS event_status
    FROM registrations r
    JOIN events e ON e.event_id = r.event_id
"""


class RegistrationRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def count_active(self, event_id: int) -> int:
        """Count registrations with status='registered' for capacity enforcement."""
        val = await self.conn.fetchval(
            "SELECT COUNT(*) FROM registrations WHERE event_id = $1 AND status = 'registered'",
            event_id,
        )
        return int(val)

    async def get_active_for_user(
        self, event_id: int, firebase_uid: str
    ) -> Optional[asyncpg.Record]:
        """Return the active registration row if the user is already registered."""
        return await self.conn.fetchrow(
            """SELECT registration_id FROM registrations
               WHERE event_id = $1 AND firebase_uid = $2 AND status = 'registered'""",
            event_id,
            firebase_uid,
        )

    # ── Paid-event seat holds (migration 014) ──────────────────────────────
    # Statuses that occupy a seat while a paid registration is in flight or
    # confirmed. Free events never produce rows in the non-'registered' states
    # here, so these queries are safe to use for both free and paid events.
    _IN_FLIGHT_OR_CONFIRMED = (
        "registered", "seat_held", "payment_pending", "payment_verification", "payment_failed",
    )

    async def get_active_or_held_for_user(
        self, event_id: int, firebase_uid: str
    ) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            """SELECT registration_id, status FROM registrations
               WHERE event_id = $1 AND firebase_uid = $2
                 AND status = ANY($3::text[])""",
            event_id,
            firebase_uid,
            list(self._IN_FLIGHT_OR_CONFIRMED),
        )

    async def count_active_or_held(self, event_id: int) -> int:
        val = await self.conn.fetchval(
            """SELECT COUNT(*) FROM registrations
               WHERE event_id = $1 AND status = ANY($2::text[])""",
            event_id,
            list(self._IN_FLIGHT_OR_CONFIRMED),
        )
        return int(val)

    async def expire_stale_holds(self, event_id: int) -> None:
        """Release seat holds whose hold_expires_at has passed. Called lazily
        before capacity/uniqueness checks — there is no background sweeper."""
        await self.conn.execute(
            """
            UPDATE registrations
            SET status = 'cancelled', cancelled_at = now(), updated_at = now()
            WHERE event_id = $1
              AND status IN ('seat_held', 'payment_pending', 'payment_verification', 'payment_failed')
              AND hold_expires_at IS NOT NULL
              AND hold_expires_at < now()
            """,
            event_id,
        )

    async def expire_all_stale_holds(self) -> List[asyncpg.Record]:
        """Explicit, auditable, global counterpart to expire_stale_holds()
        (WP4). Same policy, same status list, same condition — just batched
        across all events instead of scoped to one, and returning the
        affected rows so the caller can emit an audit event per row. Does
        not replace or modify expire_stale_holds(), which stays exactly as
        it is for the existing inline lazy-expiry call in
        registration_service.register_for_event.

        Idempotent (a second run's WHERE matches nothing already
        'cancelled') and concurrency-safe under Postgres MVCC without any
        additional locking — the same UPDATE...WHERE...RETURNING mechanism
        this codebase already relies on elsewhere (see
        test_concurrent_double_click_registration_only_one_succeeds).
        'registered' (confirmed/paid) rows are never matched by this
        WHERE clause, so a confirmed registration can never be cancelled
        by this sweep."""
        return await self.conn.fetch(
            """
            UPDATE registrations
            SET status = 'cancelled', cancelled_at = now(), updated_at = now()
            WHERE status IN ('seat_held', 'payment_pending', 'payment_verification', 'payment_failed')
              AND hold_expires_at IS NOT NULL
              AND hold_expires_at < now()
            RETURNING registration_id, event_id
            """
        )

    async def get_by_qrtoken(self, qrtoken: str) -> Optional[asyncpg.Record]:
        """Check-in lookup key. registrations.qrtoken (unique) is the only
        QR/check-in token this schema has — there is no separate
        'attendee' entity or token table; the registration row itself is
        the check-in identity."""
        return await self.conn.fetchrow(
            "SELECT * FROM registrations WHERE qrtoken = $1", qrtoken
        )

    async def get_by_id(self, registration_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM registrations WHERE registration_id = $1", registration_id
        )

    async def set_status(self, registration_id: int, status: str) -> None:
        await self.conn.execute(
            "UPDATE registrations SET status = $2, updated_at = now() WHERE registration_id = $1",
            registration_id,
            status,
        )

    async def extend_hold(self, registration_id: int, new_hold_expires_at: datetime) -> None:
        """Push the seat-hold deadline out — used when a payment enters
        verification, so a legitimately-pending confirmation doesn't lose the
        seat mid-check. Only extends; never shortens (a caller passing an
        earlier timestamp than the current one is very likely a bug, so it's
        a no-op rather than silently pulling the deadline in)."""
        await self.conn.execute(
            """
            UPDATE registrations
            SET hold_expires_at = $2, updated_at = now()
            WHERE registration_id = $1
              AND (hold_expires_at IS NULL OR hold_expires_at < $2)
            """,
            registration_id,
            new_hold_expires_at,
        )

    async def insert(
        self,
        event_id: int,
        firebase_uid: str,
        ref_id: Optional[str],
        email: str,
        phone: Optional[str],
        fullname_snapshot: Optional[str],
        batch_year_snapshot: Optional[int],
        branch_snapshot: Optional[str],
        notes: Optional[str],
        status: str = "registered",
        hold_expires_at: Optional[datetime] = None,
    ) -> int:
        """Insert a new registration row. Returns the new registration_id.

        status/hold_expires_at default to the free-event path unchanged;
        the paid-event seat-hold path passes status='seat_held' plus a
        hold_expires_at deadline computed from the event's payment config.

        qrtoken (unique) is generated here — this column previously went
        unpopulated by every registration path, which meant the check-in
        subsystem (CheckInService.verify_qr/check_in, keyed on
        registrations.qrtoken) could never find a real registration.
        Fixed as part of the admin-event-schema-alignment sprint; see that
        sprint's report.
        """
        return int(
            await self.conn.fetchval(
                """
                INSERT INTO registrations (
                    event_id, firebase_uid, ref_id,
                    email, phone,
                    fullname_snapshot, batch_year_snapshot, branch_snapshot,
                    notes, status, hold_expires_at, qrtoken
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                RETURNING registration_id
                """,
                event_id,
                firebase_uid,
                ref_id,
                email,
                phone,
                fullname_snapshot,
                batch_year_snapshot,
                branch_snapshot,
                notes,
                status,
                hold_expires_at,
                secrets.token_urlsafe(16),
            )
        )

    async def set_registration_number(
        self, registration_id: int, registration_number: str
    ) -> None:
        await self.conn.execute(
            "UPDATE registrations SET registration_number = $1 WHERE registration_id = $2",
            registration_number,
            registration_id,
        )

    async def update_email_status(
        self,
        registration_id: int,
        status: str,
        sent_at: Optional[datetime],
        error: Optional[str],
    ) -> None:
        await self.conn.execute(
            """
            UPDATE registrations SET
                confirmation_email_status = $1,
                confirmation_email_sent_at = $2,
                confirmation_email_error = $3,
                updated_at = now()
            WHERE registration_id = $4
            """,
            status,
            sent_at,
            error,
            registration_id,
        )

    async def get_by_id_with_event(
        self, registration_id: int
    ) -> Optional[asyncpg.Record]:
        """Fetch a single registration with joined event fields."""
        return await self.conn.fetchrow(
            f"{_REG_WITH_EVENT} WHERE r.registration_id = $1",
            registration_id,
        )

    async def get_latest_for_user_event(
        self, event_id: int, firebase_uid: str
    ) -> Optional[asyncpg.Record]:
        """Fetch the most recent registration row for a user+event (any status)."""
        return await self.conn.fetchrow(
            f"{_REG_WITH_EVENT} WHERE r.event_id = $1 AND r.firebase_uid = $2 ORDER BY r.registered_at DESC LIMIT 1",
            event_id,
            firebase_uid,
        )

    async def list_for_user(self, firebase_uid: str) -> List[asyncpg.Record]:
        """Fetch all registration rows for a user across all events."""
        return await self.conn.fetch(
            f"{_REG_WITH_EVENT} WHERE r.firebase_uid = $1 ORDER BY r.registered_at DESC",
            firebase_uid,
        )

    # ── Admin: attendee queries (status = 'registered') ───────────────────────
    # These methods intentionally ignore show_attendee_list — that flag controls
    # public visibility only. Admins always have access to attendee data.

    def _attendee_where(
        self,
        event_id: int,
        search: Optional[str],
        batch_year: Optional[int],
    ) -> Tuple[str, list]:
        parts = ["event_id = $1", "status = 'registered'"]
        values: list = [event_id]
        if search:
            i = len(values) + 1
            parts.append(f"fullname_snapshot ILIKE ${i}")
            values.append(f"%{search}%")
        if batch_year is not None:
            i = len(values) + 1
            parts.append(f"batch_year_snapshot = ${i}")
            values.append(batch_year)
        return " AND ".join(parts), values

    async def list_attendees(
        self,
        event_id: int,
        search: Optional[str],
        batch_year: Optional[int],
        page: int,
        per_page: int,
    ) -> List[asyncpg.Record]:
        where, values = self._attendee_where(event_id, search, batch_year)
        limit_idx = len(values) + 1
        offset_idx = len(values) + 2
        return await self.conn.fetch(
            f"SELECT {_ATTENDEE_COLS} FROM registrations"
            f" WHERE {where} ORDER BY registered_at ASC"
            f" LIMIT ${limit_idx} OFFSET ${offset_idx}",
            *values, per_page, (page - 1) * per_page,
        )

    async def count_attendees(
        self,
        event_id: int,
        search: Optional[str],
        batch_year: Optional[int],
    ) -> int:
        where, values = self._attendee_where(event_id, search, batch_year)
        val = await self.conn.fetchval(
            f"SELECT COUNT(*) FROM registrations WHERE {where}",
            *values,
        )
        return int(val)

    async def export_attendees(
        self,
        event_id: int,
        search: Optional[str],
        batch_year: Optional[int],
    ) -> List[asyncpg.Record]:
        where, values = self._attendee_where(event_id, search, batch_year)
        return await self.conn.fetch(
            f"SELECT {_ATTENDEE_COLS} FROM registrations"
            f" WHERE {where} ORDER BY registered_at ASC",
            *values,
        )

    # ── Admin: registration audit queries (all statuses) ──────────────────────

    def _registration_where(
        self,
        event_id: int,
        status_filter: Optional[str],
    ) -> Tuple[str, list]:
        parts = ["event_id = $1"]
        values: list = [event_id]
        if status_filter:
            i = len(values) + 1
            parts.append(f"status = ${i}")
            values.append(status_filter)
        return " AND ".join(parts), values

    async def list_registrations(
        self,
        event_id: int,
        status_filter: Optional[str],
        page: int,
        per_page: int,
    ) -> List[asyncpg.Record]:
        where, values = self._registration_where(event_id, status_filter)
        limit_idx = len(values) + 1
        offset_idx = len(values) + 2
        return await self.conn.fetch(
            f"SELECT {_REGISTRATION_AUDIT_COLS} FROM registrations"
            f" WHERE {where} ORDER BY registered_at ASC"
            f" LIMIT ${limit_idx} OFFSET ${offset_idx}",
            *values, per_page, (page - 1) * per_page,
        )

    async def count_registrations(
        self,
        event_id: int,
        status_filter: Optional[str],
    ) -> int:
        where, values = self._registration_where(event_id, status_filter)
        val = await self.conn.fetchval(
            f"SELECT COUNT(*) FROM registrations WHERE {where}",
            *values,
        )
        return int(val)
