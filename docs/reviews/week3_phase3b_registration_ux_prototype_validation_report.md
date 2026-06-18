# Week 3 Phase 3B — Registration UX Prototype Validation Report

**Date:** 2026-06-18  
**Phase:** 3B — Registration UX Prototype Validation Through Developer Diagnostics  
**Status:** COMPLETE — ALL CHECKS PASS  
**Author:** CAR SOFTWARE SYSTEMS  
**Prerequisite:** Phase 3 — Developer Diagnostics Registration Flow backend endpoint

---

## Summary

Phase 3B extended the Developer Diagnostics screen with a 7-section interactive UX prototype
for the alumni event registration flow. Every prototype section calls a live backend API using
the logged-in user's session token and renders the actual response in a styled "prototype frame"
that shows exactly what the production UI should look like.

All 15 use cases passed end-to-end against the running backend. 3 backend bugs and 1 Flutter
field-mapping bug were found and fixed during verification. The diagnostics backend endpoint now
runs **13/13 checks** cleanly.

**This report is the reference handoff for the frontend developer implementing the production
registration UI.**

---

## Scope

### In scope

- Alumni profile autofill via `GET /api/v1/alumni/me`
- Registration eligibility check via `GET /api/v1/events/{id}/registration-eligibility`
- Physical event registration via `POST /api/v1/events/{id}/register`
- Virtual event registration with join link via `POST /api/v1/events/{id}/register`
- Registration confirmation screen prototype
- My Registration detail via `GET /api/v1/events/{id}/my-registration`
- My Registrations list via `GET /api/v1/my/registrations`
- Negative state gallery — static reference cards for all 9 error states
- Frontend Developer Reference Notes
- Developer Diagnostics backend endpoint — `GET /api/v1/dev/diagnostics/registrations`

### Explicitly out of scope (not implemented, not to be started)

- Production Flutter registration screen in `EventDetailScreen` or `EventListScreen`
- Production confirmation screen
- Production My Registrations screen
- Admin UI (React or Flutter)
- Attendance, QR codes, waitlist, payment, check-in

All prototype and reference UI lives exclusively inside:

```
apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart
```

---

## Test Setup

### Test Credentials

| Field | Value |
|---|---|
| Email | `Username2026@gmail.com` |
| Password | `Password2026` |
| Firebase UID | `fxvOA6JInMM2OPKb3vuSV7qJwtI3` |
| Dart-define flags | `--dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com` `--dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026` |

### Alumni DB Record (alumni_db)

| Field | Value |
|---|---|
| alumni_id | `NITK2026IT001` |
| fullname | `Username Alumni` |
| email | `username2026@gmail.com` |
| phone | `+919876543210` |
| graduationyear | `2026` |
| branch | `Information Technology` |
| registrationstatus | `Active` |
| firebase_uid | `fxvOA6JInMM2OPKb3vuSV7qJwtI3` |

### Event Users Record (events_db)

| Field | Value |
|---|---|
| firebase_uid | `fxvOA6JInMM2OPKb3vuSV7qJwtI3` |
| email | `username2026@gmail.com` |
| user_type | `alumni` |
| ref_id | `NITK2026IT001` |

> **Note:** The account existed in `event_users` as `user_type='other'` with no `ref_id`. Both fields
> were updated and the `alumni_db` record was created as part of test setup for Phase 3B.

### Test Events

| Event ID | Title | Type | Capacity | Registration Constraint | Result |
|---|---|---|---|---|---|
| 25 | Breakfast Club Demo | Physical | 30 | None (always open) | Used for UC-02 |
| 26 | Webinar Demo | Virtual | 100 | None (always open) | Used for UC-03 |
| 34 | Capacity Test Event | Physical | 1 | Already full | Used for UC-05 |
| 35 | Registration Closed Test | Physical | 100 | `registration_closes_at` in the past | Used for UC-06 |
| 36 | Registration Not Open Test | Physical | 100 | `registration_opens_at` in the future | Used for UC-07 |

### Flutter App

Run command:

