"""Audit log adapter for event_audit_log.

emit() inserts one row into event_audit_log. It must never raise — any failure
is logged with the [audit] prefix and swallowed so callers are unaffected.

Security: never pass firebase_uid, email, phone, join URLs, or tokens into context.
"""
import json
import logging
from typing import Any, Dict, Optional

from app.database import get_pool

_log = logging.getLogger(__name__)


async def emit(
    actor_uid: str,
    event_type: str,
    entity_type: str,
    entity_id: int,
    context: Optional[Dict[str, Any]] = None,
) -> None:
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO event_audit_log
                    (actor_uid, event_type, entity_type, entity_id, context)
                VALUES ($1, $2, $3, $4, $5::jsonb)
                """,
                actor_uid,
                event_type,
                entity_type,
                entity_id,
                json.dumps(context) if context is not None else None,
            )
    except Exception as exc:
        _log.error(
            "[audit] emit failed actor=%s type=%s entity=%s/%s: %s",
            actor_uid, event_type, entity_type, entity_id, exc,
        )
