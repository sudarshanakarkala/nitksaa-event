# Week 3 UX Showcase — Design Document

**Date:** 2026-06-19  
**Version:** 1.0  
**Status:** Implemented  
**Scope:** Developer Diagnostics → Registration UX Showcase (Week 3)

---

## Purpose

The Week 3 UX Showcase extends the Developer Diagnostics screen into a complete visual
demonstration center for all Week 3 registration backend workflows.

Target audiences:
- **Product Owner** — review backend behaviour through visual prototype screens
- **Frontend Developer** — reference implementation for registration UI patterns
- **Backend** — live validation against running backend
- **Demo environment** — stakeholder walkthrough

---

## Access Path

```
App → Developer Diagnostics (debug mode only)
    → Registration category
        → Week 3 UX Showcase        ← NEW top-level entry
        → Registration Flow Test    ← existing (same screen)
        → My Registration Test      ← existing (same screen)
        → Capacity Guard Test       ← existing (same screen)
        → Confirmation Email Status ← existing (same screen)
        → Join Link Visibility Test ← existing (same screen)
```

All Registration category items open `_RegistrationDiagnosticDetail`, which is the
showcase screen.

---

## Screen Inventory

| # | Screen / Section | Type | API Endpoint |
|---|---|---|---|
| §0 | Run All Week 3 Validation | Live dashboard | `GET /api/v1/dev/diagnostics/registrations` |
| §1 | Alumni Autofill Preview | Interactive prototype | `GET /api/v1/alumni/me` |
| §2 | Registration Eligibility Preview | Interactive prototype | `GET /api/v1/events/{id}/registration-eligibility` |
| §3 | Registration Action Preview | Interactive prototype | `POST /api/v1/events/{id}/register` |
| §4 | Confirmation Screen Preview | Live data from §3 | (uses §3 result) |
| §5 | My Registration Preview | Interactive prototype | `GET /api/v1/events/{id}/my-registration` |
| §6 | My Registrations List Preview | Interactive prototype | `GET /api/v1/my/registrations` |
| §7 | Negative State Gallery | Static reference | (no API call) |
| Dev Notes | Frontend Developer Reference | Static reference | (no API call) |
| §8a | Join Link Visibility Matrix | Static table | (no API call) |
| §8b | Public API Leak Validation | Live check | `GET /api/v1/events/public/{id}` |
| §9 | Audit Trail Demonstration | Live data | `GET /api/v1/dev/diagnostics/db/event_audit_log` |
| §10 | Email Demonstration | Live data from §3 | (uses §3 result) |
| §11 | Snapshot Demonstration | Live comparison | (uses §1 + §3 results) |
| §12 | Database Rules Demonstration | Static reference | (no API call) |

---

## Workflow Inventory

### Section A — Registration Happy Path (§1 → §4)

Seven-step green progress timeline demonstrated via four interactive sections:

1. Alumni Profile Loaded — `GET /alumni/me` → populated autofill form (§1)
2. Event Eligibility Check — `GET /events/{id}/registration-eligibility` → eligibility banner (§2)
3. Registration Request — `POST /events/{id}/register` → register action (§3)
4. Registration Success — registration_number generated (§3 result)
5. Registration Number Generated — displayed prominently in §3 + §4
6. Confirmation Email Sent — `confirmation_email_status` from §3 → email row (§4)
7. Join Link Available (virtual only) — `join_url` from §3 → join link card (§4)

### Section B — Physical Event Registration Flow

Use Event ID picker to target event 25 (Breakfast Club Bangalore, physical):

- §2: Eligibility → `eligible`
- §3: Register → `join_url: null`
- §4: Confirmation → join link section hidden

### Section C — Virtual Event Registration Flow

Use Event ID picker to target event 26 (Webinar on AI, virtual):

- §2: Eligibility → `eligible`
- §3: Register → `join_url: "https://meet.google.com/..."` (non-null)
- §4: Confirmation → join link card visible

### Section D — My Registration (§5)

`GET /events/{id}/my-registration` — shows Registration Card with:
- Registration Number, Status, Registered At
- Join Link (if virtual + registered + published)
- Venue (if physical)

### Section E — My Registrations (§6)

`GET /my/registrations` — scrollable registration cards showing:
- Event title, event type pill (Virtual/Physical)
- Registration number in monospace
- Registered date
- Join link row (virtual only, when present)

---

## Negative State Gallery (§7)

Seven static error state cards — no API call required:

| State | Source | Colour |
|---|---|---|
| Event Full (`full` / `event_full`) | Orange | Error container |
| Registration Closed (`closed` / `registration_closed`) | Red | Error container |
| Registration Not Open Yet (`not_open_yet`) | Blue | Tertiary container |
| Already Registered (`already_registered`) | Green | Secondary container |
| Alumni Only (`alumni_only`) | Red | Error container |
| Inactive Alumni (`alumni_not_active`) | Red | Error container |
| Unauthenticated (401) | Grey | Surface variant |

Additional static cards for: `event_not_published`, `confirm_profile_required`,
`email_failed (non-blocking)`.

---

## Security Demonstrations (§8)

### §8a — Join Link Visibility Matrix

