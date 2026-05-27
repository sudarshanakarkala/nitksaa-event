from typing import Optional, List
import asyncpg
import json


class CheckInRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def find_existing_checkin(self, event_id: int, registration_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM check_ins WHERE event_id=$1 AND registration_id=$2",
            event_id, registration_id,
        )

    async def create_checkin(
        self,
        event_id: int,
        registration_id: int,
        attendee_id: int,
        qr_token: str,
        checked_in_by: str,
        session_id: Optional[int],
        ref_id: Optional[str],
        firebase_uid: Optional[str],
        notes: Optional[str],
    ) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO check_ins (
                event_id, session_id, registration_id, attendee_id,
                ref_id, firebase_uid, qr_token,
                checked_in_by, method, notes
            ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'qr',$9) RETURNING *
            """,
            event_id, session_id, registration_id, attendee_id,
            ref_id, firebase_uid, qr_token, checked_in_by, notes,
        )

    async def list_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM check_ins WHERE event_id=$1 ORDER BY checked_in_at ASC",
            event_id,
        )

    async def log_attempt(
        self,
        event_id: Optional[int],
        qr_token: str,
        registration_id: Optional[int],
        attendee_id: Optional[int],
        attempt_status: str,
        attempted_by: Optional[str],
        notes: Optional[str],
    ) -> None:
        await self.conn.execute(
            """
            INSERT INTO check_in_attempts (
                event_id, qr_token, registration_id, attendee_id,
                attempt_status, attempted_by, notes
            ) VALUES ($1,$2,$3,$4,$5,$6,$7)
            """,
            event_id, qr_token, registration_id, attendee_id,
            attempt_status, attempted_by, notes,
        )

    async def list_attempts_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM check_in_attempts WHERE event_id=$1 ORDER BY attempted_at DESC",
            event_id,
        )
