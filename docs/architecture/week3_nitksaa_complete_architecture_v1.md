# NITKSAA Event Platform — Complete Architecture v1

**Version:** 1.0  
**Date:** 2026-06-19  
**Scope:** Week 1 → Week 3 Consolidated Architecture  
**Status:** Authoritative reference — verified against backend source and migrations  
**Companion document:** `docs/architecture/nitksaa_architecture_diagrams_v1.md`

---

## Quick Reference

| Item | Value |
|---|---|
| Backend framework | FastAPI + asyncpg (Python) |
| Auth provider | Firebase Authentication |
| Backend auth token | HS256 JWT, 8-hour expiry |
| Primary database | PostgreSQL `events_db` |
| Alumni database | PostgreSQL `alumni_db` |
| Flutter version | Flutter (Dart) — debug-mode gated diagnostics |
| Admin portal | React + Vite |
| Email mode (dev) | `EMAIL_MODE=log` (SMTP not required) |
| Backend base URL | `http://localhost:8000` |
| Swagger UI | `http://localhost:8000/docs` |

---

## Section A — System Overview

The NITKSAA Event Platform consists of four client systems communicating with one FastAPI backend, which in turn reads from two PostgreSQL databases and one external auth provider.

```text
┌──────────────────────────────────────────────────────────────────────┐
│                          Client Layer                                │
│                                                                      │
│   Flutter App (Mobile/Web)          React Admin Portal              │
│   apps/event_app/                   admin/event_admin/               │
└──────────────────┬───────────────────────────┬──────────────────────┘
                   │                           │
                   │  REST / HTTPS             │  REST / HTTPS
                   │  (Backend JWT)            │  (Backend JWT)
                   ▼                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         FastAPI Backend                              │
│                     backend/app/  (uvicorn)                          │
│                                                                      │
│   Routers: auth · events · admin_events · alumni ·                  │
│            registrations · dev_diagnostics · health                 │
│                                                                      │
│   Services: registration · alumni · email · audit · events · slug   │
│   Repos:    registration_repository · event_repository · checkin    │
└────────────┬──────────────────────────────┬─────────────────────────┘
             │                              │
             │ asyncpg                      │ asyncpg
             ▼                              ▼
┌────────────────────────┐    ┌─────────────────────────────────────┐
│     events_db          │    │           alumni_db                 │
│     (PostgreSQL)       │    │           (PostgreSQL)              │
│                        │    │                                     │
│  events                │    │  alumni                             │
│  sessions              │    │  (read-only from events platform)   │
│  registrations         │    │                                     │
│  check_ins             │    └─────────────────────────────────────┘
│  event_users           │
│  event_members         │
│  event_content         │
│  event_audit_log       │
│  notifications         │
│  notification_prefs    │
└────────────────────────┘
```

**External dependency — Firebase Authentication:**

Both Flutter and Admin Portal initiate Firebase sign-in before calling the backend.
Firebase never talks to the backend directly. The backend verifies Firebase ID tokens
using the Firebase Admin SDK but does not maintain a persistent connection to Firebase.

```text
Client → Firebase SDK (signInWithEmail / Google) → Firebase returns idToken
Client → POST /api/v1/auth/firebase {"token": idToken} → Backend returns JWT
```

See Section B for the full authentication flow.

---

## Section B — Authentication Architecture

### Token Flow

Authentication is a two-phase process:

**Phase 1 — Firebase Authentication (client-side)**
1. User enters email+password or taps Google Sign-In
2. Firebase SDK verifies credentials against Firebase Auth project
3. Firebase returns a short-lived `idToken` (~1 hour) to the client
4. The `idToken` is passed to the backend — it is never stored

**Phase 2 — Backend JWT Exchange**
1. Client calls `POST /api/v1/auth/firebase` with `{"token": "<firebase_idToken>"}`
2. Backend calls `verify_firebase_token()` → Firebase Admin SDK verifies the token
3. Backend extracts `firebase_uid` and `email` from verified claims
4. Backend calls `find_alumni_by_email(email)` against `alumni_db.alumni`
5. If found: `user_type = "alumni"`, `ref_id = alumni.alumni_id`, `graduation_year = alumni.graduationyear`
6. If not found: `user_type = "other"`, `ref_id = null`
7. Backend upserts row in `event_users` (INSERT ON CONFLICT DO UPDATE `last_login`)
8. Backend checks `is_suspended` flag — raises 403 if suspended
9. Backend mints HS256 JWT (8-hour expiry) with payload: `firebase_uid, email, fullname, user_type, ref_id, graduation_year`
10. Returns `AuthResponse` with `access_token`, `user_type`, `ref_id`, etc.

**Phase 3 — Authenticated API Calls**
1. Client stores `access_token` in local storage / secure storage
2. All protected requests include `Authorization: Bearer <access_token>`
3. Backend middleware decodes and validates the JWT
4. User identity (`firebase_uid`, `user_type`, `ref_id`) is extracted from token payload

### Key Identity Relationships

```text
Firebase (external)          events_db              alumni_db
───────────────────────────────────────────────────────────────
firebase_uid  ─────────────► event_users.firebase_uid
email         ─────────────► event_users.email
              (login match)► alumni.email  → alumni.alumni_id
                                         = event_users.ref_id
```

- `firebase_uid` is the primary identity anchor across all tables
- `ref_id` (= `alumni.alumni_id`) links an event_users row to its alumni record
- Upsert on every login: `last_login` is always refreshed; `user_type` and `ref_id` are set at first login and not overwritten on subsequent logins (only `last_login` and contact info)

### JWT Claims (Backend Token)

```json
{
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "sub": "username2026@gmail.com",
  "email": "username2026@gmail.com",
  "fullname": "Username Alumni",
  "user_type": "alumni",
  "ref_id": "NITK2026IT001",
  "graduation_year": 2026,
  "exp": 1750507804
}
```

### Auth Config Parameters

