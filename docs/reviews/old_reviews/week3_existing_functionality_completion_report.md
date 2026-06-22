# Week 3 — Existing Functionality Completion Report

**Date:** 2026-06-18  
**Sprint:** Week 3 — Registration, Alumni Autofill, Confirmation Email, Protected Join Link, Developer Diagnostics  
**Scope:** Pre-implementation audit of all files that Week 3 will read from or modify  
**Basis:** Actual file reads + actual DB schema confirmed via psql (not migration files alone)

---

## Summary Table

| File | Status | Week 3 Action |
|---|---|---|
| `registration_repository.py` | BROKEN | Full rewrite |
| `registration_service.py` | BROKEN | Full rewrite |
| `schemas/registrations.py` | BROKEN | Full rewrite |
| `alumni_service.py` | PARTIAL | Extend with ref_id lookup |
| `backend/src/services/alumni.py` | COMPLETE (pattern only) | Adapt to async; do not modify |
| `backend/src/services/notify.py` | COMPLETE (pattern only) | Adapt emit() for events_db tables; do not modify |
| `dev_diagnostics.py` | COMPLETE | Add registration category tests |
| `events.py` | COMPLETE | Add registered_count fix; no structural changes |
| `admin_events.py` | PARTIAL/BROKEN | Do not touch in Week 3 |
| `RegistrationsPage.jsx` | PLACEHOLDER | Do not touch in Week 3 (Week 4) |
| `eventsApi.js` | PARTIAL | Add registration API functions |
| `apiClient.js` | COMPLETE | No changes |
| `developer_diagnostics_screen.dart` | PARTIAL | Implement registration diagnostic items |
| `event_detail_screen.dart` | PLACEHOLDER | Replace `_register()` stub |
| `public_event_detail_service.dart` | COMPLETE | No changes |
| `backend_auth_service.dart` | COMPLETE | No changes |
| `004_registrations_and_check_ins.sql` | MISALIGNED | Superseded by migration 008 |
| `007_add_show_attendee_list.sql` | COMPLETE | No changes |
| Integration note | REFERENCE | All rules must be applied |

---

## File-by-File Analysis

---

### 1. `backend/app/repositories/registration_repository.py`

**Purpose:** Database access layer for registrations — INSERT, SELECT, UPDATE operations.

**Status:** BROKEN

**Working functionality:** None. File exists and is syntactically valid Python, but all queries reference column names that do not exist in the actual DB.

**Missing Week 3 functionality:**
- All functionality is missing. Existing code references:
  - `full_name` (actual column: none — was `badge_name`)
  - `registration_source` (does not exist in DB)
  - `qr_token` (actual column: `qrtoken` — different name; and Week 3 makes this nullable)
  - `metadata` (does not exist in DB)
  - `attendees` table — this table does not exist in the live DB
- No `registration_number` column support
- No snapshot column support (fullname_snapshot, email_snapshot, etc.)
- No confirmation_email_status tracking
- No transaction-safe capacity count query
- No `SELECT FOR UPDATE` on event row for concurrency safety

**Risks:**
- Any call to this repository will result in a PostgreSQL error (column does not exist or relation does not exist)
- `create_attendee()` inserts into a non-existent `attendees` table — immediate runtime failure
- Patching individual methods risks introducing inconsistency; a full rewrite is safer

**Required changes:**
- Complete rewrite targeting actual migration 004 + migration 008 columns
- Implement: `get_active_registration(event_id, firebase_uid)`, `count_active_registrations(event_id)`, `create_registration(...)`, `cancel_registration(registration_id)`, `get_my_registrations(firebase_uid)`, `get_my_event_registration(event_id, firebase_uid)`
- All queries must use asyncpg parameter style (`$1`, `$2`, not `%s`)
- Use `async with pool.acquire() as conn` pattern (existing project standard)

**Should modify in Week 3?** YES — full rewrite required before any registration endpoint can function

---

### 2. `backend/app/services/registration_service.py`

**Purpose:** Business logic layer for registration — validation, orchestration of repository calls, error mapping.

**Status:** BROKEN

**Working functionality:** None. File is alpha-era code with correct structural intent but broken implementation.

