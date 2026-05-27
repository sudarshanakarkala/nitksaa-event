from typing import List, Dict, Any
import asyncpg
from fastapi import HTTPException
from app.repositories.event_repository import EventRepository
from app.schemas.events import EventCreate, EventUpdate, SessionCreate

ALLOWED_STATUSES = {"draft", "published", "closed", "cancelled"}


class EventService:
    def __init__(self, conn: asyncpg.Connection):
        self.repo = EventRepository(conn)

    async def create_event(self, data: EventCreate, user: Dict[str, Any]) -> asyncpg.Record:
        if await self.repo.slug_exists(data.slug):
            raise HTTPException(status_code=409, detail="slug_already_exists")
        return await self.repo.create(data, created_by=user["firebase_uid"])

    async def update_event(self, event_id: int, data: EventUpdate, user: Dict[str, Any]) -> asyncpg.Record:
        event = await self.repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        if event["status"] in ("closed", "cancelled"):
            raise HTTPException(status_code=400, detail="event_not_editable")
        return await self.repo.update(event_id, data, updated_by=user["firebase_uid"])

    async def publish_event(self, event_id: int, user: Dict[str, Any]) -> asyncpg.Record:
        event = await self.repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        if event["status"] != "draft":
            raise HTTPException(status_code=400, detail="only_draft_events_can_be_published")
        return await self.repo.set_status(event_id, "published", user["firebase_uid"])

    async def close_event(self, event_id: int, user: Dict[str, Any]) -> asyncpg.Record:
        event = await self.repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        if event["status"] not in ("draft", "published"):
            raise HTTPException(status_code=400, detail="event_cannot_be_closed")
        return await self.repo.set_status(event_id, "closed", user["firebase_uid"])

    async def get_event(self, event_id: int) -> asyncpg.Record:
        event = await self.repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        return event

    async def get_published_event(self, event_id: int) -> asyncpg.Record:
        event = await self.get_event(event_id)
        if event["status"] != "published":
            raise HTTPException(status_code=400, detail="event_not_published")
        return event

    async def list_published_events(self) -> List[asyncpg.Record]:
        return await self.repo.list_published()

    async def list_all_events(self) -> List[asyncpg.Record]:
        return await self.repo.list_all()

    async def create_session(self, event_id: int, data: SessionCreate, user: Dict[str, Any]) -> asyncpg.Record:
        event = await self.get_event(event_id)
        if event["status"] in ("cancelled",):
            raise HTTPException(status_code=400, detail="event_not_editable")
        return await self.repo.create_session(event_id, data)

    async def list_sessions(self, event_id: int) -> List[asyncpg.Record]:
        await self.get_event(event_id)
        return await self.repo.list_sessions(event_id)
