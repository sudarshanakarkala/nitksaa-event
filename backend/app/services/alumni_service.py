"""Alumni identity and profile lookup helpers."""
from typing import Optional, Dict, Any

from app.database import get_alumni_pool

# Statuses that permit event registration.
ACTIVE_ALUMNI_STATUSES: frozenset = frozenset(["Active", "Self-Verified"])


def is_alumni_active(registrationstatus: Optional[str]) -> bool:
    """Return True only when the alumni account is in an active registration status."""
    return (registrationstatus or "") in ACTIVE_ALUMNI_STATUSES


async def find_alumni_by_email(email: str) -> Optional[Dict[str, Any]]:
    """Return the alumni identity matching an email address. Used during Firebase auth login.

    Do not change the query or returned fields — auth.py depends on this signature.
    """
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


async def get_alumni_profile_by_ref_id(ref_id: str) -> Optional[Dict[str, Any]]:
    """Return the full alumni profile for a given ref_id (= alumni.alumni_id).

    Used during registration to validate active status and snapshot profile fields.
    Returns None if no matching alumni record exists.
    alumni_db is the authoritative source — do not fall back to event_users.
    """
    pool = await get_alumni_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT
                alumni_id,
                fullname,
                email,
                phone,
                graduationyear,
                branch,
                registrationstatus,
                firebase_uid
            FROM alumni
            WHERE alumni_id = $1
            LIMIT 1
            """,
            ref_id,
        )
    return dict(row) if row else None
