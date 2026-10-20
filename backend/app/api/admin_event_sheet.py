"""An event's Google Sheet: import, link, Refresh, unlink.

  GET    /api/v1/admin/sheets/info                -> the email to share with, the templates
  POST   /api/v1/admin/sheets/preview             -> read a sheet for Events → Import (no event yet)
  POST   /api/v1/admin/events/{id}/sheet/refresh  -> link (or re-read) the sheet and save it
  DELETE /api/v1/admin/events/{id}/sheet          -> unlink; what's there stays, editable again;
                                                     one way: an unlinked event can't be linked again

While an event has a sheet linked, the sheet is the only source of its
details: the Event tab (title, dates, place, seats, price, guests,
registration dates, description, images, logos) and its speakers, sessions,
sponsors and partners. Refresh saves them all in one transaction, through
the same update the form's Save uses; the form's own endpoints leave the
lists alone (409 sheet_linked, or the details save skipping them).

- When the Event tab would change the event, Refresh first answers with the
  changes (`needs_confirm`) and saves nothing; it saves when called again
  with `confirm`. The lists alone need no confirmation.
- The price doesn't change once the event has been published: it stays, and
  a warning says so.
- Capacity can't go below the people already registered.
- A sheet without its Event tab filled in can't be linked or refreshed.

Refresh matches what is already there, so ids (and check-ins) survive:
people and sponsors by name; sessions by start + title, then by title alone
when it's unique. A session with check-ins that left the sheet is kept, with
a warning. Any problem in the sheet changes nothing.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.config import get_settings
from app.database import get_pool
from app.middleware.admin_auth import require_event_admin, require_event_creator
from app.repositories.events_repository import EventsRepository
from app.schemas.event_update import EventUpdate
from app.services import alumni_directory, audit_service, sheet_reader
from app.services.events_service import EventsService
from app.services.sheet_parser import SheetResult, name_key, parse_sheet, parse_wall

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

# People the sheet owns: everyone on the event except organisers.
_SHEET_ROLES_EXCLUDED = ("ORGANIZER",)


class SheetLinkIn(BaseModel):
    url: Optional[str] = Field(None, max_length=2048)
    # Refresh: save even though the Event tab changes the event (the app
    # showed the changes and the admin agreed).
    confirm: bool = False


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
        event = await EventsRepository(conn).get_event(event_id)
    if not event:
        raise HTTPException(status_code=404, detail="event_not_found")
    if event["agenda_sheet_url"] is None and event["agenda_sheet_read_at"] is not None:
        raise HTTPException(status_code=409, detail={
            "code": "sheet_unlinked",
            "message": "This event was unlinked from its sheet, so it can't be linked again. Edit it here.",
        })
    link_in = body.url or event["agenda_sheet_url"]
    if not link_in:
        raise HTTPException(status_code=422, detail={"code": "sheet_link_invalid", "message": "Paste the sheet's link first."})

    link, tabs = await _read(link_in)
    # The sheet is the source of everything: its Event tab sets the event
    # (and its dates, which the sessions follow). A sheet without one stops.
    result = parse_sheet(tabs, need_event=True)
    if result.errors:
        raise _bad_sheet(result)

    update, changes = _event_changes(event, result)
    if update.get("capacity") is not None and update["capacity"] < (event["registered_count"] or 0):
        result.error(
            f"Event: capacity {update['capacity']} is less than the "
            f"{event['registered_count']} people already registered."
        )
        raise _bad_sheet(result)
    if changes and not body.confirm:
        return {
            "url": link,
            "needs_confirm": True,
            "changes": changes,
            "summary": _summary(result),
            "warnings": result.warnings,
        }
    result.warnings.extend(await alumni_directory.fill_speakers(result.speakers))

    tz = ZoneInfo(result.event["timezone"])
    first_link = event["agenda_sheet_url"] is None
    async with pool.acquire() as conn:
        async with conn.transaction():
            if update:
                await EventsService(conn).update_event(event_id, EventUpdate(**update), user)
                if "ticket_price" in update or "is_free" in update:
                    await _fees_from_price(conn, event_id, update)
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
        context={
            "event_id": event_id, "sheet": link, **_summary(result),
            "event_fields": [c["field"] for c in changes], "warnings": len(result.warnings),
        },
    )
    return {
        "url": link,
        "read_at": read_at,
        "summary": _summary(result),
        "changes": changes,
        "warnings": result.warnings,
        "gap_minutes": result.gap_minutes,
    }


# ── The Event tab against the event ─────────────────────────────────────────

# (field, label) in the order the app lists changes.
_EVENT_FIELDS = (
    ("title", "Title"),
    ("description", "Description"),
    ("start_datetime", "Starts"),
    ("end_datetime", "Ends"),
    ("timezone", "Timezone"),
    ("is_full_day", "Full day"),
    ("is_virtual", "Where"),
    ("location_text", "Venue"),
    ("location_maps_url", "Map link"),
    ("virtual_url", "Meeting link"),
    ("capacity", "Capacity"),
    ("max_guests", "Guests per registration"),
    ("is_free", "Free or paid"),
    ("ticket_price", "Price"),
    ("registration_opens_at", "Registration opens"),
    ("registration_closes_at", "Registration closes"),
    ("thumbnail_url", "Thumbnail"),
    ("banner_url", "Banner"),
    ("brand_logo_url", "Logo"),
    ("brand_logo_dark_url", "Logo for dark backgrounds"),
)
_PRICE_FIELDS = ("is_free", "ticket_price")


def _sheet_values(result: SheetResult) -> Dict[str, Any]:
    """The Event tab as the event's columns (instants in its timezone)."""
    e = result.event or {}
    tz = ZoneInfo(e["timezone"])

    def at(w: Optional[str]) -> Optional[datetime]:
        return parse_wall(w).replace(tzinfo=tz) if w else None

    start = at(e["start"])
    return {
        "title": e["title"],
        "description": e["description"],
        "start_datetime": start,
        "end_datetime": at(e["end"]),
        "timezone": e["timezone"],
        "is_full_day": e["is_full_day"],
        "is_virtual": e["is_virtual"],
        "location_text": e["location_text"],
        "location_maps_url": e["location_maps_url"],
        "virtual_url": e["virtual_url"],
        "capacity": e["capacity"],
        "max_guests": e["max_guests"],
        "is_free": e["is_free"],
        "ticket_price": None if e["is_free"] else Decimal(str(e["ticket_price"])),
        "registration_opens_at": at(e["registration_opens_at"]),
        # Blank: closes when the event starts, as the form saves it.
        "registration_closes_at": at(e["registration_closes_at"]) or start,
        "thumbnail_url": e["thumbnail_url"],
        "banner_url": e["banner_url"],
        "brand_logo_url": e["brand_logo_url"],
        "brand_logo_dark_url": e["brand_logo_dark_url"],
    }


