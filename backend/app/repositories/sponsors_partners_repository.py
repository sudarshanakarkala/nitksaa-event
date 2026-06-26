from typing import Any, List, Optional
import asyncpg

from app.schemas.sponsors_partners import (
    SponsorCreate, SponsorUpdate,
    PartnerCreate, PartnerUpdate,
)


class SponsorsRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def list_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            """
            SELECT * FROM event_sponsors
            WHERE event_id = $1
            ORDER BY display_order ASC, sponsor_id ASC
            """,
            event_id,
        )

    async def list_public_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            """
            SELECT sponsor_id, event_id, sponsor_type, name,
                   logo_url, website_url, description, display_order
            FROM event_sponsors
            WHERE event_id = $1 AND is_visible = true
            ORDER BY
                CASE sponsor_type
                    WHEN 'TITLE_SPONSOR'     THEN 1
                    WHEN 'GOLD_SPONSOR'      THEN 2
                    WHEN 'SILVER_SPONSOR'    THEN 3
                    WHEN 'BRONZE_SPONSOR'    THEN 4
                    WHEN 'ASSOCIATE_SPONSOR' THEN 5
                    ELSE 6
                END,
                display_order ASC,
                sponsor_id ASC
            """,
            event_id,
        )

    async def get(self, sponsor_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM event_sponsors WHERE sponsor_id = $1",
            sponsor_id,
        )

    async def create(self, event_id: int, data: SponsorCreate) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO event_sponsors (
                event_id, sponsor_type, name, logo_url,
                website_url, description, display_order, is_visible
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING *
            """,
            event_id, data.sponsor_type, data.name, data.logo_url,
            data.website_url, data.description, data.display_order, data.is_visible,
        )

    async def update(self, sponsor_id: int, data: SponsorUpdate) -> Optional[asyncpg.Record]:
        fields = data.model_dump(exclude_unset=True)
        if not fields:
            return await self.get(sponsor_id)

        set_parts = []
        values: List[Any] = []
        for i, (key, val) in enumerate(fields.items(), start=1):
            set_parts.append(f"{key} = ${i}")
            values.append(val)
        set_parts.append("updated_at = NOW()")
        values.append(sponsor_id)

        await self.conn.execute(
            f"UPDATE event_sponsors SET {', '.join(set_parts)} WHERE sponsor_id = ${len(values)}",
            *values,
        )
        return await self.get(sponsor_id)

    async def delete(self, sponsor_id: int) -> bool:
        result = await self.conn.execute(
            "DELETE FROM event_sponsors WHERE sponsor_id = $1",
            sponsor_id,
        )
        return result == "DELETE 1"


class PartnersRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def list_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            """
            SELECT * FROM event_partners
            WHERE event_id = $1
            ORDER BY display_order ASC, partner_id ASC
            """,
            event_id,
        )

    async def list_public_by_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            """
            SELECT partner_id, event_id, partner_type, name,
                   logo_url, website_url, description, display_order
            FROM event_partners
            WHERE event_id = $1 AND is_visible = true
            ORDER BY partner_type ASC, display_order ASC, partner_id ASC
            """,
            event_id,
        )

    async def get(self, partner_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM event_partners WHERE partner_id = $1",
            partner_id,
        )

    async def create(self, event_id: int, data: PartnerCreate) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO event_partners (
                event_id, partner_type, name, logo_url,
                website_url, description, display_order, is_visible
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING *
            """,
            event_id, data.partner_type, data.name, data.logo_url,
            data.website_url, data.description, data.display_order, data.is_visible,
        )

    async def update(self, partner_id: int, data: PartnerUpdate) -> Optional[asyncpg.Record]:
        fields = data.model_dump(exclude_unset=True)
        if not fields:
            return await self.get(partner_id)

        set_parts = []
        values: List[Any] = []
        for i, (key, val) in enumerate(fields.items(), start=1):
            set_parts.append(f"{key} = ${i}")
            values.append(val)
        set_parts.append("updated_at = NOW()")
        values.append(partner_id)

        await self.conn.execute(
            f"UPDATE event_partners SET {', '.join(set_parts)} WHERE partner_id = ${len(values)}",
            *values,
        )
        return await self.get(partner_id)

    async def delete(self, partner_id: int) -> bool:
        result = await self.conn.execute(
            "DELETE FROM event_partners WHERE partner_id = $1",
            partner_id,
        )
        return result == "DELETE 1"
