BEGIN;

CREATE TABLE event_users (
    firebase_uid    VARCHAR(128) PRIMARY KEY,
    email           TEXT NOT NULL,
    fullname        TEXT NOT NULL,
    user_type       VARCHAR(20) NOT NULL DEFAULT 'alumni',
    ref_id          TEXT,
    graduation_year INT,
    is_suspended    BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login      TIMESTAMPTZ
);

CREATE INDEX idx_event_users_email    ON event_users(email);
CREATE INDEX idx_event_users_ref_id   ON event_users(ref_id);
CREATE INDEX idx_event_users_type     ON event_users(user_type);

CREATE TABLE event_members (
    event_id      INT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    firebase_uid  VARCHAR(128) NOT NULL REFERENCES event_users(firebase_uid) ON DELETE CASCADE,
    role          VARCHAR(30) NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'active',
    joined_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (event_id, firebase_uid)
);

CREATE INDEX idx_event_members_event_id     ON event_members(event_id);
CREATE INDEX idx_event_members_firebase_uid ON event_members(firebase_uid);
CREATE INDEX idx_event_members_role         ON event_members(role);

COMMIT;
