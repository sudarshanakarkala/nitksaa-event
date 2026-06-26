# Week 5 Phase 2 — Backend Foundations Verification Report

**Date:** 2026-06-26  
**Phase:** 2 — People/Speakers, Sponsors/Partners, Analytics Logging  
**Status:** PASS

---

## 1. Scope

Phase 2 implements three backend foundations on top of Phase 1 (Full Day + Free/Paid):

| Foundation | Tables | Admin API | Public API | Analytics |
|---|---|---|---|---|
| People / Speakers | `event_people`, `session_people` | CRUD | `people[]`, `speakers[]` in event detail | — |
| Sponsors | `event_sponsors` | CRUD | `sponsors[]` in event detail | — |
| Partners | `event_partners` | CRUD | `partners[]` in event detail | — |
| Analytics | `event_activity_log` | — | — | Fire-and-forget log |

**Not implemented in Phase 2 (deferred):** QR attendance, rewards, meeting OAuth, payment processing, React Admin UI controls, Flutter UI for enrichment data.

---

## 2. Database Migrations

### Migration 011 — People

```
Table: event_people
  - person_id SERIAL PK
  - event_id FK → events
  - role person_role ENUM (HOST, MODERATOR, SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR, ORGANIZER)
  - fullname TEXT NOT NULL
  - title, organisation, bio, photo_url, linkedin_url TEXT (optional)
  - display_order INT DEFAULT 0
  - is_visible BOOL DEFAULT true
  - created_at, updated_at TIMESTAMPTZ

Table: session_people
  - session_id FK → sessions
  - person_id FK → event_people
  - role person_role
  - display_order INT DEFAULT 0
  - PRIMARY KEY (session_id, person_id, role)
```

Applied: **PASS** — `CREATE TYPE`, `CREATE TABLE`, indexes, comments all confirmed.

### Migration 012 — Sponsors & Partners

```
Table: event_sponsors
  - sponsor_id SERIAL PK
  - event_id FK → events
  - sponsor_type TEXT CHECK (TITLE_SPONSOR, GOLD_SPONSOR, SILVER_SPONSOR, BRONZE_SPONSOR, ASSOCIATE_SPONSOR)
  - name, logo_url, website_url, description, display_order, is_visible

Table: event_partners
  - partner_id SERIAL PK
  - event_id FK → events
  - partner_type TEXT CHECK (7 types)
  - name, logo_url, website_url, description, display_order, is_visible
```

Applied: **PASS**

### Migration 013 — Analytics

```
Table: event_activity_log
  - activity_id BIGSERIAL PK
  - event_id FK nullable
  - firebase_uid TEXT nullable
  - action_type TEXT CHECK (11 values)
  - source_app TEXT CHECK (FLUTTER, ADMIN, BACKEND, EMAIL, SYSTEM)
  - metadata JSONB DEFAULT '{}'
  - created_at TIMESTAMPTZ DEFAULT NOW()
```

Applied: **PASS**

---

## 3. Backend Code

### 3.1 Schemas

| File | Status |
|---|---|
| `backend/app/schemas/people.py` | `PersonCreate`, `PersonUpdate`, `PersonResponse`, `PublicPersonResponse` |
| `backend/app/schemas/sponsors_partners.py` | `SponsorCreate/Update/Response`, `PartnerCreate/Update/Response` |
| `backend/app/schemas/analytics.py` | `ActivityLogResponse` |

All schemas include `field_validator` for role/type enums with case-insensitive normalization.

### 3.2 Repositories

| File | Status |
|---|---|
| `backend/app/repositories/people_repository.py` | `list_by_event`, `list_public_by_event`, `get`, `create`, `update`, `delete` |
| `backend/app/repositories/sponsors_partners_repository.py` | `SponsorsRepository` + `PartnersRepository`, same method set |

`list_public_by_event` selects only `is_visible=true` rows and excludes the `is_visible` column from the result.

### 3.3 Analytics Service

`backend/app/services/analytics_service.py` — fire-and-forget pattern:
- `log_event_activity()` catches all exceptions, logs WARNING, never raises
- Integrated into `registration_service.py` at: `REGISTRATION_COMPLETED`, `REGISTRATION_FAILED`, `EMAIL_SENT`, `EMAIL_FAILED`

### 3.4 Admin API Routers

| File | Endpoints |
|---|---|
| `backend/app/api/people.py` | `GET/POST /events/{id}/people`, `PUT/DELETE /events/{id}/people/{pid}` |
| `backend/app/api/sponsors_partners.py` | Same pattern for sponsors and partners |

Both use `get_admin_user` dependency — all routes are admin-only.

### 3.5 Public Event Detail (`EventsService.get_public_event`)

Updated to fetch and embed:
- `people[]` — visible people ordered by display_order
- `speakers[]` — derived: `role=SPEAKER` AND visible
- `sponsors[]` — visible sponsors ordered by display_order
- `partners[]` — visible partners ordered by display_order

### 3.6 `main.py` Registration

```python
app.include_router(people.router)
app.include_router(sponsors_partners.router)
app.include_router(week5_diagnostics.router)
```

Route count: 60 (up from ~48 before Phase 2).

---

## 4. Phase 1 Smoke Test (Migration 010)

Verified before Phase 2 implementation:

