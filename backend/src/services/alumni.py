"""
Alumni identity cache service.

Provides fetch_alumni_info() — a cached batch lookup of alumni name,
graduation year, and branch from alumni_db.

Used by: mentorship.py, career.py
Future: when the Alumni Service is built, this module is the single
cut-over point — update fetch_alumni_info() to call the service API
instead of alumni_db directly.
"""

from __future__ import annotations

from cachetools import TTLCache

from services.db import get_alumni_db

# ---------------------------------------------------------------------------
# Cache
# Keyed by firebase_uid. Each entry holds fullname/graduationyear/branch.
# TTL is 30 minutes — these fields are admin-controlled and change rarely.
# Capped at 5,000 entries to prevent unbounded memory growth in long-running
# Cloud Run instances. TTLCache handles expiry automatically; no manual _ts
# tracking needed.
# ---------------------------------------------------------------------------
_ALUMNI_CACHE: TTLCache = TTLCache(maxsize=5_000, ttl=1800)


def fetch_alumni_info(firebase_uids: list[str]) -> dict[str, dict]:
    """
    Fetches name, graduation year, and branch from alumni_db for a list of
    firebase_uids. Returns a dict keyed by firebase_uid.

    Cross-db note: no SQL joins across databases — query website_db first,
    then call this function with the collected uids, merge in Python.

    Results are cached per firebase_uid for 30 minutes via TTLCache
    (maxsize=5,000). Cache is per-process (Cloud Run may run multiple
    instances — acceptable, each warms independently).
    """
    if not firebase_uids:
        return {}

    result: dict[str, dict] = {}
    missing: list[str] = []

    for uid in firebase_uids:
        entry = _ALUMNI_CACHE.get(uid)
        if entry is not None:
            result[uid] = entry
        else:
            missing.append(uid)

    if missing:
        with get_alumni_db() as cur:
            cur.execute(
                """
                SELECT firebase_uid, alumni_id, fullname, graduationyear, branch
                FROM   alumni
                WHERE  firebase_uid = ANY(%s)
                  AND  directory_visible = true
                """,
                [missing],
            )
            for row in cur.fetchall():
                entry = {
                    "alumni_id":      row["alumni_id"],
                    "fullname":       row["fullname"],
                    "graduationyear": row["graduationyear"],
                    "branch":         row["branch"],
                }
                _ALUMNI_CACHE[row["firebase_uid"]] = entry
                result[row["firebase_uid"]] = entry

    return result
