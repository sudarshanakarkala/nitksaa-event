"""Public event and registration endpoints."""
from typing import List, Dict, Any, Optional
from fastapi import APIRouter, Depends, Query
from app.database import get_pool
from app.middleware.dev_auth import get_current_user
from app.services.event_service import EventService
from app.services.registration_service import RegistrationService
from app.schemas.events import EventResponse, SessionResponse
from app.schemas.registrations import RegistrationCreate, RegistrationResponse

router = APIRouter(prefix="/api/v1", tags=["events"])


@router.get("/events", response_model=List[EventResponse])
async def list_events():
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        events = await svc.list_published_events()
        return [dict(e) for e in events]


@router.get("/events/{event_id}", response_model=EventResponse)
async def get_event(event_id: int):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        event = await svc.get_published_event(event_id)
        return dict(event)


@router.get("/events/{event_id}/sessions", response_model=List[SessionResponse])
async def list_event_sessions(event_id: int):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventService(conn)
        sessions = await svc.list_sessions(event_id)
        return [dict(s) for s in sessions]


@router.post("/events/{event_id}/register", response_model=RegistrationResponse, status_code=201)
async def register_for_event(
    event_id: int,
    body: RegistrationCreate,
    user: Dict[str, Any] = Depends(get_current_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = RegistrationService(conn)
        reg = await svc.register(event_id, body, user)
        return dict(reg)


@router.get("/events/{event_id}/registrations/{registration_id}", response_model=RegistrationResponse)
async def get_registration(
    event_id: int,
    registration_id: int,
    user: Dict[str, Any] = Depends(get_current_user),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = RegistrationService(conn)
        reg = await svc.get_registration(event_id, registration_id)
        return dict(reg)
