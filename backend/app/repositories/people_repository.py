from typing import Any, Dict, List, Optional
import asyncpg

from app.schemas.people import PersonCreate, PersonUpdate


class PeopleRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def list_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            """
            SELECT * FROM event_people
            WHERE event_id = $1
            ORDER BY display_order ASC, person_id ASC
            """,
            event_id,
        )

    async def list_public_by_event(self, event_id: int) -> List[asyncpg.Record]:
        """Visible records only, ordered for public display."""
        return await self.conn.fetch(
            """
            SELECT person_id, event_id, role, fullname, title,
                   organisation, bio, photo_url, linkedin_url, display_order
            FROM event_people
            WHERE event_id = $1 AND is_visible = true
            ORDER BY display_order ASC, person_id ASC
            """,
            event_id,
        )

    async def get(self, person_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM event_people WHERE person_id = $1",
            person_id,
        )

    async def create(self, event_id: int, data: PersonCreate) -> asyncpg.Record:
        row = await self.conn.fetchrow(
            """
            INSERT INTO event_people (
                event_id, role, fullname, title, organisation,
                bio, photo_url, linkedin_url, display_order, is_visible
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            RETURNING *
            """,
            event_id, data.role, data.fullname, data.title, data.organisation,
            data.bio, data.photo_url, data.linkedin_url, data.display_order, data.is_visible,
        )
        return row

    async def update(self, person_id: int, data: PersonUpdate) -> Optional[asyncpg.Record]:
        fields = {k: v for k, v in data.model_dump(exclude_unset=True).items()}
        if not fields:
            return await self.get(person_id)

        set_parts = []
        values: List[Any] = []
        for i, (key, val) in enumerate(fields.items(), start=1):
            set_parts.append(f"{key} = ${i}")
            values.append(val)
        set_parts.append("updated_at = NOW()")
        values.append(person_id)

        await self.conn.execute(
            f"UPDATE event_people SET {', '.join(set_parts)} WHERE person_id = ${len(values)}",
            *values,
        )
        return await self.get(person_id)

    async def delete(self, person_id: int) -> bool:
        result = await self.conn.execute(
            "DELETE FROM event_people WHERE person_id = $1",
            person_id,
        )
        return result == "DELETE 1"
