# Week 5 — Event Enrichment API Contract

**Date:** 2026-06-26  
**Phase:** 2 — Backend Foundations (People, Sponsors, Partners, Analytics)  
**Status:** Implemented and verified

---

## Overview

Phase 2 adds three enrichment resources to events:

| Resource | Tables | Scope |
|---|---|---|
| People / Speakers | `event_people`, `session_people` | Speakers, hosts, guests, panelists, etc. |
| Sponsors | `event_sponsors` | Sponsors with tier classification |
| Partners | `event_partners` | Community, knowledge, media, and other partners |

All enrichment resources are:
- **Admin-managed** — CRUD via admin API endpoints
- **Publicly readable** — visible records surfaced in `GET /api/v1/events/public/{id}`
- **Visibility-gated** — `is_visible=false` records never appear in public responses

Analytics logging (`event_activity_log`) is backend-only — no public read endpoint.

---

## Part A — People / Speakers

### Admin Endpoints

All require `X-Dev-User: admin` header (dev) or Bearer JWT with admin role (prod).

#### `GET /api/v1/events/{event_id}/people`
Returns all people for the event (including hidden). Admin-only.

**Response:** `Array<PersonResponse>`
```json
[
  {
    "person_id": 1,
    "event_id": 12,
    "role": "SPEAKER",
    "fullname": "Dr. Jane Doe",
    "title": "Professor of Computer Science",
    "organisation": "NITK",
    "bio": "...",
    "photo_url": null,
    "linkedin_url": null,
    "display_order": 0,
    "is_visible": true,
    "created_at": "2026-06-26T10:00:00Z",
    "updated_at": "2026-06-26T10:00:00Z"
  }
]
```

#### `POST /api/v1/events/{event_id}/people`
Create a person for an event. Returns `201 Created`.

**Request body:**
```json
{
  "role": "SPEAKER",
  "fullname": "Dr. Jane Doe",
  "title": "Professor",
  "organisation": "NITK",
  "bio": "...",
  "photo_url": null,
  "linkedin_url": null,
  "display_order": 0,
  "is_visible": true
}
```

**Valid `role` values:** `HOST`, `MODERATOR`, `SPEAKER`, `PANELIST`, `CHIEF_GUEST`, `GUEST_OF_HONOUR`, `ORGANIZER`

#### `PUT /api/v1/events/{event_id}/people/{person_id}`
Update any person fields. All fields optional.

**Request body:** same shape as POST, all fields optional.

#### `DELETE /api/v1/events/{event_id}/people/{person_id}`
Hard delete. Returns `204 No Content`.

**Errors:**
- `404 event_not_found` — event does not exist
- `404 person_not_found` — person does not exist or belongs to a different event
- `422` — invalid role value

---

### Public Event Detail: People and Speakers

`GET /api/v1/events/public/{event_id}` response now includes:

```json
{
  "event_id": 12,
  "...": "...",
  "people": [
    {
      "person_id": 1,
      "role": "HOST",
      "fullname": "Dr. Jane Doe",
      "title": "Chief Host",
      "organisation": "NITK",
      "bio": null,
      "photo_url": null,
      "linkedin_url": null,
      "display_order": 0
    }
  ],
  "speakers": [
    {
      "person_id": 2,
      "role": "SPEAKER",
      "fullname": "Prof. Example",
      "...": "..."
    }
  ]
}
```

**Rules:**
- `people[]` — all visible (`is_visible=true`) people, ordered by `display_order ASC, person_id ASC`
- `speakers[]` — derived subset: `is_visible=true` AND `role` in `{SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR}`. HOST, MODERATOR, and ORGANIZER are excluded from this subset.
- `is_visible` field never returned in public response
- `sessions` array is present but empty (`[]`) until session people is implemented in UI

---

## Part B — Sponsors

### Admin Endpoints

#### `GET /api/v1/events/{event_id}/sponsors`
Returns all sponsors (including hidden).

**Response:** `Array<SponsorResponse>`
```json
[
  {
    "sponsor_id": 1,
    "event_id": 12,
    "sponsor_type": "TITLE_SPONSOR",
    "name": "Acme Corp",
    "logo_url": "https://example.com/logo.png",
    "website_url": "https://acme.com",
    "description": null,
    "display_order": 0,
    "is_visible": true,
    "created_at": "2026-06-26T10:00:00Z",
    "updated_at": "2026-06-26T10:00:00Z"
  }
]
```

#### `POST /api/v1/events/{event_id}/sponsors`
Create a sponsor. Returns `201 Created`.

**Valid `sponsor_type` values:** `TITLE_SPONSOR`, `GOLD_SPONSOR`, `SILVER_SPONSOR`, `BRONZE_SPONSOR`, `ASSOCIATE_SPONSOR`

#### `PUT /api/v1/events/{event_id}/sponsors/{sponsor_id}`
Update sponsor. All fields optional.

#### `DELETE /api/v1/events/{event_id}/sponsors/{sponsor_id}`
Hard delete. Returns `204 No Content`.

---

### Public Event Detail: Sponsors

```json
{
  "sponsors": [
    {
      "sponsor_id": 1,
      "sponsor_type": "TITLE_SPONSOR",
      "name": "Acme Corp",
      "logo_url": "https://example.com/logo.png",
      "website_url": "https://acme.com",
      "description": null,
      "display_order": 0
    }
  ]
}
```

**Rules:** Only `is_visible=true` sponsors. `is_visible` not returned. Ordered by tier rank (TITLE → GOLD → SILVER → BRONZE → ASSOCIATE), then `display_order ASC`, then `sponsor_id ASC` within the same tier.

---

## Part C — Partners

### Admin Endpoints

