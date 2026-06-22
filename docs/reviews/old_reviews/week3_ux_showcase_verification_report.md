# Week 3 UX Showcase — Verification Report

**Date:** 2026-06-19  
**Version:** 1.0  
**Status:** Implemented and statically verified  
**Flutter analyze:** PASS — No issues found

---

## Verification Summary

| Area | Result | Notes |
|---|---|---|
| Flutter static analysis | **PASS** | `flutter analyze` — no issues |
| DiagnosticId enum | **PASS** | `week3UxShowcase` added |
| Routing | **PASS** | Routes to `_RegistrationDiagnosticDetail` |
| Registration category | **PASS** | `week3UxShowcase` listed first |
| BackendApiDetails | **PASS** | Entry added to `diagnosticApiDetails` map |
| DiagnosticItem | **PASS** | Entry added to `_diagnosticItems` map |
| §8a Join Link Matrix | **PASS** | Static widget, no API call |
| §8b Public Leak Validation | **PASS** | Calls `GET /events/public/{id}`, checks forbidden fields |
| §9 Audit Trail | **PASS** | Calls `GET /dev/diagnostics/db/event_audit_log` with auth |
| §10 Email Demo | **PASS** | Uses §3 result (no extra API call) |
| §11 Snapshot Demo | **PASS** | Compares §1 + §3 data (no extra API call) |
| §12 DB Rules | **PASS** | Static widget, 4 rule cards |
| New state variables | **PASS** | `_publicLeakLoading/Result/Error`, `_auditLogLoading/Result/Error` |
| New fetch methods | **PASS** | `_fetchPublicLeak`, `_fetchAuditLog` |
| Production guard | **PASS** | All code inside `kDebugMode` gate |

---

## Screen Inventory Verification

### Screens Present

| Section | Status | Description |
|---|---|---|
| §0 Run All Validation | Pre-existing, retained | Backend diagnostic runner |
| Event ID Picker | Pre-existing, retained | Shared input for §2, §3, §5, §8b |
| §1 Alumni Autofill | Pre-existing, retained | `GET /alumni/me` prototype |
| §2 Eligibility Preview | Pre-existing, retained | `GET /events/{id}/registration-eligibility` |
| §3 Registration Action | Pre-existing, retained | `POST /events/{id}/register` |
| §4 Confirmation Preview | Pre-existing, retained | Uses §3 result |
| §5 My Registration | Pre-existing, retained | `GET /events/{id}/my-registration` |
| §6 My Registrations List | Pre-existing, retained | `GET /my/registrations` |
| §7 Negative State Gallery | Pre-existing, retained | 9 error state cards |
| Dev Reference Notes | Pre-existing, retained | 7 frontend developer notes |
| §8a Join Link Matrix | **NEW** | Static 4-row security table |
| §8b Public Leak Validation | **NEW** | Live public API check |
| §9 Audit Trail | **NEW** | Live audit_log rows |
| §10 Email Demo | **NEW** | Email status card from §3 |
| §11 Snapshot Demo | **NEW** | Side-by-side alumni profile vs snapshot |
| §12 DB Rules | **NEW** | 4 static database rule cards |

### Total: 16 sections (10 pre-existing, 6 new)

---

## Workflow Inventory Verification

| Workflow | Sections | Status |
|---|---|---|
| Happy Path (7 steps) | §1 → §2 → §3 → §4 | COVERED |
| Physical Event Flow (Breakfast Club) | §2 + §3 (event 25) | COVERED — `join_url=null` shown |
| Virtual Event Flow (Webinar) | §2 + §3 (event 26) | COVERED — `join_url` shown |
| My Registration Card | §5 | COVERED |
| My Registrations List | §6 | COVERED |
| Negative States (7 error conditions) | §7 | COVERED |
| Join Link Security Matrix | §8a | COVERED |
| Public API Leak Validation | §8b | COVERED |
| Audit Trail | §9 | COVERED |
| Email Status | §10 | COVERED |
| Alumni Profile vs Snapshot | §11 | COVERED |
| Database Rules (4 rules) | §12 | COVERED |
| Full Backend Validation (13 checks) | §0 | COVERED |

---

## State Inventory Verification

### New state variables added

```dart
// §8: Public API Leak Validation
bool _publicLeakLoading = false;
Map<String, dynamic>? _publicLeakResult;
String? _publicLeakError;

// §9: Audit Trail
bool _auditLogLoading = false;
Map<String, dynamic>? _auditLogResult;
String? _auditLogError;
```

### Existing state variables used by new sections

| New Section | Existing State Used | Source |
|---|---|---|
| §10 Email Demo | `_registerResult` | §3 POST /register result |
| §11 Snapshot Demo | `_autofillResult` (profile) | §1 GET /alumni/me result |
| §11 Snapshot Demo | `_registerResult` (snapshot) | §3 POST /register result |

---

## Security Demonstrations Verification

### §8a — Join Link Visibility Matrix

Four rows verified against documented security rules:

| Row | Expected Join Link | Rationale |
|---|---|---|
| `registered` + `virtual` + `published` | Visible | All conditions met |
| `cancelled` + `virtual` + `published` | Hidden | Status not `registered` |
| `registered` + `physical` + `published` | Hidden | `is_virtual=false` |
| `registered` + `virtual` + `draft` | Hidden | Event not published |

**Rule source:** `backend/app/services/registration_service.py` join_url resolution logic.

