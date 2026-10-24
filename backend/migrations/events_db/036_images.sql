-- 036_images.sql — photos and logos: a record of every image we store.
--
-- The existing link columns (events.thumbnail_url, banner_url,
-- brand_logo_url, brand_logo_dark_url; event_people.photo_url;
-- event_sponsors.logo_url, event_partners.logo_url) keep holding the full
-- link the pages show. These tables record what each stored file is, where
-- it came from and how it was checked, so it can be reused, replaced and
-- cleaned up later.
--
-- - images: one row per image file in our buckets (or waiting to be checked).
--   The image service checks, converts and resizes; the API writes the row.
--   event_id is kept as NULL when the event is deleted, so the file can still
--   be found and cleaned up.
-- - person_photos: one photo per person, by lower-case email, reused across
--   events. Replace changes the row; deleting the person's photo removes it.
-- - event_people.photo_hidden: "Don't show on this event"; kept across
--   Refreshes of an imported event.
--
-- Run in Cloud SQL Studio (event_db) after a backup, BEFORE merging.
-- Only adds; safe to run twice.

BEGIN;

CREATE TABLE IF NOT EXISTS images (
    image_id       SERIAL       PRIMARY KEY,
    kind           VARCHAR(20)  NOT NULL CHECK (kind IN (
                       'thumbnail', 'banner', 'logo', 'person', 'sponsor_logo'
                   )),
    status         VARCHAR(10)  NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'ready', 'blocked')),
    block_reason   TEXT,                       -- plain words, shown to organisers
    warnings       TEXT[]       NOT NULL DEFAULT '{}',
    bucket         VARCHAR(10)  CHECK (bucket IN ('public', 'private')),
    object_name    TEXT,                       -- random name in the bucket
    url            TEXT,                       -- public link (public bucket only)
    width          INT,
    height         INT,
    bytes          INT,
    source         VARCHAR(10)  NOT NULL CHECK (source IN ('upload', 'drive')),
    source_sha256  TEXT,                       -- of the file as received
    drive_file_id  TEXT,
    drive_md5      TEXT,                       -- Drive's fingerprint of that version
    event_id       INT          REFERENCES events(event_id) ON DELETE SET NULL,
    person_email   TEXT         CHECK (person_email IS NULL OR person_email = lower(person_email)),
    added_by       VARCHAR(128),               -- firebase uid
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    unused_since   TIMESTAMPTZ,                -- replaced or removed; cleaned up 30 days later
    deleted_at     TIMESTAMPTZ                 -- file deleted from the bucket
);

CREATE INDEX IF NOT EXISTS idx_images_event  ON images (event_id);
CREATE INDEX IF NOT EXISTS idx_images_person ON images (person_email);
CREATE INDEX IF NOT EXISTS idx_images_sha    ON images (kind, source_sha256);
CREATE INDEX IF NOT EXISTS idx_images_drive  ON images (kind, drive_file_id, drive_md5);
CREATE INDEX IF NOT EXISTS idx_images_unused ON images (unused_since)
    WHERE unused_since IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS person_photos (
    email       TEXT         PRIMARY KEY CHECK (email = lower(email)),
    image_id    INT          NOT NULL REFERENCES images(image_id),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

ALTER TABLE event_people ADD COLUMN IF NOT EXISTS photo_hidden BOOLEAN NOT NULL DEFAULT false;

COMMIT;
