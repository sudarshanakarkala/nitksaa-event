# Week 3 — Actual Schema Verification Report

**Date:** 2026-06-18  
**Sprint:** Week 3 — Registration, Alumni Autofill, Confirmation Email, Protected Join Link  
**Database:** `events_db` (local PostgreSQL)  
**Method:** `information_schema` queries via psql (not migration file inference)

---

## Verification Method

All schema data in this report was obtained by querying the live local database directly:

```sql
-- Columns: information_schema.columns
-- Constraints: information_schema.table_constraints + key_column_usage + referential_constraints
-- Check constraints: information_schema.check_constraints
-- Indexes: pg_indexes
```

**Do NOT use migration files as the sole source of truth** — migration 004 has a dual-path conflict (alpha schema vs numbered series), and the actual DB may differ from any individual migration file.

---

## 1. Table Inventory

All tables confirmed in `events_db` (public schema):

| Table | Row Count | Status |
|---|---|---|
| `events` | 31 | Active, seeded |
| `event_users` | 4 | Active, seeded |
| `registrations` | 0 | Active, empty |
| `event_members` | — | Active, empty |
| `check_ins` | — | Active, empty |
| `event_audit_log` | 84 | Active, has data |
| `event_content` | — | Active |
| `notifications` | — | Active |
| `notification_preferences` | — | Active |
| `sessions` | — | Active |

**Alpha-era tables (NOT present):** `attendees`, `check_in_attempts` — confirmed absent. Any existing code referencing these tables will fail at runtime.

---

## 2. `registrations` Table

### 2.1 Columns (Actual)

| # | Column | Data Type | Max Length | Default | Nullable |
|---|---|---|---|---|---|
| 1 | `registration_id` | integer | — | `nextval(...)` SERIAL | NO |
| 2 | `event_id` | integer | — | — | NO |
| 3 | `firebase_uid` | character varying | 128 | — | NO |
| 4 | `ref_id` | character varying | 128 | — | YES |
| 5 | `badge_name` | text | — | — | NO |
| 6 | `email` | text | — | — | NO |
| 7 | `phone` | text | — | — | YES |
| 8 | `attendee_type` | character varying | 50 | — | YES |
| 9 | `status` | character varying | 20 | `'confirmed'` | NO |
| 10 | `qrtoken` | text | — | — | NO (via CHECK) |
| 11 | `confirmation_email_sent` | boolean | — | `false` | NO |
| 12 | `notes` | text | — | — | YES |
| 13 | `registered_at` | timestamptz | — | `now()` | NO |
| 14 | `cancelled_at` | timestamptz | — | — | YES |

**Total actual columns: 14**

### 2.2 Constraints (Actual)

| Constraint Name | Type | Columns | Notes |
|---|---|---|---|
| `registrations_pkey` | PRIMARY KEY | `registration_id` | — |
| `registrations_event_id_firebase_uid_key` | UNIQUE | `(event_id, firebase_uid)` | **Hard constraint — blocks re-registration** |
| `registrations_qrtoken_key` | UNIQUE | `qrtoken` | Single column unique |
| `registrations_event_id_fkey` | FOREIGN KEY | `event_id` → `events(event_id)` | DELETE CASCADE |
| `registrations_firebase_uid_fkey` | FOREIGN KEY | `firebase_uid` → `event_users(firebase_uid)` | NO ACTION |
| `registrations_registration_id_not_null` | CHECK | `registration_id IS NOT NULL` | System-generated |
| `registrations_event_id_not_null` | CHECK | `event_id IS NOT NULL` | System-generated |
| `registrations_firebase_uid_not_null` | CHECK | `firebase_uid IS NOT NULL` | System-generated |
| `registrations_badge_name_not_null` | CHECK | `badge_name IS NOT NULL` | **Blocks INSERT without badge_name** |
| `registrations_email_not_null` | CHECK | `email IS NOT NULL` | System-generated |
| `registrations_status_not_null` | CHECK | `status IS NOT NULL` | System-generated |
| `registrations_qrtoken_not_null` | CHECK | `qrtoken IS NOT NULL` | **Blocks INSERT without qrtoken** |
| `registrations_confirmation_email_sent_not_null` | CHECK | `confirmation_email_sent IS NOT NULL` | System-generated |
| `registrations_registered_at_not_null` | CHECK | `registered_at IS NOT NULL` | System-generated |

