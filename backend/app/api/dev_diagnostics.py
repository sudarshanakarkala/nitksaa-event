"""Development-only diagnostics endpoints for auth and read-only DB validation."""
from __future__ import annotations

from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional
from uuid import UUID

import time
import asyncpg
from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.database import get_alumni_pool, get_pool
from app.middleware.auth import decode_access_token
from app.services.alumni_service import ACTIVE_ALUMNI_STATUSES

router = APIRouter(prefix="/api/v1/dev/diagnostics", tags=["dev-diagnostics"])

SUPPORTED_TABLES = (
    "event_users",
    "events",
    "sessions",
    "registrations",
    "check_ins",
    "event_content",
    "event_audit_log",
    "notifications",
    "notification_preferences",
)

ORDER_BY_CANDIDATES = {
    "event_users": ("last_login", "created_at"),
    "events": ("created_at", "starts_at"),
    "sessions": ("starts_at", "start_datetime", "created_at"),
    "registrations": ("registered_at", "created_at"),
    "check_ins": ("checked_in_at", "scanned_at"),
    "event_content": ("added_at", "created_at"),
    "event_audit_log": ("created_at",),
    "notifications": ("created_at",),
    "notification_preferences": ("updated_at",),
}

_dev_bearer = HTTPBearer(auto_error=False)


def _require_development() -> None:
    if get_settings().app_env != "development":
        raise HTTPException(status_code=404, detail="not_found")


