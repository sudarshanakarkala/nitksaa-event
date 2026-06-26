"""Analytics logging service.

Fire-and-forget: log_event_activity never raises — a failed write is silently
swallowed so analytics never block or break the critical path.
"""
import json
import logging
from typing import Any, Dict, Optional

from app.database import get_pool

logger = logging.getLogger(__name__)


async def log_event_activity(
    action_type: str,
    source_app: str = "BACKEND",
    event_id: Optional[int] = None,
    firebase_uid: Optional[str] = None,
    metadata: Optional[Dict[str, Any]] = None,
) -> None:
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            # asyncpg requires a registered codec to pass dicts for JSONB columns.
            # Registering it per-connection is the idiomatic approach when no global
            # codec is set up in the connection pool initialiser.
            await conn.set_type_codec(
                "jsonb",
                encoder=json.dumps,
                decoder=json.loads,
                schema="pg_catalog",
                format="text",
            )
            await conn.execute(
                """
                INSERT INTO event_activity_log
                    (event_id, firebase_uid, action_type, source_app, metadata)
                VALUES ($1, $2, $3, $4, $5)
                """,
                event_id,
                firebase_uid,
                action_type,
                source_app,
                metadata or {},
            )
    except Exception as exc:
        logger.warning("analytics_log_failed action=%s error=%s", action_type, exc)
