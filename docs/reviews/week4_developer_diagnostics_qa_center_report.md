# Week 4 — Developer Diagnostics QA Control Center Report

Date: 2026-06-24

## Summary

The Developer Diagnostics / Developer Settings screen was redesigned from a partially-implemented UI with many "Coming soon" placeholders into a functional QA control center. Every diagnostic section now has runnable CTAs backed by real API calls. No placeholder cards remain.

---

## Before / After

| Aspect | Before | After |
|---|---|---|
| Event Management items | 4 × "Coming soon" placeholders | 4 runnable tests (Public Events, Event List, Event Detail, Admin Detail) |
| Admin / Attendees items | 4 × "Coming soon" + 2 real | 6 runnable tests (List, Search, Batch Filter, Export, Audit, Full UC-01–10) |
| Registration items | 6 items (3 duplicate of full-diagnostics) | 3 items (week3 UX showcase, full registration diagnostics, my registrations) |
| Quick Actions — Run section | 1 "Public Events API Test" + Run All | 3 section run buttons (Event Diag, Registration Diag, Admin Diag) + Run All |
| `_ComingSoonDiagnosticDetail` class | Present — used by all placeholder items | Deleted — no items route to it |
| `flutter analyze` warnings | 3 (2 unnecessary casts, 1 unused class) | 0 |

---

## Duplicate Tests Removed

The Registration section previously duplicated tests already covered by the full backend diagnostics run:

| Removed Item | DiagnosticId | Reason |
|---|---|---|
| Capacity Guard | `capacityGuard` | Covered by `registrationApi` (step 4: capacity check) |
| Confirmation Email | `confirmationEmail` | Covered by `registrationApi` (step 9: email send) |
| Join Link Visibility | `joinLinkVisibility` | Covered by `registrationApi` (step 8: virtual join link) |

These were removed from both `_diagnosticCategories()` and `_diagnosticItems()`. The enum values remain defined but are no longer surfaced in the UI.

---

## New CTA Tests Added

### Event Management — `_EventManagementDiagnosticDetail`

All four event management items now route to a single detail screen with four independent test sections:

| Section | Endpoint | Auth | Verifies |
|---|---|---|---|
| §1 Public Events API | `GET /api/v1/events/public?period=upcoming` | None | Response shape, `virtual_url_leaked` flag |
| §2 Event List API | `GET /api/v1/events?page=1&per_page=20` | Admin JWT | Admin-only access, pagination metadata |
| §3 Event Detail API | `GET /api/v1/events/public/{id}` | None | Per-event public shape; uses Event ID picker |
| §4 Event Admin Detail | `GET /api/v1/events/{id}` | Admin JWT | Admin-level event fields; uses Event ID picker |

The screen includes an Event ID picker card so reviewers can supply any event ID rather than relying on a hardcoded constant.

### Admin / Attendees — `_AdminAttendeeDiagnosticDetail`

All six admin/attendee items route to a single detail screen with six independent test sections:

| Section | Endpoint | Verifies |
|---|---|---|
| §1 Attendee List | `GET /admin/events/{id}/attendees` | No `virtual_url`/`join_url` leak, all `status=registered` |
| §2 Attendee Search | Same + `search` param | Search param accepted, results non-empty |
| §3 Batch Year Filter | Same + `batch_year` param | All returned rows match the supplied batch year |
| §4 Attendee Export | `GET /admin/events/{id}/attendees/export` | 8 required CSV columns present, no sensitive fields |
| §5 Registration Audit | `GET /admin/events/{id}/registrations` | All statuses visible in audit view |
| §6 Full Diagnostics (UC-01–10) | `GET /api/v1/dev/diagnostics/attendees?event_id={id}` | Pass/fail per use case with expandable detail |

---

## Event Diagnostics Added (detail)

Four previously-placeholder Event Management items are now active:

- **`eventsApi`** — "Public Events API Test" — GET public events, check no join URL leak
- **`eventCreationApi`** — repurposed as "Event List API Test" — GET admin event list
- **`eventDetailApi`** — "Event Detail API Test" — GET public event by ID (Event ID picker)
- **`eventPublish`** — repurposed as "Event Admin Detail Test" — GET admin event detail (Event ID picker)

