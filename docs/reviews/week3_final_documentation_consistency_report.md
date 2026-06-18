# Week 3 — Final Documentation Consistency Report

**Date:** 2026-06-18  
**Reviewer:** CAR SOFTWARE SYSTEMS  
**Scope:** Week 3 documentation and Developer Diagnostics code vs. actual backend implementation  
**Status:** COMPLETE — all issues resolved

---

## Summary

A targeted consistency review was conducted across all Week 3 documentation and the Flutter
Developer Diagnostics screen. The primary finding (OI-3) was confirmed and fully resolved:
the `eligibility_status` values used throughout documentation and the Flutter diagnostics code
did not match the values returned by the actual backend service.

A secondary distinction was documented throughout: the GET `/registration-eligibility` endpoint
and the POST `/register` endpoint use **different string codes** for the same semantic state
(e.g., `full` vs. `event_full`). This was the root cause of the confusion. All files now clearly
separate the two code sets.

**Files updated: 2**  
**Files confirmed consistent: 5**  
**flutter analyze: PASS (0 issues)**

---

## Files Reviewed

| File | Type | Finding |
|---|---|---|
| `backend/app/services/registration_service.py` | Source of truth | Authoritative — defines actual `eligibility_status` values and POST error codes |
| `backend/app/schemas/registrations.py` | Source of truth | Authoritative — defines actual response shapes |
| `docs/api/events_api_contract_v2.md` | Documentation | Clean — v2 values already correct in eligibility table; POST error codes correct |
| `docs/releases/week3_closure_report.md` | Documentation | Clean — correct v2 values used throughout |
| `docs/releases/week3_readiness_review.md` | Documentation | Clean — OI-3 correctly described with v2 values |
| `docs/reviews/week3_phase3b_registration_ux_prototype_validation_report.md` | Documentation | **4 locations updated** — see below |
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Flutter code | **6 locations updated** — see below |

---

## Old Values Found

### In Flutter diagnostics screen (`developer_diagnostics_screen.dart`)

| Location | Old Value | Type of Error |
|---|---|---|
| `_uiStateStyle()` switch case | `'event_full'` | Wrong — used as `eligibility_status` but actual value is `'full'` |
| `_uiStateStyle()` switch case | `'registration_closed'` | Wrong — used as `eligibility_status` but actual value is `'closed'` |
| `_uiStateStyle()` switch case | `'registration_not_open_yet'` | Wrong — used as `eligibility_status` but actual value is `'not_open_yet'` |
| `_eligibilityCta()` switch case | `'event_full'` | Wrong — used as `eligibility_status` but actual value is `'full'` |
| `_eligibilityCta()` switch case | `'registration_closed'` | Wrong — used as `eligibility_status` but actual value is `'closed'` |
| `_eligibilityCta()` switch case | `'registration_not_open_yet'` | Wrong — used as `eligibility_status` but actual value is `'not_open_yet'` |
| §7 negative gallery card label | `'alumni_required'` | Wrong — not a valid code anywhere; POST `/register` uses `'alumni_only'` |
| Reference note 2 | `check ui_state` | Wrong field name — actual field is `eligibility_status` |
| Reference note 2 | `confirm_profile: true` | Wrong — `RegisterRequest` has no `confirm_profile` field |
| Reference note 5 | `alumni_required` | Wrong — actual POST error code is `alumni_only` |
| Reference note 6 | `confirmation_email.status` | Wrong — actual field name is `confirmation_email_status` (flat) |

### In Phase 3B report (`week3_phase3b_registration_ux_prototype_validation_report.md`)

| Location | Old Values | Type of Error |
|---|---|---|
| §2 eligibility_status values list (line 157-158) | `"event_full"`, `"registration_closed"`, `"registration_not_open_yet"`, `"alumni_required"`, `"alumni_not_active"` | Wrong — v1 design values, not actual service values |
| §2 prototype card colour mapping | `event_full`, `registration_closed`, `registration_not_open_yet` | Wrong — used as eligibility_status but actual values are `full`, `closed`, `not_open_yet` |
| §7 negative state gallery | `alumni_required` | Wrong — actual POST error code is `alumni_only` |
| §6 error code → UI state table | `alumni_required` | Wrong — actual POST error code is `alumni_only` |

