BEGIN;

CREATE TABLE events (
    event_id                SERIAL        PRIMARY KEY,
    slug                    TEXT          UNIQUE NOT NULL,
    title                   TEXT          NOT NULL,
    tagline                 TEXT,
    description             TEXT,                           -- Markdown
    status                  VARCHAR(20)   NOT NULL DEFAULT 'draft',
                                                            -- draft | published | cancelled | completed
    start_datetime          TIMESTAMPTZ   NOT NULL,
    end_datetime            TIMESTAMPTZ   NOT NULL,
    timezone                VARCHAR(60)   NOT NULL DEFAULT 'Asia/Kolkata',
    location_text           TEXT,
    location_maps_url       TEXT,
    is_virtual              BOOLEAN       NOT NULL DEFAULT false,
    virtual_url             TEXT,
    thumbnail_url           TEXT,
    banner_url              TEXT,
    capacity                INT,                            -- NULL = unlimited
    registration_opens_at   TIMESTAMPTZ,
    registration_closes_at  TIMESTAMPTZ,
    created_by_firebase_uid VARCHAR(128)  NOT NULL,
    created_at              TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ,
    published_at            TIMESTAMPTZ,
    cancelled_at            TIMESTAMPTZ,
    cancelled_reason        TEXT
);

CREATE INDEX idx_events_status         ON events(status);
CREATE INDEX idx_events_start_datetime ON events(start_datetime);

COMMIT;
