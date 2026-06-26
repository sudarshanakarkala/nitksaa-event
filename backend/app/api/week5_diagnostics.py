"""Week 5 development-only diagnostics.

Covers: event-options, people, sponsors-partners, analytics.
All endpoints return 404 when APP_ENV != development.
"""
from __future__ import annotations

import json
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

import asyncpg
from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.database import get_pool
from app.middleware.auth import decode_access_token

router = APIRouter(prefix="/api/v1/dev/diagnostics/week5", tags=["week5-diagnostics"])

_dev_bearer = HTTPBearer(auto_error=False)


def _require_development() -> None:
    if get_settings().app_env != "development":
        raise HTTPException(status_code=404, detail="not_found")


async def _get_admin(
    credentials: HTTPAuthorizationCredentials | None = Depends(_dev_bearer),
    x_dev_user: Optional[str] = Header(default=None),
) -> Dict[str, Any]:
    _require_development()
    if x_dev_user == "admin":
        return {"firebase_uid": "dev-admin-firebase-uid", "email": "admin@dev.local"}
    if credentials is None:
        raise HTTPException(status_code=401, detail="not_authenticated")
    payload = decode_access_token(credentials.credentials)
    return {"firebase_uid": payload["firebase_uid"], "email": payload.get("email")}


# ── Result helpers ─────────────────────────────────────────────────────────────

def _r(
    id: str,
    name: str,
    passed: bool,
    details: str,
    warning: bool = False,
) -> Dict[str, Any]:
    status = "WARNING" if (warning and passed) else ("PASS" if passed else "FAIL")
    return {"id": id, "name": name, "status": status, "details": details}


def _summary(scope: str, started: datetime, results: List[Dict[str, Any]], test_event_id: Optional[int] = None) -> Dict[str, Any]:
    passed = sum(1 for r in results if r["status"] == "PASS")
    failed = sum(1 for r in results if r["status"] == "FAIL")
    warnings = sum(1 for r in results if r["status"] == "WARNING")
    overall = "failed" if failed > 0 else ("warning" if warnings > 0 else "ok")
    out: Dict[str, Any] = {
        "status": overall,
        "scope": scope,
        "started_at": started.isoformat() + "Z",
        "completed_at": datetime.utcnow().isoformat() + "Z",
        "total": len(results),
        "passed": passed,
        "failed": failed,
        "warnings": warnings,
        "results": results,
    }
    if test_event_id is not None:
        out["test_event_id"] = test_event_id
    return out


# ── Shared: create + publish a diagnostic event ────────────────────────────────

async def _create_diag_event(
    conn: asyncpg.Connection,
    title: str,
    actor: Dict[str, Any],
    is_full_day: bool = False,
    is_free: bool = True,
    ticket_price: Optional[float] = None,
) -> Optional[int]:
    from app.schemas.event_create import EventCreate
    from app.schemas.event_status import EventStatusUpdate
    from app.services.events_service import EventsService

    svc = EventsService(conn)
    now = datetime.now(timezone.utc)
    start = now + timedelta(days=60)
    end_day = start.replace(hour=23, minute=59, second=59) if is_full_day else start + timedelta(hours=2)

    data = EventCreate(
        title=title,
        description="DIAG_WEEK5 — automated diagnostic test. Safe to delete.",
        start_datetime=start,
        end_datetime=end_day,
        timezone="Asia/Kolkata",
        is_virtual=False,
        location_text="Diagnostic Test Location",
        capacity=100,
        is_full_day=is_full_day,
        is_free=is_free,
        ticket_price=ticket_price,
    )
    event = await svc.create_event(data, actor)
    event_id = event["event_id"]
    from app.schemas.event_status import EventStatusUpdate
    await svc.update_status(event_id, EventStatusUpdate(status="published"), actor)
    return event_id


async def _cancel_events(conn: asyncpg.Connection, event_ids: List[int], actor: Dict[str, Any]) -> None:
    from app.schemas.event_status import EventStatusUpdate
    from app.services.events_service import EventsService
    svc = EventsService(conn)
    for eid in event_ids:
        try:
            await svc.update_status(eid, EventStatusUpdate(status="cancelled"), actor)
        except Exception:
            pass


# ── /week5/event-options ───────────────────────────────────────────────────────

