"""Event form content (admin revamp step 5b): speakers, sessions and fee tiers.

The event form edits these as lists. It sends the whole of each list after
the event itself saves; the backend works out what to add, change and
remove, in one transaction, so a save never half-applies.

  GET /api/v1/admin/events/{event_id}/content   -> the three lists, with ids
  PUT /api/v1/admin/events/{event_id}/content   -> replace them

Speakers are the event's people with a speaker-type role (Speaker,
Panelist, Chief guest, Guest of honour); other people (hosts, organisers)
are left alone. A session that already has door check-ins can't be
removed (409 session_has_check_ins).
"""
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.database import get_pool
from app.middleware.admin_auth import require_event_admin
from app.services import audit_service

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

SPEAKER_ROLES = ("SPEAKER", "PANELIST", "CHIEF_GUEST", "GUEST_OF_HONOUR")
FEE_TYPES = {"participation", "accommodation", "contributions", "food_pass", "merchandise", "other"}


class SpeakerIn(BaseModel):
    person_id: Optional[int] = None
    fullname: str = Field(..., min_length=1, max_length=255)
    title: Optional[str] = None
    organisation: Optional[str] = None


class SessionIn(BaseModel):
    session_id: Optional[int] = None
    title: str = Field(..., min_length=1, max_length=255)
    speaker_name: Optional[str] = None
    start_datetime: datetime
    end_datetime: datetime


class FeeIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    fee_type: str = "participation"
    amount: Decimal = Field(..., ge=0)

    @field_validator("fee_type")
    @classmethod
    def _type(cls, v: str) -> str:
        v = (v or "participation").strip().lower()
        if v not in FEE_TYPES:
            raise ValueError(f"fee_type must be one of: {', '.join(sorted(FEE_TYPES))}")
        return v


class EventContentIn(BaseModel):
    speakers: List[SpeakerIn] = []
    sessions: List[SessionIn] = []
    fees: List[FeeIn] = []


def _blank_to_none(v: Optional[str]) -> Optional[str]:
    v = (v or "").strip()
    return v or None


async def _read(conn, event_id: int) -> Dict[str, Any]:
    speakers = await conn.fetch(
        """
        SELECT person_id, fullname, title, organisation, role
        FROM event_people
        WHERE event_id = $1::int AND role::text = ANY($2::text[])
        ORDER BY display_order, person_id
        """,
        event_id, list(SPEAKER_ROLES),
    )
    sessions = await conn.fetch(
        """
        SELECT session_id, title, speaker_name, start_datetime, end_datetime
        FROM sessions WHERE event_id = $1::int
        ORDER BY sort_order, start_datetime
        """,
        event_id,
    )
    fees = await conn.fetch(
        """
        SELECT fee_id, name, fee_type, amount
        FROM event_fees WHERE event_id = $1::int
        ORDER BY display_order, fee_id
        """,
        event_id,
    )
    return {
        "speakers": [dict(r) for r in speakers],
        "sessions": [dict(r) for r in sessions],
        "fees": [{**dict(r), "amount": float(r["amount"])} for r in fees],
    }


@router.get("/events/{event_id}/content")
async def get_event_content(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        return await _read(conn, event_id)


@router.put("/events/{event_id}/content")
async def put_event_content(
    event_id: int,
    body: EventContentIn,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            # ── Speakers ────────────────────────────────────────────────
            existing = {
                r["person_id"]
                for r in await conn.fetch(
                    "SELECT person_id FROM event_people WHERE event_id = $1::int AND role::text = ANY($2::text[])",
                    event_id, list(SPEAKER_ROLES),
                )
            }
            kept: set = set()
            for order, sp in enumerate(body.speakers):
                if sp.person_id is not None and sp.person_id in existing:
                    kept.add(sp.person_id)
                    await conn.execute(
                        """
                        UPDATE event_people
                        SET fullname = $2::text, title = $3::text, organisation = $4::text,
                            display_order = $5::int, updated_at = now()
                        WHERE person_id = $1::int
                        """,
                        sp.person_id, sp.fullname.strip(), _blank_to_none(sp.title),
                        _blank_to_none(sp.organisation), order,
                    )
                else:
                    await conn.execute(
                        """
                        INSERT INTO event_people (event_id, role, fullname, title, organisation, display_order, is_visible)
                        VALUES ($1::int, 'SPEAKER', $2::text, $3::text, $4::text, $5::int, true)
                        """,
                        event_id, sp.fullname.strip(), _blank_to_none(sp.title),
                        _blank_to_none(sp.organisation), order,
                    )
            removed = existing - kept
            if removed:
                await conn.execute(
                    "DELETE FROM event_people WHERE person_id = ANY($1::int[])", list(removed)
                )

            # ── Sessions ────────────────────────────────────────────────
            existing = {
                r["session_id"]
                for r in await conn.fetch(
                    "SELECT session_id FROM sessions WHERE event_id = $1::int", event_id
                )
            }
            kept = set()
            for order, s in enumerate(body.sessions):
                if s.end_datetime < s.start_datetime:
                    raise HTTPException(status_code=422, detail="session_ends_before_it_starts")
                if s.session_id is not None and s.session_id in existing:
                    kept.add(s.session_id)
                    await conn.execute(
                        """
                        UPDATE sessions
                        SET title = $2::text, speaker_name = $3::text,
                            start_datetime = $4::timestamptz, end_datetime = $5::timestamptz,
                            sort_order = $6::int
                        WHERE session_id = $1::int
                        """,
                        s.session_id, s.title.strip(), _blank_to_none(s.speaker_name),
                        s.start_datetime, s.end_datetime, order,
                    )
                else:
                    await conn.execute(
                        """
                        INSERT INTO sessions (event_id, title, speaker_name, start_datetime, end_datetime, sort_order)
                        VALUES ($1::int, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::int)
                        """,
                        event_id, s.title.strip(), _blank_to_none(s.speaker_name),
                        s.start_datetime, s.end_datetime, order,
                    )
            removed = existing - kept
            if removed:
                in_use = await conn.fetchval(
                    "SELECT EXISTS(SELECT 1 FROM check_ins WHERE session_id = ANY($1::int[]))",
                    list(removed),
                )
                if in_use:
                    raise HTTPException(status_code=409, detail="session_has_check_ins")
                await conn.execute(
                    "DELETE FROM sessions WHERE session_id = ANY($1::int[])", list(removed)
                )

            # ── Fees (nothing refers to them: replace the list) ─────────
            await conn.execute("DELETE FROM event_fees WHERE event_id = $1::int", event_id)
            for order, f in enumerate(body.fees):
                await conn.execute(
                    """
                    INSERT INTO event_fees (event_id, name, fee_type, amount, display_order)
                    VALUES ($1::int, $2::text, $3::text, $4::numeric, $5::int)
                    """,
                    event_id, f.name.strip(), f.fee_type, f.amount, order,
                )

        result = await _read(conn, event_id)

    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="event_content_updated",
        entity_type="event",
        entity_id=event_id,
        context={
            "event_id": event_id,
            "speakers": len(body.speakers),
            "sessions": len(body.sessions),
            "fees": len(body.fees),
        },
    )
    return result
