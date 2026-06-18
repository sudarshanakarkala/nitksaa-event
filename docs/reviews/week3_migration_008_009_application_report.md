# Week 3 — Migration 008 and 009 Application Report

**Date:** 2026-06-18  
**Database:** `events_db` — PostgreSQL 18.3 (Homebrew, aarch64-apple-darwin25.2.0)  
**Applied by:** `ananth` (local)  
**Status:** PASS — all verifications passed

---

## Summary

Migrations 008 and 009 were applied successfully to `events_db` on 2026-06-18.

- Migration 008 aligned the `registrations` table with the Week 3 contract: 14 existing columns − 1 dropped + 8 added = **21 final columns**.
- Migration 009 added `context JSONB` to `event_audit_log` for structured registration audit entries.
- All existing data is intact (31 events, 4 event_users, 84 audit log rows).
- No existing rows were modified (0 rows in registrations; UPDATE 0 confirmed).
- All 13 specific verification checks passed.

---

## Pre-Flight Results

| Check | Result | Value |
|---|---|---|
| Git branch | PASS | `main` |
| Working tree status | PASS | Untracked files only — no staged or modified files |
| Registrations row count | PASS | `0` |
| DB connection | PASS | `events_db` as `ananth` on PostgreSQL 18.3 |

---

## Commands Run

```bash
# Migration 008
psql "postgresql://ananth@localhost:5432/events_db" \
  -v ON_ERROR_STOP=1 \
  -f backend/migrations/events_db/008_week3_registration_alignment.sql

# Migration 009
psql "postgresql://ananth@localhost:5432/events_db" \
  -v ON_ERROR_STOP=1 \
  -f backend/migrations/events_db/009_add_audit_log_context.sql
```

Both commands used `-v ON_ERROR_STOP=1` to ensure the transaction was rolled back automatically on any error.

---

## Migration 008 Result

**psql output:**
```
BEGIN
ALTER TABLE      ← status DEFAULT changed to 'registered'
UPDATE 0         ← confirmed→registered data migration (0 rows, expected)
ALTER TABLE      ← qrtoken DROP NOT NULL
ALTER TABLE      ← badge_name DROP NOT NULL
ALTER TABLE      ← DROP CONSTRAINT registrations_event_id_firebase_uid_key
CREATE INDEX     ← uq_registrations_active (partial unique)
ALTER TABLE      ← DROP COLUMN confirmation_email_sent
ALTER TABLE      ← ADD COLUMN registration_number
CREATE INDEX     ← uq_registrations_registration_number (partial unique)
ALTER TABLE      ← ADD COLUMN fullname_snapshot
ALTER TABLE      ← ADD COLUMN batch_year_snapshot
ALTER TABLE      ← ADD COLUMN branch_snapshot
ALTER TABLE      ← ADD COLUMN confirmation_email_status
ALTER TABLE      ← ADD COLUMN confirmation_email_sent_at
ALTER TABLE      ← ADD COLUMN confirmation_email_error
ALTER TABLE      ← ADD COLUMN updated_at
COMMIT
```

**Result:** SUCCESS — transaction committed cleanly. `UPDATE 0` on the status migration confirms 0 existing rows, as expected.

---

## Migration 009 Result

**psql output:**
```
BEGIN
ALTER TABLE      ← ADD COLUMN context JSONB to event_audit_log
COMMIT
```

**Result:** SUCCESS — transaction committed cleanly.

---

## Post-Migration Schema Verification

### Registrations Final Column List

**Actual result from `information_schema.columns` — 21 rows confirmed:**

| # | Column | Data Type | Max Len | Default | Nullable |
|---|---|---|---|---|---|
| 1 | `registration_id` | integer | — | `nextval(...)` | NO |
| 2 | `event_id` | integer | — | — | NO |
| 3 | `firebase_uid` | character varying | 128 | — | NO |
| 4 | `ref_id` | character varying | 128 | — | YES |
| 5 | `badge_name` | text | — | — | **YES** ✓ |
| 6 | `email` | text | — | — | NO |
| 7 | `phone` | text | — | — | YES |
| 8 | `attendee_type` | character varying | 50 | — | YES |
| 9 | `status` | character varying | 20 | `'registered'` | NO |
| 10 | `qrtoken` | text | — | — | **YES** ✓ |
| 11 | `notes` | text | — | — | YES |
| 12 | `registered_at` | timestamptz | — | `now()` | NO |
| 13 | `cancelled_at` | timestamptz | — | — | YES |
| 14 | `registration_number` | text | — | — | YES |
| 15 | `fullname_snapshot` | text | — | — | YES |
| 16 | `batch_year_snapshot` | integer | — | — | YES |
| 17 | `branch_snapshot` | text | — | — | YES |
| 18 | `confirmation_email_status` | character varying | 20 | `'pending'` | YES |
| 19 | `confirmation_email_sent_at` | timestamptz | — | — | YES |
| 20 | `confirmation_email_error` | text | — | — | YES |
| 21 | `updated_at` | timestamptz | — | — | YES |

