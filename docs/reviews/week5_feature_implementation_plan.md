# Week 5 — Feature Implementation Plan

**Date:** 2026-06-26
**Status:** APPROVED — Phase 1 active
**Scope:** Weeks 5–8 feature roadmap for nitksaa-event

---

## Governing Rules

- Do NOT break Week 1–4 APIs. All new columns use `DEFAULT` or `NULL`.
- Do NOT modify existing migrations (001–009). New migrations only.
- Payment gateway is out of scope for all phases.
- Meeting OAuth (Google Meet / Zoom token) is architecture-only — no token storage.
- Rewards depend on QR Attendance (Phase 5) and Analytics (Phase 4). Never before.
- People/Speakers and Sponsors/Partners are separate tables and separate phases.
- All new columns are backward-compatible (existing rows silently get `DEFAULT` values).
- Every migration wrapped in `BEGIN / COMMIT`.

---

## Architecture Map

```
events table (010–011)          ← Phase 1 + Phase 2
 └── event_people (012)         ← Phase 3: People / Speakers foundation
 └── event_sponsors (013)       ← Phase 4: Sponsors / Partners foundation
 └── event_analytics_log (014)  ← Phase 5: Analytics logging foundation
 └── event_checkins (existing)  ← Phase 6: QR Attendance (extend check_ins)
 └── event_rewards (015)        ← Phase 6b: Rewards (after QR + Analytics)

Meeting OAuth                   ← Architecture diagram only — no DB/code
Payment                         ← DEFERRED — no DB/code
```

---

## Phase 1 — Full Day Events + Free/Paid Display

**Migration:** `010_week5_phase1_event_options.sql`
**Scope:** events table only

### DB Changes

| Column | Type | Default | Notes |
|---|---|---|---|
| `is_full_day` | `BOOLEAN NOT NULL` | `false` | Hides time fields in UI; dates stored as 00:00 / 23:59 |
| `is_free` | `BOOLEAN NOT NULL` | `true` | Display badge only — no payment |
| `ticket_price` | `NUMERIC(10,2) nullable` | `NULL` | INR only; NULL when is_free=true |

### Constraints

- `chk_ticket_price_non_negative`: `ticket_price IS NULL OR ticket_price >= 0`
- Validator (backend): `is_free=false` requires `ticket_price IS NOT NULL`; `is_free=true` clears ticket_price to NULL

### Backend Changes

- `event_create.py` — add 3 fields; update `validate_event()` for full-day date validation
- `event_update.py` — add 3 optional fields
- `event_response.py` — add to `EventResponse` and `PublicEventResponse`
- `events_repository.py` — add to `_PUBLIC_COLUMNS` and `create_event` INSERT

### Flutter Changes

- `public_event.dart`, `public_event_detail.dart` — add `isFullDay`, `isFree`, `ticketPrice`
- `event_detail_screen.dart` — full-day date display (no time rows); price/free badge row
- `event_list_screen.dart` — free/paid badge on list cards (optional)

### Admin Portal Changes

- `EventFormPage.jsx` — Full Day toggle (date pickers replace datetime-local); Free/Paid toggle with price field
- `eventsApi.js` — no changes (payload is extended transparently)

### Backward Compatibility

All existing events get `is_full_day=false`, `is_free=true`, `ticket_price=NULL`. No API shape changes — only additive fields. Flutter `fromJson` reads with `??` fallback.

---

## Phase 2 — People / Speakers Foundation

**Migration:** `011_week5_phase2_event_people.sql`
**Scope:** New table `event_people`; linking table `event_people_links`

### Design

- `event_people` — standalone people directory (can appear in many events)
  - `person_id, name, designation, bio, photo_url, linkedin_url, created_at`
- `event_people_links` — many-to-many join
  - `event_id, person_id, role (speaker|moderator|panelist|host), sort_order, created_at`
- Public API: `GET /api/v1/events/public/{id}` enriches `speakers` array from this table
- Admin API: `POST /api/v1/admin/events/{id}/people`, `DELETE`, `PATCH` (role/sort_order)

### Backward Compatibility

- `PublicEventDetailResponse.speakers` currently returns `[]` (hardcoded in `events_service.py`). Phase 2 wires it to `event_people_links`. Existing events remain `[]`.
- `PublicEventSpeaker` in Flutter already has `name` and `title` — no Flutter breaking change.

### Rules

- Separate from `sessions` table. Sessions are schedule items; people are humans.
- People directory is global — not per-event. Reuse across events.
- No alumni_db join (speakers may not be NITK alumni).

---

## Phase 3 — Sponsors / Partners Foundation

**Migration:** `012_week5_phase3_event_sponsors.sql`
**Scope:** New table `event_sponsors`; separate from event_people

### Design

- `event_sponsors(sponsor_id, event_id, name, logo_url, website_url, tier, sort_order, created_at)`
  - `tier`: `title | gold | silver | bronze | partner | supporter`
- Admin API: `POST/PATCH/DELETE /api/v1/admin/events/{id}/sponsors`
- Public API: `GET /api/v1/events/public/{id}` includes `sponsors: []`

### Rules

