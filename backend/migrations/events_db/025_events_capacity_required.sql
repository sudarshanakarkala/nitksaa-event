-- 025_events_capacity_required.sql
-- Every event has a capacity; there is no "unlimited" (decision, 11 Oct 2026).
--
-- Publishing already required a positive capacity (_validate_for_publish),
-- but events.capacity was nullable and the admin form offered "Leave empty
-- for unlimited", so drafts could be saved that could never be published.
-- The form (capacity required, >= 1) and the API (EventCreate requires
-- capacity, EventUpdate rejects an explicit null) now enforce it; this
-- migration makes the database agree.
--
-- 1. Backfill: every event with no capacity gets
--    GREATEST(1000, its count of 'registered' registrations), so no event
--    ends up below the number of people already registered. Set specific
--    numbers by hand before running this if 1000 is wrong for an event.
-- 2. capacity becomes NOT NULL with CHECK (capacity > 0).
--
-- Look first (the rows step 1 will change):
--   SELECT event_id, title, status, start_datetime,
--          (SELECT count(*) FROM registrations r
--            WHERE r.event_id = e.event_id AND r.status = 'registered') AS registered
--   FROM events e WHERE capacity IS NULL ORDER BY start_datetime;
--
-- Pre-check (must return 0, or the CHECK fails and the transaction rolls
-- back with nothing changed):
--   SELECT count(*) FROM events WHERE capacity <= 0;
--
-- Take a Cloud SQL backup before running. Run it after the matching code
-- (API and attendee-app form) is live: before that, an event saved with a
-- blank capacity would fail with a database error instead of a clear 422.

BEGIN;

UPDATE events e
SET capacity = GREATEST(
    1000,
    (SELECT count(*) FROM registrations r
      WHERE r.event_id = e.event_id AND r.status = 'registered')
)
WHERE capacity IS NULL;

ALTER TABLE events ALTER COLUMN capacity SET NOT NULL;

ALTER TABLE events
    ADD CONSTRAINT chk_events_capacity_positive CHECK (capacity > 0);

COMMIT;