#### `GET /api/v1/events/{event_id}/partners`
Returns all partners (including hidden).

**Valid `partner_type` values:** `COMMUNITY_PARTNER`, `KNOWLEDGE_PARTNER`, `MEDIA_PARTNER`, `VENUE_PARTNER`, `TECHNOLOGY_PARTNER`, `ECOSYSTEM_PARTNER`, `HIRING_PARTNER`

#### `POST /api/v1/events/{event_id}/partners` — `201 Created`
#### `PUT /api/v1/events/{event_id}/partners/{partner_id}`
#### `DELETE /api/v1/events/{event_id}/partners/{partner_id}` — `204 No Content`

---

### Public Event Detail: Partners

```json
{
  "partners": [
    {
      "partner_id": 1,
      "partner_type": "COMMUNITY_PARTNER",
      "name": "NITK Alumni Association",
      "logo_url": null,
      "website_url": null,
      "description": null,
      "display_order": 0
    }
  ]
}
```

**Rules:** Only `is_visible=true` partners. `is_visible` not returned. Ordered by `partner_type ASC` (alphabetical), then `display_order ASC`, then `partner_id ASC`.

---

## Part D — Analytics Logging

### `event_activity_log` table

Append-only. No public read endpoint. Backend writes only.

| Column | Type | Notes |
|---|---|---|
| `activity_id` | `BIGSERIAL PK` | Auto-increment |
| `event_id` | `INTEGER FK` | Nullable — null for non-event actions |
| `firebase_uid` | `TEXT` | Nullable — null for anonymous/system |
| `action_type` | `TEXT CHECK` | See valid values below |
| `source_app` | `TEXT CHECK` | `FLUTTER`, `ADMIN`, `BACKEND`, `EMAIL`, `SYSTEM` |
| `metadata` | `JSONB` | Action-specific context; no PII |
| `created_at` | `TIMESTAMPTZ` | Default `NOW()` |

**Valid `action_type` values:**

| Action | Triggered by |
|---|---|
| `EVENT_VIEWED` | Flutter — public event list view |
| `EVENT_DETAIL_OPENED` | Flutter — event detail opened |
| `REGISTER_CLICKED` | Flutter — register button tapped |
| `REGISTRATION_COMPLETED` | Backend — registration created |
| `REGISTRATION_FAILED` | Backend — registration rejected |
| `JOIN_LINK_CLICKED` | Flutter — virtual join link tapped |
| `MAP_CLICKED` | Flutter — map link tapped |
| `CALENDAR_CLICKED` | Flutter — add to calendar tapped |
| `EMAIL_SENT` | Email service — confirmation sent |
| `EMAIL_FAILED` | Email service — confirmation failed |
| `EVENT_SHARED` | Flutter — share button used |

### Analytics Service API

```python
from app.services.analytics_service import log_event_activity

await log_event_activity(
    action_type="REGISTRATION_COMPLETED",
    source_app="BACKEND",
    event_id=42,
    firebase_uid="abc123",
    metadata={"registration_number": "NITKSAA-2025-000001"},
)
```

**Important:** `log_event_activity` is fire-and-forget — it never raises. A failed write is logged at WARNING level and silently swallowed so analytics never block the critical path.

### Currently hooked (Phase 2 baseline)

| Action | Location |
|---|---|
| `REGISTRATION_COMPLETED` | `registration_service.register_for_event` — after transaction commits |
| `REGISTRATION_FAILED` | `registration_service.register_for_event` — already_registered and event_full |
| `EMAIL_SENT` | `registration_service.register_for_event` — after email send |
| `EMAIL_FAILED` | `registration_service.register_for_event` — after email failure |

---

## Admin Portal Usage

The React admin portal (`admin/event_admin`) manages all enrichment resources via:

- **`src/api/enrichmentApi.js`** — 12 methods covering GET/POST/PUT/DELETE for people, sponsors, partners
- **`src/pages/EventEnrichmentPanel.jsx`** — tabbed UI rendered below the event form in edit mode only

### API URL used by admin portal

| Resource | Base URL |
|---|---|
| People | `/api/v1/events/{event_id}/people` |
| Sponsors | `/api/v1/events/{event_id}/sponsors` |
| Partners | `/api/v1/events/{event_id}/partners` |

> **Note:** The spec originally listed `/api/v1/admin/events/{id}/people` but the actual backend router prefix is `/api/v1/events/{id}/people`. The admin portal uses the actual backend URLs. URL prefix alignment is deferred.

### Enrichment panel access

After creating a new event, the portal navigates to `/events/{id}/edit` so the enrichment panel is immediately accessible. The panel is edit-mode only — it does not appear on the create form.

### Admin list vs public list

Admin CRUD endpoints return **all** records including `is_visible=false` items. The panel shows a `Visible` / `Hidden` badge for each item. The public event detail only returns `is_visible=true` items and never includes the `is_visible` field.

---

## Backward Compatibility

All changes are additive only:

| Change | Impact |
|---|---|
| `people[]`, `speakers[]`, `sponsors[]`, `partners[]` added to public event detail | New fields default to `[]` — existing Flutter `fromJson` is unaffected |
| `is_full_day`, `is_free`, `ticket_price` added to event responses | All have safe defaults — Phase 1 backward compat preserved |
| Migrations 011–013 | Additive only, no modifications to existing tables |
| Analytics writes | Fire-and-forget; never block registration |

---

## Migration Reference

| Migration | Purpose |
|---|---|
| `011_week5_people.sql` | `event_people`, `session_people`, `person_role` enum |
| `012_week5_sponsors_partners.sql` | `event_sponsors`, `event_partners` |
| `013_week5_analytics.sql` | `event_activity_log` |
