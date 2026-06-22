# Week 3 — Migration 008 Final Verification Report

**Date:** 2026-06-18  
**Migration File:** `backend/migrations/events_db/008_week3_registration_alignment.sql`  
**Database:** `events_db` — PostgreSQL 18.3 (Homebrew, aarch64-apple-darwin25.2.0)  
**Reviewer:** Pre-implementation migration gate — do not apply without resolving all FAIL items  
**Status:** CONDITIONAL PASS — 3 required changes before approval

---

## Summary

Migration 008 is structurally sound and addresses the correct problems. The overall approach is right: status conversion, partial unique index replacement, nullable relaxation, and snapshot column additions are all correct.

However, the migration contains **3 items that must be corrected** before approval:

| # | Finding | Severity | Resolution |
|---|---|---|---|
| F-1 | `confirmation_email_sent` boolean not dropped — will coexist with new status column creating dual-state inconsistency | HIGH | Add `DROP COLUMN confirmation_email_sent` to migration 008 |
| F-2 | `created_at` column is redundant with `registered_at` already in schema | MEDIUM | Remove `ADD COLUMN created_at` from migration 008 |
| F-3 | `event_audit_log.context` belongs in a separate migration — mixing tables in one migration violates rollback isolation | LOW | Move `ADD COLUMN context JSONB` to migration 009 |

One additional **minor improvement**:

| # | Finding | Severity | Resolution |
|---|---|---|---|
| F-4 | `idx_registrations_registration_number` regular index is made redundant by the partial unique index on the same column | LOW | Remove the redundant regular index |

All other steps — the 11 structural changes, the PostgreSQL 18 NOT NULL drop approach, the constraint names, the partial unique index design, and the status migration — are **PASS**.

---

## Scope

This report reviews every line of migration 008 against:

- Actual DB schema (confirmed via `information_schema` and `pg_constraint`)
- Week 3 API contract (`docs/notes/june2026/nitksaa_event_week3_backend_api_contract_v2.md`)
- Week 3 architecture review (`docs/notes/june2026/nitksaa_event_week3_architecture_review_v2.md`)
- Integration note rules (`docs/notes/june2026/nitksaa-event-app-integration-note_pw.md`)
- Business semantics of each proposed column

---

## Migration Reviewed — Line-by-Line

### PostgreSQL Version Note

**Actual DB: PostgreSQL 18.3**

Migration 004 used inline `NOT NULL` syntax (e.g., `badge_name TEXT NOT NULL`). In PostgreSQL 17+, the engine auto-assigns named NOT NULL constraints with `contype = 'n'`. Confirmed via `pg_constraint`:

```
registrations_badge_name_not_null  | n | NOT NULL badge_name
registrations_qrtoken_not_null     | n | NOT NULL qrtoken
```

These are **auto-named by PostgreSQL from inline NOT NULL declarations** — they were NOT explicitly named in migration 004. `ALTER COLUMN ... DROP NOT NULL` is the correct removal method in PostgreSQL 18 and is backward-compatible. The migration's approach is correct.

---

### Step 1 — Status DEFAULT and Data Migration

```sql
ALTER TABLE registrations ALTER COLUMN status SET DEFAULT 'registered';
UPDATE registrations SET status = 'registered' WHERE status = 'confirmed';
```

**Validation:**
- Current DEFAULT: `'confirmed'` (confirmed via `information_schema.columns`)
- Actual status distribution query result:

```
 status | count
--------+-------
(0 rows)
```

Zero rows in `registrations`. No data migration needed, but the UPDATE is harmless and correct for future-proofing (if this migration is re-run on a DB with data from another environment).

**Pre-flight check from migration header** (`status NOT IN ('confirmed', 'registered', 'cancelled')`) would return 0 — confirmed.

No 'waitlisted' rows exist. No unmapped status values.

**Verdict: PASS**

---

### Step 2 — Make qrtoken Nullable

```sql
ALTER TABLE registrations ALTER COLUMN qrtoken DROP NOT NULL;
```

**Validation:**
- Actual constraint: `registrations_qrtoken_not_null | n | NOT NULL qrtoken`
- `contype = 'n'` = named NOT NULL constraint (PostgreSQL 18 auto-generated)
- `ALTER COLUMN DROP NOT NULL` drops this auto-named constraint in PostgreSQL 18 — verified correct
- The existing `registrations_qrtoken_key` UNIQUE index on `qrtoken` is NOT modified. PostgreSQL UNIQUE indexes allow multiple NULLs by default (`NULL != NULL`), so nullability is compatible with the existing unique index.

QR code / check-in is explicitly out of Week 3 scope. Making qrtoken nullable is the correct approach — QR generation can be added back in a future migration when check-in is implemented.