- Sponsors are per-event (not a global directory — logos/tiers differ per event).
- `sponsors` and `partners` share one table — `tier` distinguishes them.
- No payment/financial columns (sponsorship amount is out of scope).
- Flutter `PublicEventDetail` adds `sponsors: []` field.

---

## Phase 4 — Analytics Logging Foundation

**Migration:** `013_week5_phase4_analytics.sql`
**Scope:** New table `event_analytics_log`; backend write-only

### Design

- `event_analytics_log(log_id, event_id, user_uid, action, referrer, device_type, created_at)`
  - `action`: `page_view | registration_start | registration_complete | share | qr_scan`
- Backend: fire-and-forget INSERT (not awaited inline) — failures don't block API responses
- No PII beyond `user_uid` (Firebase UID, may be NULL for anonymous page views)
- Admin read endpoint: `GET /api/v1/admin/events/{id}/analytics` — aggregate counts only

### Rules

- No raw event log exposed to public API.
- `user_uid` nullable — anonymous events allowed.
- Analytics does NOT depend on QR attendance (that's Phase 5). Analytics logs QR scans as an `action` type but does not own the attendance record.
- Rewards depend on analytics counts (Phase 6).

---

## Phase 5 — QR Attendance Foundation

**Scope:** Extend existing `check_ins` table; generate QR tokens; scan API

### Design

- Extend `check_ins` with `qr_token TEXT UNIQUE`, `scanned_at TIMESTAMPTZ`, `scanned_by_uid TEXT`
- `GET /api/v1/my/registrations/{id}/qr` — returns QR payload (registration_number + token)
- `POST /api/v1/admin/events/{id}/checkin/scan` — validates QR token, marks check_in
- QR token generated at registration time or on first QR fetch (lazy)

### Rules

- QR token is separate from `registrations.qrtoken` (which exists but is nullable).
- Phase 5 may reuse `registrations.qrtoken` — deferred decision.
- No printing/PDF scope in this phase — just the data layer and API.

### Prerequisites

- Phase 1 complete (is_free helps with free-vs-paid attendance reporting)
- Phase 4 analytics logs `qr_scan` events

---

## Phase 6 — Rewards Architecture

**Migration:** `014_week5_phase5_rewards.sql` (after Phase 4 + 5)
**Scope:** `event_rewards`, `alumni_reward_points` tables — read-write by system only

### Design

- `event_rewards(reward_id, event_id, action, points, description, valid_until)`
  - Define point values per action: attend=10, register=2, share=1
- `alumni_reward_points(entry_id, firebase_uid, event_id, action, points, earned_at)`
  - Append-only log. `SUM(points)` = total balance.
- Admin read: `GET /api/v1/admin/alumni/{uid}/rewards` — total points + history

### Rules

- Points are purely display/internal. No redemption or payment in this phase.
- Requires QR check-in (Phase 5) to award attend points.
- Requires Analytics (Phase 4) to award page-view/share points.
- No public API for rewards in this phase.

---

## Phase 7 — Meeting OAuth Architecture (Architecture Only)

**No code. No DB.** Document only.

### Architecture Notes

- Google Meet / Zoom OAuth would require:
  - OAuth 2.0 token storage per organiser (`event_oauth_tokens` table, encrypted)
  - Token refresh on each meeting creation
  - `virtual_url` auto-populated from Meet/Zoom API after OAuth approval
- Risks: token rotation, scope management, organiser re-auth on expiry
- Recommendation: implement via a dedicated server-side job (not in-request)

### What to document

- Token table schema (proposed, not created)
- OAuth flow diagram (Google Meet as example)
- Integration point: admin event form "Generate Meet link" button → OAuth flow

---

## Phase 8 — Payment (DEFERRED)

**Out of scope.** Not in Week 5 or Week 6.

- `is_free=false` + `ticket_price` from Phase 1 is the placeholder.
- No Razorpay/Stripe integration.
- No `payment_orders` or `payment_receipts` tables.
- Document: "Payment implementation requires PCI-DSS review and a separate service."

---

## Migration Sequence

| Migration | Phase | Description |
|---|---|---|
| 001–009 | Weeks 1–4 | Locked — do not modify |
| 010 | Phase 1 | `is_full_day`, `is_free`, `ticket_price` on events |
| 011 | Phase 2 | `event_people`, `event_people_links` |
| 012 | Phase 3 | `event_sponsors` |
| 013 | Phase 4 | `event_analytics_log` |
| 014 | Phase 5 | Extend `check_ins` for QR (or new `qr_tokens` table) |
| 015 | Phase 6 | `event_rewards`, `alumni_reward_points` |

---

## Current Status

| Phase | Status |
|---|---|
| Phase 1 — Full Day + Free/Paid | IN PROGRESS |
| Phase 2 — People/Speakers | PLANNED |
| Phase 3 — Sponsors/Partners | PLANNED |
| Phase 4 — Analytics | PLANNED |
| Phase 5 — QR Attendance | PLANNED |
| Phase 6 — Rewards | PLANNED |
| Phase 7 — Meeting OAuth | ARCHITECTURE ONLY |
| Phase 8 — Payment | DEFERRED |
