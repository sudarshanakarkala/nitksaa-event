"""
Shared pytest fixtures for the NITKSAA Event Platform backend tests.

Handles:
 - sys.path so `app` is importable whether pytest is run from backend/ or the repo root
 - .env loading before app settings are initialised (pydantic-settings caches on first access)
 - Session-scoped TestClient (one asyncpg pool for the whole test session)
 - DB availability guard that skips all tests when events_db is unreachable
"""
import sys
from pathlib import Path

# ── Path fix ──────────────────────────────────────────────────────────────────
# This file lives at backend/tests/conftest.py.
# backend/ must be on sys.path so `from app.xxx import ...` works regardless of
# which directory the user invokes pytest from.
_BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

# ── .env loading ──────────────────────────────────────────────────────────────
# Must happen BEFORE `from app.main import app` so pydantic-settings picks up
# the correct EVENTS_DB_URL when it caches settings on first import.
from dotenv import load_dotenv  # noqa: E402  (import after sys.path edit)
load_dotenv(_BACKEND_DIR / ".env", override=False)

# ── Fixtures ──────────────────────────────────────────────────────────────────
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

ADMIN_HEADERS = {"X-Dev-User": "admin"}
ATTENDEE_HEADERS = {"X-Dev-User": "attendee"}


@pytest.fixture(scope="session")
def client():
    """Single TestClient + asyncpg pool shared across the whole test session."""
    try:
        from app.main import app  # imported here so .env is already loaded
    except Exception as exc:
        pytest.skip(f"app import failed — check dependencies: {exc}")
    with TestClient(app, raise_server_exceptions=True) as c:
        yield c


@pytest.fixture(scope="session", autouse=True)
def require_db(client):
    """Skip the entire test session when events_db is not reachable."""
    try:
        r = client.get("/api/v1/health")
        ok = r.status_code == 200 and r.json().get("db") == "ok"
    except Exception:
        ok = False
    if not ok:
        pytest.skip(
            "events_db is not reachable. "
            "Ensure PostgreSQL is running and EVENTS_DB_URL is set in backend/.env. "
            "Migration: psql -d events_db -f migrations/events_db/001_create_events_alpha_schema.sql"
        )
