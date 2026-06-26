# Week 5 — Event Usage Cross-Check

**Date:** 2026-06-26
**Scope:** Every place events are created, edited, listed, viewed, registered, exported, or diagnosed
**Status:** All components verified — no incompatibilities found

---

## Summary

Week 5 adds the following fields and resources to events:

- **Fields on `events` table:** `is_full_day`, `is_free`, `ticket_price` (migration 010)
- **New tables:** `event_people`, `session_people`, `event_sponsors`, `event_partners`, `event_activity_log` (migrations 011–013)
- **New public response arrays:** `people[]`, `speakers[]`, `sponsors[]`, `partners[]`

All changes are **additive only** — no existing fields are removed or renamed.

---

## Backend

| Area | File | Event usage | Week 5 compatibility | Result | Notes |
|---|---|---|---|---|---|
| Public event list | `backend/app/api/events.py` | Lists published events | `is_full_day`, `is_free`, `ticket_price` now returned in list response | PASS | New fields have SQL defaults; no existing consumers broken |
| Public event detail | `backend/app/api/events.py` | Returns single published event | `people[]`, `speakers[]`, `sponsors[]`, `partners[]` added; enrichment fetched from new tables | PASS | All arrays default `[]`; `is_visible=false` items never returned |
| Admin event CRUD | `backend/app/api/admin_events.py` | Create, update, publish, close events | Accepts `is_full_day`, `is_free`, `ticket_price` in create/update; returns them in detail | PASS | All three fields optional; existing callers unaffected |
| Admin event list | `backend/app/api/admin_events.py` | Lists all events for admin portal | `is_full_day`, `is_free`, `ticket_price` now included in list items | PASS | Additive; admin portal reads these for pill indicators |
| People CRUD | `backend/app/api/people.py` | Admin CRUD for event_people | New — GET/POST/PUT/DELETE `/api/v1/events/{id}/people` | PASS | 14/14 diagnostic tests pass |
| Sponsors CRUD | `backend/app/api/sponsors_partners.py` | Admin CRUD for event_sponsors | New — GET/POST/PUT/DELETE `/api/v1/events/{id}/sponsors` | PASS | 17/17 diagnostic tests pass |
| Partners CRUD | `backend/app/api/sponsors_partners.py` | Admin CRUD for event_partners | New — GET/POST/PUT/DELETE `/api/v1/events/{id}/partners` | PASS | 17/17 diagnostic tests pass |
| Week 5 diagnostics | `backend/app/api/week5_diagnostics.py` | Diagnostic suites for Week 5 | New — 5 endpoints, 48 tests | PASS | Returns 404 when APP_ENV != development |
| Event repository | `backend/app/repositories/events_repository.py` | SELECT/INSERT/UPDATE for events | Updated to include `is_full_day`, `is_free`, `ticket_price` | PASS | Existing rows have SQL defaults applied |
| Events service | `backend/app/services/events_service.py` | Business logic for public/admin event detail | `get_public_event` now fetches and attaches enrichment arrays; speakers[] derived | PASS | Derivation: role in {SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR} AND is_visible=true |
| Registration service | `backend/app/services/registration_service.py` | Registration flow; email confirmation | Calls `log_event_activity` after register/fail/email; fire-and-forget | PASS | an_11 confirms no secrets; registration never blocked |

---

## Admin Portal

| Area | File | Event usage | Week 5 compatibility | Result | Notes |
|---|---|---|---|---|---|
| Event form | `admin/event_admin/src/pages/EventFormPage.jsx` | Create and edit events | `is_full_day`, `is_free`, `ticket_price` fields present (Phase 1); enrichment panel added in edit mode; navigate-to-edit after create | PASS | EventEnrichmentPanel renders below form in edit mode only |
| Event list | `admin/event_admin/src/pages/EventsPage.jsx` | Lists all events | Full Day / Paid / Free indicator pills added in Event Type column | PASS | Pills are display-only; no data contract change |
| Attendees page | `admin/event_admin/src/pages/AttendeesPage.jsx` | Lists registered attendees | No Week 5 impact | PASS | Reads registrations only; enrichment not relevant |
| Registrations page | `admin/event_admin/src/pages/RegistrationsPage.jsx` | Lists registration audit trail | No Week 5 impact | PASS | Reads registrations only |
| Dashboard | `admin/event_admin/src/pages/DashboardPage.jsx` | Event counts and summary | No Week 5 impact | PASS | Reads event counts; no per-event enrichment displayed |
| Events API client | `admin/event_admin/src/api/eventsApi.js` | Create/update/list events | `createEvent` return value now captured to extract `event_id` for navigate-to-edit | PASS | Return value was previously discarded |
| Enrichment API client | `admin/event_admin/src/api/enrichmentApi.js` | CRUD for people/sponsors/partners | New — 12 methods using actual backend URLs | PASS | Uses `/api/v1/events/{id}/people` (not `/admin/`) |
| Attendees API client | `admin/event_admin/src/api/attendeesApi.js` | Fetch attendees and export | No Week 5 impact | PASS | Reads `/api/v1/admin/events/{id}/attendees` only |