**Missing Week 3 functionality:**
- `find_active_by_email()` — references non-existent `attendees` table
- `create_attendee()` — references non-existent `attendees` table
- No alumni validation (no check that user_type == alumni, no alumni_db lookup, no active status check)
- No `registration_number` generation
- No confirmation email trigger
- No snapshot column population
- Error codes are wrong: uses `capacity_reached` (Week 3 contract: `event_full`), `registration_duplicate` (Week 3: `already_registered`), wrong HTTP status for `event_not_published` (uses 400, contract: 409)
- `registered_count` is read from `d["registered_count"]` which is the hardcoded 0 placeholder in events_service.py
- No transaction safety — no `SELECT FOR UPDATE` on event, no atomic capacity check

**Risks:**
- Wrong error codes will break Flutter UI state mapping
- Race condition: no transaction lock means two concurrent users can both see capacity=available and both register for the last seat
- Patching this file risks perpetuating the wrong error codes and structural gaps

**Required changes:**
- Complete rewrite
- Implement: `register_for_event(current_user, event_id, attendee_note)`, `get_registration_eligibility(current_user, event_id)`, `get_my_event_registration(current_user, event_id)`, `list_my_registrations(current_user)`, `cancel_registration(current_user, registration_id)`, `generate_registration_number()`
- Use async transaction: `async with conn.transaction()` + `SELECT ... FOR UPDATE` on event row
- Use correct Week 3 error codes as defined in the API contract
- Call alumni_db for profile and active status validation
- Trigger email service after commit (not inside transaction)

**Should modify in Week 3?** YES — full rewrite required

---

### 3. `backend/app/schemas/registrations.py`

**Purpose:** Pydantic request/response models for registration endpoints.

**Status:** BROKEN

**Working functionality:** None. Existing `RegistrationCreate` model uses alpha-era fields that don't match any current endpoint contract.

**Missing Week 3 functionality:**
- `RegistrationCreate` has `full_name`, `badge_name`, `metadata` — Week 3 contract has neither (registration data comes from alumni_db snapshot, not user input)
- `firebase_uid` and `ref_id` as optional input fields — in Week 3 these come from the authenticated JWT, not the request body
- No `RegistrationResponse` model matching Week 3 response contract
- No `RegistrationEligibilityResponse` model
- No `MyRegistrationsResponse` model
- No email status models

**Required changes:**
- Complete rewrite
- New models: `RegisterRequest` (only `attendee_note: Optional[str]`), `RegistrationResponse`, `RegistrationEligibilityResponse`, `MyRegistrationResponse`, `MyRegistrationsListResponse`
- `RegistrationResponse` must include: registration_id, registration_number, event_id, status, registered_at, fullname_snapshot, email_snapshot, phone_snapshot, batch_year_snapshot, branch_snapshot, confirmation_email_status, join_url (nullable, only for virtual events)

**Should modify in Week 3?** YES — full rewrite required

---

### 4. `backend/app/services/alumni_service.py`

**Purpose:** Backend service for alumni data lookup from alumni_db.

**Status:** PARTIAL — insufficient for Week 3

**Working functionality:**
- `find_alumni_by_email(email)` — used during `POST /auth/firebase` to identify alumni by email
- Returns 3 fields: `alumni_id`, `fullname`, `graduationyear`
- Uses asyncpg via `get_alumni_pool()` — correct connection pattern

**Missing Week 3 functionality:**
- No status/active check — does not filter by `registrationstatus` (active alumni only)
- Query returns only 3 fields — missing: `branch`, `email`, `phone`, `firebase_uid`, `registrationstatus`
- Lookup is by email only — Week 3 requires lookup by `ref_id` (= `alumni_id`) because that's what the JWT carries
- No `get_alumni_profile_by_ref_id(ref_id)` function

**Risks:**
- `find_alumni_by_email()` must NOT be changed — it is called during auth flow and changing it would break login
- A separate function should be added for registration use

**Required changes:**
- Keep `find_alumni_by_email()` unchanged
- Add `get_alumni_profile_by_ref_id(ref_id: str) -> Optional[Dict]` — queries alumni_db by `alumni_id = $1`, returns: alumni_id, fullname, email, phone, graduationyear, branch, registrationstatus, firebase_uid
- Add active status check: `registrationstatus IN ('Active', 'Self-Verified')` — same rule as portal
- Add `is_alumni_active(registrationstatus: str) -> bool` helper

