# Week 5 — Cloud DB Migration and Validation Plan

**Date:** 2026-06-26
**Status:** PLAN — awaiting explicit approval before any migration is executed
**Scope:** events_db (owned), alumni_db (read-only consumer)

---

## Safety Rules

- Do NOT run any command against production without an approved Cloud SQL backup/snapshot.
- Do NOT run nitksaa-event migrations on alumni_db. alumni_db is read-only for this service.
- Do NOT create, alter, or drop any table in alumni_db.
- Do NOT commit or print secrets (EVENTS_DB_URL, ALUMNI_DB_URL, DB_PASSWORD, etc.).
- Do NOT execute local Windows `psql` commands directly on a remote Cloud SQL instance without the Cloud SQL Auth Proxy or an equivalent secure tunnel.
- Stop and report if any pre-flight check fails; do not proceed.

---

## Part 1 — events_db Migration

### Step 1.1 — Confirm Environment

Before running anything, record and confirm:

| Item | Question to answer |
|---|---|
| Target environment | local / staging / production? |
| Cloud SQL instance name | e.g. `nitksaa-event:asia-south1:events-db-prod` |
| Database name | Expected: `events_db` |
| DB user | Expected: a non-superuser application user |
| DB host | Via Cloud SQL Auth Proxy: `127.0.0.1:5433`, or direct internal IP |
| SSL mode | Must be `require` or `verify-ca` for staging/production |
| EVENTS_DB_URL set? | Confirm env var is present and points to correct instance |

Do not proceed to Step 1.2 until all fields above are recorded.

---

### Step 1.2 — Pre-Migration Safety Checks (run manually, record output)

**1. Take a Cloud SQL backup or on-demand snapshot before any migration.**

```
# GCP Console → Cloud SQL → [instance] → Backups → Create Backup
# OR via gcloud:
gcloud sql backups create --instance=[INSTANCE_NAME] --project=[PROJECT_ID]
```

Record the backup ID and timestamp in the validation report.

**2. Record current table inventory.**

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

Document the output. If tables already exist (prior partial migration), compare against
the expected final state before proceeding.

**3. Record current row counts for any existing tables.**

```sql
SELECT
    'events'                  AS t, COUNT(*) FROM events
UNION ALL SELECT 'sessions',         COUNT(*) FROM sessions
UNION ALL SELECT 'event_users',      COUNT(*) FROM event_users
UNION ALL SELECT 'event_members',    COUNT(*) FROM event_members
UNION ALL SELECT 'registrations',    COUNT(*) FROM registrations
UNION ALL SELECT 'check_ins',        COUNT(*) FROM check_ins
UNION ALL SELECT 'event_audit_log',  COUNT(*) FROM event_audit_log
UNION ALL SELECT 'notifications',    COUNT(*) FROM notifications;
```

If any table does not yet exist, the query will fail for that table — that is expected for a
fresh instance. Record which tables are missing.

**4. Record the migration files to apply (in order).**

Canonical migration sequence (all files located in `backend/migrations/events_db/`):

| # | Filename | Creates / Alters |
|---|---|---|
| 001 | `001_events.sql` | `events` table |
| 002 | `002_sessions.sql` | `sessions` table |
| 003 | `003_event_users_and_event_members.sql` | `event_users`, `event_members` tables |
| 004 | `004_registrations_and_check_ins.sql` | `registrations`, `check_ins` tables |
| 005 | `005_event_content.sql` | `event_content` table |
| 006 | `006_audit_notifications.sql` | `event_audit_log`, `notifications`, `notification_preferences` tables |
| 007 | `007_add_show_attendee_list.sql` | Adds `show_attendee_list` column to `events` |
| 008 | `008_week3_registration_alignment.sql` | Alters `registrations`: 8 columns added, 1 dropped, 2 indices changed, status default changed |
| 009 | `009_add_audit_log_context.sql` | Adds `context JSONB` column to `event_audit_log` |

