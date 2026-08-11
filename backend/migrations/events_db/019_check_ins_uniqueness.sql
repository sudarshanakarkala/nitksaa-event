-- 019_check_ins_uniqueness.sql
-- Admin event schema alignment sprint: the check-in subsystem
-- (CheckInRepository/CheckInService) previously targeted columns from a
-- superseded schema migration and has been repaired to use the real
-- check_ins table. That repair surfaced a real gap: no unique constraint
-- prevents two concurrent check-in requests for the same registration
-- from both passing a check-then-insert race and producing two check_ins
-- rows. This is the same class of guarantee the payment domain already
-- relies on (unique indexes as the actual source of truth, application
-- checks as a fast path only) — applied here to close the one race this
-- sprint's own concurrency-safety requirement calls out.
--
-- One registration can only ever be checked in once for its event
-- (CheckInRepository.find_existing_checkin's lookup key is exactly
-- (event_id, registration_id) — a registration belongs to exactly one
-- event via registrations.event_id, so this is effectively "once per
-- registration", made explicit as a composite key to match the existing
-- lookup exactly).

BEGIN;

CREATE UNIQUE INDEX uq_check_ins_event_registration
    ON check_ins (event_id, registration_id);

COMMIT;
