"""Development-only diagnostics endpoints for auth and read-only DB validation."""
from __future__ import annotations

from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional
from uuid import UUID

import time
import asyncpg
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.database import get_pool
from app.middleware.auth import decode_access_token

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
) -> Dict[str, Any]:
    _require_development()
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
