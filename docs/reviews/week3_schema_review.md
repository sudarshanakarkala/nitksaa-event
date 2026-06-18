# NITKSAA Event App — Week 3 Schema Review

**Date:** 2026-06-18  
**Phase:** 0 — Pre-development review  
**Reviewer:** Claude Code (automated)  
**Sprint:** Week 3 — Registration, Confirmation Email, Protected Join Link

---

## 1. Migration File Inventory

| File | Purpose | Status |
|---|---|---|
| 001_create_events_alpha_schema.sql | ALPHA schema — superseded | SUPERSEDED |
| 001_events.sql | events table (canonical) | ACTIVE |
| 002_sessions.sql | sessions table | ACTIVE |
| 003_event_users_and_event_members.sql | event_users, event_members tables | ACTIVE |
| 004_registrations_and_check_ins.sql | registrations, check_ins tables | ACTIVE — but misaligned with service code |
| 005_event_content.sql | event_content table | ACTIVE |
| 006_audit_notifications.sql | event_audit_log, notifications, notification_preferences | ACTIVE |
| 007_add_show_attendee_list.sql | adds show_attendee_list column to events | ACTIVE |

---

## 2. Critical Finding: Dual Schema Conflict

### 2.1 Problem

Two migration paths exist for the registrations table:

**Alpha schema** (`001_create_events_alpha_schema.sql`):
```sql
CREATE TABLE IF NOT EXISTS registrations (
    registration_id BIGSERIAL PRIMARY KEY,
    full_name TEXT NOT NULL,
    status TEXT DEFAULT 'registered',
    registration_source TEXT DEFAULT 'api_alpha',
    qr_token TEXT UNIQUE,    -- underscore
    metadata JSONB,
    ...
)
```
Also creates: `attendees` table, `check_in_attempts` table, different `check_ins` structure.

**Numbered series** (`004_registrations_and_check_ins.sql`):
```sql
CREATE TABLE registrations (
    registration_id SERIAL PRIMARY KEY,
    badge_name TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'confirmed',
    qrtoken TEXT UNIQUE NOT NULL,    -- no underscore, NOT NULL
    confirmation_email_sent BOOLEAN DEFAULT false,
    ...
)
-- No attendees table
-- Different check_ins structure
```

### 2.2 Impact on Existing Service Code

The existing `registration_repository.py` and `registration_service.py` use alpha schema column names:

```python
# registration_repository.py INSERT:
INSERT INTO registrations (
    event_id, firebase_uid, ref_id, email, full_name,
    status, registration_source, qr_token, metadata
)
```

These columns (`full_name`, `registration_source`, `qr_token` snake_case, `metadata`) do NOT exist in migration 004. They exist in the alpha schema.

Similarly, the repository calls `create_attendee()` which inserts into an `attendees` table. That table exists in alpha but NOT in migration 004.

### 2.3 Resolution Required

**Before Week 3 coding begins, confirm which schema is active in the live database.**

The Week 2 verification passed for events (which use the numbered series). If the numbered series was applied correctly, migration 004 ran and created the current registrations table. The alpha schema registration table either:
- Was never created (if 001_alpha was not applied)
- Was dropped and replaced (if migration tooling handled this)
- Coexists but is orphaned (unlikely given 004 does not use IF NOT EXISTS)

**For Week 3, the numbered series (004) is authoritative.** The existing `registration_repository.py` and `registration_service.py` are alpha-era code that must be fully rewritten for Week 3. Do not attempt to patch them. Write new service and repository files aligned with the 004 schema plus the Week 3 migration columns.

---

## 3. events Table Review

**Source:** `backend/migrations/events_db/001_events.sql`

| Column | Type | Notes |
|---|---|---|
| event_id | SERIAL PK | OK |
| slug | TEXT UNIQUE NOT NULL | OK |
| title | TEXT NOT NULL | OK |
| tagline | TEXT | OK |
| description | TEXT | OK |
| status | VARCHAR(20) DEFAULT 'draft' | draft/published/cancelled/completed |
| start_datetime | TIMESTAMPTZ NOT NULL | OK |
| end_datetime | TIMESTAMPTZ NOT NULL | OK |
| timezone | VARCHAR(60) DEFAULT 'Asia/Kolkata' | OK |
| location_text | TEXT | OK |
| location_maps_url | TEXT | OK |
| is_virtual | BOOLEAN DEFAULT false | OK |
| virtual_url | TEXT | Stored internally, never exposed publicly — CONFIRMED WORKING |
| thumbnail_url | TEXT | OK |
| banner_url | TEXT | OK |
| capacity | INT | NULL = unlimited |
| registration_opens_at | TIMESTAMPTZ | Present — used by computed registration_status |
| registration_closes_at | TIMESTAMPTZ | Present — used by computed registration_status |
| created_by_firebase_uid | VARCHAR(128) NOT NULL | OK |
| created_at | TIMESTAMPTZ DEFAULT now() | OK |
| updated_at | TIMESTAMPTZ | OK |
| published_at | TIMESTAMPTZ | OK |
| cancelled_at | TIMESTAMPTZ | OK |
| cancelled_reason | TEXT | OK |
| show_attendee_list | BOOLEAN DEFAULT false | Added in migration 007 |

