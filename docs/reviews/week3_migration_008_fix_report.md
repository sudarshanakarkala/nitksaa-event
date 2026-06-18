# Week 3 — Migration 008 Fix Report

**Date:** 2026-06-18  
**Based on:** `docs/reviews/week3_migration_008_verification_report.md`  
**Status:** PASS — all required and recommended changes applied

---

## Summary

Migration 008 has been corrected and migration 009 has been created. All 3 required changes (F-1, F-2, F-3) and all 4 recommended cleanup changes (R-4 through R-7) from the verification report have been applied.

The `registrations` table will have **21 columns** after migration 008 is applied:  
14 existing − 1 dropped + 8 added = 21.

Both migration files are ready for review and application. Neither has been applied to the database yet.

---

## Files Modified

| File | Action |
|---|---|
| `backend/migrations/events_db/008_week3_registration_alignment.sql` | Rewritten — all required and recommended changes applied |
| `backend/migrations/events_db/009_add_audit_log_context.sql` | Created — extracted from migration 008 |

---

## Required Changes Applied

### F-1 — Drop `confirmation_email_sent` boolean (HIGH)

**Problem:** Migration 008 added 3-column email tracking (`confirmation_email_status`, `confirmation_email_sent_at`, `confirmation_email_error`) but kept the existing `confirmation_email_sent BOOLEAN NOT NULL DEFAULT false`. This would create a dual-state inconsistency where the service must maintain two representations of the same fact.

**Fix applied:** Added Step 6 to migration 008:
```sql
ALTER TABLE registrations
    DROP COLUMN IF EXISTS confirmation_email_sent;
```

This executes before the new email tracking columns are added. No existing rows are affected (0 rows in table).

---

### F-2 — Remove `created_at` (MEDIUM)

**Problem:** `registered_at TIMESTAMPTZ NOT NULL DEFAULT now()` already exists and has identical semantics for any new INSERT. Adding `created_at` with the same default creates two columns with the same value, inviting future inconsistency.

**Fix applied:** Removed `ADD COLUMN created_at` entirely from Step 10. Only `updated_at` is added. The migration comment documents this decision:

```
-- registered_at serves as the INSERT timestamp.
```

---

### F-3 — Move `event_audit_log.context` to migration 009 (LOW)

**Problem:** Adding a column to `event_audit_log` inside a migration named `008_week3_registration_alignment.sql` mixed rollback boundaries. A rollback of registration schema changes would also undo the audit log change even if the audit log change itself was sound.

**Fix applied:** Removed Step 11 (event_audit_log.context) from migration 008 entirely. Created `009_add_audit_log_context.sql` as a standalone migration.

---

## Recommended Cleanup Applied

### R-4 — Remove redundant regular index on `registration_number`

**Problem:** `idx_registrations_registration_number` (regular index) was redundant with `uq_registrations_registration_number WHERE registration_number IS NOT NULL` (partial unique index). Any lookup by a specific registration number uses the partial unique index. The regular index added write overhead with no query benefit.

**Fix applied:** Removed `CREATE INDEX idx_registrations_registration_number` from Step 7. Only the partial unique index is created:
```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_registrations_registration_number
    ON registrations (registration_number)
    WHERE registration_number IS NOT NULL;
```

---

### R-5 — Remove `email_snapshot` (reuse `registrations.email`)

**Problem:** `registrations.email TEXT NOT NULL` already exists (migration 004). Adding `email_snapshot` would store the same value in two columns.

**Fix applied:** Removed `ADD COLUMN email_snapshot` from migration 008. The registration service populates the existing `email` column from `alumni_db.alumni.email` at INSERT time.

---

### R-6 — Remove `phone_snapshot` (reuse `registrations.phone`)

**Problem:** `registrations.phone TEXT` (nullable) already exists (migration 004). Adding `phone_snapshot` would duplicate the value.

**Fix applied:** Removed `ADD COLUMN phone_snapshot` from migration 008. The registration service populates the existing `phone` column from `alumni_db.alumni.phone` at INSERT time.

---

### R-7 — Remove `attendee_note` (reuse `registrations.notes`)

**Problem:** `registrations.notes TEXT` (nullable) already exists (migration 004). Adding `attendee_note` would store the same registrant-supplied text in a second column.

**Fix applied:** Removed `ADD COLUMN attendee_note` from migration 008. The registration service maps `RegisterRequest.attendee_note` → `registrations.notes` in the repository layer. The API request field name (`attendee_note`) does not need to match the DB column name (`notes`).

---

## Final Registration Column List

**After migration 008 is applied — 21 columns total:**