**Verdict: PASS**

---

### Step 3 — Make badge_name Nullable

```sql
ALTER TABLE registrations ALTER COLUMN badge_name DROP NOT NULL;
```

**Validation:**
- Actual constraint: `registrations_badge_name_not_null | n | NOT NULL badge_name`
- Same `contype = 'n'` pattern — `ALTER COLUMN DROP NOT NULL` is correct
- Week 3 registration contract populates `fullname_snapshot` from alumni_db, NOT `badge_name`
- `badge_name` (badge printing field) and `fullname_snapshot` (alumni profile snapshot) are **different semantic fields** — see Column Justification section for full analysis

Making badge_name nullable unblocks Week 3 INSERTs. The column is preserved for future badge-printing use (Week 4+).

**Verdict: PASS**

---

### Step 4 — Drop Hard UNIQUE(event_id, firebase_uid)

```sql
ALTER TABLE registrations DROP CONSTRAINT IF EXISTS registrations_event_id_firebase_uid_key;
```

**Validation:**
- Actual constraint confirmed: `registrations_event_id_firebase_uid_key | u | UNIQUE (event_id, firebase_uid)`
- `IF NOT EXISTS` guard prevents error if already removed (safe for re-run)
- Dropping this constraint is necessary because it blocks re-registration after cancellation. A user who registers (row inserted) and then cancels (status = 'cancelled') would be permanently blocked from re-registering for the same event under the hard constraint.
- Replacement via partial unique index in Step 5 maintains the uniqueness guarantee for active registrations only.

**Verdict: PASS**

---

### Step 5 — Partial Unique Index

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_registrations_active
    ON registrations (event_id, firebase_uid)
    WHERE status = 'registered';
```

**Validation:**
- Prevents two simultaneous active registrations for the same (event_id, firebase_uid)
- Allows: same user, same event, one row `status='cancelled'` + one row `status='registered'` — both can coexist
- Allows: same user, same event, multiple rows `status='cancelled'` (if re-registration happens multiple times)
- Prevents: two rows both with `status='registered'` for same (event_id, firebase_uid) — this is the duplicate guard

This design correctly supports the Week 3 re-registration flow without blocking historical cancellation records.

**Verdict: PASS**

---

### Step 6 — registration_number Column

```sql
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS registration_number TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_registrations_registration_number
    ON registrations (registration_number)
    WHERE registration_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_registrations_registration_number
    ON registrations (registration_number);
