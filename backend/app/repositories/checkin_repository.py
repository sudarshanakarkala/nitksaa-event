from typing import List, Optional
import asyncpg


class CheckInRepository:
    """check_ins (migration 004 + uniqueness index 019). Columns:
    checkin_id, registration_id, event_id, session_id, scanned_by,
    scanned_at, result. No qr_token/attendee_id/ref_id/firebase_uid/
    method/notes/metadata columns exist — the registration row itself is
    the check-in identity (registrations.qrtoken), and result is a plain
    enum (success/duplicate/invalid), not a free-text log. There is no
    check_in_attempts table — attempt logging for rejected/invalid scans
    is not supported by the active schema (see CheckInService and the
    admin-event-schema-alignment sprint report)."""

    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def find_existing_checkin(self, event_id: int, registration_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM check_ins WHERE event_id = $1 AND registration_id = $2",
            event_id, registration_id,
        )

    async def create_checkin(
        self,
        event_id: int,
        registration_id: int,
        session_id: Optional[int],
        scanned_by: str,
    ) -> asyncpg.Record:
        """Relies on uq_check_ins_event_registration (migration 019) as
        the actual source of truth for duplicate prevention — the
        find_existing_checkin call in CheckInService is a fast path, not
        the guarantee itself. Raises asyncpg.exceptions.UniqueViolationError
        on a losing race; the caller translates that into the same
        already_checked_in response a sequential duplicate gets."""
        return await self.conn.fetchrow(
            """
            INSERT INTO check_ins (event_id, registration_id, session_id, scanned_by, result)
            VALUES ($1, $2, $3, $4, 'success')
            RETURNING *
            """,
            event_id, registration_id, session_id, scanned_by,
        )

    async def list_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM check_ins WHERE event_id = $1 ORDER BY scanned_at ASC",
            event_id,
        )
