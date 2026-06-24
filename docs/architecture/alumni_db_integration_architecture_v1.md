# Alumni DB Integration Architecture v1

**Date:** 2026-06-24
**Status:** Authoritative
**Scope:** How `nitksaa-event` reads from `alumni_db` owned by `nitksaa-portal-v2`

---

## Purpose

`alumni_db` is the single source of truth for NITK alumni identity records. The `nitksaa-event`
backend reads alumni data from it to:

1. Verify alumni eligibility before allowing event registration
2. Snapshot alumni profile data (name, email, phone, batch year, branch) at registration time
3. Show the alumni their own profile on the Register screen

`nitksaa-event` is a **read-only consumer** of `alumni_db`. It never writes to it.

---

## Repository Relationships

```
nitksaa-portal-v2          ← OWNER of alumni_db
    │                         Manages: alumni records, batch years,
    │                         department, registration status, membership
    │
    ▼
nitksaa-event              ← READ-ONLY consumer
    │                         Reads: fullname, email, phone, graduationyear,
    │                         branch, registrationstatus
    │
    ▼
nitksaa-website            ← Future consumer (not yet integrated)
```

---

## Data Ownership

| Data | Owner | Notes |
|---|---|---|
| Alumni profile (name, email, phone) | `nitksaa-portal-v2` | `alumni_db.alumni` table |
| Batch year / graduation year | `nitksaa-portal-v2` | `alumni_db.alumni.graduationyear` |
| Department / branch | `nitksaa-portal-v2` | `alumni_db.alumni.branch` |
| Active status | `nitksaa-portal-v2` | `alumni_db.alumni.registrationstatus` |
| Event registrations | `nitksaa-event` | `events_db.registrations` |
| Snapshot fields on registrations | `nitksaa-event` | Copied from alumni_db at registration time |

**Rule:** `nitksaa-event` never modifies alumni records. If alumni data is wrong (wrong name,
inactive status incorrectly set), the fix must be made in `nitksaa-portal-v2`.

---

## Active Status Definition

`is_active = true` when `alumni_db.alumni.registrationstatus` is one of:

- `'Active'`
- `'Self-Verified'`

All other values (including `null`, `'Pending'`, `'Inactive'`, etc.) result in `is_active = false`.

Only active alumni can register for events.

---

## Registration Flow

```
User opens app
    │
    ▼
Firebase Login
    │
    ▼
POST /api/v1/auth/firebase
    │   Exchanges Firebase ID token for backend JWT
    │   Calls find_alumni_by_email(email) → alumni_db
    │   If found: user_type = 'alumni', ref_id = alumni_id
    │   If not found: user_type = 'other', ref_id = null
    │
    ▼
GET /api/v1/alumni/me
    │   Fetches full alumni profile from alumni_db using ref_id
    │   Returns: fullname, email, phone, batch_year, branch, is_active
    │
    ▼
Eligibility check (implicit in register endpoint)
    │   alumni_not_found → 403 alumni_not_found
    │   is_active == false → 403 alumni_not_active
    │   All ok → proceed
    │
    ▼
POST /api/v1/events/{id}/register
    │   Snapshots alumni profile fields into registrations table:
    │     fullname_snapshot, email_snapshot, phone_snapshot,
    │     batch_year_snapshot, branch_snapshot
    │
    ▼
Registration confirmed
    Snapshot is permanent — changes to alumni profile do not affect it
```

---

## Database Connection

### Configuration

`alumni_db` connection is configured via `ALUMNI_DB_URL` in `.env`:

```env
ALUMNI_DB_URL=postgresql://user:password@host:5432/alumni_db
```

This is separate from `DATABASE_URL` (the `events_db`).

```python
# backend/app/config.py
class Settings(BaseModel):
    database_url: str           # events_db — event_users, events, registrations
    alumni_db_url: Optional[str] = None  # alumni_db — alumni profiles
```

If `ALUMNI_DB_URL` is not set, `GET /api/v1/alumni/me` returns a 503 error.

### Connection Pool

Two separate asyncpg connection pools:

- `get_pool()` → `events_db`
- `get_alumni_pool()` → `alumni_db`

The alumni pool is initialised lazily on first use.

---

## Local Development

### Setup

`alumni_db` does not exist by default on local machines. It must be created manually:

```bash
createdb alumni_db
```

### Seed

