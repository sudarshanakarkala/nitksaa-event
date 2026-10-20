"""Event form details (admin revamp step 5b): speakers, sessions and fee tiers.

(Not to be confused with the event_content table, which holds recordings
and gallery links.)

The event form edits these as lists. It sends the whole of each list after
the event itself saves; the backend works out what to add, change and
remove, in one transaction, so a save never half-applies.

  GET /api/v1/admin/events/{event_id}/details   -> the three lists, with ids
  PUT /api/v1/admin/events/{event_id}/details   -> replace them

Speakers are the event's people with a speaker-type role (Speaker,
Panelist, Chief guest, Guest of honour, Moderator); other people (hosts,
organisers) are left alone. A session that already has door check-ins
can't be removed (409 session_has_check_ins).

Session details: each session may also carry its type, pillar, hall
(`track`), subtitle (`description`), the people on it (`people`, by name,
with a moderator flag) and the sponsors presenting it (`presented_by`, by
name). Names are matched, ignoring case, against the event's people and
sponsors as saved (the form saves sponsors before this). An unknown name is
refused (422 unknown_speaker / unknown_sponsor) and nothing is saved. A
field the request leaves out is left as it is, so an older app can't wipe
these.

Speakers' private and extra details: email and phone (admin only),
batch, LinkedIn, photo and bio; each left as it is when the request leaves
it out.

While a Google Sheet is linked, the sheet owns speakers and sessions:
this save then changes only the fees, whatever the request says.
"""
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.database import get_pool
from app.middleware.admin_auth import require_event_admin
from app.services import audit_service
from app.api.admin_event_sheet import is_linked

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

SPEAKER_ROLES = ("SPEAKER", "PANELIST", "CHIEF_GUEST", "GUEST_OF_HONOUR", "MODERATOR")
SESSION_TYPES = {
    "KEYNOTE", "TALK", "PANEL", "FIRESIDE", "WORKSHOP",
    "SHOWCASE", "NETWORKING", "AWARDS", "BREAK",
}
# Session columns a request may leave out (kept as they are when it does).
_OPTIONAL_SESSION_COLUMNS = ("session_type", "pillar", "track", "description")
# The same for speakers.
_OPTIONAL_SPEAKER_COLUMNS = ("email", "phone", "batch", "linkedin_url", "photo_url", "bio")
FEE_TYPES = {"participation", "accommodation", "contributions", "food_pass", "merchandise", "other"}


class SpeakerIn(BaseModel):
    person_id: Optional[int] = None
    fullname: str = Field(..., min_length=1, max_length=255)
    title: Optional[str] = None
    organisation: Optional[str] = None
    # Left out: kept as it is (new people are speakers).
    role: Optional[str] = None
    # Each is left as it is when the request leaves it out.
    email: Optional[str] = Field(None, max_length=320)
    phone: Optional[str] = Field(None, max_length=64)
    batch: Optional[str] = Field(None, max_length=120)
    linkedin_url: Optional[str] = Field(None, max_length=2048)
    photo_url: Optional[str] = Field(None, max_length=2048)
    bio: Optional[str] = Field(None, max_length=5000)

    @field_validator("role")
    @classmethod
    def _role(cls, v: Optional[str]) -> Optional[str]:
        v = (v or "").strip().upper()
        if not v:
            return None
        if v not in SPEAKER_ROLES:
            raise ValueError(f"role must be one of: {', '.join(SPEAKER_ROLES)}")
        return v


class SessionPersonIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    moderator: bool = False


class SessionIn(BaseModel):
    session_id: Optional[int] = None
    title: str = Field(..., min_length=1, max_length=255)
    speaker_name: Optional[str] = None
    start_datetime: datetime
    end_datetime: datetime
    # Each is left as it is when the request leaves it out.
    session_type: Optional[str] = None
    pillar: Optional[str] = None
    track: Optional[str] = None
    description: Optional[str] = None
    people: Optional[List[SessionPersonIn]] = None
    presented_by: Optional[List[str]] = None

    @field_validator("session_type")
    @classmethod
    def _type(cls, v: Optional[str]) -> Optional[str]:
        v = (v or "").strip().upper()
        if not v:
            return None
        if v not in SESSION_TYPES:
            raise ValueError(f"session_type must be one of: {', '.join(sorted(SESSION_TYPES))}")
        return v


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


class EventDetailsIn(BaseModel):
    speakers: List[SpeakerIn] = []
    sessions: List[SessionIn] = []
    fees: List[FeeIn] = []


def _blank_to_none(v: Optional[str]) -> Optional[str]:
    v = (v or "").strip()
    return v or None