```

**Validation — unique partial index:**
- `WHERE registration_number IS NOT NULL` correctly handles the nullable column — allows NULL for rows where number hasn't been generated yet, while enforcing uniqueness among non-NULL values.
- Correct design.

**Validation — redundant regular index (F-4):**
- `idx_registrations_registration_number` is a regular index on `registration_number`.
- `uq_registrations_registration_number WHERE registration_number IS NOT NULL` already covers all queries that look up by a specific registration number (since a specific number is always non-NULL).
- Any query `WHERE registration_number = 'NITKSAA-2026-000042'` will use the partial unique index.
- The regular index adds overhead (writes on INSERT/UPDATE) with no query benefit over the partial index.
- **Recommendation: Remove `idx_registrations_registration_number`** from migration 008. The partial unique index is sufficient.

**generation design note:** Format `NITKSAA-YYYY-NNNNNN` uses `registration_id` for the sequential part. Since `registration_id` is only known after INSERT, the service must:
1. INSERT registration row (registration_number = NULL)
2. Generate number from returned registration_id
3. UPDATE row to set registration_number
This two-step approach is correct. The nullable column design supports it.

**Verdict: PASS with minor fix — remove redundant regular index (F-4)**

---

### Step 7 — Alumni Profile Snapshot Columns

```sql
ADD COLUMN IF NOT EXISTS fullname_snapshot TEXT
ADD COLUMN IF NOT EXISTS email_snapshot TEXT
ADD COLUMN IF NOT EXISTS phone_snapshot TEXT
ADD COLUMN IF NOT EXISTS batch_year_snapshot INTEGER
ADD COLUMN IF NOT EXISTS branch_snapshot TEXT
```

**Validation:** All 5 snapshot columns are nullable (no NOT NULL constraint). This is correct because:
- Rows are initially inserted without snapshot data, then populated from alumni_db lookup
- If alumni_db lookup fails, registration can still succeed (with empty snapshots)
- The integration note requires: "Do not store alumni profile fields in event_users — use registration snapshot columns"

All 5 snapshots map to confirmed columns in `alumni_db.alumni`: `fullname`, `email`, `phone`, `graduationyear`, `branch`.

**Verdict: PASS**

---

### Step 8 — Confirmation Email Tracking

```sql
ADD COLUMN IF NOT EXISTS confirmation_email_status VARCHAR(20) DEFAULT 'pending'
ADD COLUMN IF NOT EXISTS confirmation_email_sent_at TIMESTAMPTZ
ADD COLUMN IF NOT EXISTS confirmation_email_error TEXT
```

**Migration 008 does NOT drop `confirmation_email_sent BOOLEAN NOT NULL DEFAULT false`.**

This creates a dual-state inconsistency — see F-1 in Column Justification section. The boolean must be dropped in the same migration.

**Verdict: PASS for new columns, FAIL for missing DROP COLUMN (see F-1)**

---

### Step 9 — attendee_note

```sql
ADD COLUMN IF NOT EXISTS attendee_note TEXT
```

Optional registrant note. Nullable. No issues.

**Verdict: PASS**

---

### Step 10 — created_at and updated_at

```sql
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now()
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ
```

`created_at` is redundant — see F-2 in Column Justification section.
`updated_at` is correct and needed.

**Verdict: updated_at PASS, created_at FAIL (see F-2)**

---

### Step 11 — event_audit_log.context

```sql
ALTER TABLE event_audit_log ADD COLUMN IF NOT EXISTS context JSONB;
```

Adding a column to a different table (`event_audit_log`) inside a migration named `008_week3_registration_alignment.sql` violates the single-responsibility principle for migrations. See F-3.

**Verdict: FAIL — move to migration 009 (see F-3)**

---

## Column Justification Review

### registration_number

**Why needed:** Confirmation number shown to registrant on success screen. Format `NITKSAA-2026-000042`. Required by UC-02 and UC-03. Printed in confirmation email.

**Week 3 dependency:** POST /register response, GET /my-registration response, confirmation email.

**Existing column that serves same purpose:** None. `registration_id` is an internal PK (integer), not a user-facing reference.

**Decision: ADD** — correct as proposed.

---

### fullname_snapshot

**Why needed:** Alumni name at registration time, used in: confirmation email salutation, admin export, display on my-registration screen.

**Week 3 dependency:** Confirmation email content, registration response.

**Existing column analysis — badge_name:**
- `badge_name` = what an attendee wants printed on their event badge (may differ from full name — e.g., "Ravi" instead of "Ravindra Kumar Hegde"). This is a **badge printing concern**, not a profile snapshot.
- `fullname_snapshot` = official full name from `alumni_db.alumni.fullname` at registration time.

These are semantically distinct. A future Week 4 badge flow might allow a user to set badge_name separately after registering. Reusing badge_name as fullname_snapshot would conflate two different data points.

**Decision: ADD fullname_snapshot as new column. Keep badge_name nullable for future use. Do not rename or merge.**

---

### email_snapshot

**Why needed:** Email address used for confirmation email delivery. Snapshot from `alumni_db.alumni.email`. Immutable — email delivery targets the address at registration time even if alumni changes their email later.

**Week 3 dependency:** Confirmation email delivery.

**Existing column:** `registrations.email TEXT NOT NULL` (migration 004). This column already holds the email.

**Critical finding: `email` column may be redundant with `email_snapshot`.**

However, the existing `email` column is `NOT NULL` and was intended to be populated at INSERT time in the alpha registration service. In Week 3, the same value (alumni email from alumni_db) would be written to both `email` and `email_snapshot` — creating actual duplication.

**Options:**
1. Rename `email` → `email_snapshot` (requires `ALTER COLUMN RENAME`)
2. Keep `email` (existing, NOT NULL) and use it as the email snapshot, skip adding `email_snapshot`
3. Add `email_snapshot` and eventually deprecate `email`

**Recommendation: Reuse `email` column. Do not add `email_snapshot`.**

The existing `email` column already captures the email at registration time (if populated correctly by the service). Adding `email_snapshot` would create two columns storing the same value. The service should populate `email` from `alumni_db.alumni.email` at INSERT time. Week 3 service can use `email` directly for email delivery.

**Impact on migration 008:** Remove `ADD COLUMN email_snapshot` from Step 7. The service writes to `email` (existing column).

---

### phone_snapshot

**Why needed:** Phone number at registration time. Used in admin export, contact reference.

**Week 3 dependency:** Admin visibility (Week 4), registration record completeness.

**Existing column:** None. `registrations` has `phone TEXT` (nullable) from migration 004.

**Critical finding: `phone` column already exists and is nullable.**

Same situation as `email` — the existing `phone` column can serve as the phone snapshot if the service populates it from alumni_db at INSERT time.

**Recommendation: Reuse `phone` column. Do not add `phone_snapshot`.**

**Impact on migration 008:** Remove `ADD COLUMN phone_snapshot` from Step 7. The service writes to `phone` (existing column).

---

### batch_year_snapshot

**Why needed:** Alumni graduation year at registration time. Used in admin export, registration record.

**Week 3 dependency:** Registration record completeness, admin export (Week 4).

**Existing column:** None in `registrations`. `event_users.graduation_year` exists but is in a different table and may differ from alumni_db value.

**Decision: ADD** — no existing column in registrations table serves this purpose. `event_users.graduation_year` is not authoritative (may be stale or null); alumni_db is the source of truth.

---

### branch_snapshot

**Why needed:** Alumni branch/department at registration time. Needed for admin segmentation and export.

**Week 3 dependency:** Registration record completeness, admin export (Week 4).

**Existing column:** None.

**Decision: ADD** — correct.

---

### confirmation_email_status

**Why needed:** 4-state email tracking: `pending | sent | failed | skipped`. Supports diagnostics test (TC-016, TC-017), confirmation email result display, admin visibility.

**Week 3 dependency:** POST /register response (email result in response body), diagnostics email test, TC-017 email failure handling.

**Existing column:** `confirmation_email_sent BOOLEAN NOT NULL DEFAULT false` — this is a binary (sent/not-sent) with no failure state, no timestamp, no error capture.

**Decision: ADD confirmation_email_status AND drop confirmation_email_sent boolean** — see F-1 below.

---

### confirmation_email_sent_at

**Why needed:** Timestamp of when email was sent. Used in diagnostics display ("Email sent at: 2026-06-18T10:05:23+05:30") and admin verification.

**Week 3 dependency:** Diagnostics email result panel, UC-11.

**Existing column:** None.

**Decision: ADD** — correct.

---

### confirmation_email_error

**Why needed:** Error message/code when email send fails. Used in diagnostics failure display (UC-12) and admin troubleshooting.

**Week 3 dependency:** TC-017 — email failure must not rollback registration, but error must be recorded.

**Existing column:** None.

**Decision: ADD** — correct.

---

### attendee_note

**Why needed:** Optional text the registrant can add at registration time (dietary requirements, accessibility needs, etc.). Stored for admin visibility.

**Week 3 dependency:** `RegisterRequest.attendee_note` (optional field in POST /register body).

**Existing column:** `registrations.notes TEXT` (nullable) — this column already exists and serves exactly this purpose.

**Critical finding: `notes` column already exists.**

**Recommendation: Reuse `notes` column. Do not add `attendee_note`.**

The service writes registrant input to `notes`. If the API contract uses `attendee_note` as the request field name, that's a schema field name (Pydantic model) — it does NOT have to match the DB column name. The service maps `request.attendee_note` → `INSERT notes = $1`.

**Impact on migration 008:** Remove `ADD COLUMN attendee_note` from Step 9.

---

### created_at (F-2)

**Why needed (claimed):** Technical row creation timestamp, separate from business event timestamp.

**Existing column:** `registered_at TIMESTAMPTZ NOT NULL DEFAULT now()` — already present.

**Analysis:**
- `registered_at` is set to `now()` at INSERT time, which IS the row creation time for a new registration.
- Under a re-registration flow where the service INSERTs a new row (rather than updating a cancelled row), `created_at` == `registered_at` always — the column is redundant.
- Under a reactivation flow where the service UPDATEs a cancelled row (sets status = 'registered', updates registered_at = now()), `created_at` would capture original row creation. But `updated_at` already serves the purpose of tracking when the row was last modified.

**Recommendation: Remove `created_at` from migration 008.** `registered_at` (when this registration event occurred) + `updated_at` (when the row was last changed) are sufficient. Adding `created_at` creates three timestamp columns with overlapping semantics and invites bugs (e.g., email service updates `updated_at` but not `created_at`, which is never touched after INSERT).

**Impact on migration 008:** Remove `ADD COLUMN created_at` from Step 10.

---

### updated_at

**Why needed:** Tracks when the row was last modified. Required for: email status updates (service sets updated_at after updating confirmation_email_status), cancellation tracking (though cancelled_at exists), audit trail.

**Week 3 dependency:** Email status update after confirmation email attempt.

**Existing column:** `cancelled_at` exists but is cancellation-specific. No general `updated_at`.

**Decision: ADD** — correct. Keep in migration 008.

---

## Special Review Items

### S-1: registered_at vs created_at

| Column | Current State | Semantics |
|---|---|---|
| `registered_at` | EXISTS — `TIMESTAMPTZ NOT NULL DEFAULT now()` | When the registration event occurred |
| `created_at` | Proposed — `TIMESTAMPTZ DEFAULT now()` | When the DB row was created |

For a new INSERT, both values are identical (both = now() at INSERT time). They diverge only in a reactivation scenario where a cancelled row is updated. In that scenario, `updated_at` already captures the modification time.

**Recommendation: Remove `created_at`. Use `registered_at` for INSERT timestamp. Use `updated_at` for modification tracking.**

---

### S-2: badge_name vs fullname_snapshot

| Column | Semantic Purpose | Status After Migration 008 |
|---|---|---|
| `badge_name` | What to print on event badge — may be a nickname | Nullable (NOT NULL dropped) |
| `fullname_snapshot` (proposed) | Official alumni full name from alumni_db at registration | New column |

These serve different purposes. However, the Week 3 implementation never prints badges. The `badge_name` column is future-use (Week 4+). `fullname_snapshot` is the correct new column for storing the alumni profile's full name at registration time.

**Recommendation: Add `fullname_snapshot`. Keep `badge_name` nullable. Do not reuse or rename badge_name.**

Note: `email` and `phone` existing columns CAN be reused (see email_snapshot and phone_snapshot sections above), but `badge_name` cannot be reused for fullname_snapshot because the badge printing use case may come back with different behavior (user-editable badge name field).

---

### S-3: confirmation_email_sent (boolean) — F-1

| Column | Type | Purpose |
|---|---|---|
| `confirmation_email_sent` | `BOOLEAN NOT NULL DEFAULT false` | Binary: was email sent? |
| `confirmation_email_status` (proposed) | `VARCHAR(20) DEFAULT 'pending'` | 4-state: pending / sent / failed / skipped |
| `confirmation_email_sent_at` (proposed) | `TIMESTAMPTZ` | Timestamp of send |
| `confirmation_email_error` (proposed) | `TEXT` | Error message if failed |

**Current migration 008 keeps the boolean AND adds the 3 new columns.** This means the service would need to maintain two representations of the same state:
- Set `confirmation_email_sent = true` AND `confirmation_email_status = 'sent'` on success
- Set `confirmation_email_sent = false` AND `confirmation_email_status = 'failed'` on failure

Any inconsistency between the two (e.g., email sent but boolean not updated, or vice versa) creates a data integrity problem.

**No active code reads `confirmation_email_sent`.** The entire registration service is being rewritten. There is zero backward compatibility cost to dropping the boolean.

**Recommendation: DROP `confirmation_email_sent` in migration 008.** The 3-column replacement (status + sent_at + error) is strictly superior. Dropping the boolean eliminates a dual-state consistency bug before it can happen.

**Migration 008 change required:**
```sql
ALTER TABLE registrations DROP COLUMN IF EXISTS confirmation_email_sent;
```

Add this BEFORE the ADD COLUMN statements for the new email tracking columns.

---

### S-4: event_audit_log.context JSONB — F-3

Migration 008 proposes:
```sql
ALTER TABLE event_audit_log ADD COLUMN IF NOT EXISTS context JSONB;
```

**Assessment:**
- This change is to a different table (`event_audit_log`, not `registrations`)
- Migration 008 is named `008_week3_registration_alignment.sql` — it should only modify the `registrations` table
- Including a different table in this migration mixes rollback boundaries: if 008 needs to be rolled back due to a registrations issue, rolling it back also drops the context column from audit log (even if audit log change was fine)
- The context column IS needed for Week 3 (registration audit events need context), but it should go in a separate migration

**Recommendation: Remove `event_audit_log.context` from migration 008. Create migration `009_audit_log_context.sql` for this change.**

Migration 009 should be applied immediately after 008, before Phase 2 implementation begins.

---

## Status Model Review

### Actual Status Distribution

```sql
SELECT status, COUNT(*)
FROM registrations
GROUP BY status;
```

**Result:**
```
 status | count
