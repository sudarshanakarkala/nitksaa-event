"""Read-only alumni identity lookup helpers."""
from typing import Optional, Dict, Any

from app.database import get_alumni_pool


async def find_alumni_by_email(email: str) -> Optional[Dict[str, Any]]:
    """Return the alumni identity matching an email address, if one exists."""
    pool = await get_alumni_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT alumni_id, fullname, graduationyear
            FROM alumni
            WHERE lower(email) = lower($1)
            LIMIT 1
            """,
            email,
        )
    return dict(row) if row else None