async def _read(conn, event_id: int) -> Dict[str, Any]:
    speakers = await conn.fetch(
        """
        SELECT person_id, fullname, title, organisation, role::text AS role,
               email, phone, batch, linkedin_url, photo_url, bio, alumni_id
        FROM event_people
        WHERE event_id = $1::int AND role::text = ANY($2::text[])
        ORDER BY display_order, person_id
        """,
        event_id, list(SPEAKER_ROLES),
    )
    sessions = await conn.fetch(
        """
        SELECT session_id, title, speaker_name, start_datetime, end_datetime,
               session_type, pillar, track, description
        FROM sessions WHERE event_id = $1::int
        ORDER BY sort_order, start_datetime
        """,
        event_id,
    )
    people_rows = await conn.fetch(
        """
        SELECT sp.session_id, p.fullname, sp.role::text AS role
          FROM session_people sp
          JOIN sessions s ON s.session_id = sp.session_id
          JOIN event_people p ON p.person_id = sp.person_id
         WHERE s.event_id = $1::int
         ORDER BY sp.session_id, sp.display_order, sp.person_id
        """,
        event_id,
    )
    sponsor_rows = await conn.fetch(
        """
        SELECT ss.session_id, sp.name
          FROM session_sponsors ss
          JOIN sessions s ON s.session_id = ss.session_id
          JOIN event_sponsors sp ON sp.sponsor_id = ss.sponsor_id
         WHERE s.event_id = $1::int
         ORDER BY ss.session_id, ss.display_order, ss.sponsor_id
        """,
        event_id,
    )
    people_by: Dict[int, List[Dict[str, Any]]] = {}
    for r in people_rows:
        people_by.setdefault(r["session_id"], []).append(
            {"name": r["fullname"], "moderator": r["role"] == "MODERATOR"}
        )
    sponsors_by: Dict[int, List[str]] = {}
    for r in sponsor_rows:
        sponsors_by.setdefault(r["session_id"], []).append(r["name"])
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
        "sessions": [
            {
                **dict(r),
                "people": people_by.get(r["session_id"], []),
                "presented_by": sponsors_by.get(r["session_id"], []),
            }
            for r in sessions
        ],
        "fees": [{**dict(r), "amount": float(r["amount"])} for r in fees],
    }


def _key(name: str) -> str:
    return " ".join(name.split()).casefold()


async def _save_session_links(conn, event_id: int, saved: List[tuple]) -> None:
    """Replaces each session's people and presenting sponsors, for the
    sessions whose request named them."""
    if not any(s.people is not None or s.presented_by is not None for _, s in saved):
        return

    people: Dict[str, Dict[str, Any]] = {}
    for r in await conn.fetch(
        """
        SELECT person_id, fullname, role::text AS role FROM event_people
         WHERE event_id = $1::int ORDER BY display_order, person_id
        """,
        event_id,
    ):
        people.setdefault(_key(r["fullname"]), dict(r))
    sponsors: Dict[str, int] = {}
    for r in await conn.fetch(
        "SELECT sponsor_id, name FROM event_sponsors WHERE event_id = $1::int"
        " ORDER BY display_order, sponsor_id",
        event_id,
    ):
        sponsors.setdefault(_key(r["name"]), r["sponsor_id"])

    for session_id, s in saved:
        if s.people is not None:
            before = {
                r["person_id"]: r["role"]
                for r in await conn.fetch(
                    "SELECT person_id, role::text AS role FROM session_people"
                    " WHERE session_id = $1::int AND role <> 'MODERATOR'",
                    session_id,
                )
            }
            await conn.execute("DELETE FROM session_people WHERE session_id = $1::int", session_id)
            seen: set = set()
            for order, entry in enumerate(s.people):
                person = people.get(_key(entry.name))
                if person is None:
                    raise HTTPException(status_code=422, detail=f"unknown_speaker: {entry.name.strip()}")
                if person["person_id"] in seen:
                    continue
                seen.add(person["person_id"])
                if entry.moderator:
                    role = "MODERATOR"
                elif person["person_id"] in before:
                    role = before[person["person_id"]]
                elif person["role"] != "MODERATOR":
                    role = person["role"]
                else:
                    role = "SPEAKER"
                await conn.execute(
                    """
                    INSERT INTO session_people (session_id, person_id, role, display_order)
                    VALUES ($1::int, $2::int, $3::text::person_role, $4::int)
                    """,
                    session_id, person["person_id"], role, order,
                )
        if s.presented_by is not None:
            await conn.execute("DELETE FROM session_sponsors WHERE session_id = $1::int", session_id)
            seen = set()
            for order, name in enumerate(s.presented_by):
                if not name.strip():
                    continue
                sponsor_id = sponsors.get(_key(name))
                if sponsor_id is None:
                    raise HTTPException(status_code=422, detail=f"unknown_sponsor: {name.strip()}")
                if sponsor_id in seen:
                    continue
                seen.add(sponsor_id)
                await conn.execute(
                    """
                    INSERT INTO session_sponsors (session_id, sponsor_id, display_order)
                    VALUES ($1::int, $2::int, $3::int)
                    """,
                    session_id, sponsor_id, order,
                )


