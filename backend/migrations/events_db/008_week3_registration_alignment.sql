-- 008_week3_registration_alignment.sql
-- Week 3: Align registrations table with Week 3 contract.
--
-- Reviewed and approved: docs/reviews/week3_migration_008_verification_report.md
-- Fixed per:             docs/reviews/week3_migration_008_fix_report.md
--
-- Net column change: 14 existing - 1 dropped + 8 added = 21 final columns.
--
-- Changes in this migration:
--   1.  ALTER status DEFAULT 'confirmed' → 'registered'
--   2.  UPDATE any existing 'confirmed' rows → 'registered'
--   3.  ALTER qrtoken DROP NOT NULL   (QR check-in deferred; Week 3 INSERTs must not require it)
--   4.  ALTER badge_name DROP NOT NULL (badge printing deferred; Week 3 does not collect it)
--   5.  DROP CONSTRAINT registrations_event_id_firebase_uid_key (hard unique blocks re-registration)
--   6.  CREATE partial unique index WHERE status = 'registered'   (replaces Step 5)
--   7.  DROP COLUMN confirmation_email_sent  (replaced by 3-column status tracking below)
--   8.  ADD COLUMN registration_number TEXT  + partial unique index
--   9.  ADD COLUMN fullname_snapshot TEXT
--  10.  ADD COLUMN batch_year_snapshot INTEGER
--  11.  ADD COLUMN branch_snapshot TEXT
--  12.  ADD COLUMN confirmation_email_status VARCHAR(20) DEFAULT 'pending'
--  13.  ADD COLUMN confirmation_email_sent_at TIMESTAMPTZ
--  14.  ADD COLUMN confirmation_email_error TEXT
--  15.  ADD COLUMN updated_at TIMESTAMPTZ
--
-- Columns NOT added (reuse existing columns instead):
--   email_snapshot  → use registrations.email       (populated from alumni_db at INSERT)
--   phone_snapshot  → use registrations.phone       (populated from alumni_db at INSERT)
--   attendee_note   → use registrations.notes       (service maps request.attendee_note → notes)
--   created_at      → use registrations.registered_at (identical semantics for new INSERTs)
--
-- Audit log changes (event_audit_log.context) are in migration 009.
--
-- Pre-flight checks (run manually before applying):
--   SELECT COUNT(*) FROM registrations;
--   -- Document row count. Currently expected: 0.
--
--   SELECT status, COUNT(*) FROM registrations GROUP BY status;
--   -- Document status distribution. Expected: (0 rows).
--
--   SELECT COUNT(*) FROM registrations
--   WHERE status NOT IN ('confirmed', 'registered', 'cancelled');
--   -- Must return 0. Any unknown status values need manual handling first.
--
-- Rollback notes:
--   See docs/reviews/week3_migration_008_fix_report.md — Rollback Notes section.
--   WARNING: Re-adding the hard UNIQUE constraint on rollback will fail if any
--   re-registration rows exist (two rows with same event_id+firebase_uid, one cancelled,
--   one registered). Safe to roll back only while registrations table is empty.

BEGIN;

-- ============================================================
-- Step 1: Convert status DEFAULT and migrate existing data
-- ============================================================

ALTER TABLE registrations
    ALTER COLUMN status SET DEFAULT 'registered';

UPDATE registrations
    SET status = 'registered'
    WHERE status = 'confirmed';

-- ============================================================
-- Step 2: Make qrtoken nullable
-- QR check-in is not in Week 3 scope. Week 3 INSERTs must not
-- require a qrtoken value. The existing UNIQUE index remains:
-- PostgreSQL allows multiple NULLs in a UNIQUE index.
-- ============================================================

ALTER TABLE registrations
    ALTER COLUMN qrtoken DROP NOT NULL;

-- ============================================================
-- Step 3: Make badge_name nullable
-- Badge printing is not in Week 3 scope. Alumni full name is
-- stored in fullname_snapshot (added below), not badge_name.
-- badge_name is preserved for future badge-printing features.
-- ============================================================

ALTER TABLE registrations
    ALTER COLUMN badge_name DROP NOT NULL;

-- ============================================================
-- Step 4: Drop hard UNIQUE(event_id, firebase_uid)
-- Blocks re-registration after cancellation. Replaced in Step 5
-- by a partial unique index on active registrations only.
-- ============================================================

ALTER TABLE registrations
    DROP CONSTRAINT IF EXISTS registrations_event_id_firebase_uid_key;

