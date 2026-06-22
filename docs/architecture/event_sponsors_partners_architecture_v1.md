# Event Sponsors and Partners — Architecture v1

**Date:** 2026-06-22
**Status:** ARCHITECTURE DOCUMENT — do not implement without product owner approval
**Depends on:** migrations 001–009 (existing)
**Related decisions:** `week4_feedback_architecture_decisions.md` Decisions 6 and 7

---

## Why Sponsors and Partners Are Not the Same

This is the central architectural decision in this document. A single merged table
(`event_sponsorships` with a type enum) is the easy path but the wrong one.

**Sponsors** provide financial or brand support. They pay for placement. Their relationship
to the event is transactional. They expect logo placement in specific tiers (Title, Gold,
Silver, Bronze). Sponsors are organized by financial tier, which determines display prominence
and benefits.

**Partners** provide collaboration support. They are not paying for placement — they are
contributing knowledge, media reach, community connections, venue, technology, or
hiring access. The relationship is one of mutual benefit, not purchase. Partners are
organized by the type of value they provide, not by financial level.

Mixing them:
- Conflates financial contribution with collaboration
- Forces a sponsor tier model onto partners (what is the "Gold" equivalent for a media partner?)
- Forces a collaboration type model onto sponsors (what "type" is a Title Sponsor?)
- Creates UI confusion: a title sponsor and a knowledge partner look the same in the data

Keeping them separate:
- Each has its own enum that makes sense for its domain
- Display treatment can differ (sponsors: tier-based prominence; partners: type-grouped listing)
- Business logic for each is independent (sponsor tiers have contractual implications;
  partner types are descriptive)
- Adding new sponsor tiers or partner types does not affect the other table

The performance argument for merging (one join instead of two) is acknowledged. For public event
detail, the backend runs two simple indexed queries and returns two arrays. This is not a
performance concern. Caching the full event detail response addresses any future volume concern.

---

## Proposed Schema

### Table: `event_sponsors`

```sql
CREATE TABLE event_sponsors (
    sponsor_id     SERIAL        PRIMARY KEY,
    event_id       INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    name           TEXT          NOT NULL,
    logo_url       TEXT,
    website_url    TEXT,
    sponsor_type   VARCHAR(30)   NOT NULL
                   CHECK (sponsor_type IN (
                       'TITLE_SPONSOR',
                       'GOLD_SPONSOR',
                       'SILVER_SPONSOR',
                       'BRONZE_SPONSOR',
                       'ASSOCIATE_SPONSOR'
                   )),
    description    TEXT,
    sort_order     INT           NOT NULL DEFAULT 0,
    is_visible     BOOLEAN       NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ
);

CREATE INDEX idx_event_sponsors_event_id ON event_sponsors(event_id);
CREATE INDEX idx_event_sponsors_visible  ON event_sponsors(event_id, is_visible);
```

### Table: `event_partners`

```sql
CREATE TABLE event_partners (
    partner_id     SERIAL        PRIMARY KEY,
    event_id       INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    name           TEXT          NOT NULL,
    logo_url       TEXT,
    website_url    TEXT,
    partner_type   VARCHAR(30)   NOT NULL
                   CHECK (partner_type IN (
                       'COMMUNITY_PARTNER',
                       'KNOWLEDGE_PARTNER',
                       'MEDIA_PARTNER',
                       'VENUE_PARTNER',
                       'TECHNOLOGY_PARTNER',
                       'ECOSYSTEM_PARTNER',
                       'HIRING_PARTNER'
                   )),
    description    TEXT,
    sort_order     INT           NOT NULL DEFAULT 0,
    is_visible     BOOLEAN       NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ
);

CREATE INDEX idx_event_partners_event_id ON event_partners(event_id);
CREATE INDEX idx_event_partners_visible  ON event_partners(event_id, is_visible);
```

---

## Sponsor Type Enum

| Type | Description |
|---|---|
| `TITLE_SPONSOR` | Primary / naming sponsor — highest tier; event may carry their name |
| `GOLD_SPONSOR` | Second tier |
| `SILVER_SPONSOR` | Third tier |
| `BRONZE_SPONSOR` | Fourth tier |
| `ASSOCIATE_SPONSOR` | Supporting sponsor; smaller contribution; typically logo-only placement |

Display rule: sponsors are ordered by tier first (`TITLE_SPONSOR` first), then by `sort_order`
within tier.

---

## Partner Type Enum

| Type | Description |
|---|---|
| `COMMUNITY_PARTNER` | Alumni associations, student chapters, professional groups |
| `KNOWLEDGE_PARTNER` | Research institutions, think tanks, publications |
| `MEDIA_PARTNER` | Press, blogs, video channels, content platforms |
| `VENUE_PARTNER` | Venue provider (when venue is a distinct organization) |
| `TECHNOLOGY_PARTNER` | Tech platform, tool, or infrastructure provider |
| `ECOSYSTEM_PARTNER` | Startup ecosystems, incubators, accelerators |
| `HIRING_PARTNER` | Companies actively recruiting at the event |

