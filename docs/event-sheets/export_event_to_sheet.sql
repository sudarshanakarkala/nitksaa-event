-- Export events from live into the sheet template's columns.
-- Read only (SELECTs), so no backup needed. Run in Cloud SQL Studio, event_db.
--
-- Step 0: find the two events' links (slugs).
SELECT event_id, slug, title, start_datetime, status
  FROM events
 WHERE title ILIKE '%breakfast%' OR title ILIKE '%konnect%'
 ORDER BY start_datetime DESC;

-- Steps 1–4: put the two slugs in the line marked "THE TWO EVENTS" in each
-- query, run it, and export or copy the result. The first column says which
-- event a row belongs to. Times are in each event's own timezone.

-- 1. Event tab (one row per event)
WITH picked AS (SELECT unnest(ARRAY['nitkonnect-2026-demo', 'bangalore-breakfast-nov-2026']) AS slug)  -- THE TWO EVENTS
SELECT e.slug                                                       AS "event",
       e.title                                                      AS "Title",
       to_char(e.start_datetime AT TIME ZONE e.timezone, 'FMDD Mon YYYY')            AS "Start date",
       CASE WHEN e.is_full_day THEN '' ELSE to_char(e.start_datetime AT TIME ZONE e.timezone, 'FMHH12:MI am') END AS "Start time",
       to_char(e.end_datetime AT TIME ZONE e.timezone, 'FMDD Mon YYYY')              AS "End date",
       CASE WHEN e.is_full_day THEN '' ELSE to_char(e.end_datetime AT TIME ZONE e.timezone, 'FMHH12:MI am') END AS "End time",
       e.timezone                                                   AS "Timezone",
       CASE WHEN e.is_virtual THEN 'Online' ELSE 'In person' END    AS "Where",
       e.location_text                                              AS "Venue",
       e.location_maps_url                                          AS "Map link",
       e.virtual_url                                                AS "Meeting link",
       e.capacity                                                   AS "Capacity",
       CASE WHEN e.is_free THEN NULL ELSE e.ticket_price END        AS "Ticket price",
       e.max_guests                                                 AS "Guests per registration",
       to_char(e.registration_opens_at  AT TIME ZONE e.timezone, 'FMDD Mon YYYY FMHH12:MI am') AS "Registration opens",
       to_char(e.registration_closes_at AT TIME ZONE e.timezone, 'FMDD Mon YYYY FMHH12:MI am') AS "Registration closes",
       e.description                                                AS "Description",
       e.thumbnail_url                                              AS "Thumbnail link",
       e.banner_url                                                 AS "Banner link",
       e.brand_logo_url                                             AS "Logo link",
       e.brand_logo_dark_url                                        AS "Logo link (dark backgrounds)"
  FROM events e JOIN picked USING (slug);

-- 2. Sessions tab
WITH picked AS (SELECT unnest(ARRAY['nitkonnect-2026-demo', 'bangalore-breakfast-nov-2026']) AS slug)  -- THE TWO EVENTS
SELECT e.slug                                                                   AS "event",
       to_char(s.start_datetime AT TIME ZONE e.timezone, 'FMDD Mon YYYY')      AS "Date",
       to_char(s.start_datetime AT TIME ZONE e.timezone, 'FMHH12:MI am')       AS "Start",
       to_char(s.end_datetime   AT TIME ZONE e.timezone, 'FMHH12:MI am')       AS "End",
       s.title                                                                  AS "Title",
       COALESCE(
         (SELECT string_agg(p.fullname, ', ' ORDER BY sp.display_order, p.person_id)
            FROM session_people sp JOIN event_people p ON p.person_id = sp.person_id
           WHERE sp.session_id = s.session_id AND sp.role::text <> 'MODERATOR'),
         s.speaker_name)                                                        AS "Speakers",
       (SELECT string_agg(p.fullname, ', ' ORDER BY sp.display_order, p.person_id)
          FROM session_people sp JOIN event_people p ON p.person_id = sp.person_id
         WHERE sp.session_id = s.session_id AND sp.role::text = 'MODERATOR')   AS "Moderator",
       initcap(lower(s.session_type))                                           AS "Type",
       s.track                                                                  AS "Hall",
       s.pillar                                                                 AS "Pillar",
       s.description                                                            AS "Subtitle",
       (SELECT string_agg(sp2.name, ', ' ORDER BY ss.display_order, sp2.sponsor_id)
          FROM session_sponsors ss JOIN event_sponsors sp2 ON sp2.sponsor_id = ss.sponsor_id
         WHERE ss.session_id = s.session_id)                                    AS "Presented by"
  FROM sessions s JOIN events e ON e.event_id = s.event_id JOIN picked USING (slug)
 ORDER BY e.slug, s.start_datetime, s.sort_order, s.session_id;

-- 3. Speakers tab (people on the event, hosts included; organisers left out)
WITH picked AS (SELECT unnest(ARRAY['nitkonnect-2026-demo', 'bangalore-breakfast-nov-2026']) AS slug)  -- THE TWO EVENTS
SELECT e.slug                                                                   AS "event",
       p.fullname                                                               AS "Name",
       upper(substr(lower(replace(p.role::text, '_', ' ')), 1, 1))
         || substr(lower(replace(p.role::text, '_', ' ')), 2)                   AS "Role",
       p.title                                                                  AS "Title",
       p.organisation                                                           AS "Company",
       p.linkedin_url                                                           AS "LinkedIn",
       p.photo_url                                                              AS "Photo link",
       p.bio                                                                    AS "Bio",
       p.is_visible                                                             AS "visible"
  FROM event_people p JOIN events e ON e.event_id = p.event_id JOIN picked USING (slug)
 WHERE p.role::text <> 'ORGANIZER'
 ORDER BY e.slug, p.display_order, p.person_id;

-- 4. Sponsors tab (sponsors, then partners)
WITH picked AS (SELECT unnest(ARRAY['nitkonnect-2026-demo', 'bangalore-breakfast-nov-2026']) AS slug)  -- THE TWO EVENTS
SELECT "event", "Name", "Tier", "Label", "Logo link", "Website"
  FROM (
    SELECT e.slug AS "event", s.name AS "Name",
           upper(substr(lower(replace(s.sponsor_type, '_', ' ')), 1, 1))
             || substr(lower(replace(s.sponsor_type, '_', ' ')), 2) AS "Tier",
           s.label AS "Label", s.logo_url AS "Logo link", s.website_url AS "Website",
           0 AS kind, s.display_order AS ord, s.sponsor_id AS id
      FROM event_sponsors s JOIN events e ON e.event_id = s.event_id JOIN picked USING (slug)
    UNION ALL
    SELECT e.slug, pa.name,
           upper(substr(lower(replace(pa.partner_type, '_', ' ')), 1, 1))
             || substr(lower(replace(pa.partner_type, '_', ' ')), 2),
           NULL, pa.logo_url, pa.website_url,
           1, pa.display_order, pa.partner_id
      FROM event_partners pa JOIN events e ON e.event_id = pa.event_id JOIN picked USING (slug)
  ) x
 ORDER BY "event", kind, ord, id;