**Indexes:**
- idx_events_status ON events(status) — OK
- idx_events_start_datetime ON events(start_datetime) — OK

**Week 3 impact:** No new columns needed on events table. All fields required for registration logic (capacity, registration_opens_at, registration_closes_at, is_virtual, virtual_url, status) are present.

**One gap:** `_validate_for_publish()` in events_service.py requires `capacity` for all events. This means events without capacity cannot be published. For Week 3 registration logic, unlimited capacity events (capacity=NULL) should be allowed. The registered_count cap check must handle NULL capacity correctly:

```python
if capacity is not None and registered >= capacity:
    return "full"
```

This is already correctly handled in `_compute_registration_status()`. No code change needed for this.

---

## 4. registrations Table Review

**Source:** `backend/migrations/events_db/004_registrations_and_check_ins.sql`

### 4.1 Current Columns

| Column | Type | Default | Notes |
|---|---|---|---|
| registration_id | SERIAL PK | | OK |
| event_id | INT NOT NULL FK→events | ON DELETE CASCADE | **Risk: cascade deletes registrations if event deleted. Week 3 uses soft delete only.** |
| firebase_uid | VARCHAR(128) NOT NULL FK→event_users | | OK |
| ref_id | VARCHAR(128) | nullable | alumni_id reference |
| badge_name | TEXT NOT NULL | | **Mismatch: service uses full_name. Must be renamed or service adapted.** |
| email | TEXT NOT NULL | | OK |
| phone | TEXT | | OK |
| attendee_type | VARCHAR(50) | | Not needed for Week 3 |
| status | VARCHAR(20) NOT NULL DEFAULT 'confirmed' | | **WRONG: Week 3 needs 'registered'** |
| qrtoken | TEXT UNIQUE NOT NULL | | **WRONG: service uses qr_token (snake_case). QR is out of scope for Week 3.** |
| confirmation_email_sent | BOOLEAN DEFAULT false | | **Insufficient: Week 3 needs status string + timestamp + error** |
| notes | TEXT | | OK |
| registered_at | TIMESTAMPTZ DEFAULT now() | | OK |
| cancelled_at | TIMESTAMPTZ | | OK |
| UNIQUE (event_id, firebase_uid) | | | **WRONG: blocks reactivation after cancellation** |

### 4.2 Missing Columns (Week 3 Requirements)

The following columns are required by the Week 3 API contract and do not exist:

| Column | Type | Purpose |
|---|---|---|
| registration_number | TEXT UNIQUE | NITKSAA-2026-XXXXXX format, for confirmation |
| fullname_snapshot | TEXT | Alumni name at registration time |
| email_snapshot | TEXT | Alumni email at registration time |
| phone_snapshot | TEXT | Alumni phone at registration time |
| batch_year_snapshot | INT | Alumni graduation year at registration time |
| branch_snapshot | TEXT | Alumni branch at registration time |
| confirmation_email_status | VARCHAR(20) DEFAULT 'pending' | sent / failed / skipped |
| confirmation_email_sent_at | TIMESTAMPTZ | When email was sent |
| confirmation_email_error | TEXT | Error detail if send failed |
| attendee_note | TEXT | Optional note from registrant |
| created_at | TIMESTAMPTZ DEFAULT now() | For audit |
| updated_at | TIMESTAMPTZ | For audit |

### 4.3 Constraint Issues

**UNIQUE (event_id, firebase_uid):**
This hard unique constraint allows only ONE registration row per user per event — ever. If a user cancels and tries to re-register, the INSERT fails with a unique violation.

Week 3 must handle this. Options:
1. Change constraint to a partial unique index: `CREATE UNIQUE INDEX uq_active_reg ON registrations(event_id, firebase_uid) WHERE status = 'registered'`
2. Use UPDATE/reactivation instead of INSERT for returning registrants

Recommended: replace the hard UNIQUE with the partial index. Requires:
```sql
ALTER TABLE registrations DROP CONSTRAINT registrations_event_id_firebase_uid_key;
CREATE UNIQUE INDEX uq_active_registration
ON registrations(event_id, firebase_uid)
WHERE status = 'registered';
```

**status DEFAULT 'confirmed':**
Must be changed to `'registered'` to match the Week 3 contract.