| # | Column | Type | Nullable | Source |
|---|---|---|---|---|
| 1 | `registration_id` | integer | NO | Existing (migration 004) |
| 2 | `event_id` | integer | NO | Existing (migration 004) |
| 3 | `firebase_uid` | varchar(128) | NO | Existing (migration 004) |
| 4 | `ref_id` | varchar(128) | YES | Existing (migration 004) |
| 5 | `badge_name` | text | **YES** | Existing — NOT NULL dropped by 008 |
| 6 | `email` | text | NO | Existing — populated from alumni_db |
| 7 | `phone` | text | YES | Existing — populated from alumni_db |
| 8 | `attendee_type` | varchar(50) | YES | Existing (migration 004) |
| 9 | `status` | varchar(20) | NO | Existing — DEFAULT changed to 'registered' |
| 10 | `qrtoken` | text | **YES** | Existing — NOT NULL dropped by 008 |
| 11 | `notes` | text | YES | Existing — receives `attendee_note` from request |
| 12 | `registered_at` | timestamptz | NO | Existing — serves as INSERT timestamp |
| 13 | `cancelled_at` | timestamptz | YES | Existing (migration 004) |
| 14 | `registration_number` | text | YES | **NEW** — set immediately after INSERT |
| 15 | `fullname_snapshot` | text | YES | **NEW** — from alumni_db.fullname |
| 16 | `batch_year_snapshot` | integer | YES | **NEW** — from alumni_db.graduationyear |
| 17 | `branch_snapshot` | text | YES | **NEW** — from alumni_db.branch |
| 18 | `confirmation_email_status` | varchar(20) | YES | **NEW** — pending/sent/failed/skipped |
| 19 | `confirmation_email_sent_at` | timestamptz | YES | **NEW** — set after email attempt |
| 20 | `confirmation_email_error` | text | YES | **NEW** — error message if failed |
| 21 | `updated_at` | timestamptz | YES | **NEW** — set on any post-INSERT modification |

**Dropped column (not in final table):**

| Column | Was | Replaced by |
|---|---|---|
| `confirmation_email_sent` | boolean NOT NULL DEFAULT false | `confirmation_email_status` + `sent_at` + `error` |

---

## Migration 008 SQL Summary

**File:** `backend/migrations/events_db/008_week3_registration_alignment.sql`

| Step | Operation | SQL |
|---|---|---|
| 1 | Change status DEFAULT | `ALTER COLUMN status SET DEFAULT 'registered'` |
| 1 | Migrate existing rows | `UPDATE ... SET status = 'registered' WHERE status = 'confirmed'` |
| 2 | Make qrtoken nullable | `ALTER COLUMN qrtoken DROP NOT NULL` |
| 3 | Make badge_name nullable | `ALTER COLUMN badge_name DROP NOT NULL` |
| 4 | Drop hard unique | `DROP CONSTRAINT IF EXISTS registrations_event_id_firebase_uid_key` |
| 5 | Add partial unique | `CREATE UNIQUE INDEX uq_registrations_active ... WHERE status = 'registered'` |
| 6 | Drop boolean | `DROP COLUMN IF EXISTS confirmation_email_sent` |
| 7 | Add registration_number | `ADD COLUMN registration_number TEXT` |
| 7 | Add partial unique on number | `CREATE UNIQUE INDEX uq_registrations_registration_number ... WHERE NOT NULL` |
| 8 | Add fullname_snapshot | `ADD COLUMN fullname_snapshot TEXT` |
| 9 | Add batch_year_snapshot | `ADD COLUMN batch_year_snapshot INTEGER` |
| 10 | Add branch_snapshot | `ADD COLUMN branch_snapshot TEXT` |
| 11 | Add email status | `ADD COLUMN confirmation_email_status VARCHAR(20) DEFAULT 'pending'` |
| 12 | Add email sent_at | `ADD COLUMN confirmation_email_sent_at TIMESTAMPTZ` |
| 13 | Add email error | `ADD COLUMN confirmation_email_error TEXT` |
| 14 | Add updated_at | `ADD COLUMN updated_at TIMESTAMPTZ` |

All operations are inside a single `BEGIN; ... COMMIT;` transaction.

---

## Migration 009 SQL Summary

**File:** `backend/migrations/events_db/009_add_audit_log_context.sql`

| Step | Operation | SQL |
|---|---|---|
| 1 | Add context to audit log | `ALTER TABLE event_audit_log ADD COLUMN IF NOT EXISTS context JSONB` |

Single operation inside `BEGIN; ... COMMIT;`. Existing 84 rows in `event_audit_log` are unaffected — `context` will be NULL for all of them.

Security constraint documented in migration header: never write PII (firebase_uid, email, phone) or join URLs into the context column.

