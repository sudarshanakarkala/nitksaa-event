-- 032_revoked_tokens.sql — sign out ends the session on the server too.
--
-- Each app token carries an id (`jti`). Signing out puts that id here, and
-- the server refuses the token from then on. Rows are only needed until the
-- token would have run out anyway (8 hours), so `expires_at` lets old rows
-- be cleared (logout does that as it goes).
--
-- Run in Cloud SQL Studio (event_db) after a backup, BEFORE merging: once
-- merged, every signed-in request checks this table. Safe to run twice.

BEGIN;

CREATE TABLE IF NOT EXISTS revoked_tokens (
    jti          TEXT        PRIMARY KEY,
    firebase_uid VARCHAR(128) NOT NULL,
    expires_at   TIMESTAMPTZ NOT NULL,
    revoked_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS revoked_tokens_expires_at_idx
    ON revoked_tokens (expires_at);

COMMIT;
