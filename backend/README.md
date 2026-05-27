# NITKSAA Event Platform — Backend (Alpha)

FastAPI + PostgreSQL backend for the NITKSAA Event Platform.  
This is a backend-only Alpha validation slice. No Flutter or React UI is included.

---

## Stack

| Layer | Technology |
|-------|-----------|
| API | FastAPI 0.111, Python 3.11+ |
| Database | PostgreSQL 14+ (`events_db`) |
| DB Driver | asyncpg (async) |
| Validation | Pydantic v2 |
| Auth (Alpha) | Dev placeholder via `X-Dev-User` header |
| Tests | pytest + FastAPI TestClient |

---

## Environment Variables

Copy `.env.example` to `.env` and edit:

```
APP_ENV=development
APP_NAME=NITKSAA Event API
APP_VERSION=0.1.0-alpha
EVENTS_DB_URL=postgresql://postgres:postgres@localhost:5432/events_db
```

> `APP_ENV=development` is required for dev auth to work.

---

## Setup

```bash
# 1. Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate        # macOS/Linux
# .venv\Scripts\activate         # Windows

# 2. Install dependencies
pip install -r requirements.txt

# 3. Copy env file
cp .env.example .env
# Edit .env with your PostgreSQL credentials

# 4. Create events_db database
createdb events_db
# or: psql -c "CREATE DATABASE events_db;"

# 5. Run migration
psql -d events_db -f migrations/events_db/001_create_events_alpha_schema.sql
```

---

## Run Server

```bash
# From the backend/ directory
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API docs: http://localhost:8000/docs  
ReDoc: http://localhost:8000/redoc

---

## DB Migration

```bash
psql -d events_db -f migrations/events_db/001_create_events_alpha_schema.sql
```

Tables created: `events`, `sessions`, `registrations`, `attendees`, `check_ins`, `check_in_attempts`

---

## Running Tests

```bash
# From backend/ directory, with events_db running
pytest tests/test_event_flow.py -v
```

Tests auto-skip if the database is unavailable.

---

## Dev Auth

This Alpha uses a header-based auth placeholder (only when `APP_ENV=development`):

| Header value | Role | is_admin |
|---|---|---|
| `X-Dev-User: admin` | Admin | true |
| `X-Dev-User: attendee` | Attendee | false |

---

## curl Test Flow

See [`scripts/event_flow_curl_examples.md`](scripts/event_flow_curl_examples.md) for the full 20-step test guide.

Quick smoke test:
```bash
curl http://localhost:8000/healthz
curl http://localhost:8000/api/v1/health
```

---

## What Was Built (Alpha Scope)

- Health endpoints (`/healthz`, `/api/v1/health`)
- `events_db` schema migration (6 tables, 11 indexes)
- Dev auth placeholder middleware
- QR token generation (`nitksaa_evt_` prefix, 256-bit entropy)
- Event CRUD (create, update, publish, close)
- Session management
- Public event listing & detail
- Attendee registration with duplicate prevention
- QR token verification
- QR check-in with duplicate prevention
- Check-in attempt audit logging (success/duplicate/invalid/unauthorized)
- Full curl/Postman guide
- pytest test suite (12 test cases)

---

## What Is Deferred

- Production Firebase JWT verification
- Flutter UI
- React Admin UI
- Payments
- Waitlist
- Email notifications
- Push notifications
- QR code image generation
- Offline sync
- Analytics
- Production QR token hashing (HMAC-SHA256)
- Cross-database queries to alumni_db
- Superadmin / portal staff roles