| Parameter | Default | Notes |
|---|---|---|
| `SECRET_KEY` | `dev-event-secret-change-me` | Change in production |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | 480 (8 hours) | Configured in `config.py` |
| `FIREBASE_PROJECT_ID` | `project-d22bed42-f302-4e23-8dc` | Must match Firebase console |

---

## Section C — Events DB Architecture

**Database:** `events_db` (PostgreSQL)  
**Connection:** via `EVENTS_DB_URL` or constructed from `DB_HOST/PORT/USER/PASSWORD/events_db_name`  
**Connection pool:** asyncpg

### Tables (in creation order)

#### `events` (migration 001)

| Column | Type | Notes |
|---|---|---|
| `event_id` | SERIAL PK | Auto-increment |
| `slug` | TEXT UNIQUE NOT NULL | URL-friendly identifier |
| `title` | TEXT NOT NULL | |
| `tagline` | TEXT | Optional |
| `description` | TEXT | Markdown |
| `status` | VARCHAR(20) DEFAULT 'draft' | `draft` \| `published` \| `cancelled` \| `completed` |
| `start_datetime` | TIMESTAMPTZ NOT NULL | |
| `end_datetime` | TIMESTAMPTZ NOT NULL | |
| `timezone` | VARCHAR(60) DEFAULT 'Asia/Kolkata' | |
| `location_text` | TEXT | Physical event address |
| `location_maps_url` | TEXT | Google Maps link |
| `is_virtual` | BOOLEAN NOT NULL DEFAULT false | |
| `virtual_url` | TEXT | Join link — never exposed by public API |
| `thumbnail_url` | TEXT | |
| `banner_url` | TEXT | |
| `capacity` | INT | NULL = unlimited |
| `registration_opens_at` | TIMESTAMPTZ | NULL = immediately |
| `registration_closes_at` | TIMESTAMPTZ | NULL = never |
| `created_by_firebase_uid` | VARCHAR(128) NOT NULL | Admin who created |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | Set by PATCH operations |
| `published_at` | TIMESTAMPTZ | Set when status → published |
| `cancelled_at` | TIMESTAMPTZ | Set when status → cancelled |
| `cancelled_reason` | TEXT | |
| `show_attendee_list` | BOOLEAN NOT NULL DEFAULT false | Added in migration 007 |

Indexes: `idx_events_status`, `idx_events_start_datetime`

#### `sessions` (migration 002)

| Column | Type | Notes |
|---|---|---|
| `session_id` | SERIAL PK | |
| `event_id` | INT FK → events | CASCADE DELETE |
| `track` | TEXT | |
| `title` | TEXT NOT NULL | |
| `description` | TEXT | |
| `start_datetime` | TIMESTAMPTZ NOT NULL | |
| `end_datetime` | TIMESTAMPTZ NOT NULL | |
| `location_text` | TEXT | |
| `speaker_name` | TEXT | |
| `speaker_bio` | TEXT | |
| `speaker_photo_url` | TEXT | |
| `sort_order` | INT NOT NULL DEFAULT 0 | |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT now() | |

#### `event_users` (migration 003)

| Column | Type | Notes |
|---|---|---|
| `firebase_uid` | VARCHAR(128) PK | Primary identity anchor |
| `email` | TEXT NOT NULL | |
| `fullname` | TEXT NOT NULL | From Firebase claims or alumni_db |
| `user_type` | VARCHAR(20) NOT NULL DEFAULT 'alumni' | `alumni` \| `other` |
| `ref_id` | TEXT | alumni_db.alumni.alumni_id — null for non-alumni |
| `graduation_year` | INT | From alumni_db |
| `is_suspended` | BOOLEAN NOT NULL DEFAULT false | Account block flag |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT now() | |
| `last_login` | TIMESTAMPTZ | Updated on every login |

Indexes: `idx_event_users_email`, `idx_event_users_ref_id`, `idx_event_users_type`

#### `event_members` (migration 003)

| Column | Type | Notes |
|---|---|---|
| `event_id` | INT FK → events | CASCADE DELETE |
| `firebase_uid` | VARCHAR(128) FK → event_users | CASCADE DELETE |
| `role` | VARCHAR(30) NOT NULL | |
| `status` | VARCHAR(20) NOT NULL DEFAULT 'active' | |
| `joined_at` | TIMESTAMPTZ NOT NULL DEFAULT now() | |

PK: `(event_id, firebase_uid)`

#### `registrations` (migration 004 + 008)

Migration 008 added 8 columns, dropped 1, and replaced the hard UNIQUE constraint with a partial unique index.

| Column | Type | Notes |
|---|---|---|
| `registration_id` | SERIAL PK | |
| `event_id` | INT FK → events | CASCADE DELETE |
| `firebase_uid` | VARCHAR(128) FK → event_users | |
| `ref_id` | VARCHAR(128) | alumni_db.alumni.alumni_id |
| `badge_name` | TEXT | Nullable (was NOT NULL in 004 — relaxed in 008) |
| `email` | TEXT NOT NULL | = `email_snapshot` (set from alumni_db at INSERT) |
| `phone` | TEXT | = `phone_snapshot` (set from alumni_db at INSERT) |
| `attendee_type` | VARCHAR(50) | |
| `status` | VARCHAR(20) NOT NULL DEFAULT **'registered'** | `registered` \| `cancelled` |
| `qrtoken` | TEXT UNIQUE | Nullable (QR check-in deferred to future) |
| `notes` | TEXT | = `attendee_note` in API |
| `registered_at` | TIMESTAMPTZ NOT NULL DEFAULT now() | |
| `cancelled_at` | TIMESTAMPTZ | Set when cancelled |
| `registration_number` | TEXT | Format: `NITKSAA-YYYY-NNNNNN` (added migration 008) |
| `fullname_snapshot` | TEXT | Immutable alumni name at registration time (added 008) |
| `batch_year_snapshot` | INTEGER | From alumni_db.alumni.graduationyear (added 008) |
| `branch_snapshot` | TEXT | From alumni_db.alumni.branch (added 008) |
| `confirmation_email_status` | VARCHAR(20) DEFAULT 'pending' | `pending`\|`sent`\|`failed`\|`skipped` (added 008) |
| `confirmation_email_sent_at` | TIMESTAMPTZ | Added 008 |
| `confirmation_email_error` | TEXT | Added 008 |
| `updated_at` | TIMESTAMPTZ | Set after email and cancellation (added 008) |