-- ============================================================
-- Step 5: Add partial unique index for active registrations
-- Prevents two simultaneous active registrations for the same
-- (event_id, firebase_uid). Allows:
--   - registered → cancelled → registered again (re-registration)
--   - multiple cancelled rows for same user+event
-- Prevents:
--   - two rows both with status='registered' for same user+event
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_registrations_active
    ON registrations (event_id, firebase_uid)
    WHERE status = 'registered';

-- ============================================================
-- Step 6: Drop confirmation_email_sent boolean
-- The boolean (sent / not-sent) is replaced by 3-column tracking
-- (status / sent_at / error) added in Steps 11-13. No active
-- code reads this column — all registration code is being
-- rewritten in Week 3. No existing rows to migrate (0 rows).
-- ============================================================

ALTER TABLE registrations
    DROP COLUMN IF EXISTS confirmation_email_sent;

-- ============================================================
-- Step 7: Add registration_number
-- Format: NITKSAA-YYYY-NNNNNN (e.g. NITKSAA-2026-000042).
-- Generated by the service after INSERT (requires registration_id
-- from RETURNING clause). Column is nullable until the service
-- performs the immediate UPDATE after INSERT.
-- Partial unique index enforces uniqueness among non-NULL values;
-- multiple NULL values are allowed during the two-step INSERT flow.
-- ============================================================

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS registration_number TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_registrations_registration_number
    ON registrations (registration_number)
    WHERE registration_number IS NOT NULL;

-- ============================================================
-- Step 8: Add fullname_snapshot
-- Alumni full name from alumni_db.alumni.fullname at registration
-- time. Immutable after INSERT — does not change when the alumni
-- updates their profile. Used in confirmation email and display.
-- Semantically distinct from badge_name (which is what to print
-- on an event badge, potentially a nickname or shortened name).
-- ============================================================

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS fullname_snapshot TEXT;

-- ============================================================
-- Step 9: Add batch_year_snapshot
-- Graduation year from alumni_db.alumni.graduationyear at
-- registration time. event_users.graduation_year is not used
-- here — alumni_db is the authoritative source.
-- ============================================================

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS batch_year_snapshot INTEGER;

-- ============================================================
-- Step 10: Add branch_snapshot
-- Branch/department from alumni_db.alumni.branch at registration
-- time. No equivalent column exists in registrations or
-- event_users.
-- ============================================================

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS branch_snapshot TEXT;

-- ============================================================
-- Steps 11-13: Confirmation email tracking columns
-- Replaces the boolean confirmation_email_sent (dropped in Step 6).
--
-- confirmation_email_status values:
--   pending  — not yet attempted (default set at registration INSERT)
--   sent     — email successfully delivered by provider
--   failed   — send attempt made; provider returned an error
--   skipped  — EMAIL_MODE=log; email was logged, not sent
--
-- Policy: email failure must never roll back a successful
-- registration (integration note rule). These columns record the
-- outcome AFTER the registration transaction has committed.
-- ============================================================

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS confirmation_email_status VARCHAR(20) DEFAULT 'pending';

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS confirmation_email_sent_at TIMESTAMPTZ;

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS confirmation_email_error TEXT;

-- ============================================================
-- Step 14: Add updated_at
-- Set by the service whenever the row is modified after INSERT:
--   - after updating confirmation_email_status + sent_at/error
--   - after cancellation (in addition to cancelled_at)
-- Not set at INSERT time; starts as NULL.
-- registered_at serves as the INSERT timestamp.
-- ============================================================

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- ============================================================
-- Post-migration verification (run after COMMIT):
--
-- Column count:
--   SELECT COUNT(*) FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'registrations';
--   -- Expected: 21
--
-- Columns present:
--   SELECT column_name, data_type, column_default, is_nullable
--   FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'registrations'
--   ORDER BY ordinal_position;
--
-- Indexes:
--   SELECT indexname, indexdef FROM pg_indexes
--   WHERE tablename = 'registrations' ORDER BY indexname;
--   -- Must have:    uq_registrations_active (partial, WHERE status='registered')
--   -- Must have:    uq_registrations_registration_number (partial, WHERE NOT NULL)
--   -- Must NOT have: registrations_event_id_firebase_uid_key (dropped)
--
-- Status default:
--   SELECT column_default FROM information_schema.columns
--   WHERE table_name = 'registrations' AND column_name = 'status';
--   -- Expected: 'registered'::character varying
--
-- Dropped column absent:
--   SELECT COUNT(*) FROM information_schema.columns
--   WHERE table_name = 'registrations' AND column_name = 'confirmation_email_sent';
--   -- Expected: 0
--
-- Data integrity:
--   SELECT COUNT(*) FROM registrations WHERE status = 'confirmed';
--   -- Expected: 0
-- ============================================================

COMMIT;