**qrtoken NOT NULL:**
QR is out of scope for Week 3. This column should become nullable via migration. Cannot insert a registration without it under the current constraint.

### 4.4 Week 3 Migration Requirements

A new migration file is required: `008_week3_registrations.sql`

This migration must:

```sql
-- Drop hard unique constraint
ALTER TABLE registrations DROP CONSTRAINT registrations_event_id_firebase_uid_key;

-- Fix status default
ALTER TABLE registrations ALTER COLUMN status SET DEFAULT 'registered';

-- Make qrtoken nullable (QR deferred)
ALTER TABLE registrations ALTER COLUMN qrtoken DROP NOT NULL;

-- Rename badge_name to fullname_snapshot (or add fullname_snapshot separately)
-- Option A: rename existing column
ALTER TABLE registrations RENAME COLUMN badge_name TO fullname_snapshot;

-- Add missing Week 3 columns
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS registration_number TEXT;
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS email_snapshot TEXT;
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS phone_snapshot TEXT;
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS batch_year_snapshot INT;
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS branch_snapshot TEXT;
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS confirmation_email_status VARCHAR(20) DEFAULT 'pending';
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS confirmation_email_sent_at TIMESTAMPTZ;
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS confirmation_email_error TEXT;
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS attendee_note TEXT;
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- Partial unique index for active registrations
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_registration
ON registrations(event_id, firebase_uid)
WHERE status = 'registered';

-- Unique index for registration_number
CREATE UNIQUE INDEX IF NOT EXISTS uq_registration_number
ON registrations(registration_number)
WHERE registration_number IS NOT NULL;
```

---

## 5. event_users Table Review

**Source:** `backend/migrations/events_db/003_event_users_and_event_members.sql`

| Column | Type | Notes |
|---|---|---|
| firebase_uid | VARCHAR(128) PK | OK |
| email | TEXT NOT NULL | OK |
| fullname | TEXT NOT NULL | OK |
| user_type | VARCHAR(20) DEFAULT 'alumni' | alumni / other — used for alumni check |
| ref_id | TEXT | alumni_db.alumni_id — set during login |
| graduation_year | INT | Stored as graduation_year, API contract uses batch_year |
| is_suspended | BOOLEAN DEFAULT false | Used for suspension check |
| created_at | TIMESTAMPTZ NOT NULL | OK |
| last_login | TIMESTAMPTZ | OK |

**Indexes:** email, ref_id, user_type — all present.

**Week 3 issues:**
1. `graduation_year` vs `batch_year`: The API contract's `/alumni/me` response uses `batch_year`. The event_users table stores `graduation_year`. Mapping required in service layer. alumni_db also uses `graduationyear`. Consistent mapping: `graduationyear` → `batch_year` in API responses.

2. `ref_id` is nullable. Non-alumni users (user_type='other') will have ref_id=NULL. Registration endpoint must reject users with NULL ref_id or user_type != 'alumni'.

3. The `_upsert_event_user()` function in auth.py does NOT update user_type or ref_id on conflict. This means if a user first logged in before their alumni record was found (e.g., alumni_db was unreachable), they'd remain as user_type='other' with ref_id=NULL on all subsequent logins. This could block alumni from registering. **Risk: LOW for normal cases; potential edge case.**

---

## 6. event_members Table Review

**Source:** `backend/migrations/events_db/003_event_users_and_event_members.sql`

| Column | Type | Notes |
|---|---|---|
| event_id | INT FK→events ON DELETE CASCADE | |
| firebase_uid | VARCHAR(128) FK→event_users ON DELETE CASCADE | |
| role | VARCHAR(30) NOT NULL | organizer, volunteer, etc. |
| status | VARCHAR(20) DEFAULT 'active' | |
| joined_at | TIMESTAMPTZ | |

**Purpose:** Staff roles on specific events. Not needed for Week 3 alumni registration.

**Architecture review observation:** This table was called out as undocumented. It is for event-scoped staff/volunteer roles, not alumni attendees. Confirmed not a Week 3 concern.

---

## 7. check_ins Table Review

**Source:** `backend/migrations/events_db/004_registrations_and_check_ins.sql`

| Column | Notes |
|---|---|
| checkin_id | PK |
| registration_id | FK→registrations |
| event_id | FK→events |
| scanned_by | FK→event_users |
| scanned_at | timestamp |
| session_id | FK→sessions, nullable |
| result | success / duplicate / invalid |

**Week 3 status:** Out of scope. Table exists, no changes needed.

---

## 8. event_audit_log Table Review

**Source:** `backend/migrations/events_db/006_audit_notifications.sql`