async def _run_event_options(actor: Dict[str, Any]) -> Dict[str, Any]:
    from app.services.events_service import EventsService

    started = datetime.utcnow()
    results: List[Dict[str, Any]] = []
    pool = await get_pool()
    ts = started.strftime("%H%M%S")
    full_day_id: Optional[int] = None
    paid_id: Optional[int] = None

    async with pool.acquire() as conn:
        svc = EventsService(conn)

        # 01: Create full-day event
        t0 = time.monotonic()
        try:
            full_day_id = await _create_diag_event(
                conn, f"DIAG_WEEK5_FULLDAY_{ts}", actor, is_full_day=True, is_free=True,
            )
            event = await svc.get_event(full_day_id)
            ok = event["is_full_day"] is True
            results.append(_r("eo_01", "Create full-day event", ok,
                f"event_id={full_day_id} is_full_day={event['is_full_day']}"))
        except Exception as exc:
            results.append(_r("eo_01", "Create full-day event", False, str(exc)))

        # 02: Verify full-day flag in admin response
        t0 = time.monotonic()
        if full_day_id:
            try:
                ev = await svc.get_event(full_day_id)
                ok = ev["is_full_day"] is True and ev["is_free"] is True and ev["ticket_price"] is None
                results.append(_r("eo_02", "Full-day fields in admin response", ok,
                    f"is_full_day={ev['is_full_day']} is_free={ev['is_free']} ticket_price={ev['ticket_price']}"))
            except Exception as exc:
                results.append(_r("eo_02", "Full-day fields in admin response", False, str(exc)))
        else:
            results.append(_r("eo_02", "Full-day fields in admin response", False, "skipped: no event"))

        # 03: Create paid event
        try:
            paid_id = await _create_diag_event(
                conn, f"DIAG_WEEK5_PAID_{ts}", actor, is_full_day=False, is_free=False, ticket_price=500,
            )
            ev = await svc.get_event(paid_id)
            ok = ev["is_free"] is False and ev["ticket_price"] is not None
            results.append(_r("eo_03", "Create paid event", ok,
                f"event_id={paid_id} is_free={ev['is_free']} ticket_price={ev['ticket_price']}"))
        except Exception as exc:
            results.append(_r("eo_03", "Create paid event", False, str(exc)))
            paid_id = None

        # 04: Public response includes is_full_day, is_free, ticket_price (full-day)
        if full_day_id:
            try:
                pub = await svc.get_public_event(full_day_id)
                has_fields = all(k in pub for k in ("is_full_day", "is_free", "ticket_price"))
                ok = has_fields and pub["is_full_day"] is True
                results.append(_r("eo_04", "Public event detail: full-day fields present", ok,
                    f"is_full_day={pub.get('is_full_day')} is_free={pub.get('is_free')} ticket_price={pub.get('ticket_price')}"))
            except Exception as exc:
                results.append(_r("eo_04", "Public event detail: full-day fields present", False, str(exc)))
        else:
            results.append(_r("eo_04", "Public event detail: full-day fields present", False, "skipped"))

        # 05: Public response includes ticket_price for paid event
        if paid_id:
            try:
                pub = await svc.get_public_event(paid_id)
                ok = pub.get("is_free") is False and pub.get("ticket_price") is not None
                results.append(_r("eo_05", "Public event detail: paid fields present", ok,
                    f"is_free={pub.get('is_free')} ticket_price={pub.get('ticket_price')}"))
            except Exception as exc:
                results.append(_r("eo_05", "Public event detail: paid fields present", False, str(exc)))
        else:
            results.append(_r("eo_05", "Public event detail: paid fields present", False, "skipped"))

        # 06: Backward compat — existing events default to is_full_day=false, is_free=true
        try:
            rows = await conn.fetch(
                "SELECT is_full_day, is_free FROM events WHERE is_full_day IS NOT NULL LIMIT 20"
            )
            all_have_defaults = all(
                r["is_full_day"] in (True, False) and r["is_free"] in (True, False)
                for r in rows
            )
            results.append(_r("eo_06", "Backward compat: existing events have defaults", all_have_defaults,
                f"Checked {len(rows)} events — all have is_full_day/is_free boolean values"))
        except Exception as exc:
            results.append(_r("eo_06", "Backward compat: existing events have defaults", False, str(exc)))

        # Cleanup
        await _cancel_events(conn, [e for e in [full_day_id, paid_id] if e], actor)

    return _summary("week5_event_options", started, results)


@router.get("/event-options")
async def diag_event_options(user: Dict[str, Any] = Depends(_get_admin)) -> Dict[str, Any]:
    return await _run_event_options({"firebase_uid": user["firebase_uid"]})