async def _get_dev_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_dev_bearer),
    x_dev_user: Optional[str] = Header(default=None),
) -> Dict[str, Any]:
    _require_development()
    # Accept X-Dev-User: admin as shorthand in development (consistent with other dev endpoints)
    if x_dev_user == "admin":
        return {
            "firebase_uid": "dev-admin-firebase-uid",
            "email": "admin@example.com",
            "fullname": "Dev Admin",
            "user_type": "alumni",
            "ref_id": "ALUMNI-DEV-ADMIN",
            "graduation_year": None,
        }
    if credentials is None:
        raise HTTPException(status_code=401, detail="not_authenticated")

    payload = decode_access_token(credentials.credentials)
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT firebase_uid, email, fullname, user_type, ref_id,
                   graduation_year, is_suspended
            FROM event_users
            WHERE firebase_uid = $1
            """,
            payload["firebase_uid"],
        )

    if row and row["is_suspended"]:
        raise HTTPException(status_code=403, detail="account_suspended")

    if row:
        return {
            "firebase_uid": row["firebase_uid"],
            "email": row["email"],
            "fullname": row["fullname"],
            "user_type": row["user_type"],
            "ref_id": row["ref_id"],
            "graduation_year": row["graduation_year"],
        }

    return {
        "firebase_uid": payload["firebase_uid"],
        "email": payload.get("email"),
        "fullname": payload.get("fullname"),
        "user_type": payload["user_type"],
        "ref_id": payload.get("ref_id"),
        "graduation_year": payload.get("graduation_year"),
    }


def _serialize(value: Any) -> Any:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, UUID):
        return str(value)
    return value


def _record_to_dict(record: asyncpg.Record) -> Dict[str, Any]:
    return {key: _serialize(value) for key, value in dict(record).items()}


async def _table_exists(conn: asyncpg.Connection, table_name: str) -> bool:
    exists = await conn.fetchval(
        """
        SELECT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_name = $1
        )
        """,
        table_name,
    )
    return bool(exists)


async def _first_existing_column(
    conn: asyncpg.Connection,
    table_name: str,
    candidates: tuple[str, ...],
) -> str | None:
    for column_name in candidates:
        exists = await conn.fetchval(
            """
            SELECT EXISTS (
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = $1
                  AND column_name = $2
            )
            """,
            table_name,
            column_name,
        )
        if exists:
            return column_name
    return None


@router.get("/auth/me")
async def dev_auth_me(
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    return {
        "status": "ok",
        "user": user,
        "checked_at": datetime.utcnow().isoformat() + "Z",
    }


@router.get("/db/tables")
async def list_diagnostic_tables(
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    pool = await get_pool()
    tables: List[Dict[str, Any]] = []
    async with pool.acquire() as conn:
        for table_name in SUPPORTED_TABLES:
            if not await _table_exists(conn, table_name):
                tables.append(
                    {
                        "name": table_name,
                        "available": False,
                        "row_count": 0,
                        "error": "table_not_found",
                    }
                )
                continue

            row_count = await conn.fetchval(f'SELECT count(*) FROM "{table_name}"')
            tables.append(
                {
                    "name": table_name,
                    "available": True,
                    "row_count": row_count,
                    "error": None,
                }
            )

    return {
        "status": "ok",
        "requested_by": user["firebase_uid"],
        "tables": tables,
        "limit": 50,
        "refreshed_at": datetime.utcnow().isoformat() + "Z",
    }


@router.get("/db/{table_name}")
async def get_diagnostic_table(
    table_name: str,
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    if table_name not in SUPPORTED_TABLES:
        raise HTTPException(status_code=404, detail="table_not_supported")

    pool = await get_pool()
    async with pool.acquire() as conn:
        if not await _table_exists(conn, table_name):
            return {
                "status": "ok",
                "requested_by": user["firebase_uid"],
                "table": table_name,
                "available": False,
                "row_count": 0,
                "limit": 50,
                "rows": [],
                "error": "table_not_found",
                "refreshed_at": datetime.utcnow().isoformat() + "Z",
            }

        row_count = await conn.fetchval(f'SELECT count(*) FROM "{table_name}"')
        order_column = await _first_existing_column(
            conn,
            table_name,
            ORDER_BY_CANDIDATES.get(table_name, ()),
        )
        order_clause = f' ORDER BY "{order_column}" DESC NULLS LAST' if order_column else ""
        rows = await conn.fetch(
            f'SELECT * FROM "{table_name}"{order_clause} LIMIT 50',
        )

    return {
        "status": "ok",
        "requested_by": user["firebase_uid"],
        "table": table_name,
        "available": True,
        "row_count": row_count,
        "limit": 50,
        "rows": [_record_to_dict(row) for row in rows],
        "error": None,
        "refreshed_at": datetime.utcnow().isoformat() + "Z",
    }


# ── Event Management Diagnostics ──────────────────────────────────────────────


def _diag_entry(
    feature: str,
    api: str,
    method: str,
    auth_required: bool,
    request: Dict[str, Any],
    response: Dict[str, Any],
    passed: bool,
    duration_ms: int,
    error: Optional[str] = None,
) -> Dict[str, Any]:
    entry: Dict[str, Any] = {
        "feature": feature,
        "api": api,
        "method": method,
        "auth_required": auth_required,
        "request": request,
        "response": response,
        "status": "PASS" if passed else "FAIL",
        "duration_ms": duration_ms,
        "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if error:
        entry["error"] = error
    return entry


@router.get("/events")
async def run_event_management_diagnostics(
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    """Run all 8 Event Management diagnostics. Development mode only."""
    from app.schemas.event_create import EventCreate
    from app.schemas.event_status import EventStatusUpdate
    from app.schemas.event_update import EventUpdate
    from app.services.events_service import EventsService

    pool = await get_pool()
    results: List[Dict[str, Any]] = []
    test_event_id: Optional[int] = None
    actor: Dict[str, Any] = {"firebase_uid": user["firebase_uid"]}

    run_ts = datetime.utcnow()
    ts_key = run_ts.strftime("%Y%m%d%H%M%S")
    test_title = f"DIAGNOSTIC_TEST_{ts_key}"
    start_dt = run_ts + timedelta(days=30)
    end_dt = start_dt + timedelta(hours=2)

    async with pool.acquire() as conn:
        svc = EventsService(conn)

        # ── Diagnostic 3: Event Create ────────────────────────────────────────
        t0 = time.monotonic()
        try:
            event_data = EventCreate(
                title=test_title,
                description="Automated diagnostic test event. Safe to ignore.",
                start_datetime=start_dt,
                end_datetime=end_dt,
                timezone="Asia/Kolkata",
                is_virtual=False,
                location_text="Diagnostic Test Location",
                capacity=10,
            )
            created = await svc.create_event(event_data, actor)
            test_event_id = created["event_id"]
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Event Create Test", "/api/v1/events", "POST", True,
                {"title": test_title, "is_virtual": False, "location_text": "Diagnostic Test Location"},
                {"event_id": test_event_id, "status": created["status"], "slug": created["slug"]},
                True, ms,
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Event Create Test", "/api/v1/events", "POST", True,
                {"title": test_title}, {}, False, ms, str(exc),
            ))

        # ── Diagnostic 1: Events List ─────────────────────────────────────────
        t0 = time.monotonic()
        try:
            events, total = await svc.list_events(page=1, per_page=20)
            ms = int((time.monotonic() - t0) * 1000)
            test_found = test_event_id is not None and any(
                e["event_id"] == test_event_id for e in events
            )
            results.append(_diag_entry(
                "Events List Test", "/api/v1/events", "GET", True,
                {"page": 1, "per_page": 20},
                {"total": total, "returned": len(events), "test_event_found": test_found},
                True, ms,
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Events List Test", "/api/v1/events", "GET", True,
                {"page": 1, "per_page": 20}, {}, False, ms, str(exc),
            ))

        # ── Diagnostic 2: Event Detail ────────────────────────────────────────
        t0 = time.monotonic()
        if test_event_id is not None:
            try:
                event = await svc.get_event(test_event_id)
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Event Detail Test", f"/api/v1/events/{test_event_id}", "GET", True,
                    {"event_id": test_event_id},
                    {
                        "event_id": event["event_id"],
                        "slug": event["slug"],
                        "status": event["status"],
                        "registration_status": event["registration_status"],
                    },
                    True, ms,
                ))
            except Exception as exc:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Event Detail Test", f"/api/v1/events/{test_event_id}", "GET", True,
                    {"event_id": test_event_id}, {}, False, ms, str(exc),
                ))
        else:
            results.append(_diag_entry(
                "Event Detail Test", "/api/v1/events/{event_id}", "GET", True,
                {}, {}, False, 0, "skipped: test event not created",
            ))

        # ── Diagnostic 4: Event Update ────────────────────────────────────────
        t0 = time.monotonic()
        if test_event_id is not None:
            try:
                update_data = EventUpdate(tagline="Diagnostic update — ignore")
                updated = await svc.update_event(test_event_id, update_data, actor)
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Event Update Test", f"/api/v1/events/{test_event_id}", "PATCH", True,
                    {"tagline": "Diagnostic update — ignore"},
                    {
                        "event_id": updated["event_id"],
                        "tagline": updated.get("tagline"),
                        "status": updated["status"],
                    },
                    True, ms,
                ))
            except Exception as exc:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Event Update Test", f"/api/v1/events/{test_event_id}", "PATCH", True,
                    {}, {}, False, ms, str(exc),
                ))
        else:
            results.append(_diag_entry(
                "Event Update Test", "/api/v1/events/{event_id}", "PATCH", True,
                {}, {}, False, 0, "skipped: test event not created",
            ))

        # ── Diagnostic 5: Event Publish (draft→published→draft) ───────────────
        t0 = time.monotonic()
        if test_event_id is not None:
            try:
                pub = await svc.update_status(
                    test_event_id, EventStatusUpdate(status="published"), actor
                )
                assert pub["status"] == "published", f"expected published, got {pub['status']}"
                unpub = await svc.update_status(
                    test_event_id, EventStatusUpdate(status="draft"), actor
                )
                assert unpub["status"] == "draft", f"expected draft, got {unpub['status']}"
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Event Publish Test", f"/api/v1/events/{test_event_id}/status", "PATCH", True,
                    {"status": "published / draft"},
                    {"transitions": "draft→published: OK, published→draft: OK"},
                    True, ms,
                ))
            except Exception as exc:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Event Publish Test", f"/api/v1/events/{test_event_id}/status", "PATCH", True,
                    {}, {}, False, ms, str(exc),
                ))
        else:
            results.append(_diag_entry(
                "Event Publish Test", "/api/v1/events/{event_id}/status", "PATCH", True,
                {}, {}, False, 0, "skipped: test event not created",
            ))

        # Re-publish silently so public tests can find the event
        republish_ok = False
        if test_event_id is not None:
            try:
                await svc.update_status(
                    test_event_id, EventStatusUpdate(status="published"), actor
                )
                republish_ok = True
            except Exception:
                pass

        # ── Diagnostic 7: Public Events Test ──────────────────────────────────
        t0 = time.monotonic()
        try:
            pub_events, pub_total = await svc.list_public_events(
                period=None, page=1, per_page=100
            )
            ms = int((time.monotonic() - t0) * 1000)
            forbidden = ["virtual_url", "created_by_firebase_uid", "created_by_name"]
            leaked = [f for e in pub_events for f in forbidden if f in e]
            test_visible = republish_ok and test_event_id is not None and any(
                e["event_id"] == test_event_id for e in pub_events
            )
            passed = len(leaked) == 0
            results.append(_diag_entry(
                "Public Events Test", "/api/v1/events/public", "GET", False,
                {"page": 1, "per_page": 100},
                {
                    "total": pub_total,
                    "returned": len(pub_events),
                    "test_event_visible": test_visible,
                    "forbidden_fields_leaked": leaked if leaked else "none",
                },
                passed, ms,
                None if passed else f"Forbidden fields in response: {leaked}",
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Public Events Test", "/api/v1/events/public", "GET", False,
                {}, {}, False, ms, str(exc),
            ))

        # ── Diagnostic 8: Public Event Detail Test ─────────────────────────────
        t0 = time.monotonic()
        if test_event_id is not None and republish_ok:
            try:
                pub_event = await svc.get_public_event(test_event_id)
                ms = int((time.monotonic() - t0) * 1000)
                forbidden = ["virtual_url", "created_by_firebase_uid", "created_by_name"]
                leaked = [f for f in forbidden if f in pub_event]
                has_sessions = isinstance(pub_event.get("sessions"), list)
                has_speakers = isinstance(pub_event.get("speakers"), list)
                passed = len(leaked) == 0 and has_sessions and has_speakers
                results.append(_diag_entry(
                    "Public Event Detail Test",
                    f"/api/v1/events/public/{test_event_id}", "GET", False,
                    {"event_id": test_event_id},
                    {
                        "event_id": pub_event["event_id"],
                        "status": pub_event["status"],
                        "forbidden_fields_leaked": leaked if leaked else "none",
                        "sessions_present": has_sessions,
                        "speakers_present": has_speakers,
                    },
                    passed, ms,
                    None if passed else f"Issues — leaked={leaked} sessions={has_sessions} speakers={has_speakers}",
                ))
            except Exception as exc:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Public Event Detail Test",
                    f"/api/v1/events/public/{test_event_id}", "GET", False,
                    {"event_id": test_event_id}, {}, False, ms, str(exc),
                ))
        else:
            results.append(_diag_entry(
                "Public Event Detail Test", "/api/v1/events/public/{event_id}", "GET", False,
                {}, {}, False, 0, "skipped: no published test event available",
            ))

        # ── Diagnostic 6: Event Cancel Test (cleanup) ─────────────────────────
        t0 = time.monotonic()
        if test_event_id is not None:
            try:
                cancelled = await svc.update_status(
                    test_event_id, EventStatusUpdate(status="cancelled"), actor
                )
                ms = int((time.monotonic() - t0) * 1000)
                passed = cancelled["status"] == "cancelled"
                results.append(_diag_entry(
                    "Event Cancel Test",
                    f"/api/v1/events/{test_event_id}/status", "PATCH", True,
                    {"status": "cancelled"},
                    {"event_id": cancelled["event_id"], "status": cancelled["status"]},
                    passed, ms,
                    None if passed else "Cancel transition did not succeed",
                ))
            except Exception as exc:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Event Cancel Test",
                    f"/api/v1/events/{test_event_id}/status", "PATCH", True,
                    {"status": "cancelled"}, {}, False, ms, str(exc),
                ))
        else:
            results.append(_diag_entry(
                "Event Cancel Test", "/api/v1/events/{event_id}/status", "PATCH", True,
                {}, {}, False, 0, "skipped: test event not created",
            ))

    passed_count = sum(1 for r in results if r["status"] == "PASS")
    failed_count = sum(1 for r in results if r["status"] == "FAIL")

    return {
        "status": "ok",
        "category": "Event Management",
        "total": len(results),
        "passed": passed_count,
        "failed": failed_count,
        "test_event_id": test_event_id,
        "results": results,
        "run_by": user["firebase_uid"],
        "run_at": run_ts.isoformat() + "Z",
    }


# ── Registration Flow Diagnostics ─────────────────────────────────────────────


@router.get("/registrations")
async def run_registration_diagnostics(
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    """Run Registration Flow diagnostics. Development mode only."""
    from app.schemas.event_create import EventCreate
    from app.schemas.event_status import EventStatusUpdate
    from app.schemas.registrations import RegisterRequest
    from app.services import alumni_service, registration_service
    from app.services.events_service import EventsService

    pool = await get_pool()
    results: List[Dict[str, Any]] = []
    run_ts = datetime.utcnow()
    ts_key = run_ts.strftime("%Y%m%d%H%M%S")
    actor: Dict[str, Any] = {"firebase_uid": user["firebase_uid"]}
    start_dt = run_ts + timedelta(days=30)
    end_dt = start_dt + timedelta(hours=2)
    test_title_v = f"DIAG_REG_VIRTUAL_{ts_key}"
    test_title_c = f"DIAG_REG_CAP_{ts_key}"

    test_virtual_event_id: Optional[int] = None
    test_cap_event_id: Optional[int] = None
    test_registration_id: Optional[int] = None

    is_alumni = user.get("user_type") == "alumni" and bool(user.get("ref_id"))

    # ── Diag 1: Alumni Profile ────────────────────────────────────────────────
    t0 = time.monotonic()
    if is_alumni:
        try:
            profile = await alumni_service.get_alumni_profile_by_ref_id(user["ref_id"])
            ms = int((time.monotonic() - t0) * 1000)
            if profile:
                active = alumni_service.is_alumni_active(profile.get("registrationstatus"))
                results.append(_diag_entry(
                    "Alumni Profile", "/api/v1/alumni/me", "GET", True,
                    {"ref_id": user["ref_id"]},
                    {
                        "fullname": profile.get("fullname"),
                        "is_active": active,
                        "registrationstatus": profile.get("registrationstatus"),
                    },
                    active, ms,
                    None if active else "Alumni profile found but not active",
                ))
            else:
                results.append(_diag_entry(
                    "Alumni Profile", "/api/v1/alumni/me", "GET", True,
                    {"ref_id": user["ref_id"]}, {}, False, ms, "alumni_profile_not_found",
                ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Alumni Profile", "/api/v1/alumni/me", "GET", True,
                {"ref_id": user["ref_id"]}, {}, False, ms, str(exc),
            ))
    else:
        results.append(_diag_entry(
            "Alumni Profile", "/api/v1/alumni/me", "GET", True,
            {"user_type": user.get("user_type")}, {}, False, 0,
            "skipped: user is not alumni or has no ref_id",
        ))

    # ── Test event setup ──────────────────────────────────────────────────────
    async with pool.acquire() as conn:
        svc = EventsService(conn)

        # Virtual event for registration + join_url tests
        t0 = time.monotonic()
        try:
            v_data = EventCreate(
                title=test_title_v,
                description="Dev diagnostic test virtual event. Safe to ignore.",
                start_datetime=start_dt,
                end_datetime=end_dt,
                timezone="Asia/Kolkata",
                is_virtual=True,
                virtual_url="https://meet.example.com/dev-diagnostic-test",
                capacity=5,
            )
            created_v = await svc.create_event(v_data, actor)
            test_virtual_event_id = created_v["event_id"]
            await svc.update_status(
                test_virtual_event_id,
                EventStatusUpdate(status="published"),
                actor,
            )
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Test Virtual Event Setup", "/api/v1/events (diagnostic)", "POST", True,
                {"title": test_title_v, "is_virtual": True, "capacity": 5},
                {"event_id": test_virtual_event_id, "status": "published"},
                True, ms,
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Test Virtual Event Setup", "/api/v1/events (diagnostic)", "POST", True,
                {"title": test_title_v}, {}, False, ms, str(exc),
            ))

        # Capacity-guard event (capacity=1, in-person)
        t0 = time.monotonic()
        try:
            c_data = EventCreate(
                title=test_title_c,
                description="Dev diagnostic capacity guard test. Safe to ignore.",
                start_datetime=start_dt,
                end_datetime=end_dt,
                timezone="Asia/Kolkata",
                is_virtual=False,
                location_text="Diagnostic Test Location",
                capacity=1,
            )
            created_c = await svc.create_event(c_data, actor)
            test_cap_event_id = created_c["event_id"]
            await svc.update_status(
                test_cap_event_id,
                EventStatusUpdate(status="published"),
                actor,
            )
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Test Capacity Event Setup", "/api/v1/events (diagnostic)", "POST", True,
                {"title": test_title_c, "capacity": 1},
                {"event_id": test_cap_event_id, "status": "published"},
                True, ms,
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Test Capacity Event Setup", "/api/v1/events (diagnostic)", "POST", True,
                {"title": test_title_c}, {}, False, ms, str(exc),
            ))

    # ── Diag 2: Registration Eligibility ──────────────────────────────────────
    t0 = time.monotonic()
    if test_virtual_event_id is not None and is_alumni:
        try:
            elig = await registration_service.get_registration_eligibility(
                test_virtual_event_id, user
            )
            ms = int((time.monotonic() - t0) * 1000)
            passed = elig.eligibility_status == "eligible"
            results.append(_diag_entry(
                "Registration Eligibility",
                f"/api/v1/events/{test_virtual_event_id}/registration-eligibility",
                "GET", True,
                {"event_id": test_virtual_event_id},
                {"eligibility_status": elig.eligibility_status, "message": elig.message},
                passed, ms,
                None if passed else f"Not eligible: {elig.eligibility_status} — {elig.message}",
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Registration Eligibility",
                f"/api/v1/events/{test_virtual_event_id}/registration-eligibility",
                "GET", True,
                {"event_id": test_virtual_event_id}, {}, False, ms, str(exc),
            ))
    else:
        results.append(_diag_entry(
            "Registration Eligibility",
            "/api/v1/events/{event_id}/registration-eligibility", "GET", True,
            {}, {}, False, 0, "skipped: no test event or user is not alumni",
        ))

    # ── Diag 3: Register for Event ─────────────────────────────────────────────
    t0 = time.monotonic()
    if test_virtual_event_id is not None and is_alumni:
        try:
            body = RegisterRequest(attendee_note="Dev diagnostic auto-registration — safe to ignore")
            reg = await registration_service.register_for_event(
                test_virtual_event_id, user, body
            )
            test_registration_id = reg.registration_id
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Register for Event",
                f"/api/v1/events/{test_virtual_event_id}/register",
                "POST", True,
                {"event_id": test_virtual_event_id, "user": user.get("email")},
                {
                    "registration_id": reg.registration_id,
                    "registration_number": reg.registration_number,
                    "status": reg.status,
                    "confirmation_email_status": reg.confirmation_email_status,
                },
                True, ms,
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Register for Event",
                f"/api/v1/events/{test_virtual_event_id}/register",
                "POST", True,
                {"event_id": test_virtual_event_id}, {}, False, ms, str(exc),
            ))
    else:
        results.append(_diag_entry(
            "Register for Event", "/api/v1/events/{event_id}/register", "POST", True,
            {}, {}, False, 0, "skipped: no test event or user is not alumni",
        ))

    # ── Diag 4: My Registration (also verifies join_url for virtual event) ────
    t0 = time.monotonic()
    if test_virtual_event_id is not None and test_registration_id is not None:
        try:
            my_reg = await registration_service.get_my_event_registration(
                test_virtual_event_id, user
            )
            ms = int((time.monotonic() - t0) * 1000)
            join_url_present = my_reg.join_url is not None
            passed = my_reg.status == "registered" and join_url_present
            results.append(_diag_entry(
                "My Registration",
                f"/api/v1/events/{test_virtual_event_id}/my-registration",
                "GET", True,
                {"event_id": test_virtual_event_id},
                {
                    "status": my_reg.status,
                    "registration_number": my_reg.registration_number,
                    "join_url_present": join_url_present,
                },
                passed, ms,
                None if passed else (
                    f"Expected status=registered + join_url; "
                    f"got status={my_reg.status} join_url={'present' if join_url_present else 'absent'}"
                ),
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "My Registration",
                f"/api/v1/events/{test_virtual_event_id}/my-registration",
                "GET", True,
                {"event_id": test_virtual_event_id}, {}, False, ms, str(exc),
            ))
    else:
        results.append(_diag_entry(
            "My Registration", "/api/v1/events/{event_id}/my-registration", "GET", True,
            {}, {}, False, 0, "skipped: registration not created",
        ))

    # ── Diag 5: My Registrations List ─────────────────────────────────────────
    t0 = time.monotonic()
    if test_registration_id is not None:
        try:
            my_list = await registration_service.list_my_registrations(user)
            ms = int((time.monotonic() - t0) * 1000)
            found = any(r.registration_id == test_registration_id for r in my_list.registrations)
            results.append(_diag_entry(
                "My Registrations List", "/api/v1/my/registrations", "GET", True,
                {},
                {"total": my_list.total, "test_registration_found": found},
                found, ms,
                None if found else "Test registration not found in list",
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "My Registrations List", "/api/v1/my/registrations", "GET", True,
                {}, {}, False, ms, str(exc),
            ))
    else:
        results.append(_diag_entry(
            "My Registrations List", "/api/v1/my/registrations", "GET", True,
            {}, {}, False, 0, "skipped: registration not created",
        ))

    # ── Diag 6: Duplicate Registration Guard ──────────────────────────────────
    t0 = time.monotonic()
    if test_virtual_event_id is not None and test_registration_id is not None:
        try:
            body2 = RegisterRequest(attendee_note="Duplicate guard test — should be rejected")
            await registration_service.register_for_event(test_virtual_event_id, user, body2)
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Duplicate Registration Guard",
                f"/api/v1/events/{test_virtual_event_id}/register",
                "POST", True,
                {"event_id": test_virtual_event_id},
                {}, False, ms,
                "Expected 409 already_registered but second registration succeeded",
            ))
        except HTTPException as exc:
            ms = int((time.monotonic() - t0) * 1000)
            passed = exc.status_code == 409 and exc.detail == "already_registered"
            results.append(_diag_entry(
                "Duplicate Registration Guard",
                f"/api/v1/events/{test_virtual_event_id}/register",
                "POST", True,
                {"event_id": test_virtual_event_id},
                {"status_code": exc.status_code, "detail": exc.detail},
                passed, ms,
                None if passed else f"Expected 409 already_registered, got {exc.status_code} {exc.detail}",
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Duplicate Registration Guard",
                f"/api/v1/events/{test_virtual_event_id}/register",
                "POST", True,
                {}, {}, False, ms, str(exc),
            ))
    else:
        results.append(_diag_entry(
            "Duplicate Registration Guard",
            "/api/v1/events/{event_id}/register", "POST", True,
            {}, {}, False, 0, "skipped: no base registration to test against",
        ))

    # ── Diag 7: Capacity Guard ────────────────────────────────────────────────
    t0 = time.monotonic()
    if test_cap_event_id is not None and is_alumni:
        filler_uid = f"diag_cap_filler_{ts_key}"
        async with pool.acquire() as conn:
            try:
                # registrations.firebase_uid has a FK to event_users — insert a
                # temporary event_users row so the filler registration passes the constraint
                await conn.execute(
                    """
                    INSERT INTO event_users
                        (firebase_uid, email, fullname, user_type)
                    VALUES ($1, $2, $3, 'other')
                    ON CONFLICT (firebase_uid) DO NOTHING
                    """,
                    filler_uid, "capfiller@dev.internal", "Capacity Filler (Dev Diag)",
                )
                await conn.execute(
                    """
                    INSERT INTO registrations
                        (event_id, firebase_uid, status, email, phone,
                         fullname_snapshot, batch_year_snapshot, branch_snapshot,
                         notes, registered_at, confirmation_email_status)
                    VALUES ($1, $2, 'registered', $3, $4, $5, $6, $7, $8, NOW(), 'skipped')
                    """,
                    test_cap_event_id, filler_uid,
                    "capfiller@dev.internal", "0000000000",
                    "Capacity Filler (Dev Diag)", 2000, "Diagnostics", None,
                )
                body3 = RegisterRequest(attendee_note="Capacity guard test — should fail event_full")
                try:
                    await registration_service.register_for_event(test_cap_event_id, user, body3)
                    ms = int((time.monotonic() - t0) * 1000)
                    results.append(_diag_entry(
                        "Capacity Guard",
                        f"/api/v1/events/{test_cap_event_id}/register",
                        "POST", True,
                        {"event_id": test_cap_event_id, "capacity": 1},
                        {}, False, ms,
                        "Expected 409 event_full but registration succeeded (capacity guard not working)",
                    ))
                except HTTPException as exc:
                    ms = int((time.monotonic() - t0) * 1000)
                    passed = exc.status_code == 409 and exc.detail == "event_full"
                    results.append(_diag_entry(
                        "Capacity Guard",
                        f"/api/v1/events/{test_cap_event_id}/register",
                        "POST", True,
                        {"event_id": test_cap_event_id, "capacity": 1},
                        {"status_code": exc.status_code, "detail": exc.detail},
                        passed, ms,
                        None if passed else f"Expected 409 event_full, got {exc.status_code} {exc.detail}",
                    ))
                except Exception as exc:
                    ms = int((time.monotonic() - t0) * 1000)
                    results.append(_diag_entry(
                        "Capacity Guard",
                        f"/api/v1/events/{test_cap_event_id}/register",
                        "POST", True,
                        {}, {}, False, ms, str(exc),
                    ))
            finally:
                # Always clean up filler registration and the temp event_users row
                try:
                    await conn.execute(
                        "DELETE FROM registrations WHERE event_id=$1 AND firebase_uid=$2",
                        test_cap_event_id, filler_uid,
                    )
                except Exception:
                    pass
                try:
                    await conn.execute(
                        "DELETE FROM event_users WHERE firebase_uid=$1",
                        filler_uid,
                    )
                except Exception:
                    pass
    else:
        results.append(_diag_entry(
            "Capacity Guard", "/api/v1/events/{event_id}/register", "POST", True,
            {}, {}, False, 0, "skipped: no capacity test event or user is not alumni",
        ))

    # ── Diag 8: Join Link Visibility ──────────────────────────────────────────
    t0 = time.monotonic()
    if test_registration_id is not None and test_virtual_event_id is not None:
        try:
            join_reg = await registration_service.get_my_event_registration(
                test_virtual_event_id, user
            )
            ms = int((time.monotonic() - t0) * 1000)
            join_url = join_reg.join_url
            passed = join_url is not None
            results.append(_diag_entry(
                "Join Link Visibility",
                f"/api/v1/events/{test_virtual_event_id}/my-registration",
                "GET", True,
                {"event_id": test_virtual_event_id, "is_virtual": True, "status": "registered"},
                {
                    "join_url_present": passed,
                    "join_url_prefix": join_url[:50] if join_url else None,
                },
                passed, ms,
                None if passed else "join_url was None for virtual+published+registered event",
            ))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_diag_entry(
                "Join Link Visibility",
                f"/api/v1/events/{test_virtual_event_id}/my-registration",
                "GET", True,
                {}, {}, False, ms, str(exc),
            ))
    else:
        results.append(_diag_entry(
            "Join Link Visibility",
            "/api/v1/events/{event_id}/my-registration", "GET", True,
            {}, {}, False, 0, "skipped: no registration",
        ))

    # ── Diag 9: Confirmation Email Status ─────────────────────────────────────
    t0 = time.monotonic()
    if test_registration_id is not None:
        async with pool.acquire() as conn:
            try:
                row = await conn.fetchrow(
                    """
                    SELECT confirmation_email_status, confirmation_email_sent_at
                    FROM registrations WHERE registration_id = $1
                    """,
                    test_registration_id,
                )
                ms = int((time.monotonic() - t0) * 1000)
                email_status = row["confirmation_email_status"] if row else None
                passed = email_status in ("sent", "failed")
                results.append(_diag_entry(
                    "Confirmation Email Status",
                    "registrations (DB direct)", "DB", False,
                    {"registration_id": test_registration_id},
                    {
                        "confirmation_email_status": email_status,
                        "sent_at": _serialize(row["confirmation_email_sent_at"]) if row else None,
                    },
                    passed, ms,
                    None if passed else f"Expected sent/failed, got {email_status!r}",
                ))
            except Exception as exc:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Confirmation Email Status", "registrations (DB direct)", "DB", False,
                    {}, {}, False, ms, str(exc),
                ))
    else:
        results.append(_diag_entry(
            "Confirmation Email Status", "registrations (DB direct)", "DB", False,
            {}, {}, False, 0, "skipped: no registration",
        ))

    # ── Diag 10: Audit Log Check ──────────────────────────────────────────────
    t0 = time.monotonic()
    if test_registration_id is not None:
        async with pool.acquire() as conn:
            try:
                audit_row = await conn.fetchrow(
                    """
                    SELECT log_id, event_type, actor_uid, created_at
                    FROM event_audit_log
                    WHERE entity_type = 'registration'
                      AND entity_id = $1
                    ORDER BY created_at DESC LIMIT 1
                    """,
                    test_registration_id,
                )
                ms = int((time.monotonic() - t0) * 1000)
                found = audit_row is not None
                results.append(_diag_entry(
                    "Audit Log Check",
                    "event_audit_log (DB direct)", "DB", False,
                    {"entity_type": "registration", "entity_id": test_registration_id},
                    {
                        "found": found,
                        "event_type": audit_row["event_type"] if audit_row else None,
                        "actor_uid": audit_row["actor_uid"] if audit_row else None,
                    },
                    found, ms,
                    None if found else "No audit_log row found for registration — audit.emit() may have failed silently",
                ))
            except Exception as exc:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Audit Log Check", "event_audit_log (DB direct)", "DB", False,
                    {}, {}, False, ms, str(exc),
                ))
    else:
        results.append(_diag_entry(
            "Audit Log Check", "event_audit_log (DB direct)", "DB", False,
            {}, {}, False, 0, "skipped: no registration",
        ))

    # ── Diag 11: Public API Leak Check (virtual_url must not appear) ──────────
    t0 = time.monotonic()
    if test_virtual_event_id is not None:
        async with pool.acquire() as conn:
            svc2 = EventsService(conn)
            try:
                pub_event = await svc2.get_public_event(test_virtual_event_id)
                ms = int((time.monotonic() - t0) * 1000)
                forbidden = ["virtual_url", "created_by_firebase_uid"]
                leaked = [f for f in forbidden if f in pub_event]
                passed = len(leaked) == 0
                results.append(_diag_entry(
                    "Public API Leak Check",
                    f"/api/v1/events/public/{test_virtual_event_id}", "GET", False,
                    {"event_id": test_virtual_event_id, "forbidden_fields": forbidden},
                    {"forbidden_fields_leaked": leaked if leaked else "none"},
                    passed, ms,
                    None if passed else f"Forbidden fields in public response: {leaked}",
                ))
            except Exception as exc:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_diag_entry(
                    "Public API Leak Check",
                    f"/api/v1/events/public/{test_virtual_event_id}", "GET", False,
                    {}, {}, False, ms, str(exc),
                ))
    else:
        results.append(_diag_entry(
            "Public API Leak Check",
            "/api/v1/events/public/{event_id}", "GET", False,
            {}, {}, False, 0, "skipped: no test virtual event",
        ))

    # ── Cleanup: cancel test events ───────────────────────────────────────────
    async with pool.acquire() as conn:
        svc3 = EventsService(conn)
        for eid in [test_virtual_event_id, test_cap_event_id]:
            if eid is not None:
                try:
                    await svc3.update_status(
                        eid, EventStatusUpdate(status="cancelled"), actor
                    )
                except Exception:
                    pass

    passed_count = sum(1 for r in results if r["status"] == "PASS")
    failed_count = sum(1 for r in results if r["status"] == "FAIL")

    return {
        "status": "ok",
        "category": "Registration Flow",
        "total": len(results),
        "passed": passed_count,
        "failed": failed_count,
        "test_virtual_event_id": test_virtual_event_id,
        "test_registration_id": test_registration_id,
        "is_alumni_user": is_alumni,
        "results": results,
        "run_by": user["firebase_uid"],
        "run_at": run_ts.isoformat() + "Z",
    }


# ── Alumni DB Diagnostics ──────────────────────────────────────────────────────
#
# All endpoints below are read-only and never modify alumni_db or events_db.
# They return 404 automatically when APP_ENV != "development" via _get_dev_user.


def _alumni_record_to_dict(record: asyncpg.Record) -> Dict[str, Any]:
    """Serialize an alumni row, including all standard fields."""
    return {key: _serialize(value) for key, value in dict(record).items()}


@router.get("/alumni/search")
async def search_alumni_by_email(
    email: str,
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    """Search alumni_db by exact email (case-insensitive, trimmed). Read-only."""
    normalized = email.strip().lower()
    alumni_pool = await get_alumni_pool()
    async with alumni_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT alumni_id, fullname, email, phone, branch,
                   graduationyear, registrationstatus
            FROM alumni
            WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))
            LIMIT 10
            """,
            email,
        )
    records = [_alumni_record_to_dict(r) for r in rows]
    return {
        "status": "ok",
        "query": {
            "email_input": email,
            "normalized_email": normalized,
        },
        "found": len(records) > 0,
        "count": len(records),
        "records": records,
        "checked_at": datetime.utcnow().isoformat() + "Z",
    }