**Should modify in Week 3?** YES — extend (do not replace existing functions)

---

### 5. `backend/src/services/alumni.py`

**Purpose:** Website cloned code — `fetch_alumni_info()` pattern for batch alumni lookup by firebase_uid list.

**Status:** COMPLETE (as a reference pattern — do not modify)

**Working functionality:**
- Batch lookup by firebase_uid list
- `TTLCache` (30 min, 5000 entries) — caching pattern to avoid repeated alumni_db hits
- `SELECT firebase_uid, alumni_id, fullname, graduationyear, branch FROM alumni WHERE firebase_uid = ANY(%s) AND directory_visible = true`
- Returns dict keyed by firebase_uid
- Uses psycopg2 (synchronous) — NOT compatible with event app's asyncpg

**Missing Week 3 functionality:**
- Uses `directory_visible = true` filter — this may not be appropriate for registration checks (an alumni not in directory should still be able to register if their account is active)
- Does not return `phone`, `email`, `registrationstatus` — needed for registration snapshot and active check
- psycopg2 is synchronous — cannot be awaited in asyncpg FastAPI routes

**Risks:**
- Do not `import` this file from the event app backend — it will break async context
- The integration note requires following the emit() and fetch_alumni_info() patterns — this means implementing equivalent async patterns in `backend/app/services/alumni_service.py`, not calling this file directly

**Required changes:**
- Do NOT modify this file
- Use it as a design reference only; implement an async equivalent in `alumni_service.py`

**Should modify in Week 3?** NO — reference only

---

### 6. `backend/src/services/notify.py`

**Purpose:** Website cloned code — `emit()` notification pattern for audit + in-app + email notifications.

**Status:** COMPLETE (as a reference pattern — do not modify)

**Working functionality:**
- Three-layer notification: audit log → in-app notification → background email thread
- `emit()` never raises exceptions — all failures are logged with `[notify]` prefix
- Background email via Gmail SMTP (`threading.Thread`)
- Writes to `website_audit_log` and `website_users` tables — these do NOT exist in events_db

**Missing Week 3 functionality (in events_db context):**
- References `website_audit_log` — events_db equivalent is `event_audit_log`
- References `website_users` — events_db equivalent is `event_users`
- `event_audit_log` schema: log_id, actor_uid, event_type, entity_type, entity_id, created_at — different from website schema
- Gmail SMTP is used — Week 3 needs an EmailService abstraction (log mode + sendgrid mode)
- No registration-specific event types: needs `registration_created`, `registration_cancelled`, `confirmation_email_sent`, `confirmation_email_failed`

**Required changes:**
- Do NOT modify this file
- Implement an adapted `emit()` equivalent in `backend/app/services/audit_service.py` that writes to `event_audit_log`
- Implement `backend/app/services/email_service.py` as a proper EmailService abstraction (EmailMode.LOG / EmailMode.SEND)
- The rule: `emit()` must never raise — must be applied to the adapted version

**Should modify in Week 3?** NO — reference only

---

### 7. `backend/app/api/dev_diagnostics.py`

**Purpose:** Developer-only diagnostic endpoint for testing infrastructure. Gated by `_require_development()`.

**Status:** COMPLETE (Week 2 functionality)

**Working functionality:**
- `GET /api/v1/dev/diagnostics` — returns structured diagnostic results
- `_require_development()` — returns 404 in production, 200 in dev
- `_diag_entry(name, passed, detail)` — consistent test result structure
- JWT auth via `decode_access_token()` — not the standard `get_current_user()` middleware
- 8 existing tests: auth (3), DB tables (3), event management (2) — all PASS in Week 2

**Missing Week 3 functionality:**
- Registration diagnostic category: 5 tests planned (registrationApi, myRegistration, capacityGuard, confirmationEmail, joinLinkVisibility)
- Alumni autofill diagnostic test
- Email status diagnostic test
- No `POST /api/v1/dev/diagnostics/registrations/run` action endpoint

**Risks:**
- Must not expose PII (alumni profile data) in diagnostic response bodies
- Must gate all new tests with `_require_development()`
- Diagnostic tests should not persist data (use cleanup or use a known test event)

