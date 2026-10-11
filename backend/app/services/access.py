"""One access resolver for every admin check (admin revamp step 1).

Every admin decision — route dependencies in app.middleware.admin_auth, the
NITiKa admin scope, and the `access` block returned at login — goes through
get_access(), so there is one source of truth.

Overall admin if ANY of:
  * the uid is in PLATFORM_ADMIN_FIREBASE_UIDS (emergency fallback only);
  * event_users.is_admin (migration 026; granted in the Roles tab);
  * an active payment_platform_roles 'platform_admin' grant.

An overall admin is reported with 'platform_admin' in platform_roles, so the
existing payment-role checks (where platform_admin satisfies everything)
treat all three sources the same.

Event creator: overall admin, or event_users.is_event_creator.
Event admin:   active event_members row with role 'event_admin'.

Access is computed per request and never put in the JWT, so a role change
applies at the next request without signing in again.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import asyncpg

from app.config import get_settings
from app.database import get_pool
from app.repositories.payment_role_repository import PaymentRoleRepository


@dataclass
class Access:
    is_admin: bool = False                 # overall admin
    is_event_creator: bool = False         # may create events (true for any overall admin)
    platform_roles: set = field(default_factory=set)  # platform_admin / finance_operator / auditor / support
    admin_event_ids: List[int] = field(default_factory=list)  # empty for overall admin = "all"

    @property
    def is_any_admin(self) -> bool:
        return self.is_admin or self.is_event_creator or bool(self.admin_event_ids)

    def scope_event_ids(self) -> Optional[List[int]]:
        """None = every event (overall admin); otherwise exactly the events
        this user administers (possibly empty)."""
        return None if self.is_admin else list(self.admin_event_ids)

    def can_admin_event(self, event_id: int) -> bool:
        return self.is_admin or event_id in self.admin_event_ids

    def to_dict(self) -> Dict[str, Any]:
        return {
            "is_admin": self.is_admin,
            "is_event_creator": self.is_event_creator,
            "platform_roles": sorted(self.platform_roles),
            "admin_event_ids": list(self.admin_event_ids),
        }


async def get_access(conn: asyncpg.Connection, firebase_uid: str) -> Access:
    settings = get_settings()
    repo = PaymentRoleRepository(conn)

    flags = await conn.fetchrow(
        "SELECT is_admin, is_event_creator FROM event_users WHERE firebase_uid = $1",
        firebase_uid,
    )
    platform_roles = set(await repo.active_platform_roles(firebase_uid))

    is_admin = (
        firebase_uid in settings.platform_admin_firebase_uids
        or bool(flags and flags["is_admin"])
        or "platform_admin" in platform_roles
    )
    if is_admin:
        platform_roles.add("platform_admin")

    is_event_creator = is_admin or bool(flags and flags["is_event_creator"])
    admin_event_ids = [] if is_admin else await repo.event_admin_event_ids(firebase_uid)

    return Access(
        is_admin=is_admin,
        is_event_creator=is_event_creator,
        platform_roles=platform_roles,
        admin_event_ids=admin_event_ids,
    )


async def load_access(firebase_uid: str) -> Access:
    """get_access on a pooled connection, for callers without one."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        return await get_access(conn, firebase_uid)