| Column | Type | Notes |
|---|---|---|
| log_id | BIGSERIAL PK | |
| actor_uid | VARCHAR(128) | nullable |
| event_type | TEXT NOT NULL | action name |
| entity_type | TEXT NOT NULL | 'event', 'registration', etc. |
| entity_id | INTEGER | **Type mismatch: registrations.registration_id is SERIAL (int4), log entity_id is INTEGER — OK** |
| created_at | TIMESTAMPTZ | |

**Week 3 gap:** No `payload` column for structured details (e.g., email error text, registration_number). The architecture recommends audit actions for:
- `registration_created`
- `registration_duplicate_blocked`
- `confirmation_email_sent`
- `confirmation_email_failed`
- `join_link_revealed`

These can be logged with the current schema by using the event_type field. Payload detail should go to application logs rather than the audit table. No schema change required for Week 3.

---

## 9. registered_count Gap

### Current State

In `backend/app/services/events_service.py`:

```python
def _enrich(d: Dict[str, Any]) -> Dict[str, Any]:
    d["registered_count"] = 0   # ← hardcoded placeholder
    d["registration_status"] = _compute_registration_status(d)
    return d
```

The comment in `_with_public_card_metadata()` explicitly says: "Week 2 placeholder, registration integration will replace this in Week 3."

### Week 3 Requirement

The `registered_count` must reflect actual active registrations:

```sql
SELECT COUNT(*) FROM registrations
WHERE event_id = $1 AND status != 'cancelled'
```

### Options for Implementation

**Option A (query per event):** Add a subquery or JOIN to each event fetch.
```sql
SELECT e.*, 
    (SELECT COUNT(*) FROM registrations r 
     WHERE r.event_id = e.event_id AND r.status != 'cancelled') AS registered_count
FROM events e
WHERE ...
```

**Option B (batch fetch):** After fetching event list, run one batch count query.

**Option C (denormalized counter):** Add a `registered_count` column to events, updated atomically on each registration. More complex but faster reads.

Recommendation: Option A (subquery) for simplicity. Acceptable performance for expected event/registration volumes. Do not add denormalized counter for Week 3.

---

## 10. registration_number Generation

No current implementation exists.

Week 3 format: `NITKSAA-2026-XXXXXX` where XXXXXX is the zero-padded registration_id.

Simplest correct implementation:
```python
def generate_registration_number(registration_id: int) -> str:
    return f"NITKSAA-2026-{registration_id:06d}"
```

This should be set immediately after insert (using RETURNING registration_id) and written back to the row:
```sql
UPDATE registrations SET registration_number = $1 WHERE registration_id = $2
```

Or computed at insert time via a trigger, but service-level generation is simpler for Week 3.

---

## 11. Index Gaps

### Missing indexes on registrations

The current migration 004 has:
- idx_registrations_event_id ON registrations(event_id) — OK
- idx_registrations_firebase_uid ON registrations(firebase_uid) — OK
- idx_registrations_qrtoken ON registrations(qrtoken) — less relevant for Week 3
- idx_registrations_status ON registrations(event_id, status) — GOOD for count queries

**Missing for Week 3:**
- Index on `registration_number` — covered by unique index from migration 008
- Index for my-registration lookup: `(firebase_uid, event_id)` — already covered by existing index on firebase_uid

---

## 12. Summary Table

| Schema Item | Status | Action Required |
|---|---|---|
| events table columns | COMPLETE | None for Week 3 |
| registrations status default | WRONG ('confirmed') | Migration 008: change to 'registered' |
| registrations UNIQUE constraint | WRONG (hard unique blocks reactivation) | Migration 008: replace with partial index |
| registrations qrtoken NOT NULL | WRONG (QR deferred) | Migration 008: make nullable |
| registration_number column | MISSING | Migration 008: add column |
| fullname_snapshot column | MISSING | Migration 008: add or rename badge_name |
| email_snapshot column | MISSING | Migration 008: add column |
| phone_snapshot column | MISSING | Migration 008: add column |
| batch_year_snapshot column | MISSING | Migration 008: add column |
| branch_snapshot column | MISSING | Migration 008: add column |
| confirmation_email_status column | MISSING | Migration 008: add column |
| confirmation_email_sent_at column | MISSING | Migration 008: add column |
| confirmation_email_error column | MISSING | Migration 008: add column |
| attendee_note column | MISSING | Migration 008: add column |
| created_at/updated_at on registrations | MISSING | Migration 008: add columns |
| registered_count computation | HARDCODED 0 | EventsService: add live subquery |
| registration_number generation | MISSING | New service function |
| dual schema conflict | CRITICAL | Old service code must be fully rewritten |
| event_users graduation_year naming | MISMATCH vs batch_year | Map in service layer |
| event_audit_log payload | NOT PRESENT | Use application logs for detail |
| check_ins table | OK | No change needed |
| event_members table | OK | No change needed |
| events table | COMPLETE | No change needed |
