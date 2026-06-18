"""Registration repository — targets the 21-column Week 3 schema (migration 008).

Column mapping (DB → API alias where names differ):
  registrations.email  → email_snapshot  (alumni email at registration time)
  registrations.phone  → phone_snapshot
  registrations.notes  → attendee_note
"""
from datetime import datetime
from typing import Any, Dict, List, Optional

import asyncpg

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
        r.updated_at,
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
    ) -> int:
        """Insert a new registration row. Returns the new registration_id."""
        return int(
            await self.conn.fetchval(
                """
                INSERT INTO registrations (
                    event_id, firebase_uid, ref_id,
                    email, phone,
                    fullname_snapshot, batch_year_snapshot, branch_snapshot,
                    notes, status
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'registered')
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
