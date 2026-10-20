"""Reads an event sheet's tabs into the event's details (B7).

Pure: takes the cell values the Sheets API returned and gives back what the
event will hold, or the problems, each naming the tab and row. No network,
no database; app/api/admin_event_sheet.py does those.

Tabs (found by name, ignoring case): Event (Field / Value rows), Sessions,
Speakers, Sponsors (a header row, then one row each). Columns are found by
their header words, ignoring case, spaces, punctuation and a trailing "*",
so reordered or extra columns are fine. A missing or empty tab means none.

Cells come as the API's UNFORMATTED_VALUE with SERIAL_NUMBER dates: a real
date or time cell is a number (days since 30 Dec 1899; the fraction is the
time of day), anything typed as text is a string. Both are accepted.

Wall times ("yyyy-MM-dd HH:mm") are in the event's timezone, the format the
event form uses; the caller turns them into instants.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MAX_ROWS = 500
MAX_ERRORS = 50
DEFAULT_TIMEZONE = "Asia/Kolkata"

SESSION_TYPES = {
    t.casefold(): t.upper()
    for t in ("Keynote", "Talk", "Panel", "Fireside", "Workshop", "Showcase", "Networking", "Awards", "Break")
}
ROLES = {
    "speaker": "SPEAKER",
    "panelist": "PANELIST",
    "panellist": "PANELIST",
    "moderator": "MODERATOR",
    "chief guest": "CHIEF_GUEST",
    "guest of honour": "GUEST_OF_HONOUR",
    "guest of honor": "GUEST_OF_HONOUR",
    "host": "HOST",
}
SPONSOR_TIERS = {
    "title sponsor": "TITLE_SPONSOR",
    "gold sponsor": "GOLD_SPONSOR",
    "silver sponsor": "SILVER_SPONSOR",
    "bronze sponsor": "BRONZE_SPONSOR",
    "associate sponsor": "ASSOCIATE_SPONSOR",
}
PARTNER_TIERS = {
    "community partner": "COMMUNITY_PARTNER",
    "knowledge partner": "KNOWLEDGE_PARTNER",
    "media partner": "MEDIA_PARTNER",
    "venue partner": "VENUE_PARTNER",
    "technology partner": "TECHNOLOGY_PARTNER",
    "ecosystem partner": "ECOSYSTEM_PARTNER",
    "hiring partner": "HIRING_PARTNER",
}

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_TIME = re.compile(r"^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?$", re.I)
_DATE_FORMATS = ("%d %b %Y", "%d %B %Y", "%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y", "%d %b, %Y", "%b %d, %Y", "%B %d, %Y")
_SERIAL_EPOCH = date(1899, 12, 30)


def _day_text(d: date) -> str:
    """"21 Feb 2026"."""
    return d.strftime("%d %b %Y").lstrip("0")


def name_key(name: str) -> str:
    """Names match ignoring case and extra spaces."""
    return " ".join(name.split()).casefold()


def _header_key(h: Any) -> str:
    return re.sub(r"[^a-z0-9]", "", str(h or "").replace("*", "").casefold())


def wall(d: date, minutes: int) -> str:
    """"yyyy-MM-dd HH:mm" for a date and minutes after midnight (may pass midnight)."""
    t = datetime(d.year, d.month, d.day) + timedelta(minutes=minutes)
    return t.strftime("%Y-%m-%d %H:%M")


def parse_wall(text: str) -> datetime:
    return datetime.strptime(text, "%Y-%m-%d %H:%M")


@dataclass
class SheetResult:
    event: Optional[Dict[str, Any]] = None
    gap_minutes: int = 0
    speakers: List[Dict[str, Any]] = field(default_factory=list)
    sessions: List[Dict[str, Any]] = field(default_factory=list)
    sponsors: List[Dict[str, Any]] = field(default_factory=list)
    partners: List[Dict[str, Any]] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)

    def error(self, text: str) -> None:
        if len(self.errors) < MAX_ERRORS:
            self.errors.append(text)
        elif len(self.errors) == MAX_ERRORS:
            self.errors.append("…and more. Fix these first, then Refresh again.")

    def as_dict(self) -> Dict[str, Any]:
        return {
            "event": self.event,
            "gap_minutes": self.gap_minutes,
            "speakers": self.speakers,
            "sessions": self.sessions,
            "sponsors": self.sponsors,
            "partners": self.partners,
            "errors": self.errors,
            "warnings": self.warnings,
        }


# ── Cell values ─────────────────────────────────────────────────────────────

def _text(v: Any) -> str:
    if v is None or isinstance(v, bool):
        return "" if v is None else ("Yes" if v else "No")
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return " ".join(str(v).split()) if "\n" not in str(v) else str(v).strip()


def _number(v: Any) -> Optional[float]:
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = _text(v).replace(",", "").replace("₹", "").strip()
    try:
        return float(s)
    except ValueError:
        return None


def _date(v: Any) -> Tuple[Optional[date], bool]:
    """(date, ok). Blank is (None, True)."""
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return _SERIAL_EPOCH + timedelta(days=int(v)), True
    s = _text(v)
    if not s:
        return None, True
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(s, fmt).date(), True
        except ValueError:
            pass
    return None, False


def _time(v: Any) -> Tuple[Optional[int], bool]:
    """(minutes after midnight, ok). Blank is (None, True)."""
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        minutes = int(round((float(v) % 1) * 1440))
        return (0 if minutes == 1440 else minutes), True
    s = _text(v).lower().replace(" ", "")
    if not s:
        return None, True
    m = _TIME.match(s)
    if not m:
        return None, False
    hour, minute = int(m.group(1)), int(m.group(2) or 0)
    half = (m.group(3) or "").replace(".", "")
    if minute > 59:
        return None, False
    if half:
        if not 1 <= hour <= 12:
            return None, False
        hour = hour % 12 + (12 if half == "pm" else 0)
    elif hour > 23:
        return None, False
    return hour * 60 + minute, True


def _datetime(v: Any) -> Tuple[Optional[str], bool]:
    """(wall time, ok) for a cell holding a date and a time."""
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        d, _ = _date(v)
        minutes, _ = _time(v)
        return wall(d, minutes or 0), True
    s = _text(v)
    if not s:
        return None, True
    m = re.match(r"^(.*?)[\s,]+(\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.)?)$", s, re.I)
    if m:
        d, ok_d = _date(m.group(1))
        minutes, ok_t = _time(m.group(2))
        if d and ok_d and ok_t and minutes is not None:
            return wall(d, minutes), True
    d, ok = _date(s)
    if d and ok:
        return wall(d, 0), True
    return None, False


def _link(v: Any) -> Tuple[Optional[str], bool]:
    s = _text(v)
    if not s:
        return None, True
    if s.lower().startswith(("www.", "linkedin.com", "in.linkedin.com")):
        s = "https://" + s
    if not s.lower().startswith("https://") or " " in s:
        return None, False
    return s, True


def _names(v: Any) -> List[str]:
    return [n.strip() for n in re.split(r"[,;\n]", _text(v)) if n.strip()]


# ── Tabs ────────────────────────────────────────────────────────────────────

def _find_tab(tabs: Dict[str, List[List[Any]]], name: str) -> List[List[Any]]:
    for title, rows in tabs.items():
        if title.strip().casefold() == name.casefold():
            return rows or []
    return []


def _table(result: SheetResult, tabs, tab: str, columns: Dict[str, str], required: Tuple[str, ...]):
    """Rows of a list tab as {field: value} plus their sheet row number.
    `columns` maps a header key to a field name."""
    rows = _find_tab(tabs, tab)
    if not rows:
        return []
    header = [_header_key(h) for h in rows[0]]
    index = {}
    for i, h in enumerate(header):
        if h in columns and columns[h] not in index:
            index[columns[h]] = i
    body = [(n + 2, r) for n, r in enumerate(rows[1:]) if any(_text(c) for c in r)]
    if not body:
        return []
    missing = [f for f in required if f not in index]
    if missing:
        for f in missing:
            result.error(f"{tab} tab: no '{_LABELS.get(f, f)}' column. Keep the header row as in the template.")
        return []
    if len(body) > MAX_ROWS:
        result.error(f"{tab} tab: more than {MAX_ROWS} rows.")
        return []
    out = []
    for row_no, r in body:
        out.append((row_no, {f: (r[i] if i < len(r) else None) for f, i in index.items()}))
    return out


# Required columns, as their headers read in the template.
_LABELS = {"start": "Start", "title": "Title", "name": "Name", "tier": "Tier"}


SESSION_COLUMNS = {
    "date": "date", "start": "start", "starttime": "start", "end": "end", "endtime": "end",
    "title": "title", "session": "title", "speakers": "speakers", "speaker": "speakers",
    "moderator": "moderator", "moderators": "moderator", "type": "type", "sessiontype": "type",
    "hall": "hall", "track": "hall", "room": "hall", "pillar": "pillar", "subtitle": "subtitle",
    "presentedby": "presented_by",
}
SPEAKER_COLUMNS = {
    "name": "name", "fullname": "name", "role": "role", "title": "title", "designation": "title",
    "company": "company", "organisation": "company", "organization": "company", "email": "email",
    "phone": "phone", "linkedin": "linkedin", "photolink": "photo", "photo": "photo", "batch": "batch",
    "nitkbatch": "batch", "bio": "bio",
}
SPONSOR_COLUMNS = {
    "name": "name", "tier": "tier", "label": "label", "logolink": "logo", "logo": "logo",
    "website": "website",
}
EVENT_FIELDS = {
    "title": "title", "date": "date", "startdate": "date", "starttime": "start_time",
    "endtime": "end_time", "enddate": "end_date", "timezone": "timezone", "venue": "venue",
    "maplink": "map_link", "meetinglink": "meeting_link", "capacity": "capacity",
    "ticketprice": "price", "price": "price", "guestsperregistration": "guests",
    "registrationopens": "opens", "registrationcloses": "closes", "description": "description",
    "thumbnaillink": "thumbnail", "bannerlink": "banner", "logolink": "logo",
    "logolinkdarkbackgrounds": "logo_dark", "gapbetweensessionsminutes": "gap",
    "gapbetweensessions": "gap",
}


def _event_values(tabs) -> Dict[str, Tuple[int, Any]]:
    out: Dict[str, Tuple[int, Any]] = {}
    for n, r in enumerate(_find_tab(tabs, "Event")):
        if not r:
            continue
        f = EVENT_FIELDS.get(_header_key(r[0]))
        if f and f not in out:
            out[f] = (n + 1, r[1] if len(r) > 1 else None)
    return out


# ── The parse ───────────────────────────────────────────────────────────────

def parse_sheet(
    tabs: Dict[str, List[List[Any]]],
    *,
    timezone: Optional[str] = None,
    event_start: Optional[str] = None,
    event_end: Optional[str] = None,
    need_event: bool = False,
) -> SheetResult:
    """`timezone`, `event_start`, `event_end` (wall times) describe an
    existing event; on import they come from the Event tab instead
    (`need_event`)."""
    result = SheetResult()
    ev = _event_values(tabs)
    _parse_gap(result, ev)
    if need_event:
        _parse_event(result, ev)
        if not result.event:
            return result  # the Event tab first: the sessions' dates depend on it
        timezone = result.event["timezone"]
        event_start, event_end = result.event["start"], result.event["end"]
    timezone = timezone or DEFAULT_TIMEZONE

    speakers = _parse_speakers(result, tabs)
    sponsors, partners = _parse_sponsors(result, tabs)
    first_day = parse_wall(event_start).date() if event_start else None
    last_moment = parse_wall(event_end) if event_end else None
    _parse_sessions(result, tabs, speakers, sponsors, partners, first_day, last_moment)
    result.speakers = list(speakers.values())
    result.sponsors = list(sponsors.values())
    result.partners = list(partners.values())
    return result


def _parse_gap(result: SheetResult, ev) -> None:
    if "gap" not in ev:
        return
    row, v = ev["gap"]
    if not _text(v):
        return
    n = _number(v)
    if n is None or n < 0 or n > 60 or not float(n).is_integer():
        result.error(f"Event, row {row}: the gap between sessions must be 0 to 60 minutes.")
        return
    result.gap_minutes = int(n)


def _parse_event(result: SheetResult, ev) -> None:
    def val(f):
        return ev.get(f, (0, None))

    def where(f):
        return f"Event, row {ev[f][0]}" if f in ev else "Event"

    if not any(_text(v) for _, v in ev.values()):
        result.error("Event tab: empty. Fill in at least the title, date and capacity.")
        return
    e: Dict[str, Any] = {}
    ok = True

    title = _text(val("title")[1])
    if not title:
        result.error(f"{where('title')}: no title.")
        ok = False
    e["title"] = title

    tz = _text(val("timezone")[1]) or DEFAULT_TIMEZONE
    try:
        ZoneInfo(tz)
    except (ZoneInfoNotFoundError, ValueError):
        result.error(f"{where('timezone')}: '{tz}' isn't a timezone (e.g. Asia/Kolkata).")
        ok, tz = False, DEFAULT_TIMEZONE
    e["timezone"] = tz

    day, good = _date(val("date")[1])
    if not good:
        result.error(f"{where('date')}: '{_text(val('date')[1])}' isn't a date (e.g. 15 Nov 2026).")
        ok = False
    elif day is None:
        result.error(f"{where('date')}: no date.")
        ok = False
    end_day, good = _date(val("end_date")[1])
    if not good:
        result.error(f"{where('end_date')}: '{_text(val('end_date')[1])}' isn't a date.")
        ok = False
    start_t, good_s = _time(val("start_time")[1])
    end_t, good_e = _time(val("end_time")[1])
    if not good_s:
        result.error(f"{where('start_time')}: '{_text(val('start_time')[1])}' isn't a time (e.g. 7:30 am).")
        ok = False
    if not good_e:
        result.error(f"{where('end_time')}: '{_text(val('end_time')[1])}' isn't a time (e.g. 9:30 am).")
        ok = False
    if day and good_s and good_e:
        end_day = end_day or day
        if start_t is None and end_t is None:
            e["is_full_day"] = True
            e["start"] = wall(day, 0)
            e["end"] = wall(end_day + timedelta(days=1), 0)
        elif start_t is None or end_t is None:
            result.error(f"{where('start_time' if start_t is None else 'end_time')}: give both a start and an end time, or neither for a full-day event.")
            ok = False
        else:
            e["is_full_day"] = False
            e["start"], e["end"] = wall(day, start_t), wall(end_day, end_t)
            if e["end"] <= e["start"]:
                result.error(f"{where('end_time')}: the event ends before it starts.")
                ok = False

    venue = _text(val("venue")[1])
    meeting, good = _link(val("meeting_link")[1])
    if not good:
        result.error(f"{where('meeting_link')}: the meeting link must start https://")
        ok = False
    maps, good = _link(val("map_link")[1])
    if not good:
        result.error(f"{where('map_link')}: the map link must start https://")
        ok = False
    if venue:
        e.update(is_virtual=False, location_text=venue, location_maps_url=maps, virtual_url=None)
        if meeting:
            result.warnings.append("Event: both a venue and a meeting link; the event is set up in person, so the meeting link isn't used.")
    elif meeting:
        e.update(is_virtual=True, location_text=None, location_maps_url=None, virtual_url=meeting)
    else:
        result.error("Event: give a Venue, or a Meeting link for an online event.")
        ok = False

    cap = _number(val("capacity")[1])
    if cap is None or cap <= 0 or not float(cap).is_integer():
        result.error(f"{where('capacity')}: capacity must be a whole number above 0.")
        ok = False
    else:
        e["capacity"] = int(cap)

    price_text = _text(val("price")[1])
    price = _number(val("price")[1]) if price_text else 0.0
    if price is None or price < 0:
        result.error(f"{where('price')}: the ticket price must be a number (blank or 0 for free).")
        ok = False
    else:
        e["is_free"] = price == 0
        e["ticket_price"] = None if price == 0 else round(price, 2)

    guests_text = _text(val("guests")[1])
    guests = _number(val("guests")[1]) if guests_text else 0.0
    if guests is None or guests not in (0, 1, 2, 3, 4):
        result.error(f"{where('guests')}: guests per registration must be 0 to 4.")
        ok = False
    else:
        e["max_guests"] = int(guests)

    for f, key in (("opens", "registration_opens_at"), ("closes", "registration_closes_at")):
        w, good = _datetime(val(f)[1])
        if not good:
            result.error(f"{where(f)}: '{_text(val(f)[1])}' isn't a date and time (e.g. 1 Nov 2026 10:00 am).")
            ok = False
        e[key] = w
    if e.get("registration_closes_at") and e.get("start") and e["registration_closes_at"] > e["start"]:
        result.error(f"{where('closes')}: registration can't close after the event starts.")
        ok = False
    if e.get("registration_opens_at") and e.get("registration_closes_at") and e["registration_opens_at"] >= e["registration_closes_at"]:
        result.error(f"{where('opens')}: registration opens after it closes.")
        ok = False

    e["description"] = _text(val("description")[1]) or None
    for f, key in (("thumbnail", "thumbnail_url"), ("banner", "banner_url"),
                   ("logo", "brand_logo_url"), ("logo_dark", "brand_logo_dark_url")):
        link, good = _link(val(f)[1])
        if not good:
            result.error(f"{where(f)}: the link must start https://")
            ok = False
        e[key] = link
    if ok:
        result.event = e


def _parse_speakers(result: SheetResult, tabs) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    rows_of: Dict[str, int] = {}
    for row, r in _table(result, tabs, "Speakers", SPEAKER_COLUMNS, ("name",)):
        here = f"Speakers, row {row}"
        name = _text(r.get("name"))
        if not name:
            result.error(f"{here}: no name.")
            continue
        key = name_key(name)
        if key in out:
            result.error(f"{here}: '{name}' is already on row {rows_of[key]}. Each person once.")
            continue
        role_text = _text(r.get("role"))
        role = ROLES.get(name_key(role_text), None) if role_text else "SPEAKER"
        if role is None:
            result.error(f"{here}: role '{role_text}' isn't one of Speaker, Panelist, Moderator, Chief guest, Guest of honour, Host.")
            continue
        email = _text(r.get("email")) or None
        if email and not _EMAIL.match(email):
            result.error(f"{here}: '{email}' isn't an email address.")
            continue
        links = {}
        bad = False
        for f, key2, what in (("linkedin", "linkedin_url", "LinkedIn link"), ("photo", "photo_url", "photo link")):
            link, good = _link(r.get(f))
            if not good:
                result.error(f"{here}: the {what} must start https://")
                bad = True
            links[key2] = link
        if bad:
            continue
        rows_of[key] = row
        out[key] = {
            "row": row,
            "fullname": name,
            "role": role,
            "title": _text(r.get("title")) or None,
            "organisation": _text(r.get("company")) or None,
            "email": email.lower() if email else None,
            "phone": _text(r.get("phone")) or None,
            "batch": _text(r.get("batch")) or None,
            "bio": _text(r.get("bio")) or None,
            "alumni_id": None,
            **links,
        }
    return out


def _parse_sponsors(result: SheetResult, tabs):
    sponsors: Dict[str, Dict[str, Any]] = {}
    partners: Dict[str, Dict[str, Any]] = {}
    rows_of: Dict[str, int] = {}
    for row, r in _table(result, tabs, "Sponsors", SPONSOR_COLUMNS, ("name", "tier")):
        here = f"Sponsors, row {row}"
        name = _text(r.get("name"))
        if not name:
            result.error(f"{here}: no name.")
            continue
        key = name_key(name)
        if key in rows_of:
            result.error(f"{here}: '{name}' is already on row {rows_of[key]}. Each sponsor once.")
            continue
        tier_text = _text(r.get("tier"))
        tier_key = name_key(tier_text.replace("_", " "))
        if not tier_text:
            result.error(f"{here}: no tier.")
            continue
        sponsor_type = SPONSOR_TIERS.get(tier_key) or SPONSOR_TIERS.get(tier_key + " sponsor")
        partner_type = PARTNER_TIERS.get(tier_key) or PARTNER_TIERS.get(tier_key + " partner")
        if not sponsor_type and not partner_type:
            result.error(f"{here}: tier '{tier_text}' isn't in the list (e.g. Gold sponsor, Media partner).")
            continue
        logo, good_l = _link(r.get("logo"))
        site, good_w = _link(r.get("website"))
        if not good_l or not good_w:
            result.error(f"{here}: the {'logo link' if not good_l else 'website'} must start https://")
            continue
        rows_of[key] = row
        label = _text(r.get("label")) or None
        if sponsor_type:
            sponsors[key] = {"row": row, "name": name, "sponsor_type": sponsor_type, "label": label,
                             "logo_url": logo, "website_url": site}
        else:
            if label:
                result.warnings.append(f"{here}: a partner has no label; '{label}' isn't shown.")
            partners[key] = {"row": row, "name": name, "partner_type": partner_type,
                             "logo_url": logo, "website_url": site}
    return sponsors, partners


def _parse_sessions(result, tabs, speakers, sponsors, partners, first_day, last_moment) -> None:
    parsed = []
    seen: Dict[Tuple[str, str], int] = {}
    for row, r in _table(result, tabs, "Sessions", SESSION_COLUMNS, ("start", "title")):
        here = f"Sessions, row {row}"
        bad = False
        title = _text(r.get("title"))
        if not title:
            result.error(f"{here}: no title.")
            bad = True
        day, good = _date(r.get("date"))
        if not good:
            result.error(f"{here}: '{_text(r.get('date'))}' isn't a date (e.g. 15 Nov 2026).")
            bad = True
        elif day is None:
            day = first_day
            if day is None:
                result.error(f"{here}: no date (and the Event tab has none to use).")
                bad = True
        start, good = _time(r.get("start"))
        if not good:
            result.error(f"{here}: start '{_text(r.get('start'))}' isn't a time (e.g. 9:30 or 2:15 pm).")
            bad = True
        elif start is None:
            result.error(f"{here}: no start time.")
            bad = True
        end, good = _time(r.get("end"))
        if not good:
            result.error(f"{here}: end '{_text(r.get('end'))}' isn't a time (e.g. 10:15 am).")
            bad = True
        type_text = _text(r.get("type"))
        session_type = SESSION_TYPES.get(type_text.casefold()) if type_text else None
        if type_text and not session_type:
            result.error(f"{here}: type '{type_text}' isn't one of Keynote, Talk, Panel, Fireside, Workshop, Showcase, Networking, Awards, Break.")
            bad = True

        people: List[Dict[str, Any]] = []
        for column, moderator in (("speakers", False), ("moderator", True)):
            for n in _names(r.get(column)):
                sp = speakers.get(name_key(n))
                if sp is None:
                    what = "moderator" if moderator else "speaker"
                    result.error(f"{here}: {what} '{n}' isn't on the Speakers tab.")
                    bad = True
                    continue
                existing = next((p for p in people if p["name"] == sp["fullname"]), None)
                if existing:
                    existing["moderator"] = existing["moderator"] or moderator
                else:
                    people.append({"name": sp["fullname"], "moderator": moderator})
        presented_by: List[str] = []
        for n in _names(r.get("presented_by")):
            k = name_key(n)
            if k in sponsors:
                if sponsors[k]["name"] not in presented_by:
                    presented_by.append(sponsors[k]["name"])
            elif k in partners:
                result.error(f"{here}: '{n}' is a partner; only sponsors can present a session.")
                bad = True
            else:
                result.error(f"{here}: sponsor '{n}' isn't on the Sponsors tab.")
                bad = True
        if bad:
            continue
        key = (wall(day, start), name_key(title))
        if key in seen:
            result.error(f"{here}: the same title and start as row {seen[key]}.")
            continue
        seen[key] = row
        parsed.append({
            "row": row, "day": day, "start_min": start, "end_min": end,
            "title": title,
            "session_type": session_type,
            "track": _text(r.get("hall")) or None,
            "pillar": _text(r.get("pillar")) or None,
            "description": _text(r.get("subtitle")) or None,
            "people": people,
            "presented_by": presented_by,
        })

    # Dates outside the event (a copied template keeps the template's
    # dates): move every session by the same number of days, so the sheet's
    # first day is the event's first day. Times of day stay as written.
    last_day = (last_moment - timedelta(minutes=1)).date() if last_moment else None
    days = sorted({s["day"] for s in parsed})
    if first_day and last_day and days and any(not (first_day <= d <= last_day) for d in days):
        shift = first_day - days[0]
        for s in parsed:
            s["day"] = s["day"] + shift
        for d in days:
            moved = d + shift
            if moved != d:
                result.warnings.append(
                    f"Sessions on {_day_text(d)} are shown on {_day_text(moved)}, the event's "
                    f"{'date' if first_day == last_day else 'day ' + str((moved - first_day).days + 1)}."
                )

    # A blank End runs to the next later start that day, less the gap.
    starts_by_day: Dict[date, List[int]] = {}
    for s in parsed:
        starts_by_day.setdefault(s["day"], []).append(s["start_min"])
    outside: Dict[date, List[int]] = {}
    for s in parsed:
        start_w = wall(s["day"], s["start_min"])
        if s["end_min"] is not None:
            end_min = s["end_min"]
            if end_min < s["start_min"]:
                if end_min + 1440 - s["start_min"] <= 12 * 60:  # e.g. 11:00 pm to 1:00 am
                    end_min += 1440
                else:
                    result.error(f"Sessions, row {s['row']}: it ends before it starts.")
                    continue
            end_w = wall(s["day"], end_min)
        else:
            later = sorted(m for m in starts_by_day[s["day"]] if m > s["start_min"])
            if later:
                end_min = later[0] - result.gap_minutes
                if end_min <= s["start_min"]:
                    end_min = later[0]
                end_w = wall(s["day"], end_min)
            else:
                # The day's last session runs until the event's end time on
                # that day (each day of 1–2 Mar ending 18:00 ends at 18:00).
                # A full-day event has no end time: one hour.
                closing = last_moment.hour * 60 + last_moment.minute if last_moment else None
                if closing and closing > s["start_min"]:
                    end_w = wall(s["day"], closing)
                elif last_moment is not None:
                    end_w = wall(s["day"], s["start_min"] + 60)
                else:
                    end_w = wall(s["day"], s["start_min"] + 60)
                    result.warnings.append(f"Sessions, row {s['row']}: no end time and nothing after it; set to one hour.")
        if first_day and last_day and not (first_day <= s["day"] <= last_day):
            outside.setdefault(s["day"], []).append(s["row"])
        result.sessions.append({
            "row": s["row"],
            "title": s["title"],
            "start": start_w,
            "end": end_w,
            "session_type": s["session_type"],
            "track": s["track"],
            "pillar": s["pillar"],
            "description": s["description"],
            "people": s["people"],
            "presented_by": s["presented_by"],
        })
    # One line per day outside the event, not one per session.
    for day, rows in sorted(outside.items()):
        when = _day_text(day)
        if len(rows) == 1:
            result.warnings.append(f"Sessions, row {rows[0]}: {when} is outside the event's dates.")
        else:
            result.warnings.append(f"{len(rows)} sessions are on {when}, outside the event's dates.")