---

## Files Updated

### 1. `developer_diagnostics_screen.dart`

**Change 1 — `_uiStateStyle()` switch (correctness bug)**

```dart
// Before (wrong — eligibility API returns these v2 values):
'event_full' => ...
'registration_closed' => ...
'registration_not_open_yet' => ...

// After (correct v2 eligibility_status values):
'full' => ...
'closed' => ...
'not_open_yet' => ...
```

**Change 2 — `_eligibilityCta()` switch (correctness bug)**

```dart
// Before:
'event_full' => 'Event Full',
'registration_closed' => 'Registration Closed',
'registration_not_open_yet' => 'Registration Not Open Yet',

// After:
'full' => 'Event Full',
'closed' => 'Registration Closed',
'not_open_yet' => 'Registration Not Open Yet',
```

**Change 3 — `_uiStateStyle()` comment (documentation)**

Added comment clarifying that POST `/register` uses different detail strings, and these are HTTP
error codes not `eligibility_status` values.

**Change 4 — §7 negative gallery `alumni_required` label**

```dart
// Before:
_negativeCard('alumni_required', ...)

// After:
_negativeCard('alumni_only', ...) // with annotation showing eligibility equivalent
```

All other §7 labels (`event_full`, `registration_closed`, `registration_not_open_yet`) were
retained as they are the correct POST `/register` HTTP error `detail` codes. Each card's message
text was extended with a parenthetical showing the corresponding eligibility_status value.

**Change 5 — Reference note 2 (two errors)**

```
// Before:
'② GET /events/{id}/registration-eligibility → check ui_state'
'③ POST /events/{id}/register with confirm_profile: true'

// After:
'② GET /events/{id}/registration-eligibility → check eligibility_status'
'③ POST /events/{id}/register — body: {"attendee_note": "optional"}'
```

**Change 6 — Reference note 5 (wrong error code + expanded mapping)**

```
// Before:
'alumni_required → "Alumni only" message'
'event_full → disabled register button'

// After (full two-code mapping):
'POST detail "alumni_only" / eligibility "ineligible" → "Alumni only" message'
'POST detail "alumni_not_active" / eligibility "ineligible" → "Contact support"'
'POST detail "event_full" / eligibility "full" → disabled register button'
'POST detail "registration_closed" / eligibility "closed" → disabled register button'
'POST detail "registration_not_open_yet" / eligibility "not_open_yet" → disabled register button'
'POST detail "already_registered" / eligibility "already_registered" → "View Registration" CTA'
'eligibility "ineligible" → read message field to distinguish alumni_only vs alumni_not_active'
```

**Change 7 — Reference note 6 (wrong field name)**

```
// Before:
'confirmation_email.status = "failed"'

// After:
'confirmation_email_status = "failed"'
```

---

### 2. `week3_phase3b_registration_ux_prototype_validation_report.md`

**Change 1 — §2 eligibility_status values list**

Replaced the v1 values list with the actual v2 values and added an explicit "Do not use v1 values"
warning block explaining the catch-all nature of `ineligible` and how to distinguish its sub-cases.

**Change 2 — §2 prototype card colour mapping description**

```
// Before:
error container for `event_full` / `registration_closed`,
tertiary container for `registration_not_open_yet`

// After:
error container for `full` / `closed`,
tertiary container for `not_open_yet`, surface for `ineligible`
```

**Change 3 — §7 negative state gallery table**

Restructured the table to add a "Eligibility equivalent" column and clarify that labels are POST
error `detail` codes. Fixed `alumni_required` → `alumni_only`. Added mapping rows for the
eligibility equivalent of each state.

**Change 4 — §6 error code → UI state mapping table**

Added "Eligibility equivalent" column. Fixed `alumni_required` → `alumni_only`. Added a
"Two-code rule" warning block explaining that both code sets must be handled in production.

---

## Final Eligibility Status Mapping

This is the authoritative mapping as of Week 3, derived directly from
`backend/app/services/registration_service.py`.

### GET /api/v1/events/{event_id}/registration-eligibility — `eligibility_status` values

