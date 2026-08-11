from typing import Any, Dict, List

import asyncpg
from fastapi import HTTPException

from app.repositories.checkin_repository import CheckInRepository
from app.repositories.events_repository import EventsRepository
from app.repositories.registration_repository import RegistrationRepository
from app.schemas.checkins import CheckInCreate, QRVerifyResponse

# A registration is eligible for check-in only once it's fully confirmed —
# 'registered' is the only terminal, paid-or-free-confirmed state in the
# active status vocabulary (seat_held/payment_pending/payment_verification/
# payment_failed/cancelled are all non-eligible).
_ELIGIBLE_STATUS = "registered"


class CheckInService:
    def __init__(self, conn: asyncpg.Connection):
        self.event_repo = EventsRepository(conn)
        self.reg_repo = RegistrationRepository(conn)
        self.checkin_repo = CheckInRepository(conn)

    async def verify_qr(self, event_id: int, qr_token: str) -> QRVerifyResponse:
        event = await self.event_repo.get_event(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")

        registration = await self.reg_repo.get_by_qrtoken(qr_token)
        if not registration:
            return QRVerifyResponse(
                valid=False,
                qr_token=qr_token,
                already_checked_in=False,
                message="invalid_qr_token",
            )

        if registration["event_id"] != event_id:
            return QRVerifyResponse(
                valid=False,
                qr_token=qr_token,
                registration_id=registration["registration_id"],
                full_name=registration["fullname_snapshot"],
                email=registration["email"],
                ref_id=registration["ref_id"],
                registration_status=registration["status"],
                already_checked_in=False,
                message="token_belongs_to_different_event",
            )

        if registration["status"] != _ELIGIBLE_STATUS:
            return QRVerifyResponse(
                valid=False,
                qr_token=qr_token,
                registration_id=registration["registration_id"],
                full_name=registration["fullname_snapshot"],
                email=registration["email"],
                ref_id=registration["ref_id"],
                registration_status=registration["status"],
                already_checked_in=False,
                message="registration_not_eligible",
            )

        existing = await self.checkin_repo.find_existing_checkin(event_id, registration["registration_id"])
        return QRVerifyResponse(
            valid=existing is None,
            qr_token=qr_token,
            registration_id=registration["registration_id"],
            full_name=registration["fullname_snapshot"],
            email=registration["email"],
            ref_id=registration["ref_id"],
            registration_status=registration["status"],
            already_checked_in=existing is not None,
            message="already_checked_in" if existing else "ready_to_checkin",
        )

    async def check_in(
        self,
        event_id: int,
        data: CheckInCreate,
        user: Dict[str, Any],
    ) -> asyncpg.Record:
        event = await self.event_repo.get_event(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")

        registration = await self.reg_repo.get_by_qrtoken(data.qr_token)
        if not registration:
            raise HTTPException(status_code=404, detail="invalid_qr_token")

        if registration["event_id"] != event_id:
            raise HTTPException(status_code=400, detail="registration_belongs_to_different_event")

        if registration["status"] != _ELIGIBLE_STATUS:
            raise HTTPException(status_code=403, detail="registration_not_eligible")

        existing = await self.checkin_repo.find_existing_checkin(event_id, registration["registration_id"])
        if existing:
            raise HTTPException(status_code=409, detail="already_checked_in")

        try:
            return await self.checkin_repo.create_checkin(
                event_id=event_id,
                registration_id=registration["registration_id"],
                session_id=data.session_id,
                scanned_by=user["firebase_uid"],
            )
        except asyncpg.exceptions.UniqueViolationError:
            # Lost the race against a concurrent check-in for the same
            # registration — uq_check_ins_event_registration (migration
            # 019) is the actual guard; the check above is a fast path,
            # not the source of truth. Same clean 409 a sequential
            # duplicate gets, never a 500.
            raise HTTPException(status_code=409, detail="already_checked_in")

    async def list_checkins(self, event_id: int) -> List[asyncpg.Record]:
        event = await self.event_repo.get_event(event_id)
        if not event:
            raise HTTPException(status_code=404, detail="event_not_found")
        return await self.checkin_repo.list_by_event(event_id)
