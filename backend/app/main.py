from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.config import get_settings
from app.database import get_pool, close_pool
from app.api import health, events, admin_events, auth, dev_diagnostics


@asynccontextmanager
async def lifespan(app: FastAPI):
    await get_pool()
    yield
    await close_pool()


settings = get_settings()

app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

app.include_router(health.router)
app.include_router(events.router)
app.include_router(admin_events.router)
app.include_router(auth.router)
app.include_router(dev_diagnostics.router)
