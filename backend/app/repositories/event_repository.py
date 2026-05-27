from typing import Optional, List
import asyncpg
from app.schemas.events import EventCreate, EventUpdate, SessionCreate


class EventRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def create(self, data: EventCreate, created_by: str) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO events (
                slug, title, description, event_type,
                venue_name, venue_address, city, country,
                is_virtual, virtual_url, starts_at, ends_at, timezone,
                capacity, registration_opens_at, registration_closes_at,
                status, created_by, updated_by
            ) VALUES (
                $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,
                'draft',$17,$17
            ) RETURNING *
            """,
            data.slug, data.title, data.description, data.event_type,
            data.venue_name, data.venue_address, data.city, data.country,
            data.is_virtual, data.virtual_url, data.starts_at, data.ends_at,
            data.timezone, data.capacity, data.registration_opens_at,
            data.registration_closes_at, created_by,
        )

    async def update(self, event_id: int, data: EventUpdate, updated_by: str) -> Optional[asyncpg.Record]:
        fields = data.model_dump(exclude_unset=True)
        if not fields:
            return await self.get_by_id(event_id)
        set_clauses = []
        values = []
        for i, (key, val) in enumerate(fields.items(), start=1):
            set_clauses.append(f"{key} = ${i}")
            values.append(val)
        idx = len(values) + 1
        set_clauses.append(f"updated_by = ${idx}")
        values.append(updated_by)
        idx += 1
        set_clauses.append(f"updated_at = NOW()")
        values.append(event_id)
        query = f"UPDATE events SET {', '.join(set_clauses)} WHERE event_id = ${idx} RETURNING *"
        return await self.conn.fetchrow(query, *values)

    async def set_status(self, event_id: int, status: str, updated_by: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "UPDATE events SET status=$1, updated_by=$2, updated_at=NOW() WHERE event_id=$3 RETURNING *",
            status, updated_by, event_id,
        )

    async def get_by_id(self, event_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM events WHERE event_id=$1", event_id
        )

    async def get_by_slug(self, slug: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM events WHERE slug=$1", slug
        )

    async def list_published(self) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM events WHERE status='published' ORDER BY starts_at ASC"
        )

    async def list_all(self) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM events ORDER BY created_at DESC"
        )

    async def slug_exists(self, slug: str) -> bool:
        row = await self.conn.fetchrow("SELECT 1 FROM events WHERE slug=$1", slug)
        return row is not None

    # Sessions
    async def create_session(self, event_id: int, data: SessionCreate) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO sessions (
                event_id, title, description, speaker_name,
                location, track_name, starts_at, ends_at,
                capacity, sort_order
            ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *
            """,
            event_id, data.title, data.description, data.speaker_name,
            data.location, data.track_name, data.starts_at, data.ends_at,
            data.capacity, data.sort_order,
        )

    async def list_sessions(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM sessions WHERE event_id=$1 ORDER BY sort_order, starts_at",
            event_id,
        )