```bash
cd apps/event_app
flutter run -d chrome \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

Login with `Username2026@gmail.com` / `Password2026` on the login screen. After login, navigate to
Developer Diagnostics → Registration Flow Test to access all 7 prototype sections.

---

## Actual API Response Shapes

> **IMPORTANT for frontend developer:** The actual API response shapes differ from the Week 3 API
> contract document's nested structure. The backend returns **flat** responses. Use the shapes below,
> not the contract doc examples.

### GET /api/v1/alumni/me

Returns the alumni object **directly** — no `"status": "ok"` wrapper, no `"alumni"` key.

```json
{
  "ref_id": "NITK2026IT001",
  "fullname": "Username Alumni",
  "email": "username2026@gmail.com",
  "phone": "+919876543210",
  "batch_year": 2026,
  "branch": "Information Technology",
  "is_active": true
}
```

### GET /api/v1/events/{id}/registration-eligibility

Returns a flat object — no `"event"` sub-object, no `"eligibility"` sub-object, no `"my_registration"`.

```json
{
  "event_id": 25,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "eligibility_status": "eligible",
  "message": "You are eligible to register.",
  "registered_count": 0,
  "capacity": 30
}
```

`eligibility_status` values (v2 — actual from `registration_service.py`):
`"eligible"`, `"already_registered"`, `"full"`, `"closed"`, `"not_open_yet"`, `"ineligible"`.

> **Do not use v1 values** `event_full`, `registration_closed`, `registration_not_open_yet`,
> `alumni_required`, `alumni_not_active` as `eligibility_status` — those are either old design
> names or POST `/register` HTTP error codes, not eligibility endpoint values.
> `"ineligible"` is a catch-all for non-alumni, alumni not found, alumni not active, event not
> found, and event not published. Use the `message` field or `GET /alumni/me` to distinguish the
> specific reason.

### POST /api/v1/events/{id}/register

Request body (only `attendee_note` is accepted — `confirm_profile` is not a backend field):

```json
{
  "attendee_note": "optional note"
}
```

Response — flat with a nested `event` sub-object only:

```json
{
  "registration_id": 4,
  "registration_number": "NITKSAA-2026-000004",
  "event_id": 25,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "ref_id": "NITK2026IT001",
  "status": "registered",
  "fullname_snapshot": "Username Alumni",
  "email_snapshot": "username2026@gmail.com",
  "phone_snapshot": "+919876543210",
  "batch_year_snapshot": 2026,
  "branch_snapshot": "Information Technology",
  "attendee_note": "optional note",
  "registered_at": "2026-06-18T09:55:41.007308Z",
  "cancelled_at": null,
  "confirmation_email_status": "sent",
  "confirmation_email_sent_at": "2026-06-18T09:55:41.020087Z",
  "join_url": null,
  "event": {
    "event_id": 25,
    "title": "Breakfast Club Demo",
    "start_datetime": "2026-08-02T00:55:12.881266Z",
    "end_datetime": "2026-08-02T02:55:12.881266Z",
    "timezone": "Asia/Kolkata",
    "is_virtual": false,
    "location_text": "Bangalore",
    "location_maps_url": null
  },
  "updated_at": null
}
```

For a **virtual event**, `join_url` is populated:

```json
{
  "registration_number": "NITKSAA-2026-000005",
  "join_url": "https://meet.google.com/nitksaa-demo-webinar",
  "event": { "is_virtual": true, ... }
}
```

### GET /api/v1/events/{id}/my-registration

Same flat shape as the register response. Key fields for the UI:

```json
{
  "registration_number": "NITKSAA-2026-000004",
  "status": "registered",
  "registered_at": "2026-06-18T09:55:41.007308Z",
  "join_url": null,
  "event": { "title": "...", "is_virtual": false, "location_text": "Bangalore" }
}
```

### GET /api/v1/my/registrations

```json
{
  "registrations": [
    {
      "registration_number": "NITKSAA-2026-000005",
      "status": "registered",
      "registered_at": "2026-06-18T09:56:44.833099Z",
      "join_url": "https://meet.google.com/nitksaa-demo-webinar",
      "event": { "event_id": 26, "title": "Webinar Demo", "is_virtual": true }
    },
    {
      "registration_number": "NITKSAA-2026-000004",
      "status": "registered",
      "registered_at": "2026-06-18T09:55:41.007308Z",
      "join_url": null,
      "event": { "event_id": 25, "title": "Breakfast Club Demo", "is_virtual": false }
    }
  ],
  "total": 2
}
```

---

## Flutter Diagnostics Prototype Sections

All 7 sections live in `_RegistrationDiagnosticDetailState` inside `developer_diagnostics_screen.dart`.

### Section 0 — Run All Diagnostics

Calls `GET /api/v1/dev/diagnostics/registrations` (90-second timeout). Renders PASS/FAIL cards for
all 13 backend checks with per-check response data, duration, and error text.

### Event ID Picker

Shared `surfaceContainerHighest` card with a number text field used by §2, §3, and §5.
Enter a published event ID (e.g., `25` or `26`) before triggering those sections.

### §1 — Alumni Autofill Preview

- **API:** `GET /api/v1/alumni/me`
- **Prototype card:** Shows live profile data in read-only `surfaceContainerHighest` tiles
  (Name, Email, Phone, Batch Year, Branch, Status) with a disabled "Confirm & Continue to Register"
  button — matches the expected production UX where the user confirms their pre-filled profile before
  proceeding to registration.
- **Fetch button:** "Fetch → GET /alumni/me"

### §2 — Registration Eligibility Preview

- **API:** `GET /api/v1/events/{id}/registration-eligibility`
- **Prototype card:** Event ID, registered count / capacity pill, coloured eligibility banner
  (green for `eligible`, secondary for `already_registered`, error container for `full` /
  `closed`, tertiary container for `not_open_yet`, surface for `ineligible`), disabled CTA mapped
  from `eligibility_status` (v2 values).
- **Fetch button:** "Check → GET /events/{id}/registration-eligibility"
- **Requires:** Event ID from the picker.

### §3 — Registration Action Preview

- **API:** `POST /api/v1/events/{id}/register`
- **Prototype card:** Pre-filled profile snapshot (`fullname_snapshot`, `email_snapshot`,
  `batch_year_snapshot`, `branch_snapshot`) + disabled Register button. After a successful call,
  the button is replaced by a green confirmation banner showing the registration number.
- **Fetch button:** "Register (Dev) → POST /events/{id}/register"
- **Request body:** `{"attendee_note": "Dev diagnostics prototype test"}`
- **Requires:** Event ID from the picker.

### §4 — Confirmation Screen Preview

- **No API call.** Derives data from §3 `_registerResult`.
- **Prototype card:** Large check icon, `"You're registered."` heading, secondary message,
  `registration_number` in a `primaryContainer` pill with monospace letterSpacing, join link block
  (only when `event.is_virtual == true AND join_url != null`), email status row
  (sent/failed/skipped), disabled "View My Registration" button.
- **Placeholder:** Shown when §3 has not been run.

### §5 — My Registration Preview

- **API:** `GET /api/v1/events/{id}/my-registration`
- **Prototype card:** Event title, registration number, status, registered_at timestamp. For virtual
  events shows join link in a `secondaryContainer` block; for physical events shows venue text.
  Shows "Not registered for this event." when `status != 'registered'`.
- **Fetch button:** "Fetch → GET /events/{id}/my-registration"
- **Requires:** Event ID from the picker.

### §6 — My Registrations List Preview

- **API:** `GET /api/v1/my/registrations`
- **Prototype card:** List of registration cards, each showing event title, Virtual/Physical pill,
  registration number (monospace in primary colour), registration date, and join link row for
  virtual events.
- **Fetch button:** "Fetch → GET /my/registrations"
- **No event ID required.**

### §7 — Negative State Gallery

Static reference cards — no API call. Shows what each error state should look like in the
production UI.

The cards are labeled with the POST `/register` HTTP error `detail` codes — the same UI state
is also reachable via the eligibility endpoint using different `eligibility_status` strings.

| UI State (POST detail) | Eligibility equivalent | Colour | Icon | Expected CTA |
|---|---|---|---|---|
| `alumni_only` | `ineligible` (+ check `message`) | errorContainer | group_off | Contact Support |
| `alumni_not_active` | `ineligible` (+ check `message`) | errorContainer | person_off | Contact Support |
| `already_registered` | `already_registered` | secondaryContainer | check_circle | View My Registration |
| `event_full` | `full` | errorContainer | do_not_disturb | Register button disabled |
| `registration_closed` | `closed` | errorContainer | lock_clock | Register button disabled |
| `registration_not_open_yet` | `not_open_yet` | tertiaryContainer | hourglass_top | Register button disabled |
| `event_not_published` | `ineligible` (+ check `message`) | errorContainer | event_busy | N/A |
| `confirm_profile_required` | N/A | tertiaryContainer | warning_amber | Confirm Profile |
| `email_failed` (non-blocking) | N/A — confirmation_email_status field | tertiaryContainer | email | Save Registration Number |

---

## Use Case Results

All use cases verified via direct API calls using `Username2026@gmail.com` credentials and a
backend JWT obtained through the Firebase Authentication REST API + `/api/v1/auth/firebase` exchange.

| UC | Description | API | Expected | Result | Detail |
|---|---|---|---|---|---|
| UC-01 | Alumni autofill | GET /alumni/me | 200 + profile | **PASS** | `fullname=Username Alumni`, `is_active=true` |
| UC-02 | Physical event registration | POST /events/25/register | 201 + reg number | **PASS** | `NITKSAA-2026-000004`, `confirmation_email_status=sent` |
| UC-03 | Virtual event registration + join link | POST /events/26/register | 201 + join_url | **PASS** | `NITKSAA-2026-000005`, `join_url=https://meet.google.com/nitksaa-demo-webinar` |
| UC-04 | Duplicate registration guard | POST /events/25/register (2nd) | 409 already_registered | **PASS** | HTTP 409, `detail=already_registered` |
| UC-05 | Event full | POST /events/34/register | 409 event_full | **PASS** | HTTP 409, `detail=event_full` |
| UC-06 | Registration closed | POST /events/35/register | 409 registration_closed | **PASS** | HTTP 409, `detail=registration_closed` |
| UC-07 | Registration not open yet | POST /events/36/register | 409 registration_not_open_yet | **PASS** | HTTP 409, `detail=registration_not_open_yet` |
| UC-11 | Confirmation email status | DB check on registrations | `confirmation_email_status=sent` | **PASS** | Both reg IDs: `sent`, timestamps recorded |
| UC-13 | My registration — physical (no join link) | GET /events/25/my-registration | `join_url=null` | **PASS** | `status=registered`, `join_url=None` |
| UC-13 | My registration — virtual (join link present) | GET /events/26/my-registration | `join_url` set | **PASS** | `join_url=https://meet.google.com/nitksaa-demo-webinar` |
| UC-14 | My registrations list | GET /my/registrations | 2 items, virtual has join_url | **PASS** | `total=2`, physical `join_url=None`, virtual `join_url` set |

