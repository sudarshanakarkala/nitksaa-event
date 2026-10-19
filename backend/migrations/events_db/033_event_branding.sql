-- 033_event_branding.sql — an event's own branding (B6, NITKonnect).
--
-- Optional, so every event without branding looks as before:
-- - brand_logo_url: the logo on light backgrounds;
-- - brand_logo_dark_url: the logo on dark backgrounds (e.g. a white one);
-- - brand_accent: one colour, as #RRGGBB.
-- The wide banner stays in banner_url.
--
-- Run in Cloud SQL Studio (event_db) after a backup, BEFORE merging: once
-- merged, the event pages read these columns. Only adds; safe to run twice.

BEGIN;

ALTER TABLE events ADD COLUMN IF NOT EXISTS brand_logo_url TEXT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS brand_logo_dark_url TEXT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS brand_accent TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'events_brand_accent_hex'
    ) THEN
        ALTER TABLE events ADD CONSTRAINT events_brand_accent_hex
            CHECK (brand_accent IS NULL OR brand_accent ~ '^#[0-9A-Fa-f]{6}$');
    END IF;
END $$;

COMMIT;
