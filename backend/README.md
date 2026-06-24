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
ALUMNI_DB_URL=postgresql://postgres:postgres@localhost:5432/alumni_db
EMAIL_MODE=log
```

> `APP_ENV=development` is required for dev auth to work.

See `.env.example` for the full list of variables including email SMTP settings.

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

# 4. Create both databases
createdb events_db
createdb alumni_db
# or: psql -c "CREATE DATABASE events_db;" && psql -c "CREATE DATABASE alumni_db;"

# 5. Run migrations (run all in order)
psql -d events_db -f migrations/events_db/001_create_events_alpha_schema.sql
# ... through the latest migration file
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

## alumni_db Local Setup

The backend connects to two PostgreSQL databases:

| Database | Purpose |
|---|---|
| `events_db` | Primary database — all events, registrations, sessions |
| `alumni_db` | Read-only alumni eligibility lookups (from nitksaa-portal-v2) |

`alumni_db` does not exist by default. Alumni eligibility calls gracefully skip the lookup
when `alumni_db` is unreachable, so the backend runs without it for most development tasks.

**To run eligibility checks locally:**

```bash
# Create an empty alumni_db
createdb alumni_db

# Apply the portal schema (obtain from nitksaa-portal-v2/migrations/)
# or run a minimal seed for testing:
psql -d alumni_db -c "
  CREATE TABLE IF NOT EXISTS alumni_profiles (
    ref_id      VARCHAR(128) PRIMARY KEY,
    firebase_uid VARCHAR(128),
    email       TEXT,
    batch_year  INT,
    is_verified BOOLEAN DEFAULT false
  );
  INSERT INTO alumni_profiles VALUES
    ('TEST-001', 'dev-uid-admin', 'admin@test.com', 2010, true),
    ('TEST-002', 'dev-uid-user',  'user@test.com',  2015, true);
"
```

**Staging:** Point `ALUMNI_DB_URL` to the portal's staging database for realistic eligibility
checks. Do not use the production alumni_db URL in local development.

---

## Email Setup

Email sending is disabled by default (`EMAIL_MODE=log`). In log mode, emails are written to the
Python logger and the registration flow completes normally.

**To enable real email delivery:**

```env
EMAIL_MODE=send
SMTP_USER=nitksaa.events@gmail.com
SMTP_PASSWORD=your-gmail-app-password   # Gmail App Password, not the account password
EMAIL_FROM=nitksaa.events@gmail.com
EMAIL_REPLY_TO=events@nitksaa.org
```

Use a Gmail App Password (generated at myaccount.google.com → Security → App passwords), not
the account password. Two-factor authentication must be enabled on the Gmail account.

Test the configuration with `EMAIL_MODE=send` against a test event registration before using
in production.

---

## What Is Deferred

- Production Firebase JWT verification
- Flutter UI
- React Admin UI
- Payments
- Waitlist
- Push notifications
- QR code image generation
- Offline sync
- Analytics
- Production QR token hashing (HMAC-SHA256)
- Full cross-database alumni_db schema (portal team owns the schema)
- Superadmin / portal staff roles