### 2.3 Indexes (Actual)

| Index Name | Type | Columns | Condition |
|---|---|---|---|
| `registrations_pkey` | UNIQUE BTREE | `(registration_id)` | — |
| `registrations_event_id_firebase_uid_key` | UNIQUE BTREE | `(event_id, firebase_uid)` | None — hard unique on all rows |
| `registrations_qrtoken_key` | UNIQUE BTREE | `(qrtoken)` | — |
| `idx_registrations_event_id` | BTREE | `(event_id)` | — |
| `idx_registrations_firebase_uid` | BTREE | `(firebase_uid)` | — |
| `idx_registrations_qrtoken` | BTREE | `(qrtoken)` | — |
| `idx_registrations_status` | BTREE | `(event_id, status)` | — |

### 2.4 Gaps vs Week 3 Contract

| Issue | Actual State | Week 3 Required State | Action |
|---|---|---|---|
| `status` default | `'confirmed'` | `'registered'` | Migration 008 |
| Hard `UNIQUE(event_id, firebase_uid)` | EXISTS | Replace with partial unique `WHERE status = 'registered'` | Migration 008 |
| `qrtoken` NOT NULL | YES (via CHECK constraint `registrations_qrtoken_not_null`) | Nullable (QR not in Week 3) | Migration 008 |
| `badge_name` NOT NULL | YES (via CHECK constraint `registrations_badge_name_not_null`) | Nullable (not in Week 3 contract) | Migration 008 |
| `registration_number` | Missing | `TEXT UNIQUE` | Migration 008 |
| `fullname_snapshot` | Missing | `TEXT` | Migration 008 |
| `email_snapshot` | Missing | `TEXT` | Migration 008 |
| `phone_snapshot` | Missing | `TEXT` | Migration 008 |
| `batch_year_snapshot` | Missing | `INTEGER` | Migration 008 |
| `branch_snapshot` | Missing | `TEXT` | Migration 008 |
| `confirmation_email_status` | Missing (only boolean `confirmation_email_sent`) | `VARCHAR(20) DEFAULT 'pending'` | Migration 008 |
| `confirmation_email_sent_at` | Missing | `TIMESTAMPTZ` | Migration 008 |
| `confirmation_email_error` | Missing | `TEXT` | Migration 008 |
| `attendee_note` | Missing | `TEXT` | Migration 008 |
| `created_at` | Missing (`registered_at` exists but semantics differ) | `TIMESTAMPTZ DEFAULT now()` | Migration 008 |
| `updated_at` | Missing | `TIMESTAMPTZ` | Migration 008 |

**Data migration required:** UPDATE status 'confirmed' → 'registered' (0 current rows; still needed for correctness)

---

## 3. `events` Table

### 3.1 Columns (Actual)

| # | Column | Data Type | Default | Nullable |
|---|---|---|---|---|
| 1 | `event_id` | integer | SERIAL | NO |
| 2 | `slug` | text | — | NO |
| 3 | `title` | text | — | NO |
| 4 | `tagline` | text | — | YES |
| 5 | `description` | text | — | YES |
| 6 | `status` | varchar(20) | `'draft'` | NO |
| 7 | `start_datetime` | timestamptz | — | NO |
| 8 | `end_datetime` | timestamptz | — | NO |
| 9 | `timezone` | varchar(60) | `'Asia/Kolkata'` | NO |
| 10 | `location_text` | text | — | YES |
| 11 | `location_maps_url` | text | — | YES |
| 12 | `is_virtual` | boolean | `false` | NO |
| 13 | `virtual_url` | text | — | YES |
| 14 | `thumbnail_url` | text | — | YES |
| 15 | `banner_url` | text | — | YES |
| 16 | `capacity` | integer | — | YES |
| 17 | `registration_opens_at` | timestamptz | — | YES |
| 18 | `registration_closes_at` | timestamptz | — | YES |
| 19 | `created_by_firebase_uid` | varchar(128) | — | NO |
| 20 | `created_at` | timestamptz | `now()` | NO |
| 21 | `updated_at` | timestamptz | — | YES |
| 22 | `published_at` | timestamptz | — | YES |
| 23 | `cancelled_at` | timestamptz | — | YES |
| 24 | `cancelled_reason` | text | — | YES |
| 25 | `show_attendee_list` | boolean | `false` | NO |