Static 4-row table:

| Registration | Event Type | Event Status | Join Link |
|---|---|---|---|
| registered | virtual | published | **Visible** |
| cancelled | virtual | published | Hidden |
| registered | physical | published | Hidden |
| registered | virtual | draft | Hidden |

Highlighted: only the first combination exposes `join_url`.

### §8b — Public API Leak Validation

Live check: `GET /api/v1/events/public/{event_id}` (no auth).

Checks response for forbidden fields: `virtual_url`, `join_url`, `created_by_firebase_uid`.

Displays:
- **PASS** badge (green) if none present
- **FAIL** badge (red) listing leaked fields

---

## Audit Trail Demonstration (§9)

`GET /api/v1/dev/diagnostics/db/event_audit_log` (auth required).

Displays latest 8 rows:
- `event_type` (action)
- `entity_type` + `entity_id`
- `created_at`
- PII hidden (`actor_uid` not shown in card body)

Note: "Audit records written automatically on every registration, cancellation,
and event status change."

---

## Email Demonstration (§10)

Populated from §3 Registration Action result (no additional API call).

Fields displayed:
- Registration Number
- Email Sent At
- Confirmation Email Status (with colour-coded icon)

Rule highlighted: "Email delivery never blocks registration success."

---

## Snapshot Demonstration (§11)

Side-by-side comparison of `GET /alumni/me` (§1) vs `POST /register` snapshot fields (§3).

Compared fields:
- Full Name (`fullname` vs `fullname_snapshot`)
- Batch Year (`batch_year` vs `batch_year_snapshot`)
- Branch (`branch` vs `branch_snapshot`)

Rule highlighted: "Snapshot fields are frozen at registration time."

---

## Database Rules Demonstration (§12)

Four static rule cards:

| Rule | DB Constraint | Verification |
|---|---|---|
| Unique Registration Number | Service-generated `NITKSAA-{year}-{id:06d}` | Diag 3 (Register) |
| Partial Unique Registration | UNIQUE (event_id, firebase_uid) WHERE status='registered' | Migration 008 |
| Re-registration After Cancellation | Cancelled rows soft-deleted; partial index allows new row | Diag 6 (Duplicate Guard) |
| Registered Count Excludes Cancelled | COUNT(*) WHERE status='registered' only | Diag 7 (Capacity Guard) |

---

## Run Full Week 3 Showcase Validation (§0)

One-tap validation using `GET /api/v1/dev/diagnostics/registrations`.

Runs 11 backend diagnostic checks:
1. Alumni Profile
2. Test Virtual Event Setup
3. Test Capacity Event Setup
4. Registration Eligibility
5. Register for Event
6. My Registration (+ join_url check)
7. My Registrations List
8. Duplicate Registration Guard
9. Capacity Guard
10. Confirmation Email Status
11. Join Link Visibility
12. Audit Log Check (registration → audit_log row)
13. Public API Leak Check

Displays: PASS/FAIL dashboard with per-check results and timing.

---

## Implementation Files

| File | Change |
|---|---|
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Primary implementation |

### Code additions in `developer_diagnostics_screen.dart`

- `DiagnosticId.week3UxShowcase` — new enum value
- `diagnosticApiDetails[DiagnosticId.week3UxShowcase]` — new API details entry
- `_diagnosticItems[DiagnosticId.week3UxShowcase]` — new DiagnosticItem
- `Registration` category updated — `week3UxShowcase` added as first item
- `DiagnosticDetailScreen` switch — `week3UxShowcase` routed to `_RegistrationDiagnosticDetail`
- `_RegistrationDiagnosticDetailState` — 6 new state variables
- `build()` method — §8–§12 sections appended after Dev Reference Notes
- New widgets: `_joinLinkMatrixCard`, `_matrixCell`, `_publicLeakCard`,
  `_auditTrailCard`, `_auditRowCard`, `_emailDemoCard`, `_snapshotDemoCard`,
  `_snapshotRow`, `_databaseRulesCard`, `_dbRuleCard`, `_dbRuleRow`
- New fetch methods: `_fetchPublicLeak`, `_fetchAuditLog`

---

## Design Decisions

1. **Single screen, multiple sections** — All showcase sections live inside the existing
   `_RegistrationDiagnosticDetail` widget. No new screen class was needed; the widget
   already handles all registration flows. This avoids duplication of auth/fetch
   infrastructure.

2. **No production UI changes** — All new code is inside debug-mode-gated diagnostics.
   The `kDebugMode` guard in `DeveloperDiagnosticsScreen.build()` ensures nothing
   appears in production.

3. **Incremental fetch model** — Each section has its own "Fetch" button. Sections that
   depend on earlier data (§10 email, §11 snapshot) gracefully show placeholders when
   prerequisite data is not yet loaded.

4. **Static sections require no auth** — §7 (Negative Gallery), §8a (Matrix), §12
   (DB Rules) are fully static. They demonstrate backend design without requiring
   authentication.

5. **Public leak check is unauthenticated** — §8b calls the public API without a token,
   mirroring what an anonymous user or a web scraper would receive. This proves the
   security boundary holds.
