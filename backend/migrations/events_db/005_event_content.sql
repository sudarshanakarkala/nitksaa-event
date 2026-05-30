BEGIN;

CREATE TABLE event_content (
    content_id    SERIAL        PRIMARY KEY,
    event_id      INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    content_type  VARCHAR(20)   NOT NULL CHECK (content_type IN ('recording', 'gallery')),
    label         TEXT          NOT NULL,
    url           TEXT          NOT NULL,
    sort_order    INT           NOT NULL DEFAULT 0,
    added_by      VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid),
    added_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_event_content_event_id ON event_content(event_id);

COMMIT;
