# Week 5 — Cloud SQL Migration Execution Checklist

**Date:** 2026-06-26  
**Migrations:** 010, 011, 012, 013  
**Target:** Cloud SQL (PostgreSQL) production instance  
**Status:** NOT YET APPLIED  

---

## Pre-Flight Verification (Run Locally Before Touching Cloud SQL)

- [ ] All four migration files exist locally:
  - `backend/migrations/events_db/010_week5_phase1_event_options.sql`
  - `backend/migrations/events_db/011_week5_people.sql`
  - `backend/migrations/events_db/012_week5_sponsors_partners.sql`
  - `backend/migrations/events_db/013_week5_analytics.sql`
- [ ] All four files are committed to git (verify: `git status backend/migrations/`)
- [ ] All four files are additive only — no DROP, no ALTER of existing columns, no data modification
- [ ] Order is correct: 010 → 011 → 012 → 013 (no cross-dependencies; must run sequentially)
- [ ] Dependency check: 011 references `sessions(session_id)` from migration 002 — sessions table must exist

---

## Step 1 — Take a Database Backup

Before applying any migration, take a snapshot or export of the Cloud SQL instance.

```bash
# Using gcloud (replace with your project/instance names):
gcloud sql export sql [INSTANCE_NAME] gs://[BUCKET]/backup-pre-week5-$(date +%Y%m%d).sql \
  --database=events_db

# Verify export succeeded:
gsutil ls gs://[BUCKET]/
```

**Do not proceed until backup is confirmed.**

---

## Step 2 — Connect to Cloud SQL

Use Cloud SQL Auth Proxy or direct connection (only if Authorized Networks is approved):

```bash
# Option A: Cloud SQL Auth Proxy (recommended)
./cloud-sql-proxy [PROJECT]:[REGION]:[INSTANCE] --port 5433 &

# Then connect:
psql "host=127.0.0.1 port=5433 dbname=events_db user=[DB_USER] sslmode=disable"

# Option B: Direct connection (only if Authorized Networks includes your IP)
psql "host=[CLOUD_SQL_PUBLIC_IP] dbname=events_db user=[DB_USER] sslmode=require"
```

---

## Step 3 — Verify Current Migration State

Before applying, confirm which migrations are already present:

```sql
-- Check existing tables:
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Expected BEFORE Week 5 migrations:
-- events, sessions, event_users, registrations, check_ins, event_audit_log, ...
-- NOT present yet: event_people, session_people, event_sponsors, event_partners, event_activity_log

-- Confirm person_role type does NOT yet exist:
SELECT typname FROM pg_type WHERE typname = 'person_role';
-- Should return 0 rows
```

---

## Step 4 — Apply Migration 010

```sql
-- Connect and apply:
\i backend/migrations/events_db/010_week5_phase1_event_options.sql

-- OR run as single command:
psql [CONNECTION_STRING] -f backend/migrations/events_db/010_week5_phase1_event_options.sql
```

**Verification SQL after 010:**

```sql
-- Verify new columns on events table:
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'events'
  AND column_name IN ('is_full_day', 'is_free', 'ticket_price')
ORDER BY column_name;

-- Expected: 3 rows with correct types and defaults
-- is_free: boolean, DEFAULT true, NOT NULL
-- is_full_day: boolean, DEFAULT false, NOT NULL
-- ticket_price: numeric, nullable

-- Verify existing rows have defaults:
SELECT COUNT(*) as total,
       SUM(CASE WHEN is_full_day IS NOT NULL THEN 1 ELSE 0 END) as have_full_day,
       SUM(CASE WHEN is_free IS NOT NULL THEN 1 ELSE 0 END) as have_is_free
FROM events;
-- total = have_full_day = have_is_free (all rows have defaults)
```

---

## Step 5 — Apply Migration 011 (People)

```bash
psql [CONNECTION_STRING] -f backend/migrations/events_db/011_week5_people.sql
```

**Verification SQL after 011:**

```sql
-- Verify person_role enum:
SELECT enumlabel FROM pg_enum
WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'person_role')
ORDER BY enumsortorder;
-- Expected: HOST, MODERATOR, SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR, ORGANIZER

-- Verify event_people table:
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'event_people'
ORDER BY ordinal_position;
-- Expected: 12 columns including person_id, event_id, role, fullname, is_visible, etc.

-- Verify session_people table:
SELECT COUNT(*) FROM information_schema.tables
WHERE table_name = 'session_people';
-- Expected: 1

-- Verify indexes:
SELECT indexname FROM pg_indexes WHERE tablename IN ('event_people', 'session_people');
-- Expected: idx_event_people_event_id, idx_event_people_visible, idx_session_people_session
```

---

## Step 6 — Apply Migration 012 (Sponsors and Partners)

```bash
psql [CONNECTION_STRING] -f backend/migrations/events_db/012_week5_sponsors_partners.sql
```

**Verification SQL after 012:**

