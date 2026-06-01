BEGIN;

CREATE TABLE event_audit_log (
log_id BIGSERIAL PRIMARY KEY,
actor_uid VARCHAR(128),
event_type TEXT NOT NULL,
entity_type TEXT NOT NULL,
entity_id INTEGER,
created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
notification_id BIGSERIAL PRIMARY KEY,
firebase_uid VARCHAR(128) NOT NULL,
event_type TEXT NOT NULL,
entity_type TEXT,
entity_id INTEGER,
is_read BOOLEAN NOT NULL DEFAULT false,
created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notification_preferences (
firebase_uid VARCHAR(128) NOT NULL,
event_type TEXT NOT NULL,
push_enabled BOOLEAN NOT NULL DEFAULT true,
PRIMARY KEY (firebase_uid, event_type)
);

COMMIT;
