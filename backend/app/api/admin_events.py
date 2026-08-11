"""Admin-only event management and check-in endpoints.

Authorization: production Firebase-JWT-backed RBAC via
app.middleware.admin_auth (platform_admin, or event_admin scoped to the
event_id in the route) — migrated off the development-only
app.middleware.dev_auth placeholder in the operational-readiness sprint.
Two routes have no event_id to scope to (create, list-all) and are
platform_admin-only.
"""
import csv
import io
from typing import List, Dict, Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from app.database import get_pool
from app.middleware.admin_auth import require_event_admin, require_platform_role
from app.repositories.registration_repository import RegistrationRepository
from app.schemas.checkins import CheckInCreate, CheckInResponse, QRVerifyResponse
from app.schemas.event_create import EventCreate
from app.schemas.event_response import EventResponse
from app.schemas.event_status import EventStatusUpdate
from app.schemas.event_update import EventUpdate
from app.schemas.events import SessionCreate, SessionResponse
from app.schemas.registrations import (
    AdminAttendeeItem,
    AdminAttendeeListResponse,
    AdminRegistrationItem,
    AdminRegistrationListResponse,
)
from app.services import audit_service
from app.services.checkin_service import CheckInService
from app.services.events_service import EventsService

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

# GET /events (list-all) previously returned every event unbounded;
# EventsService.list_events is paginated (shared with the public/events.py
# listing implementation). This default keeps existing admin-tooling
# behavior close to "just give me everything" for realistic event counts
# while gaining real pagination support — see the sprint report's API
# compatibility section for the exact classification of this change.
_LIST_ALL_DEFAULT_PER_PAGE = 200


# ── Event CRUD ────────────────────────────────────────────────────────────────
# Delegates to EventsService/EventsRepository — the same already-correct,
# already-audited data-access layer app/api/events.py uses (that router is
# unchanged: still dev-auth-gated, still shared test-fixture
# infrastructure). This router supplies real RBAC on top of the identical
# service layer, rather than maintaining a second, independent
# implementation. EventsService audits every mutation itself
# (event_created/event_updated/event_published/event_unpublished/
# event_cancelled/event_completed) — no separate audit_service.emit call
# is needed here.