---

## Flutter App

| Area | File | Event usage | Week 5 compatibility | Result | Notes |
|---|---|---|---|---|---|
| Public event model | `apps/event_app/lib/features/events/domain/public_event.dart` | List-view event model | No Week 5 impact | PASS | Enrichment data only on detail view, not list |
| Public event detail model | `apps/event_app/lib/features/events/domain/public_event_detail.dart` | Detail view event model | Week 5 fields parsed from JSON; all optional with `[]` defaults | PASS | `fromJson` uses `?.` and fallback `[]`; no breaking change |
| Event detail screen | `apps/event_app/lib/features/events/presentation/event_detail_screen.dart` | Displays event detail | Phase 1 fields displayed; people/speakers/sponsors/partners display deferred | PASS | Screen safely receives and ignores new arrays if not rendered |
| Event list screen | `apps/event_app/lib/features/events/presentation/event_list_screen.dart` | Lists published events | No Week 5 impact | PASS | List view shows title, date, location |
| Register screen | `apps/event_app/lib/features/events/presentation/register_screen.dart` | Registration flow | No Week 5 impact | PASS | Registration does not read enrichment data |
| My registrations screen | `apps/event_app/lib/features/my_registrations/presentation/my_registrations_screen.dart` | Shows user's registrations | No Week 5 impact | PASS | Shows title, registration number, status only |
| Developer diagnostics | `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Calls backend diagnostics | "Week 5 — Event Enrichment" category added with 5 items | PASS | flutter analyze: 0 issues |

---

## Documentation

| Area | File | Event usage | Week 5 compatibility | Result | Notes |
|---|---|---|---|---|---|
| API index | `docs/api/backend_api_index_v3.md` | All endpoint reference | Updated to v3.1 — Week 5 People/Sponsors/Partners and diagnostic sections added | PASS | Documentation version matrix updated |
| API contract | `docs/api/events_api_contract_v2.md` | Registration, public event, eligibility | Updated to v2.1 — Week 5 additive fields and enrichment arrays documented | PASS | Changelog updated |
| Enrichment contract | `docs/api/week5_event_enrichment_api_contract.md` | People/Sponsors/Partners/Analytics | Admin portal usage notes added; ordering and visibility rules already present | PASS | Complete |
| Manual verification | `docs/reviews/week5_manual_verification_steps.md` | QA guide | Section L (admin enrichment) added; K.6 counts corrected to 48 | PASS | PASS criteria updated |
| Developer workflows | `docs/reviews/week5_developer_workflows_verification.md` | Diagnostic endpoints guide | Flutter diagnostics section and admin portal section added | PASS | 48/48 totals confirmed |

---

## Backward Compatibility Summary

| Change | Impact | Status |
|---|---|---|
| `is_full_day`, `is_free`, `ticket_price` in public list and detail | New fields with SQL defaults | Safe — existing rows have defaults; Flutter fromJson uses `?.` |
| `people[]`, `speakers[]`, `sponsors[]`, `partners[]` in public event detail | New arrays, default `[]` | Safe — Flutter fromJson handles missing fields with `[]` fallback |
| Admin event response includes `is_full_day`, `is_free`, `ticket_price` | Additive | Safe — admin portal reads these for pill indicators |
| Admin portal navigate-to-edit after create | UX change only | Safe — same route, no data impact |
| Events list Full Day / Paid / Free pills | Display-only | Safe — no data contract change |
| `apiClient.put` added | Additive | Safe — no existing call sites changed |
| Analytics hooks in registration_service | Fire-and-forget | Safe — registration never blocked; confirmed by diagnostic |

**No breaking changes identified.**

---

## Open Items

| Item | Priority | Notes |
|---|---|---|
| Flutter UI for people/speakers/sponsors/partners display | Deferred | Backend + admin ready; Flutter display sprint to follow |
| Cloud SQL migrations 010–013 | Requires PO approval | Checklist at `week5_cloud_migration_execution_checklist.md` |
| URL prefix alignment `/api/v1/events/{id}/people` vs `/api/v1/admin/events/{id}/people` | Low | Would require diagnostics update and API doc revision; deferred |
| Automated backend tests (`pytest`) | Low | pytest conftest uses wrong DB user locally; deferred |
| `flutter test` — 1 pre-existing failure (GoRouter in test harness) | Low | Not a Week 5 regression; deferred to test maintenance sprint |