**Required changes:**
- Add registration diagnostic tests: 5 tests for the Registration category
- Add alumni autofill test (calls `GET /alumni/me`, checks 200 + required fields)
- Add email status test (checks `confirmation_email_status` from last registration or config)
- Add join link test (checks virtual event registration response includes join_url, public response excludes it)
- Registration tests must use a valid published event from the DB, or have a fallback

**Should modify in Week 3?** YES — extend with registration category

---

### 8. `backend/app/api/events.py`

**Purpose:** Public and admin event CRUD endpoints. The canonical Week 2 events router.

**Status:** COMPLETE (Week 2)

**Working functionality:**
- `GET /api/v1/events/public` — public event list, no auth, no virtual_url
- `GET /api/v1/events/public/{event_id}` — public event detail, no virtual_url
- Admin routes via `get_admin_user` dependency
- `registered_count` present in response (currently hardcoded 0 via events_service.py)
- `registration_status` computed (logic correct, but always sees count=0)

**Missing Week 3 functionality:**
- `registered_count` is hardcoded 0 — `_enrich()` in events_service.py must be fixed to query actual count from registrations table
- `registration_status` will be correct once `registered_count` is real

**Risks:**
- Fixing `registered_count` requires a DB query per event — use a batched or aggregated subquery to avoid N+1
- Must confirm virtual_url remains excluded from public responses after serializer changes

**Required changes:**
- Fix `registered_count` in `events_service.py` `_enrich()` method to query actual count: `SELECT COUNT(*) FROM registrations WHERE event_id = $1 AND status = 'registered'`
- No structural changes to events.py itself

**Should modify in Week 3?** YES — fix registered_count in events_service.py

---

### 9. `backend/app/api/admin_events.py`

**Purpose:** Admin-only event management routes under `/api/v1/admin/`.

**Status:** PARTIAL/BROKEN

**Working functionality:**
- Admin route pattern uses `get_admin_user` (dev_auth) — correct for admin
- Event CRUD routes under `/api/v1/admin/` work (use alpha-era event_service.py / event_repository.py but events table schema is compatible)

**Missing Week 3 functionality:**
- `GET /admin/events/{id}/registrations` — calls `RegistrationService.list_registrations()` which is broken (alpha-era)
- `GET /admin/events/{id}/attendees` — calls `list_attendees()` which references missing `attendees` table
- Check-in routes — deferred to future week

**Risks:**
- Any call to `/admin/events/{id}/registrations` or `/admin/events/{id}/attendees` will crash at runtime
- Do NOT fix these in Week 3 — they are deferred to Week 4 admin attendee list

**Required changes:**
- None in Week 3 — leave broken admin registration/attendee routes as-is
- The `/admin/events/{id}/registrations` endpoint will remain broken until Week 4

**Should modify in Week 3?** NO — leave as-is; Week 4 scope

---

### 10. `admin/event_admin/src/pages/RegistrationsPage.jsx`

**Purpose:** React Admin page for viewing registrations.

**Status:** PLACEHOLDER

**Working functionality:**
- Renders a "Coming in Week 3" card
- Lists planned APIs as documentation: `POST /events/{id}/register`, `GET /events/{id}/my-registration`
- No actual API calls, no data display

**Missing Week 3 functionality:**
- All functionality is missing — this is intentional per Week 3 scope decision
- Attendee list, search, filter, CSV export are all Week 4

**Required changes:**
- None in Week 3

**Should modify in Week 3?** NO — Week 4 scope

---

### 11. `admin/event_admin/src/api/eventsApi.js`

**Purpose:** React Admin API client functions for event management.

**Status:** PARTIAL (events only)

**Working functionality:**
- `listEvents`, `getEvent`, `createEvent`, `updateEvent`, `updateEventStatus` — all complete
- Uses `apiClient.js` which handles auth headers and 401 redirect

**Missing Week 3 functionality:**
- No registration API functions
- No alumni API functions
- No diagnostic API functions

**Required changes (Week 3 minimum):**
- Add `getEventRegistrations(eventId)` — for admin to see registrations count/list (Week 4 full implementation, but API function can be added as stub)
- No urgent change needed for Week 3 since `RegistrationsPage.jsx` is not being implemented