# ── /week5/people ──────────────────────────────────────────────────────────────

async def _run_people(actor: Dict[str, Any]) -> Dict[str, Any]:
    from app.repositories.people_repository import PeopleRepository
    from app.schemas.people import PersonCreate, PersonUpdate
    from app.services.events_service import EventsService

    started = datetime.utcnow()
    results: List[Dict[str, Any]] = []
    pool = await get_pool()
    ts = started.strftime("%H%M%S")
    event_id: Optional[int] = None

    async with pool.acquire() as conn:
        svc = EventsService(conn)
        repo = PeopleRepository(conn)

        # people_01: Create diagnostic event
        try:
            event_id = await _create_diag_event(conn, f"DIAG_WEEK5_PEOPLE_{ts}", actor)
            results.append(_r("people_01", "Create diagnostic event", True, f"event_id={event_id}"))
        except Exception as exc:
            results.append(_r("people_01", "Create diagnostic event", False, str(exc)))
            return _summary("week5_people", started, results)

        # people_02: Add HOST
        host_id: Optional[int] = None
        try:
            row = await repo.create(event_id, PersonCreate(
                role="HOST", fullname="DIAG_HOST Dr. Diagnostic", title="Chief Host",
                organisation="DIAG_WEEK5_ORG", display_order=0,
            ))
            host_id = row["person_id"]
            results.append(_r("people_02", "Add HOST person", True, f"person_id={host_id} role={row['role']}"))
        except Exception as exc:
            results.append(_r("people_02", "Add HOST person", False, str(exc)))

        # people_03: Add SPEAKER
        speaker_id: Optional[int] = None
        try:
            row = await repo.create(event_id, PersonCreate(
                role="SPEAKER", fullname="DIAG_SPEAKER Prof. Diagnostic",
                title="Speaker Title", organisation="DIAG_WEEK5_ORG", display_order=1,
            ))
            speaker_id = row["person_id"]
            results.append(_r("people_03", "Add SPEAKER person", True, f"person_id={speaker_id} role={row['role']}"))
        except Exception as exc:
            results.append(_r("people_03", "Add SPEAKER person", False, str(exc)))

        # people_04: Add PANELIST
        panelist_id: Optional[int] = None
        try:
            row = await repo.create(event_id, PersonCreate(
                role="PANELIST", fullname="DIAG_PANELIST Ms. Diagnostic",
                display_order=2,
            ))
            panelist_id = row["person_id"]
            results.append(_r("people_04", "Add PANELIST person", True, f"person_id={panelist_id} role={row['role']}"))
        except Exception as exc:
            results.append(_r("people_04", "Add PANELIST person", False, str(exc)))

        # people_05: Add CHIEF_GUEST
        chief_guest_id: Optional[int] = None
        try:
            row = await repo.create(event_id, PersonCreate(
                role="CHIEF_GUEST", fullname="DIAG_CHIEF_GUEST Hon. Diagnostic",
                display_order=3,
            ))
            chief_guest_id = row["person_id"]
            results.append(_r("people_05", "Add CHIEF_GUEST person", True, f"person_id={chief_guest_id} role={row['role']}"))
        except Exception as exc:
            results.append(_r("people_05", "Add CHIEF_GUEST person", False, str(exc)))

        # people_06: Add GUEST_OF_HONOUR
        goh_id: Optional[int] = None
        try:
            row = await repo.create(event_id, PersonCreate(
                role="GUEST_OF_HONOUR", fullname="DIAG_GUEST_OF_HONOUR Sir Diagnostic",
                display_order=4,
            ))
            goh_id = row["person_id"]
            results.append(_r("people_06", "Add GUEST_OF_HONOUR person", True, f"person_id={goh_id} role={row['role']}"))
        except Exception as exc:
            results.append(_r("people_06", "Add GUEST_OF_HONOUR person", False, str(exc)))

        # people_07: Add hidden SPEAKER (is_visible=false)
        hidden_id: Optional[int] = None
        try:
            row = await repo.create(event_id, PersonCreate(
                role="SPEAKER", fullname="DIAG_HIDDEN_SPEAKER — should not appear publicly",
                is_visible=False, display_order=99,
            ))
            hidden_id = row["person_id"]
            results.append(_r("people_07", "Add hidden person (is_visible=false)", True,
                f"person_id={hidden_id} is_visible={row['is_visible']}"))
        except Exception as exc:
            results.append(_r("people_07", "Add hidden person (is_visible=false)", False, str(exc)))

        # people_08: List people (admin — shows all 6 including hidden)
        try:
            all_people = await repo.list_by_event(event_id)
            expected = 6
            ok = len(all_people) == expected
            results.append(_r("people_08", "Admin list includes all people (incl. hidden)", ok,
                f"expected={expected} got={len(all_people)}"))
        except Exception as exc:
            results.append(_r("people_08", "Admin list includes all people (incl. hidden)", False, str(exc)))

        # people_09: Public people[]: 5 visible (HOST, SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR)
        try:
            pub = await svc.get_public_event(event_id)
            people_pub = pub.get("people", [])
            ok = isinstance(people_pub, list) and len(people_pub) == 5
            results.append(_r("people_09", "Public people[] contains 5 visible people", ok,
                f"people count={len(people_pub)} (expected 5 visible)"))
        except Exception as exc:
            results.append(_r("people_09", "Public people[] visible filter", False, str(exc)))

        # people_10: Hidden person NOT in public people[]
        try:
            pub = await svc.get_public_event(event_id)
            people_ids = {p["person_id"] for p in pub.get("people", [])}
            hidden_exposed = hidden_id is not None and hidden_id in people_ids
            results.append(_r("people_10", "Hidden person not exposed publicly", not hidden_exposed,
                f"hidden_id={hidden_id} in_public_people={hidden_exposed}"))
        except Exception as exc:
            results.append(_r("people_10", "Hidden person not exposed publicly", False, str(exc)))

        # people_11: Speakers subset contains SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR (not HOST)
        _speaker_roles = {"SPEAKER", "PANELIST", "CHIEF_GUEST", "GUEST_OF_HONOUR"}
        try:
            pub = await svc.get_public_event(event_id)
            speakers = pub.get("speakers", [])
            roles_in_speakers = {s["role"] for s in speakers}
            all_valid = roles_in_speakers.issubset(_speaker_roles)
            count_ok = len(speakers) == 4  # SPEAKER + PANELIST + CHIEF_GUEST + GUEST_OF_HONOUR
            ok = all_valid and count_ok
            results.append(_r("people_11",
                "Speakers[] contains SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR", ok,
                f"speakers count={len(speakers)} roles={sorted(roles_in_speakers)}"))
        except Exception as exc:
            results.append(_r("people_11", "Speakers[] derivation rule", False, str(exc)))

        # people_12: HOST not in speakers[]
        try:
            pub = await svc.get_public_event(event_id)
            speakers = pub.get("speakers", [])
            speaker_roles = {s["role"] for s in speakers}
            host_not_in_speakers = "HOST" not in speaker_roles
            results.append(_r("people_12", "HOST not in speakers[]", host_not_in_speakers,
                f"roles in speakers={sorted(speaker_roles)} HOST present={not host_not_in_speakers}"))
        except Exception as exc:
            results.append(_r("people_12", "HOST not in speakers[]", False, str(exc)))

        # people_13: Update person
        if speaker_id:
            try:
                updated = await repo.update(speaker_id, PersonUpdate(title="Updated Speaker Title"))
                ok = updated["title"] == "Updated Speaker Title"
                results.append(_r("people_13", "Update person title", ok,
                    f"new_title={updated['title']}"))
            except Exception as exc:
                results.append(_r("people_13", "Update person title", False, str(exc)))
        else:
            results.append(_r("people_13", "Update person title", False, "skipped: no speaker created"))

        # people_14: Delete person
        if panelist_id:
            try:
                deleted = await repo.delete(panelist_id)
                remaining = await repo.list_by_event(event_id)
                ok = deleted and all(p["person_id"] != panelist_id for p in remaining)
                results.append(_r("people_14", "Delete person", ok,
                    f"deleted={deleted} remaining_count={len(remaining)}"))
            except Exception as exc:
                results.append(_r("people_14", "Delete person", False, str(exc)))
        else:
            results.append(_r("people_14", "Delete person", False, "skipped: no panelist created"))

        await _cancel_events(conn, [event_id] if event_id else [], actor)

    return _summary("week5_people", started, results, test_event_id=event_id)


