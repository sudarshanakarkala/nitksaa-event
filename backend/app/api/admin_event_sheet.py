"""An event's Google Sheet (B7): import, link, Refresh, unlink.

  GET    /api/v1/admin/sheets/info                -> the email to share with, the templates
  POST   /api/v1/admin/sheets/preview             -> read a sheet for Events → Import (no event yet)
  POST   /api/v1/admin/events/{id}/sheet/refresh  -> link (or re-read) the sheet and save it
  DELETE /api/v1/admin/events/{id}/sheet          -> unlink; what's there stays, editable again

While an event has a sheet linked, the sheet is the only source of its
speakers, sessions, sponsors and partners: Refresh replaces them all in one
transaction, and the form's own endpoints leave them alone (409
sheet_linked, or the details save skipping them). The essentials (title,
dates, place, seats, price) stay in the app.

Refresh matches what is already there, so ids (and check-ins) survive:
people and sponsors by name; sessions by start + title, then by title alone
when it's unique. A session with check-ins that left the sheet is kept, with
a warning. Any problem in the sheet changes nothing.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.config import get_settings
from app.database import get_pool
from app.middleware.admin_auth import require_event_admin, require_event_creator
from app.services import alumni_directory, audit_service, sheet_reader
from app.services.sheet_parser import SheetResult, name_key, parse_sheet, parse_wall

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

# People the sheet owns: everyone on the event except organisers.
_SHEET_ROLES_EXCLUDED = ("ORGANIZER",)


class SheetLinkIn(BaseModel):
    url: Optional[str] = Field(None, max_length=2048)


async def is_linked(conn, event_id: int) -> bool:
    return bool(await conn.fetchval(
        "SELECT agenda_sheet_url IS NOT NULL FROM events WHERE event_id = $1::int", event_id
    ))


async def refuse_if_linked(conn, event_id: int) -> None:
    """For the form's per-item endpoints: the sheet owns these while linked."""
    if await is_linked(conn, event_id):
        raise HTTPException(status_code=409, detail="sheet_linked")


def _bad_sheet(result: SheetResult) -> HTTPException:
    return HTTPException(status_code=422, detail={
        "code": "sheet_errors", "errors": result.errors, "warnings": result.warnings,
    })


def _unreachable(err: sheet_reader.SheetAccessError) -> HTTPException:
    return HTTPException(status_code=422, detail={"code": err.code, "message": err.message})


async def _read(link: Optional[str]) -> tuple[str, Dict[str, List[List[Any]]]]:
    sheet_id = sheet_reader.spreadsheet_id(link or "")
    if not sheet_id:
        raise HTTPException(status_code=422, detail={
            "code": "sheet_link_invalid",
            "message": "That isn't a Google Sheet link. Copy it from the sheet's address bar.",
        })
    try:
        tabs = await sheet_reader.read_tabs(sheet_id)
    except sheet_reader.SheetAccessError as err:
        raise _unreachable(err) from err
    return sheet_reader.canonical_link(sheet_id), tabs


def _summary(result: SheetResult) -> Dict[str, int]:
    return {
        "sessions": len(result.sessions),
        "speakers": len(result.speakers),
        "sponsors": len(result.sponsors),
        "partners": len(result.partners),
    }