> **WARNING — Duplicate 001 file:** The migrations directory contains both
> `001_create_events_alpha_schema.sql` and `001_events.sql`. The canonical file is
> `001_events.sql`. `001_create_events_alpha_schema.sql` is an archived alpha draft.
> **Never apply both.** Confirm which file was applied previously (if any) before proceeding.
> If the instance is fresh, apply only `001_events.sql`.

---

### Step 1.3 — Apply Migrations in Order

Apply only files not already applied. Each migration is wrapped in a `BEGIN / COMMIT` block.
If a migration fails, the transaction rolls back automatically. Record success or failure for
each step.

**Method (via psql with Cloud SQL Auth Proxy):**

```bash
# Replace placeholders — do NOT hardcode passwords in shell history
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/001_events.sql
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/002_sessions.sql
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/003_event_users_and_event_members.sql
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/004_registrations_and_check_ins.sql
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/005_event_content.sql
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/006_audit_notifications.sql
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/007_add_show_attendee_list.sql
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/008_week3_registration_alignment.sql
psql "$EVENTS_DB_URL" -f backend/migrations/events_db/009_add_audit_log_context.sql
```

**Pre-flight check for migration 008** (required before applying 008):

```sql
-- Must complete before applying 008_week3_registration_alignment.sql
SELECT COUNT(*) FROM registrations;
-- Expected for fresh staging: 0

SELECT status, COUNT(*) FROM registrations GROUP BY status;
-- Expected for fresh staging: (0 rows)

SELECT COUNT(*) FROM registrations
WHERE status NOT IN ('confirmed', 'registered', 'cancelled');
-- Must return 0. Any unknown status values must be handled manually first.
```

**Pre-flight check for migration 009** (required before applying 009):

```sql
SELECT COUNT(*) FROM event_audit_log;
-- Document count. Existing rows will have context = NULL after migration.
```

---

### Step 1.4 — Post-Migration Schema Verification (events_db)

Run all of the following after all 9 migrations have been applied. Record each result.

#### 1.4.1 — Table Inventory

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

**Expected tables (10 total):**

| Expected table |
|---|
| check_ins |
| event_audit_log |
| event_content |
| event_members |
| event_users |
| events |
| notifications |
| notification_preferences |
| registrations |
| sessions |

#### 1.4.2 — events table

```sql
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'events'
ORDER BY ordinal_position;
```

**Key columns to verify:**

| Column | Type | Notes |
|---|---|---|
| event_id | integer | PK, serial |
| slug | text | UNIQUE NOT NULL |
| title | text | NOT NULL |
| status | varchar(20) | DEFAULT 'draft' |
| start_datetime | timestamptz | NOT NULL |
| end_datetime | timestamptz | NOT NULL |
| timezone | varchar(60) | DEFAULT 'Asia/Kolkata' |
| is_virtual | boolean | DEFAULT false |
| capacity | integer | nullable (NULL = unlimited) |
| registration_opens_at | timestamptz | nullable |
| registration_closes_at | timestamptz | nullable |
| show_attendee_list | boolean | DEFAULT false — added by 007 |

#### 1.4.3 — sessions table

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'sessions'
ORDER BY ordinal_position;
```

Expected columns: `session_id, event_id, track, title, description, start_datetime,
end_datetime, location_text, speaker_name, speaker_bio, speaker_photo_url, sort_order,
created_at`

#### 1.4.4 — event_users and event_members tables

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('event_users', 'event_members')
ORDER BY table_name, ordinal_position;
```

event_users expected: `firebase_uid, email, fullname, user_type, ref_id, graduation_year,
is_suspended, created_at, last_login`

event_members expected: `event_id, firebase_uid, role, added_at`

#### 1.4.5 — registrations table (Week 3 alignment — critical)

```sql
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'registrations'
ORDER BY ordinal_position;
```

