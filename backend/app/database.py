import asyncpg
from typing import Optional
from app.config import get_settings

_pool: Optional[asyncpg.Pool] = None
_alumni_pool: Optional[asyncpg.Pool] = None


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        settings = get_settings()
        _pool = await asyncpg.create_pool(
            dsn=settings.events_db_dsn,
            min_size=2,
            max_size=10,
        )
    return _pool


async def get_alumni_pool() -> asyncpg.Pool:
    global _alumni_pool
    if _alumni_pool is None:
        settings = get_settings()
        _alumni_pool = await asyncpg.create_pool(
            dsn=settings.alumni_db_dsn,
            min_size=1,
            max_size=5,
        )
    return _alumni_pool


async def close_pool() -> None:
    global _pool, _alumni_pool
    if _pool is not None:
        await _pool.close()
        _pool = None
    if _alumni_pool is not None:
        await _alumni_pool.close()
        _alumni_pool = None
