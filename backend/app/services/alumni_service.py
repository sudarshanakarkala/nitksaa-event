"""Alumni identity and profile lookup helpers."""
from typing import Optional, Dict, Any

from app.database import get_alumni_pool

# Statuses that permit event registration.
ACTIVE_ALUMNI_STATUSES: frozenset = frozenset(["ACTIVE", "Self-Verified"])

# User types that are allowed to register for events. Admins are alumni too.
REGISTRABLE_USER_TYPES: tuple = ("alumni", "admin")


def is_alumni_active(registrationstatus: Optional[str]) -> bool:
    """Return True only when the alumni account is in an active registration status."""
    return (registrationstatus or "") in ACTIVE_ALUMNI_STATUSES


async def resolve_alumni_ref_id(user: Dict[str, Any]) -> Optional[str]:
    """Resolve the alumni ref_id a user may register under.

    Only ``alumni`` and ``admin`` users are allowed to register. Admin users are
    alumni, but their ``event_users`` row sometimes carries ``user_type='admin'``
    without a ``ref_id`` (e.g. created outside the normal Firebase -> alumni
    mapping flow). In that case fall back to an alumni_db lookup by email so they
    can register for events like any other alumni.

    Returns ``None`` when the user is not registrable or no alumni identity can
    be resolved.
    """
    print(f"Resolving alumni ref_id for user {user.get('email')} ({user.get('user_type')})")
    if user.get("user_type") not in REGISTRABLE_USER_TYPES:
        return None

    ref_id = (user.get("ref_id") or "").strip()
    print(f"User ref_id: {ref_id}")
    if ref_id:
        return ref_id

    email = user.get("email")
    if not email:
        return None

    try:
        alumni = await find_alumni_by_email(email)
    except Exception:
        # alumni_db unreachable — fail open (treated as ineligible) rather than 500.
        return None
    if alumni:
        return alumni.get("alumni_id")
    return None


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