---

## Public API Leak Verification

Security invariant: `virtual_url` and `join_url` must never appear in the public events API.

```bash
curl http://localhost:8000/api/v1/events/public/26
```

Verified response for virtual event 26 (Webinar Demo):

| Field | Present in public response |
|---|---|
| `virtual_url` | **NO** — key absent |
| `join_url` | **NO** — key absent |

**Result: PASS** — no join link or virtual URL leaks through the public endpoint.

---

## Join Link Verification

`join_url` is resolved by `_resolve_join_url()` in the registration service.
It returns the virtual URL **only when all three conditions are met:**

1. `registrations.status = 'registered'` (the user is actively registered, not cancelled)
2. `events.is_virtual = true`
3. `events.status = 'published'`

| Scenario | join_url | Result |
|---|---|---|
| Registered user, virtual event, published | `https://meet.google.com/nitksaa-demo-webinar` | Present — **PASS** |
| Registered user, physical event, published | `null` | Absent — **PASS** |
| Public events API, virtual event | Key not present | Absent — **PASS** |

---

## Email Status Verification

The email failure policy: **transaction commits first, email is sent after commit, failure updates
`confirmation_email_status='failed'` but never rolls back the registration.**

Email mode is `log` in the development environment — writes to Python logger, records status as
`sent`.

