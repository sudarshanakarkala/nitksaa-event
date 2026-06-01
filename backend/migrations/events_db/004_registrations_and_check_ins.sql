BEGIN;

CREATE TABLE registrations (
    registration_id         SERIAL        PRIMARY KEY,
    event_id                INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    firebase_uid            VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid),
    ref_id                  VARCHAR(128),
    badge_name              TEXT          NOT NULL,
    email                   TEXT          NOT NULL,
    phone                   TEXT,
    attendee_type           VARCHAR(50),
    status                  VARCHAR(20)   NOT NULL DEFAULT 'confirmed',
    qrtoken                 TEXT          UNIQUE NOT NULL,
    confirmation_email_sent BOOLEAN       NOT NULL DEFAULT false,
    notes                   TEXT,
    registered_at           TIMESTAMPTZ   NOT NULL DEFAULT now(),
    cancelled_at            TIMESTAMPTZ,
    UNIQUE (event_id, firebase_uid)
);

CREATE INDEX idx_registrations_event_id     ON registrations(event_id);
CREATE INDEX idx_registrations_firebase_uid ON registrations(firebase_uid);
CREATE INDEX idx_registrations_qrtoken      ON registrations(qrtoken);
CREATE INDEX idx_registrations_status       ON registrations(event_id, status);

CREATE TABLE check_ins (
    checkin_id       SERIAL        PRIMARY KEY,
    registration_id  INT           NOT NULL REFERENCES registrations(registration_id),
    event_id         INT           NOT NULL REFERENCES events(event_id),
    scanned_by       VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid),
    scanned_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    session_id       INT           REFERENCES sessions(session_id),
    result           VARCHAR(20)   NOT NULL CHECK (result IN ('success', 'duplicate', 'invalid'))
);

CREATE INDEX idx_checkins_registration_id ON check_ins(registration_id);
CREATE INDEX idx_checkins_event_id        ON check_ins(event_id);

COMMIT;
