"""
Database connection pools.

Two pools — one per database — initialised on first use and cached
for the lifetime of the process.

    get_db()        → website_db  (platform features, user registry)
    get_alumni_db() → alumni_db   (alumni identity, source of truth — read-only)
"""

from __future__ import annotations

from contextlib import contextmanager

import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor

from config.settings import settings

_website_pool: pool.ThreadedConnectionPool | None = None
_alumni_pool:  pool.ThreadedConnectionPool | None = None


def _get_website_pool() -> pool.ThreadedConnectionPool:
    global _website_pool
    if _website_pool is None:
        _website_pool = pool.ThreadedConnectionPool(1, 10, dsn=settings.db_url)
    return _website_pool


def _get_alumni_pool() -> pool.ThreadedConnectionPool:
    global _alumni_pool
    if _alumni_pool is None:
        _alumni_pool = pool.ThreadedConnectionPool(1, 10, dsn=settings.alumni_db_url)
    return _alumni_pool


@contextmanager
def get_db():
    """
    Context manager yielding a RealDictCursor for website_db.
    Commits on success, rolls back on error.
    """
    p = _get_website_pool()
    conn = p.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        p.putconn(conn)


@contextmanager
def get_alumni_db():
    """
    Context manager yielding a RealDictCursor for alumni_db.
    Read-only by convention — never run INSERT/UPDATE/DELETE against alumni_db
    from this application except for the firebase_uid backfill in auth.py.
    """
    p = _get_alumni_pool()
    conn = p.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        p.putconn(conn)
