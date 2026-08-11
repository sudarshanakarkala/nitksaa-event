"""Admin CRUD for event sponsors and partners.

Authorization: real Firebase-JWT-backed RBAC via app.middleware.admin_auth
(platform_admin, or event_admin scoped to the event_id in the route) —
migrated off the development-only app.middleware.dev_auth placeholder in
the admin-auth-unification sprint. Public presentation of sponsors/
partners is unaffected — it is served separately by
EventsService.get_public_event (app/api/events.py's
/events/public/{event_id}), which already only ever returns
is_visible=true rows via {Sponsors,Partners}Repository.list_public_by_event;
this router has no public routes and none were added.
"""
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException

from app.database import get_pool
from app.middleware.admin_auth import require_event_admin
from app.repositories.sponsors_partners_repository import SponsorsRepository, PartnersRepository
from app.schemas.sponsors_partners import (
    SponsorCreate, SponsorResponse, SponsorUpdate,
    PartnerCreate, PartnerResponse, PartnerUpdate,
)
from app.services import audit_service

router = APIRouter(prefix="/api/v1/events", tags=["sponsors", "partners"])


async def _require_event(conn, event_id: int) -> None:
    row = await conn.fetchrow("SELECT event_id FROM events WHERE event_id = $1", event_id)
    if not row:
        raise HTTPException(status_code=404, detail="event_not_found")


# ── Sponsors ──────────────────────────────────────────────────────────────────

@router.get("/{event_id}/sponsors", response_model=List[SponsorResponse])
async def list_sponsors(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> List[Dict[str, Any]]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _require_event(conn, event_id)
        rows = await SponsorsRepository(conn).list_by_event(event_id)
    return [dict(r) for r in rows]


@router.post("/{event_id}/sponsors", response_model=SponsorResponse, status_code=201)
async def create_sponsor(
    event_id: int,
    body: SponsorCreate,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _require_event(conn, event_id)
        row = await SponsorsRepository(conn).create(event_id, body)
    await audit_service.emit(
        actor_uid=user["firebase_uid"], event_type="sponsor_created",
        entity_type="sponsor", entity_id=row["sponsor_id"], context={"event_id": event_id},
    )
    return dict(row)


@router.put("/{event_id}/sponsors/{sponsor_id}", response_model=SponsorResponse)
async def update_sponsor(
    event_id: int,
    sponsor_id: int,
    body: SponsorUpdate,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = SponsorsRepository(conn)
        existing = await repo.get(sponsor_id)
        if not existing or existing["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="sponsor_not_found")
        row = await repo.update(sponsor_id, body)
    await audit_service.emit(
        actor_uid=user["firebase_uid"], event_type="sponsor_updated",
        entity_type="sponsor", entity_id=sponsor_id, context={"event_id": event_id},
    )
    return dict(row)


@router.delete("/{event_id}/sponsors/{sponsor_id}", status_code=204)
async def delete_sponsor(
    event_id: int,
    sponsor_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = SponsorsRepository(conn)
        existing = await repo.get(sponsor_id)
        if not existing or existing["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="sponsor_not_found")
        await repo.delete(sponsor_id)
    await audit_service.emit(
        actor_uid=user["firebase_uid"], event_type="sponsor_deleted",
        entity_type="sponsor", entity_id=sponsor_id, context={"event_id": event_id},
    )


# ── Partners ──────────────────────────────────────────────────────────────────

@router.get("/{event_id}/partners", response_model=List[PartnerResponse])
async def list_partners(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> List[Dict[str, Any]]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _require_event(conn, event_id)
        rows = await PartnersRepository(conn).list_by_event(event_id)
    return [dict(r) for r in rows]


@router.post("/{event_id}/partners", response_model=PartnerResponse, status_code=201)
async def create_partner(
    event_id: int,
    body: PartnerCreate,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _require_event(conn, event_id)
        row = await PartnersRepository(conn).create(event_id, body)
    await audit_service.emit(
        actor_uid=user["firebase_uid"], event_type="partner_created",
        entity_type="partner", entity_id=row["partner_id"], context={"event_id": event_id},
    )
    return dict(row)


@router.put("/{event_id}/partners/{partner_id}", response_model=PartnerResponse)
async def update_partner(
    event_id: int,
    partner_id: int,
    body: PartnerUpdate,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = PartnersRepository(conn)
        existing = await repo.get(partner_id)
        if not existing or existing["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="partner_not_found")
        row = await repo.update(partner_id, body)
    await audit_service.emit(
        actor_uid=user["firebase_uid"], event_type="partner_updated",
        entity_type="partner", entity_id=partner_id, context={"event_id": event_id},
    )
    return dict(row)


@router.delete("/{event_id}/partners/{partner_id}", status_code=204)
async def delete_partner(
    event_id: int,
    partner_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = PartnersRepository(conn)
        existing = await repo.get(partner_id)
        if not existing or existing["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="partner_not_found")
        await repo.delete(partner_id)
    await audit_service.emit(
        actor_uid=user["firebase_uid"], event_type="partner_deleted",
        entity_type="partner", entity_id=partner_id, context={"event_id": event_id},
    )