A minimal seed is required for local development. Minimum fields:

```sql
CREATE TABLE IF NOT EXISTS alumni (
    alumni_id        TEXT PRIMARY KEY,
    fullname         TEXT,
    email            TEXT UNIQUE,
    phone            TEXT,
    graduationyear   INT,
    branch           TEXT,
    registrationstatus TEXT
);

INSERT INTO alumni VALUES (
    'NITK2026IT001', 'Dev User', 'dev@example.com',
    '+919999999999', 2026, 'Information Technology', 'Active'
);
```

### Limitations

- Local seed data does not match production alumni records
- Testing alumni lookup failures requires intentionally using an email not in the seed
- Inactive alumni testing requires a seed record with `registrationstatus = 'Inactive'`

---

## Staging

The staging environment should point to a staging copy of `alumni_db` maintained by
`nitksaa-portal-v2`. The staging `alumni_db` should contain a set of test alumni records
that mirror production schema without using real personal data.

`ALUMNI_DB_URL` in the staging `.env` should point to:

```
postgresql://user:password@staging-host:5432/alumni_db
```

SSL should be enabled for staging and production connections:

```
postgresql://user:password@host:5432/alumni_db?sslmode=require
```

---

## Production

- `alumni_db` is owned and managed by `nitksaa-portal-v2`
- `nitksaa-event` connects with a **read-only database user**
- SSL required: `?sslmode=require` or `sslmode=verify-full`
- `nitksaa-event` should never be given write permissions on `alumni_db`
- Connection credentials must be rotated if compromised — update only in `nitksaa-event` backend `.env`

---

## Known Risks

| Risk | Mitigation |
|---|---|
| Local seed != production data | Integration tests that depend on specific alumni records may fail in production |
| Alumni profile changes after registration | Snapshot fields are immutable — the registration record always shows data at time of registration |
| `ALUMNI_DB_URL` not set in deployment | `GET /alumni/me` returns 503; registration is blocked; backend startup should log a warning |
| Production alumni_db connection not SSL-verified | Validate `sslmode=require` is set before production deployment |
| Alumni account marked inactive after registration | Registration is not cancelled automatically — the registered state persists; only new registrations are blocked |

---

## Verification Checklist

### Before Production Deployment

| Check | How to verify |
|---|---|
| `ALUMNI_DB_URL` is set | `cat .env | grep ALUMNI_DB_URL` |
| SSL mode configured | URL contains `sslmode=require` |
| Connection succeeds | `GET /api/v1/dev/diagnostics/alumni/search?email=test@example.com` returns 200 |
| Existing alumni lookup | `GET /api/v1/alumni/me` with a known alumni token returns profile |
| Active alumni can register | Full registration flow with an active alumni account |
| Inactive alumni blocked | 403 `alumni_not_active` when attempting registration |
| Non-alumni blocked | 403 `alumni_only` when `user_type != 'alumni'` |
| Missing alumni blocked | 403 `alumni_not_found` when `ref_id` not in alumni_db |
| Snapshot immutability | Change alumni name in alumni_db; existing registration still shows original name |

### Dev Diagnostics Commands

```http
# Check alumni by email
GET /api/v1/dev/diagnostics/alumni/search?email=user@example.com
X-Dev-User: admin

# Trace full login flow
GET /api/v1/dev/diagnostics/alumni/login-trace?email=user@example.com
X-Dev-User: admin

# Lookup by alumni_id
GET /api/v1/dev/diagnostics/alumni/NITK2026IT001
X-Dev-User: admin
```

---

## Field Reference

### `alumni_db.alumni` columns used by `nitksaa-event`

| Column | Used in | Notes |
|---|---|---|
| `alumni_id` | `ref_id` in event_users and registration response | Primary key |
| `fullname` | Profile display, `fullname_snapshot` | May be null in some records |
| `email` | Login matching, `email_snapshot` | Used by `find_alumni_by_email()` |
| `phone` | `phone_snapshot` | Nullable |
| `graduationyear` | `batch_year`, `batch_year_snapshot` | Renamed in API |
| `branch` | `branch_snapshot` | Nullable; department name |
| `registrationstatus` | `is_active` computation | Compared against `{'Active', 'Self-Verified'}` |

### Columns NOT used

`nitksaa-event` does not read or use: membership fees, payment history, committee roles,
portal login state, or any columns outside the list above.
