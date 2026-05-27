from typing import Optional, List
import asyncpg
import json
from app.schemas.registrations import RegistrationCreate


class RegistrationRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def find_active_by_email(self, event_id: int, email: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            """
            SELECT * FROM registrations
            WHERE event_id=$1 AND lower(email)=lower($2) AND status != 'cancelled'
            """,
            event_id, email,
        )

    async def find_active_by_ref_id(self, event_id: int, ref_id: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            """
            SELECT * FROM registrations
            WHERE event_id=$1 AND ref_id=$2 AND status != 'cancelled'
            """,
            event_id, ref_id,
        )

    async def create(
        self,
        event_id: int,
        data: RegistrationCreate,
        qr_token: str,
    ) -> asyncpg.Record:
        metadata_json = json.dumps(data.metadata or {})
        return await self.conn.fetchrow(
            """
            INSERT INTO registrations (
                event_id, firebase_uid, ref_id, email, full_name,
                status, registration_source, qr_token, metadata
            ) VALUES ($1,$2,$3,$4,$5,'registered','api_alpha',$6,$7::jsonb)
            RETURNING *
            """,
            event_id,
            data.firebase_uid,
            data.ref_id,
            str(data.email),
            data.full_name,
            qr_token,
            metadata_json,
        )

    async def create_attendee(
        self,
        registration_id: int,
        event_id: int,
        data: RegistrationCreate,
    ) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO attendees (
                registration_id, event_id, ref_id, firebase_uid,
                attendee_type, display_name, email, phone, badge_name
            ) VALUES ($1,$2,$3,$4,'alumni',$5,$6,$7,$8)
            RETURNING *
            """,
            registration_id,
            event_id,
            data.ref_id,
            data.firebase_uid,
            data.full_name,
            str(data.email),
            data.phone,
            data.badge_name or data.full_name,
        )

    async def get_by_id(self, registration_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM registrations WHERE registration_id=$1", registration_id
        )

    async def get_by_token(self, qr_token: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM registrations WHERE qr_token=$1", qr_token
        )

    async def list_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM registrations WHERE event_id=$1 ORDER BY registered_at ASC",
            event_id,
        )

    async def list_attendees_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM attendees WHERE event_id=$1 ORDER BY created_at ASC",
            event_id,
        )

    async def get_attendee_by_registration(self, registration_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM attendees WHERE registration_id=$1",
            registration_id,
        )

    async def set_registration_status(self, registration_id: int, status: str) -> None:
        await self.conn.execute(
            "UPDATE registrations SET status=$1, updated_at=NOW() WHERE registration_id=$2",
            status, registration_id,
        )