---

## Rollback Notes

### Rollback migration 009

```sql
BEGIN;
ALTER TABLE event_audit_log DROP COLUMN IF EXISTS context;
COMMIT;
```

Risk: **NONE** — additive column, DROP is always safe.

---

### Rollback migration 008

Apply in reverse step order:

```sql
BEGIN;

-- Reverse Step 14
ALTER TABLE registrations DROP COLUMN IF EXISTS updated_at;

-- Reverse Steps 11-13
ALTER TABLE registrations DROP COLUMN IF EXISTS confirmation_email_error;
ALTER TABLE registrations DROP COLUMN IF EXISTS confirmation_email_sent_at;
ALTER TABLE registrations DROP COLUMN IF EXISTS confirmation_email_status;

-- Reverse Steps 8-10
ALTER TABLE registrations DROP COLUMN IF EXISTS branch_snapshot;
ALTER TABLE registrations DROP COLUMN IF EXISTS batch_year_snapshot;
ALTER TABLE registrations DROP COLUMN IF EXISTS fullname_snapshot;

-- Reverse Step 7
DROP INDEX IF EXISTS uq_registrations_registration_number;
ALTER TABLE registrations DROP COLUMN IF EXISTS registration_number;

-- Reverse Step 6: restore the boolean (as nullable — rows may have NULL now)
ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS confirmation_email_sent BOOLEAN DEFAULT false;

-- Reverse Step 5
DROP INDEX IF EXISTS uq_registrations_active;

-- Reverse Step 4: WARNING — will fail if re-registration rows exist
-- Check first: SELECT event_id, firebase_uid, COUNT(*)
--              FROM registrations GROUP BY event_id, firebase_uid HAVING COUNT(*) > 1;
ALTER TABLE registrations
    ADD CONSTRAINT registrations_event_id_firebase_uid_key UNIQUE (event_id, firebase_uid);

-- Reverse Step 3: WARNING — will fail if any rows have NULL badge_name
-- Check first: SELECT COUNT(*) FROM registrations WHERE badge_name IS NULL;
ALTER TABLE registrations ALTER COLUMN badge_name SET NOT NULL;

-- Reverse Step 2: WARNING — will fail if any rows have NULL qrtoken
-- Check first: SELECT COUNT(*) FROM registrations WHERE qrtoken IS NULL;
ALTER TABLE registrations ALTER COLUMN qrtoken SET NOT NULL;

-- Reverse Step 1
ALTER TABLE registrations ALTER COLUMN status SET DEFAULT 'confirmed';
-- Only if rows exist: UPDATE registrations SET status = 'confirmed' WHERE status = 'registered';

COMMIT;
```

### Rollback risk assessment

| Change | Risk (now, 0 rows) | Risk (after registrations exist) |
|---|---|---|
| New columns (DROP COLUMN) | NONE | NONE |
| Partial unique index (DROP INDEX) | NONE | NONE |
| DROP confirmation_email_sent (re-add) | NONE | LOW — re-added as nullable |
| Re-add hard UNIQUE constraint | NONE | **MEDIUM** — fails if re-registration rows exist |
| Re-add badge_name NOT NULL | NONE | MEDIUM — fails if NULLs inserted |
| Re-add qrtoken NOT NULL | NONE | MEDIUM — fails if NULLs inserted |
| Status DEFAULT revert | NONE | LOW — UPDATE needed |

**Current rollback risk: NONE** (0 rows in registrations). Apply both migrations now while the table is empty to minimize future rollback complexity.

---

## PASS / FAIL Recommendation

**PASS**

Migration 008 and migration 009 are ready to apply.

All 3 required changes from the verification report have been applied. All 4 recommended cleanup changes have been applied. The migration is transactional (single BEGIN/COMMIT), the changes are sequenced correctly (DROP COLUMN before ADD COLUMN for the email tracking replacement), and the post-migration verification queries are included in the migration file header.

---

## Next Steps

1. Apply migration 008:
   ```bash
   psql "postgresql://ananth@localhost:5432/events_db" \
     < backend/migrations/events_db/008_week3_registration_alignment.sql
   ```

2. Apply migration 009:
   ```bash
   psql "postgresql://ananth@localhost:5432/events_db" \
     < backend/migrations/events_db/009_add_audit_log_context.sql
   ```

3. Run post-migration verification queries from the migration 008 header comment block.

4. Confirm: 21 columns in `registrations`, `context` column in `event_audit_log`, partial unique index present, hard unique constraint absent, `confirmation_email_sent` column absent.

5. Proceed to Phase 2: `alumni_service.py` extension (`get_alumni_profile_by_ref_id`).