def _strip_rows(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [{k: v for k, v in item.items() if k != "row"} for item in items]


# ── Endpoints ───────────────────────────────────────────────────────────────

@router.get("/sheets/info")
async def sheet_info(user: Dict[str, Any] = Depends(require_event_creator)) -> Dict[str, Any]:
    s = get_settings()
    return {
        "share_with": s.sheets_reader_email,
        "templates": [
            {"name": "Blank", "url": s.sheet_template_blank_url},
            {"name": "Breakfast example", "url": s.sheet_template_breakfast_url},
            {"name": "NITKonnect example", "url": s.sheet_template_nitkonnect_url},
        ],
    }


@router.post("/sheets/preview")
async def preview_sheet(
    body: SheetLinkIn,
    user: Dict[str, Any] = Depends(require_event_creator),
) -> Dict[str, Any]:
    """Events → Import: the Event tab as the create form's fields, plus what
    the other tabs hold. Saves nothing."""
    link, tabs = await _read(body.url)
    result = parse_sheet(tabs, need_event=True)
    if result.errors:
        raise _bad_sheet(result)
    return {"url": link, "event": result.event, "summary": _summary(result), "warnings": result.warnings}


@router.post("/events/{event_id}/sheet/refresh")
async def refresh_sheet(
    event_id: int,
    body: SheetLinkIn,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        event = await conn.fetchrow(
            "SELECT event_id, timezone, start_datetime, end_datetime, agenda_sheet_url"
            " FROM events WHERE event_id = $1::int",
            event_id,
        )
    if not event:
        raise HTTPException(status_code=404, detail="event_not_found")
    link_in = body.url or event["agenda_sheet_url"]
    if not link_in:
        raise HTTPException(status_code=422, detail={"code": "sheet_link_invalid", "message": "Paste the sheet's link first."})

    link, tabs = await _read(link_in)
    tz = ZoneInfo(event["timezone"])
    fmt = "%Y-%m-%d %H:%M"
    result = parse_sheet(
        tabs,
        timezone=event["timezone"],
        event_start=event["start_datetime"].astimezone(tz).strftime(fmt),
        event_end=event["end_datetime"].astimezone(tz).strftime(fmt),
    )
    if result.errors:
        raise _bad_sheet(result)
    result.warnings.extend(await alumni_directory.fill_speakers(result.speakers))

    first_link = event["agenda_sheet_url"] is None
    async with pool.acquire() as conn:
        async with conn.transaction():
            kept = await _apply(conn, event_id, result, tz)
            read_at = await conn.fetchval(
                "UPDATE events SET agenda_sheet_url = $2::text, agenda_sheet_read_at = now(), updated_at = now()"
                " WHERE event_id = $1::int RETURNING agenda_sheet_read_at",
                event_id, link,
            )
    for title in kept:
        result.warnings.append(f"'{title}' isn't in the sheet any more but people checked in to it, so it was kept.")

    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="event_sheet_linked" if first_link else "event_sheet_refreshed",
        entity_type="event",
        entity_id=event_id,
        context={"event_id": event_id, "sheet": link, **_summary(result), "warnings": len(result.warnings)},
    )
    return {
        "url": link,
        "read_at": read_at,
        "summary": _summary(result),
        "warnings": result.warnings,
        "gap_minutes": result.gap_minutes,
    }


@router.delete("/events/{event_id}/sheet")
async def unlink_sheet(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        link = await conn.fetchval(
            "UPDATE events e SET agenda_sheet_url = NULL, agenda_sheet_read_at = NULL, updated_at = now()"
            " FROM (SELECT agenda_sheet_url FROM events WHERE event_id = $1::int) old"
            " WHERE e.event_id = $1::int RETURNING old.agenda_sheet_url",
            event_id,
        )
        if link is None and not await conn.fetchval("SELECT 1 FROM events WHERE event_id = $1::int", event_id):
            raise HTTPException(status_code=404, detail="event_not_found")
    if link:
        await audit_service.emit(
            actor_uid=user["firebase_uid"], event_type="event_sheet_unlinked",
            entity_type="event", entity_id=event_id, context={"event_id": event_id, "sheet": link},
        )
    return {"url": None}


# ── Saving a Refresh ────────────────────────────────────────────────────────

def _instant(wall_text: str, tz: ZoneInfo) -> datetime:
    return parse_wall(wall_text).replace(tzinfo=tz)


async def _apply(conn, event_id: int, result: SheetResult, tz: ZoneInfo) -> List[str]:
    """Writes the sheet's lists over the event's. Returns titles of sessions
    kept because of check-ins."""
    sponsor_ids = await _apply_orgs(
        conn, event_id, "event_sponsors", "sponsor_id", "sponsor_type", result.sponsors, has_label=True,
    )
    await _apply_orgs(conn, event_id, "event_partners", "partner_id", "partner_type", result.partners, has_label=False)
    person_ids = await _apply_people(conn, event_id, result.speakers)
    return await _apply_sessions(conn, event_id, result.sessions, person_ids, sponsor_ids, tz)


async def _apply_orgs(conn, event_id, table, id_col, type_col, items, *, has_label) -> Dict[str, int]:
    existing: Dict[str, int] = {}
    for r in await conn.fetch(
        f"SELECT {id_col} AS id, name FROM {table} WHERE event_id = $1::int ORDER BY display_order, {id_col}",
        event_id,
    ):
        existing.setdefault(name_key(r["name"]), r["id"])
    ids: Dict[str, int] = {}
    label_set = ", label = $7::text" if has_label else ""
    label_col = ", label" if has_label else ""
    label_val = ", $7::text" if has_label else ""
    for order, item in enumerate(items):
        key = name_key(item["name"])
        args = [item["name"], item[type_col], item["logo_url"], item["website_url"], order]
        if has_label:
            args.append(item["label"])
        if key in existing and existing[key] not in ids.values():
            ident = existing[key]
            await conn.execute(
                f"UPDATE {table} SET name = $2::text, {type_col} = $3::text, logo_url = $4::text,"
                f" website_url = $5::text, display_order = $6::int, is_visible = true,"
                f" updated_at = now(){label_set} WHERE {id_col} = $1::int",
                ident, *args,
            )
        else:
            ident = await conn.fetchval(
                f"INSERT INTO {table} (event_id, name, {type_col}, logo_url, website_url, display_order,"
                f" is_visible{label_col}) VALUES ($1::int, $2::text, $3::text, $4::text, $5::text, $6::int,"
                f" true{label_val}) RETURNING {id_col}",
                event_id, *args,
            )
        ids[key] = ident
    gone = [i for i in existing.values() if i not in ids.values()]
    if gone:
        await conn.execute(f"DELETE FROM {table} WHERE {id_col} = ANY($1::int[])", gone)
    return ids


async def _apply_people(conn, event_id: int, speakers: List[Dict[str, Any]]) -> Dict[str, int]:
    existing: Dict[str, int] = {}
    for r in await conn.fetch(
        "SELECT person_id, fullname FROM event_people WHERE event_id = $1::int"
        " AND role::text <> ALL($2::text[]) ORDER BY display_order, person_id",
        event_id, list(_SHEET_ROLES_EXCLUDED),
    ):
        existing.setdefault(name_key(r["fullname"]), r["person_id"])
    ids: Dict[str, int] = {}
    for order, sp in enumerate(speakers):
        key = name_key(sp["fullname"])
        args = [
            sp["fullname"], sp["role"], sp["title"], sp["organisation"], sp["bio"], sp["photo_url"],
            sp["linkedin_url"], sp["email"], sp["phone"], sp["batch"], sp["alumni_id"], order,
        ]
        if key in existing:
            ident = existing[key]
            await conn.execute(
                """
                UPDATE event_people
                   SET fullname = $2::text, role = $3::text::person_role, title = $4::text,
                       organisation = $5::text, bio = $6::text, photo_url = $7::text,
                       linkedin_url = $8::text, email = $9::text, phone = $10::text,
                       batch = $11::text, alumni_id = $12::text, display_order = $13::int,
                       is_visible = true, updated_at = now()
                 WHERE person_id = $1::int
                """,
                ident, *args,
            )
        else:
            ident = await conn.fetchval(
                """
                INSERT INTO event_people (event_id, fullname, role, title, organisation, bio, photo_url,
                                          linkedin_url, email, phone, batch, alumni_id, display_order, is_visible)
                VALUES ($1::int, $2::text, $3::text::person_role, $4::text, $5::text, $6::text, $7::text,
                        $8::text, $9::text, $10::text, $11::text, $12::text, $13::int, true)
                RETURNING person_id
                """,
                event_id, *args,
            )
        ids[key] = ident
    gone = [i for i in existing.values() if i not in ids.values()]
    if gone:
        await conn.execute("DELETE FROM event_people WHERE person_id = ANY($1::int[])", gone)
    return ids


async def _apply_sessions(conn, event_id, sessions, person_ids, sponsor_ids, tz) -> List[str]:
    rows = await conn.fetch(
        "SELECT session_id, title, start_datetime FROM sessions WHERE event_id = $1::int"
        " ORDER BY sort_order, start_datetime, session_id",
        event_id,
    )
    by_start_title = {}
    by_title: Dict[str, List[int]] = {}
    for r in rows:
        by_start_title.setdefault((r["start_datetime"], name_key(r["title"])), r["session_id"])
        by_title.setdefault(name_key(r["title"]), []).append(r["session_id"])
    sheet_titles: Dict[str, int] = {}
    for s in sessions:
        sheet_titles[name_key(s["title"])] = sheet_titles.get(name_key(s["title"]), 0) + 1

    used: set = set()
    for order, s in enumerate(sessions):
        start, end = _instant(s["start"], tz), _instant(s["end"], tz)
        key = name_key(s["title"])
        ident = by_start_title.get((start, key))
        if ident in used:
            ident = None
        if ident is None and sheet_titles[key] == 1 and len(by_title.get(key, [])) == 1:
            candidate = by_title[key][0]
            ident = None if candidate in used else candidate
        args = [s["title"], start, end, order, s["session_type"], s["pillar"], s["track"], s["description"]]
        if ident is not None:
            await conn.execute(
                """
                UPDATE sessions
                   SET title = $2::text, speaker_name = NULL, start_datetime = $3::timestamptz,
                       end_datetime = $4::timestamptz, sort_order = $5::int, session_type = $6::text,
                       pillar = $7::text, track = $8::text, description = $9::text
                 WHERE session_id = $1::int
                """,
                ident, *args,
            )
        else:
            ident = await conn.fetchval(
                """
                INSERT INTO sessions (event_id, title, speaker_name, start_datetime, end_datetime, sort_order,
                                      session_type, pillar, track, description)
                VALUES ($1::int, $2::text, NULL, $3::timestamptz, $4::timestamptz, $5::int,
                        $6::text, $7::text, $8::text, $9::text)
                RETURNING session_id
                """,
                event_id, *args,
            )
        used.add(ident)
        await conn.execute("DELETE FROM session_people WHERE session_id = $1::int", ident)
        for i, p in enumerate(s["people"]):
            await conn.execute(
                """
                INSERT INTO session_people (session_id, person_id, role, display_order)
                SELECT $1::int, $2::int,
                       CASE WHEN $3::bool THEN 'MODERATOR'::person_role
                            WHEN role = 'MODERATOR' THEN 'SPEAKER'::person_role ELSE role END,
                       $4::int
                  FROM event_people WHERE person_id = $2::int
                """,
                ident, person_ids[name_key(p["name"])], p["moderator"], i,
            )
        await conn.execute("DELETE FROM session_sponsors WHERE session_id = $1::int", ident)
        for i, name in enumerate(s["presented_by"]):
            await conn.execute(
                "INSERT INTO session_sponsors (session_id, sponsor_id, display_order) VALUES ($1::int, $2::int, $3::int)",
                ident, sponsor_ids[name_key(name)], i,
            )

    gone = [r["session_id"] for r in rows if r["session_id"] not in used]
    kept: List[str] = []
    if gone:
        checked = {
            r["session_id"]
            for r in await conn.fetch(
                "SELECT DISTINCT session_id FROM check_ins WHERE session_id = ANY($1::int[])", gone
            )
        }
        kept = [r["title"] for r in rows if r["session_id"] in checked]
        delete = [i for i in gone if i not in checked]
        if delete:
            await conn.execute("DELETE FROM sessions WHERE session_id = ANY($1::int[])", delete)
    return kept
