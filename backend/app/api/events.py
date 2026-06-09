"""Week 2 Event API — admin CRUD + public listing.

Route order matters: /events/public must be registered before /events/{event_id}
so FastAPI does not consume the literal "public" as an integer event_id.
"""
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Query

from app.database import get_pool
from app.middleware.dev_auth import get_admin_user
from app.schemas.event_create import EventCreate
from app.schemas.event_status import EventStatusUpdate
from app.schemas.event_update import EventUpdate
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


@router.get("/events/public/{event_id}")
async def get_public_event(event_id: int) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        event = await svc.get_public_event(event_id)
    return {"event": event}


# ── Admin routes (require X-Dev-User: admin header in development) ─────────────

@router.post("/events", status_code=201)
async def create_event(
    body: EventCreate,
    user: Dict[str, Any] = Depends(get_admin_user),
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
    user: Dict[str, Any] = Depends(get_admin_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        events, total = await svc.list_events(page, per_page, status, is_virtual, search)
    return {"events": events, "total": total, "page": page, "per_page": per_page}


@router.get("/events/{event_id}")
async def get_event(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
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
    user: Dict[str, Any] = Depends(get_admin_user),
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
    user: Dict[str, Any] = Depends(get_admin_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        event = await svc.update_event(event_id, body, user)
    return {"status": "ok", "event": event}
