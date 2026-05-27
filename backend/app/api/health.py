from fastapi import APIRouter, Depends
from app.database import get_pool
from app.config import get_settings

router = APIRouter(tags=["health"])


@router.get("/healthz")
async def root_health():
    return {"status": "ok", "service": get_settings().app_name}


@router.get("/api/v1/health")
async def api_health():
    pool = await get_pool()
    try:
        async with pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        db_status = "ok"
    except Exception as e:
        db_status = f"error: {str(e)}"

    return {
        "status": "ok",
        "version": get_settings().app_version,
        "env": get_settings().app_env,
        "db": db_status,
    }
