-- 034_session_details.sql — session details for big events (NITKonnect).
--
-- Optional, so every event without them looks as before:
-- - sessions.session_type: KEYNOTE, TALK, PANEL, FIRESIDE, WORKSHOP,
--   SHOWCASE, NETWORKING, AWARDS or BREAK (checked by the server, so a new
--   type needs no migration); a BREAK shows as a band on the agenda;
-- - sessions.pillar: free text ("Career Konnect"); the agenda filters by it;
-- - event_sponsors.label: free text shown instead of the tier
--   ("Co-presenter");
-- - session_sponsors: the sponsors presenting a session ("X Presents"),
--   in order.
--
-- Run in Cloud SQL Studio (event_db) after a backup, BEFORE merging: once
-- merged, the event pages read these. Only adds; safe to run twice.

BEGIN;

ALTER TABLE sessions       ADD COLUMN IF NOT EXISTS session_type TEXT;
ALTER TABLE sessions       ADD COLUMN IF NOT EXISTS pillar TEXT;
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS label TEXT;

CREATE TABLE IF NOT EXISTS session_sponsors (
    session_id    INTEGER NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    sponsor_id    INTEGER NOT NULL REFERENCES event_sponsors(sponsor_id) ON DELETE CASCADE,
    display_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (session_id, sponsor_id)
);

CREATE INDEX IF NOT EXISTS idx_session_sponsors_session ON session_sponsors(session_id);

COMMIT;
