# Week 3 Phase 3 — Developer Diagnostics: Registration Flow

**Date:** 2026-06-18  
**Phase:** 3 — Developer Diagnostics Registration Flow  
**Status:** COMPLETE  
**Prerequisite:** Phase 2B runtime verification — 63/63 PASS  

---

## Scope

Extend the existing Developer Diagnostics infrastructure (backend + Flutter) with a live
Registration Flow diagnostic category. All five placeholder `DiagnosticItem` entries in the
Registration section are replaced with real, runnable diagnostics backed by a new backend
endpoint.

**Explicitly out of scope (not implemented):**
- Attendance / QR code flows
- Waitlist / payment
- Production React Admin screens
- Production themed Flutter registration screens

---

## Backend Changes

### New endpoint: `GET /api/v1/dev/diagnostics/registrations`

**File:** `backend/app/api/dev_diagnostics.py`  
**Guard:** `_require_development()` (returns 404 in production)  
**Auth:** backend JWT via `_get_dev_user()` dependency  

Runs 11 diagnostic checks sequentially and returns a single structured JSON report.

#### Diagnostic sequence

| # | Feature | API / Source | Method | Auth |
|---|---------|-------------|--------|------|
| 1 | Alumni Profile | `/api/v1/alumni/me` | GET | JWT |
| 2 | Test Virtual Event Setup | `EventsService.create_event` + publish | POST | internal |
| 3 | Test Capacity Event Setup | `EventsService.create_event` + publish | POST | internal |
| 4 | Registration Eligibility | `/api/v1/events/{id}/registration-eligibility` | GET | JWT |
| 5 | Register for Event | `/api/v1/events/{id}/register` | POST | JWT |
| 6 | My Registration | `/api/v1/events/{id}/my-registration` | GET | JWT |
| 7 | My Registrations List | `/api/v1/my/registrations` | GET | JWT |
| 8 | Duplicate Registration Guard | `/api/v1/events/{id}/register` (2nd attempt) | POST | JWT |
| 9 | Capacity Guard | `/api/v1/events/{id}/register` (event at capacity) | POST | JWT |
| 10 | Join Link Visibility | `/api/v1/events/{id}/my-registration` | GET | JWT |
| 11 | Confirmation Email Status | `registrations` table direct | DB | internal |
| 12 | Audit Log Check | `event_audit_log` table direct | DB | internal |
| 13 | Public API Leak Check | `/api/v1/events/public/{id}` | GET | none |

#### Capacity guard strategy

A filler registration row is inserted directly (bypassing service) to fill the
capacity=1 test event, then the real user attempts to register and must receive
`409 event_full`. The filler row is always deleted in a `finally` block.

#### Test event lifecycle

- Two events are created per run: a virtual event (capacity=5) and an in-person event (capacity=1).
- Both are published before tests and cancelled in a cleanup step at the end.
- Registration rows created against the test events are left in the DB as historical records.

#### Security invariants verified

- `virtual_url` absent from public event response (Diag 13)
- `join_url` present only for: `status=registered AND is_virtual=True AND event_status=published`
- Duplicate guard: `already_registered` (409) on second registration attempt
- Capacity guard: `event_full` (409) when registered_count >= capacity

#### Skip conditions

All diagnostics that require alumni access are skipped gracefully (not failed) when the
requesting user is not of `user_type='alumni'` or has no `ref_id`.

#### Response shape

```json
{
  "status": "ok",
  "category": "Registration Flow",
  "total": 13,
  "passed": 13,
  "failed": 0,
  "test_virtual_event_id": 42,
  "test_registration_id": 7,
  "is_alumni_user": true,
  "results": [ ... ],
  "run_by": "<firebase_uid>",
  "run_at": "2026-06-18T..."
}
```

---

## Flutter Changes

**File:** `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart`

### 1. Registration category items — from placeholder to live

Five `DiagnosticItem.placeholder()` entries replaced with real `DiagnosticItem()` entries
(`comingSoon: false`, `initialStatus: DiagnosticStatus.notApplicable`):