--------+-------
(0 rows)
```

Zero rows in the registrations table. No existing status values to audit.

**Pre-flight check result** (`status NOT IN ('confirmed', 'registered', 'cancelled')` → 0): Confirmed safe.

**Waitlisted status:** Not present in DB. Migration 008's pre-flight check comment lists `('confirmed', 'registered', 'cancelled')` as known statuses — this is complete. No 'waitlisted' rows exist.

### Status Model Validation

| Source | Status Values |
|---|---|
| Migration 004 DEFAULT | `'confirmed'` |
| Actual DB DEFAULT | `'confirmed'` |
| Week 3 contract | `registered`, `cancelled` |
| Migration 008 proposes | `DEFAULT 'registered'`, UPDATE confirmed→registered |

The conversion is correct. Week 3 canonical statuses `registered` and `cancelled` are sufficient — no waitlist, no payment hold, no pending state.

**Rollback implication:** If migration 008 is rolled back after any registrations have been created (status = 'registered'), those rows would need to be converted back to 'confirmed' before the hard UNIQUE constraint can be re-added (they'd be functionally broken under the old schema). Since there are 0 rows now, rollback is trivial. Once registrations exist, rollback becomes operationally risky.

---

## Constraint Review

### UNIQUE(event_id, firebase_uid) — Drop and Replace

**Current constraint:** Hard UNIQUE on ALL rows regardless of status.

**Scenario that fails under hard UNIQUE:**
1. User registers → INSERT (event_id=1, firebase_uid='A', status='registered') → SUCCESS
2. User cancels → UPDATE status='cancelled' → SUCCESS (row still exists)
3. User tries to re-register → INSERT (event_id=1, firebase_uid='A', status='registered') → **FAILS** with UNIQUE violation

**Partial index solution:**
```sql
CREATE UNIQUE INDEX uq_registrations_active
    ON registrations (event_id, firebase_uid)
    WHERE status = 'registered';