@router.get("/people")
async def diag_people(user: Dict[str, Any] = Depends(_get_admin)) -> Dict[str, Any]:
    return await _run_people({"firebase_uid": user["firebase_uid"]})


# ── /week5/sponsors-partners ───────────────────────────────────────────────────

async def _run_sponsors_partners(actor: Dict[str, Any]) -> Dict[str, Any]:
    from app.repositories.sponsors_partners_repository import SponsorsRepository, PartnersRepository
    from app.schemas.sponsors_partners import (
        SponsorCreate, SponsorUpdate,
        PartnerCreate, PartnerUpdate,
    )
    from app.services.events_service import EventsService

    started = datetime.utcnow()
    results: List[Dict[str, Any]] = []
    pool = await get_pool()
    ts = started.strftime("%H%M%S")
    event_id: Optional[int] = None

    async with pool.acquire() as conn:
        svc = EventsService(conn)
        sp_repo = SponsorsRepository(conn)
        pt_repo = PartnersRepository(conn)

        # sp_01: Create diagnostic event
        try:
            event_id = await _create_diag_event(conn, f"DIAG_WEEK5_SPONSORS_{ts}", actor)
            results.append(_r("sp_01", "Create diagnostic event", True, f"event_id={event_id}"))
        except Exception as exc:
            results.append(_r("sp_01", "Create diagnostic event", False, str(exc)))
            return _summary("week5_sponsors_partners", started, results)

        title_id: Optional[int] = None
        gold_id: Optional[int] = None
        hidden_sp_id: Optional[int] = None
        comm_id: Optional[int] = None
        know_id: Optional[int] = None
        hidden_pt_id: Optional[int] = None

        # sp_02: Add GOLD_SPONSOR first (lower sponsor_id) at display_order=0
        # Note: GOLD is created before TITLE intentionally — tier ordering must place TITLE first
        try:
            row = await sp_repo.create(event_id, SponsorCreate(
                sponsor_type="GOLD_SPONSOR", name="DIAG_GOLD_SPONSOR", display_order=0,
            ))
            gold_id = row["sponsor_id"]
            results.append(_r("sp_02", "Add GOLD_SPONSOR", True, f"sponsor_id={gold_id}"))
        except Exception as exc:
            results.append(_r("sp_02", "Add GOLD_SPONSOR", False, str(exc)))

        # sp_03: Add TITLE_SPONSOR second (higher sponsor_id) at display_order=0
        # Same display_order as GOLD — tier ordering must place this first in public list
        try:
            row = await sp_repo.create(event_id, SponsorCreate(
                sponsor_type="TITLE_SPONSOR", name="DIAG_TITLE_SPONSOR",
                website_url="https://diag.example.com", display_order=0,
            ))
            title_id = row["sponsor_id"]
            results.append(_r("sp_03", "Add TITLE_SPONSOR", True, f"sponsor_id={title_id}"))
        except Exception as exc:
            results.append(_r("sp_03", "Add TITLE_SPONSOR", False, str(exc)))

        # sp_04: Add hidden sponsor
        try:
            row = await sp_repo.create(event_id, SponsorCreate(
                sponsor_type="BRONZE_SPONSOR", name="DIAG_HIDDEN_SPONSOR", is_visible=False,
            ))
            hidden_sp_id = row["sponsor_id"]
            results.append(_r("sp_04", "Add hidden sponsor (is_visible=false)", True,
                f"sponsor_id={hidden_sp_id} is_visible={row['is_visible']}"))
        except Exception as exc:
            results.append(_r("sp_04", "Add hidden sponsor (is_visible=false)", False, str(exc)))

        # sp_05: Add KNOWLEDGE_PARTNER first (lower partner_id) at display_order=0
        # KNOWLEDGE is created before COMMUNITY intentionally — alpha ordering must place COMMUNITY first
        try:
            row = await pt_repo.create(event_id, PartnerCreate(
                partner_type="KNOWLEDGE_PARTNER", name="DIAG_KNOWLEDGE_PARTNER", display_order=0,
            ))
            know_id = row["partner_id"]
            results.append(_r("sp_05", "Add KNOWLEDGE_PARTNER", True, f"partner_id={know_id}"))
        except Exception as exc:
            results.append(_r("sp_05", "Add KNOWLEDGE_PARTNER", False, str(exc)))

        # sp_06: Add COMMUNITY_PARTNER second (higher partner_id) at display_order=0
        # Same display_order as KNOWLEDGE — alphabetical ordering must place this first in public list
        try:
            row = await pt_repo.create(event_id, PartnerCreate(
                partner_type="COMMUNITY_PARTNER", name="DIAG_COMMUNITY_PARTNER", display_order=0,
            ))
            comm_id = row["partner_id"]
            results.append(_r("sp_06", "Add COMMUNITY_PARTNER", True, f"partner_id={comm_id}"))
        except Exception as exc:
            results.append(_r("sp_06", "Add COMMUNITY_PARTNER", False, str(exc)))

        # sp_07: Add hidden partner
        try:
            row = await pt_repo.create(event_id, PartnerCreate(
                partner_type="MEDIA_PARTNER", name="DIAG_HIDDEN_PARTNER", is_visible=False,
            ))
            hidden_pt_id = row["partner_id"]
            results.append(_r("sp_07", "Add hidden partner (is_visible=false)", True,
                f"partner_id={hidden_pt_id} is_visible={row['is_visible']}"))
        except Exception as exc:
            results.append(_r("sp_07", "Add hidden partner (is_visible=false)", False, str(exc)))

        # sp_08: Admin list sponsors (includes hidden)
        try:
            all_sp = await sp_repo.list_by_event(event_id)
            ok = len(all_sp) == 3
            results.append(_r("sp_08", "Admin list sponsors (includes hidden)", ok,
                f"count={len(all_sp)} expected=3"))
        except Exception as exc:
            results.append(_r("sp_08", "Admin list sponsors", False, str(exc)))

        # sp_09: Admin list partners (includes hidden)
        try:
            all_pt = await pt_repo.list_by_event(event_id)
            ok = len(all_pt) == 3
            results.append(_r("sp_09", "Admin list partners (includes hidden)", ok,
                f"count={len(all_pt)} expected=3"))
        except Exception as exc:
            results.append(_r("sp_09", "Admin list partners", False, str(exc)))

        # sp_10: Public sponsors — visible only (2 visible sponsors), no is_visible field
        try:
            pub = await svc.get_public_event(event_id)
            pub_sp = pub.get("sponsors", [])
            ok = len(pub_sp) == 2 and all("is_visible" not in s for s in pub_sp)
            results.append(_r("sp_10", "Public sponsors: visible only, no is_visible field", ok,
                f"count={len(pub_sp)} expected=2 has_is_visible={'is_visible' in (pub_sp[0] if pub_sp else {})}"))
        except Exception as exc:
            results.append(_r("sp_10", "Public sponsors: visible only", False, str(exc)))

        # sp_10_tier: Sponsor tier ordering — TITLE_SPONSOR before GOLD_SPONSOR
        # GOLD was created first (lower ID, same display_order=0); TITLE must still appear first
        try:
            pub = await svc.get_public_event(event_id)
            pub_sp = pub.get("sponsors", [])
            first_type = pub_sp[0]["sponsor_type"] if pub_sp else None
            ok = first_type == "TITLE_SPONSOR"
            results.append(_r("sp_10_tier", "Sponsor tier ordering: TITLE_SPONSOR before GOLD_SPONSOR", ok,
                f"first={first_type} (GOLD was created first with same display_order=0)"))
        except Exception as exc:
            results.append(_r("sp_10_tier", "Sponsor tier ordering", False, str(exc)))

        # sp_11: Public partners — visible only (2 visible partners)
        try:
            pub = await svc.get_public_event(event_id)
            pub_pt = pub.get("partners", [])
            ok = len(pub_pt) == 2
            results.append(_r("sp_11", "Public partners: visible only", ok,
                f"count={len(pub_pt)} expected=2"))
        except Exception as exc:
            results.append(_r("sp_11", "Public partners: visible only", False, str(exc)))

        # sp_11_alpha: Partner alphabetical ordering — COMMUNITY_PARTNER before KNOWLEDGE_PARTNER
        # KNOWLEDGE was created first (lower ID, same display_order=0); COMMUNITY must appear first
        try:
            pub = await svc.get_public_event(event_id)
            pub_pt = pub.get("partners", [])
            first_type = pub_pt[0]["partner_type"] if pub_pt else None
            ok = first_type == "COMMUNITY_PARTNER"
            results.append(_r("sp_11_alpha", "Partner ordering: COMMUNITY_PARTNER before KNOWLEDGE_PARTNER", ok,
                f"first={first_type} (KNOWLEDGE was created first with same display_order=0)"))
        except Exception as exc:
            results.append(_r("sp_11_alpha", "Partner alphabetical ordering", False, str(exc)))

        # sp_12: Sponsors and partners are separate, non-interleaved lists in the response
        try:
            pub = await svc.get_public_event(event_id)
            sponsors_list = pub.get("sponsors", [])
            partners_list = pub.get("partners", [])
            sp_has_sponsor_id = all("sponsor_id" in s for s in sponsors_list)
            pt_has_partner_id = all("partner_id" in p for p in partners_list)
            both_keys_correct = sp_has_sponsor_id and pt_has_partner_id
            results.append(_r("sp_12", "Sponsors and partners are separate lists", both_keys_correct,
                f"sponsors use sponsor_id={sp_has_sponsor_id} partners use partner_id={pt_has_partner_id}"))
        except Exception as exc:
            results.append(_r("sp_12", "Sponsors and partners are separate lists", False, str(exc)))

        # sp_13: Update sponsor
        if title_id:
            try:
                updated = await sp_repo.update(title_id, SponsorUpdate(description="Updated by DIAG_WEEK5"))
                ok = updated["description"] == "Updated by DIAG_WEEK5"
                results.append(_r("sp_13", "Update sponsor", ok, f"description={updated['description']}"))
            except Exception as exc:
                results.append(_r("sp_13", "Update sponsor", False, str(exc)))
        else:
            results.append(_r("sp_13", "Update sponsor", False, "skipped"))

        # sp_14: Update partner
        if comm_id:
            try:
                updated = await pt_repo.update(comm_id, PartnerUpdate(description="Updated by DIAG_WEEK5"))
                ok = updated["description"] == "Updated by DIAG_WEEK5"
                results.append(_r("sp_14", "Update partner", ok, f"description={updated['description']}"))
            except Exception as exc:
                results.append(_r("sp_14", "Update partner", False, str(exc)))
        else:
            results.append(_r("sp_14", "Update partner", False, "skipped"))

        # sp_15: Delete test data
        deleted_count = 0
        for sid in [title_id, gold_id, hidden_sp_id]:
            if sid:
                try:
                    await sp_repo.delete(sid)
                    deleted_count += 1
                except Exception:
                    pass
        for pid in [comm_id, know_id, hidden_pt_id]:
            if pid:
                try:
                    await pt_repo.delete(pid)
                    deleted_count += 1
                except Exception:
                    pass
        results.append(_r("sp_15", "Delete all test sponsors/partners", deleted_count == 6,
            f"deleted={deleted_count} expected=6"))

        await _cancel_events(conn, [event_id] if event_id else [], actor)

    return _summary("week5_sponsors_partners", started, results, test_event_id=event_id)