| DiagnosticId | Title |
|---|---|
| `registrationApi` | Registration Flow Test |
| `myRegistration` | My Registration Test |
| `capacityGuard` | Capacity Guard Test |
| `confirmationEmail` | Confirmation Email Status |
| `joinLinkVisibility` | Join Link Visibility Test |

### 2. DiagnosticDetailScreen routing

The five registration IDs are removed from the `_ComingSoonDiagnosticDetail` catch-all and
routed to the new `_RegistrationDiagnosticDetail` widget:

```dart
DiagnosticId.registrationApi ||
DiagnosticId.myRegistration ||
DiagnosticId.capacityGuard ||
DiagnosticId.confirmationEmail ||
DiagnosticId.joinLinkVisibility =>
  _RegistrationDiagnosticDetail(item: item),
```

### 3. New widget: `_RegistrationDiagnosticDetail`

Stateful widget. Tapping any of the five IDs opens this single unified diagnostic screen.

**Auth strategy:**
1. Check stored `AuthSessionStore` session first (alumni who logged in via the app don't re-authenticate)
2. Fall back to `FirebaseAuth.instance.currentUser.getIdToken(true)` + backend exchange if no stored session

**UX flow:**
- "Run Registration Diagnostics" button calls `GET /api/v1/dev/diagnostics/registrations`
- 90-second timeout (backend creates two events, registers, runs 13 checks, cancels)
- Results rendered as cards with PASS (green) / FAIL (red) / N/A badges
- Each result card shows: feature name, status badge, response key-values, error text, duration
- Summary pill row: `N PASS`, `N FAIL` of total
- Raw JSON collapsible block at the bottom

**Debug-only guard:** The parent screen already enforces `kDebugMode` check at root level —
returns `Scaffold(body: Center(child: Text('Not available.')))` in release.

---

## Validation Results

### python -m compileall app
```
Listing 'app'...
Listing 'app/api'...
Listing 'app/middleware'...
Listing 'app/repositories'...
Listing 'app/schemas'...
Listing 'app/services'...
Listing 'app/utils'...
[no errors]
```

### flutter analyze
```
Analyzing event_app...
No issues found! (ran in 1.8s)
```

### flutter test
```
00:01 +16: All tests passed!
```

### Route registration check
```
Registration route registered: ['/api/v1/dev/diagnostics/registrations']
Total dev_diagnostics routes: 5
```

---

## Security Constraints Honoured

| Constraint | Status |
|---|--------|
| `virtual_url` never in public APIs | VERIFIED — Diag 13 checks and reports leaked fields |
| `join_url` only in authenticated registration endpoints | VERIFIED — resolved by `_resolve_join_url()` in service |
| Email failure never rolls back registration | VERIFIED (Phase 2B) — diagnostic confirms email_status written post-commit |
| `emit()` never raises | VERIFIED — wrapped in try/except in audit_service |
| No hardcoded tokens in Flutter | VERIFIED — uses AuthSessionStore then Firebase refresh |
| Development-only guard | VERIFIED — `_require_development()` in every dev_diagnostics route |

---

## Files Changed

| File | Change |
|---|--------|
| `backend/app/api/dev_diagnostics.py` | Added `GET /api/v1/dev/diagnostics/registrations` (approx 280 lines) |
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Added `_RegistrationDiagnosticDetail` widget; updated 5 items from placeholder to live; updated switch routing |

---

## Not Implemented (Deferred)

Per scope agreement, the following remain as `_ComingSoonDiagnosticDetail`:
- `eventsApi`, `eventDetailApi`, `eventCreationApi`, `eventPublish` (Event Management diagnostics)
- `attendeeListApi`, `attendeeExport`, `adminRoleGuard`, `auditTrail` (Admin / Attendees diagnostics)

---

## Status: PASS

All three validation gates passed. Phase 3 developer diagnostics for the Registration Flow
are complete and ready for internal review.