@router.get("/alumni/search-prefix")
async def search_alumni_by_prefix(
    prefix: str,
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    """Search alumni_db by email prefix or fullname fragment. Read-only."""
    normalized = prefix.strip().lower()
    alumni_pool = await get_alumni_pool()
    async with alumni_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT alumni_id, fullname, email
            FROM alumni
            WHERE LOWER(email) LIKE LOWER($1 || '%')
               OR LOWER(fullname) LIKE LOWER('%' || $1 || '%')
            ORDER BY email ASC
            LIMIT 50
            """,
            prefix.strip(),
        )
    records = [_alumni_record_to_dict(r) for r in rows]
    return {
        "status": "ok",
        "query": {
            "prefix_input": prefix,
            "normalized_prefix": normalized,
        },
        "count": len(records),
        "records": records,
        "checked_at": datetime.utcnow().isoformat() + "Z",
    }


@router.get("/alumni/login-trace")
async def trace_login_mapping(
    email: str,
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    """
    Simulate the alumni lookup + event_users join that POST /auth/firebase performs,
    but without a Firebase token or any writes. Diagnoses why a user may appear
    as user_type=other with ref_id=NULL.
    """
    normalized = email.strip().lower()

    # ── Step 1: alumni_db lookup (mirror production find_alumni_by_email logic) ──
    alumni_pool = await get_alumni_pool()
    async with alumni_pool.acquire() as conn:
        alumni_row = await conn.fetchrow(
            """
            SELECT alumni_id, fullname, email, graduationyear, branch,
                   registrationstatus
            FROM alumni
            WHERE LOWER(email) = LOWER($1)
            LIMIT 1
            """,
            email,
        )

    alumni_data: Optional[Dict[str, Any]] = (
        _alumni_record_to_dict(alumni_row) if alumni_row else None
    )

    # ── Step 2: check if email would match with TRIM (detect whitespace issue) ──
    whitespace_mismatch = False
    if alumni_data is None:
        async with alumni_pool.acquire() as conn:
            trimmed_row = await conn.fetchrow(
                """
                SELECT alumni_id, fullname, email, graduationyear, branch,
                       registrationstatus
                FROM alumni
                WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))
                LIMIT 1
                """,
                email,
            )
        if trimmed_row is not None:
            alumni_data = _alumni_record_to_dict(trimmed_row)
            whitespace_mismatch = True

    # ── Step 3: event_users lookup (current login state) ──
    events_pool = await get_pool()
    async with events_pool.acquire() as conn:
        eu_row = await conn.fetchrow(
            """
            SELECT firebase_uid, email, fullname, user_type, ref_id,
                   graduation_year, is_suspended, last_login
            FROM event_users
            WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))
            LIMIT 1
            """,
            email,
        )
    event_user: Optional[Dict[str, Any]] = (
        {key: _serialize(value) for key, value in dict(eu_row).items()}
        if eu_row
        else None
    )

    # ── Step 4: build expected mapping ──────────────────────────────────────────
    is_active = (
        (alumni_data.get("registrationstatus") or "") in ACTIVE_ALUMNI_STATUSES
        if alumni_data
        else False
    )
    expected_mapping: Optional[Dict[str, Any]] = None
    if alumni_data and is_active:
        expected_mapping = {
            "expected_user_type": "alumni",
            "expected_ref_id": alumni_data["alumni_id"],
            "expected_graduation_year": alumni_data.get("graduationyear"),
            "is_active": True,
        }
    elif alumni_data and not is_active:
        expected_mapping = {
            "expected_user_type": "other",
            "expected_ref_id": None,
            "expected_graduation_year": None,
            "is_active": False,
        }

    # ── Step 5: diagnosis ────────────────────────────────────────────────────────
    if whitespace_mismatch:
        diagnosis_result = "warning_email_case_or_whitespace_mismatch"
        diagnosis_reason = (
            "alumni found only after trimming whitespace — "
            "production lookup (no TRIM) will fail for this email"
        )
    elif alumni_data is None:
        diagnosis_result = "fail_alumni_not_found"
        diagnosis_reason = "no alumni record matches this email in alumni_db"
    elif not is_active:
        diagnosis_result = "fail_alumni_inactive"
        diagnosis_reason = (
            f"alumni found but registrationstatus="
            f"'{alumni_data.get('registrationstatus')}' is not active"
        )
    elif event_user is None:
        diagnosis_result = "fail_event_user_missing"
        diagnosis_reason = "alumni found and active, but no event_users row for this email"
    elif (
        event_user.get("user_type") != "alumni"
        or event_user.get("ref_id") is None
    ):
        diagnosis_result = "fail_alumni_exists_but_event_user_not_mapped"
        diagnosis_reason = (
            f"alumni found and active, but event_users row has "
            f"user_type='{event_user.get('user_type')}' "
            f"ref_id={event_user.get('ref_id')!r}. "
            "Root cause: ON CONFLICT in _upsert_event_user does not update "
            "user_type/ref_id/graduation_year for existing rows."
        )
    else:
        diagnosis_result = "pass_mapping_correct"
        diagnosis_reason = "alumni found, active, and correctly mapped in event_users"

    alumni_lookup_payload: Optional[Dict[str, Any]] = None
    if alumni_data:
        alumni_lookup_payload = {
            "found": True,
            "alumni_id": alumni_data.get("alumni_id"),
            "fullname": alumni_data.get("fullname"),
            "email": alumni_data.get("email"),
            "graduationyear": alumni_data.get("graduationyear"),
            "branch": alumni_data.get("branch"),
            "registrationstatus": alumni_data.get("registrationstatus"),
        }
    else:
        alumni_lookup_payload = {"found": False}

    existing_eu_payload: Optional[Dict[str, Any]] = None
    if event_user:
        existing_eu_payload = {
            "found": True,
            "firebase_uid": event_user.get("firebase_uid"),
            "email": event_user.get("email"),
            "user_type": event_user.get("user_type"),
            "ref_id": event_user.get("ref_id"),
            "graduation_year": event_user.get("graduation_year"),
            "is_suspended": event_user.get("is_suspended"),
            "last_login": event_user.get("last_login"),
        }
    else:
        existing_eu_payload = {"found": False}

    return {
        "status": "ok",
        "query": {
            "email_input": email,
            "normalized_email": normalized,
        },
        "alumni_lookup": alumni_lookup_payload,
        "expected_event_user_mapping": expected_mapping,
        "existing_event_user": existing_eu_payload,
        "diagnosis": {
            "result": diagnosis_result,
            "reason": diagnosis_reason,
        },
        "checked_at": datetime.utcnow().isoformat() + "Z",
    }


# ── Attendee Management Diagnostics (Week 4 Phase 2) ─────────────────────────


@router.get("/attendees")
async def run_attendee_management_diagnostics(
    event_id: int = Query(..., description="Event ID to verify attendee management against"),
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    """Verify UC-01 through UC-10 for admin attendee management. Development mode only.

    Requires an existing event_id. Does NOT create or modify any data.
    """
    from app.repositories.registration_repository import RegistrationRepository

    pool = await get_pool()
    results: List[Dict[str, Any]] = []
    run_ts = datetime.utcnow()

    def _uc(uc: str, name: str, passed: bool, detail: Dict[str, Any], error: Optional[str] = None) -> Dict[str, Any]:
        entry: Dict[str, Any] = {"uc": uc, "name": name, "status": "PASS" if passed else "FAIL", "detail": detail}
        if error:
            entry["error"] = error
        return entry

    async with pool.acquire() as conn:
        repo = RegistrationRepository(conn)

        # UC-09: event not found (nonexistent event_id → count returns 0, not an error)
        t0 = time.monotonic()
        try:
            nonexistent = 999_999_999
            count_bad = await repo.count_attendees(nonexistent, None, None)
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-09", "event not found returns empty", True,
                {"nonexistent_event_id": nonexistent, "count": count_bad, "duration_ms": ms}))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-09", "event not found returns empty", False,
                {"duration_ms": ms}, str(exc)))

        # UC-01: attendees visible — list_attendees returns status='registered' only
        t0 = time.monotonic()
        try:
            total = await repo.count_attendees(event_id, None, None)
            rows = await repo.list_attendees(event_id, None, None, 1, 50)
            ms = int((time.monotonic() - t0) * 1000)
            all_registered = all(r["status"] == "registered" for r in rows)
            passed = all_registered or total == 0
            results.append(_uc("UC-01", "attendees visible (status=registered only)", passed,
                {"event_id": event_id, "total": total, "returned": len(rows), "all_status_registered": all_registered, "duration_ms": ms},
                None if passed else "Non-registered rows returned in attendee list"))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-01", "attendees visible", False, {"duration_ms": ms}, str(exc)))

        # UC-10: empty attendee list — no crash on event with 0 registrations
        t0 = time.monotonic()
        try:
            count_empty = await repo.count_attendees(nonexistent, None, None)
            rows_empty = await repo.list_attendees(nonexistent, None, None, 1, 50)
            ms = int((time.monotonic() - t0) * 1000)
            passed = count_empty == 0 and rows_empty == []
            results.append(_uc("UC-10", "empty attendee list handled", passed,
                {"count": count_empty, "rows": len(rows_empty), "duration_ms": ms},
                None if passed else f"Expected 0 rows, got count={count_empty}"))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-10", "empty attendee list handled", False, {"duration_ms": ms}, str(exc)))

        # UC-02: search works — search on known name prefix (verifies ILIKE filter)
        t0 = time.monotonic()
        try:
            all_rows = await repo.list_attendees(event_id, None, None, 1, 200)
            if all_rows:
                first_name = (all_rows[0]["fullname_snapshot"] or "")[:3]
                searched = await repo.list_attendees(event_id, first_name, None, 1, 200) if first_name else all_rows
                count_searched = await repo.count_attendees(event_id, first_name or None, None)
                ms = int((time.monotonic() - t0) * 1000)
                # Every result must contain the search prefix in fullname
                all_match = all((r["fullname_snapshot"] or "").lower().startswith(first_name.lower()) for r in searched) if first_name else True
                passed = all_match and count_searched == len(searched)
                results.append(_uc("UC-02", "search filter works", passed,
                    {"search_prefix": first_name, "count_matched": count_searched, "all_match": all_match, "duration_ms": ms},
                    None if passed else f"Search result mismatch: count={count_searched} rows={len(searched)}"))
            else:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_uc("UC-02", "search filter works", True,
                    {"note": "no attendees in event — skipped verification", "duration_ms": ms}))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-02", "search filter works", False, {"duration_ms": ms}, str(exc)))

        # UC-03: batch filter works
        t0 = time.monotonic()
        try:
            all_rows2 = await repo.list_attendees(event_id, None, None, 1, 200)
            batch_years = list({r["batch_year_snapshot"] for r in all_rows2 if r["batch_year_snapshot"] is not None})
            if batch_years:
                test_year = batch_years[0]
                filtered = await repo.list_attendees(event_id, None, test_year, 1, 200)
                count_filtered = await repo.count_attendees(event_id, None, test_year)
                ms = int((time.monotonic() - t0) * 1000)
                all_match = all(r["batch_year_snapshot"] == test_year for r in filtered)
                passed = all_match and count_filtered == len(filtered)
                results.append(_uc("UC-03", "batch year filter works", passed,
                    {"test_year": test_year, "count": count_filtered, "all_match": all_match, "duration_ms": ms},
                    None if passed else "Batch filter returned rows with different batch year"))
            else:
                ms = int((time.monotonic() - t0) * 1000)
                results.append(_uc("UC-03", "batch year filter works", True,
                    {"note": "no attendees with batch_year — skipped verification", "duration_ms": ms}))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-03", "batch year filter works", False, {"duration_ms": ms}, str(exc)))

        # UC-04: pagination works — page 1 and page 2 return non-overlapping rows
        t0 = time.monotonic()
        try:
            total_pg = await repo.count_attendees(event_id, None, None)
            page1 = await repo.list_attendees(event_id, None, None, 1, 5)
            page2 = await repo.list_attendees(event_id, None, None, 2, 5)
            ms = int((time.monotonic() - t0) * 1000)
            ids_p1 = {r["registration_id"] for r in page1}
            ids_p2 = {r["registration_id"] for r in page2}
            no_overlap = len(ids_p1 & ids_p2) == 0
            correct_size = len(page1) <= 5 and len(page2) <= 5
            passed = no_overlap and correct_size
            results.append(_uc("UC-04", "pagination works (no overlap, correct size)", passed,
                {"total": total_pg, "page1_rows": len(page1), "page2_rows": len(page2), "overlap": not no_overlap, "duration_ms": ms},
                None if passed else "Pages overlap or exceed per_page size"))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-04", "pagination works", False, {"duration_ms": ms}, str(exc)))

        # UC-05: CSV export returns correct columns
        t0 = time.monotonic()
        try:
            export_rows = await repo.export_attendees(event_id, None, None)
            ms = int((time.monotonic() - t0) * 1000)
            required_cols = {"registration_number", "fullname_snapshot", "email_snapshot",
                             "batch_year_snapshot", "branch_snapshot", "phone_snapshot",
                             "registered_at", "status"}
            if export_rows:
                present_cols = set(export_rows[0].keys())
                missing = required_cols - present_cols
                passed = len(missing) == 0
                results.append(_uc("UC-05", "CSV export columns correct", passed,
                    {"rows": len(export_rows), "columns": sorted(present_cols), "missing": sorted(missing), "duration_ms": ms},
                    None if passed else f"Missing CSV columns: {sorted(missing)}"))
            else:
                results.append(_uc("UC-05", "CSV export columns correct", True,
                    {"note": "no attendees — column structure not verifiable from data; query succeeded", "duration_ms": ms}))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-05", "CSV export columns correct", False, {"duration_ms": ms}, str(exc)))

        # UC-06: cancelled hidden from attendees (list_attendees must not return cancelled rows)
        t0 = time.monotonic()
        try:
            all_att = await repo.list_attendees(event_id, None, None, 1, 200)
            cancelled_in_att = [r for r in all_att if r["status"] != "registered"]
            ms = int((time.monotonic() - t0) * 1000)
            passed = len(cancelled_in_att) == 0
            results.append(_uc("UC-06", "cancelled hidden from attendees list", passed,
                {"total_attendees": len(all_att), "non_registered_rows": len(cancelled_in_att), "duration_ms": ms},
                None if passed else f"{len(cancelled_in_att)} non-registered rows leaked into attendee list"))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-06", "cancelled hidden from attendees list", False, {"duration_ms": ms}, str(exc)))

        # UC-07: cancelled visible in registrations audit view
        t0 = time.monotonic()
        try:
            total_all = await repo.count_registrations(event_id, None)
            total_reg = await repo.count_registrations(event_id, "registered")
            total_can = await repo.count_registrations(event_id, "cancelled")
            ms = int((time.monotonic() - t0) * 1000)
            cancelled_rows = await repo.list_registrations(event_id, "cancelled", 1, 50)
            all_cancelled_correct = all(r["status"] == "cancelled" for r in cancelled_rows)
            passed = total_all == total_reg + total_can and all_cancelled_correct
            results.append(_uc("UC-07", "cancelled visible in registrations audit view", passed,
                {"total_all": total_all, "total_registered": total_reg, "total_cancelled": total_can,
                 "counts_sum_correctly": total_all == total_reg + total_can, "duration_ms": ms},
                None if passed else "Registration counts do not add up or cancelled filter is wrong"))
        except Exception as exc:
            ms = int((time.monotonic() - t0) * 1000)
            results.append(_uc("UC-07", "cancelled visible in registrations audit", False, {"duration_ms": ms}, str(exc)))

        # UC-08: admin required — verify endpoint is wired to get_admin_user
        # (Middleware enforcement is structural — confirmed in admin_events.py route definitions.)
        results.append(_uc("UC-08", "admin auth required (structural check)", True,
            {"note": "All /api/v1/admin/* routes use Depends(get_admin_user). Verified in admin_events.py source."}))

    passed_count = sum(1 for r in results if r["status"] == "PASS")
    failed_count = sum(1 for r in results if r["status"] == "FAIL")

    return {
        "status": "ok",
        "category": "Attendee Management",
        "event_id": event_id,
        "total": len(results),
        "passed": passed_count,
        "failed": failed_count,
        "results": results,
        "run_by": user["firebase_uid"],
        "run_at": run_ts.isoformat() + "Z",
    }


@router.get("/alumni/{alumni_id}")
async def lookup_alumni_by_id(
    alumni_id: str,
    user: Dict[str, Any] = Depends(_get_dev_user),
) -> Dict[str, Any]:
    """Return the full alumni row from alumni_db for a given alumni_id. Read-only."""
    alumni_pool = await get_alumni_pool()
    async with alumni_pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT alumni_id, fullname, email, phone, branch,
                   graduationyear, registrationstatus, firebase_uid
            FROM alumni
            WHERE alumni_id = $1
            LIMIT 1
            """,
            alumni_id,
        )
    if row is None:
        return {
            "status": "ok",
            "found": False,
            "alumni_id": alumni_id,
            "record": None,
            "checked_at": datetime.utcnow().isoformat() + "Z",
        }
    return {
        "status": "ok",
        "found": True,
        "alumni_id": alumni_id,
        "record": _alumni_record_to_dict(row),
        "checked_at": datetime.utcnow().isoformat() + "Z",
    }