def _same(field: str, old: Any, new: Any) -> bool:
    if isinstance(old, str) or isinstance(new, str) or old is None or new is None:
        old = (old or "").strip() if isinstance(old, str) or old is None else old
        new = (new or "").strip() if isinstance(new, str) or new is None else new
    if field == "ticket_price":
        return (Decimal(str(old)) if old not in (None, "") else None) == (Decimal(str(new)) if new not in (None, "") else None)
    return old == new


def _shown(field: str, value: Any, tz: ZoneInfo) -> str:
    if value is None or value == "":
        return "—"
    if isinstance(value, datetime):
        return value.astimezone(tz).strftime("%d %b %Y, %I:%M %p").lstrip("0").replace(" 0", " ").replace("AM", "am").replace("PM", "pm")
    if field == "is_virtual":
        return "Online" if value else "In person"
    if field == "is_free":
        return "Free" if value else "Paid"
    if field == "is_full_day":
        return "Yes" if value else "No"
    if field == "ticket_price":
        amount = Decimal(str(value))
        return f"₹{amount:,.0f}" if amount == amount.to_integral() else f"₹{amount:,.2f}"
    text = str(value).strip()
    return text if len(text) <= 60 else text[:57].rstrip() + "…"


def _event_changes(event, result: SheetResult) -> tuple[Dict[str, Any], List[Dict[str, str]]]:
    """What the Event tab would change: (the update to save, the changes to show)."""
    new = _sheet_values(result)
    tz = ZoneInfo(new["timezone"])
    published = event["published_at"] is not None
    update: Dict[str, Any] = {}
    changes: List[Dict[str, str]] = []
    for field, label in _EVENT_FIELDS:
        old = event[field]
        if _same(field, old, new[field]):
            continue
        if published and field in _PRICE_FIELDS:
            continue
        update[field] = new[field]
        changes.append({"field": label, "from": _shown(field, old, tz), "to": _shown(field, new[field], tz)})
    if published and any(not _same(f, event[f], new[f]) for f in _PRICE_FIELDS):
        kept = "free" if event["is_free"] else _shown("ticket_price", event["ticket_price"], tz)
        result.warnings.append(f"The price stays {kept}: it can't change once the event is published.")
    if "start_datetime" in update or "end_datetime" in update:
        # The form always sends both; so does Refresh (one check: end after start).
        update["start_datetime"], update["end_datetime"] = new["start_datetime"], new["end_datetime"]
    return update, changes


async def _fees_from_price(conn, event_id: int, update: Dict[str, Any]) -> None:
    """The sheet has one price: the fee lines become one line of it (none if free)."""
    await conn.execute("DELETE FROM event_fees WHERE event_id = $1::int", event_id)
    price = update.get("ticket_price")
    if not update.get("is_free", False) and price:
        await conn.execute(
            "INSERT INTO event_fees (event_id, name, fee_type, amount, display_order)"
            " VALUES ($1::int, 'Registration', 'participation', $2::numeric, 0)",
            event_id, price,
        )


@router.delete("/events/{event_id}/sheet")
async def unlink_sheet(
    event_id: int,
    user: Dict[str, Any] = Depends(require_event_admin),
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        link = await conn.fetchval(
            # The read time stays: it marks the event as once linked, so it
            # can't be linked again (Unlink is one way, Import to DIY).
            "UPDATE events e SET agenda_sheet_url = NULL, updated_at = now()"
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