**Should modify in Week 3?** OPTIONAL — can defer all changes to Week 4

---

### 12. `admin/event_admin/src/api/apiClient.js`

**Purpose:** Axios client with auth headers for React Admin.

**Status:** COMPLETE

**Working functionality:**
- Sends `Authorization: Bearer <token>` from session storage
- Sends `X-Dev-User` header from `VITE_DEV_USER` env var (for dev_auth admin routes)
- 401/403 → redirect to /login
- Correct base URL from `VITE_API_BASE_URL`

**Missing Week 3 functionality:** None

**Required changes:** None

**Should modify in Week 3?** NO

---

### 13. `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart`

**Purpose:** Flutter developer diagnostics UI. Development-only screen showing test results for backend infrastructure.

**Status:** PARTIAL

**Working functionality:**
- Shows Auth, DB Tables, Event Management categories with working tests
- Pattern: `DiagnosticCategory` → list of `DiagnosticItem` with status icons
- Runs all tests on screen load
- Registration category structurally defined in `_diagnosticCategories()` with correct 5 items

**Missing Week 3 functionality:**
- `DiagnosticId.registrationApi`, `registrantMyRegistration`, `capacityGuard`, `confirmationEmail`, `joinLinkVisibility` — items are referenced in category list but not defined in `_diagnosticItems()`
- No actual API calls for registration tests — all 5 items will fail or show empty state
- No alumni autofill panel
- No registration flow UI preview panels

**Risks:**
- If items are not defined in `_diagnosticItems()`, the screen will throw a null reference error when the Registration category is displayed
- Must verify that referenced `DiagnosticId` enum values exist before adding items

**Required changes:**
- Define all 5 `DiagnosticId` items in `_diagnosticItems()` with appropriate API calls
- Add implementations for: `registrationApi` → POST register test, `myRegistration` → GET my-registration test, `capacityGuard` → eligibility check test, `confirmationEmail` → email status check, `joinLinkVisibility` → join_url reveal test
- Add `AlumniAutofillPanel` or equivalent item for GET /alumni/me

**Should modify in Week 3?** YES — implement registration diagnostic items

---

### 14. `apps/event_app/lib/features/events/presentation/event_detail_screen.dart`

**Purpose:** Event detail screen — shows event info, register button.

**Status:** PLACEHOLDER (for registration)

**Working functionality:**
- Event detail display (title, description, dates, venue) — complete
- Auth check: unauthenticated user → navigate to /login
- Authenticated user → shows snackbar "Registration will be available in Week 3." — this is the placeholder

**Missing Week 3 functionality:**
- `_register()` method is a stub that shows a snackbar instead of calling the registration API
- No eligibility check before showing register button state
- No registration confirmation flow
- No "already registered" state handling
- No join link display for virtual events (this is expected — production UI is deferred, diagnostics handles it)

**Risks:**
- Week 3 scope says no production Flutter registration UI — but the existing snackbar stub must be replaced or kept clearly as a stub. The diagnostics screen is the reference implementation.
- If the `_register()` placeholder remains, users testing via the app directly won't be able to register from the event detail screen

**Required changes (Week 3):**
- Replace `_register()` stub with a real registration call via the registration service
- OR clearly document that registration from event detail screen is deferred and the diagnostics screen is the only registration path in Week 3
- Per Week 3 scope: diagnostics-first is acceptable; production event detail registration can be Week 4

**Should modify in Week 3?** OPTIONAL — diagnostics path is the Week 3 goal; event_detail_screen.dart registration can be Week 4 if diagnostics fully covers the flow

---

### 15. `apps/event_app/lib/features/events/services/public_event_detail_service.dart`

**Purpose:** Flutter service for fetching public event detail without auth.

**Status:** COMPLETE

**Working functionality:**
- `GET /api/v1/events/public/{eventId}` — no auth headers
- Returns event detail data to the UI
- Correctly uses unauthenticated request

**Missing Week 3 functionality:** None — this service intentionally excludes join_url (public API never returns it)

**Required changes:** None

**Should modify in Week 3?** NO

---

### 16. `apps/event_app/lib/features/auth/services/backend_auth_service.dart`

