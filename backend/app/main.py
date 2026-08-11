from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import get_settings
from app.database import get_pool, close_pool
from app.api import (
    health, events, admin_events, auth, dev_diagnostics, alumni, registrations,
    people, sponsors_partners, week5_diagnostics, payments,
)


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

_cors_kwargs: dict = {
    "allow_origins": settings.origins_list,
    "allow_credentials": True,
    "allow_methods": ["*"],
    "allow_headers": ["*"],
}
if settings.app_env == "development":
    # Flutter Web uses a dynamic port during local development.
    _cors_kwargs["allow_origin_regex"] = (
        r"^http://(localhost|127\.0\.0\.1):\d+$"
    )

app.add_middleware(CORSMiddleware, **_cors_kwargs)

app.include_router(health.router)
app.include_router(events.router)
app.include_router(admin_events.router)
app.include_router(auth.router)
app.include_router(dev_diagnostics.router)
app.include_router(week5_diagnostics.router)
app.include_router(alumni.router)
app.include_router(registrations.router)
app.include_router(people.router)
app.include_router(sponsors_partners.router)
app.include_router(payments.router)