**Key indexes:**
- `uq_registrations_active` — partial UNIQUE `(event_id, firebase_uid) WHERE status = 'registered'` (replaces hard UNIQUE)
- `uq_registrations_registration_number` — partial UNIQUE `(registration_number) WHERE NOT NULL`
- `idx_registrations_event_id`, `idx_registrations_firebase_uid`, `idx_registrations_status`

> **Registration number generation:** Two-step process — INSERT row (gets `registration_id`), then UPDATE `registration_number = 'NITKSAA-' || EXTRACT(year FROM now()) || '-' || LPAD(registration_id::text, 6, '0')` within the same transaction.

#### `check_ins` (migration 004)

| Column | Type | Notes |
|---|---|---|
| `checkin_id` | SERIAL PK | |
| `registration_id` | INT FK → registrations | |
| `event_id` | INT FK → events | |
| `scanned_by` | VARCHAR(128) FK → event_users | |
| `scanned_at` | TIMESTAMPTZ NOT NULL DEFAULT now() | |
| `session_id` | INT FK → sessions | Nullable |
| `result` | VARCHAR(20) CHECK | `success` \| `duplicate` \| `invalid` |

#### `event_content` (migration 005)

| Column | Type | Notes |
|---|---|---|
| `content_id` | SERIAL PK | |
| `event_id` | INT FK → events | CASCADE DELETE |
| `content_type` | VARCHAR(20) CHECK | `recording` \| `gallery` |
| `label` | TEXT NOT NULL | |
| `url` | TEXT NOT NULL | |
| `sort_order` | INT NOT NULL DEFAULT 0 | |
| `added_by` | VARCHAR(128) FK → event_users | |
| `added_at` | TIMESTAMPTZ NOT NULL DEFAULT now() | |

#### `event_audit_log` (migration 006 + 009)

| Column | Type | Notes |
|---|---|---|
| `log_id` | BIGSERIAL PK | |
| `actor_uid` | VARCHAR(128) | Firebase UID of the actor (nullable for system actions) |
| `event_type` | TEXT NOT NULL | e.g., `registration_created`, `confirmation_email_sent` |
| `entity_type` | TEXT NOT NULL | e.g., `registration`, `event` |
| `entity_id` | INTEGER | e.g., `registration_id` |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT now() | |
| `context` | JSONB | Structured metadata — added migration 009 |

**Security rule:** `context` must never contain `firebase_uid`, `email`, `phone`, join URLs, or tokens.

**Event types used in Week 3:**
- `registration_created`
- `registration_email_sent` (or `confirmation_email_sent`)
- `registration_email_failed`
- `registration_cancelled`
- `registration_duplicate_blocked`
- `diagnostics_execution`

#### `notifications` and `notification_preferences` (migration 006)

Infrastructure tables — created but not yet used by production features.

| Table | Key columns |
|---|---|
| `notifications` | `notification_id BIGSERIAL PK`, `firebase_uid`, `event_type`, `is_read BOOLEAN` |
| `notification_preferences` | PK `(firebase_uid, event_type)`, `push_enabled BOOLEAN` |

---

## Section D — Alumni DB Architecture

**Database:** `alumni_db` (PostgreSQL, separate from events_db)  
**Connection:** via `ALUMNI_DB_URL` or constructed from `DB_HOST/PORT/USER/PASSWORD/alumni_db_name`  
**Access pattern:** Read-only from the events platform — alumni records are never modified

### Table Used: `alumni`

Fields accessed by the events platform:

| alumni_db column | API / response field | Notes |
|---|---|---|
| `alumni_id` | `ref_id` (in event_users, registrations) | Primary key — used as the cross-DB link |
| `fullname` | `fullname` (AlumniProfileResponse) | Displayed name; copied to `fullname_snapshot` at registration |
| `email` | `email` (AlumniProfileResponse) | Used for confirmation email delivery |
| `phone` | `phone` (AlumniProfileResponse) | Copied to `phone_snapshot` at registration |
| `graduationyear` | `batch_year` (AlumniProfileResponse) | Copied to `batch_year_snapshot` at registration |
| `branch` | `branch` (AlumniProfileResponse) | Copied to `branch_snapshot` at registration |
| `registrationstatus` | `is_active` (AlumniProfileResponse) | Computed: `is_active = registrationstatus IN ('Active', 'Self-Verified')` |
| `firebase_uid` | (not directly used by events platform) | May exist in alumni_db but not the join key |

### Cross-Database Identity Mapping

```text
POST /auth/firebase
  ↓
find_alumni_by_email(email) → alumni_db.alumni WHERE email = $1
  ↓
alumni_id  →  stored as  event_users.ref_id
              stored as  registrations.ref_id
              used by    GET /alumni/me (SELECT alumni WHERE alumni_id = current_user.ref_id)
```

**Active alumni check (registration eligibility):**
```python
def is_alumni_active(registrationstatus: str) -> bool:
    return registrationstatus in ('Active', 'Self-Verified')
```

---

## Section E — Registration Flow Architecture

### Overview

The registration flow is implemented in `backend/app/services/registration_service.py`.

**Pre-conditions for successful registration:**
1. Backend JWT is valid (`user_type = "alumni"`, `ref_id` is not null)
2. Alumni record exists in alumni_db (`ref_id` → `alumni.alumni_id`)
3. Alumni is active (`registrationstatus IN ('Active', 'Self-Verified')`)
4. Event exists, is `published`
5. `now` is within `[registration_opens_at, registration_closes_at]` (if set)
6. No active registration exists for this `(event_id, firebase_uid)` pair
7. `registered_count < capacity` (if capacity is set)