Display rule: partners are grouped by type, ordered by `sort_order` within each type group.

---

## API Response Shape

### Public event detail additions

`GET /api/v1/events/public/{event_id}` or `GET /api/v1/events/{slug}`

```json
{
  "event_id": 3,
  "sponsors": [
    {
      "sponsor_id": 1,
      "name": "Acme Technologies",
      "logo_url": "https://storage.googleapis.com/...",
      "website_url": "https://acme.com",
      "sponsor_type": "TITLE_SPONSOR",
      "description": "Acme Technologies is the title sponsor of NITKonnect 2026.",
      "sort_order": 0
    },
    {
      "sponsor_id": 2,
      "name": "BuildFast",
      "logo_url": "https://storage.googleapis.com/...",
      "website_url": "https://buildfast.io",
      "sponsor_type": "GOLD_SPONSOR",
      "description": null,
      "sort_order": 0
    }
  ],
  "partners": [
    {
      "partner_id": 1,
      "name": "TechCrunch India",
      "logo_url": "https://storage.googleapis.com/...",
      "website_url": "https://techcrunch.com/india",
      "partner_type": "MEDIA_PARTNER",
      "description": null,
      "sort_order": 0
    },
    {
      "partner_id": 2,
      "name": "NITK Alumni Association, Bangalore Chapter",
      "logo_url": null,
      "website_url": null,
      "partner_type": "COMMUNITY_PARTNER",
      "description": null,
      "sort_order": 0
    }
  ]
}
```

Notes:
- `logo_url` and `website_url` are nullable — not every sponsor/partner has a website or logo in the system.
- `description` is nullable — short context text; not always provided.
- Only `is_visible = true` rows are returned in the public API.
- Sponsors ordered: by tier rank first, then by `sort_order`.
- Partners ordered: by `partner_type` alphabetically, then by `sort_order`.

### Admin API additions (future)

```
POST   /api/v1/admin/events/{event_id}/sponsors           — add a sponsor
PATCH  /api/v1/admin/events/{event_id}/sponsors/{id}      — update a sponsor
DELETE /api/v1/admin/events/{event_id}/sponsors/{id}      — remove a sponsor

POST   /api/v1/admin/events/{event_id}/partners           — add a partner
PATCH  /api/v1/admin/events/{event_id}/partners/{id}      — update a partner
DELETE /api/v1/admin/events/{event_id}/partners/{id}      — remove a partner
```

---

## Performance and Extensibility Tradeoff

**Performance concern:** Two tables means two queries when fetching public event detail. One
merged table would be one query.

**Why this is not a real concern for Alpha:**

1. The public event detail endpoint is one of the most cacheable responses in the API. A
   published event's sponsors and partners change rarely (once created, not per-request). The
   backend can cache the full event detail response at the route level or return appropriate
   `Cache-Control` headers for CDN caching.

2. Two simple indexed queries (`WHERE event_id = $1 AND is_visible = true`) on small tables
   (most events have fewer than 10 sponsors and 10 partners) complete in microseconds.

3. The complexity saved by a merged table is minimal. The complexity introduced by needing to
   union two different type domains in the same table is ongoing.

**Extensibility benefit:** Adding a new partner type (e.g., `GOVERNMENT_PARTNER` in future) is
one line in a migration (`ALTER TABLE event_partners ALTER COLUMN partner_type TYPE ... USING ...`
or add to the CHECK constraint). Adding a new partner type to a merged table would require
careful handling of the shared enum to avoid affecting the sponsor rows.

---

## Admin UI Future Needs

The admin portal event form (`EventFormPage.jsx`) needs two new sections:

**Sponsors section:**
- Add sponsor form: name, logo_url, website_url, sponsor_type (dropdown), description, sort_order
- Sponsor list grouped by tier, with reorder controls
- Toggle `is_visible` per sponsor

**Partners section:**
- Add partner form: name, logo_url, website_url, partner_type (dropdown), description, sort_order
- Partner list grouped by type
- Toggle `is_visible` per partner

Logo upload: requires a file upload endpoint (Cloud Storage) — this is a separate infrastructure
decision. For Alpha, `logo_url` can be a manually entered URL pointing to an externally hosted image.

---

## Flutter / Website Impact

### Flutter event detail screen

A new "Sponsors & Partners" section below the event description or at the bottom of the detail screen:
- Sponsors: logo grid with tier label, linked to `website_url`
- Partners: logo grid grouped by type, linked to `website_url`
- Only shown when `sponsors.length > 0` or `partners.length > 0`

### Website integration

The website calls the Event App public API directly. When `sponsors` and `partners` are added
to the public event detail response, the website consumes them without a new API contract
negotiation. The additions are purely additive.

---

## Implementation Recommendation

**Do not implement in Week 4.** Write this document. Confirm the separate-table decision with
the product owner. Implement in Week 5 or later when the first event with confirmed sponsor or
partner relationships is being created.

Neither the Alpha demo events (Breakfast Club, Webinar) nor the Jun 30 beta require sponsor/partner
display. The architecture gap is acknowledged and the design is ready to implement.