**Column count:** 21 ✓  
**`confirmation_email_sent` absent:** Verified — `COUNT(*) = 0` from `information_schema.columns` ✓

---

## Constraint Verification

**Actual `pg_constraint` result:**

| Constraint | Type | Definition |
|---|---|---|
| `registrations_pkey` | PRIMARY KEY | `PRIMARY KEY (registration_id)` |
| `registrations_event_id_fkey` | FOREIGN KEY | `FOREIGN KEY (event_id) REFERENCES events(event_id) ON DELETE CASCADE` |
| `registrations_firebase_uid_fkey` | FOREIGN KEY | `FOREIGN KEY (firebase_uid) REFERENCES event_users(firebase_uid)` |
| `registrations_qrtoken_key` | UNIQUE | `UNIQUE (qrtoken)` |
| `registrations_registration_id_not_null` | NOT NULL | `NOT NULL registration_id` |
| `registrations_event_id_not_null` | NOT NULL | `NOT NULL event_id` |
| `registrations_firebase_uid_not_null` | NOT NULL | `NOT NULL firebase_uid` |
| `registrations_email_not_null` | NOT NULL | `NOT NULL email` |
| `registrations_status_not_null` | NOT NULL | `NOT NULL status` |
| `registrations_registered_at_not_null` | NOT NULL | `NOT NULL registered_at` |

**Verification checks:**

| Check | Expected | Actual | Result |
|---|---|---|---|
| Hard UNIQUE `registrations_event_id_firebase_uid_key` absent | Absent | Not in pg_constraint | PASS ✓ |
| `registrations_qrtoken_not_null` absent | Absent | Not in pg_constraint | PASS ✓ |
| `registrations_badge_name_not_null` absent | Absent | Not in pg_constraint | PASS ✓ |
| `registrations_confirmation_email_sent_not_null` absent | Absent | Not in pg_constraint | PASS ✓ |
| FKs intact | Present | Both FKs confirmed | PASS ✓ |

---

## Index Verification

**Actual `pg_indexes` result:**

| Index | Type | Definition |
|---|---|---|
| `registrations_pkey` | UNIQUE BTREE | `(registration_id)` |
| `registrations_qrtoken_key` | UNIQUE BTREE | `(qrtoken)` |
| `uq_registrations_active` | **UNIQUE BTREE PARTIAL** | `(event_id, firebase_uid) WHERE status = 'registered'` |
| `uq_registrations_registration_number` | **UNIQUE BTREE PARTIAL** | `(registration_number) WHERE registration_number IS NOT NULL` |
| `idx_registrations_event_id` | BTREE | `(event_id)` |
| `idx_registrations_firebase_uid` | BTREE | `(firebase_uid)` |
| `idx_registrations_qrtoken` | BTREE | `(qrtoken)` |
| `idx_registrations_status` | BTREE | `(event_id, status)` |

**Verification checks:**

| Check | Expected | Actual | Result |
|---|---|---|---|
| `registrations_event_id_firebase_uid_key` absent | Absent | Not in pg_indexes | PASS ✓ |
| `uq_registrations_active` present | `WHERE status = 'registered'` | Confirmed partial unique | PASS ✓ |
| `uq_registrations_registration_number` present | `WHERE NOT NULL` | Confirmed partial unique | PASS ✓ |
| No redundant regular index on `registration_number` | Absent | Not in pg_indexes | PASS ✓ |

---

## event_audit_log Context Verification

**Actual columns in `event_audit_log` after migration 009:**

| Column | Data Type |
|---|---|
| `log_id` | bigint |
| `actor_uid` | character varying |
| `event_type` | text |
| `entity_type` | text |
| `entity_id` | integer |
| `created_at` | timestamptz |
| `context` | **jsonb** |

**Verification:**

| Check | Expected | Actual | Result |
|---|---|---|---|
| `context` column exists | JSONB | jsonb | PASS ✓ |
| Total columns | 7 | 7 | PASS ✓ |
| Existing rows unaffected | 84 | 84 | PASS ✓ |

---

## Row Count Verification

| Table | Before Migrations | After Migrations | Change | Result |
|---|---|---|---|---|
| `registrations` | 0 | 0 | 0 | PASS ✓ |
| `events` | 31 | 31 | 0 | PASS ✓ |
| `event_users` | 4 | 4 | 0 | PASS ✓ |
| `event_audit_log` | 84 | 84 | 0 | PASS ✓ |

