# Week 3 — Manual Verification Guide v2

**Date:** 2026-06-19  
**Version:** 2.0  
**Branch:** main  
**Status:** Final — Week 3 (includes UX Showcase)  
**Supersedes:** `backend_week3_manual_verification_guide_v1.md`

> **Scope:** Step-by-step manual verification of all Week 3 registration use cases using the
> Flutter Developer Diagnostics screen (including the Week 3 UX Showcase), backend API curl
> commands, and direct database queries.  
> All values in this guide reflect the **actual backend implementation (v2)**. Do not use v1 values.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Login Verification](#2-login-verification)
3. [Developer Diagnostics — Run All Checks](#3-developer-diagnostics--run-all-checks)
4. [Week 3 UX Showcase — Step-by-Step](#4-week-3-ux-showcase--step-by-step)
5. [Positive Use Cases (curl)](#5-positive-use-cases-curl)
6. [Negative Use Cases (curl)](#6-negative-use-cases-curl)
7. [Security Tests](#7-security-tests)
8. [API Integrity Tests](#8-api-integrity-tests)
9. [Database Constraint Tests](#9-database-constraint-tests)
10. [Test Event Reference](#10-test-event-reference)
11. [Expected API Response Shapes (v2)](#11-expected-api-response-shapes-v2)
12. [Expected UI States (v2)](#12-expected-ui-states-v2)
13. [Backend API Curl Reference](#13-backend-api-curl-reference)
14. [Database Verification Queries](#14-database-verification-queries)
15. [Troubleshooting](#15-troubleshooting)
16. [Final PASS/FAIL Checklist](#16-final-passfail-checklist)

---

## 1. Prerequisites

### 1.1 Environment Requirements

| Requirement | Value | How to Check |
|---|---|---|
| `APP_ENV` | `development` | `grep APP_ENV backend/.env` |
| `EVENTS_DB_URL` | set (local PostgreSQL) | `grep EVENTS_DB_URL backend/.env` |
| `ALUMNI_DB_URL` | set (local PostgreSQL) | `grep ALUMNI_DB_URL backend/.env` |
| `FIREBASE_PROJECT_ID` | set | `grep FIREBASE_PROJECT_ID backend/.env` |
| `DEV_DIAGNOSTICS_EMAIL` | `Username2026@gmail.com` | `grep DEV_DIAGNOSTICS_EMAIL backend/.env` |
| Flutter SDK | 3.x or later | `flutter --version` |
| Python 3.11+ | required for curl pretty-print | `python3 --version` |
| psql | required for DB queries | `psql --version` |

> **Critical:** If `ALUMNI_DB_URL` is not set, the test user will authenticate as
> `user_type="other"` instead of `"alumni"`, and all alumni-gated endpoints will return
> `alumni_only` or `ineligible`. Set `ALUMNI_DB_URL` before running any registration tests.
> See `docs/GETTING_STARTED_WEEK3.md` for local alumni_db setup instructions.

### 1.2 Start the Backend

**Terminal 1:**

```bash
cd backend
uvicorn app.main:app --port 8000 --log-level warning
```

Wait for: `Application startup complete.`

Verify health:

```bash
curl http://localhost:8000/health
# Expected: {"status":"ok"}
```

### 1.3 Start the Flutter App

**Terminal 2:**

```bash
cd apps/event_app
flutter run -d chrome \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

> The `--dart-define` flags inject credentials that `DevAccessConfig` reads at compile time.
> Without these flags, the Developer Diagnostics screen will not auto-login.

### 1.4 Test Account

| Field | Value |
|---|---|
| Email | `Username2026@gmail.com` |
| Password | `Password2026` |
| Firebase UID | `fxvOA6JInMM2OPKb3vuSV7qJwtI3` |
| Alumni ID (`ref_id`) | `NITK2026IT001` |
| `user_type` | `alumni` |
| `registrationstatus` in alumni_db | `Active` |

### 1.5 Test Events (Quick Reference)

| Event ID | Type | Scenario |
|---|---|---|
| 25 | Physical | Open — positive registration test |
| 26 | Virtual | Open — join_url test |
| 34 | Physical | Full (capacity=1) — capacity guard |
| 35 | Physical | Registration closed (window past) |
| 36 | Physical | Registration not open yet (window future) |

> If any of these events are missing, see [Section 10.3](#103-recreate-test-events) for recreation SQL.

---

## 2. Login Verification

### 2.1 Via Flutter Developer Diagnostics

1. Open the Flutter app in Chrome (started with `--dart-define` flags in §1.3).
2. Navigate to **Developer Diagnostics** (bottom nav bar or Foundation Ready screen).
3. The screen auto-logs in using the injected credentials on mount.

**Expected header:**

```
Logged in as: Username2026@gmail.com
Type: alumni | Ref: NITK2026IT001
```

**If the header shows "Not logged in":** The `--dart-define` flags were omitted. Restart Flutter with the full command from §1.3.

### 2.2 Via curl (Two-Step)

**Step 1 — Get Firebase idToken:**

```bash
FIREBASE_API_KEY="your-firebase-web-api-key"   # from Firebase console → Project settings

curl -s -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "Username2026@gmail.com",
    "password": "Password2026",
    "returnSecureToken": true
  }' | python3 -m json.tool
```

Copy the `idToken` value from the response (a long JWT string).

**Step 2 — Exchange for backend access_token:**

```bash
FIREBASE_ID_TOKEN="paste-id-token-from-step-1"

ACCESS_TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/firebase \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"${FIREBASE_ID_TOKEN}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "ACCESS_TOKEN=${ACCESS_TOKEN}"
```

**Expected response (Step 2):**

```json
{
  "status": "ok",
  "access_token": "<HS256 JWT>",
  "token_type": "bearer",
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "user_type": "alumni",
  "fullname": "<name from alumni_db>",
  "ref_id": "NITK2026IT001",
  "graduation_year": 2026
}
```

**PASS criteria:**
- `user_type` is `"alumni"` (not `"other"`)
- `ref_id` is `"NITK2026IT001"` (not `null`)
- `access_token` is a non-empty string

> Store `ACCESS_TOKEN` in your shell session. All subsequent curl commands in this guide use it.
> The token expires after 480 minutes (development setting). Re-run Step 2 if it expires.

### 2.3 Verify Current User

```bash
curl -s http://localhost:8000/api/v1/auth/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected: `firebase_uid`, `email`, `user_type: "alumni"`, `ref_id: "NITK2026IT001"`.

---

## 3. Developer Diagnostics — Run All Checks

### 3.1 Overview

The Developer Diagnostics screen runs a 13-check diagnostic suite against the backend.
All 13 checks must PASS. If any check FAILs, see [Section 15](#15-troubleshooting).

### 3.2 Via Flutter Screen

1. Open Developer Diagnostics.
2. Tap **Registration** category to expand it.
3. Tap any Registration item (e.g., **Registration Flow Test**).
4. Tap **"Run All Registration Diagnostics"**.
5. Wait up to 90 seconds.
6. Inspect the result card per check — all must show green PASS.

### 3.3 Via curl

```bash
curl -s http://localhost:8000/api/v1/dev/diagnostics/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

**Top-level response shape:**

```json
{
  "status": "ok",
  "category": "Registration Flow",
  "total": 13,
  "passed": 13,
  "failed": 0,
  "test_virtual_event_id": <int>,
  "test_registration_id": <int>,
  "is_alumni_user": true,
  "results": [...],
  "run_by": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "run_at": "2026-06-19T..."
}
```

**PASS criteria:** `"passed": 13`, `"failed": 0`.

### 3.4 The 13 Checks

| # | Check Name | Method + Endpoint | PASS Condition |
|---|---|---|---|
| 1 | Alumni Profile | `GET /api/v1/alumni/me` | `is_active: true` |
| 2 | Test Virtual Event Setup | `POST /api/v1/events` (admin) | `status: "published"`, `is_virtual: true` |
| 3 | Test Capacity Event Setup | `POST /api/v1/events` (admin) | `status: "published"`, `capacity: 1` |
| 4 | Registration Eligibility | `GET /api/v1/events/{id}/registration-eligibility` | `eligibility_status: "eligible"` |
| 5 | Register for Event | `POST /api/v1/events/{id}/register` | `status: "registered"`, `registration_number` present |
| 6 | My Registration | `GET /api/v1/events/{id}/my-registration` | `status: "registered"`, `join_url` present |
| 7 | My Registrations List | `GET /api/v1/my/registrations` | test registration found in list |
| 8 | Duplicate Registration Guard | `POST /api/v1/events/{id}/register` (2nd) | `HTTP 409`, `detail: "already_registered"` |
| 9 | Capacity Guard | `POST /api/v1/events/{id}/register` on full event | `HTTP 409`, `detail: "event_full"` |
| 10 | Join Link Visibility | `GET /api/v1/events/{id}/my-registration` | `join_url` non-null for virtual+published+registered |
| 11 | Confirmation Email Status | DB query on registrations | `confirmation_email_status` in `("sent","failed")` |
| 12 | Audit Log Check | DB query on event_audit_log | audit row found for `entity_type="registration"` |
| 13 | Public API Leak Check | `GET /api/v1/events/public/{id}` (no auth) | `virtual_url` and `created_by_firebase_uid` absent |

> The diagnostics endpoint creates two temporary events (`DIAG_REG_VIRTUAL_*` and
> `DIAG_REG_CAP_*`) and cancels them at the end. These are safe to ignore in the database.

---

## 4. Week 3 UX Showcase — Step-by-Step

The Developer Diagnostics screen has been extended into a complete Week 3 UX Demonstration Center.
All 16 sections are accessible within a single screen.

### 4.1 Access Path

```
App → Developer Diagnostics (debug mode only)
    → Registration category (tap to expand)
    → Week 3 UX Showcase   ← tap this (listed first in the category)
```

All Registration category items open the same screen (`_RegistrationDiagnosticDetail`).
The UX Showcase entry is listed first as the primary entry point.

### 4.2 Recommended Test Order

Run sections in the order below. Later sections (§10, §11) depend on earlier fetches.

---

### Step 4-A — §0 Run All Validation (backend sanity check)

1. Scroll to **§0 Run All Diagnostics** near the top of the screen.
2. Tap **"Run All Registration Diagnostics"**.
3. Wait ~5–90 seconds (backend creates temporary test events, runs 13 checks, cleans up).

**Expected:** Green PASS dashboard — `13 / 13 PASS`.

If any check fails here, stop and resolve the backend issue before continuing. See [Section 15](#15-troubleshooting).

---

### Step 4-B — §1 Alumni Autofill Preview

1. Scroll to **§1 Alumni Profile Autofill**.
2. Tap **"Fetch → GET /alumni/me"**.

**Expected card:**

```
Name:       Username Alumni
Ref ID:     NITK2026IT001
Batch Year: 2026
Branch:     Information Technology
Email:      Username2026@gmail.com
Phone:      +919876543210
Status:     Active
```

**If you see 403 or empty:** Your token has expired or your Firebase UID has no matching alumni
record. Re-authenticate (§2.2) and verify the alumni_db record (§14.8).

> **This step is required for §11 Snapshot Demo.** Complete §1 before proceeding to §11.

---

### Step 4-C — §2 Eligibility Preview (physical event)

1. In the **Event ID picker**, enter `25`.
2. Tap **"Check Eligibility"**.

**Expected:** Green `eligible` banner.

```
eligibility_status: eligible
message: You are eligible to register.
registered_count: <n>
capacity: 50
```

**If you see `already_registered`:** You have an active registration for event 25.
This is expected if you ran this test before. Continue to §3 which will return `409`.

---

### Step 4-D — §2 Eligibility Preview (virtual event)

1. Change Event ID to `26`.
2. Tap **"Check Eligibility"**.

**Expected:** Green `eligible` banner (same shape, `capacity: 50`).

---

### Step 4-E — §3 Registration Action (physical — no join_url)

1. Keep Event ID as `25`.
2. Tap **"Register (Dev)"**.

**Expected result card:**

```
registration_number: NITKSAA-2026-XXXXXX
status: registered
join_url: null          ← physical event — join link must be absent
event.is_virtual: false
confirmation_email_status: sent   (or "failed" — both are PASS)
```

> If you already registered for event 25: you will see `409 already_registered`.
> This is the correct behavior — the duplicate guard is working.
> To reset: cancel via psql (see §9 DB-07) and retry.

---

### Step 4-F — §3 Registration Action (virtual — join_url present)

1. Change Event ID to `26`.
2. Tap **"Register (Dev)"**.

**Expected result card:**

```
registration_number: NITKSAA-2026-XXXXXX
status: registered
join_url: https://meet.google.com/nitksaa-demo-webinar   ← non-null for virtual
event.is_virtual: true
confirmation_email_status: sent
```

> `join_url` is a **top-level** field. `is_virtual` is inside the nested `event` object.
> This is by design — see §12.4 for the full join_url visibility rule.

> **This step is required for §10 Email Demo and §11 Snapshot Demo.**

---

### Step 4-G — §4 Confirmation Preview

No tap needed — this section auto-populates from §3.

1. Scroll to **§4 Confirmation Preview**.

**Expected for event 26 (virtual):**
- Registration number displayed prominently (monospace)
- Join link card visible with the `meet.google.com` URL
- Email status row: `sent` with green checkmark icon

**Expected for event 25 (physical):**
- Registration number displayed
- Join link section hidden (no card)
- Venue shown instead: `NIT Karnataka, Surathkal`

---

### Step 4-H — §5 My Registration

1. Enter Event ID `26`.
2. Tap **"Fetch My Registration"**.

**Expected card:**
- `registration_number: NITKSAA-2026-XXXXXX`
- `status: registered`
- `registered_at: 2026-06-...`
- `join_url` visible (virtual event)

Repeat with Event ID `25` — join_url card must be absent.

---

### Step 4-I — §6 My Registrations List

1. Tap **"Fetch My Registrations"**.

**Expected:** Scrollable list showing at minimum event 25 and event 26 registrations.

- Event 26 card: join link row visible
- Event 25 card: no join link row
- `total`: 2 or more

---

### Step 4-J — §7 Negative State Gallery

No tap required — this section is fully static.

Scroll through and verify 9 error state cards are visible:

| Card | Colour | Expected Trigger |
|---|---|---|
| Event Full (`event_full`) | Orange / error container | `409 event_full` |
| Registration Closed (`registration_closed`) | Red / error container | `409 registration_closed` |
| Registration Not Open Yet (`not_open_yet`) | Blue / tertiary container | `409 registration_not_open_yet` |
| Already Registered (`already_registered`) | Green / secondary container | `409 already_registered` |
| Alumni Only (`alumni_only`) | Red / error container | `403 alumni_only` |
| Inactive Alumni (`alumni_not_active`) | Red / error container | `403 alumni_not_active` |
| Unauthenticated (401) | Grey / surface variant | `401` |
| Event Not Published (`event_not_published`) | Surface | `409 event_not_published` |
| Confirm Profile Required | Surface | `409 confirm_profile_required` |

---

### Step 4-K — Dev Reference Notes

No tap required — static section with 7 frontend developer rules.

Verify these rules are displayed:

1. Response is **flat** — no nested `registration`, `alumni`, or `confirmation_email` wrappers.
2. `is_virtual` is inside the nested `event` object, not at the top level of `RegistrationResponse`.
3. `join_url` is a **top-level** field.
4. Eligibility status values differ from POST error detail codes — see the two-code table.
5. `confirmation_email_status` is always `"sent"`, `"failed"`, or `"skipped"` — never `null`.
6. Email failure never rolls back a registration.
7. `batch_year` and `branch` may be `null` if not set in alumni_db.

---

### Step 4-L — §8a Join Link Visibility Matrix

No tap required — static section.

Scroll to **§8a Join Link Visibility Matrix** and verify 4 rows:

| Registration Status | Event Type | Event Status | join_url |
|---|---|---|---|
| `registered` | virtual | published | **Visible** (highlighted row) |
| `cancelled` | virtual | published | Hidden |
| `registered` | physical | published | Hidden |
| `registered` | virtual | draft | Hidden |

Only the first row combination produces a non-null `join_url`. This is enforced by
`_resolve_join_url()` in `registration_service.py`.

---

### Step 4-M — §8b Public API Leak Validation

1. Enter Event ID `26` in the picker.
2. Tap **"Check Public Event"**.

> This call is made **without authentication** — it mirrors what an anonymous user or web scraper
> receives from `GET /api/v1/events/public/{id}`.

**Expected: green PASS badge**

```
PASS — No sensitive fields leaked
(virtual_url: not present, join_url: not present, created_by_firebase_uid: not present)
```

**If you see a red FAIL badge:** A sensitive field was found in the public API response.
This is a **security regression** and must be fixed before proceeding.

Repeat with Event ID `25` — same PASS expected.

---

### Step 4-N — §9 Audit Trail Demonstration

1. Make sure §3 Registration has been run (required to produce audit rows).
2. Scroll to **§9 Audit Trail Demonstration**.
3. Tap **"Fetch Audit Log"**.

**Expected:** Latest 8 rows from `event_audit_log`, each showing:

- `event_type`: e.g., `registration.created`, `confirmation_email.sent`, `event.status_changed`
- `entity_type`: `registration` or `event`
- `entity_id`: the registration_id or event_id
- `created_at`: ISO timestamp

Note: `actor_uid` is intentionally hidden in the card UI (PII protection). It is present
in the database but not surfaced here.

---

### Step 4-O — §10 Email Demonstration

No tap required — auto-populated from §3 result.

Scroll to **§10 Email Demonstration**.

**Expected card:**

| Label | Example Value |
|---|---|
| Reg # | `NITKSAA-2026-000005` |
| Sent At | `2026-06-19T09:56:44.851099Z` |
| Status | `sent` (green icon) |

**Status icon colours:**
- `sent` → green `mark_email_read` icon
- `failed` → red `email` icon (registration is still valid — email is non-blocking)
- `skipped` → grey `email` icon (email disabled in this environment)

If no data appears: Run §3 first, then scroll back to §10.

---

### Step 4-P — §11 Snapshot Demonstration

No tap required — auto-populated from §1 (alumni profile) and §3 (registration).

Scroll to **§11 Snapshot Demonstration**.

**Expected side-by-side comparison:**

| Label | Alumni Profile (live) | Registration Snapshot (frozen) |
|---|---|---|
| Full Name | `Username Alumni` | `Username Alumni` |
| Batch Year | `2026` | `2026` |
| Branch | `Information Technology` | `Information Technology` |

Both columns should show identical values immediately after registration.
The snapshot is frozen at registration time — it will not change if the alumni profile changes later.

**If `batch_year` or `branch` shows `—`:** The alumni_db record has a `null` value for that field.
This is expected and handled correctly.

If no data appears: §1 and §3 must both be run first.

---

### Step 4-Q — §12 Database Rules Demonstration

No tap required — fully static.

Scroll to **§12 Database Rules Demonstration** and verify 4 rule cards with green badges:

| Rule | DB Constraint | Verified By |
|---|---|---|
| Unique Registration Number | Service-generated `NITKSAA-{year}-{id:06d}` | §3 result (reg number shown) |
| Partial Unique Registration | `UNIQUE(event_id, firebase_uid) WHERE status='registered'` | Migration 008 |
| Re-registration After Cancellation | Cancelled rows soft-deleted; partial index allows new row | Diagnostic check 8 |
| Registered Count Excludes Cancelled | `COUNT(*) WHERE status='registered'` only | Diagnostic check 9 |

---

### 4.3 UX Showcase PASS/FAIL Summary

| Section | Type | PASS Condition |
|---|---|---|
| §0 Run All Validation | Live | 13/13 PASS |
| §1 Alumni Autofill | Live | Profile card populated with `is_active: true` |
| §2 Eligibility (event 25) | Live | `eligible` banner shown |
| §2 Eligibility (event 26) | Live | `eligible` banner shown |
| §3 Register (event 25) | Live | `status: registered`, `join_url: null` |
| §3 Register (event 26) | Live | `status: registered`, `join_url` non-null |
| §4 Confirmation (event 26) | From §3 | Join link card visible |
| §4 Confirmation (event 25) | From §3 | Join link card hidden, venue shown |
| §5 My Registration | Live | Registration card shown |
| §6 My Registrations List | Live | Both events in scrollable list |
| §7 Negative Gallery | Static | 9 error cards visible |
| Dev Notes | Static | 7 rules displayed |
| §8a Join Link Matrix | Static | 4 rows, row 1 highlighted |
| §8b Public Leak | Live | Green PASS badge — no forbidden fields |
| §9 Audit Trail | Live | Rows from `event_audit_log` displayed |
| §10 Email Demo | From §3 | Email status card shown |
| §11 Snapshot Demo | From §1+§3 | Both columns match |
| §12 DB Rules | Static | 4 rule cards with green badges |

---

## 5. Positive Use Cases (curl)

### UC-01 — Register for Physical Event (Event 25)

**Goal:** Full physical registration completes with `join_url: null`.

```bash
# Step 1 — Check eligibility
curl -s http://localhost:8000/api/v1/events/25/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected: `"eligibility_status": "eligible"`

```bash
# Step 2 — Register
curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Manual verification test"}' | python3 -m json.tool
```

Expected (HTTP 201):

```json
{
  "registration_number": "NITKSAA-2026-XXXXXX",
  "event_id": 25,
  "status": "registered",
  "join_url": null,
  "confirmation_email_status": "sent",
  "event": {
    "event_id": 25,
    "is_virtual": false,
    "location_text": "NIT Karnataka, Surathkal"
  }
}
```

**PASS criteria:**
- HTTP `201`
- `status: "registered"`
- `join_url: null` — physical event must never have a join link
- `event.is_virtual: false` — note: `is_virtual` is inside the nested `event` object
- `registration_number` matches `NITKSAA-YYYY-NNNNNN`
- `confirmation_email_status` is `"sent"` or `"failed"` (never `null`)

---

### UC-02 — Register for Virtual Event (Event 26)

**Goal:** Virtual registration returns a non-null `join_url`.

```bash
# Step 1 — Check eligibility
curl -s http://localhost:8000/api/v1/events/26/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected: `"eligibility_status": "eligible"`

```bash
# Step 2 — Register
curl -s -X POST http://localhost:8000/api/v1/events/26/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Virtual event test"}' | python3 -m json.tool
```

Expected (HTTP 201):

```json
{
  "registration_number": "NITKSAA-2026-XXXXXX",
  "event_id": 26,
  "status": "registered",
  "join_url": "https://meet.google.com/nitksaa-demo-webinar",
  "confirmation_email_status": "sent",
  "event": {
    "event_id": 26,
    "is_virtual": true,
    "location_text": null
  }
}
```

**PASS criteria:**
- `event.is_virtual: true` — inside the nested `event` object, not at top level
- `join_url` is a non-empty string starting with `https://`
- HTTP `201`

```bash
# Step 3 — Verify join_url persists via my-registration
curl -s http://localhost:8000/api/v1/events/26/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected: same `join_url` as in the registration response.

> **Security invariant:** `virtual_url` must never appear in any API response.
> `join_url` only appears when: `status="registered"` AND `is_virtual=true` AND event `status="published"`.

---

### UC-03 — My Registrations List

**Goal:** Both events appear in the list with correct join_url state.

```bash
curl -s http://localhost:8000/api/v1/my/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected:

```json
{
  "total": 2,
  "registrations": [
    { "event_id": 26, "join_url": "https://...", "status": "registered" },
    { "event_id": 25, "join_url": null, "status": "registered" }
  ]
}
```

**PASS criteria:**
- Both event 25 and event 26 registrations present
- Event 26: `join_url` populated
- Event 25: `join_url: null`
- Items ordered by `registered_at DESC` (most recent first)

---

### UC-11 — Alumni Profile (GET /alumni/me)

```bash
curl -s http://localhost:8000/api/v1/alumni/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected (flat response — no wrapper object):

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

**PASS criteria:**
- `is_active: true`
- Field is `ref_id` (not `alumni_id`)
- Field is `batch_year` (not `graduationyear`)
- `registrationstatus` does not appear — alumni status is computed into `is_active`
- Response is flat — no nested wrapper

---

### UC-13 — Public Events List (No Auth)

```bash
curl -s "http://localhost:8000/api/v1/events/public?page=1&per_page=20" \
  | python3 -m json.tool
```

**PASS criteria:**
- Response contains `total` and `events` array
- No event object contains `virtual_url`
- No event object contains `created_by_firebase_uid`
- All returned events have `status: "published"`

---

### UC-14 — Public Event Detail (No Auth)

```bash
curl -s http://localhost:8000/api/v1/events/public/26 | python3 -m json.tool
```

**PASS criteria:**
- `virtual_url` absent from response
- `created_by_firebase_uid` absent
- `sessions` is a list (may be empty)
- HTTP `200`

---

## 6. Negative Use Cases (curl)

### NC-01 — Duplicate Registration (already_registered)

**Goal:** Second registration attempt returns `409 already_registered`.

Pre-condition: already registered for event 25 (UC-01).

```bash
curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Duplicate attempt"}' | python3 -m json.tool
```

Expected: `{"detail": "already_registered"}`

**PASS criteria:** HTTP `409`, `detail: "already_registered"`

Eligibility equivalent (GET):

```bash
curl -s http://localhost:8000/api/v1/events/25/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
# Expected: {"eligibility_status": "already_registered", ...}
```

---

### NC-02 — Event Full (event_full)

**Goal:** Registration on full event (event 34, capacity=1) returns `409 event_full`.

```bash
curl -s -X POST http://localhost:8000/api/v1/events/34/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected: `{"detail": "event_full"}`

**PASS criteria:** HTTP `409`, `detail: "event_full"`

> **Two-code note:** POST error is `event_full`; GET eligibility returns `full` — not the same string.

```bash
# Eligibility equivalent
curl -s http://localhost:8000/api/v1/events/34/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
# Expected: {"eligibility_status": "full", ...}    ← "full" not "event_full"
```

---

### NC-03 — Registration Closed (registration_closed)

**Goal:** Registration on event 35 (window past) returns `409 registration_closed`.

```bash
curl -s -X POST http://localhost:8000/api/v1/events/35/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected: `{"detail": "registration_closed"}`

```bash
# Eligibility equivalent
curl -s http://localhost:8000/api/v1/events/35/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
# Expected: {"eligibility_status": "closed", ...}    ← "closed" not "registration_closed"
```

**PASS criteria:** POST `409` / `registration_closed`. GET eligibility `closed`.

---

### NC-04 — Registration Not Open Yet (registration_not_open_yet)

**Goal:** Registration on event 36 (window future) returns `409 registration_not_open_yet`.

```bash
curl -s -X POST http://localhost:8000/api/v1/events/36/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected: `{"detail": "registration_not_open_yet"}`

```bash
# Eligibility equivalent
curl -s http://localhost:8000/api/v1/events/36/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
# Expected: {"eligibility_status": "not_open_yet", ...}
```

---

### NC-05 — Non-Alumni User (alumni_only)

**Goal:** Non-alumni user gets `403 alumni_only`.

```bash
NON_ALUMNI_TOKEN="token-for-non-alumni-user"

curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${NON_ALUMNI_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected: `{"detail": "alumni_only"}`

Eligibility for non-alumni:

```json
{
  "eligibility_status": "ineligible",
  "message": "Only alumni can register for this event."
}
```

**PASS criteria:** POST `403` / `alumni_only`. GET eligibility `ineligible` + message containing "alumni".

> **Note:** `alumni_required` is not a valid code. The correct code is `alumni_only`.

---

### NC-06 — Inactive Alumni (alumni_not_active)

**Goal:** Alumni with `registrationstatus` outside `{'Active', 'Self-Verified'}` gets `403 alumni_not_active`.

```bash
INACTIVE_ALUMNI_TOKEN="token-for-inactive-alumni"

curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${INACTIVE_ALUMNI_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected: `{"detail": "alumni_not_active"}`

Eligibility:

```json
{
  "eligibility_status": "ineligible",
  "message": "Alumni account is not active."
}
```

**PASS criteria:** POST `403` / `alumni_not_active`. GET eligibility `ineligible` with different message from NC-05.

---

### NC-07 — Unauthenticated Access

**Goal:** Authenticated endpoints reject no-token requests with `401`.

```bash
# Eligibility — no auth
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/api/v1/events/25/registration-eligibility
# Expected: 401

# POST register — no auth
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Content-Type: application/json" \
  -d '{}'
# Expected: 401

# My registrations — no auth
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/api/v1/my/registrations
# Expected: 401

# GET /alumni/me — no auth
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/api/v1/alumni/me
# Expected: 401
```

**PASS criteria:** All four return HTTP `401`.

---

### NC-08 — Public API Leak (virtual_url must not appear)

**Goal:** `virtual_url` is never present in public API responses.

```bash
curl -s http://localhost:8000/api/v1/events/public/26 | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('virtual_url present:', 'virtual_url' in d)
print('join_url present:', 'join_url' in d)
print('created_by_firebase_uid present:', 'created_by_firebase_uid' in d)
"
```

Expected output:

```
virtual_url present: False
join_url present: False
created_by_firebase_uid present: False
```

**PASS criteria:** All three fields absent from public response. HTTP `200`.

---

### NC-09 — Dev Diagnostics Unavailable in Production

**Goal:** Dev diagnostics endpoint returns `404` when `APP_ENV != development`.

> This test requires temporarily changing `APP_ENV=production` in `backend/.env` and restarting
> the backend. Only run in your personal dev environment — never on staging.

```bash
# With APP_ENV=production, restart backend, then:
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/api/v1/dev/diagnostics/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
# Expected: 404
```

Restore `APP_ENV=development` and restart before continuing.

---

## 7. Security Tests

> **Important:** Tests in this section require direct database manipulation. Only run on your
> local dev database. Never apply these SQL commands in staging or production without explicit
> approval. Always restore the database after each test.

### SEC-07 — Cancelled Registration Hides join_url

**Goal:** `join_url` becomes `null` after a registration is cancelled.

**Rule:**

```
join_url is non-null only when ALL of:
  registration.status = 'registered'
  event.is_virtual = true
  event.status = 'published'
```

**Pre-condition:** Complete UC-02 first (register for event 26).

**Step 1 — Confirm join_url is present before cancellation:**

```bash
curl -s http://localhost:8000/api/v1/events/26/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('status:', d.get('status'))
print('join_url:', d.get('join_url'))
"
```

Expected:

```
status: registered
join_url: https://meet.google.com/...   ← non-null
```

**Step 2 — Get registration_id:**

```sql
-- In psql -d events_db
SELECT registration_id, status
FROM registrations
WHERE event_id = 26
  AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
  AND status = 'registered';
```

Note the `registration_id`.

**Step 3 — Cancel (local dev only):**

```sql
UPDATE registrations
SET status = 'cancelled',
    cancelled_at = NOW(),
    updated_at = NOW()
WHERE registration_id = <registration_id>;
```

**Step 4 — Confirm join_url is now null:**

```bash
curl -s http://localhost:8000/api/v1/events/26/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('status:', d.get('status'))
print('join_url:', d.get('join_url'))
"
```

Expected:

```
status: cancelled
join_url: None
```

**Step 5 — Restore (required for subsequent tests):**

```sql
UPDATE registrations
SET status = 'registered',
    cancelled_at = NULL,
    updated_at = NOW()
WHERE registration_id = <registration_id>;
```

**PASS criteria:**
- After cancellation: `join_url` is `null`, `status` is `"cancelled"`, HTTP `200`
- After restore: `join_url` is non-null again

**FAIL if:** `join_url` is non-null when `status = 'cancelled'`.

---

### SEC-08 — Cancelled Registration Not Counted in registered_count

**Goal:** Cancelled registrations do not consume capacity.

**Pre-condition:** At least one active registration for event 25.

**Step 1 — Record current registered_count:**

```bash
curl -s http://localhost:8000/api/v1/events/25/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('registered_count:', d.get('registered_count'))
print('capacity:', d.get('capacity'))
"
```

Note `registered_count` as **N**.

**Step 2 — Verify DB count matches:**

```sql
SELECT COUNT(*) AS registered_count
FROM registrations
WHERE event_id = 25 AND status = 'registered';
```

Expected: equals **N**.

**Step 3 — Cancel one registration:**

```sql
SELECT registration_id FROM registrations
WHERE event_id = 25
  AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
  AND status = 'registered'
LIMIT 1;

-- Cancel it
UPDATE registrations
SET status = 'cancelled',
    cancelled_at = NOW(),
    updated_at = NOW()
WHERE registration_id = <registration_id>;
```

**Step 4 — Recheck registered_count:**

```bash
curl -s http://localhost:8000/api/v1/events/25/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('registered_count:', d.get('registered_count'))
"
```

Expected: `registered_count` = **N − 1**.

**Step 5 — Verify DB breakdown:**

```sql
SELECT
  COUNT(*) FILTER (WHERE status = 'registered') AS active_count,
  COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled_count
FROM registrations
WHERE event_id = 25;
```

Expected: `active_count` = **N − 1**, `cancelled_count` ≥ 1. Cancelled row is retained.

**Step 6 — Restore:**

```sql
UPDATE registrations
SET status = 'registered',
    cancelled_at = NULL,
    updated_at = NOW()
WHERE registration_id = <registration_id>;
```

**PASS criteria:**
- API `registered_count` decreases by 1 after cancellation
- Cancelled row is retained (not deleted)
- `registered_count` returns to **N** after restore

**FAIL if:** Cancelled row is counted or hard-deleted.

---

## 8. API Integrity Tests

### API-01 — Registration Number Uniqueness

**Goal:** Each registration has a unique number in the format `NITKSAA-YYYY-NNNNNN`.

**Step 1 — Check for duplicates:**

```sql
-- In psql -d events_db
SELECT registration_number, COUNT(*)
FROM registrations
WHERE registration_number IS NOT NULL
GROUP BY registration_number
HAVING COUNT(*) > 1;
```

Expected: **0 rows**.

**Step 2 — Verify format:**

```sql
SELECT registration_number
FROM registrations
WHERE registration_number NOT LIKE 'NITKSAA-____-______'
  AND registration_number IS NOT NULL;
```

Expected: **0 rows**.

**Step 3 — Verify year component:**

```sql
SELECT registration_number,
       split_part(registration_number, '-', 2) AS year_part
FROM registrations
WHERE registration_number IS NOT NULL;
```

Expected: `year_part = '2026'` for all rows.

**Step 4 — Verify sequence equals registration_id:**

```sql
SELECT
  registration_id,
  registration_number,
  CAST(split_part(registration_number, '-', 3) AS INTEGER) AS sequence_part
FROM registrations
WHERE registration_number IS NOT NULL
ORDER BY registration_id;
```

Expected: `sequence_part = registration_id` for every row.

**PASS criteria:** Zero duplicates, all numbers match the pattern, sequence equals `registration_id`.

---

### API-02 — Snapshot Frozen at Registration Time

**Goal:** Updating alumni_db does not change existing registration snapshots.

**Step 1 — Record current snapshot values:**

```bash
curl -s http://localhost:8000/api/v1/events/25/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in ['fullname_snapshot','email_snapshot','phone_snapshot','batch_year_snapshot','branch_snapshot']:
    print(f'{k}: {d.get(k)}')
"
```

Note all five values as your **baseline**.

**Step 2 — Note original alumni_db values before modifying:**

```bash
psql -d alumni_db -c "
SELECT alumni_id, fullname, phone, graduationyear, branch
FROM alumni
WHERE alumni_id = 'NITK2026IT001';
"
```

**Step 3 — Temporarily update the alumni profile:**

```sql
-- In psql -d alumni_db
UPDATE alumni
SET fullname = 'MODIFIED Name',
    phone = '+910000000000',
    graduationyear = 1999,
    branch = 'Modified Branch'
WHERE alumni_id = 'NITK2026IT001';
```

**Step 4 — Confirm GET /alumni/me reflects the change:**

```bash
curl -s http://localhost:8000/api/v1/alumni/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('fullname (live):', d.get('fullname'))
print('batch_year (live):', d.get('batch_year'))
print('branch (live):', d.get('branch'))
"
```

Expected: `fullname = "MODIFIED Name"`, `batch_year = 1999`.

**Step 5 — Confirm registration snapshot is unchanged:**

```bash
curl -s http://localhost:8000/api/v1/events/25/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in ['fullname_snapshot','batch_year_snapshot','branch_snapshot']:
    print(f'{k}: {d.get(k)}')
"
```

Expected: identical to the **baseline** from Step 1.

**Step 6 — Restore alumni_db (REQUIRED before continuing):**

```sql
UPDATE alumni
SET fullname = 'Username Alumni',
    phone = '+919876543210',
    graduationyear = 2026,
    branch = 'Information Technology'
WHERE alumni_id = 'NITK2026IT001';
```

Verify:

```sql
SELECT fullname, phone, graduationyear, branch
FROM alumni WHERE alumni_id = 'NITK2026IT001';
```

> **Warning:** Always run Step 6 before continuing. Failure to restore will cause NC-06, UC-11,
> and diagnostic checks to fail.

**PASS criteria:**
- Snapshot fields unchanged after alumni_db update
- Restore confirms original values in both profile and snapshot

---

## 9. Database Constraint Tests

### DB-07 — Partial Unique Index Allows Re-Registration After Cancellation

**Goal:** Migration 008 replaced a hard `UNIQUE(event_id, firebase_uid)` constraint with a partial
unique index — so cancelled rows do not block re-registration.

**Background:** A hard unique index would prevent re-registration even after cancellation. The
partial index `UNIQUE(event_id, firebase_uid) WHERE status='registered'` makes cancelled rows
invisible to the constraint.

**Step 1 — Confirm one active registration for event 25:**

```sql
SELECT registration_id, status, registration_number
FROM registrations
WHERE event_id = 25
  AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3';
```

Expected: one row with `status = 'registered'`.

**Step 2 — Attempt a duplicate (must be blocked):**

```bash
curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected: HTTP `409`, `"detail": "already_registered"`.

**Step 3 — Cancel the existing registration:**

```sql
UPDATE registrations
SET status = 'cancelled',
    cancelled_at = NOW(),
    updated_at = NOW()
WHERE event_id = 25
  AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
  AND status = 'registered';
```

**Step 4 — Re-register for the same event:**

```bash
curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected: HTTP `201`, new `registration_number` different from the original.

**Step 5 — Verify two rows coexist:**

```sql
SELECT registration_id, status, registration_number, registered_at, cancelled_at
FROM registrations
WHERE event_id = 25
  AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
ORDER BY registration_id;
```

Expected: two rows — one `cancelled`, one `registered` — with different `registration_number` values.

**Step 6 — Verify the partial index definition (optional):**

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'registrations'
  AND indexdef ILIKE '%where%registered%';
```

Expected: an index with a `WHERE (status = 'registered')` predicate.

**PASS criteria:**
- Step 2: `409 already_registered` — duplicate correctly blocked
- Step 4: `201` — re-registration succeeds after cancellation
- Step 5: two rows coexist, both with distinct `registration_number`

**FAIL if:** Step 4 returns `409 already_registered` — migration 008 was not applied.

---

## 10. Test Event Reference

### 10.1 Known Test Events

| Event ID | Type | Scenario | State |
|---|---|---|---|
| 25 | Physical | Open registration — positive test | `status=published`, registration open |
| 26 | Virtual | Join URL test | `status=published`, registration open, `virtual_url` set |
| 34 | Physical | Full event guard | `status=published`, `capacity=1`, 1 registration exists |
| 35 | Physical | Registration closed | `status=published`, `registration_closes_at` in past |
| 36 | Physical | Registration not yet open | `status=published`, `registration_opens_at` in future |

### 10.2 Known Test Registrations

| Registration Number | Event ID | Notes |
|---|---|---|
| NITKSAA-2026-000004 | 25 | Physical — `join_url: null` |
| NITKSAA-2026-000005 | 26 | Virtual — `join_url` present |

> If these events do not exist in your database, use §10.3 to recreate them.

### 10.3 Recreate Test Events

Connect to events_db:

```bash
psql -d events_db
```

**Event 25 — Physical, open registration:**

```sql
INSERT INTO events (
  title, status, is_virtual, location_text, capacity,
  registration_opens_at, registration_closes_at,
  starts_at, ends_at, timezone, created_by_firebase_uid
) VALUES (
  'Test Physical Event (Week 3)',
  'published', false, 'NIT Karnataka, Surathkal', 50,
  NOW() - INTERVAL '7 days',
  NOW() + INTERVAL '7 days',
  NOW() + INTERVAL '30 days',
  NOW() + INTERVAL '30 days' + INTERVAL '2 hours',
  'Asia/Kolkata', 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
) RETURNING event_id;
```

**Event 26 — Virtual, open registration:**

```sql
INSERT INTO events (
  title, status, is_virtual, virtual_url, capacity,
  registration_opens_at, registration_closes_at,
  starts_at, ends_at, timezone, created_by_firebase_uid
) VALUES (
  'Test Virtual Event (Week 3)',
  'published', true, 'https://meet.example.com/test-event-26', 50,
  NOW() - INTERVAL '7 days',
  NOW() + INTERVAL '7 days',
  NOW() + INTERVAL '30 days',
  NOW() + INTERVAL '30 days' + INTERVAL '2 hours',
  'Asia/Kolkata', 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
) RETURNING event_id;
```

**Event 34 — Capacity guard (capacity=1):**

```sql
INSERT INTO events (
  title, status, is_virtual, location_text, capacity,
  registration_opens_at, registration_closes_at,
  starts_at, ends_at, timezone, created_by_firebase_uid
) VALUES (
  'Test Capacity Guard Event (Week 3)',
  'published', false, 'NIT Karnataka, Surathkal', 1,
  NOW() - INTERVAL '7 days',
  NOW() + INTERVAL '7 days',
  NOW() + INTERVAL '30 days',
  NOW() + INTERVAL '30 days' + INTERVAL '2 hours',
  'Asia/Kolkata', 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
) RETURNING event_id;
-- Note the returned event_id, then insert the filler registration:
INSERT INTO registrations (
  event_id, firebase_uid, status, email, fullname_snapshot,
  batch_year_snapshot, branch_snapshot, registered_at, confirmation_email_status
) VALUES (
  <event_id_from_above>, 'fxvOA6JInMM2OPKb3vuSV7qJwtI3',
  'registered', 'Username2026@gmail.com', 'Test User',
  2026, 'IT', NOW(), 'skipped'
);
```

**Event 35 — Registration closed:**

```sql
INSERT INTO events (
  title, status, is_virtual, location_text, capacity,
  registration_opens_at, registration_closes_at,
  starts_at, ends_at, timezone, created_by_firebase_uid
) VALUES (
  'Test Closed Registration Event (Week 3)',
  'published', false, 'NIT Karnataka, Surathkal', 50,
  NOW() - INTERVAL '14 days',
  NOW() - INTERVAL '1 day',
  NOW() + INTERVAL '30 days',
  NOW() + INTERVAL '30 days' + INTERVAL '2 hours',
  'Asia/Kolkata', 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
) RETURNING event_id;
```

**Event 36 — Registration not open yet:**

```sql
INSERT INTO events (
  title, status, is_virtual, location_text, capacity,
  registration_opens_at, registration_closes_at,
  starts_at, ends_at, timezone, created_by_firebase_uid
) VALUES (
  'Test Future Registration Event (Week 3)',
  'published', false, 'NIT Karnataka, Surathkal', 50,
  NOW() + INTERVAL '7 days',
  NOW() + INTERVAL '14 days',
  NOW() + INTERVAL '30 days',
  NOW() + INTERVAL '30 days' + INTERVAL '2 hours',
  'Asia/Kolkata', 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
) RETURNING event_id;
```

---

## 11. Expected API Response Shapes (v2)

> These are the **actual shapes** returned by the running backend. All v1 field names (e.g.
> `alumni_id`, `graduationyear`, `registrationstatus`) do not appear in API responses.

### 11.1 GET /api/v1/alumni/me — AlumniProfileResponse

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

Nullable fields: `phone`, `batch_year`, `branch` (all may be `null`).

### 11.2 GET /api/v1/events/{id}/registration-eligibility — RegistrationEligibilityResponse

Always HTTP 200 — never 4xx for eligibility reasons.

```json
{
  "event_id": 25,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "eligibility_status": "eligible",
  "message": "You are eligible to register.",
  "registered_count": 3,
  "capacity": 50
}
```

`registered_count` and `capacity` are `null` for non-`eligible` states.

### 11.3 POST /api/v1/events/{id}/register — RegistrationResponse (HTTP 201)

**Physical event (`join_url: null`):**

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
  "attendee_note": null,
  "registered_at": "2026-06-19T09:55:41.007308Z",
  "cancelled_at": null,
  "confirmation_email_status": "sent",
  "confirmation_email_sent_at": "2026-06-19T09:55:41.020087Z",
  "join_url": null,
  "event": {
    "event_id": 25,
    "title": "Breakfast Club Demo",
    "start_datetime": "2026-08-02T00:55:12.881266Z",
    "end_datetime": "2026-08-02T02:55:12.881266Z",
    "timezone": "Asia/Kolkata",
    "is_virtual": false,
    "location_text": "NIT Karnataka, Surathkal",
    "location_maps_url": null
  },
  "updated_at": null
}
```

**Virtual event (`join_url` non-null):** Same shape with `join_url: "https://meet.google.com/..."`,
`event.is_virtual: true`, `event.location_text: null`.

**Key field notes:**

| Field | Location | Note |
|---|---|---|
| `join_url` | Top-level | Non-null only for registered+virtual+published |
| `event.is_virtual` | Inside `event` object | NOT at top level of registration response |
| `registration_number` | Top-level | Format: `NITKSAA-{year}-{registration_id:06d}` |
| `confirmation_email_status` | Top-level | `"sent"`, `"failed"`, or `"skipped"` — never `null` |

### 11.4 POST /api/v1/events/{id}/register — Error Responses

| HTTP | `detail` | Cause |
|---|---|---|
| 403 | `alumni_only` | `user_type != "alumni"` or no `ref_id` |
| 403 | `alumni_not_found` | `ref_id` not in `alumni_db` |
| 403 | `alumni_not_active` | `registrationstatus` not Active/Self-Verified |
| 404 | `event_not_found` | `event_id` does not exist |
| 409 | `event_not_published` | event `status != "published"` |
| 409 | `registration_not_open_yet` | before `registration_opens_at` |
| 409 | `registration_closed` | after `registration_closes_at` |
| 409 | `already_registered` | active registration already exists |
| 409 | `event_full` | `COUNT(status='registered') >= capacity` |

### 11.5 GET /api/v1/my/registrations — MyRegistrationsListResponse

```json
{
  "registrations": [
    { "<full RegistrationResponse>" },
    { "<full RegistrationResponse>" }
  ],
  "total": 2
}
```

Items ordered by `registered_at DESC`. Each item is a full `RegistrationResponse` (§11.3 shape).

---

## 12. Expected UI States (v2)

### 12.1 Eligibility Status Values

> These are the **actual v2 values**. The old v1 values (`event_full`, `registration_closed`,
> `registration_not_open_yet`, `can_register`, `alumni_required`) do not exist in the backend.

| `eligibility_status` | Condition | Colour | Icon | CTA |
|---|---|---|---|---|
| `eligible` | Can register | `primaryContainer` | `how_to_reg_outlined` | "Register" |
| `already_registered` | Active registration exists | `primaryContainer` | `check_circle_outline` | "Already Registered" |
| `full` | `registered_count >= capacity` | `errorContainer` | `do_not_disturb_outlined` | "Event Full" |
| `closed` | Past `registration_closes_at` | `errorContainer` | `lock_clock_outlined` | "Registration Closed" |
| `not_open_yet` | Before `registration_opens_at` | `tertiaryContainer` | `hourglass_top_outlined` | "Not Open Yet" |
| `ineligible` | Non-alumni, inactive, not published | `surface` | `info_outline` | (show `message`) |

### 12.2 POST Register Error Detail Codes

| HTTP | `detail` | Flutter handling |
|---|---|---|
| 403 | `alumni_only` | "Alumni accounts only" |
| 403 | `alumni_not_found` | "Alumni profile not found" |
| 403 | `alumni_not_active` | "Alumni account is not active" |
| 404 | `event_not_found` | "Event not found" |
| 409 | `event_not_published` | Show eligibility banner |
| 409 | `registration_not_open_yet` | Show eligibility banner |
| 409 | `registration_closed` | Show eligibility banner |
| 409 | `already_registered` | Show eligibility banner |
| 409 | `event_full` | Show eligibility banner |

### 12.3 Two-Code Cross-Reference

> **Rule:** Switch on `eligibility_status` for GET responses. Switch on `detail` for POST errors.
> Never mix the two code sets.

| UI State | GET `eligibility_status` | POST `detail` |
|---|---|---|
| Event full | `full` | `event_full` |
| Registration closed | `closed` | `registration_closed` |
| Not open yet | `not_open_yet` | `registration_not_open_yet` |
| Already registered | `already_registered` | `already_registered` |
| Non-alumni | `ineligible` (msg: "Only alumni…") | `alumni_only` |
| Inactive alumni | `ineligible` (msg: "Alumni account is not active.") | `alumni_not_active` |
| Not published | `ineligible` (msg: "Event is not open…") | `event_not_published` |

### 12.4 join_url Visibility Rule

`join_url` is non-null **only when all three conditions hold:**

| Condition | Value Required |
|---|---|
| `registration.status` | `"registered"` (not `"cancelled"`) |
| `event.is_virtual` | `true` (physical events always return `null`) |
| `event.status` | `"published"` (draft/cancelled return `null`) |

---

## 13. Backend API Curl Reference

> All authenticated endpoints require `Authorization: Bearer ${ACCESS_TOKEN}`.
> Set `ACCESS_TOKEN` as described in §2.2.

### 13.1 Authentication

```bash
# Firebase login
curl -s -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email":"Username2026@gmail.com","password":"Password2026","returnSecureToken":true}'

# Backend token exchange
curl -s -X POST http://localhost:8000/api/v1/auth/firebase \
  -H "Content-Type: application/json" \
  -d '{"token":"<firebase_id_token>"}'

# Verify current user
curl -s http://localhost:8000/api/v1/auth/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 13.2 Public Endpoints (No Auth)

```bash
# List published events
curl -s "http://localhost:8000/api/v1/events/public?page=1&per_page=20"

# Public event detail — event 26 (virtual)
curl -s http://localhost:8000/api/v1/events/public/26

# Public event detail — event 25 (physical)
curl -s http://localhost:8000/api/v1/events/public/25
```

### 13.3 Alumni Profile

```bash
curl -s http://localhost:8000/api/v1/alumni/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 13.4 Registration Eligibility

```bash
# Event 25 (physical, open)
curl -s http://localhost:8000/api/v1/events/25/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Event 26 (virtual, open)
curl -s http://localhost:8000/api/v1/events/26/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Event 34 (full — capacity=1)
curl -s http://localhost:8000/api/v1/events/34/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Event 35 (closed)
curl -s http://localhost:8000/api/v1/events/35/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Event 36 (not open yet)
curl -s http://localhost:8000/api/v1/events/36/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 13.5 Register for Event

```bash
# Event 25 (physical)
curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Manual test"}'

# Event 26 (virtual — will return join_url)
curl -s -X POST http://localhost:8000/api/v1/events/26/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 13.6 My Registration (single event)

```bash
curl -s http://localhost:8000/api/v1/events/25/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

curl -s http://localhost:8000/api/v1/events/26/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 13.7 My Registrations List

```bash
curl -s http://localhost:8000/api/v1/my/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 13.8 Developer Diagnostics (dev only)

```bash
# 13-check registration flow
curl -s http://localhost:8000/api/v1/dev/diagnostics/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool

# Auth check
curl -s http://localhost:8000/api/v1/dev/diagnostics/auth/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# DB tables list
curl -s http://localhost:8000/api/v1/dev/diagnostics/db/tables \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Audit log table
curl -s http://localhost:8000/api/v1/dev/diagnostics/db/event_audit_log \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool

# Registrations table
curl -s http://localhost:8000/api/v1/dev/diagnostics/db/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

---

## 14. Database Verification Queries

Connect to databases:

```bash
psql -d events_db    # registration and event data
psql -d alumni_db    # alumni profiles
```

### 14.1 All Registrations for Test User

```sql
SELECT
  r.registration_id,
  r.registration_number,
  r.event_id,
  e.title,
  r.status,
  r.confirmation_email_status,
  r.join_url IS NOT NULL AS has_join_url,
  r.registered_at
FROM registrations r
JOIN events e ON e.event_id = r.event_id
WHERE r.firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
ORDER BY r.registered_at DESC;
```

### 14.2 Registration Numbers Compliance

```sql
-- Check for duplicates
SELECT registration_number, COUNT(*)
FROM registrations
WHERE registration_number IS NOT NULL
GROUP BY registration_number
HAVING COUNT(*) > 1;

-- Verify format
SELECT registration_number
FROM registrations
WHERE registration_number NOT LIKE 'NITKSAA-____-______'
  AND registration_number IS NOT NULL;
```

Expected: 0 rows for both queries.

### 14.3 Email Status (never null after registration)

```sql
SELECT
  registration_id,
  registration_number,
  confirmation_email_status,
  confirmation_email_sent_at
FROM registrations
WHERE firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
ORDER BY registered_at DESC;
```

Expected: `confirmation_email_status` is `"sent"`, `"failed"`, or `"skipped"` — never `null`.

### 14.4 Audit Log for Registrations

```sql
SELECT
  log_id,
  event_type,
  entity_type,
  entity_id,
  actor_uid,
  created_at
FROM event_audit_log
WHERE entity_type = 'registration'
ORDER BY created_at DESC
LIMIT 10;
```

Expected: rows with `event_type` like `registration.created`, `confirmation_email.sent`.

### 14.5 Test Event Configuration

```sql
SELECT
  event_id,
  title,
  status,
  is_virtual,
  capacity,
  registration_opens_at,
  registration_closes_at,
  starts_at
FROM events
WHERE event_id IN (25, 26, 34, 35, 36)
ORDER BY event_id;
```

### 14.6 Registered Count vs Capacity (Event 34)

```sql
SELECT
  e.event_id,
  e.capacity,
  COUNT(r.registration_id) FILTER (WHERE r.status = 'registered') AS registered_count
FROM events e
LEFT JOIN registrations r ON r.event_id = e.event_id
WHERE e.event_id = 34
GROUP BY e.event_id, e.capacity;
```

Expected: `registered_count >= capacity` (event is full).

### 14.7 join_url Security (virtual_url stored in DB, not in public API)

```sql
SELECT
  event_id,
  is_virtual,
  virtual_url IS NOT NULL AS has_virtual_url,
  status
FROM events
WHERE event_id = 26;
```

Expected: `has_virtual_url = true`. This proves the URL is stored server-side only.
The public API must never return this value — verified by NC-08.

### 14.8 Alumni Record in alumni_db

```bash
psql -d alumni_db
```

```sql
SELECT
  alumni_id,
  fullname,
  email,
  graduationyear,
  branch,
  registrationstatus
FROM alumni
WHERE alumni_id = 'NITK2026IT001';
```

Expected: `registrationstatus = 'Active'` or `'Self-Verified'`.

### 14.9 Snapshot Fields in Registrations

```sql
SELECT
  registration_id,
  registration_number,
  fullname_snapshot,
  email_snapshot,
  phone_snapshot,
  batch_year_snapshot,
  branch_snapshot
FROM registrations
WHERE firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
ORDER BY registration_id;
```

### 14.10 Partial Unique Index Verification

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'registrations'
  AND indexdef ILIKE '%where%registered%';
```

Expected: an index with predicate `WHERE (status = 'registered')`.

---

## 15. Troubleshooting

### T-01 — user_type is "other" instead of "alumni"

**Symptom:** `POST /auth/firebase` returns `user_type: "other"`, `ref_id: null`.

**Cause:** `ALUMNI_DB_URL` is not set or `alumni_db` has no record for `Username2026@gmail.com`.

**Fix:**
1. `grep ALUMNI_DB_URL backend/.env`
2. Restart backend after setting it.
3. `psql -d alumni_db -c "SELECT * FROM alumni WHERE email = 'Username2026@gmail.com'"`
4. If no record: follow `docs/GETTING_STARTED_WEEK3.md` to set up alumni_db.

---

### T-02 — Dev diagnostics returns 404

**Symptom:** `GET /api/v1/dev/diagnostics/registrations` returns HTTP 404.

**Cause:** `APP_ENV` is not `development`.

**Fix:** Set `APP_ENV=development` in `backend/.env` and restart.

---

### T-03 — All diagnostics fail with "skipped: user is not alumni"

**Symptom:** Checks 2–13 all show `"skipped: user is not alumni or has no ref_id"`.

**Cause:** Same as T-01.

**Fix:** Resolve T-01 first.

---

### T-04 — join_url is null for virtual event

**Symptom:** `GET /events/26/my-registration` returns `join_url: null`.

**Cause:** One of the three conditions for `_resolve_join_url()` is not met.

**Fix:**

```sql
SELECT event_id, status, is_virtual FROM events WHERE event_id = 26;
SELECT event_id, status FROM registrations
WHERE event_id = 26 AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3';
```

Correct whichever condition fails: event must be `published`, `is_virtual = true`; registration must be `registered`.

---

### T-05 — eligibility returns "ineligible" when expecting "eligible"

**Symptom:** GET eligibility for event 25/26 returns `eligibility_status: "ineligible"`.

**Check each cause in order:**
1. `user_type != "alumni"` → fix T-01
2. `ref_id` is null → fix T-01
3. Alumni not in alumni_db → check §14.8
4. Alumni `registrationstatus` not Active/Self-Verified → update alumni_db record
5. Event not published → `SELECT status FROM events WHERE event_id = 25`

---

### T-06 — Event 34 not triggering event_full

**Symptom:** POST to event 34 returns `201` instead of `409 event_full`.

**Cause:** The filler registration for event 34 is missing.

**Fix:**

```sql
SELECT COUNT(*) FROM registrations WHERE event_id = 34 AND status = 'registered';
```

If 0: insert a filler registration per §10.3.

---

### T-07 — Backend returns 500 on registration

**Symptom:** POST /register returns HTTP 500.

**Causes:**
- `events_db` connection down → check `EVENTS_DB_URL`
- `alumni_db` connection down → check `ALUMNI_DB_URL`
- Backend log shows exception → restart with `--log-level debug`

---

### T-08 — Flutter screen shows "Not logged in"

**Symptom:** Developer Diagnostics header shows "Not logged in".

**Cause:** `--dart-define` flags not passed to `flutter run`.

**Fix:**

```bash
flutter run -d chrome \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

---

### T-09 — Audit log rows missing after registration

**Symptom:** §9 audit trail shows empty or diagnostic check 12 fails.

**Cause:** `audit_service.emit()` failed silently (wrapped in try/except).

**Fix:** Check backend logs for `WARNING` from audit service. The registration itself is valid. Run §3 again to generate a new audit row.

---

### T-10 — confirmation_email_status is "failed"

**Meaning:** Email delivery failed. The **registration is still valid** — email never blocks registration.

**For manual verification:** `"failed"` is an acceptable PASS state. The diagnostics check accepts both `"sent"` and `"failed"`.

**To fix email:** Check SMTP settings in `backend/.env`.

---

### T-11 — §11 Snapshot Demo shows no data

**Symptom:** §11 Snapshot Demonstration shows placeholder text instead of comparison.

**Cause:** §1 (alumni autofill) or §3 (registration) has not been run yet.

**Fix:** Run §1 and §3 in the UX Showcase, then scroll back to §11.

---

### T-12 — §8b Public Leak Validation shows FAIL

**Symptom:** §8b shows a red FAIL badge listing one or more forbidden fields.

**Cause:** A sensitive field (`virtual_url`, `join_url`, or `created_by_firebase_uid`) is being
returned by `GET /api/v1/events/public/{id}`.

**This is a security regression.** Stop testing and investigate `EventsService.get_public_event()`
to identify which field is leaking through the public schema projection.

---

## 16. Final PASS/FAIL Checklist

Use this table to record your manual verification results.

### 16.1 Setup and Login

| # | Check | Expected | Result |
|---|---|---|---|
| S-01 | Backend starts | `Application startup complete.` | |
| S-02 | `GET /health` | `{"status":"ok"}` | |
| S-03 | Flutter runs with `--dart-define` flags | No startup errors | |
| S-04 | Firebase login succeeds | `idToken` returned | |
| S-05 | Backend token exchange | `user_type: "alumni"`, `ref_id: "NITK2026IT001"` | |
| S-06 | `GET /auth/me` confirms alumni | `user_type: alumni` | |

### 16.2 Developer Diagnostics (13 Checks)

| # | Check | Expected | Result |
|---|---|---|---|
| D-01 | `/dev/diagnostics/registrations` returns 13 results | `"total": 13` | |
| D-02 | Check 1: Alumni Profile | `PASS`, `is_active: true` | |
| D-03 | Check 2: Test Virtual Event Setup | `PASS`, `status: "published"` | |
| D-04 | Check 3: Test Capacity Event Setup | `PASS`, `capacity: 1` | |
| D-05 | Check 4: Registration Eligibility | `PASS`, `eligible` | |
| D-06 | Check 5: Register for Event | `PASS`, `status: "registered"` | |
| D-07 | Check 6: My Registration | `PASS`, `join_url` present | |
| D-08 | Check 7: My Registrations List | `PASS`, test registration found | |
| D-09 | Check 8: Duplicate Guard | `PASS`, `409 already_registered` | |
| D-10 | Check 9: Capacity Guard | `PASS`, `409 event_full` | |
| D-11 | Check 10: Join Link Visibility | `PASS`, `join_url_present: true` | |
| D-12 | Check 11: Confirmation Email Status | `PASS`, `sent` or `failed` | |
| D-13 | Check 12: Audit Log | `PASS`, audit row found | |
| D-14 | Check 13: Public API Leak | `PASS`, no forbidden fields | |
| D-15 | **Overall** | `"passed": 13, "failed": 0` | |

### 16.3 Week 3 UX Showcase

| # | Section | Expected | Result |
|---|---|---|---|
| UX-01 | §0 Run All Validation | 13/13 green PASS | |
| UX-02 | §1 Alumni Autofill | Profile card with name, ref_id, is_active | |
| UX-03 | §2 Eligibility (event 25) | Green `eligible` banner | |
| UX-04 | §2 Eligibility (event 26) | Green `eligible` banner | |
| UX-05 | §3 Register (event 25) | `join_url: null`, `status: registered` | |
| UX-06 | §3 Register (event 26) | `join_url` non-null, `status: registered` | |
| UX-07 | §4 Confirmation (event 26) | Join link card visible | |
| UX-08 | §4 Confirmation (event 25) | Join link hidden, venue shown | |
| UX-09 | §5 My Registration | Registration card shown | |
| UX-10 | §6 My Registrations List | Both events in list | |
| UX-11 | §7 Negative Gallery | 9 error cards visible | |
| UX-12 | Dev Notes | 7 rules displayed | |
| UX-13 | §8a Join Link Matrix | 4 rows, row 1 highlighted | |
| UX-14 | §8b Public Leak (event 26) | Green PASS badge | |
| UX-15 | §9 Audit Trail | Rows from event_audit_log | |
| UX-16 | §10 Email Demo | Email status card populated | |
| UX-17 | §11 Snapshot Demo | Both columns populated, values match | |
| UX-18 | §12 DB Rules | 4 rule cards with green badges | |

### 16.4 Positive Use Cases (curl)

| # | Check | Expected | Result |
|---|---|---|---|
| P-01 | UC-01: Register event 25 (physical) | HTTP 201, `join_url: null` | |
| P-02 | UC-02: Register event 26 (virtual) | HTTP 201, `join_url` present | |
| P-03 | UC-03: My registrations list | Both events, event 26 has `join_url` | |
| P-04 | UC-11: GET /alumni/me | `is_active: true`, flat response | |
| P-05 | UC-13: Public events list | No `virtual_url` in any event | |
| P-06 | UC-14: Public event 26 detail | `virtual_url` absent, `join_url` absent | |

### 16.5 Negative Use Cases (curl)

| # | Check | Expected | Result |
|---|---|---|---|
| N-01 | NC-01: Duplicate registration | `409 already_registered` | |
| N-02 | NC-02: Full event (event 34) | `409 event_full` | |
| N-03 | NC-03: Closed registration (event 35) | `409 registration_closed` | |
| N-04 | NC-04: Registration not open (event 36) | `409 registration_not_open_yet` | |
| N-05 | NC-05: Non-alumni | `403 alumni_only` | |
| N-06 | NC-06: Inactive alumni | `403 alumni_not_active` | |
| N-07 | NC-07: No auth — eligibility | `401` | |
| N-08 | NC-07: No auth — POST register | `401` | |
| N-09 | NC-07: No auth — my registrations | `401` | |
| N-10 | NC-08: Public API — virtual_url absent | `virtual_url present: False` | |

### 16.6 Eligibility Status v2 Compliance

| # | Check | Expected | Result |
|---|---|---|---|
| E-01 | Event 25/26 before registering | `eligible` | |
| E-02 | Event 25/26 after registering | `already_registered` | |
| E-03 | Event 34 eligibility | `full` (NOT `event_full`) | |
| E-04 | Event 35 eligibility | `closed` (NOT `registration_closed`) | |
| E-05 | Event 36 eligibility | `not_open_yet` (NOT `registration_not_open_yet`) | |
| E-06 | Non-alumni eligibility | `ineligible` + `message` field | |

### 16.7 Database Verification

| # | Check | Expected | Result |
|---|---|---|---|
| DB-01 | Registration numbers present | `NITKSAA-YYYY-NNNNNN` pattern | |
| DB-02 | `confirmation_email_status` not null | `"sent"` or `"failed"` | |
| DB-03 | Audit log has registration rows | `entity_type = "registration"` | |
| DB-04 | Event 34 has 1 registered row | `registered_count = 1` | |
| DB-05 | Event 26 has `virtual_url` in DB | `has_virtual_url = true` | |
| DB-06 | Alumni record active in alumni_db | `registrationstatus = "Active"` | |
| DB-07 | Re-registration after cancellation | HTTP 201, two rows in registrations | |

### 16.8 Security Invariants

| # | Invariant | Verified By | Result |
|---|---|---|---|
| SEC-01 | `virtual_url` never in public API | NC-08, D-14, UX-14 | |
| SEC-02 | `join_url` only for registered+virtual+published | UC-02 vs UC-01, UX-07/08 | |
| SEC-03 | Email failure does not rollback registration | T-10 note | |
| SEC-04 | `audit_service.emit()` never raises | D-13, T-09 | |
| SEC-05 | Dev diagnostics return 404 in non-development | NC-09 | |
| SEC-06 | Authenticated endpoints reject no-token requests | N-07..N-09 | |
| SEC-07 | Cancelled registration returns `join_url: null` | SEC-07 test | |
| SEC-08 | Cancelled registration excluded from `registered_count` | SEC-08 test | |

### 16.9 API Integrity

| # | Check | Expected | Result |
|---|---|---|---|
| API-01 | No duplicate `registration_number` values | 0 rows from HAVING COUNT(*) > 1 | |
| API-02 | Snapshots frozen at registration time | Baseline values unchanged after alumni_db update | |

---

### Overall Verification Result

| Section | Total Checks | PASS | FAIL |
|---|---|---|---|
| Setup and Login | 6 | | |
| Developer Diagnostics (13 checks) | 15 | | |
| Week 3 UX Showcase | 18 | | |
| Positive Use Cases (curl) | 6 | | |
| Negative Use Cases (curl) | 10 | | |
| Eligibility Status v2 Compliance | 6 | | |
| Database Verification | 7 | | |
| Security Invariants | 8 | | |
| API Integrity | 2 | | |
| **TOTAL** | **78** | | |

**Week 4 GO condition:** All 78 checks PASS, or all FAIL items have documented explanations with
resolution plans in the open issues register.

---

*This guide covers Week 3 deliverables only. Production Flutter registration UI, Admin attendee
management, attendance tracking, QR check-in, waitlist, and payments are out of scope for Week 3.*

*For API response shapes reference: `docs/api/week3_actual_api_response_shapes.md`*  
*For UX Showcase design details: `docs/reviews/week3_ux_showcase_design.md`*  
*For UX Showcase verification: `docs/reviews/week3_ux_showcase_verification_report.md`*