**Expected: 21 columns total after migration 008.**

Critical columns added by 008:

| Column | Type | Default | Notes |
|---|---|---|---|
| registration_number | text | — | nullable until post-INSERT UPDATE |
| fullname_snapshot | text | — | alumni name at registration time |
| batch_year_snapshot | integer | — | graduationyear at registration time |
| branch_snapshot | text | — | branch at registration time |
| confirmation_email_status | varchar(20) | 'pending' | values: pending/sent/failed/skipped |
| confirmation_email_sent_at | timestamptz | — | nullable |
| confirmation_email_error | text | — | nullable |
| updated_at | timestamptz | — | nullable |

Critical changes from 008:

```sql
-- status DEFAULT must be 'registered' (not 'confirmed')
SELECT column_default FROM information_schema.columns
WHERE table_name = 'registrations' AND column_name = 'status';
-- Expected: 'registered'::character varying

-- confirmation_email_sent must be GONE
SELECT COUNT(*) FROM information_schema.columns
WHERE table_name = 'registrations' AND column_name = 'confirmation_email_sent';
-- Expected: 0

-- qrtoken must be nullable
SELECT is_nullable FROM information_schema.columns
WHERE table_name = 'registrations' AND column_name = 'qrtoken';
-- Expected: YES

-- Hard unique constraint must be ABSENT
SELECT COUNT(*) FROM pg_constraint
WHERE conname = 'registrations_event_id_firebase_uid_key';
-- Expected: 0

-- Partial unique index on active registrations must EXIST
SELECT indexname, indexdef FROM pg_indexes
WHERE tablename = 'registrations' AND indexname = 'uq_registrations_active';
-- Expected: present, WHERE clause = (status = 'registered')

-- Partial unique index on registration_number must EXIST
SELECT indexname FROM pg_indexes
WHERE tablename = 'registrations'
  AND indexname = 'uq_registrations_registration_number';
-- Expected: present
```

#### 1.4.6 — check_ins table

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'check_ins'
ORDER BY ordinal_position;
```

#### 1.4.7 — event_audit_log table (Week 3 — context column)

```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'event_audit_log'
ORDER BY ordinal_position;
```

Expected columns: `log_id, actor_uid, event_type, entity_type, entity_id, created_at, context`

`context` column must be present with type `jsonb` — added by migration 009.

#### 1.4.8 — notifications and notification_preferences tables

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('notifications', 'notification_preferences')
ORDER BY table_name, ordinal_position;
```

notifications expected: `notification_id, firebase_uid, event_type, entity_type, entity_id,
is_read, created_at`

notification_preferences expected: `firebase_uid, event_type, push_enabled`  (PK on both)

---

## Part 2 — alumni_db Validation

### Step 2.1 — Confirm Read-Only Configuration

Verify before any test:

| Item | Check |
|---|---|
| ALUMNI_DB_URL | Points to staging/production alumni_db, not events_db |
| DB user | Must have SELECT-only privilege; must NOT have INSERT/UPDATE/DELETE/DDL |
| SSL mode | Must be `require` or `verify-ca` — never `disable` for remote Cloud SQL |
| Application code | All alumni_db queries in `alumni_service.py` are SELECT only |

**Verify DB user privileges (run as superuser on alumni_db):**

```sql
-- Substitute actual username
SELECT grantee, privilege_type, table_name
FROM information_schema.role_table_grants
WHERE grantee = '<alumni_db_app_user>'
  AND table_name = 'alumni'
ORDER BY privilege_type;
-- Must show only SELECT. INSERT/UPDATE/DELETE/TRUNCATE must be absent.
```

### Step 2.2 — Alumni Lookup Validation

These queries simulate what the application does. Run against staging alumni_db only.

**Active alumni lookup (registration permitted):**