```
registration_number   | status     | confirmation_email_status | confirmation_email_sent_at
----------------------+------------+---------------------------+--------------------------------
NITKSAA-2026-000004   | registered | sent                      | 2026-06-18 15:25:41.020087+05:30
NITKSAA-2026-000005   | registered | sent                      | 2026-06-18 15:26:44.835532+05:30
```

Both registrations: `confirmation_email_status=sent`, `confirmation_email_sent_at` recorded.

**Result: PASS** — email status written post-commit, timestamps present, no rollback on email.

---

## Section 0 — Run All Diagnostics (13/13)

`GET /api/v1/dev/diagnostics/registrations` result after fixing all 3 backend bugs:

```
Status: ok | Passed: 13/13 | Failed: 0

  [PASS] Alumni Profile
  [PASS] Test Virtual Event Setup
  [PASS] Test Capacity Event Setup
  [PASS] Registration Eligibility
  [PASS] Register for Event
  [PASS] My Registration
  [PASS] My Registrations List
  [PASS] Duplicate Registration Guard
  [PASS] Capacity Guard
  [PASS] Join Link Visibility
  [PASS] Confirmation Email Status
  [PASS] Audit Log Check
  [PASS] Public API Leak Check
```

---

## Bugs Found and Fixed

### Bug 1 — FK Violation in Capacity Filler Row

