BEGIN;

CREATE TABLE sessions (
    session_id        SERIAL        PRIMARY KEY,
    event_id          INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    track             TEXT,
    title             TEXT          NOT NULL,
    description       TEXT,
    start_datetime    TIMESTAMPTZ   NOT NULL,
    end_datetime      TIMESTAMPTZ   NOT NULL,
    location_text     TEXT,
    speaker_name      TEXT,
    speaker_bio       TEXT,
    speaker_photo_url TEXT,
    sort_order        INT           NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_sessions_event_id ON sessions(event_id);
CREATE INDEX idx_sessions_sort     ON sessions(event_id, sort_order);

COMMIT;
