"""Admin CRUD for event people (speakers, hosts, guests, etc.)."""
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException

from app.database import get_pool
from app.middleware.dev_auth import get_admin_user
from app.repositories.people_repository import PeopleRepository
from app.schemas.people import PersonCreate, PersonResponse, PersonUpdate

router = APIRouter(prefix="/api/v1/events", tags=["people"])


async def _require_event(conn, event_id: int) -> None:
    row = await conn.fetchrow("SELECT event_id FROM events WHERE event_id = $1", event_id)
    if not row:
        raise HTTPException(status_code=404, detail="event_not_found")


async def _require_person(repo: PeopleRepository, person_id: int, event_id: int) -> Dict[str, Any]:
    row = await repo.get(person_id)
    if not row or row["event_id"] != event_id:
        raise HTTPException(status_code=404, detail="person_not_found")
    return dict(row)


@router.get("/{event_id}/people", response_model=List[PersonResponse])
async def list_people(
    event_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
) -> List[Dict[str, Any]]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _require_event(conn, event_id)
        repo = PeopleRepository(conn)
        rows = await repo.list_by_event(event_id)
    return [dict(r) for r in rows]


@router.post("/{event_id}/people", response_model=PersonResponse, status_code=201)
async def create_person(
    event_id: int,
    body: PersonCreate,
    user: Dict[str, Any] = Depends(get_admin_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        await _require_event(conn, event_id)
        repo = PeopleRepository(conn)
        row = await repo.create(event_id, body)
    return dict(row)


@router.put("/{event_id}/people/{person_id}", response_model=PersonResponse)
async def update_person(
    event_id: int,
    person_id: int,
    body: PersonUpdate,
    user: Dict[str, Any] = Depends(get_admin_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = PeopleRepository(conn)
        await _require_person(repo, person_id, event_id)
        row = await repo.update(person_id, body)
    return dict(row)


@router.delete("/{event_id}/people/{person_id}", status_code=204)
async def delete_person(
    event_id: int,
    person_id: int,
    user: Dict[str, Any] = Depends(get_admin_user),
) -> None:
    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = PeopleRepository(conn)
        await _require_person(repo, person_id, event_id)
        await repo.delete(person_id)