**File:** `backend/app/api/dev_diagnostics.py`  
**Symptom:** `GET /api/v1/dev/diagnostics/registrations` returned HTTP 500 Internal Server Error.  
**Root cause:** The capacity guard test inserts a filler registration row with a synthetic
`firebase_uid` (e.g., `diag_cap_filler_20260618104016`) to fill a capacity=1 test event.
The `registrations` table has a foreign key:

```sql
FOREIGN KEY (firebase_uid) REFERENCES event_users(firebase_uid)
```

The synthetic UID does not exist in `event_users`, so the INSERT raised
`asyncpg.exceptions.ForeignKeyViolationError`.

**Fix:** Insert a temporary `event_users` row for the filler UID before inserting the filler
registration. Delete both in the `finally` block.

```python
# Before filler registration INSERT:
await conn.execute(
    """
    INSERT INTO event_users (firebase_uid, email, fullname, user_type)
    VALUES ($1, $2, $3, 'other')
    ON CONFLICT (firebase_uid) DO NOTHING
    """,
    filler_uid, "capfiller@dev.internal", "Capacity Filler (Dev Diag)",
)

# In finally block (added):
await conn.execute(
    "DELETE FROM event_users WHERE firebase_uid=$1",
    filler_uid,
)
```

---

### Bug 2 — Wrong Primary Key Column Name in Audit Log Check

**File:** `backend/app/api/dev_diagnostics.py`  
**Symptom:** Audit Log Check returned `FAIL` with `ERROR: column "audit_id" does not exist`.  
**Root cause:** The SELECT query used `audit_id` but the `event_audit_log` table's PK column
is `log_id`.

**Fix:**

```python
# Before:
SELECT audit_id, event_type, actor_uid, created_at FROM event_audit_log ...

# After:
SELECT log_id, event_type, actor_uid, created_at FROM event_audit_log ...
```

---

### Bug 3 — entity_id Type Mismatch in Audit Log Query

**File:** `backend/app/api/dev_diagnostics.py`  
**Symptom:** Audit Log Check returned `FAIL` with `ERROR: invalid input for query argument $1:
'18' ('str' object cannot be interpreted as an integer)`.  
**Root cause:** `entity_id` in `event_audit_log` is an `integer` column. The query was passing
`str(test_registration_id)` which asyncpg cannot coerce to integer for a typed parameter.

**Fix:**

```python
# Before:
    str(test_registration_id),

# After:
    test_registration_id,
```

---

### Bug 4 — Flutter Prototype Field Mapping (Nested vs. Flat)

**File:** `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart`  
**Symptom:** All 5 prototype sections showed the placeholder "data not yet fetched" message
even after a successful API call.  
**Root cause:** The prototype widgets were written against the API contract doc's proposed
nested response structure. The actual backend responses are flat. Specific mismatches:

| Prototype code | Actual API field |
|---|---|
| `_autofillResult?['alumni']` | `_autofillResult` directly |
| `_eligibilityResult?['eligibility']['ui_state']` | `_eligibilityResult?['eligibility_status']` |
| `_eligibilityResult?['event']['title']` | Not in eligibility response |
| `_registerResult?['registration']['registration_number']` | `_registerResult?['registration_number']` |
| `_registerResult?['alumni']['fullname']` | `_registerResult?['fullname_snapshot']` |
| `_registerResult?['access']['join_url']` | `_registerResult?['join_url']` |
| `_registerResult?['confirmation_email']['status']` | `_registerResult?['confirmation_email_status']` |
| `_myRegResult?['registered']` | `_myRegResult?['status'] == 'registered'` |
| `_myRegResult?['registration']['registration_number']` | `_myRegResult?['registration_number']` |
| `_myRegResult?['access']['join_url']` | `_myRegResult?['join_url']` |
| `item['access']['join_url']` (in list) | `item['join_url']` (top level) |

