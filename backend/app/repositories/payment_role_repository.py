"""Payment RBAC storage — payment_platform_roles (migration 018) and the
event-scoped 'event_admin' role stored in the pre-existing (previously
unused) event_members table (migration 003).

Platform roles: platform_admin, finance_operator, auditor, support — not
tied to a specific event. Event-scoped role: event_admin — one row per
(event_id, firebase_uid) in event_members, reusing that table's existing
schema rather than introducing a parallel one.
"""
from typing import List, Optional

import asyncpg

PLATFORM_ROLES = ("platform_admin", "finance_operator", "auditor", "support")
EVENT_ADMIN_ROLE = "event_admin"


class PaymentRoleRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    # ── Platform-wide roles (payment_platform_roles) ───────────────────────

    async def active_platform_roles(self, firebase_uid: str) -> set:
        rows = await self.conn.fetch(
            """
            SELECT role FROM payment_platform_roles
            WHERE firebase_uid = $1 AND revoked_at IS NULL
            """,
            firebase_uid,
        )
        return {r["role"] for r in rows}

    async def grant_platform_role(
        self, firebase_uid: str, role: str, granted_by: str
    ) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO payment_platform_roles (firebase_uid, role, granted_by)
            VALUES ($1, $2, $3)
            RETURNING *
            """,
            firebase_uid,
            role,
            granted_by,
        )

    async def get_active_grant_by_id(self, grant_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_platform_roles WHERE id = $1 AND revoked_at IS NULL",
            grant_id,
        )

    async def revoke_platform_role(self, grant_id: int, revoked_by: str) -> None:
        await self.conn.execute(
            """
            UPDATE payment_platform_roles
            SET revoked_at = now(), revoked_by = $2
            WHERE id = $1 AND revoked_at IS NULL
            """,
            grant_id,
            revoked_by,
        )

    async def list_active_platform_roles(self) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            """
            SELECT * FROM payment_platform_roles
            WHERE revoked_at IS NULL
            ORDER BY granted_at DESC
            """
        )

    # ── Event-scoped 'event_admin' role (event_members) ───────────────────

    async def is_event_admin(self, event_id: int, firebase_uid: str) -> bool:
        val = await self.conn.fetchval(
            """
            SELECT EXISTS (
                SELECT 1 FROM event_members
                WHERE event_id = $1 AND firebase_uid = $2
                  AND role = $3 AND status = 'active'
            )
            """,
            event_id,
            firebase_uid,
            EVENT_ADMIN_ROLE,
        )
        return bool(val)

    async def grant_event_admin(self, event_id: int, firebase_uid: str) -> asyncpg.Record:
        """Upsert an active event_admin membership row for one event."""
        return await self.conn.fetchrow(
            """
            INSERT INTO event_members (event_id, firebase_uid, role, status)
            VALUES ($1, $2, $3, 'active')
            ON CONFLICT (event_id, firebase_uid)
            DO UPDATE SET role = $3, status = 'active'
            RETURNING *
            """,
            event_id,
            firebase_uid,
            EVENT_ADMIN_ROLE,
        )