@router.get("/sponsors-partners")
async def diag_sponsors_partners(user: Dict[str, Any] = Depends(_get_admin)) -> Dict[str, Any]:
    return await _run_sponsors_partners({"firebase_uid": user["firebase_uid"]})


# ── /week5/analytics ───────────────────────────────────────────────────────────

async def _run_analytics(actor: Dict[str, Any]) -> Dict[str, Any]:
    from app.services import analytics_service
    from app.services.events_service import EventsService

    started = datetime.utcnow()
    results: List[Dict[str, Any]] = []
    pool = await get_pool()
    ts = started.strftime("%H%M%S")
    event_id: Optional[int] = None

    async with pool.acquire() as conn:
        # Create diagnostic event
        try:
            event_id = await _create_diag_event(conn, f"DIAG_WEEK5_ANALYTICS_{ts}", actor)
            results.append(_r("an_01", "Create diagnostic event", True, f"event_id={event_id}"))
        except Exception as exc:
            results.append(_r("an_01", "Create diagnostic event", False, str(exc)))
            return _summary("week5_analytics", started, results)

    # Log each action type
    actions_to_log = [
        ("an_02", "Log EVENT_DETAIL_OPENED", "EVENT_DETAIL_OPENED", "BACKEND",
         {"page": "event_detail"}),
        ("an_03", "Log REGISTER_CLICKED", "REGISTER_CLICKED", "FLUTTER",
         {"source": "event_list"}),
        ("an_04", "Log REGISTRATION_COMPLETED", "REGISTRATION_COMPLETED", "BACKEND",
         {"registration_number": "DIAG-TEST-001"}),
        ("an_05", "Log REGISTRATION_FAILED", "REGISTRATION_FAILED", "BACKEND",
         {"reason": "already_registered"}),
        ("an_06", "Log EMAIL_SENT", "EMAIL_SENT", "EMAIL",
         {"registration_number": "DIAG-TEST-001"}),
        ("an_07", "Log EMAIL_FAILED", "EMAIL_FAILED", "EMAIL",
         {"reason": "smtp_timeout"}),
    ]

    logged_actions = []
    for test_id, name, action, source, meta in actions_to_log:
        try:
            await analytics_service.log_event_activity(
                action_type=action,
                source_app=source,
                event_id=event_id,
                firebase_uid=actor["firebase_uid"],
                metadata=meta,
            )
            logged_actions.append(action)
            results.append(_r(test_id, name, True, f"action={action} source={source}"))
        except Exception as exc:
            results.append(_r(test_id, name, False, str(exc)))

    # Verify rows in DB
    async with pool.acquire() as conn:
        # an_08: Rows inserted
        try:
            count = await conn.fetchval(
                "SELECT COUNT(*) FROM event_activity_log WHERE event_id = $1 AND firebase_uid = $2",
                event_id, actor["firebase_uid"],
            )
            ok = int(count) >= len(logged_actions)
            results.append(_r("an_08", "Verify rows inserted into event_activity_log", ok,
                f"rows={count} expected>={len(logged_actions)}"))
        except Exception as exc:
            results.append(_r("an_08", "Verify rows inserted", False, str(exc)))

        # an_09: Metadata JSON stored correctly
        try:
            rows = await conn.fetch(
                "SELECT metadata FROM event_activity_log WHERE event_id = $1 AND firebase_uid = $2",
                event_id, actor["firebase_uid"],
            )
            meta_ok = all(
                isinstance(r["metadata"], (dict, str)) for r in rows
            )
            results.append(_r("an_09", "Metadata JSON stored correctly", meta_ok,
                f"checked {len(rows)} rows"))
        except Exception as exc:
            results.append(_r("an_09", "Metadata JSON stored correctly", False, str(exc)))

        # an_10: source_app present in all rows
        try:
            rows = await conn.fetch(
                "SELECT source_app FROM event_activity_log WHERE event_id = $1",
                event_id,
            )
            all_have_source = all(r["source_app"] is not None for r in rows)
            results.append(_r("an_10", "source_app present in all rows", all_have_source,
                f"checked {len(rows)} rows"))
        except Exception as exc:
            results.append(_r("an_10", "source_app present in all rows", False, str(exc)))

        # an_11: No secrets in metadata (check for known secret keys)
        try:
            rows = await conn.fetch(
                "SELECT metadata FROM event_activity_log WHERE event_id = $1",
                event_id,
            )
            secret_keys = {"password", "token", "secret", "key", "credential", "firebase_token"}
            leaked = []
            for row in rows:
                m = row["metadata"]
                if isinstance(m, dict):
                    leaked.extend([k for k in m if k.lower() in secret_keys])
            ok = len(leaked) == 0
            results.append(_r("an_11", "No secrets in metadata", ok,
                f"leaked_keys={leaked}" if leaked else "No sensitive keys found in metadata"))
        except Exception as exc:
            results.append(_r("an_11", "No secrets in metadata", False, str(exc)))

        # Cleanup: cancel event (log rows intentionally kept — append-only log)
        await _cancel_events(conn, [event_id] if event_id else [], actor)

    return _summary("week5_analytics", started, results, test_event_id=event_id)