**Purpose:** Flutter service for Firebase → backend JWT auth flow.

**Status:** COMPLETE

**Working functionality:**
- `loginWithFirebaseToken(token)` → `POST /api/v1/auth/firebase` with `{'token': token}`
- `validateAccessToken()` → `GET /api/v1/auth/me`
- Returns backend JWT for use in all protected API calls

**Missing Week 3 functionality:** None

**Required changes:** None

**Should modify in Week 3?** NO

---

### 17. `backend/migrations/events_db/004_registrations_and_check_ins.sql`

**Purpose:** Created the registrations and check_ins tables in canonical numbered migration series.

**Status:** MISALIGNED with Week 3 contract

**Working functionality:** Migration ran successfully — tables confirmed in DB.

**Gaps vs Week 3 contract:**
- `status DEFAULT 'confirmed'` — Week 3 canonical status is `registered`
- `qrtoken TEXT UNIQUE NOT NULL` — Week 3 must make qrtoken nullable (QR not in Week 3 scope)
- `badge_name TEXT NOT NULL` — Week 3 registration contract has no badge_name
- Hard `UNIQUE(event_id, firebase_uid)` — blocks re-registration after cancellation; must be replaced with partial unique index
- Missing 12 columns required by Week 3 contract
- Missing `registration_number` column

**Required changes:** Superseded by migration 008 (do NOT re-run or modify migration 004)

**Should modify in Week 3?** NO — create migration 008 instead

---

### 18. `backend/migrations/events_db/007_add_show_attendee_list.sql`

**Purpose:** Added `show_attendee_list BOOLEAN DEFAULT false` to events table.

**Status:** COMPLETE

**Working functionality:** Column confirmed in events table (25th column in actual DB).

**Missing Week 3 functionality:** None

**Required changes:** None

**Should modify in Week 3?** NO

---

### 19. `docs/notes/june2026/nitksaa-event-app-integration-note_pw.md`

**Purpose:** Integration rules document — constraints that all Week 3 code must follow.

**Status:** REFERENCE — all rules active

**Critical rules for Week 3 implementation:**
1. Do not rerun old migrations blindly — verify actual schema first (done via psql)
2. Use alumni_db as source of truth for alumni profile data
3. Use `ref_id` → `alumni.alumni_id` for lookup (not email-based lookup for registration)
4. Implement `fetch_alumni_info()` equivalent pattern (async version in alumni_service.py)
5. Use `notify.py emit()` pattern for registration notifications (async adaptation in audit_service.py)
6. Email failure must never rollback successful registration
7. `virtual_url` must never appear in public APIs
8. `join_url` may only appear in authenticated registration endpoints
9. Do not store alumni profile fields in event_users — use registration snapshot columns only
10. All notifications must go through emit() — emit() must never raise

**Required changes:** None — this is a rules document, not source code

**Should modify in Week 3?** NO

---

## Week 3 Implementation Order (Based on This Audit)

```
Migration 008 (schema alignment)
  ↓
alumni_service.py extend (get_alumni_profile_by_ref_id)
  ↓
schemas/registrations.py rewrite
  ↓
registration_repository.py rewrite
  ↓
audit_service.py (emit() adaptation)
  ↓
email_service.py (EmailService abstraction)
  ↓
registration_service.py rewrite
  ↓
backend/app/api/alumni.py (new — GET /alumni/me)
  ↓
backend/app/api/registrations.py (new — registration endpoints)
  ↓
events_service.py fix (registered_count from DB)
  ↓
main.py register new routers
  ↓
dev_diagnostics.py extend (registration category)
  ↓
Flutter diagnostics screen (registration items)
```

---

## Files NOT Touched in Week 3

Per scope decision:
- `admin_events.py` admin registration/attendee routes — broken but leave for Week 4
- `RegistrationsPage.jsx` — placeholder stays for Week 4
- `event_detail_screen.dart` register button — diagnostics is the Week 3 registration UI
- `backend/src/services/alumni.py` and `notify.py` — reference only, do not modify
- All check-in, QR, attendance, waitlist, payment files — deferred

---

*This report was created as Part A of the Week 3 pre-implementation review. Schema verification (Part B) and migration 008 (Part C) follow.*