```sql
-- Substitute a known active alumni email
SELECT alumni_id, fullname, graduationyear, branch, registrationstatus
FROM alumni
WHERE lower(email) = lower('<active_alumni_email>')
LIMIT 1;
-- Expected: 1 row, registrationstatus IN ('Active', 'Self-Verified')
```

**Inactive alumni lookup (registration must be blocked):**

```sql
-- Substitute a known inactive alumni email (if available in staging)
SELECT alumni_id, fullname, registrationstatus
FROM alumni
WHERE lower(email) = lower('<inactive_alumni_email>')
LIMIT 1;
-- Expected: 1 row, registrationstatus NOT IN ('Active', 'Self-Verified')
-- Application must reject registration for this user.
```

**Missing alumni lookup (non-existent email):**

```sql
SELECT COUNT(*) FROM alumni
WHERE lower(email) = lower('nonexistent_test_9999@example.com');
-- Expected: 0
-- Application must return 404 for this case.
```

**Email normalisation check:**

```sql
-- Verify LOWER(TRIM(email)) lookup works correctly
SELECT COUNT(*) FROM alumni
WHERE lower(trim(email)) = lower(trim('<known_active_email>'));
-- Expected: same result as the plain lower() query above
```

**Profile fields used at registration (ref_id lookup):**

```sql
-- Substitute a known alumni_id (ref_id)
SELECT alumni_id, fullname, email, phone, graduationyear, branch,
       registrationstatus, firebase_uid
FROM alumni
WHERE alumni_id = '<known_alumni_id>'
LIMIT 1;
-- All 8 columns must be present. This matches get_alumni_profile_by_ref_id().
```

---

## Part 3 — Backend API Verification (staging only)

All endpoint tests must run against staging. Do NOT run create/publish/register/export
operations against production.

### Step 3.1 — Health and Public Endpoints

```bash
# Health check — events_db connectivity
curl -s https://<staging-host>/api/v1/health
# Expected: {"status":"ok","version":"...","env":"staging","db":"ok"}

# Public events list
curl -s https://<staging-host>/api/v1/events/public
# Expected: 200 OK, JSON array (may be empty if no published events yet)
```

### Step 3.2 — Admin Event Lifecycle (staging only)

These steps require admin credentials. Run in this order:

1. **Create a draft event** — POST `/api/v1/admin/events` with valid payload
2. **Verify it appears** in admin events list — GET `/api/v1/admin/events`
3. **Publish the event** — POST `/api/v1/admin/events/{id}/publish`
4. **Verify it appears** in the public list — GET `/api/v1/events`
5. **Confirm audit log** recorded `published` entry:
   ```sql
   SELECT * FROM event_audit_log ORDER BY created_at DESC LIMIT 5;
   ```

### Step 3.3 — Alumni Endpoints (staging only)

```bash
# Alumni profile (requires valid JWT)
curl -s -H "Authorization: Bearer <token>" https://<staging-host>/api/v1/alumni/me
# Expected: 200 with alumni profile fields; registrationstatus visible

# Registration (requires active alumni JWT and a published event)
curl -s -X POST -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"attendee_note": "Staging test registration"}' \
     https://<staging-host>/api/v1/events/{id}/register
# Expected: 201 with registration_number (NITKSAA-YYYY-NNNNNN format)
# Verify row in registrations table:
#   SELECT registration_number, status, fullname_snapshot, batch_year_snapshot,
#          branch_snapshot, confirmation_email_status
#   FROM registrations ORDER BY registered_at DESC LIMIT 1;
```

### Step 3.4 — Attendee Export (staging only)

```bash
# Requires admin credentials
curl -s -H "Authorization: Bearer <admin-token>" \
     https://<staging-host>/api/v1/admin/events/{id}/attendees/export
# Expected: 200 CSV or JSON with registered attendees
# Verify exported row includes fullname_snapshot, batch_year_snapshot, branch_snapshot
```

---

## Part 4 — Rollback Reference

These rollbacks are safe only while their respective tables have zero live data.

