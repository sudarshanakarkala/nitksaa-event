-- Week 5 Phase 2B: Sponsors and Partners foundation

BEGIN;

CREATE TABLE event_sponsors (
    sponsor_id      SERIAL PRIMARY KEY,
    event_id        INTEGER      NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    sponsor_type    TEXT         NOT NULL CHECK (sponsor_type IN (
                        'TITLE_SPONSOR', 'GOLD_SPONSOR', 'SILVER_SPONSOR',
                        'BRONZE_SPONSOR', 'ASSOCIATE_SPONSOR'
                    )),
    name            TEXT         NOT NULL,
    logo_url        TEXT,
    website_url     TEXT,
    description     TEXT,
    display_order   INTEGER      NOT NULL DEFAULT 0,
    is_visible      BOOLEAN      NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_event_sponsors_event    ON event_sponsors(event_id);
CREATE INDEX idx_event_sponsors_visible  ON event_sponsors(event_id, is_visible, display_order);

CREATE TABLE event_partners (
    partner_id      SERIAL PRIMARY KEY,
    event_id        INTEGER      NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    partner_type    TEXT         NOT NULL CHECK (partner_type IN (
                        'COMMUNITY_PARTNER', 'KNOWLEDGE_PARTNER', 'MEDIA_PARTNER',
                        'VENUE_PARTNER', 'TECHNOLOGY_PARTNER',
                        'ECOSYSTEM_PARTNER', 'HIRING_PARTNER'
                    )),
    name            TEXT         NOT NULL,
    logo_url        TEXT,
    website_url     TEXT,
    description     TEXT,
    display_order   INTEGER      NOT NULL DEFAULT 0,
    is_visible      BOOLEAN      NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_event_partners_event    ON event_partners(event_id);
CREATE INDEX idx_event_partners_visible  ON event_partners(event_id, is_visible, display_order);

COMMENT ON TABLE event_sponsors IS 'Sponsors attached to events (display only)';
COMMENT ON TABLE event_partners IS 'Partners attached to events (display only)';
COMMENT ON COLUMN event_sponsors.is_visible IS 'False = admin-hidden; not returned in public API responses';
COMMENT ON COLUMN event_partners.is_visible IS 'False = admin-hidden; not returned in public API responses';

COMMIT;
