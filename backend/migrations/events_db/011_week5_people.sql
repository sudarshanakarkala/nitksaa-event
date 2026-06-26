-- Week 5 Phase 2A: People / Speakers foundation
-- event_people: people attached to an event with a role
-- session_people: link people to specific sessions within an event

BEGIN;

CREATE TYPE person_role AS ENUM (
    'HOST',
    'MODERATOR',
    'SPEAKER',
    'PANELIST',
    'CHIEF_GUEST',
    'GUEST_OF_HONOUR',
    'ORGANIZER'
);

CREATE TABLE event_people (
    person_id        SERIAL PRIMARY KEY,
    event_id         INTEGER      NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    role             person_role  NOT NULL,
    fullname         TEXT         NOT NULL,
    title            TEXT,
    organisation     TEXT,
    bio              TEXT,
    photo_url        TEXT,
    linkedin_url     TEXT,
    display_order    INTEGER      NOT NULL DEFAULT 0,
    is_visible       BOOLEAN      NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_event_people_event_id   ON event_people(event_id);
CREATE INDEX idx_event_people_visible    ON event_people(event_id, is_visible, display_order);

CREATE TABLE session_people (
    session_id      INTEGER      NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    person_id       INTEGER      NOT NULL REFERENCES event_people(person_id) ON DELETE CASCADE,
    role            person_role  NOT NULL,
    display_order   INTEGER      NOT NULL DEFAULT 0,
    PRIMARY KEY (session_id, person_id, role)
);

CREATE INDEX idx_session_people_session ON session_people(session_id);

COMMENT ON TABLE event_people   IS 'People (speakers, hosts, guests, etc.) attached to events';
COMMENT ON TABLE session_people IS 'Link between people and specific sessions within an event';
COMMENT ON COLUMN event_people.is_visible   IS 'False = admin-hidden; not returned in public API responses';
COMMENT ON COLUMN event_people.display_order IS 'Lower values displayed first';

COMMIT;
