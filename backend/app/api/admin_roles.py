"""Roles API (admin revamp step 1.6).

  GET    /api/v1/admin/users?query=                 overall admin
  PATCH  /api/v1/admin/users/{uid}/roles            overall admin
  GET    /api/v1/admin/events/{id}/admins           overall admin or this event's admins
  POST   /api/v1/admin/events/{id}/admins           overall admin or this event's admins
  DELETE /api/v1/admin/events/{id}/admins/{uid}     overall admin or this event's admins

Every change is audited as role_granted / role_revoked with context
{target_uid, role, event_id?}. An admin can't remove their own overall
admin flag. Revoking an event admin sets event_members.status = 'revoked'
(the row is kept for history).
"""
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.config import get_settings
from app.database import get_pool
from app.middleware.admin_auth import require_event_admin, require_overall_admin
from app.repositories.payment_role_repository import EVENT_ADMIN_ROLE, PaymentRoleRepository
from app.services import audit_service

router = APIRouter(prefix="/api/v1/admin", tags=["admin-roles"])

ROLE_OVERALL_ADMIN = "overall_admin"
ROLE_EVENT_CREATOR = "event_creator"


# ── Schemas ──────────────────────────────────────────────────────────────────

class AdminUserItem(BaseModel):
    firebase_uid: str
    email: str
    fullname: str
    user_type: str
    is_admin: bool
    is_event_creator: bool
    # True when the uid is in PLATFORM_ADMIN_FIREBASE_UIDS: overall admin
    # regardless of is_admin, and not changeable from the Roles tab.
    is_emergency_admin: bool
    admin_event_ids: List[int]


class AdminUserListResponse(BaseModel):
    users: List[AdminUserItem]
    total: int
    page: int
    per_page: int


class UserRolesUpdate(BaseModel):
    is_admin: Optional[bool] = None
    is_event_creator: Optional[bool] = None


class EventAdminItem(BaseModel):
    firebase_uid: str
    email: Optional[str]
    fullname: Optional[str]
    joined_at: Optional[Any] = None
    is_creator: bool


class EventAdminListResponse(BaseModel):
    event_id: int
    admins: List[EventAdminItem]


class EventAdminGrant(BaseModel):
    firebase_uid: str = Field(..., min_length=1, max_length=128)


# ── Helpers ──────────────────────────────────────────────────────────────────

_USER_COLUMNS = """
    u.firebase_uid, u.email, u.fullname, u.user_type, u.is_admin, u.is_event_creator,
    COALESCE((
        SELECT array_agg(m.event_id ORDER BY m.event_id)
        FROM event_members m
        WHERE m.firebase_uid = u.firebase_uid
          AND m.role = 'event_admin' AND m.status = 'active'
    ), ARRAY[]::int[]) AS admin_event_ids
"""


def _user_item(row) -> Dict[str, Any]:
    d = dict(row)
    d["admin_event_ids"] = list(d["admin_event_ids"] or [])
    d["is_emergency_admin"] = d["firebase_uid"] in get_settings().platform_admin_firebase_uids
    return d


async def _audit_role(actor_uid: str, granted: bool, role: str, target_uid: str,
                      event_id: Optional[int] = None) -> None:
    context: Dict[str, Any] = {"target_uid": target_uid, "role": role}
    if event_id is not None:
        context["event_id"] = event_id
    await audit_service.emit(
        actor_uid=actor_uid,
        event_type="role_granted" if granted else "role_revoked",
        entity_type="event" if event_id is not None else "event_user",
        entity_id=event_id,
        context=context,
    )


# ── Users and their flags (overall admin only) ───────────────────────────────

@router.get("/users", response_model=AdminUserListResponse)
async def search_users(
    query: Optional[str] = Query(None, description="Name or email, case-insensitive"),
    page: int = Query(1, ge=1),
    per_page: int = Query(25, ge=1, le=100),
    user: Dict[str, Any] = Depends(require_overall_admin),
):
    where = ""
    args: List[Any] = []
    if query and query.strip():
        where = "WHERE u.fullname ILIKE $1 OR u.email ILIKE $1"
        args.append(f"%{query.strip()}%")

    pool = await get_pool()
    async with pool.acquire() as conn:
        total = int(await conn.fetchval(f"SELECT COUNT(*) FROM event_users u {where}", *args))
        rows = await conn.fetch(
            f"""
            SELECT {_USER_COLUMNS}
            FROM event_users u
            {where}
            ORDER BY u.is_admin DESC, u.is_event_creator DESC, lower(u.fullname)
            LIMIT ${len(args) + 1} OFFSET ${len(args) + 2}
            """,
            *args, per_page, (page - 1) * per_page,
        )
    return {"users": [_user_item(r) for r in rows], "total": total,
            "page": page, "per_page": per_page}