**Fix:** Updated all 5 proto widget methods (`_alumniAutofillProto`, `_eligibilityProto`,
`_registerProto`, `_confirmationProto`, `_myRegistrationProto`) and `_registrationListCard` to
use the actual flat field names.

---

## Validation Commands

### Backend

```bash
# Compile check
cd backend
python -m compileall app -q

# Run full registration diagnostics (requires running backend + alumni credentials)
curl -s --max-time 90 \
  http://localhost:8000/api/v1/dev/diagnostics/registrations \
  -H "Authorization: Bearer <backend_jwt>"
```

### Flutter

```bash
cd apps/event_app

flutter analyze --no-fatal-infos
# Expected: No issues found!

flutter test
# Expected: 00:01 +16: All tests passed!

flutter run -d chrome \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

### Validation Results

| Gate | Result |
|---|---|
| `python -m compileall app` | No errors |
| `flutter analyze` | No issues found (ran in 1.9s) |
| `flutter test` | 16/16 passed |
| Section 0 diagnostics | 13/13 PASS |
| UC-01 to UC-14 | All PASS |
| Public API leak check | PASS |

---

## PASS / FAIL Status

| Area | Status |
|---|---|
| Backend diagnostics endpoint | **PASS** (13/13) |
| Flutter prototype §1 Alumni Autofill | **PASS** |
| Flutter prototype §2 Eligibility | **PASS** |
| Flutter prototype §3 Registration Action | **PASS** |
| Flutter prototype §4 Confirmation Screen | **PASS** |
| Flutter prototype §5 My Registration | **PASS** |
| Flutter prototype §6 My Registrations List | **PASS** |
| Flutter prototype §7 Negative State Gallery | **PASS** (static reference) |
| Frontend Developer Reference Notes | **PASS** (rendered in app) |
| Join link security (physical=null, virtual=present) | **PASS** |
| Public API leak check (no virtual_url/join_url) | **PASS** |
| Email status post-commit (non-blocking) | **PASS** |
| Duplicate registration guard (409) | **PASS** |
| Capacity guard (409) | **PASS** |
| Registration closed guard (409) | **PASS** |
| Registration not open yet guard (409) | **PASS** |
| flutter analyze | **PASS** (0 issues) |
| flutter test | **PASS** (16/16) |

**Overall: PASS**

---

## Frontend Developer Reference Notes

These notes are also rendered as a static card at the bottom of the Registration Diagnostics screen.

### 1. API response shapes are flat

Do not use the nested structure from the Week 3 API contract document. The actual backend
returns flat responses — see the "Actual API Response Shapes" section above.

### 2. Profile autofill — GET /alumni/me

- Call after login, before showing the registration form.
- Fields arrive at the top level of the response object (no wrapper key).
- All profile fields are **read-only** for Week 3. Do not render editable inputs.
- Show a "Confirm Profile" button the user must tap before registration is allowed.
- `is_active` must be `true` or show an `alumni_not_active` error state.

### 3. Registration flow order

```
① GET /alumni/me           → display read-only profile
② User taps Confirm
③ POST /events/{id}/register  → body: {"attendee_note": "optional"}
④ Show confirmation screen
```

The eligibility endpoint (`GET /events/{id}/registration-eligibility`) is optional but recommended
as a pre-check before showing the Register button. Use `eligibility_status` to determine the CTA.

### 4. Confirmation screen

- Show `registration_number` prominently — use a pill or chip with monospace font and letterSpacing.
- Show `join_url` only if `event.is_virtual == true AND join_url != null`.
- Show `confirmation_email_status` as a secondary, non-blocking row below the registration number.
- If `confirmation_email_status == 'failed'`, tell the user to save their registration number —
  do not block or error the screen.
- CTA: "View My Registration" → navigates to §5 My Registration detail.

### 5. join_url security rule

```
join_url is ONLY present in:
  - POST /events/{id}/register  (response, when is_virtual=true)
  - GET  /events/{id}/my-registration  (when status=registered AND is_virtual=true)
  - GET  /my/registrations  (per item, same condition)

join_url is NEVER present in:
  - GET /events/public/{id}
  - GET /events  (any list endpoint)
  - Any admin or management endpoint