---

## All 13 Specific Verification Checks

| # | Check | Expected | Actual | Result |
|---|---|---|---|---|
| 1 | `registrations` has 21 columns | 21 | 21 | PASS ✓ |
| 2 | `confirmation_email_sent` column is absent | Absent | 0 rows in information_schema | PASS ✓ |
| 3 | `status` default is `'registered'` | `'registered'::character varying` | `'registered'::character varying` | PASS ✓ |
| 4 | `qrtoken` is nullable | YES | YES | PASS ✓ |
| 5 | `badge_name` is nullable | YES | YES | PASS ✓ |
| 6 | Hard `UNIQUE(event_id, firebase_uid)` is absent | Absent | Not in pg_constraint | PASS ✓ |
| 7 | `uq_registrations_active` partial unique index exists | Present | `WHERE status = 'registered'` | PASS ✓ |
| 8 | `registration_number` column exists | Present | TEXT, nullable | PASS ✓ |
| 9 | `uq_registrations_registration_number` partial unique exists | Present | `WHERE NOT NULL` | PASS ✓ |
| 10 | `event_audit_log.context` exists | JSONB | jsonb | PASS ✓ |
| 11 | `events` row count unchanged | 31 | 31 | PASS ✓ |
| 12 | `event_users` row count unchanged | 4 | 4 | PASS ✓ |
| 13 | `event_audit_log` row count unchanged | 84 | 84 | PASS ✓ |

**All 13 checks: PASS**

---

## Rollback Risk After Application

| Factor | Risk Level | Notes |
|---|---|---|
| Registrations rows | NONE | Still 0 rows — no re-registration paths exercised |
| Re-add hard UNIQUE constraint | NONE now | Zero rows means no duplicates; risk becomes MEDIUM once registrations exist |
| Re-add qrtoken NOT NULL | NONE now | Zero rows; safe while table is empty |
| Re-add badge_name NOT NULL | NONE now | Zero rows; safe while table is empty |
| Drop new columns | NONE | Always safe regardless of row count |
| Drop audit log context | NONE | Always safe regardless of row count |

**Current rollback risk: NONE**

Rollback SQL is documented in `docs/reviews/week3_migration_008_fix_report.md`. The optimal window for rollback (if needed) is **before any registration data is created**.

---

## PASS / FAIL Status

**PASS**

Both migrations applied successfully. All 13 specific verification checks passed. No data was modified. No errors were raised. The `registrations` table is at the correct 21-column Week 3 schema. `event_audit_log` has the `context` JSONB column.

The database is ready for Phase 2 implementation.

---

## Next Steps

Phase 2 implementation order (do not begin without explicit approval):

```
1. Extend backend/app/services/alumni_service.py
   - Add get_alumni_profile_by_ref_id(ref_id)
   - Add is_alumni_active(registrationstatus) helper

2. Rewrite backend/app/schemas/registrations.py
   - RegisterRequest (attendee_note optional only)
   - RegistrationResponse (21-column schema)
   - RegistrationEligibilityResponse
   - MyRegistrationsListResponse

3. Rewrite backend/app/repositories/registration_repository.py
   - Targeting 21-column schema
   - asyncpg parameter style ($1, $2)
   - count_active_registrations, get_active_registration,
     create_registration, update_registration_number,
     update_email_status, get_my_registrations

4. Create backend/app/services/audit_service.py
   - Async emit() adapter for event_audit_log
   - Writes actor_uid, event_type, entity_type, entity_id, context
   - Must never raise

5. Create backend/app/services/email_service.py
   - EmailService abstraction (EmailMode.LOG / EmailMode.SEND)
   - LocalLogEmailProvider, SendGridEmailProvider stubs
   - Email failure must never raise or rollback registration

6. Rewrite backend/app/services/registration_service.py
   - register_for_event, get_registration_eligibility,
     get_my_event_registration, list_my_registrations
   - Transaction: SELECT FOR UPDATE event → count → validate → INSERT

7. Create backend/app/api/alumni.py
   - GET /api/v1/alumni/me

8. Create backend/app/api/registrations.py
   - POST /api/v1/events/{event_id}/register
   - GET  /api/v1/events/{event_id}/my-registration
   - GET  /api/v1/my/registrations

9. Fix registered_count in backend/app/services/events_service.py
   - Query: SELECT COUNT(*) FROM registrations
     WHERE event_id = $1 AND status = 'registered'

10. Register new routers in backend/app/main.py

11. Extend backend/app/api/dev_diagnostics.py
    - Registration category (5 tests)

12. Implement Flutter registration diagnostic items
    - developer_diagnostics_screen.dart
```
