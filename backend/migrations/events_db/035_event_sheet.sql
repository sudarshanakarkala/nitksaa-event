-- 035_event_sheet.sql — an event's Google Sheet, and speakers' private details (B7).
--
-- Optional, so every event without a sheet looks and saves as before:
-- - events.agenda_sheet_url: the linked Google Sheet. While it is set, the
--   event's speakers, sessions and sponsors come from the sheet (Refresh);
--   admin only, never in the public event.
-- - events.agenda_sheet_read_at: when the sheet was last read (Refresh).
-- - event_people.email, event_people.phone: for organisers to contact a
--   speaker; admin only, never in the public event.
-- - event_people.batch: shown on the speaker card, e.g. "Electrical &
--   Electronics, 1981" (from the sheet or the alumni directory).
-- - event_people.alumni_id: the alumni directory record the speaker matched.
--
-- Run in Cloud SQL Studio (event_db) after a backup, BEFORE merging: once
-- merged, the server reads these. Only adds; safe to run twice.

BEGIN;

ALTER TABLE events       ADD COLUMN IF NOT EXISTS agenda_sheet_url     TEXT;
ALTER TABLE events       ADD COLUMN IF NOT EXISTS agenda_sheet_read_at TIMESTAMPTZ;

ALTER TABLE event_people ADD COLUMN IF NOT EXISTS email     TEXT;
ALTER TABLE event_people ADD COLUMN IF NOT EXISTS phone     TEXT;
ALTER TABLE event_people ADD COLUMN IF NOT EXISTS batch     TEXT;
ALTER TABLE event_people ADD COLUMN IF NOT EXISTS alumni_id TEXT;

COMMIT;
