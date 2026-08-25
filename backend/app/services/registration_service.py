"""Registration business logic.

Transaction safety: register_for_event issues SELECT ... FOR UPDATE on the event row
before the capacity check and INSERT, preventing double-registration under concurrent load.

Email failure policy: email is sent after the transaction commits. A failed send
updates confirmation_email_status to 'failed' but never rolls back the registration.
"""
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from fastapi import HTTPException

from app.database import get_pool
from app.repositories.registration_repository import RegistrationRepository
from app.schemas.registrations import (
    EventSummary,
    MyRegistrationsListResponse,
    RegisterRequest,
    RegistrationEligibilityResponse,
    RegistrationResponse,
)
from app.services import alumni_service, analytics_service, audit_service, email_service


def _resolve_join_url(row: Dict[str, Any]) -> Optional[str]:
    """Return virtual_url only for an active registration on a published virtual event."""
    if (
        row.get("status") == "registered"
        and row.get("is_virtual")
        and row.get("event_status") == "published"
    ):
        return row.get("virtual_url")
    return None


def _format_registration(row: Dict[str, Any]) -> RegistrationResponse:
    join_url = _resolve_join_url(row)
    event = EventSummary(
        event_id=row["event_id"],
        title=row["event_title"],
        start_datetime=row["start_datetime"],
        end_datetime=row["end_datetime"],
        timezone=row["timezone"],
        is_virtual=row["is_virtual"],
        location_text=row.get("location_text"),
        location_maps_url=row.get("location_maps_url"),
    )
    return RegistrationResponse(
        registration_id=row["registration_id"],
        registration_number=row.get("registration_number"),
        event_id=row["event_id"],
        firebase_uid=row["firebase_uid"],
        ref_id=row.get("ref_id"),
        status=row["status"],
        fullname_snapshot=row.get("fullname_snapshot"),
        email_snapshot=row.get("email_snapshot"),
        phone_snapshot=row.get("phone_snapshot"),
        batch_year_snapshot=row.get("batch_year_snapshot"),
        branch_snapshot=row.get("branch_snapshot"),
        attendee_note=row.get("attendee_note"),
        registered_at=row["registered_at"],
        cancelled_at=row.get("cancelled_at"),
        confirmation_email_status=row.get("confirmation_email_status"),
        confirmation_email_sent_at=row.get("confirmation_email_sent_at"),
        join_url=join_url,
        event=event,
        updated_at=row.get("updated_at"),
    )


