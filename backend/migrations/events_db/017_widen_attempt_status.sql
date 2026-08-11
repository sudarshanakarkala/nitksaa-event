-- 017_widen_attempt_status.sql
-- Bug fix for migration 016: 'requires_verification' (21 chars) does not fit
-- in payment_attempts.status VARCHAR(20) — the CHECK constraint accepted the
-- value at DDL time but every actual INSERT/UPDATE using it fails with
-- StringDataRightTruncationError. Widen the column; behavior otherwise
-- unchanged (existing values are all well under the new limit).

BEGIN;

ALTER TABLE payment_attempts ALTER COLUMN status TYPE VARCHAR(30);

COMMIT;