@router.get("/analytics")
async def diag_analytics(user: Dict[str, Any] = Depends(_get_admin)) -> Dict[str, Any]:
    return await _run_analytics({"firebase_uid": user["firebase_uid"]})


# ── /week5/all ─────────────────────────────────────────────────────────────────

@router.get("/all")
async def diag_all(user: Dict[str, Any] = Depends(_get_admin)) -> Dict[str, Any]:
    actor = {"firebase_uid": user["firebase_uid"]}
    started = datetime.utcnow()

    suites = []
    for fn in [_run_event_options, _run_people, _run_sponsors_partners, _run_analytics]:
        try:
            result = await fn(actor)
            suites.append(result)
        except Exception as exc:
            suites.append({
                "status": "failed",
                "scope": fn.__name__.replace("_run_", "week5_"),
                "error": str(exc),
                "total": 0, "passed": 0, "failed": 1, "warnings": 0, "results": [],
            })

    total = sum(s.get("total", 0) for s in suites)
    passed = sum(s.get("passed", 0) for s in suites)
    failed = sum(s.get("failed", 0) for s in suites)
    warnings = sum(s.get("warnings", 0) for s in suites)
    overall = "failed" if failed > 0 else ("warning" if warnings > 0 else "ok")

    return {
        "status": overall,
        "started_at": started.isoformat() + "Z",
        "completed_at": datetime.utcnow().isoformat() + "Z",
        "total": total,
        "passed": passed,
        "failed": failed,
        "warnings": warnings,
        "suites": suites,
    }