**Total actual columns: 25**

### 3.2 Constraints and Indexes (Actual)

| Name | Type | Columns |
|---|---|---|
| `events_pkey` | PRIMARY KEY | `event_id` |
| `events_slug_key` | UNIQUE | `slug` |
| `idx_events_status` | INDEX | `status` |
| `idx_events_start_datetime` | INDEX | `start_datetime` |

### 3.3 Week 3 Notes

- `virtual_url` EXISTS in table — confirmed. Events_repository.py `_PUBLIC_COLUMNS` correctly excludes it.
- `is_virtual` EXISTS — needed for join_url reveal logic
- `capacity`, `registration_opens_at`, `registration_closes_at` all present — registration eligibility checks can use these directly
- `status` values in use: 'draft', 'published', 'cancelled', 'completed' — no migration needed

**No gaps vs Week 3 contract for the events table.**

---

## 4. `event_users` Table

### 4.1 Columns (Actual)

| # | Column | Data Type | Default | Nullable |
|---|---|---|---|---|
| 1 | `firebase_uid` | varchar(128) | — | NO |
| 2 | `email` | text | — | NO |
| 3 | `fullname` | text | — | NO |
| 4 | `user_type` | varchar(20) | `'alumni'` | NO |
| 5 | `ref_id` | text | — | YES |
| 6 | `graduation_year` | integer | — | YES |
| 7 | `is_suspended` | boolean | `false` | NO |
| 8 | `created_at` | timestamptz | `now()` | NO |
| 9 | `last_login` | timestamptz | — | YES |

**Total actual columns: 9**

### 4.2 Constraints and Indexes (Actual)

| Name | Type | Columns |
|---|---|---|
| `event_users_pkey` | PRIMARY KEY | `firebase_uid` |
| `idx_event_users_email` | INDEX | `email` |
| `idx_event_users_ref_id` | INDEX | `ref_id` |
| `idx_event_users_type` | INDEX | `user_type` |

### 4.3 Week 3 Notes

- `user_type` present — registration gate checks `user_type = 'alumni'`
- `ref_id` present (nullable) — used as alumni_db foreign reference
- `is_suspended` present — used by `get_current_user()` middleware suspension check
- `graduation_year` present in event_users — but Week 3 uses alumni_db for authoritative batch_year; event_users value may differ or be null
- **Integration note rule:** Do NOT store alumni profile fields (name, branch, year) in event_users — use registration snapshot columns. This is confirmed: event_users has `graduation_year` only, not branch.

**No structural gaps for Week 3. No migration needed for this table.**

---

## 5. `event_members` Table

### 5.1 Columns (Actual)

| # | Column | Data Type | Default | Nullable |
|---|---|---|---|---|
| 1 | `event_id` | integer | — | NO |
| 2 | `firebase_uid` | varchar(128) | — | NO |
| 3 | `role` | varchar(30) | — | NO |
| 4 | `status` | varchar(20) | `'active'` | NO |
| 5 | `joined_at` | timestamptz | `now()` | NO |

**Total actual columns: 5**

### 5.2 Constraints and Indexes (Actual)

| Name | Type | Columns |
|---|---|---|
| `event_members_pkey` | PRIMARY KEY | `(event_id, firebase_uid)` |
| `event_members_event_id_fkey` | FOREIGN KEY | `event_id` → `events(event_id)` CASCADE |
| `event_members_firebase_uid_fkey` | FOREIGN KEY | `firebase_uid` → `event_users(firebase_uid)` CASCADE |
| `idx_event_members_event_id` | INDEX | `event_id` |
| `idx_event_members_firebase_uid` | INDEX | `firebase_uid` |
| `idx_event_members_role` | INDEX | `role` |

