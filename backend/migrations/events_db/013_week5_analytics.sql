-- Week 5 Phase 2C: Analytics logging foundation

BEGIN;

CREATE TABLE event_activity_log (
    activity_id     BIGSERIAL    PRIMARY KEY,
    event_id        INTEGER      REFERENCES events(event_id) ON DELETE SET NULL,
    firebase_uid    TEXT,
    action_type     TEXT         NOT NULL CHECK (action_type IN (
                        'EVENT_VIEWED', 'EVENT_DETAIL_OPENED',
                        'REGISTER_CLICKED', 'REGISTRATION_COMPLETED', 'REGISTRATION_FAILED',
                        'JOIN_LINK_CLICKED', 'MAP_CLICKED', 'CALENDAR_CLICKED',
                        'EMAIL_SENT', 'EMAIL_FAILED', 'EVENT_SHARED'
                    )),
    source_app      TEXT         NOT NULL DEFAULT 'SYSTEM' CHECK (source_app IN (
                        'FLUTTER', 'ADMIN', 'BACKEND', 'EMAIL', 'SYSTEM'
                    )),
    metadata        JSONB        NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_activity_log_event_id    ON event_activity_log(event_id);
CREATE INDEX idx_activity_log_action_type ON event_activity_log(action_type);
CREATE INDEX idx_activity_log_created_at  ON event_activity_log(created_at DESC);

COMMENT ON TABLE event_activity_log IS 'Append-only analytics log for event and registration actions';
COMMENT ON COLUMN event_activity_log.firebase_uid IS 'NULL for anonymous / system actions';
COMMENT ON COLUMN event_activity_log.event_id     IS 'NULL for non-event-specific actions';
COMMENT ON COLUMN event_activity_log.metadata     IS 'Action-specific context (no PII)';

COMMIT;