```sql
-- Verify event_sponsors:
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'event_sponsors'
ORDER BY ordinal_position;
-- Expected: 10 columns

-- Verify event_partners:
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'event_partners'
ORDER BY ordinal_position;
-- Expected: 10 columns

-- Verify CHECK constraints:
SELECT conname, consrc
FROM pg_constraint
WHERE conrelid = 'event_sponsors'::regclass AND contype = 'c';
-- Should include sponsor_type IN ('TITLE_SPONSOR', ...)
```

---

## Step 7 — Apply Migration 013 (Analytics)

```bash
psql [CONNECTION_STRING] -f backend/migrations/events_db/013_week5_analytics.sql
```

**Verification SQL after 013:**

```sql
-- Verify event_activity_log:
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'event_activity_log'
ORDER BY ordinal_position;
-- Expected: activity_id (bigint), event_id (nullable), firebase_uid, action_type, source_app, metadata (jsonb), created_at

-- Verify BIGSERIAL (not SERIAL):
SELECT data_type, udt_name
FROM information_schema.columns
WHERE table_name = 'event_activity_log' AND column_name = 'activity_id';
-- Expected: data_type='bigint'

-- Verify ON DELETE SET NULL for event_id FK:
SELECT tc.constraint_name, rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.referential_constraints rc ON tc.constraint_name = rc.constraint_name
WHERE tc.table_name = 'event_activity_log';
-- Expected: delete_rule = 'SET NULL'

-- Verify indexes:
SELECT indexname FROM pg_indexes WHERE tablename = 'event_activity_log';
-- Expected: idx_activity_log_event_id, idx_activity_log_action_type, idx_activity_log_created_at
```

---

## Step 8 — Post-Migration API Smoke Checks

After all migrations applied, deploy and verify the live API:

```bash
# 1. Health check:
curl https://[YOUR_API_HOST]/api/v1/health
# Expected: {"status":"ok","db":"ok"}

# 2. Public event detail returns new arrays:
curl https://[YOUR_API_HOST]/api/v1/events/public/[EVENT_ID]
# Expected: response includes "people":[], "speakers":[], "sponsors":[], "partners":[]

# 3. Admin can create a person (use your JWT):
curl -X POST https://[YOUR_API_HOST]/api/v1/events/[EVENT_ID]/people \
  -H "Authorization: Bearer [TOKEN]" \
  -H "Content-Type: application/json" \
  -d '{"role":"SPEAKER","fullname":"Test Speaker","display_order":0}'
# Expected: 201 Created

# 4. Verify backward compat — existing events have is_full_day, is_free defaults:
curl https://[YOUR_API_HOST]/api/v1/events/public/[OLD_EVENT_ID]
# Expected: is_full_day=false, is_free=true in response
```

---

## Step 9 — Run Week 5 Diagnostics (Development Environment Only)

Diagnostics are dev-only (`APP_ENV=development`). Run against the local backend pointed at Cloud SQL AFTER migrations are applied:

```bash
# Point backend at Cloud SQL temporarily for verification:
EVENTS_DB_URL="[CLOUD_SQL_CONNECTION_STRING]" uvicorn app.main:app --port 8001

# Run all diagnostics:
curl -H "X-Dev-User: admin" http://localhost:8001/api/v1/dev/diagnostics/week5/all

# Expected: status=ok, passed=48, failed=0, warnings=0
```

**Important:** The diagnostics create and cancel test events. This is safe — cancelled events are excluded from public listings. The analytics diagnostic leaves log rows (intentional — append-only table).

---

## Rollback / Risk Notes

| Risk | Mitigation |
|---|---|
| Migration fails mid-run | Each migration is wrapped in BEGIN/COMMIT. Partial failure auto-rolls back the failed migration. Earlier migrations remain applied. |
| `CREATE TYPE person_role` fails if type already exists | Check with `SELECT typname FROM pg_type WHERE typname = 'person_role'` before running 011 |
| `event_people` FK to `events` fails | events table must exist — confirmed by migrations 001/001 |
| `session_people` FK to `sessions` fails | sessions table must exist — confirmed by migration 002 |
| Backend connects to Cloud SQL without new tables | If backend deploys before migrations are applied: `GET /api/v1/events/public/{id}` returns 500 because `event_people` table doesn't exist. Apply migrations first. |

**No rollback migrations are provided.** To reverse:
- Migration 013: `DROP TABLE event_activity_log;`
- Migration 012: `DROP TABLE event_partners; DROP TABLE event_sponsors;`
- Migration 011: `DROP TABLE session_people; DROP TABLE event_people; DROP TYPE person_role;`
- Migration 010: `ALTER TABLE events DROP COLUMN is_full_day; DROP COLUMN is_free; DROP COLUMN ticket_price;`

**Do not run rollbacks on a production instance without product owner approval and another backup.**

---

## Checklist Sign-Off

| Step | Verified by | Date |
|---|---|---|
| Backup taken | | |
| Migration 010 applied and verified | | |
| Migration 011 applied and verified | | |
| Migration 012 applied and verified | | |
| Migration 013 applied and verified | | |
| API smoke checks passed | | |
| Backend deployed with new code | | |
| Week 5 diagnostics passed on Cloud SQL | | |