```

**Scenario under partial unique:**
1. User registers → (event_id=1, uid='A', status='registered') — index entry added → SUCCESS
2. User cancels → status changes to 'cancelled' — index entry removed (row no longer matches WHERE clause) → SUCCESS
3. User re-registers → new (event_id=1, uid='A', status='registered') — no conflict → SUCCESS
4. Two concurrent users try to grab last seat → transaction lock in service prevents race; only one gets status='registered' → correct

**Concurrent duplicate prevention:** The partial unique index prevents two rows with `(event_id=1, uid='A', status='registered')` from coexisting even if the service transaction has a race. PostgreSQL enforces the index constraint atomically.

**Verdict: Design is correct. PASS.**

---

### qrtoken Nullable

- QR check-in is out of Week 3 scope
- `qrtoken UNIQUE NOT NULL` (migration 004) would block all Week 3 INSERTs
- Making qrtoken nullable + keeping the UNIQUE index allows future QR generation to populate the column
- PostgreSQL UNIQUE index allows multiple NULLs — no uniqueness violation if many rows have NULL qrtoken

**Verdict: PASS**

---

### badge_name Nullable

- `badge_name NOT NULL` (migration 004) blocks Week 3 INSERTs
- Week 3 does not collect or display badge names
- Making nullable allows INSERTs without badge_name; future badge-printing feature can add NOT NULL back after populating column
- Since 0 rows exist, this change has zero data impact

**Verdict: PASS**

---

## Data Impact Analysis

| Table | Rows Before | Rows After | Impact |
|---|---|---|---|
| `registrations` | 0 | 0 (schema only) | Zero — no data modified |
| `events` | 31 | 31 | Untouched |
| `event_users` | 4 | 4 | Untouched |
| `event_audit_log` | 84 | 84 | Untouched (context column stays in 009) |

The UPDATE `WHERE status = 'confirmed'` affects 0 rows. All DDL changes (ALTER TABLE, CREATE INDEX, DROP CONSTRAINT) are metadata-only with zero row impact.

**Lock analysis:** DDL on a table with 0 rows acquires an `ACCESS EXCLUSIVE` lock briefly. No active queries on this table in development. No contention risk.

---

## Rollback Analysis

### Rollback SQL for Each Change

**Note:** Rollback SQL assumes migration 008 applied cleanly but rollback is needed. Apply in reverse order.

```sql
BEGIN;

