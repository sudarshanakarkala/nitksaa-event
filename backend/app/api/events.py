"""Week 2 Event API — admin CRUD + public listing.

Route order matters: /events/public must be registered before /events/{event_id}
so FastAPI does not consume the literal "public" as an integer event_id.

Authorization (admin routes): real Firebase-JWT-backed RBAC via
app.middleware.admin_auth — migrated off the development-only
app.middleware.dev_auth placeholder in the admin-auth-unification sprint.
create needs "can create events" (overall admin or
event_users.is_event_creator); list is any admin, scoped to the events
they administer (admin revamp step 1); get/update/
status (event_id in path) are platform_admin or the event's own
event_admin — the same policy admin_events.py already uses for the
equivalent routes. This router and admin_events.py both delegate to the
same EventsService/EventsRepository data-access layer (unchanged by this
sprint); see the admin-auth-unification sprint report for why both
surfaces are kept rather than merged.
"""
from typing import Any, Dict, Optional

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_pool
from app.middleware.admin_auth import require_any_admin, require_event_admin, require_event_creator
from app.schemas.event_create import EventCreate
from app.schemas.event_status import EventStatusUpdate
from app.schemas.event_update import EventUpdate
from app.services import audit_service
from app.services.events_service import EventsService

router = APIRouter(prefix="/api/v1", tags=["events"])


# ── Public routes (registered first — no auth required) ───────────────────────

@router.get("/events/public")
async def list_public_events(
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=20, ge=1, le=100),
    period: Optional[str] = Query(default=None, pattern="^(upcoming|past|all)$"),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        events, total = await svc.list_public_events(period, page, per_page)
    return {"events": events, "total": total, "page": page, "per_page": per_page}


@router.get("/events/public/by-slug/{slug}")
async def get_public_event_id_by_slug(slug: str) -> Dict[str, Any]:
    """The event behind a readable link (/e/<slug>): published events only."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        event_id = await svc.get_public_event_id_by_slug(slug.lower())
    return {"event_id": event_id}


@router.get("/events/public/{event_id}")
async def get_public_event(event_id: int) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        event = await svc.get_public_event(event_id)
    return {"event": event}


# ── Admin routes (platform_admin, or event_admin scoped to event_id) ───────────

@router.post("/events", status_code=201)
async def create_event(
    body: EventCreate,
    user: Dict[str, Any] = Depends(require_event_creator),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        event = await svc.create_event(body, user)
    return {"status": "ok", "event": event}


@router.get("/events")
async def list_events(
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=20, ge=1, le=100),
    status: Optional[str] = Query(default=None),
    is_virtual: Optional[bool] = Query(default=None),
    search: Optional[str] = Query(default=None),
    period: Optional[str] = Query(default=None, pattern="^(upcoming|past|all)$"),
    user: Dict[str, Any] = Depends(require_any_admin),
) -> Dict[str, Any]:
    """Admin list, scoped: overall admins get every event; anyone else
    only the events they administer."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        events, total = await svc.list_events(
            page, per_page, status, is_virtual, search,
            period=period, event_ids=user["access"].scope_event_ids(),
        )
    return {"events": events, "total": total, "page": page, "per_page": per_page}


@router.get("/events/{event_id}")
async def get_event(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        event = await svc.get_event(event_id)
    return {"event": event}


@router.patch("/events/{event_id}/status")
async def update_event_status(
    event_id: int,
    body: EventStatusUpdate,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        event = await svc.update_status(event_id, body, user)
    return {"status": "ok", "event": event}


@router.patch("/events/{event_id}")
async def update_event(
    event_id: int,
    body: EventUpdate,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        event = await svc.update_event(event_id, body, user)
    return {"status": "ok", "event": event}


@router.delete("/events/{event_id}")
async def delete_event(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    """Delete an event: only a draft that has never had a registration.

    Anything else is refused with 409 (event_not_draft /
    event_has_registrations); those events should be cancelled instead,
    which keeps their history. Child rows (sessions, sponsors, partners,
    people, event admins, payment configuration) go with the event.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            event = await conn.fetchrow(
                "SELECT event_id, title, status FROM events WHERE event_id = $1 FOR UPDATE",
                event_id,
            )
            if not event:
                raise HTTPException(status_code=404, detail="event_not_found")
            if event["status"] != "draft":
                raise HTTPException(status_code=409, detail="event_not_draft")
            has_registrations = await conn.fetchval(
                "SELECT EXISTS(SELECT 1 FROM registrations WHERE event_id = $1)", event_id
            )
            if has_registrations:
                raise HTTPException(status_code=409, detail="event_has_registrations")
            try:
                await conn.execute("DELETE FROM events WHERE event_id = $1", event_id)
            except asyncpg.exceptions.ForeignKeyViolationError:
                # Something still points at the event (e.g. a check-in).
                raise HTTPException(status_code=409, detail="event_has_registrations")

    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="event_deleted",
        entity_type="event",
        entity_id=event_id,
        context={"title": event["title"]},
    )
    return {"status": "ok", "event_id": event_id}
