from typing import Optional, List, Tuple, Dict, Any
import asyncpg

from app.schemas.event_create import EventCreate


_SELECT_WITH_CREATOR = """
    SELECT e.*, u.fullname AS created_by_name
    FROM events e
    LEFT JOIN event_users u ON u.firebase_uid = e.created_by_firebase_uid
"""

_PUBLIC_COLUMNS = """
    e.event_id, e.slug, e.title, e.tagline, e.description,
    e.status, e.start_datetime, e.end_datetime, e.timezone,
    e.location_text, e.location_maps_url, e.is_virtual,
    e.thumbnail_url, e.banner_url, e.capacity,
    e.show_attendee_list,
    e.registration_opens_at, e.registration_closes_at,
    e.published_at
"""


class EventsRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def get_event(self, event_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            f"{_SELECT_WITH_CREATOR} WHERE e.event_id = $1",
            event_id,
        )

    async def slug_exists(self, slug: str) -> bool:
        return bool(await self.conn.fetchval(
            "SELECT 1 FROM events WHERE slug = $1", slug
        ))

    async def create_event(
        self, data: EventCreate, slug: str, firebase_uid: str
    ) -> asyncpg.Record:
        event_id = await self.conn.fetchval(
            """
            INSERT INTO events (
                slug, title, tagline, description,
                start_datetime, end_datetime, timezone,
                location_text, location_maps_url,
                is_virtual, virtual_url,
                thumbnail_url, banner_url,
                capacity, show_attendee_list,
                registration_opens_at, registration_closes_at,
                created_by_firebase_uid, status
            ) VALUES (
                $1, $2, $3, $4,
                $5, $6, $7,
                $8, $9,
                $10, $11,
                $12, $13,
                $14, $15,
                $16, $17,
                $18, 'draft'
            ) RETURNING event_id
            """,
            slug,
            data.title,
            data.tagline,
            data.description,
            data.start_datetime,
            data.end_datetime,
            data.timezone,
            data.location_text,
            data.location_maps_url,
            data.is_virtual,
            data.virtual_url,
            data.thumbnail_url,
            data.banner_url,
            data.capacity,
            data.show_attendee_list,
            data.registration_opens_at,
            data.registration_closes_at,
            firebase_uid,
        )
        return await self.get_event(event_id)

    async def update_event(
        self, event_id: int, fields: Dict[str, Any]
    ) -> Optional[asyncpg.Record]:
        if not fields:
            return await self.get_event(event_id)

        set_parts = []
        values = []
        for i, (key, val) in enumerate(fields.items(), start=1):
            set_parts.append(f"{key} = ${i}")
            values.append(val)
        set_parts.append("updated_at = NOW()")
        where_idx = len(values) + 1
        values.append(event_id)

        await self.conn.execute(
            f"UPDATE events SET {', '.join(set_parts)} WHERE event_id = ${where_idx}",
            *values,
        )
        return await self.get_event(event_id)

    async def list_events(
        self,
        page: int,
        per_page: int,
        status: Optional[str],
        is_virtual: Optional[bool],
        search: Optional[str],
    ) -> Tuple[List[asyncpg.Record], int]:
        where_parts: List[str] = []
        where_values: List[Any] = []

        if status is not None:
            where_parts.append(f"e.status = ${len(where_values) + 1}")
            where_values.append(status)

        if is_virtual is not None:
            where_parts.append(f"e.is_virtual = ${len(where_values) + 1}")
            where_values.append(is_virtual)

        if search:
            idx = len(where_values) + 1
            where_parts.append(f"(e.title ILIKE ${idx} OR e.description ILIKE ${idx})")
            where_values.append(f"%{search}%")

        where_clause = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""

        total = int(await self.conn.fetchval(
            f"SELECT COUNT(*) FROM events e {where_clause}",
            *where_values,
        ))

        limit_idx = len(where_values) + 1
        offset_idx = len(where_values) + 2
        offset = (page - 1) * per_page

        rows = await self.conn.fetch(
            f"""
            {_SELECT_WITH_CREATOR}
            {where_clause}
            ORDER BY e.created_at DESC
            LIMIT ${limit_idx} OFFSET ${offset_idx}
            """,
            *where_values, per_page, offset,
        )
        return list(rows), total

    async def list_public_events(
        self, period: Optional[str], page: int, per_page: int
    ) -> Tuple[List[asyncpg.Record], int]:
        period_clause = ""
        if period == "upcoming":
            period_clause = " AND e.end_datetime >= NOW()"
        elif period == "past":
            period_clause = " AND e.end_datetime < NOW()"

        base_where = f"WHERE e.status = 'published'{period_clause}"

        total = int(await self.conn.fetchval(
            f"SELECT COUNT(*) FROM events e {base_where}"
        ))

        order = "DESC" if period == "past" else "ASC"
        offset = (page - 1) * per_page

        rows = await self.conn.fetch(
            f"""
            SELECT {_PUBLIC_COLUMNS}
            FROM events e
            {base_where}
            ORDER BY e.start_datetime {order}
            LIMIT $1 OFFSET $2
            """,
            per_page, offset,
        )
        return list(rows), total

    async def get_public_event(self, event_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            f"""
            SELECT {_PUBLIC_COLUMNS}
            FROM events e
            WHERE e.event_id = $1 AND e.status = 'published'
            """,
            event_id,
        )