| Value | Meaning | `registered_count` + `capacity` present? |
|---|---|---|
| `eligible` | User can register | Yes |
| `already_registered` | Active registration exists | No |
| `full` | `registered_count >= capacity` | Yes |
| `closed` | `now > registration_closes_at` | No |
| `not_open_yet` | `now < registration_opens_at` | No |
| `ineligible` | Catch-all: non-alumni, alumni not found, alumni not active, event not found, event not published | No |

### POST /api/v1/events/{event_id}/register — HTTP error `detail` codes

| HTTP | `detail` | Meaning |
|---|---|---|
| 403 | `alumni_only` | `user_type != 'alumni'` or no `ref_id` |
| 403 | `alumni_not_found` | `ref_id` not in alumni_db |
| 403 | `alumni_not_active` | `registrationstatus` not in `{'Active', 'Self-Verified'}` |
| 404 | `event_not_found` | event_id does not exist |
| 409 | `event_not_published` | `events.status != 'published'` |
| 409 | `registration_not_open_yet` | current time before `registration_opens_at` |
| 409 | `registration_closed` | current time after `registration_closes_at` |
| 409 | `already_registered` | active registration exists |
| 409 | `event_full` | `COUNT(status='registered') >= capacity` |

### Two-code cross-reference

| UI State | Eligibility `eligibility_status` | POST error `detail` |
|---|---|---|
| Alumni not allowed | `ineligible` (message: "Only alumni…") | `alumni_only` |
| Alumni not active | `ineligible` (message: "Alumni account is not active.") | `alumni_not_active` |
| Event full | `full` | `event_full` |
| Registration closed | `closed` | `registration_closed` |
| Registration not open | `not_open_yet` | `registration_not_open_yet` |
| Already registered | `already_registered` | `already_registered` |
| Event not published | `ineligible` (message: "Event is not open…") | `event_not_published` |

---

## Frontend Developer Warning

**READ BEFORE IMPLEMENTING THE PRODUCTION ELIGIBILITY UI**

The `GET /registration-eligibility` endpoint and the `POST /register` endpoint use **different
string values** for the same semantic states. This is a known implementation detail.

```
ELIGIBILITY ENDPOINT (GET)    ←→    POST REGISTER ERROR (409/403)
eligibility_status="full"           detail="event_full"
eligibility_status="closed"         detail="registration_closed"
eligibility_status="not_open_yet"   detail="registration_not_open_yet"
eligibility_status="ineligible"     detail="alumni_only"  OR  "alumni_not_active"
                                         (read message field to distinguish)
eligibility_status="already_registered"  detail="already_registered"  (same)
eligibility_status="eligible"            n/a — no error
```

**Rules:**

1. When switching on `eligibility_status` values: use `eligible`, `full`, `closed`, `not_open_yet`,
   `ineligible`, `already_registered`. Never use `event_full`, `registration_closed`,
   `registration_not_open_yet`, `alumni_required`, `alumni_not_active`, `can_register`.

2. When handling POST `/register` HTTP errors: use the `detail` field values: `alumni_only`,
   `alumni_not_found`, `alumni_not_active`, `event_not_found`, `event_not_published`,
   `event_full`, `registration_closed`, `registration_not_open_yet`, `already_registered`.
   Note: `alumni_required` **does not exist** — the correct code is `alumni_only`.

3. When `eligibility_status = "ineligible"`: read the `message` field, or call `GET /alumni/me`
   and check `is_active`, to distinguish between "not an alumni user" and "alumni not active".

4. API contract v2 (`docs/api/events_api_contract_v2.md`) is the authoritative reference.
   Do not use v1 shapes or values.

---

## Validation Performed