---

## Attendee Diagnostics Added (detail)

Two new `DiagnosticId` values added to support search and batch filter tests:

```dart
attendeeSearchTest,   // new
attendeeBatchFilter,  // new
```

Six items in the Admin/Attendees category (4 real + 2 new), all routed to `_AdminAttendeeDiagnosticDetail`.

---

## Registration Section Cleanup

Registration section reduced from 6 items to 3:

| Kept | DiagnosticId | Purpose |
|---|---|---|
| Week 3 UX Showcase | `week3UxShowcase` | End-to-end reviewer flow demonstration |
| Full Registration Diagnostics | `registrationApi` | 13-step backend registration flow |
| My Registrations Smoke Test | `myRegistration` | Authenticated user's registration list |

---

## Quick Actions Card Changes

`_QuickActionsCard` Run section replaced a single "Public Events API Test" card with three section run buttons:

| Button | Destination | Sublabel |
|---|---|---|
| Run Event Diagnostics | `_EventManagementDiagnosticDetail` | Public, list, detail, admin detail |
| Run Registration Diagnostics | `_RegistrationDiagnosticDetail` | 13-check backend flow + UX showcase |
| Run Attendee / Admin Diagnostics | `_AdminAttendeeDiagnosticDetail` | List · search · export · UC-01–UC-10 |

Run All Diagnostics hero button is unchanged — still iterates all `DiagnosticId` values sequentially.

---

## Routing Changes

`DiagnosticDetailScreen.build()` exhaustive switch updated:

```dart
DiagnosticId.eventsApi ||
DiagnosticId.eventDetailApi ||
DiagnosticId.eventCreationApi ||
DiagnosticId.eventPublish =>
  _EventManagementDiagnosticDetail(item: item),

DiagnosticId.attendeeListApi ||
DiagnosticId.attendeeSearchTest ||
DiagnosticId.attendeeBatchFilter ||
DiagnosticId.attendeeExport ||
DiagnosticId.adminRoleGuard ||
DiagnosticId.auditTrail =>
  _AdminAttendeeDiagnosticDetail(item: item),
```

`_ComingSoonDiagnosticDetail` removed — no items route to it.

---

## Verification Result

```
flutter analyze lib/features/developer/presentation/developer_diagnostics_screen.dart
→ No issues found!
```

Previous warnings resolved:
- `unnecessary_cast` at line 1736 — fixed by extracting cast to local `m` variable
- `unnecessary_cast` at line 2162 — fixed by same pattern
- `unused_element _ComingSoonDiagnosticDetail` — class deleted

---

## Known Limitations

- **Event ID picker not pre-populated** — the picker starts empty. Reviewers must know or look up a valid event ID before running Event Detail, Admin Detail, Attendee, or Export tests.
- **Token refresh on 401** — if the admin JWT expires during a multi-step test run, the individual section will show an error chip; re-tapping Run re-fetches the token via `_ensureToken()`.
- **CSV export verification is structural only** — the export test checks that required column headers are present in the response and that sensitive columns (`virtual_url`, `join_url`, `firebase_uid`) are absent. It does not download the file or verify row data values.
- **UC-01–UC-10 verification is backend-driven** — the Full Diagnostics section calls `GET /api/v1/dev/diagnostics/attendees?event_id={id}` and displays the backend's own pass/fail verdict. It is only available in `DEBUG` mode (the dev diagnostics endpoint requires a development flag).
- **No mock/offline mode** — all tests require the backend to be reachable. A timeout or connection error produces an error chip on the affected section.

---

## Files Changed

| File | Change |
|---|---|
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Added `attendeeSearchTest`, `attendeeBatchFilter` enum values; updated categories and items; updated routing switch; inserted `_EventManagementDiagnosticDetail` and `_AdminAttendeeDiagnosticDetail` widgets; updated state class and `_QuickActionsCard`; deleted `_ComingSoonDiagnosticDetail`; fixed 2 unnecessary cast warnings |

---

## What Was NOT Changed

Per session instructions — no new features:

- No speakers / sponsors / analytics
- No meeting OAuth or provider integration
- No QR check-in / rewards
- No paid events / payment gateway
- No full-day event migration
- No Flutter production registration UI