### Transaction Boundary

```text
async with conn.transaction():
    ├── SELECT events WHERE event_id = $1 FOR UPDATE  ← prevents double-registration race
    ├── Validate event status, dates, capacity
    ├── Validate no duplicate registration
    ├── INSERT INTO registrations (...)
    ├── UPDATE registrations SET registration_number = 'NITKSAA-YYYY-NNNNNN'
    └── COMMIT ← registration is durable here

# Outside transaction (non-blocking, post-commit):
await email_service.send_confirmation_email(...)
await registration_repository.update_email_status(...)
await audit_service.emit('registration_created', ...)
```

### Registration Number Format

```text
NITKSAA-{year}-{registration_id:06d}

Examples:
  NITKSAA-2026-000001
  NITKSAA-2026-000042
  NITKSAA-2026-001000
```

Year is extracted from `now()` (UTC) at INSERT time.

### Snapshot Fields

At the moment of registration, six fields are copied from alumni_db into the registration row:

| Snapshot column | Source | Why immutable |
|---|---|---|
| `email` (= `email_snapshot`) | `alumni.email` | Alumni may change email later; confirmation goes to email at time of reg |
| `phone` (= `phone_snapshot`) | `alumni.phone` | Contact info frozen at registration |
| `fullname_snapshot` | `alumni.fullname` | Badge/display name at time of reg |
| `batch_year_snapshot` | `alumni.graduationyear` | Frozen for reports |
| `branch_snapshot` | `alumni.branch` | Frozen for reports |
| `ref_id` | `event_users.ref_id` | = `alumni.alumni_id` |

### Error Codes (POST /register)

| HTTP | detail | Condition |
|---|---|---|
| 403 | `alumni_only` | `user_type != "alumni"` or `ref_id` is null |
| 403 | `alumni_not_found` | `ref_id` not in alumni_db |
| 403 | `alumni_not_active` | `registrationstatus NOT IN ('Active', 'Self-Verified')` |
| 404 | `event_not_found` | Event does not exist |
| 409 | `event_not_published` | Event status != `published` |
| 409 | `registration_not_open_yet` | `now < registration_opens_at` |
| 409 | `registration_closed` | `now > registration_closes_at` |
| 409 | `already_registered` | Partial unique index violation |
| 409 | `event_full` | `registered_count >= capacity` |

---

## Section F — Join Link Security Architecture

The `virtual_url` of an event (the actual meeting link) must never be exposed to:
- Unauthenticated requests
- Authenticated users who have not registered
- Cancelled registrations
- Draft/cancelled events

### Resolution Rule (from `registration_service.py`)

```python
def _resolve_join_url(row: Dict[str, Any]) -> Optional[str]:
    if (
        row.get("status") == "registered"          # ← registration is active
        and row.get("is_virtual")                   # ← event is virtual
        and row.get("event_status") == "published"  # ← event is live
    ):
        return row.get("virtual_url")
    return None
```

All three conditions must be true simultaneously. Any single failing condition returns `None`.

### Visibility Matrix

| Scenario | join_url | Reason |
|---|---|---|
| `registered` + `is_virtual=true` + `published` | **Visible** | All three conditions met |
| `cancelled` + `is_virtual=true` + `published` | `null` | Status is not `registered` |
| `registered` + `is_virtual=false` + `published` | `null` | Physical event — no join link |
| `registered` + `is_virtual=true` + `draft` | `null` | Event is not published |
| Public API (no auth) | `null` | `virtual_url` stripped from public schema projection |
| Public API (with auth) | `null` | Public endpoints never return `virtual_url` or `join_url` |

### Public API Protection

The public event endpoints (`GET /api/v1/events/public` and `GET /api/v1/events/public/{event_id}`) use schema projection — `virtual_url`, `join_url`, and `created_by_firebase_uid` are not included in the response model. This is enforced at the Pydantic schema level, not by conditional logic.

---

## Section G — Email Architecture

### Email Service (`backend/app/services/email_service.py`)

The email service is stateless — it accepts parameters and returns an `EmailResult`. It never raises an exception to callers.

**Modes (controlled by `EMAIL_MODE` env var):**

| Mode | Behaviour | Use |
|---|---|---|
| `log` (default) | Writes a log entry; returns `status="sent"` | Development — no SMTP setup needed |
| `send` | Sends via SMTP (smtplib + starttls) | Production / staging |
| Any other value | Logs a warning; returns `status="skipped"` | Fallback |

**Email content (HTML):**
- Subject: `Registration confirmed — {event_title}`
- Body: registration number, fullname, event title, join link (if virtual)

### Non-Blocking Email Pattern

Email is always sent **after** the registration transaction commits:

```text
Transaction COMMIT
     ↓ (registration is now durable)
send_confirmation_email(...)
     ↓
EmailResult(status="sent"|"failed"|"skipped", sent_at, error)
     ↓
UPDATE registrations SET
  confirmation_email_status = result.status,
  confirmation_email_sent_at = result.sent_at,
  confirmation_email_error = result.error,
  updated_at = now()
     ↓
audit_service.emit('confirmation_email_sent' or 'confirmation_email_failed')
```

**Critical invariant:** A failed email send NEVER rolls back the registration. The confirmation can be resent manually. The registration itself is the source of truth.

### SMTP Configuration

| Setting | Env var | Default |
|---|---|---|
| Email mode | `EMAIL_MODE` | `log` |
| From address | `EMAIL_FROM` | null (uses smtp_user) |
| Reply-to | `EMAIL_REPLY_TO` | null |
| SMTP host | `SMTP_HOST` | `smtp.gmail.com` |
| SMTP port | `SMTP_PORT` | 587 |
| SMTP user | `SMTP_USER` | null |
| SMTP password | `SMTP_PASSWORD` | null |

---

## Section H — Audit Log Architecture

### Table: `event_audit_log` (migrations 006 + 009)