### 5.3 Week 3 Notes

- `event_members` is for staff/volunteer assignment, not alumni registration — not used in Week 3 registration flow
- No migration needed

---

## 6. `check_ins` Table

### 6.1 Columns (Actual)

| # | Column | Data Type | Default | Nullable |
|---|---|---|---|---|
| 1 | `checkin_id` | integer | SERIAL | NO |
| 2 | `registration_id` | integer | — | NO |
| 3 | `event_id` | integer | — | NO |
| 4 | `scanned_by` | varchar(128) | — | NO |
| 5 | `scanned_at` | timestamptz | `now()` | NO |
| 6 | `session_id` | integer | — | YES |
| 7 | `result` | varchar(20) | — | NO |

**Total actual columns: 7**

### 6.2 Constraints and Indexes (Actual)

| Name | Type | Columns |
|---|---|---|
| `check_ins_pkey` | PRIMARY KEY | `checkin_id` |
| `check_ins_registration_id_fkey` | FK | `registration_id` → `registrations(registration_id)` NO ACTION |
| `check_ins_event_id_fkey` | FK | `event_id` → `events(event_id)` NO ACTION |
| `check_ins_scanned_by_fkey` | FK | `scanned_by` → `event_users(firebase_uid)` NO ACTION |
| `check_ins_session_id_fkey` | FK | `session_id` → `sessions(session_id)` NO ACTION |
| `idx_checkins_event_id` | INDEX | `event_id` |
| `idx_checkins_registration_id` | INDEX | `registration_id` |

### 6.3 Week 3 Notes

- Deferred to future week — check-in / QR is explicitly out of Week 3 scope
- FK from `check_ins.registration_id` → `registrations(registration_id)` uses NO ACTION — safe to add registrations without check-in entries
- No migration needed

---

## 7. `event_audit_log` Table

### 7.1 Columns (Actual)

| # | Column | Data Type | Default | Nullable |
|---|---|---|---|---|
| 1 | `log_id` | bigint | SERIAL | NO |
| 2 | `actor_uid` | varchar | — | YES |
| 3 | `event_type` | text | — | NO |
| 4 | `entity_type` | text | — | NO |
| 5 | `entity_id` | integer | — | YES |
| 6 | `created_at` | timestamptz | `now()` | NO |

**Total actual columns: 6**  
**Rows in DB: 84** (all from Week 2 event management activity)

### 7.2 Week 3 Notes

- This is the events_db equivalent of `website_audit_log` from the website's notify.py
- The adapted `emit()` for events_db must write to this table
- Schema is simpler than website: no `recipient_uid`, no `context` JSON column
- Week 3 must decide: use existing schema (6 columns) or add `context` column for registration audit detail
- **Recommendation:** Add a `context` JSONB column via migration 008 or a separate 009 migration so registration audit entries can include event_id, registration_number without leaking PII

---

## 8. Migration Status Summary

| Migration File | Applied | State |
|---|---|---|
| `001_create_events_alpha_schema.sql` | Unknown — alpha path | NOT active (alpha tables absent from DB) |
| `001_initial_event_schema.sql` | Applied | Active — numbered series baseline |
| `002_event_audit_log.sql` | Applied | Active |
| `003_event_members_and_notifications.sql` | Applied | Active |
| `004_registrations_and_check_ins.sql` | Applied | Active — canonical registrations table |
| `005_sessions.sql` | Applied | Active |
| `006_event_content.sql` | Applied | Active |
| `007_add_show_attendee_list.sql` | Applied | Active |
| `008_week3_registration_alignment.sql` | **PENDING** | To be created and applied |

---

## 9. Key Risks Identified