-- Rollback Step 11 (if audit_log.context was included — pending removal per F-3)
-- ALTER TABLE event_audit_log DROP COLUMN IF EXISTS context;

-- Rollback Step 10: Drop updated_at (created_at is being removed per F-2)
ALTER TABLE registrations DROP COLUMN IF EXISTS updated_at;

-- Rollback Step 9: Drop attendee_note (being removed from migration per reuse of notes)
-- ALTER TABLE registrations DROP COLUMN IF EXISTS attendee_note;

-- Rollback Step 8: Drop confirmation email columns; restore boolean
ALTER TABLE registrations DROP COLUMN IF EXISTS confirmation_email_error;
ALTER TABLE registrations DROP COLUMN IF EXISTS confirmation_email_sent_at;
ALTER TABLE registrations DROP COLUMN IF EXISTS confirmation_email_status;
-- After F-1 fix: re-add the boolean (originally NOT NULL, but rows may now have NULL values)
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS confirmation_email_sent BOOLEAN DEFAULT false;

-- Rollback Step 7: Drop snapshot columns
ALTER TABLE registrations DROP COLUMN IF EXISTS branch_snapshot;
ALTER TABLE registrations DROP COLUMN IF EXISTS batch_year_snapshot;
ALTER TABLE registrations DROP COLUMN IF EXISTS phone_snapshot;
ALTER TABLE registrations DROP COLUMN IF EXISTS email_snapshot;  -- only if kept in migration
ALTER TABLE registrations DROP COLUMN IF EXISTS fullname_snapshot;