```sql
log_id       BIGSERIAL PRIMARY KEY
actor_uid    VARCHAR(128)    -- Firebase UID (null for system actions)
event_type   TEXT NOT NULL   -- Action type
entity_type  TEXT NOT NULL   -- What was affected
entity_id    INTEGER         -- ID of the affected entity
created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
context      JSONB           -- Structured metadata (added migration 009)
```

### Audit Service (`backend/app/services/audit_service.py`)

`emit()` characteristics:
- Never raises — all errors are caught and logged with `[audit]` prefix
- Callers are never blocked or affected by audit failures
- Opens its own connection from the pool (does not participate in the registration transaction)
- Writes after registration commit — audit failure does not affect registration

### Event Types (Week 1–3)

| event_type | entity_type | entity_id | context keys |
|---|---|---|---|
| `registration_created` | `registration` | `registration_id` | `registration_number`, `event_id` |
| `confirmation_email_sent` | `registration` | `registration_id` | `email_status` |
| `confirmation_email_failed` | `registration` | `registration_id` | `email_status`, `error` |
| `registration_cancelled` | `registration` | `registration_id` | |
| `registration_duplicate_blocked` | `registration` | `event_id` | |
| `diagnostics_execution` | `system` | — | |

**Security rule:** `context` must never contain `firebase_uid`, `email`, `phone`, join URLs, or auth tokens.

---

## Section I — Developer Diagnostics Architecture

Developer Diagnostics is available only in `APP_ENV=development` (backend) and `kDebugMode` (Flutter). It is stripped from release builds and returns `404` from production backend.

### Flutter: Diagnostic Categories and Items

| Category | Items | Status |
|---|---|---|
| General | Foundation Status, Logger Test, Theme Control, Network Test, App Performance, Debug Tools | Implemented |
| Authentication | Firebase Token Test, Backend Auth Test, /auth/me Test | Implemented |
| Database | Event Users Test, Database Tables Test | Implemented |
| Event Management | Events API Test, Event Detail API Test, Event Creation API Test, Event Publish Test | Placeholder (Week 3+) |
| Registration | **Week 3 UX Showcase**, Registration Flow Test, My Registration Test, Capacity Guard Test, Confirmation Email Status, Join Link Visibility Test | Implemented |
| Admin / Attendees | Attendee List API Test, Attendee Export Test, Admin Role Guard Test, Audit Trail Test | Placeholder (Week 4) |
| **Alumni Database** | Search by Email, Search by Prefix, Lookup by Alumni ID, Login Mapping Trace | **Implemented** |

### Backend: Dev Diagnostics Endpoints

All at `/api/v1/dev/diagnostics/` — return `404` when `APP_ENV != "development"`.

| Endpoint | Purpose |
|---|---|
| `GET /db/tables` | List all accessible tables with row counts |
| `GET /db/{table_name}` | Inspect rows from a supported table |
| `GET /auth/me` | Auth check — current user from event_users |
| `GET /registrations` | Run 13-check registration diagnostics suite |
| `GET /alumni/search?email=` | Search alumni_db by exact email (case-insensitive, TRIM) |
| `GET /alumni/search-prefix?prefix=` | Search alumni_db by email prefix or name fragment |
| `GET /alumni/{alumni_id}` | Full row lookup from alumni_db by alumni_id |
| `GET /alumni/login-trace?email=` | Trace alumni_db → event_users login mapping; diagnose user_type=other root cause |

### 13-Check Registration Diagnostics Suite

| Check # | Feature tested | Expected |
|---|---|---|
| 1 | Alumni Profile | PASS |
| 2 | Test Virtual Event Setup | Event 26 exists and is published |
| 3 | Test Capacity Event Setup | Event 34 exists and is full |
| 4 | Registration Eligibility | `eligible` for event 25 or 26 |
| 5 | Register for Event | HTTP 201, `status=registered` |
| 6 | My Registration | `join_url` present for virtual |
| 7 | My Registrations List | Test registration found in list |
| 8 | Duplicate Registration Guard | HTTP 409, `already_registered` |
| 9 | Capacity Guard | HTTP 409, `event_full` for event 34 |
| 10 | Confirmation Email Status | `confirmation_email_status` = `sent` or `failed` |
| 11 | Join Link Visibility | `join_url` present for virtual registered event |
| 12 | Audit Log Check | At least one audit row found |
| 13 | Public API Leak Check | `virtual_url`, `join_url` absent from public response |

### Week 3 UX Showcase

Located in: Registration category → "Week 3 UX Showcase" → `_RegistrationDiagnosticDetail`

| Section | Type | Content |
|---|---|---|
| §0 Run All | Live | 13-check backend diagnostic runner |
| §1 Alumni Autofill | Live | `GET /alumni/me` response |
| §2 Eligibility | Live | `GET /events/{id}/registration-eligibility` response |
| §3 Registration Action | Live | `POST /events/{id}/register` response |
| §4 Confirmation Preview | Derived | Uses §3 result — no extra API call |
| §5 My Registration | Live | `GET /events/{id}/my-registration` response |
| §6 My Registrations | Live | `GET /my/registrations` response |
| §7 Negative Gallery | Static | 9 error state cards |
| §8a Join Link Matrix | Static | 4-row security rule table |
| §8b Public Leak Validation | Live | `GET /events/public/{id}` + forbidden field check |
| §9 Audit Trail | Live | `GET /dev/diagnostics/db/event_audit_log` rows |
| §10 Email Demo | Derived | Uses §3 result |
| §11 Snapshot Demo | Derived | §1 vs §3 comparison |
| §12 DB Rules | Static | 4 database constraint cards |

---

## Section J — Flutter App Architecture

**Location:** `apps/event_app/`  
**Framework:** Flutter (Dart)  
**State management:** Riverpod  
**Routing:** go_router  
**HTTP client:** Dio

### Layer Structure