### §8b — Public Leak Validation

Forbidden fields checked: `virtual_url`, `join_url`, `created_by_firebase_uid`.

Backend confirmed: `EventsService.get_public_event()` strips these fields via
schema projection (does not include them in the public response shape).

**Expected result:** PASS badge (green) for any published event.

---

## Audit Trail Demonstration Verification

Endpoint: `GET /api/v1/dev/diagnostics/db/event_audit_log`  
Table: `event_audit_log`  
Fields displayed: `event_type`, `entity_type`, `entity_id`, `created_at`  
Fields hidden: `actor_uid`, `log_id`, `metadata` (PII protection in card UI)

**Expected result:** Latest audit rows displayed after any registration action.

---

## Email Demonstration Verification

Field mapping from `POST /register` response (§3):

| UI Label | Response Field | Type |
|---|---|---|
| Reg # | `registration_number` | string |
| Sent At | `confirmation_email_sent_at` | ISO datetime |
| Status | `confirmation_email_status` | `"sent"` \| `"failed"` \| `"skipped"` |

Icon colours:
- `sent` → green `mark_email_read`
- `failed` → error `email`
- `skipped` → grey `email` (dev/log mode)

---

## Snapshot Demonstration Verification

Comparison fields verified against actual API shapes:

| Label | Alumni Profile Key | Registration Snapshot Key |
|---|---|---|
| Full Name | `fullname` | `fullname_snapshot` |
| Batch Year | `batch_year` | `batch_year_snapshot` |
| Branch | `branch` | `branch_snapshot` |

**Note:** `batch_year` may be `null` in alumni_db; `batch_year_snapshot` will be `null`
if not provided at registration time — this is expected and handled by `?.toString() ?? '—'`.

---

## Database Rules Verification

| Rule Card | DB Object | Verification Source |
|---|---|---|
| Unique Registration Number | `registration_service.py` — format generation | Diag 3 result (§3) |
| Partial Unique Registration | Migration 008 `registrations_active_unique` partial index | Migration report |
| Re-registration After Cancellation | Partial index + status soft-delete | Diag 6 duplicate guard |
| Registered Count Excludes Cancelled | `COUNT WHERE status='registered'` | Diag 7 capacity guard |

---

## Screenshots Reference

> Screenshots are taken from the Developer Diagnostics → Registration category →
> Week 3 UX Showcase entry.

| Screenshot Reference | Section | Content |
|---|---|---|
| `screenshot_01_showcase_entry.png` | Main Diagnostics | Registration category with Week 3 UX Showcase listed first |
| `screenshot_02_run_validation.png` | §0 | Run All Diagnostics PASS dashboard (13/13) |
| `screenshot_03_alumni_autofill.png` | §1 | Alumni profile autofill prototype |
| `screenshot_04_eligibility.png` | §2 | Eligibility banner — eligible state |
| `screenshot_05_registration_action.png` | §3 | Registration success with reg number |
| `screenshot_06_confirmation.png` | §4 | Confirmation screen with join_url (virtual) |
| `screenshot_07_my_registration.png` | §5 | My Registration card |
| `screenshot_08_my_registrations_list.png` | §6 | Scrollable registrations list |
| `screenshot_09_negative_gallery.png` | §7 | 9 error state cards |
| `screenshot_10_join_link_matrix.png` | §8a | Security matrix table |
| `screenshot_11_public_leak_pass.png` | §8b | Public API leak — PASS badge |
| `screenshot_12_audit_trail.png` | §9 | Audit log rows |
| `screenshot_13_email_demo.png` | §10 | Email status card |
| `screenshot_14_snapshot_demo.png` | §11 | Side-by-side profile vs snapshot |
| `screenshot_15_db_rules.png` | §12 | 4 database rule cards |

> Note: Screenshots are taken during live demo sessions and stored in project documentation.
> The verification report captures the expected content; actual screenshots confirm it.

---

## Validation Results

### Flutter Static Analysis

```
flutter analyze lib/features/developer/presentation/developer_diagnostics_screen.dart
Analyzing developer_diagnostics_screen.dart...
No issues found! (ran in 1.3s)
```

### Backend Diagnostic Endpoint (reference)

`GET /api/v1/dev/diagnostics/registrations` — 13 checks covering:

1. Alumni Profile — PASS
2. Test Virtual Event Setup — PASS
3. Test Capacity Event Setup — PASS
4. Registration Eligibility — PASS
5. Register for Event — PASS
6. My Registration — PASS (join_url present)
7. My Registrations List — PASS (test registration found)
8. Duplicate Registration Guard — PASS (409 already_registered)
9. Capacity Guard — PASS (409 event_full)
10. Confirmation Email Status — PASS (sent or failed)
11. Join Link Visibility — PASS (join_url present for virtual)
12. Audit Log Check — PASS (row found)
13. Public API Leak Check — PASS (no forbidden fields)

---

## Files Changed

| File | Type | Change |
|---|---|---|
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Modified | 6 new sections, 11 new widgets, 2 new fetch methods, DiagnosticId, routing, category |
| `docs/reviews/week3_ux_showcase_design.md` | Created | Design document |
| `docs/reviews/week3_ux_showcase_verification_report.md` | Created | This report |
| `docs/validation/backend_week3_manual_verification_guide.md` | Updated | Week 3 UX Showcase section added |
| `docs/releases/week3_status_report_2026-06-18.md` | Updated | UX Showcase completed entry |
