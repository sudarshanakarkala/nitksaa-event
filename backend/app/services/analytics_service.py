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
            # set_type_codec registers on the physical connection, not just
            # this acquire() — on a pooled connection that persists for the
            # connection's whole lifetime and silently changes how EVERY
            # future caller that reuses it sees jsonb columns (e.g.
            # payment_service.get_timeline's json.loads(row["context"])
            # would crash on an already-decoded dict). Pass a pre-serialized
            # string with an explicit cast instead — the same pattern
            # audit_service.emit already uses safely — so no per-connection
            # state is mutated.
            await conn.execute(
                """
                INSERT INTO event_activity_log
                    (event_id, firebase_uid, action_type, source_app, metadata)
                VALUES ($1, $2, $3, $4, $5::jsonb)
                """,
                event_id,
                firebase_uid,
                action_type,
                source_app,
                json.dumps(metadata or {}),
            )
    except Exception as exc:
        logger.warning("analytics_log_failed action=%s error=%s", action_type, exc)