@router.patch("/users/{firebase_uid}/roles", response_model=AdminUserItem)
async def update_user_roles(
    firebase_uid: str,
    body: UserRolesUpdate,
    user: Dict[str, Any] = Depends(require_overall_admin),
):
    actor_uid = user["firebase_uid"]
    if body.is_admin is False and firebase_uid == actor_uid:
        raise HTTPException(status_code=409, detail="cannot_remove_own_admin")

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            current = await conn.fetchrow(
                """
                SELECT is_admin, is_event_creator FROM event_users
                WHERE firebase_uid = $1 FOR UPDATE
                """,
                firebase_uid,
            )
            if not current:
                raise HTTPException(status_code=404, detail="user_not_found")

            changes: List[tuple] = []  # (role, granted)
            if body.is_admin is not None and body.is_admin != current["is_admin"]:
                changes.append((ROLE_OVERALL_ADMIN, body.is_admin))
            if body.is_event_creator is not None and body.is_event_creator != current["is_event_creator"]:
                changes.append((ROLE_EVENT_CREATOR, body.is_event_creator))

            if changes:
                await conn.execute(
                    """
                    UPDATE event_users
                    SET is_admin = COALESCE($2, is_admin),
                        is_event_creator = COALESCE($3, is_event_creator)
                    WHERE firebase_uid = $1
                    """,
                    firebase_uid, body.is_admin, body.is_event_creator,
                )
            row = await conn.fetchrow(
                f"SELECT {_USER_COLUMNS} FROM event_users u WHERE u.firebase_uid = $1",
                firebase_uid,
            )

    for role, granted in changes:
        await _audit_role(actor_uid, granted, role, firebase_uid)
    return _user_item(row)


# ── Per-event admins (overall admin, or that event's own admins) ─────────────

@router.get("/events/{event_id}/admins", response_model=EventAdminListResponse)
async def list_event_admins(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT m.firebase_uid, u.email, u.fullname, m.joined_at,
                   (m.firebase_uid = e.created_by_firebase_uid) AS is_creator
            FROM event_members m
            JOIN events e ON e.event_id = m.event_id
            LEFT JOIN event_users u ON u.firebase_uid = m.firebase_uid
            WHERE m.event_id = $1 AND m.role = $2 AND m.status = 'active'
            ORDER BY is_creator DESC, lower(u.fullname)
            """,
            event_id, EVENT_ADMIN_ROLE,
        )
    return {"event_id": event_id, "admins": [dict(r) for r in rows]}


@router.post("/events/{event_id}/admins", response_model=EventAdminItem, status_code=201)
async def grant_event_admin(
    event_id: int,
    body: EventAdminGrant,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        target = await conn.fetchrow(
            "SELECT email, fullname FROM event_users WHERE firebase_uid = $1",
            body.firebase_uid,
        )
        if not target:
            raise HTTPException(status_code=404, detail="user_not_found")
        repo = PaymentRoleRepository(conn)
        if await repo.is_event_admin(event_id, body.firebase_uid):
            raise HTTPException(status_code=409, detail="already_event_admin")
        row = await repo.grant_event_admin(event_id, body.firebase_uid)
        creator = await conn.fetchval(
            "SELECT created_by_firebase_uid FROM events WHERE event_id = $1", event_id
        )

    await _audit_role(user["firebase_uid"], True, EVENT_ADMIN_ROLE, body.firebase_uid, event_id)
    return {
        "firebase_uid": row["firebase_uid"],
        "email": target["email"],
        "fullname": target["fullname"],
        "joined_at": row["joined_at"],
        "is_creator": row["firebase_uid"] == creator,
    }


@router.delete("/events/{event_id}/admins/{firebase_uid}")
async def revoke_event_admin(
    event_id: int,
    firebase_uid: str,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        result = await conn.execute(
            """
            UPDATE event_members SET status = 'revoked'
            WHERE event_id = $1 AND firebase_uid = $2
              AND role = $3 AND status = 'active'
            """,
            event_id, firebase_uid, EVENT_ADMIN_ROLE,
        )
    if result.endswith(" 0"):
        raise HTTPException(status_code=404, detail="event_admin_not_found")

    await _audit_role(user["firebase_uid"], False, EVENT_ADMIN_ROLE, firebase_uid, event_id)
    return {"status": "ok", "event_id": event_id, "firebase_uid": firebase_uid}