| Migration | Rollback SQL |
|---|---|
| 009 | `ALTER TABLE event_audit_log DROP COLUMN IF EXISTS context;` |
| 008 | See `docs/reviews/old_reviews/week3_migration_008_fix_report.md` — Rollback Notes section. **WARNING:** Only safe while `registrations` is empty. |
| 007 | `ALTER TABLE events DROP COLUMN IF EXISTS show_attendee_list;` |
| 006 | `DROP TABLE IF EXISTS notification_preferences, notifications, event_audit_log;` |
| 005 | `DROP TABLE IF EXISTS event_content;` |
| 004 | `DROP TABLE IF EXISTS check_ins, registrations;` |
| 003 | `DROP TABLE IF EXISTS event_members, event_users;` |
| 002 | `DROP TABLE IF EXISTS sessions;` |
| 001 | `DROP TABLE IF EXISTS events;` |

---

## Part 5 — Validation Report Template

After testing, fill in `docs/reviews/week5_cloud_db_validation_report.md` with the following
sections:

1. **Environment confirmed** — instance name, DB name, user, SSL mode, backup ID/timestamp
2. **Pre-migration table inventory** — output of table list query
3. **Migrations applied** — filename, applied at timestamp, success/failure
4. **Post-migration schema verification** — results of each 1.4.x check
5. **alumni_db validation** — results of each 2.2 query
6. **API verification** — endpoint results and curl responses
7. **Issues encountered** — any deviations, errors, or unexpected state
8. **Sign-off** — who ran it, when, what environment

---

## Checklist Summary

### events_db

- [ ] Environment (instance, DB name, user, SSL) confirmed and recorded
- [ ] Cloud SQL backup/snapshot taken and backup ID recorded
- [ ] Pre-migration table inventory recorded
- [ ] Pre-migration row counts recorded
- [ ] Duplicate 001 file situation confirmed — only `001_events.sql` in scope
- [ ] Migrations 001–009 applied in order, each confirmed successful
- [ ] Pre-flight check for 008 passed (0 rows in unexpected status)
- [ ] Pre-flight check for 009 passed (audit log row count documented)
- [ ] Post-migration: 10 tables present
- [ ] `events` table: `show_attendee_list` column present (007)
- [ ] `registrations` table: 21 columns, status default = 'registered', qrtoken nullable
- [ ] `registrations` table: `confirmation_email_sent` column absent
- [ ] `registrations` table: hard unique constraint absent
- [ ] `registrations` table: `uq_registrations_active` partial index present
- [ ] `registrations` table: `uq_registrations_registration_number` partial index present
- [ ] `event_audit_log` table: `context` JSONB column present (009)

### alumni_db

- [ ] ALUMNI_DB_URL confirmed pointing to correct alumni_db instance
- [ ] DB user confirmed SELECT-only
- [ ] SSL mode confirmed `require` or `verify-ca`
- [ ] Active alumni lookup returns correct row
- [ ] Inactive alumni lookup returns row with non-active status
- [ ] Missing alumni returns 0 rows
- [ ] Email normalisation LOWER(TRIM()) verified
- [ ] ref_id lookup returns all 8 required profile fields

### Backend API (staging only)

- [ ] GET /api/v1/health → `{"status":"ok","db":"ok"}`
- [ ] GET /api/v1/events/public → 200 OK (JSON array)
- [ ] Create draft event in staging → success
- [ ] Publish event in staging → success, audit log entry created
- [ ] GET /api/v1/alumni/me → alumni profile returned
- [ ] POST /api/v1/events/{id}/register → 201 with registration_number
- [ ] Registration row confirmed in DB with snapshot fields populated
- [ ] Attendee export confirmed with snapshot fields

---

*Stop here. Do not execute any migration or API call until explicitly approved.*
*After testing is approved and complete, fill in `week5_cloud_db_validation_report.md`.*