```text
apps/event_app/lib/
├── main.dart                    App entry point
├── app/                         App config, root widget
├── config/                      Environment variables (dart-define)
├── core/                        Core utilities, app state
├── features/
│   ├── auth/                    Authentication feature
│   │   ├── data/                Auth API client, repositories
│   │   ├── domain/              Auth models
│   │   ├── presentation/        Login screen, auth providers
│   │   └── services/            AuthSessionStore, GoogleSignInInitializer
│   ├── developer/               Developer Diagnostics (debug-mode only)
│   │   └── presentation/        developer_diagnostics_screen.dart
│   ├── events/                  Public event browsing
│   │   ├── domain/              Event models
│   │   ├── presentation/        event_list_screen, event_detail_screen
│   │   └── services/            Event API service
│   ├── foundation/              Foundation check screen
│   └── home/                    Home screen
│       └── presentation/
├── routes/
│   ├── app_router.dart          GoRouter configuration
│   ├── app_routes.dart          Route constants
│   └── route_guards.dart        Auth-gated route guards
├── services/                    Shared services (Dio setup, etc.)
├── shared/                      Shared widgets, models
├── theme/                       Theme provider
└── widgets/                     Shared UI components
```

### Production Screens (Implemented)

| Route | Screen | Auth | Purpose |
|---|---|---|---|
| `/` | Root / Splash | None | Redirect to login or home |
| `/login` | LoginScreen | None | Firebase email+password + Google |
| `/home` | HomeScreen | Required | Post-login home (nav to events, diagnostics) |
| `/events` | EventListScreen | None (public) | Public event list with Upcoming/Past tabs |
| `/events/{id}` | EventDetailScreen | None (public) | Public event detail with registration CTA |
| `/developer` | DeveloperDiagnosticsScreen | Required + `kDebugMode` | Development tool |
| `/foundation` | FoundationCheckScreen | None | App status check (debug only) |

### Diagnostics-Only (Not Production UX)

The registration flow UX (register button, confirmation screen, my registrations) is implemented only inside `DeveloperDiagnosticsScreen` as prototypes. Production registration UI is deferred to Week 4.

---

## Section K — Admin Portal Architecture

**Location:** `admin/event_admin/`  
**Framework:** React + Vite  
**Auth:** Firebase SDK + backend JWT exchange  
**HTTP client:** Custom `apiClient.js` (fetch-based)

### Layer Structure

```text
admin/event_admin/src/
├── App.jsx                      Root component, route setup
├── main.jsx                     Vite entry point
├── firebase.js                  Firebase SDK initialization
├── api/
│   ├── apiClient.js             Fetch wrapper — auto-attaches Bearer JWT
│   ├── authApi.js               Firebase exchange + /auth/me
│   └── eventsApi.js             Event CRUD calls
├── auth/
│   ├── AuthProvider.jsx         Firebase + backend session management
│   ├── RequireAuth.jsx          Route guard component
│   └── sessionStorage.js        localStorage key constants
├── components/                  Shared UI components
├── layout/                      Shell layout (sidebar, header)
├── pages/
│   ├── LoginPage.jsx            Firebase sign-in
│   ├── DashboardPage.jsx        Health check card, overview
│   ├── EventsPage.jsx           Event list table (all statuses)
│   ├── EventFormPage.jsx        Create + Edit form
│   ├── AttendeesPage.jsx        (Week 4 — not yet functional)
│   ├── RegistrationsPage.jsx    (Week 4 — not yet functional)
│   └── SettingsPage.jsx         Firebase config display, env info
└── styles/                      CSS modules
```

### Admin Portal Status by Feature

| Feature | Page | Week | Status |
|---|---|---|---|
| Login (Firebase → JWT) | LoginPage | 1 | Implemented |
| Health check display | DashboardPage | 1 | Implemented |
| Event list (all statuses) | EventsPage | 2 | Implemented |
| Create event (as draft) | EventFormPage | 2 | Implemented |
| Edit event | EventFormPage | 2 | Implemented |
| Publish / unpublish | EventsPage | 2 | Implemented |
| Cancel event | EventsPage | 2 | Implemented |
| Attendee list | AttendeesPage | 4 | **Pending** |
| Registration search | RegistrationsPage | 4 | **Pending** |
| CSV export | EventsPage | 4 | **Pending** |

### Token Storage Policy

| Token | Stored | Key |
|---|---|---|
| Firebase ID token | Never stored | Memory only |
| Backend JWT | `localStorage` | `nitksaa_event_admin_access_token` |
| User summary | `localStorage` | `nitksaa_event_admin_user` |

### apiClient Error Handling

| Scenario | Behaviour |
|---|---|
| Network unreachable | Throws with "cannot reach backend" |
| HTTP 401 / 403 | `clearSession()` + redirect to `/login` |
| HTTP 4xx (other) | Throws with `detail` from response body |
| HTTP 5xx | Throws with "HTTP 5xx" message |

---

## Section L — API Inventory

### Week 1 — Foundation and Authentication

| Method | Path | Auth | Status |
|---|---|---|---|
| `GET` | `/api/v1/health` | None | Implemented |
| `POST` | `/api/v1/auth/firebase` | Firebase token in body | Implemented |
| `GET` | `/api/v1/auth/me` | Backend JWT | Implemented |

### Week 2 — Event Management and Public Events

| Method | Path | Auth | Status |
|---|---|---|---|
| `GET` | `/api/v1/events/public` | None | Implemented |
| `GET` | `/api/v1/events/public/{event_id}` | None | Implemented |
| `POST` | `/api/v1/events` | Backend JWT (admin) | Implemented |
| `GET` | `/api/v1/events` | Backend JWT (admin) | Implemented |
| `GET` | `/api/v1/events/{event_id}` | Backend JWT (admin) | Implemented |
| `PATCH` | `/api/v1/events/{event_id}` | Backend JWT (admin) | Implemented |
| `PATCH` | `/api/v1/events/{event_id}/status` | Backend JWT (admin) | Implemented |

### Week 3 — Registration and Alumni