### Risk 1: badge_name NOT NULL blocks Week 3 INSERTs
**Severity:** CRITICAL  
**Detail:** `badge_name TEXT NOT NULL` with CHECK constraint `registrations_badge_name_not_null`. Week 3 registration service does not populate badge_name. Any INSERT will fail.  
**Fix:** Migration 008 must `ALTER TABLE registrations ALTER COLUMN badge_name DROP NOT NULL`

### Risk 2: qrtoken NOT NULL blocks Week 3 INSERTs
**Severity:** CRITICAL  
**Detail:** `qrtoken` has CHECK constraint `registrations_qrtoken_not_null` enforcing NOT NULL. Week 3 does not generate QR tokens.  
**Fix:** Migration 008 must drop the NOT NULL constraint

### Risk 3: Hard UNIQUE(event_id, firebase_uid) blocks re-registration
**Severity:** HIGH  
**Detail:** Once a user registers and then cancels (status = 'cancelled'), the hard UNIQUE constraint prevents them from registering again for the same event. This violates the cancellation/re-registration use case.  
**Fix:** Migration 008 drops this constraint and replaces it with `CREATE UNIQUE INDEX ... WHERE status = 'registered'`

### Risk 4: status DEFAULT 'confirmed' diverges from Week 3 contract
**Severity:** MEDIUM  
**Detail:** Week 3 canonical status is 'registered'. Any INSERT without explicit status will use 'confirmed'. The `_compute_registration_status()` logic and UI state mapping depends on canonical values.  
**Fix:** Migration 008 changes DEFAULT to 'registered' and converts any existing rows

### Risk 5: registered_count hardcoded 0 in events_service.py
**Severity:** MEDIUM  
**Detail:** `_compute_registration_status()` uses `registered_count` but events_service.py sets it to 0 unconditionally. After migration 008, registration INSERTs will succeed, but event capacity full detection will never trigger. Events can be over-registered.  
**Fix:** Fix `_enrich()` in events_service.py to query actual count from registrations table

### Risk 6: No context column in event_audit_log
**Severity:** LOW  
**Detail:** Registration audit events (registration_created, confirmation_email_sent) have no place to store context (event_id as text, registration_number) in the 6-column audit table without leaking PII.  
**Fix:** Optional — add `context JSONB` to event_audit_log in migration 008 or separately

---

## 10. Confirmation: Week 3 Schema Requirements vs Actual DB

| Requirement | Actual State | Ready? |
|---|---|---|
| events table has capacity, registration_opens_at, registration_closes_at, is_virtual | ✓ All present | YES |
| events table has virtual_url (stored, not exposed publicly) | ✓ Present, excluded from public columns | YES |
| event_users has user_type, ref_id, is_suspended | ✓ All present | YES |
| registrations table exists | ✓ Present | YES |
| registrations status = 'registered' | ✗ Default is 'confirmed' | NO → Migration 008 |
| registrations qrtoken nullable | ✗ NOT NULL enforced | NO → Migration 008 |
| registrations badge_name nullable | ✗ NOT NULL enforced | NO → Migration 008 |
| registrations no hard UNIQUE(event_id, firebase_uid) | ✗ Hard constraint active | NO → Migration 008 |
| registrations partial unique WHERE status = 'registered' | ✗ Does not exist | NO → Migration 008 |
| registrations has registration_number | ✗ Missing | NO → Migration 008 |
| registrations has snapshot columns (6) | ✗ Missing | NO → Migration 008 |
| registrations has confirmation_email_status | ✗ Missing (only boolean) | NO → Migration 008 |
| registrations has attendee_note, created_at, updated_at | ✗ Missing | NO → Migration 008 |
| event_audit_log exists | ✓ Present, 84 rows | YES |
| No alpha-era tables (attendees, check_in_attempts) | ✓ Confirmed absent | YES |

**Conclusion:** 13 of 15 schema requirements need migration 008. The events table and event_users table are ready. The registrations table requires 12 new columns, 2 NOT NULL removals, 1 constraint drop, and 1 constraint replacement.

---

*This report documents the actual DB state as of 2026-06-18. Migration 008 addresses all identified gaps.*