@router.get("/events/{event_id}/details")
async def get_event_details(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        return await _read(conn, event_id)


@router.put("/events/{event_id}/details")
async def put_event_details(
    event_id: int,
    body: EventDetailsIn,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            # A linked sheet owns speakers and sessions: only fees here.
            linked = await is_linked(conn, event_id)
            # ── Speakers ────────────────────────────────────────────────
            existing = {
                r["person_id"]
                for r in await conn.fetch(
                    "SELECT person_id FROM event_people WHERE event_id = $1::int AND role::text = ANY($2::text[])",
                    event_id, list(SPEAKER_ROLES),
                )
            }
            kept: set = set()
            for order, sp in enumerate([] if linked else body.speakers):
                extra = {
                    col: _blank_to_none(getattr(sp, col))
                    for col in _OPTIONAL_SPEAKER_COLUMNS
                    if col in sp.model_fields_set
                }
                if "email" in extra and extra["email"]:
                    extra["email"] = extra["email"].lower()
                if sp.person_id is not None and sp.person_id in existing:
                    kept.add(sp.person_id)
                    sets = "".join(f", {col} = ${7 + i}::text" for i, col in enumerate(extra))
                    await conn.execute(
                        f"""
                        UPDATE event_people
                        SET fullname = $2::text, title = $3::text, organisation = $4::text,
                            display_order = $5::int, updated_at = now(),
                            role = COALESCE($6::text::person_role, role){sets}
                        WHERE person_id = $1::int
                        """,
                        sp.person_id, sp.fullname.strip(), _blank_to_none(sp.title),
                        _blank_to_none(sp.organisation), order, sp.role, *extra.values(),
                    )
                else:
                    cols = "".join(f", {col}" for col in extra)
                    params = "".join(f", ${7 + i}::text" for i in range(len(extra)))
                    await conn.execute(
                        f"""
                        INSERT INTO event_people (event_id, role, fullname, title, organisation, display_order, is_visible{cols})
                        VALUES ($1::int, COALESCE($6::text, 'SPEAKER')::person_role,
                                $2::text, $3::text, $4::text, $5::int, true{params})
                        """,
                        event_id, sp.fullname.strip(), _blank_to_none(sp.title),
                        _blank_to_none(sp.organisation), order, sp.role, *extra.values(),
                    )
            removed = set() if linked else existing - kept
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
            saved: List[tuple] = []  # (session_id, SessionIn), for people and sponsors
            for order, s in enumerate([] if linked else body.sessions):
                if s.end_datetime < s.start_datetime:
                    raise HTTPException(status_code=422, detail="session_ends_before_it_starts")
                optional = {
                    col: _blank_to_none(getattr(s, col)) if col != "session_type" else s.session_type
                    for col in _OPTIONAL_SESSION_COLUMNS
                    if col in s.model_fields_set
                }
                if s.session_id is not None and s.session_id in existing:
                    kept.add(s.session_id)
                    sets = [f"{col} = ${7 + i}::text" for i, col in enumerate(optional)]
                    await conn.execute(
                        f"""
                        UPDATE sessions
                        SET title = $2::text, speaker_name = $3::text,
                            start_datetime = $4::timestamptz, end_datetime = $5::timestamptz,
                            sort_order = $6::int{''.join(', ' + x for x in sets)}
                        WHERE session_id = $1::int
                        """,
                        s.session_id, s.title.strip(), _blank_to_none(s.speaker_name),
                        s.start_datetime, s.end_datetime, order, *optional.values(),
                    )
                    session_id = s.session_id
                else:
                    cols = "".join(f", {col}" for col in optional)
                    params = "".join(f", ${7 + i}::text" for i in range(len(optional)))
                    session_id = await conn.fetchval(
                        f"""
                        INSERT INTO sessions (event_id, title, speaker_name, start_datetime, end_datetime, sort_order{cols})
                        VALUES ($1::int, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::int{params})
                        RETURNING session_id
                        """,
                        event_id, s.title.strip(), _blank_to_none(s.speaker_name),
                        s.start_datetime, s.end_datetime, order, *optional.values(),
                    )
                saved.append((session_id, s))
            removed = set() if linked else existing - kept
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

            # ── Who is on each session, who presents it ────────────
            await _save_session_links(conn, event_id, saved)

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
        event_type="event_details_updated",
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