| Method | Path | Auth | Status |
|---|---|---|---|
| `GET` | `/api/v1/alumni/me` | Backend JWT (alumni only) | Implemented |
| `POST` | `/api/v1/events/{event_id}/register` | Backend JWT (alumni only) | Implemented |
| `GET` | `/api/v1/events/{event_id}/registration-eligibility` | Backend JWT | Implemented |
| `GET` | `/api/v1/events/{event_id}/my-registration` | Backend JWT | Implemented |
| `GET` | `/api/v1/my/registrations` | Backend JWT | Implemented |
| `GET` | `/api/v1/dev/diagnostics/registrations` | Backend JWT (dev only) | Implemented |

### Week 4 — Admin Attendees (Planned)

| Method | Path | Auth | Status |
|---|---|---|---|
| `GET` | `/api/v1/events/{event_id}/attendees` | Backend JWT (admin) | **Planned — returns 501** |
| `GET` | `/api/v1/events/{event_id}/attendees/export` | Backend JWT (admin) | **Planned — returns 501** |

### Developer Diagnostics (Dev Environment Only)

| Method | Path | Auth | Status |
|---|---|---|---|
| `GET` | `/api/v1/dev/diagnostics/db/tables` | Backend JWT | Implemented |
| `GET` | `/api/v1/dev/diagnostics/db/{table_name}` | Backend JWT | Implemented |
| `GET` | `/api/v1/dev/diagnostics/auth/me` | Backend JWT | Implemented |

---

## Section M — Migration History

Database: `events_db`

| Migration | File | Purpose | Week |
|---|---|---|---|
| 001 | `001_events.sql` | Create `events` table — all event fields including `virtual_url`, `capacity`, `status` lifecycle | 1 |
| 002 | `002_sessions.sql` | Create `sessions` table — per-event tracks and speaker info | 1 |
| 003 | `003_event_users_and_event_members.sql` | Create `event_users` (identity anchor) and `event_members` (per-event roles) | 1 |
| 004 | `004_registrations_and_check_ins.sql` | Create `registrations` and `check_ins` tables (original schema — pre-Week 3) | 1/2 |
| 005 | `005_event_content.sql` | Create `event_content` table — recordings and gallery links | 2 |
| 006 | `006_audit_notifications.sql` | Create `event_audit_log`, `notifications`, `notification_preferences` | 2 |
| 007 | `007_add_show_attendee_list.sql` | ALTER `events` — add `show_attendee_list BOOLEAN` | 2 |
| **008** | **`008_week3_registration_alignment.sql`** | **Major registrations update — 15 changes (see below)** | **3** |
| **009** | **`009_add_audit_log_context.sql`** | **ADD COLUMN `context JSONB` to `event_audit_log`** | **3** |

### Migration 008 Detail (Week 3 Key Migration)

Migration 008 makes the following changes to `registrations`:

1. `status` DEFAULT changed `'confirmed'` → `'registered'`
2. Existing `'confirmed'` rows migrated to `'registered'`
3. `qrtoken` made nullable (QR check-in deferred)
4. `badge_name` made nullable (badge printing deferred)
5. Hard `UNIQUE(event_id, firebase_uid)` constraint dropped
6. Partial unique index `uq_registrations_active WHERE status='registered'` created
7. `confirmation_email_sent` BOOLEAN column dropped
8–14. New columns added: `registration_number`, `fullname_snapshot`, `batch_year_snapshot`, `branch_snapshot`, `confirmation_email_status`, `confirmation_email_sent_at`, `confirmation_email_error`
15. `updated_at` column added

Final column count: **21 columns** (14 original − 1 dropped + 8 added).

### Migration 009 Detail (Week 3 Audit Enhancement)

Single change: `ALTER TABLE event_audit_log ADD COLUMN IF NOT EXISTS context JSONB`

Allows registration audit entries to carry structured metadata like `registration_number`, `event_id`, `email_status`. Existing rows are unaffected (`context = NULL`).

---

## Section N — Feature Completion Matrix

| Feature | Week | Status | Notes |
|---|---|---|---|
| Firebase Authentication | 1 | Implemented | Email+password, Google Sign-In |
| Backend JWT Exchange | 1 | Implemented | `/auth/firebase` → `access_token` |
| Auth Me endpoint | 1 | Implemented | `/auth/me` |
| Dev Diagnostics — Auth | 1 | Implemented | Firebase token, backend auth, auth/me |
| Dev Diagnostics — Database | 1 | Implemented | Table listing, row inspection |
| Health endpoint | 1 | Implemented | DB connectivity check |
| Event CRUD (admin) | 2 | Implemented | Create, read, update |
| Event Status Lifecycle | 2 | Implemented | draft → published → cancelled/completed |
| Public Event List | 2 | Implemented | Paginated, published-only |
| Public Event Detail | 2 | Implemented | Wrapped `{"event": {...}}` shape |
| Admin Event List | 2 | Implemented | All statuses |
| Admin Event Detail | 2 | Implemented | Includes `virtual_url` |
| Flutter Public Event List Screen | 2 | Implemented | Upcoming/Past tabs |
| Flutter Event Detail Screen | 2 | Implemented | Registration CTA placeholder |
| React Admin Event Pages | 2 | Implemented | EventsPage, EventFormPage |
| join_url hidden from public API | 2 | Implemented | Schema projection |
| Alumni Profile endpoint | 3 | Implemented | `/alumni/me` |
| Registration eligibility endpoint | 3 | Implemented | `/events/{id}/registration-eligibility` |
| Alumni registration | 3 | Implemented | With capacity, deadline, duplicate guards |
| Registration number generation | 3 | Implemented | `NITKSAA-YYYY-NNNNNN` format |
| Alumni snapshot capture | 3 | Implemented | 5 fields copied at registration time |
| Confirmation email service | 3 | Implemented | `EMAIL_MODE=log` (dev) / `send` (prod) |
| Email non-blocking policy | 3 | Implemented | Post-commit, failure = status update only |
| Join link reveal | 3 | Implemented | 3-condition rule from `_resolve_join_url` |
| My Registration endpoint | 3 | Implemented | `/events/{id}/my-registration` |
| My Registrations List | 3 | Implemented | `/my/registrations` |
| Audit log JSONB context | 3 | Implemented | Migration 009 |
| Dev Diagnostics — Registration | 3 | Implemented | 13-check suite |
| Week 3 UX Showcase | 3 | Implemented | 16 sections in Developer Diagnostics |
| Admin attendee list endpoint | 4 | **Planned** | Returns 501 currently |
| Admin attendee CSV export | 4 | **Planned** | Returns 501 currently |
| React Admin attendee page | 4 | **Pending** | Page exists but not functional |
| Flutter registration screen | 4 | **Pending** | No production screen yet |
| Flutter confirmation screen | 4 | **Pending** | |
| Flutter my registrations screen | 4 | **Pending** | |
| Flutter join link display | 4 | **Pending** | |
| QR check-in | Future | Deferred | `qrtoken` column exists, nullable |
| Waitlist | Future | Deferred | Not designed |
| Payments | Future | Deferred | Not designed |
| Push notifications | Future | Deferred | Infrastructure table created |
| Sessions / tracks UI | Future | Deferred | Table created, no UI |
| Attendance tracking | Future | Deferred | `check_ins` table exists |

