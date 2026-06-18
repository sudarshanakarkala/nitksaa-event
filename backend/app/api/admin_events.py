"""Admin-only event management and check-in endpoints."""
from typing import List, Dict, Any
from fastapi import APIRouter, Depends, Query
from app.database import get_pool
from app.middleware.dev_auth import get_admin_user
from app.services.event_service import EventService
from app.services.checkin_service import CheckInService
from app.schemas.events import EventCreate, EventUpdate, EventResponse, SessionCreate, SessionResponse
from app.schemas.checkins import CheckInCreate, CheckInResponse, CheckInAttemptResponse, QRVerifyResponse

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])


# ── Event CRUD ────────────────────────────────────────────────────────────────

@router.post("/events", response_model=EventResponse, status_code=201)
async def create_event(
    body: EventCreate,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        event = await svc.create_event(body, user)
        return dict(event)


@router.patch("/events/{event_id}", response_model=EventResponse)
async def update_event(
    event_id: int,
    body: EventUpdate,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        event = await svc.update_event(event_id, body, user)
        return dict(event)


@router.post("/events/{event_id}/publish", response_model=EventResponse)
async def publish_event(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        event = await svc.publish_event(event_id, user)
        return dict(event)


@router.post("/events/{event_id}/close", response_model=EventResponse)
async def close_event(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        event = await svc.close_event(event_id, user)
        return dict(event)


@router.get("/events", response_model=List[EventResponse])
async def list_all_events(
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        events = await svc.list_all_events()
        return [dict(e) for e in events]


# ── Sessions ──────────────────────────────────────────────────────────────────

@router.post("/events/{event_id}/sessions", response_model=SessionResponse, status_code=201)
async def create_session(
    event_id: int,
    body: SessionCreate,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        session = await svc.create_session(event_id, body, user)
        return dict(session)


# ── Registrations & Attendees (admin) ────────────────────────────────────────
# Not yet implemented in Week 3 — registration management is Phase 2 alumni-side only.

@router.get("/events/{event_id}/registrations")
async def list_registrations(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    from fastapi import HTTPException
    raise HTTPException(status_code=501, detail="admin_registration_list_not_implemented")


@router.get("/events/{event_id}/attendees")
async def list_attendees(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    from fastapi import HTTPException
    raise HTTPException(status_code=501, detail="admin_attendee_list_not_implemented")


# ── Check-In ──────────────────────────────────────────────────────────────────

@router.get("/events/{event_id}/check-ins/verify", response_model=QRVerifyResponse)
async def verify_qr(
    event_id: int,
    qr_token: str = Query(...),
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = CheckInService(conn)
        return await svc.verify_qr(event_id, qr_token)


@router.post("/events/{event_id}/check-ins", response_model=CheckInResponse, status_code=201)
async def check_in(
    event_id: int,
    body: CheckInCreate,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = CheckInService(conn)
        checkin = await svc.check_in(event_id, body, user)
        return dict(checkin)


@router.get("/events/{event_id}/check-ins", response_model=List[CheckInResponse])
async def list_checkins(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = CheckInService(conn)
        checkins = await svc.list_checkins(event_id)
        return [dict(c) for c in checkins]


@router.get("/events/{event_id}/check-in-attempts", response_model=List[CheckInAttemptResponse])
async def list_checkin_attempts(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = CheckInService(conn)
        attempts = await svc.list_attempts(event_id)
        return [dict(a) for a in attempts]