@router.post("/events", response_model=EventResponse, status_code=201)
async def create_event(
    body: EventCreate,
    user: Dict[str, Any] = Depends(require_platform_role("platform_admin")),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        return await svc.create_event(body, user)


@router.patch("/events/{event_id}", response_model=EventResponse)
async def update_event(
    event_id: int,
    body: EventUpdate,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        return await svc.update_event(event_id, body, user)


@router.post("/events/{event_id}/publish", response_model=EventResponse)
async def publish_event(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        return await svc.update_status(event_id, EventStatusUpdate(status="published"), user)


@router.post("/events/{event_id}/close", response_model=EventResponse)
async def close_event(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    """'Close' maps to status='completed' — the active schema's status
    vocabulary (draft/published/cancelled/completed) has no separate
    'closed' value; 'completed' is the correct real-world meaning of an
    admin explicitly closing a (necessarily published) event. See the
    sprint report for the alternatives considered."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        return await svc.update_status(event_id, EventStatusUpdate(status="completed"), user)


@router.get("/events", response_model=List[EventResponse])
async def list_all_events(
    page: int = Query(1, ge=1),
    per_page: int = Query(_LIST_ALL_DEFAULT_PER_PAGE, ge=1, le=500),
    user: Dict[str, Any] = Depends(require_platform_role("platform_admin")),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        events, _total = await svc.list_events(page=page, per_page=per_page)
        return events


# ── Sessions ──────────────────────────────────────────────────────────────────

@router.post("/events/{event_id}/sessions", response_model=SessionResponse, status_code=201)
async def create_session(
    event_id: int,
    body: SessionCreate,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = EventsService(conn)
        return await svc.create_session(event_id, body, user)


# ── Registrations & Attendees (admin) ────────────────────────────────────────
# Business rule: admin endpoints ignore show_attendee_list.
# show_attendee_list controls public visibility only; admins always have full access.

@router.get("/events/{event_id}/attendees/export")
async def export_attendees(
    event_id: int,
    search: Optional[str] = Query(None),
    batch_year: Optional[int] = Query(None),
    user: Dict[str, Any] = Depends(require_event_admin),
):
    """CSV export of active attendees. UTF-8 with BOM for Excel compatibility.

    Does NOT include virtual_url, join_url, qr_token, internal IDs, or audit metadata.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        event = await conn.fetchrow(
            "SELECT event_id FROM events WHERE event_id = $1", event_id
        )
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        repo = RegistrationRepository(conn)
        rows = await repo.export_attendees(event_id, search, batch_year)

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "registration_number", "fullname_snapshot", "email_snapshot",
        "batch_year_snapshot", "branch_snapshot", "phone_snapshot",
        "registered_at", "status",
    ])
    for row in rows:
        writer.writerow([
            row["registration_number"] or "",
            row["fullname_snapshot"] or "",
            row["email_snapshot"] or "",
            row["batch_year_snapshot"] if row["batch_year_snapshot"] is not None else "",
            row["branch_snapshot"] or "",
            row["phone_snapshot"] or "",
            row["registered_at"].isoformat() if row["registered_at"] else "",
            row["status"] or "",
        ])

    content = output.getvalue().encode("utf-8-sig")  # UTF-8 BOM for Excel
    filename = f"attendees-event-{event_id}.csv"
    return StreamingResponse(
        io.BytesIO(content),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/events/{event_id}/attendees", response_model=AdminAttendeeListResponse)
async def list_attendees(
    event_id: int,
    search: Optional[str] = Query(None, description="Case-insensitive name search"),
    batch_year: Optional[int] = Query(None, description="Exact batch year filter"),
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    user: Dict[str, Any] = Depends(require_event_admin),
):
    """Operational attendee list — active registrations only (status='registered').

    Ignores show_attendee_list. Ordered by registered_at ASC.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        event = await conn.fetchrow(
            "SELECT event_id FROM events WHERE event_id = $1", event_id
        )
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        repo = RegistrationRepository(conn)
        total = await repo.count_attendees(event_id, search, batch_year)
        rows = await repo.list_attendees(event_id, search, batch_year, page, per_page)
    return AdminAttendeeListResponse(
        attendees=[AdminAttendeeItem(**dict(r)) for r in rows],
        total=total,
        page=page,
        per_page=per_page,
    )


@router.get("/events/{event_id}/registrations", response_model=AdminRegistrationListResponse)
async def list_registrations(
    event_id: int,
    status: Optional[str] = Query(None, description="registered | cancelled"),
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    user: Dict[str, Any] = Depends(require_event_admin),
):
    """Audit view — all registration statuses. Supports status filter.

    Future statuses are automatically supported without code changes.
    """
    pool = await get_pool()
    async with pool.acquire() as conn:
        event = await conn.fetchrow(
            "SELECT event_id FROM events WHERE event_id = $1", event_id
        )
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        repo = RegistrationRepository(conn)
        total = await repo.count_registrations(event_id, status)
        rows = await repo.list_registrations(event_id, status, page, per_page)
    return AdminRegistrationListResponse(
        registrations=[AdminRegistrationItem(**dict(r)) for r in rows],
        total=total,
        page=page,
        per_page=per_page,
    )


# ── Check-In ──────────────────────────────────────────────────────────────────

@router.get("/events/{event_id}/check-ins/verify", response_model=QRVerifyResponse)
async def verify_qr(
    event_id: int,
    qr_token: str = Query(...),
    user: Dict[str, Any] = Depends(require_event_admin),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = CheckInService(conn)
        return await svc.verify_qr(event_id, qr_token)


@router.post("/events/{event_id}/check-ins", response_model=CheckInResponse, status_code=201)
async def check_in(
    event_id: int,
    body: CheckInCreate,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = CheckInService(conn)
        checkin = await svc.check_in(event_id, body, user)
    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="check_in_created",
        entity_type="registration",
        entity_id=checkin["registration_id"],
        context={"event_id": event_id, "checkin_id": checkin["checkin_id"]},
    )
    return dict(checkin)


@router.get("/events/{event_id}/check-ins", response_model=List[CheckInResponse])
async def list_checkins(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    pool = await get_pool()
    async with pool.acquire() as conn:
        svc = CheckInService(conn)
        checkins = await svc.list_checkins(event_id)
        return [dict(c) for c in checkins]


@router.get("/events/{event_id}/check-in-attempts")
async def list_checkin_attempts(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
):
    """PARTIAL capability: no check_in_attempts table exists in the active
    schema (it targeted a superseded migration) — there is nowhere to read
    rejected/invalid scan attempts from. Returns an honest 501 rather than
    fabricating empty or synthetic data. See the admin-event-schema
    -alignment sprint report and the operations runbook's Known
    Limitations for the product/schema decision behind this."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        event = await conn.fetchval("SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1)", event_id)
    if not event:
        raise HTTPException(status_code=404, detail="event_not_found")
    raise HTTPException(
        status_code=501,
        detail="check_in_attempt_logging_not_supported_by_current_schema",
    )