-- Rollback Step 6: Drop registration_number
DROP INDEX IF EXISTS uq_registrations_registration_number;
DROP INDEX IF EXISTS idx_registrations_registration_number;  -- only if kept in migration
ALTER TABLE registrations DROP COLUMN IF EXISTS registration_number;

-- Rollback Step 5: Drop partial unique index
DROP INDEX IF EXISTS uq_registrations_active;

-- Rollback Step 4: Restore hard UNIQUE constraint
-- WARNING: This FAILS if any (event_id, firebase_uid) pairs have re-registration rows
-- Check first: SELECT event_id, firebase_uid, COUNT(*) FROM registrations
--              GROUP BY event_id, firebase_uid HAVING COUNT(*) > 1;
ALTER TABLE registrations ADD CONSTRAINT registrations_event_id_firebase_uid_key
    UNIQUE (event_id, firebase_uid);

-- Rollback Step 3: Restore badge_name NOT NULL
-- WARNING: This FAILS if any rows have NULL badge_name
-- Check: SELECT COUNT(*) FROM registrations WHERE badge_name IS NULL;
ALTER TABLE registrations ALTER COLUMN badge_name SET NOT NULL;

-- Rollback Step 2: Restore qrtoken NOT NULL
-- WARNING: This FAILS if any rows have NULL qrtoken
-- Check: SELECT COUNT(*) FROM registrations WHERE qrtoken IS NULL;
ALTER TABLE registrations ALTER COLUMN qrtoken SET NOT NULL;

-- Rollback Step 1: Revert status default and data
ALTER TABLE registrations ALTER COLUMN status SET DEFAULT 'confirmed';
-- Only if rows were registered and need reverting:
-- UPDATE registrations SET status = 'confirmed' WHERE status = 'registered';

COMMIT;
```

### Rollback Risk Assessment

| Change | Risk | Condition |
|---|---|---|
| Status DEFAULT change | LOW | Trivial if no rows; needs UPDATE if rows exist |
| status = 'confirmed' data migration | LOW | 0 rows affected; reverse UPDATE is trivial |
| qrtoken DROP NOT NULL | LOW | Re-add with SET NOT NULL will fail if NULL qrtokens inserted |
| badge_name DROP NOT NULL | LOW | Re-add with SET NOT NULL will fail if NULL badge_names inserted |
| Drop hard UNIQUE constraint | **MEDIUM** | Re-add will fail if any re-registration rows exist |
| Partial unique index | LOW | DROP INDEX is always safe |
| New columns | LOW | DROP COLUMN is always safe |
| confirmation_email_sent DROP (F-1 fix) | LOW | Re-add as nullable column |
| event_audit_log.context (if included) | LOW | DROP COLUMN is safe |

**Overall rollback risk: LOW (currently, with 0 rows). Becomes MEDIUM after any re-registration activity occurs** (which would block re-adding the hard UNIQUE constraint on rollback).

**Recommendation: Apply migration 008 before any registration data exists** (current state is ideal). After registrations are created, rollback risk increases to MEDIUM.

---

## Risks

| Risk | Severity | Notes |
|---|---|---|
| Dual email state (F-1) | HIGH | `confirmation_email_sent` boolean not dropped — creates inconsistency risk |
| `created_at` redundancy (F-2) | MEDIUM | Three timestamp columns with overlapping semantics; `created_at` == `registered_at` for new INSERTs |
| `email`, `phone`, `attendee_note` duplication | MEDIUM | Three new columns proposed where existing columns suffice (`email`, `phone`, `notes`) |
| `event_audit_log` in registrations migration (F-3) | LOW | Scope/rollback concern; not a data risk |
| Redundant regular index on registration_number (F-4) | LOW | Extra write overhead per INSERT; no data risk |
| Partial unique index race condition | LOW | Mitigated by service-level `SELECT FOR UPDATE` on event row |
| PostgreSQL 18 NOT NULL named constraint handling | NONE | Confirmed: `ALTER COLUMN DROP NOT NULL` is correct |
| 0 rows in registrations | NONE | Actually reduces risk — no data migration needed |

---

## Recommendations

### Changes Required Before Approval

**1. Drop `confirmation_email_sent` boolean (F-1 — HIGH)**

Add to migration 008 Step 8, before the ADD COLUMN statements:
```sql
-- Drop the coarse boolean; replaced by 3-column status tracking below
ALTER TABLE registrations DROP COLUMN IF EXISTS confirmation_email_sent;
```

**2. Remove `ADD COLUMN created_at` (F-2 — MEDIUM)**

Remove this block from Step 10:
```sql
-- REMOVE THIS:
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
```
Keep `updated_at`. Use `registered_at` for INSERT timestamp.

**3. Remove `event_audit_log.context` from migration 008 (F-3 — LOW)**

Remove Step 11 entirely from migration 008. Create `009_audit_log_context.sql`:
```sql
BEGIN;
ALTER TABLE event_audit_log ADD COLUMN IF NOT EXISTS context JSONB;
COMMIT;
```

**4. Remove redundant `idx_registrations_registration_number` index (F-4 — LOW)**

Remove from Step 6:
```sql
-- REMOVE THIS:
CREATE INDEX IF NOT EXISTS idx_registrations_registration_number
    ON registrations (registration_number);