---

## Section O — Known Technical Debt

| Item | Impact | Priority | Reference |
|---|---|---|---|
| Developer Diagnostics missing copy button on JSON blocks | Low — ergonomics only | P1 | `docs/reviews/developer_diagnostics_json_io_review.md` |
| §9 Audit Trail has no raw JSON `_jsonBlock` | Low — dev ergonomics | P1 | `docs/reviews/developer_diagnostics_json_io_review.md` |
| No request payload shown in diagnostics | Medium — debugging | P2 | `docs/reviews/developer_diagnostics_json_io_review.md` |
| HTTP status codes not shown in diagnostics | Low | P2 | `docs/reviews/developer_diagnostics_json_io_review.md` |
| Cleanup / test-reset tool not implemented | Medium — dev velocity | P2 | `docs/reviews/dev_diagnostics_cleanup_tool_design_review.md` |
| Admin attendee management backend | High — Week 4 blocker | P1 | Returns 501, needs implementation |
| Production Flutter registration UI | High — Week 4 goal | P1 | None of the registration screens exist |
| No hard-delete for events | By design | N/A | Only soft-cancel; confirmed correct |
| `show_attendee_list` flag unused | Low | Low | Column exists, no UI reads it |
| `event_members` table unused | Low | Low | Table created, no API |
| `event_content` table unused | Low | Low | Table created, no API |
| Slug-based public URLs (e.g., `/events/webinar-on-ai`) | Medium | P3 | Architecture suggestion open |
| `registration_opens_at` vs `published` separation | Low | P3 | Architecture observation open |
| `notifications` and `notification_preferences` tables unused | Low | Low | Infrastructure ready for future |

---

## Section P — Week 4 Starting Point

### Already Done — Do Not Touch

| Area | Status |
|---|---|
| Firebase Authentication end-to-end | Complete |
| Backend JWT exchange and validation | Complete |
| Events CRUD (all lifecycle states) | Complete |
| Public event listing and detail APIs | Complete |
| Admin event management (React Portal) | Complete |
| Alumni profile endpoint | Complete |
| Registration eligibility endpoint | Complete |
| Registration backend (all validations) | Complete |
| Snapshot capture | Complete |
| Confirmation email service | Complete |
| Join link security | Complete |
| Audit log (with JSONB context) | Complete |
| Developer Diagnostics full suite | Complete |
| Week 3 UX Showcase (16 sections) | Complete |
| 9 migrations applied | Complete |

### Recommended Week 4 Build Order

**Phase 1 — Admin Attendee Backend (Week 4 Day 1–2)**

1. Implement `GET /api/v1/events/{event_id}/attendees` — paginated registration list
2. Implement `GET /api/v1/events/{event_id}/attendees/export` — CSV download
3. Verify both endpoints with Swagger + manual test
4. Update `backend_api_index_v2.md`

**Phase 2 — Admin Attendee UI (Week 4 Day 2–3)**

5. Wire up `AttendeesPage.jsx` in React Admin Portal
6. Add batch-year filter and search-by-name
7. Add CSV export button
8. Add registered count summary card to `EventsPage.jsx`

**Phase 3 — Flutter Production Registration UI (Week 4 Day 3–5)**

9. Registration screen (confirm alumni autofill, tap to register)
10. Eligibility state handling (full / closed / not_open_yet / ineligible cards)
11. Confirmation screen (registration number, join link for virtual)
12. My Registrations screen (list view, ordered by date)
13. Join link display on Event Detail screen (post-registration)
14. Venue map link for physical events

**Phase 4 — Beta Hardening (Week 4 Day 5–7)**

15. Staging deployment and environment variable setup
16. End-to-end smoke test on staging
17. Staff walkthrough guide
18. Known issues list
19. Final beta demo script

### Test Event Reference (for Week 4 testing)

| event_id | Type | Condition | Purpose |
|---|---|---|---|
| 25 | Physical | Registration open | Standard registration test |
| 26 | Virtual | Registration open | Join link reveal test |
| 34 | Any | Full | `event_full` guard test |
| 35 | Any | Closed | `registration_closed` guard test |
| 36 | Any | Not open yet | `registration_not_open_yet` guard test |

Recreate these with SQL in `docs/validation/backend_week3_manual_verification_guide_v2.md §10` if local IDs differ.

---

*All diagrams in: `docs/architecture/nitksaa_architecture_diagrams_v1.md`*  
*API reference: `docs/api/backend_api_index_v2.md`*  
*Response shapes: `docs/api/week3_actual_api_response_shapes.md`*  
*API testing: `docs/api/swagger_testing_guide.md`*