async def register_for_event(
    event_id: int, user: Dict[str, Any], body: RegisterRequest
) -> RegistrationResponse:
    firebase_uid = user["firebase_uid"]
    ref_id = user.get("ref_id")

    if user.get("user_type") not in ["alumni", "admin"] or not ref_id:
        raise HTTPException(status_code=403, detail="alumni_only")

    profile = await alumni_service.get_alumni_profile_by_ref_id(ref_id)
    if not profile:
        raise HTTPException(status_code=403, detail="alumni_not_found")
    if not alumni_service.is_alumni_active(profile.get("registrationstatus")):
        raise HTTPException(status_code=403, detail="alumni_not_active")

    pool = await get_pool()
    registration_id: int
    reg_number: str

    async with pool.acquire() as conn:
        repo = RegistrationRepository(conn)

        async with conn.transaction():
            event_row = await conn.fetchrow(
                """
                SELECT event_id, status, capacity, is_virtual,
                       registration_opens_at, registration_closes_at
                FROM events
                WHERE event_id = $1
                FOR UPDATE
                """,
                event_id,
            )

            if not event_row:
                raise HTTPException(status_code=404, detail="event_not_found")
            if event_row["status"] != "published":
                raise HTTPException(status_code=409, detail="event_not_published")

            now = datetime.now(timezone.utc)
            opens_at = event_row["registration_opens_at"]
            closes_at = event_row["registration_closes_at"]
            if opens_at and now < opens_at:
                raise HTTPException(status_code=409, detail="registration_not_open_yet")
            if closes_at and now > closes_at:
                raise HTTPException(status_code=409, detail="registration_closed")

            if await repo.get_active_for_user(event_id, firebase_uid):
                await analytics_service.log_event_activity(
                    action_type="REGISTRATION_FAILED",
                    source_app="BACKEND",
                    event_id=event_id,
                    firebase_uid=firebase_uid,
                    metadata={"reason": "already_registered"},
                )
                raise HTTPException(status_code=409, detail="already_registered")

            capacity = event_row["capacity"]
            if capacity is not None:
                if await repo.count_active(event_id) >= capacity:
                    await analytics_service.log_event_activity(
                        action_type="REGISTRATION_FAILED",
                        source_app="BACKEND",
                        event_id=event_id,
                        firebase_uid=firebase_uid,
                        metadata={"reason": "event_full"},
                    )
                    raise HTTPException(status_code=409, detail="event_full")

            registration_id = await repo.insert(
                event_id=event_id,
                firebase_uid=firebase_uid,
                ref_id=ref_id,
                email=profile["email"],
                phone=profile.get("phone"),
                fullname_snapshot=profile.get("fullname"),
                batch_year_snapshot=profile.get("graduationyear"),
                branch_snapshot=profile.get("branch"),
                notes=body.attendee_note,
            )
            reg_number = f"NITKSAA-{datetime.now(timezone.utc).year}-{registration_id:06d}"
            await repo.set_registration_number(registration_id, reg_number)
        # Transaction committed

        full_row = dict(await repo.get_by_id_with_event(registration_id))

    await analytics_service.log_event_activity(
        action_type="REGISTRATION_COMPLETED",
        source_app="BACKEND",
        event_id=event_id,
        firebase_uid=firebase_uid,
        metadata={"registration_number": reg_number},
    )

    email_result = await email_service.send_confirmation_email(
        email_to=profile["email"],
        fullname=profile.get("fullname", ""),
        event_title=full_row.get("event_title", ""),
        registration_number=reg_number,
        join_url=_resolve_join_url(full_row),
    )

    print(f"Email send result: {email_result.status}, error={email_result.error}")

    email_action = "EMAIL_SENT" if email_result.status == "sent" else "EMAIL_FAILED"
    await analytics_service.log_event_activity(
        action_type=email_action,
        source_app="EMAIL",
        event_id=event_id,
        firebase_uid=firebase_uid,
        metadata={"registration_number": reg_number},
    )

    async with pool.acquire() as conn2:
        await RegistrationRepository(conn2).update_email_status(
            registration_id=registration_id,
            status=email_result.status,
            sent_at=email_result.sent_at,
            error=email_result.error,
        )
    full_row["confirmation_email_status"] = email_result.status
    full_row["confirmation_email_sent_at"] = email_result.sent_at

    await audit_service.emit(
        actor_uid=firebase_uid,
        event_type="registration_created",
        entity_type="registration",
        entity_id=registration_id,
        context={"event_id": event_id, "registration_number": reg_number},
    )

    return _format_registration(full_row)


async def get_my_event_registration(
    event_id: int, user: Dict[str, Any]
) -> RegistrationResponse:
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await RegistrationRepository(conn).get_latest_for_user_event(
            event_id, user["firebase_uid"]
        )
    if not row:
        raise HTTPException(status_code=404, detail="registration_not_found")
    return _format_registration(dict(row))