| Check | Method | Result |
|---|---|---|
| `flutter analyze` | `flutter analyze --no-fatal-infos` | **PASS — 0 issues** |
| `_uiStateStyle()` uses v2 eligibility values | Code review | **PASS** — `full`, `closed`, `not_open_yet` |
| `_eligibilityCta()` uses v2 eligibility values | Code review | **PASS** — `full`, `closed`, `not_open_yet` |
| No `can_register` in Flutter screen | `grep` | **PASS — not found** |
| No `alumni_required` in Flutter screen logic | `grep` | **PASS — only in §7 label as `alumni_only`** |
| No `ui_state` in Flutter screen | `grep` | **PASS — not found** |
| No `confirm_profile: true` in Flutter screen | `grep` | **PASS — not found** |
| No `confirmation_email.status` in Flutter screen | `grep` | **PASS — not found** |
| Phase 3B report eligibility list uses v2 values | Doc review | **PASS** |
| Phase 3B report §6 uses `alumni_only` not `alumni_required` | Doc review | **PASS** |
| Contract v2 eligibility table uses v2 values | Doc review | **PASS — no change needed** |
| Closure report uses v2 values | Doc review | **PASS — no change needed** |
| Readiness review uses v2 values | Doc review | **PASS — no change needed** |

---

## PASS / FAIL Status

| Area | Status | Notes |
|---|---|---|
| Backend service code (`registration_service.py`) | **PASS — source of truth, unchanged** | Defines actual values |
| Backend schemas (`schemas/registrations.py`) | **PASS — source of truth, unchanged** | Defines actual shapes |
| API contract v2 | **PASS** | Correct before this review; no changes needed |
| Week 3 closure report | **PASS** | Correct before this review; no changes needed |
| Readiness review | **PASS** | Correct before this review; no changes needed |
| Phase 3B report | **PASS (after 4 fixes)** | Old v1 eligibility values replaced with v2 |
| Flutter diagnostics — `_uiStateStyle()` | **PASS (after fix)** | Was broken: `event_full` etc. would never match |
| Flutter diagnostics — `_eligibilityCta()` | **PASS (after fix)** | Was broken: same issue |
| Flutter diagnostics — §7 gallery | **PASS (after fix)** | `alumni_required` → `alumni_only`; POST/eligibility duality annotated |
| Flutter diagnostics — reference notes | **PASS (after 3 fixes)** | `ui_state`, `confirm_profile`, field name all corrected |
| `flutter analyze` | **PASS** | 0 issues after all changes |

**Overall: PASS — all inconsistencies resolved.**

---

## Remaining Open Issues

These issues were known before this review (carried from week3_readiness_review.md) and are
unchanged. None were introduced by this review.

| # | Issue | Severity | Resolution |
|---|---|---|---|
| OI-1 | `RegisterRequest` has no `confirm_profile` field | Low | Decide in Week 4: add as optional no-op or leave absent |
| OI-2 | Eligibility response has no `event` or `my_registration` sub-objects | Medium | Decide in Week 4: add fields or leave flat |
| OI-3 | `eligibility_status` values differ from contract v1 | **RESOLVED** | Contract v2 and all docs now use actual v2 values |
| OI-4 | `GET /alumni/me` returns flat response, no `{status:ok, alumni:{...}}` wrapper | Low | Contract v2 formalises flat shape |
| OI-5 | `ListTile` / `DecoratedBox` assertion in event list screen (debug, pre-existing) | Low | Fix before production build |
| OI-6 | `ALUMNI_DB_URL` local setup not documented in README | Medium | Add to setup guide before new developer onboards |

---

## Recommendation for Week 4

**DOCUMENTATION IS CONSISTENT. SAFE TO PROCEED.**

1. **OI-3 is resolved.** The Flutter developer implementing production UI can use the API contract
   v2 and the developer diagnostics screen as authoritative references. All eligibility_status
   values and POST error codes are now documented consistently and correctly.

2. **Two-code awareness is required.** The eligibility endpoint and POST register endpoint use
   different codes for the same UI states. The production Flutter implementation must handle both.
   Use `eligibility_status` when processing eligibility responses; use `detail` when catching
   HTTP errors from POST register. The cross-reference table in this report is the definitive guide.

3. **`ineligible` is a catch-all.** When the eligibility endpoint returns `ineligible`, use the
   `message` field or call `GET /alumni/me` to distinguish between "not an alumni" and "alumni
   not active" for targeted user-facing messaging.

4. No backend code changes are required. All discrepancies were in documentation and the Flutter
   diagnostics prototype code only.
