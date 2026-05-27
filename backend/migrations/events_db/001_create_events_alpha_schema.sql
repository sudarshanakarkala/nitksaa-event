-- NITKSAA Event Platform - Alpha Schema
-- events_db (PostgreSQL)
-- Migration: 001_create_events_alpha_schema
--
-- Rules:
--   - No cross-database foreign keys (alumni_db.alumni is referenced by value only)
--   - ref_id = alumni_db.alumni.alumni_id stored as plain TEXT reference

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- events
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS events (
    event_id                BIGSERIAL PRIMARY KEY,
    slug                    TEXT UNIQUE NOT NULL,
    title                   TEXT NOT NULL,
    description             TEXT,
    event_type              TEXT NOT NULL DEFAULT 'event',
    venue_name              TEXT,
    venue_address           TEXT,
    city                    TEXT,
    country                 TEXT NOT NULL DEFAULT 'India',
    is_virtual              BOOLEAN NOT NULL DEFAULT FALSE,
    virtual_url             TEXT,
    starts_at               TIMESTAMPTZ NOT NULL,
    ends_at                 TIMESTAMPTZ,
    timezone                TEXT NOT NULL DEFAULT 'Asia/Kolkata',
    capacity                INTEGER,
    registration_opens_at   TIMESTAMPTZ,
    registration_closes_at  TIMESTAMPTZ,
    status                  TEXT NOT NULL DEFAULT 'draft'
                                CHECK (status IN ('draft','published','closed','cancelled')),
    created_by              TEXT,
    updated_by              TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- sessions
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions (
    session_id   BIGSERIAL PRIMARY KEY,
    event_id     BIGINT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    title        TEXT NOT NULL,
    description  TEXT,
    speaker_name TEXT,
    location     TEXT,
    track_name   TEXT,
    starts_at    TIMESTAMPTZ NOT NULL,
    ends_at      TIMESTAMPTZ,
    capacity     INTEGER,
    status       TEXT NOT NULL DEFAULT 'scheduled',
    sort_order   INTEGER NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- registrations
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS registrations (
    registration_id     BIGSERIAL PRIMARY KEY,
    event_id            BIGINT NOT NULL REFERENCES events(event_id),
    firebase_uid        TEXT,
    ref_id              TEXT,           -- value ref to alumni_db.alumni.alumni_id; no FK
    email               TEXT,
    full_name           TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'registered',
    registration_source TEXT NOT NULL DEFAULT 'api_alpha',
    qr_token            TEXT UNIQUE,
    registered_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled_at        TIMESTAMPTZ,
    cancel_reason       TEXT,
    metadata            JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- attendees
-- Alpha: one registration = one attendee
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS attendees (
    attendee_id      BIGSERIAL PRIMARY KEY,
    registration_id  BIGINT NOT NULL REFERENCES registrations(registration_id),
    event_id         BIGINT NOT NULL REFERENCES events(event_id),
    ref_id           TEXT,           -- value ref to alumni_db.alumni.alumni_id; no FK
    firebase_uid     TEXT,
    attendee_type    TEXT NOT NULL DEFAULT 'alumni',
    display_name     TEXT NOT NULL,
    email            TEXT,
    phone            TEXT,
    badge_name       TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- check_ins
-- Prevents duplicate event-level check-in via unique constraint
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS check_ins (
    check_in_id      BIGSERIAL PRIMARY KEY,
    event_id         BIGINT NOT NULL REFERENCES events(event_id),
    session_id       BIGINT REFERENCES sessions(session_id),
    registration_id  BIGINT REFERENCES registrations(registration_id),
    attendee_id      BIGINT REFERENCES attendees(attendee_id),
    ref_id           TEXT,
    firebase_uid     TEXT,
    qr_token         TEXT,
    checked_in_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checked_in_by    TEXT,
    method           TEXT NOT NULL DEFAULT 'qr',
    notes            TEXT,
    metadata         JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- one check-in per registration per event
    CONSTRAINT uq_checkin_event_registration UNIQUE (event_id, registration_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- check_in_attempts
-- Audit log of every scan attempt (success/duplicate/invalid/unauthorized)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS check_in_attempts (
    attempt_id      BIGSERIAL PRIMARY KEY,
    event_id        BIGINT,
    qr_token        TEXT,
    registration_id BIGINT,
    attendee_id     BIGINT,
    attempt_status  TEXT NOT NULL
                        CHECK (attempt_status IN ('success','duplicate','invalid','unauthorized')),
    attempted_by    TEXT,
    attempted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes           TEXT,
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_events_status_starts_at       ON events (status, starts_at);
CREATE INDEX IF NOT EXISTS idx_events_slug                   ON events (slug);

CREATE INDEX IF NOT EXISTS idx_sessions_event_starts_at      ON sessions (event_id, starts_at);

CREATE INDEX IF NOT EXISTS idx_registrations_event_email     ON registrations (event_id, lower(email));
CREATE INDEX IF NOT EXISTS idx_registrations_event_ref_id    ON registrations (event_id, ref_id);
CREATE INDEX IF NOT EXISTS idx_registrations_qr_token        ON registrations (qr_token);

CREATE INDEX IF NOT EXISTS idx_attendees_event_id            ON attendees (event_id);

CREATE INDEX IF NOT EXISTS idx_check_ins_event_registration  ON check_ins (event_id, registration_id);
CREATE INDEX IF NOT EXISTS idx_check_ins_qr_token            ON check_ins (qr_token);

CREATE INDEX IF NOT EXISTS idx_attempts_event_attempted_at   ON check_in_attempts (event_id, attempted_at);
CREATE INDEX IF NOT EXISTS idx_attempts_qr_token             ON check_in_attempts (qr_token);

COMMIT;