| Check | Result |
|---|---|
| Create full-day event (`is_full_day=true`) | PASS — `is_full_day=True is_free=True ticket_price=None` |
| Create paid event (`is_free=false, ticket_price=500`) | PASS — `is_free=False ticket_price=500.00` |
| Public endpoint includes `is_full_day`, `is_free`, `ticket_price` | PASS |
| Existing events default correctly | PASS |

---

## 5. Week 5 Diagnostics — Automated Verification

Run via: `curl -H "X-Dev-User: admin" http://localhost:8000/api/v1/dev/diagnostics/week5/all`

### Summary

```
OVERALL: status=ok  passed=43/43  failed=0  warnings=0

  week5_event_options:     ok  6/6
  week5_people:            ok  11/11
  week5_sponsors_partners: ok  15/15
  week5_analytics:         ok  11/11
```

### `week5/event-options` (6/6 PASS)

| Test | Result |
|---|---|
| Create full-day event, verify `is_full_day=true` | PASS |
| Full-day fields in admin response | PASS |
| Create paid event, verify `is_free=false, ticket_price=500` | PASS |
| Public detail: full-day fields present | PASS |
| Public detail: paid fields present | PASS |
| Backward compat: existing events have boolean defaults | PASS |

### `week5/people` (11/11 PASS)

| Test | Result |
|---|---|
| Create diagnostic event | PASS |
| Add HOST, SPEAKER, PANELIST | PASS × 3 |
| Add hidden SPEAKER (`is_visible=false`) | PASS |
| Admin list: 4 people (including hidden) | PASS |
| Speakers subset: 1 SPEAKER role, visible only | PASS |
| Public `people[]`: 3 visible people | PASS |
| Hidden person NOT in public response | PASS |
| Update person title | PASS |
| Delete person | PASS |

### `week5/sponsors-partners` (15/15 PASS)

| Test | Result |
|---|---|
| Create diagnostic event | PASS |
| Add TITLE_SPONSOR, GOLD_SPONSOR, hidden BRONZE_SPONSOR | PASS × 3 |
| Add COMMUNITY_PARTNER, KNOWLEDGE_PARTNER, hidden MEDIA_PARTNER | PASS × 3 |
| Admin list sponsors: 3 (including hidden) | PASS |
| Admin list partners: 3 (including hidden) | PASS |
| Public sponsors: 2 visible, no `is_visible` field | PASS |
| Public partners: 2 visible | PASS |
| Sponsors and partners use correct ID keys | PASS |
| Update sponsor description | PASS |
| Update partner description | PASS |
| Delete all 6 test records | PASS |

### `week5/analytics` (11/11 PASS)

| Test | Result |
|---|---|
| Create diagnostic event | PASS |
| Log EVENT_DETAIL_OPENED, REGISTER_CLICKED, REGISTRATION_COMPLETED, REGISTRATION_FAILED, EMAIL_SENT, EMAIL_FAILED | PASS × 6 |
| Rows present in `event_activity_log` | PASS |
| Metadata JSON stored correctly | PASS |
| `source_app` present in all rows | PASS |
| No secrets in metadata | PASS |

---

## 6. Admin CRUD Smoke Test

Direct API calls to verify the HTTP surface:

```
POST /api/v1/events/148/people → person_id=9, role=SPEAKER
GET  /api/v1/events/148/people → count=1
PUT  /api/v1/events/148/people/9 → title=Updated Prof
POST /api/v1/events/148/sponsors → sponsor_id=10, type=GOLD_SPONSOR
POST /api/v1/events/148/partners → partner created
GET  /api/v1/events/public/148 → people=1, speakers=1, sponsors=1, partners=1
```

Result: **PASS**

---

## 7. Backward Compatibility

| Concern | Status |
|---|---|
| Events without people/sponsors/partners return `[]` in public detail | PASS |
| Existing public event responses not broken | PASS — `people`, `speakers`, `sponsors`, `partners` are additive |
| Migrations 001–010 unmodified | PASS |
| Registration flow unchanged | PASS — analytics logs are fire-and-forget |
| `session_people` table exists (ready for future session linking) | DB confirmed |

---

## 8. Known Gaps (deferred to future phases)

| Gap | Phase |
|---|---|
| React Admin UI for people/sponsors/partners management | Deferred |
| Flutter UI display of people[], sponsors[], partners[] | Deferred |
| Session people linking in admin | Deferred |
| Analytics dashboard / read API | Deferred |
| CLIENT-side analytics logging (Flutter app events) | Deferred |
| Cloud SQL migration of 011, 012, 013 | Required before production deploy |

---

## 9. Verdict

| Layer | Result |
|---|---|
| Migrations 011–013 | PASS |
| Schemas (people, sponsors_partners, analytics) | PASS |
| Repositories (people, sponsors, partners) | PASS |
| Analytics service (fire-and-forget) | PASS |
| Analytics hooks in registration service | PASS |
| Admin API routers (people, sponsors_partners) | PASS |
| Public event detail enrichment | PASS |
| Week 5 diagnostics (43/43) | PASS |
| Backend imports clean (60 routes) | PASS |
| Backward compatibility | PASS |

**Overall: PASS** — Phase 2 backend foundations complete. Phase 3+ can proceed when ready.
