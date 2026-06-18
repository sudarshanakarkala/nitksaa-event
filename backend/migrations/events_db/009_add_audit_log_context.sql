-- 009_add_audit_log_context.sql
-- Week 3: Add context JSONB column to event_audit_log.
--
-- Separated from migration 008 to maintain single-table rollback boundaries.
-- Must be applied immediately after 008 and before Phase 2 implementation begins.
--
-- Context column allows registration audit entries to carry structured metadata:
--   { "registration_number": "NITKSAA-2026-000042", "event_id": 1,
--     "email_status": "sent" }
--
-- Security rule: never write firebase_uid, email, phone, or join URLs into context.
-- Existing 84 rows in event_audit_log are unaffected (context = NULL for all of them).
--
-- Pre-flight check:
--   SELECT COUNT(*) FROM event_audit_log;
--   -- Document count. Existing rows will have context = NULL after this migration.
--
-- Rollback:
--   ALTER TABLE event_audit_log DROP COLUMN IF EXISTS context;

BEGIN;

ALTER TABLE event_audit_log
    ADD COLUMN IF NOT EXISTS context JSONB;

-- Post-migration verification (run after COMMIT):
--
--   SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'event_audit_log'
--   ORDER BY ordinal_position;
--   -- Expected columns: log_id, actor_uid, event_type, entity_type, entity_id, created_at, context

COMMIT;
