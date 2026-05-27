from typing import Dict, Any, List
from datetime import datetime, timezone
import asyncpg
from fastapi import HTTPException
from app.repositories.event_repository import EventRepository
from app.repositories.registration_repository import RegistrationRepository
from app.schemas.registrations import RegistrationCreate
from app.utils.token_utils import generate_qr_token


class RegistrationService:
    def __init__(self, conn: asyncpg.Connection):
        self.event_repo = EventRepository(conn)
        self.reg_repo = RegistrationRepository(conn)

    async def register(
        self,
        event_id: int,
        data: RegistrationCreate,
        user: Dict[str, Any],
    ) -> asyncpg.Record:
        event = await self.event_repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        if event["status"] != "published":
            raise HTTPException(status_code=400, detail="event_not_published")

        # Registration window checks
        now = datetime.now(timezone.utc)
        if event["registration_closes_at"] and now > event["registration_closes_at"]:
            raise HTTPException(status_code=400, detail="registration_closed")
        if event["registration_opens_at"] and now < event["registration_opens_at"]:
            raise HTTPException(status_code=400, detail="registration_not_open_yet")

        # Capacity check
        if event["capacity"] is not None:
            existing = await self.reg_repo.list_by_event(event_id)
            active = [r for r in existing if r["status"] != "cancelled"]
            if len(active) >= event["capacity"]:
                raise HTTPException(status_code=409, detail="capacity_reached")

        # Duplicate checks
        dup_email = await self.reg_repo.find_active_by_email(event_id, str(data.email))
        if dup_email:
            raise HTTPException(status_code=409, detail="registration_duplicate")

        effective_ref_id = data.ref_id or user.get("ref_id")
        if effective_ref_id:
            dup_ref = await self.reg_repo.find_active_by_ref_id(event_id, effective_ref_id)
            if dup_ref:
                raise HTTPException(status_code=409, detail="registration_duplicate")

        # Merge auth context into registration data
        if not data.firebase_uid:
            data.firebase_uid = user.get("firebase_uid")
        if not data.ref_id:
            data.ref_id = user.get("ref_id")

        qr_token = generate_qr_token()
        registration = await self.reg_repo.create(event_id, data, qr_token)
        await self.reg_repo.create_attendee(registration["registration_id"], event_id, data)
        return registration

    async def get_registration(self, event_id: int, registration_id: int) -> asyncpg.Record:
        reg = await self.reg_repo.get_by_id(registration_id)
        if not reg:
            raise HTTPException(status_code=404, detail="registration_not_found")
        if reg["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="registration_not_found")
        return reg

    async def list_registrations(self, event_id: int) -> List[asyncpg.Record]:
        event = await self.event_repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        return await self.reg_repo.list_by_event(event_id)

    async def list_attendees(self, event_id: int) -> List[asyncpg.Record]:
        event = await self.event_repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        return await self.reg_repo.list_attendees_by_event(event_id)
