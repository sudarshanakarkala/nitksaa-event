from typing import Dict, Any, List, Optional
import asyncpg
from fastapi import HTTPException
from app.repositories.event_repository import EventRepository
from app.repositories.registration_repository import RegistrationRepository
from app.repositories.checkin_repository import CheckInRepository
from app.schemas.checkins import QRVerifyResponse, CheckInCreate


class CheckInService:
    def __init__(self, conn: asyncpg.Connection):
        self.event_repo = EventRepository(conn)
        self.reg_repo = RegistrationRepository(conn)
        self.checkin_repo = CheckInRepository(conn)

    async def verify_qr(self, event_id: int, qr_token: str) -> QRVerifyResponse:
        event = await self.event_repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")

        registration = await self.reg_repo.get_by_token(qr_token)
        if not registration:
            return QRVerifyResponse(
                valid=False,
                qr_token=qr_token,
                registration_id=None,
                attendee_id=None,
                full_name=None,
                email=None,
                ref_id=None,
                registration_status=None,
                already_checked_in=False,
                message="invalid_qr_token",
            )

        if registration["event_id"] != event_id:
            return QRVerifyResponse(
                valid=False,
                qr_token=qr_token,
                registration_id=registration["registration_id"],
                attendee_id=None,
                full_name=registration["full_name"],
                email=registration["email"],
                ref_id=registration["ref_id"],
                registration_status=registration["status"],
                already_checked_in=False,
                message="token_belongs_to_different_event",
            )

        attendee = await self.reg_repo.get_attendee_by_registration(registration["registration_id"])
        existing_checkin = await self.checkin_repo.find_existing_checkin(
            event_id, registration["registration_id"]
        )

        return QRVerifyResponse(
            valid=True,
            qr_token=qr_token,
            registration_id=registration["registration_id"],
            attendee_id=attendee["attendee_id"] if attendee else None,
            full_name=registration["full_name"],
            email=registration["email"],
            ref_id=registration["ref_id"],
            registration_status=registration["status"],
            already_checked_in=existing_checkin is not None,
            message="already_checked_in" if existing_checkin else "ready_to_checkin",
        )

    async def check_in(
        self,
        event_id: int,
        data: CheckInCreate,
        user: Dict[str, Any],
    ) -> asyncpg.Record:
        event = await self.event_repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")

        qr_token = data.qr_token
        registration = await self.reg_repo.get_by_token(qr_token)

        if not registration:
            await self.checkin_repo.log_attempt(
                event_id=event_id,
                qr_token=qr_token,
                registration_id=None,
                attendee_id=None,
                attempt_status="invalid",
                attempted_by=user["firebase_uid"],
                notes="token_not_found",
            )
            raise HTTPException(status_code=404, detail="invalid_qr_token")

        if registration["event_id"] != event_id:
            await self.checkin_repo.log_attempt(
                event_id=event_id,
                qr_token=qr_token,
                registration_id=registration["registration_id"],
                attendee_id=None,
                attempt_status="invalid",
                attempted_by=user["firebase_uid"],
                notes="token_belongs_to_different_event",
            )
            raise HTTPException(status_code=400, detail="invalid_qr_token")

        if registration["status"] == "cancelled":
            await self.checkin_repo.log_attempt(
                event_id=event_id,
                qr_token=qr_token,
                registration_id=registration["registration_id"],
                attendee_id=None,
                attempt_status="unauthorized",
                attempted_by=user["firebase_uid"],
                notes="registration_cancelled",
            )
            raise HTTPException(status_code=403, detail="registration_cancelled")

        attendee = await self.reg_repo.get_attendee_by_registration(registration["registration_id"])
        attendee_id = attendee["attendee_id"] if attendee else None

        existing = await self.checkin_repo.find_existing_checkin(event_id, registration["registration_id"])
        if existing:
            await self.checkin_repo.log_attempt(
                event_id=event_id,
                qr_token=qr_token,
                registration_id=registration["registration_id"],
                attendee_id=attendee_id,
                attempt_status="duplicate",
                attempted_by=user["firebase_uid"],
                notes="already_checked_in",
            )
            raise HTTPException(status_code=409, detail="already_checked_in")

        checkin = await self.checkin_repo.create_checkin(
            event_id=event_id,
            registration_id=registration["registration_id"],
            attendee_id=attendee_id,
            qr_token=qr_token,
            checked_in_by=user["firebase_uid"],
            session_id=data.session_id,
            ref_id=registration["ref_id"],
            firebase_uid=registration["firebase_uid"],
            notes=data.notes,
        )

        await self.reg_repo.set_registration_status(registration["registration_id"], "checked_in")

        await self.checkin_repo.log_attempt(
            event_id=event_id,
            qr_token=qr_token,
            registration_id=registration["registration_id"],
            attendee_id=attendee_id,
            attempt_status="success",
            attempted_by=user["firebase_uid"],
            notes=None,
        )
        return checkin

    async def list_checkins(self, event_id: int) -> List[asyncpg.Record]:
        event = await self.event_repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        return await self.checkin_repo.list_by_event(event_id)

    async def list_attempts(self, event_id: int) -> List[asyncpg.Record]:
        event = await self.event_repo.get_by_id(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        return await self.checkin_repo.list_attempts_by_event(event_id)
