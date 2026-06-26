"""Admin CRUD for event sponsors and partners."""
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException

from app.database import get_pool
from app.middleware.dev_auth import get_admin_user
from app.repositories.sponsors_partners_repository import SponsorsRepository, PartnersRepository
from app.schemas.sponsors_partners import (
    SponsorCreate, SponsorResponse, SponsorUpdate,
    PartnerCreate, PartnerResponse, PartnerUpdate,
)

router = APIRouter(prefix="/api/v1/events", tags=["sponsors", "partners"])


async def _require_event(conn, event_id: int) -> None:
    row = await conn.fetchrow("SELECT event_id FROM events WHERE event_id = $1", event_id)
    if not row:
        raise HTTPException(status_code=404, detail="event_not_found")


# ── Sponsors ──────────────────────────────────────────────────────────────────

@router.get("/{event_id}/sponsors", response_model=List[SponsorResponse])
async def list_sponsors(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
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
    user: Dict[str, Any] = Depends(get_admin_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _require_event(conn, event_id)
        row = await SponsorsRepository(conn).create(event_id, body)
    return dict(row)


@router.put("/{event_id}/sponsors/{sponsor_id}", response_model=SponsorResponse)
async def update_sponsor(
    event_id: int,
    sponsor_id: int,
    body: SponsorUpdate,
    user: Dict[str, Any] = Depends(get_admin_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = SponsorsRepository(conn)
        existing = await repo.get(sponsor_id)
        if not existing or existing["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="sponsor_not_found")
        row = await repo.update(sponsor_id, body)
    return dict(row)


@router.delete("/{event_id}/sponsors/{sponsor_id}", status_code=204)
async def delete_sponsor(
    event_id: int,
    sponsor_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
) -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = SponsorsRepository(conn)
        existing = await repo.get(sponsor_id)
        if not existing or existing["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="sponsor_not_found")
        await repo.delete(sponsor_id)


# ── Partners ──────────────────────────────────────────────────────────────────

@router.get("/{event_id}/partners", response_model=List[PartnerResponse])
async def list_partners(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
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
    user: Dict[str, Any] = Depends(get_admin_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _require_event(conn, event_id)
        row = await PartnersRepository(conn).create(event_id, body)
    return dict(row)


@router.put("/{event_id}/partners/{partner_id}", response_model=PartnerResponse)
async def update_partner(
    event_id: int,
    partner_id: int,
    body: PartnerUpdate,
    user: Dict[str, Any] = Depends(get_admin_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = PartnersRepository(conn)
        existing = await repo.get(partner_id)
        if not existing or existing["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="partner_not_found")
        row = await repo.update(partner_id, body)
    return dict(row)


@router.delete("/{event_id}/partners/{partner_id}", status_code=204)
async def delete_partner(
    event_id: int,
    partner_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
) -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = PartnersRepository(conn)
        existing = await repo.get(partner_id)
        if not existing or existing["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="partner_not_found")
        await repo.delete(partner_id)
