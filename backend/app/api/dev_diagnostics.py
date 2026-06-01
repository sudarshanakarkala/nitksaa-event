"""Development-only diagnostics endpoints for auth and read-only DB validation."""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, List
from uuid import UUID

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