async def cancel_my_event_registration(
    event_id: int, user: Dict[str, Any]
) -> RegistrationResponse:
    firebase_uid = user["firebase_uid"]
    pool = await get_pool()

    async with pool.acquire() as conn:
        repo = RegistrationRepository(conn)
        async with conn.transaction():
            event_row = await conn.fetchrow(
                """
                SELECT event_id, status, registration_opens_at, registration_closes_at
                FROM events
                WHERE event_id = $1
                FOR UPDATE
                """,
                event_id,
            )
            if not event_row:
                raise HTTPException(status_code=404, detail="event_not_found")
            if event_row["status"] != "published":
                raise HTTPException(status_code=409, detail="event_not_open")

            now = datetime.now(timezone.utc)
            opens_at = event_row["registration_opens_at"]
            closes_at = event_row["registration_closes_at"]
            if opens_at and now < opens_at:
                raise HTTPException(status_code=409, detail="registration_not_open_yet")
            if closes_at and now > closes_at:
                raise HTTPException(status_code=409, detail="registration_closed")

            registration_id = await repo.cancel_active_for_user(event_id, firebase_uid)
            if not registration_id:
                raise HTTPException(status_code=404, detail="active_registration_not_found")

        row = await repo.get_by_id_with_event(registration_id)

    await analytics_service.log_event_activity(
        action_type="REGISTRATION_FAILED",
        source_app="BACKEND",
        event_id=event_id,
        firebase_uid=firebase_uid,
        metadata={"reason": "cancelled_by_user"},
    )
    await audit_service.emit(
        actor_uid=firebase_uid,
        event_type="registration_cancelled",
        entity_type="registration",
        entity_id=registration_id,
        context={"event_id": event_id},
    )
    return _format_registration(dict(row))


async def list_my_registrations(user: Dict[str, Any]) -> MyRegistrationsListResponse:
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await RegistrationRepository(conn).list_for_user(user["firebase_uid"])
    regs = [_format_registration(dict(r)) for r in rows]
    return MyRegistrationsListResponse(registrations=regs, total=len(regs))


async def get_registration_eligibility(
    event_id: int, user: Dict[str, Any]
) -> RegistrationEligibilityResponse:
    firebase_uid = user["firebase_uid"]
    ref_id = user.get("ref_id")

    def _ineligible(msg: str) -> RegistrationEligibilityResponse:
        return RegistrationEligibilityResponse(
            event_id=event_id,
            firebase_uid=firebase_uid,
            eligibility_status="ineligible",
            message=msg,
        )

    if user.get("user_type") not in ["alumni", "admin"] or not ref_id:
        return _ineligible(user.get("user_type") + "Only alumni can register for events.")

    profile = await alumni_service.get_alumni_profile_by_ref_id(ref_id)
    if not profile or not alumni_service.is_alumni_active(profile.get("registrationstatus")):
        return _ineligible("Alumni account is not active.")

    pool = await get_pool()
    async with pool.acquire() as conn:
        repo = RegistrationRepository(conn)
        event_row = await conn.fetchrow(
            """
            SELECT status, capacity, registration_opens_at, registration_closes_at
            FROM events WHERE event_id = $1
            """,
            event_id,
        )
        if not event_row:
            return _ineligible("Event not found.")
        if event_row["status"] != "published":
            return _ineligible("Event is not open for registration.")

        now = datetime.now(timezone.utc)
        opens_at = event_row["registration_opens_at"]
        closes_at = event_row["registration_closes_at"]
        if opens_at and now < opens_at:
            return RegistrationEligibilityResponse(
                event_id=event_id,
                firebase_uid=firebase_uid,
                eligibility_status="not_open_yet",
                message="Registration has not opened yet.",
            )
        if closes_at and now > closes_at:
            return RegistrationEligibilityResponse(
                event_id=event_id,
                firebase_uid=firebase_uid,
                eligibility_status="closed",
                message="Registration is closed.",
            )

        if await repo.get_active_for_user(event_id, firebase_uid):
            return RegistrationEligibilityResponse(
                event_id=event_id,
                firebase_uid=firebase_uid,
                eligibility_status="already_registered",
                message="You are already registered for this event.",
            )

        capacity = event_row["capacity"]
        active_count = await repo.count_active(event_id)

        if capacity is not None and active_count >= capacity:
            return RegistrationEligibilityResponse(
                event_id=event_id,
                firebase_uid=firebase_uid,
                eligibility_status="full",
                message="Event is at full capacity.",
                registered_count=active_count,
                capacity=capacity,
            )

        return RegistrationEligibilityResponse(
            event_id=event_id,
            firebase_uid=firebase_uid,
            eligibility_status="eligible",
            message="You are eligible to register.",
            registered_count=active_count,
            capacity=capacity,
        )