```
The partial unique index `uq_registrations_registration_number WHERE registration_number IS NOT NULL` covers all non-NULL lookups.

### Columns to Remove or Reuse

**5. Reuse `email` column instead of adding `email_snapshot` (MEDIUM)**

Remove from Step 7:
```sql
-- REMOVE THIS:
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS email_snapshot TEXT;
```
Service writes alumni email to the existing `email` column.

**6. Reuse `phone` column instead of adding `phone_snapshot` (MEDIUM)**

Remove from Step 7:
```sql
-- REMOVE THIS:
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS phone_snapshot TEXT;
```
Service writes alumni phone to the existing `phone` column.

**7. Reuse `notes` column instead of adding `attendee_note` (MEDIUM)**

Remove from Step 9:
```sql
-- REMOVE THIS:
ALTER TABLE registrations ADD COLUMN IF NOT EXISTS attendee_note TEXT;
```
Service maps `RegisterRequest.attendee_note` → `registrations.notes`. Column name mismatch between API and DB is handled in the repository layer.

---

### Final Column List After Recommended Changes

**Columns added by migration 008 (after applying all recommendations):**

| Column | Type | Justification |
|---|---|---|
| `registration_number` | TEXT | Confirmation number — no existing column |
| `fullname_snapshot` | TEXT | Alumni full name — badge_name is semantically different |
| `batch_year_snapshot` | INTEGER | Graduation year — not in registrations table |
| `branch_snapshot` | TEXT | Department — not in registrations table |
| `confirmation_email_status` | VARCHAR(20) DEFAULT 'pending' | 4-state tracking — replaces boolean |
| `confirmation_email_sent_at` | TIMESTAMPTZ | Send timestamp — not in registrations table |
| `confirmation_email_error` | TEXT | Error capture — not in registrations table |
| `updated_at` | TIMESTAMPTZ | Row modification tracking — not in registrations table |

**Columns removed from proposed migration 008:**

| Column | Reason |
|---|---|
| `email_snapshot` | Reuse existing `email` column |
| `phone_snapshot` | Reuse existing `phone` column |
| `attendee_note` | Reuse existing `notes` column |
| `created_at` | Redundant with `registered_at` |

**Columns dropped by migration 008 (after applying F-1 fix):**

| Column | Reason |
|---|---|
| `confirmation_email_sent` | Replaced by 3-column status tracking; no active code reads it |

**Net result:** 14 existing → DROP 1 → ADD 8 = **21 columns** total (not 26 as originally calculated).

---

## PASS / FAIL Recommendation

**CONDITIONAL PASS**

Migration 008 is approved **after** making the following 7 changes:

| # | Change | Priority |
|---|---|---|
| F-1 | Add `DROP COLUMN confirmation_email_sent` | **REQUIRED** |
| F-2 | Remove `ADD COLUMN created_at` | **REQUIRED** |
| F-3 | Remove `event_audit_log.context` (create 009 instead) | **REQUIRED** |
| F-4 | Remove redundant `idx_registrations_registration_number` | Recommended |
| R-5 | Remove `email_snapshot` (reuse `email`) | Recommended |
| R-6 | Remove `phone_snapshot` (reuse `phone`) | Recommended |
| R-7 | Remove `attendee_note` (reuse `notes`) | Recommended |

Items F-1, F-2, F-3 are required before applying. R-4 through R-7 are strongly recommended to keep the schema clean and avoid data duplication.

**If only F-1/F-2/F-3 are applied:** The migration is approvable. R-5/R-6/R-7 can be deferred but will result in redundant columns.

---

## Next Steps

1. Update `backend/migrations/events_db/008_week3_registration_alignment.sql` with required changes
2. Create `backend/migrations/events_db/009_audit_log_context.sql`
3. Re-review migration 008 diff (quick review only — structural changes only)
4. Apply migration 008: `psql events_db < backend/migrations/events_db/008_week3_registration_alignment.sql`
5. Apply migration 009: `psql events_db < backend/migrations/events_db/009_audit_log_context.sql`
6. Run post-migration verification queries from migration 008 header comment
7. Proceed to Phase 2: alumni_service.py extension

Do NOT apply migration 008 in its current form. Apply only after the REQUIRED changes (F-1, F-2, F-3) are made.