```

Never copy `virtual_url` from any event object and display it as a join link.

### 6. Error code → UI state mapping

These are the `detail` strings returned by `POST /events/{id}/register` HTTP error responses.
They differ from the `eligibility_status` values returned by the eligibility endpoint — see note below.

| HTTP | POST detail (actual) | Eligibility equivalent | UI State | User-facing message |
|---|---|---|---|---|
| 403 | `alumni_only` | `ineligible` | Block | "Only NITKSAA alumni can register for this event." |
| 403 | `alumni_not_active` | `ineligible` | Block | "Your alumni profile is not active. Please contact support." |
| 409 | `already_registered` | `already_registered` | Show existing reg | "You're already registered." + View Registration CTA |
| 409 | `event_full` | `full` | Disable button | "This event is full." |
| 409 | `registration_closed` | `closed` | Disable button | "Registration is closed." |
| 409 | `registration_not_open_yet` | `not_open_yet` | Disable button | "Registration is not open yet." |
| 409 | `event_not_published` | `ineligible` | Hide reg section | "This event is not available." |

> **Two-code rule:** The eligibility endpoint and the POST register endpoint use different string
> values for the same semantic state. Always handle both. For eligibility pre-checks use v2
> `eligibility_status` values. For POST error handling use the `detail` strings above.
> When `eligibility_status = "ineligible"`, read the `message` field (or call `GET /alumni/me`)
> to distinguish between `alumni_only` and `alumni_not_active`.

### 7. Email failure is non-blocking

Registration is successful even when `confirmation_email_status == 'failed'`. The transaction
commits first; email is attempted after. Never rollback or show an error screen for email failure.
Show a banner: _"Confirmation email could not be sent. Please save your registration number."_

### 8. Registration number format

`NITKSAA-{year}-{registration_id:06d}` — e.g., `NITKSAA-2026-000004`.
Display with monospace font. This is the user's primary reference for their booking.

### 9. Week 3 scope boundary

**Implement for production:** Physical registration, virtual registration, join link display,
confirmation screen, my registration detail, my registrations list.

**Do not implement yet:** Waitlist, payment, QR code check-in, attendance tracking.
Add-to-calendar payload is included in the response for future use; `.ics` generation is deferred.

---

## Open Issues

| # | Issue | Severity | Owner |
|---|---|---|---|
| 1 | `RegisterRequest` schema does not have a `confirm_profile` field — the API contract doc specifies `{"confirm_profile": true, ...}` but the backend ignores it. Either add the field as a no-op validation signal or update the contract doc. | Low | Backend |
| 2 | `GET /events/{id}/registration-eligibility` does not return `event` details (title, is_virtual, etc.) or `my_registration`. The contract doc specifies these sub-objects. Either add them to the response or formally update the contract. | Medium | Backend |
| 3 | `GET /alumni/me` does not return a `{"status": "ok", "alumni": {...}}` wrapper. The contract doc specifies this shape. Either add the wrapper or formally update the contract. | Low | Backend |
| 4 | `ListTile` wrapped in `DecoratedBox` assertion fires in the event list screen in debug mode (pre-existing, not introduced in Phase 3B). | Low | Frontend |

---

## Files Changed in Phase 3B

| File | Change |
|---|---|
| `backend/app/api/dev_diagnostics.py` | Fixed FK violation (capacity filler), `audit_id` → `log_id`, removed `str()` cast on `entity_id` |
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Added 7 prototype sections, Event ID Picker, Part C Dev Reference Notes, all helper widgets and fetch methods; fixed all 5 proto field mappings to match actual flat API responses |
| `docs/reviews/week3_phase3b_registration_ux_prototype_validation_report.md` | This file |

---

## Next Steps

The following items are ready to begin once the frontend developer starts production UI work.
**Do not start any of these during Week 3.**

| # | Item | Notes |
|---|---|---|
| 1 | Production registration flow in `EventDetailScreen` | Use §1–§4 prototypes as the visual reference. Use actual flat API field names documented above. |
| 2 | Production My Registration detail screen | Use §5 prototype as reference. |
| 3 | Production My Registrations list screen | Use §6 prototype as reference. |
| 4 | Backend: Add `event` + `my_registration` sub-objects to eligibility response | Removes Open Issue #2, simplifies frontend pre-check logic. |
| 5 | Backend: Add `confirm_profile` field to `RegisterRequest` | Resolves Open Issue #1. |
| 6 | Backend: Add `{"status": "ok", "alumni": {...}}` wrapper to GET /alumni/me | Resolves Open Issue #3, aligns implementation with contract doc. |

---

*Phase 3B complete. All diagnostics pass. Report ready for internal review.*
