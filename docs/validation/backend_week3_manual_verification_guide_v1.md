# Week 3 — Manual Verification Guide

**Date:** 2026-06-18  
**Version:** 1.0  
**Branch:** main  
**Status:** Final — Week 3

> **Scope:** Step-by-step manual verification of all Week 3 registration use cases using the
> Flutter Developer Diagnostics screen, backend API curl commands, and direct database queries.  
> All values in this guide reflect the **actual backend implementation (v2)**. Do not use v1 values.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Login Verification](#2-login-verification)
3. [Developer Diagnostics Verification](#3-developer-diagnostics-verification)
4. [Positive Use Cases](#4-positive-use-cases)
5. [Negative Use Cases](#5-negative-use-cases)
   - [5.1 Additional Security Tests](#51-additional-security-tests)
   - [5.2 Additional API Tests](#52-additional-api-tests)
   - [5.3 Additional Database Constraint Tests](#53-additional-database-constraint-tests)
6. [Test Event Reference](#6-test-event-reference)
7. [Expected UI States (v2)](#7-expected-ui-states-v2)
8. [Backend API Curl Reference](#8-backend-api-curl-reference)
9. [Database Verification Queries](#9-database-verification-queries)
10. [Troubleshooting](#10-troubleshooting)
11. [Final PASS/FAIL Checklist](#11-final-passfail-checklist)

---

## 1. Prerequisites

### 1.1 Environment Requirements

| Requirement | Value | Check |
|---|---|---|
| `APP_ENV` in `backend/.env` | `development` | `grep APP_ENV backend/.env` |
| `EVENTS_DB_URL` in `backend/.env` | set (local PostgreSQL) | `grep EVENTS_DB_URL backend/.env` |
| `ALUMNI_DB_URL` in `backend/.env` | set (local PostgreSQL) | `grep ALUMNI_DB_URL backend/.env` |
| `FIREBASE_PROJECT_ID` in `backend/.env` | set | `grep FIREBASE_PROJECT_ID backend/.env` |
| `DEV_DIAGNOSTICS_EMAIL` in `backend/.env` | `Username2026@gmail.com` | `grep DEV_DIAGNOSTICS_EMAIL backend/.env` |
| Flutter SDK | 3.x or later | `flutter --version` |
| Python 3.11+ | required | `python --version` |

> **If `ALUMNI_DB_URL` is not set:** Alumni lookup silently fails; the test user will log in as
> `user_type="other"` instead of `"alumni"`, and all alumni-gated endpoints will return
> `alumni_only` or `ineligible`. Set `ALUMNI_DB_URL` before running registration tests.

### 1.2 Start Commands

**Terminal 1 — Backend:**

```bash
cd backend
uvicorn app.main:app --port 8000 --log-level warning
```

Expected output: `Application startup complete.`  
Verify: `curl http://localhost:8000/health` → `{"status":"ok"}`

**Terminal 2 — Flutter (Chrome):**

```bash
cd apps/event_app
flutter run -d chrome \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

> The `--dart-define` flags inject credentials that `DevAccessConfig` reads at compile time via
> `String.fromEnvironment()`. Without these flags, the Developer Diagnostics section will not auto-login.

### 1.3 Test Credentials

| Field | Value |
|---|---|
| Email | `Username2026@gmail.com` |
| Password | `Password2026` |
| Firebase UID | `fxvOA6JInMM2OPKb3vuSV7qJwtI3` |
| Alumni ID (ref_id) | `NITK2026IT001` |
| `user_type` | `alumni` |
| `registrationstatus` in alumni_db | `Active` |

### 1.4 Test Events

See [Section 6](#6-test-event-reference) for full details. Quick reference:

| Event ID | Type | Scenario |
|---|---|---|
| 25 | Physical | Open — positive registration test |
| 26 | Virtual | Open — join_url test |
| 34 | Physical | Full (capacity=1) — capacity guard test |
| 35 | Physical | Registration closed |
| 36 | Physical | Registration not open yet |

---

## 2. Login Verification

### 2.1 Via Flutter Developer Diagnostics Screen

1. Start both backend and Flutter (see §1.2).
2. In the Flutter web app, navigate to **Developer Diagnostics** (bottom nav or direct route).
3. The screen auto-logins using `DEV_DIAGNOSTICS_EMAIL` and `DEV_DIAGNOSTICS_PASSWORD` on mount.
4. The header should show the logged-in user's email and `user_type: alumni`.

**Expected header state:**

```
Logged in as: Username2026@gmail.com
Type: alumni | Ref: NITK2026IT001
```

**If the header shows "Not logged in":** The `--dart-define` flags were not set. Restart Flutter
with the full command from §1.2.

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

Copy the `idToken` field from the response (it is a long JWT string).

**Step 2 — Exchange for backend access_token:**

```bash
FIREBASE_ID_TOKEN="paste-id-token-from-step-1"

ACCESS_TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/firebase \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"${FIREBASE_ID_TOKEN}\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "ACCESS_TOKEN=${ACCESS_TOKEN}"
```

**Expected response from Step 2:**

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

> Store `ACCESS_TOKEN` in your shell session — all subsequent curl commands in this guide use it.
> The token expires after 480 minutes (development setting). Re-run Step 2 if it expires.

### 2.3 Verify Current User

```bash
curl -s http://localhost:8000/api/v1/auth/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected: `firebase_uid`, `email`, `user_type: "alumni"`, `ref_id: "NITK2026IT001"`.

---

## 3. Developer Diagnostics Verification

### 3.1 Overview

The Developer Diagnostics screen (`developer_diagnostics_screen.dart`) is accessible only in
`APP_ENV=development`. It runs a 13-check diagnostic suite against
`GET /api/v1/dev/diagnostics/registrations`.

**All 13 checks must PASS.** If any check FAILs, see [Section 10](#10-troubleshooting).

### 3.2 Running the Diagnostics

**Via Flutter screen:**

1. Navigate to Developer Diagnostics.
2. Tap **Run Registration Diagnostics**.
3. Wait up to 90 seconds for all 13 checks to complete.
4. Inspect the result card for each check.

**Via curl:**

```bash
curl -s http://localhost:8000/api/v1/dev/diagnostics/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

### 3.3 The 13 Checks

| # | Check Name | API / Method | Expected PASS Condition |
|---|---|---|---|
| 1 | Alumni Profile | `GET /api/v1/alumni/me` | `is_active: true`, `registrationstatus: "Active"` |
| 2 | Test Virtual Event Setup | `POST /api/v1/events` | `status: "published"`, `is_virtual: true` |
| 3 | Test Capacity Event Setup | `POST /api/v1/events` | `status: "published"`, `capacity: 1` |
| 4 | Registration Eligibility | `GET /api/v1/events/{id}/registration-eligibility` | `eligibility_status: "eligible"` |
| 5 | Register for Event | `POST /api/v1/events/{id}/register` | `status: "registered"`, `registration_number` present |
| 6 | My Registration | `GET /api/v1/events/{id}/my-registration` | `status: "registered"`, `join_url` present (virtual) |
| 7 | My Registrations List | `GET /api/v1/my/registrations` | test registration found in list |
| 8 | Duplicate Registration Guard | `POST /api/v1/events/{id}/register` (2nd attempt) | `HTTP 409`, `detail: "already_registered"` |
| 9 | Capacity Guard | `POST /api/v1/events/{id}/register` (capacity=1 full) | `HTTP 409`, `detail: "event_full"` |
| 10 | Join Link Visibility | `GET /api/v1/events/{id}/my-registration` | `join_url` non-null for virtual+published+registered |
| 11 | Confirmation Email Status | DB direct query on `registrations` | `confirmation_email_status` in `("sent", "failed")` |
| 12 | Audit Log Check | DB direct query on `event_audit_log` | audit row found for `entity_type="registration"` |
| 13 | Public API Leak Check | `GET /api/v1/events/public/{id}` | `virtual_url` and `created_by_firebase_uid` absent |

### 3.4 Reading the Response

The top-level response shape:

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
  "run_at": "2026-06-18T..."
}
```

Each entry in `results`:

```json
{
  "feature": "Register for Event",
  "api": "/api/v1/events/{id}/register",
  "method": "POST",
  "auth_required": true,
  "request": { "event_id": 123 },
  "response": {
    "registration_id": 7,
    "registration_number": "NITKSAA-2026-000007",
    "status": "registered",
    "confirmation_email_status": "sent"
  },
  "status": "PASS",
  "duration_ms": 45,
  "timestamp": "2026-06-18T..."
}
```

**PASS criteria for this section:** `"passed": 13`, `"failed": 0`.

> The diagnostics endpoint creates two temporary events (`DIAG_REG_VIRTUAL_*` and
> `DIAG_REG_CAP_*`) and cancels them at the end. These are safe to ignore in the database.

---

## 4. Positive Use Cases

### UC-01 — Alumni Registers for Physical Event (Event 25)

**Goal:** Confirm a full physical registration completes successfully.

**Step 1 — Check eligibility:**

```bash
curl -s http://localhost:8000/api/v1/events/25/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected:

```json
{
  "eligibility_status": "eligible",
  "message": "You are eligible to register.",
  "registered_count": <n>,
  "capacity": <cap>
}
```

**Step 2 — Register:**

```bash
curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Manual verification test"}' | python3 -m json.tool
```

Expected (HTTP 201):

```json
{
  "registration_id": <int>,
  "registration_number": "NITKSAA-2026-XXXXXX",
  "event_id": 25,
  "status": "registered",
  "join_url": null,
  "confirmation_email_status": "sent",
  "registered_at": "2026-06-18T...",
  "event": {
    "event_id": 25,
    "title": "<event title>",
    "is_virtual": false,
    "timezone": "Asia/Kolkata",
    "location_text": "<venue>",
    "location_maps_url": null,
    "start_datetime": "...",
    "end_datetime": "..."
  }
}
```

> `is_virtual` is in the nested `event` object, not at the top level of the registration response.

**PASS criteria:**
- HTTP status: `201`
- `status: "registered"`
- `join_url: null` (physical event — join_url must be null)
- `event.is_virtual: false` (check inside the nested `event` object)
- `registration_number` matches pattern `NITKSAA-YYYY-NNNNNN`
- `confirmation_email_status` is `"sent"` or `"failed"` (never `null`)

**Flutter UI (Developer Diagnostics §4 — positive cards):** Tap **Register (Event 25)**. Expect green card with registration number.

---

### UC-02 — Alumni Registers for Virtual Event (Event 26)

**Goal:** Confirm `join_url` is returned for a virtual registration.

**Step 1 — Check eligibility:**

```bash
curl -s http://localhost:8000/api/v1/events/26/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected: `eligibility_status: "eligible"`

**Step 2 — Register:**

```bash
curl -s -X POST http://localhost:8000/api/v1/events/26/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Virtual event test"}' | python3 -m json.tool
```

Expected (HTTP 201):

```json
{
  "registration_id": <int>,
  "registration_number": "NITKSAA-2026-XXXXXX",
  "event_id": 26,
  "status": "registered",
  "join_url": "https://...",
  "confirmation_email_status": "sent",
  "registered_at": "2026-06-18T...",
  "event": {
    "event_id": 26,
    "title": "<event title>",
    "is_virtual": true,
    "timezone": "Asia/Kolkata",
    "location_text": null,
    "location_maps_url": null,
    "start_datetime": "...",
    "end_datetime": "..."
  }
}
```

> `is_virtual` is in the nested `event` object. `join_url` is a top-level field and is non-null
> because the event is virtual AND the registration is active AND the event is published.

**PASS criteria:**
- `event.is_virtual: true` (`is_virtual` is inside the nested `event` object, not at top level)
- `join_url` is a non-null, non-empty string starting with `https://`
- HTTP status: `201`

**Step 3 — Verify join_url via my-registration:**

```bash
curl -s http://localhost:8000/api/v1/events/26/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected: `join_url` is present (same URL as in the registration response).

> **Security invariant:** `virtual_url` must never appear in any public API response.
> `join_url` only appears when: `status="registered"` AND `is_virtual=true` AND event `status="published"`.

---

### UC-03 — View My Registrations List

**Goal:** Confirm both event 25 and event 26 registrations appear in the list.

```bash
curl -s http://localhost:8000/api/v1/my/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected:

```json
{
  "total": <n>,
  "registrations": [
    {
      "registration_id": <int>,
      "registration_number": "NITKSAA-2026-XXXXXX",
      "event_id": 25,
      "status": "registered",
      ...
    },
    {
      "registration_id": <int>,
      "registration_number": "NITKSAA-2026-XXXXXX",
      "event_id": 26,
      "status": "registered",
      "join_url": "https://...",
      ...
    }
  ]
}
```

**PASS criteria:**
- Both event 25 and event 26 registrations present
- Event 26 entry has `join_url` populated
- Event 25 entry has `join_url: null`

---

### UC-11 — Alumni Profile (GET /alumni/me)

**Goal:** Confirm alumni profile is returned with the correct active status.

```bash
curl -s http://localhost:8000/api/v1/alumni/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

Expected (flat response — no wrapper object):

```json
{
  "ref_id": "NITK2026IT001",
  "fullname": "<name>",
  "email": "Username2026@gmail.com",
  "phone": null,
  "batch_year": 2026,
  "branch": "IT",
  "is_active": true
}
```

**PASS criteria:**
- `is_active: true`
- `ref_id: "NITK2026IT001"` (field is `ref_id`, not `alumni_id`)
- `batch_year: 2026` (field is `batch_year`, not `graduationyear`)
- `registrationstatus` does not appear in the API response — alumni status is computed into `is_active`
- Response is flat — no nested `{status, alumni: {...}}` wrapper

---

### UC-13 — Public Events List (No Auth)

**Goal:** Confirm public API returns events without sensitive fields.

```bash
curl -s "http://localhost:8000/api/v1/events/public?page=1&per_page=20" \
  | python3 -m json.tool
```

**PASS criteria:**
- Response contains `total` and `events` array
- No event object contains `virtual_url`
- No event object contains `created_by_firebase_uid`
- `status` field in each event is `"published"`

---

### UC-14 — Public Event Detail (No Auth)

```bash
curl -s http://localhost:8000/api/v1/events/public/26 | python3 -m json.tool
```

Expected:

```json
{
  "event_id": 26,
  "title": "<title>",
  "status": "published",
  "is_virtual": true,
  "sessions": [],
  "speakers": [],
  ...
}
```

**PASS criteria:**
- `virtual_url` absent
- `sessions` is a list (may be empty)
- `speakers` is a list (may be empty)
- `created_by_firebase_uid` absent

---

## 5. Negative Use Cases

### NC-01 — Duplicate Registration (already_registered)

**Goal:** Second registration attempt for the same event returns `409 already_registered`.

```bash
# Assumes you have already registered for event 25 (UC-01)
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Duplicate attempt"}'
# Expected output: 409
```

Full response:

```bash
curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Duplicate attempt"}' | python3 -m json.tool
```

Expected:

```json
{
  "detail": "already_registered"
}
```

**PASS criteria:** HTTP `409`, `detail: "already_registered"`

**Eligibility equivalent:** `eligibility_status: "already_registered"` (GET eligibility will show this state)

**Flutter UI:** Eligibility card shows **"Already Registered"** (primary container colour, `Icons.check_circle_outline`).

---

### NC-02 — Full Event Registration (event_full)

**Goal:** Registration attempt on a full event returns `409 event_full`.

**Pre-condition:** Event 34 must have `capacity=1` and already have one active registration.

```bash
curl -s -X POST http://localhost:8000/api/v1/events/34/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Full event test"}' | python3 -m json.tool
```

Expected:

```json
{
  "detail": "event_full"
}
```

**PASS criteria:** HTTP `409`, `detail: "event_full"`

**Eligibility equivalent:** `eligibility_status: "full"` (GET eligibility returns `full` — not `event_full`)

```bash
curl -s http://localhost:8000/api/v1/events/34/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
# Expected: {"eligibility_status": "full", ...}
```

**Flutter UI:** Eligibility card shows **"Event Full"** (error container, `Icons.do_not_disturb_outlined`). CTA button is disabled.

---

### NC-03 — Registration Closed (registration_closed)

**Goal:** Registration attempt when `registration_closes_at` is in the past returns `409 registration_closed`.

**Pre-condition:** Event 35 has `registration_closes_at` in the past.

```bash
curl -s -X POST http://localhost:8000/api/v1/events/35/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected:

```json
{
  "detail": "registration_closed"
}
```

**Eligibility:**

```bash
curl -s http://localhost:8000/api/v1/events/35/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
# Expected: {"eligibility_status": "closed", ...}
```

**PASS criteria:** POST returns HTTP `409` / `detail: "registration_closed"`. Eligibility returns `eligibility_status: "closed"` (not `registration_closed`).

**Flutter UI:** Eligibility card shows **"Registration Closed"** (error container, `Icons.lock_clock_outlined`).

---

### NC-04 — Registration Not Open Yet (registration_not_open_yet)

**Goal:** Registration attempt when `registration_opens_at` is in the future returns `409 registration_not_open_yet`.

**Pre-condition:** Event 36 has `registration_opens_at` in the future.

```bash
curl -s -X POST http://localhost:8000/api/v1/events/36/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected:

```json
{
  "detail": "registration_not_open_yet"
}
```

**Eligibility:**

```bash
curl -s http://localhost:8000/api/v1/events/36/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
# Expected: {"eligibility_status": "not_open_yet", ...}
```

**PASS criteria:** POST returns HTTP `409` / `detail: "registration_not_open_yet"`. Eligibility returns `eligibility_status: "not_open_yet"`.

**Flutter UI:** Eligibility card shows **"Registration Not Open Yet"** (tertiary container, `Icons.hourglass_top_outlined`).

---

### NC-05 — Non-Alumni User (alumni_only)

**Goal:** Registration attempt by a non-alumni user returns `403 alumni_only`.

**Setup:** Log in with a non-alumni Google account (not linked to any alumni_db record).

```bash
# Use access_token from non-alumni account login
NON_ALUMNI_TOKEN="token-for-non-alumni-user"

curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${NON_ALUMNI_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected:

```json
{
  "detail": "alumni_only"
}
```

**Eligibility for non-alumni:**

```bash
curl -s http://localhost:8000/api/v1/events/25/registration-eligibility \
  -H "Authorization: Bearer ${NON_ALUMNI_TOKEN}" | python3 -m json.tool
```

Expected:

```json
{
  "eligibility_status": "ineligible",
  "message": "Only alumni can register for this event."
}
```

**PASS criteria:** POST returns HTTP `403` / `detail: "alumni_only"`. Eligibility returns `eligibility_status: "ineligible"` (catch-all). Read `message` to distinguish from `alumni_not_active`.

> **Note:** `alumni_required` is not a valid error code. The correct code is `alumni_only`.

---

### NC-06 — Inactive Alumni (alumni_not_active)

**Goal:** Registration attempt by an alumni with `registrationstatus` outside `{'Active', 'Self-Verified'}` returns `403 alumni_not_active`.

**Setup:** Requires an alumni account whose `registrationstatus` in `alumni_db` is e.g. `"Inactive"`.

```bash
INACTIVE_ALUMNI_TOKEN="token-for-inactive-alumni"

curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${INACTIVE_ALUMNI_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -m json.tool
```

Expected:

```json
{
  "detail": "alumni_not_active"
}
```

**Eligibility:**

```json
{
  "eligibility_status": "ineligible",
  "message": "Alumni account is not active."
}
```

**PASS criteria:** POST returns HTTP `403` / `detail: "alumni_not_active"`. Eligibility returns `eligibility_status: "ineligible"` with a different `message` than the alumni_only case.

**Flutter UI:** Eligibility card shows **"Not Eligible"** (surface, `Icons.info_outline`). CTA shows message text.

---

### NC-07 — Unauthenticated Access to Registration Endpoint

**Goal:** Confirm that authenticated endpoints reject unauthenticated requests with `401`.

```bash
# No Authorization header
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/api/v1/events/25/registration-eligibility
# Expected: 401

curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Content-Type: application/json" \
  -d '{}'
# Expected: 401

curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/api/v1/my/registrations
# Expected: 401
```

**PASS criteria:** All three return HTTP `401`.

---

### NC-08 — Public API Leak Check (virtual_url must not appear)

**Goal:** Confirm `virtual_url` is never present in public API responses for a virtual event.

```bash
# Event 26 is virtual
curl -s http://localhost:8000/api/v1/events/public/26 | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('virtual_url present:', 'virtual_url' in d)
print('created_by_firebase_uid present:', 'created_by_firebase_uid' in d)
"
```

Expected output:

```
virtual_url present: False
created_by_firebase_uid present: False
```

**PASS criteria:** Both fields absent from public response. HTTP `200`.

---

### NC-09 — Dev Diagnostics Not Available in Production

**Goal:** Confirm dev diagnostics endpoint returns `404` when `APP_ENV != development`.

> This test requires temporarily changing `APP_ENV` to `production` in `backend/.env` and
> restarting the server. Only run if you can safely do so in your dev environment.

```bash
# With APP_ENV=production
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/api/v1/dev/diagnostics/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
# Expected: 404
```

**PASS criteria:** HTTP `404`.

---

> **Note on cancellation in tests below:** Sections 5.1 and 5.3 require setting
> `registration.status = 'cancelled'`. Week 3 does not expose a public cancel endpoint.
> These tests use direct `psql UPDATE` commands for controlled local verification only.
> **Do not apply these manual DB updates in staging or production unless explicitly approved.**
> Always restore the database to its original state after each test.

---

## 5.1 Additional Security Tests

### SEC-07 — Cancelled Registration Hides join_url

**Goal:** Verify that `join_url` is `null` for a cancelled registration on a virtual event.

**Rule:**

```
join_url is non-null only when ALL three conditions hold:
  registration.status = 'registered'
  event.is_virtual = true
  event.status = 'published'
```

If any condition fails, `_resolve_join_url()` returns `null`.

**Setup:** Requires event 26 (virtual, published, with `virtual_url` set). Complete UC-02 first if
not yet registered.

**Step 1 — Confirm join_url is present before cancellation:**

```bash
curl -s "http://localhost:8000/api/v1/events/26/my-registration" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('status:', d.get('status'))
print('join_url:', d.get('join_url'))
"
```

Expected output:

```
status: registered
join_url: https://meet.google.com/...   ← non-null
```

**Step 2 — Fetch the registration_id:**

```bash
psql -d events_db -c "
SELECT registration_id, status
FROM registrations
WHERE event_id = 26
  AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
  AND status = 'registered';
"
```

Note the `registration_id` value.

**Step 3 — Cancel the registration (local dev only):**

```sql
UPDATE registrations
SET status = 'cancelled',
    cancelled_at = NOW(),
    updated_at = NOW()
WHERE registration_id = <registration_id_from_step_2>;
```

**Step 4 — Confirm join_url is now null:**

```bash
curl -s "http://localhost:8000/api/v1/events/26/my-registration" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('status:', d.get('status'))
print('join_url:', d.get('join_url'))
"
```

Expected output:

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
WHERE registration_id = <registration_id_from_step_2>;
```

**PASS criteria:**
- After cancellation, `join_url` is `null` in the response.
- `status` is `"cancelled"`.
- HTTP is `200` — the record still exists, just cancelled.

**FAIL if:** `join_url` is non-null when `status = 'cancelled'`.

---

### SEC-08 — Cancelled Registration Not Counted in registered_count

**Goal:** Verify that cancelled registrations do not consume event capacity or appear in
`registered_count`.

**Setup:** Uses event 25 (physical, capacity = 50, open registration).

**Step 1 — Record the current registered_count via the eligibility endpoint:**

```bash
curl -s "http://localhost:8000/api/v1/events/25/registration-eligibility" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('eligibility_status:', d.get('eligibility_status'))
print('registered_count:', d.get('registered_count'))
print('capacity:', d.get('capacity'))
"
```

Note the `registered_count` value (call it **N**).

**Step 2 — Confirm the DB count matches:**

```sql
SELECT COUNT(*) AS registered_count
FROM registrations
WHERE event_id = 25 AND status = 'registered';
```

Expected: equals **N**.

**Step 3 — Cancel one active registration:**

```sql
-- Identify a registration to cancel
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

**Step 4 — Recheck registered_count via API:**

```bash
curl -s "http://localhost:8000/api/v1/events/25/registration-eligibility" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('eligibility_status:', d.get('eligibility_status'))
print('registered_count:', d.get('registered_count'))
"
```

Expected: `registered_count` = **N − 1**.

**Step 5 — Confirm DB breakdown:**

```sql
SELECT
  COUNT(*) FILTER (WHERE status = 'registered') AS active_count,
  COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled_count
FROM registrations
WHERE event_id = 25;
```

Expected: `active_count` = **N − 1**, `cancelled_count` ≥ 1.
The cancelled row is retained — it is not deleted.

**Step 6 — Restore:**

```sql
UPDATE registrations
SET status = 'registered',
    cancelled_at = NULL,
    updated_at = NOW()
WHERE registration_id = <registration_id>;
```

**PASS criteria:**
- API `registered_count` decreases by 1 after cancellation.
- DB `COUNT(status='registered')` excludes cancelled rows.
- Cancelled row is retained in the table (not deleted).
- If the event was at capacity (status `full`) before cancellation, status returns to `eligible`
  after cancellation.

**FAIL if:** Cancelled row is still counted in `registered_count` or if the row is hard-deleted.

---

## 5.2 Additional API Tests

### API-01 — Registration Number Uniqueness Across Multiple Registrations

**Goal:** Verify each registration gets a unique `registration_number` in the format
`NITKSAA-YYYY-NNNNNN`.

**Step 1 — List all registration numbers:**

```bash
psql -d events_db -c "
SELECT registration_id, registration_number
FROM registrations
ORDER BY registration_id;
"
```

**Step 2 — Check for duplicates:**

```sql
SELECT registration_number, COUNT(*)
FROM registrations
WHERE registration_number IS NOT NULL
GROUP BY registration_number
HAVING COUNT(*) > 1;
```

Expected: **0 rows** (no duplicates).

**Step 3 — Verify format pattern:**

```sql
SELECT registration_number
FROM registrations
WHERE registration_number NOT LIKE 'NITKSAA-____-______'
  AND registration_number IS NOT NULL;
```

Expected: **0 rows** (all match the pattern).

**Step 4 — Verify year component:**

```sql
SELECT registration_number,
       split_part(registration_number, '-', 2) AS year_part
FROM registrations
WHERE registration_number IS NOT NULL;
```

Expected: `year_part = '2026'` (or the year of the test run) for all rows.

**Step 5 — Verify sequence equals registration_id:**

```sql
SELECT registration_id,
       registration_number,
       CAST(split_part(registration_number, '-', 3) AS INTEGER) AS sequence_part
FROM registrations
WHERE registration_number IS NOT NULL
ORDER BY registration_id;
```

Expected: `sequence_part` equals `registration_id` for every row. The format is
`NITKSAA-{year}-{registration_id:06d}`.

**PASS criteria:**
- Zero duplicate `registration_number` values.
- All numbers match `NITKSAA-YYYY-NNNNNN`.
- The 6-digit sequence part equals `registration_id`.

**FAIL if:** Any duplicate exists, or any value deviates from the format.

---

### API-02 — Registration Snapshots Unchanged After Alumni Profile Change

**Goal:** Verify snapshot fields in the registration record preserve the alumni profile at
registration time. A later change to `alumni_db` must not alter existing registration snapshots.

**Snapshot fields:**

| Response field | DB column |
|---|---|
| `fullname_snapshot` | `registrations.fullname` |
| `email_snapshot` | `registrations.email` |
| `phone_snapshot` | `registrations.phone` |
| `batch_year_snapshot` | `registrations.batch_year` |
| `branch_snapshot` | `registrations.branch` |

**Step 1 — Record current snapshot values from the API:**

```bash
curl -s "http://localhost:8000/api/v1/events/25/my-registration" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in ['fullname_snapshot','email_snapshot','phone_snapshot','batch_year_snapshot','branch_snapshot']:
    print(f'{k}: {d.get(k)}')
"
```

Note all five values — these are your **baseline**.

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

Expected: `fullname = "MODIFIED Name"`, `batch_year = 1999`, `branch = "Modified Branch"`.
This confirms the live profile changed.

**Step 5 — Confirm my-registration snapshot is unchanged:**

```bash
curl -s "http://localhost:8000/api/v1/events/25/my-registration" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in ['fullname_snapshot','batch_year_snapshot','branch_snapshot']:
    print(f'{k}: {d.get(k)}')
"
```

Expected: values are **identical to the baseline** from Step 1.

**Step 6 — Restore alumni_db (REQUIRED — other tests depend on this record):**

```sql
UPDATE alumni
SET fullname = 'Username Alumni',
    phone = '+919876543210',
    graduationyear = 2026,
    branch = 'Information Technology'
WHERE alumni_id = 'NITK2026IT001';

-- Verify restoration
SELECT fullname, phone, graduationyear, branch
FROM alumni WHERE alumni_id = 'NITK2026IT001';
```

> **Warning:** Always run Step 6 before continuing to other tests. Failure to restore the alumni
> record will cause NC-06, UC-11, and diagnostics checks to fail.

**PASS criteria:**
- Snapshot fields in the registration response remain unchanged after the `alumni_db` update.
- `GET /alumni/me` reflects the modified profile during Step 4.
- After restoration, both the live profile and snapshot show the expected original values.

**FAIL if:** Any snapshot field changes when the `alumni_db` profile is updated.

---

## 5.3 Additional Database Constraint Tests

### DB-07 — Partial Unique Index Allows Re-Registration After Cancellation

**Goal:** Verify that migration 008 replaced a hard `UNIQUE(event_id, firebase_uid)` constraint
with a partial unique index that allows a cancelled row and a new registered row to coexist for
the same `(event_id, firebase_uid)` pair.

**Background:** A hard unique index would block re-registration even after cancellation. The
partial index enforces uniqueness only on `status = 'registered'` rows. Cancelled rows are
invisible to the constraint.

**Step 1 — Confirm one active registration exists for event 25:**

```sql
SELECT registration_id, status, registration_number
FROM registrations
WHERE event_id = 25
  AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3';
```

Expected: one row with `status = 'registered'`.

**Step 2 — Attempt a duplicate registration (must be blocked):**

```bash
curl -s -X POST \
  "http://localhost:8000/api/v1/events/25/register" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('detail:', d.get('detail'))
" 2>/dev/null || \
curl -s -o /dev/null -w "HTTP %{http_code}" -X POST \
  "http://localhost:8000/api/v1/events/25/register" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Expected: HTTP `409`, `"detail": "already_registered"`.

**Step 3 — Cancel the existing registration (local dev only):**

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
curl -s -X POST \
  "http://localhost:8000/api/v1/events/25/register" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('status:', d.get('status'))
print('registration_number:', d.get('registration_number'))
"
```

Expected: HTTP `201`, new `registration_number` different from the first.

**Step 5 — Verify two rows exist for the same event:**

```sql
SELECT registration_id, status, registration_number, registered_at, cancelled_at
FROM registrations
WHERE event_id = 25
  AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
ORDER BY registration_id;
```

Expected: two rows — one `cancelled`, one `registered` — with different `registration_id` and
`registration_number` values.

**Step 6 — Verify the partial index definition (optional):**

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'registrations'
  AND indexdef ILIKE '%where%registered%';
```

Expected: an index with a `WHERE (status = 'registered')` predicate.

**PASS criteria:**
- Step 2: `409 already_registered` — active duplicate correctly blocked.
- Step 4: `201` — re-registration succeeds after cancellation.
- Step 5: two rows coexist — one `cancelled`, one `registered`.
- The new `registration_number` is distinct from the cancelled row's number.

**FAIL if:** Step 4 returns `409 already_registered` — this means the constraint is a hard `UNIQUE`
and migration 008 was not applied or was rolled back.

---

## 6. Test Event Reference

### 6.1 Known Test Events

| Event ID | Title | Type | Scenario | State |
|---|---|---|---|---|
| 25 | (physical test event) | Physical | Open registration — positive test | `status=published`, registration open |
| 26 | (virtual test event) | Virtual | Join URL test | `status=published`, registration open, `virtual_url` set |
| 34 | (capacity guard event) | Physical | Full event guard | `status=published`, `capacity=1`, 1 registration exists |
| 35 | (closed event) | Physical | Registration closed | `status=published`, `registration_closes_at` in past |
| 36 | (not open event) | Physical | Registration not yet open | `status=published`, `registration_opens_at` in future |

### 6.2 Known Test Registrations

| Registration Number | Event ID | Notes |
|---|---|---|
| NITKSAA-2026-000004 | 25 | Physical — no join_url |
| NITKSAA-2026-000005 | 26 | Virtual — join_url present |

> **If these events do not exist:** Use the admin API or psql to create and configure them.
> See §6.3 for recreation instructions.

### 6.3 Event Recreation Instructions

If test events 25/26/34/35/36 have been deleted or misconfigured, recreate them via psql:

**Connect to events_db:**

```bash
psql -d events_db
```

**Event 25 — Physical, open registration:**

```sql
-- Adjust dates as needed for your testing window
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

-- Insert filler registration to fill the capacity slot
-- (Replace <event_id> with the ID returned above)
INSERT INTO registrations (
  event_id, firebase_uid, status, email, fullname_snapshot,
  batch_year_snapshot, branch_snapshot, registered_at, confirmation_email_status
) VALUES (
  <event_id>, 'fxvOA6JInMM2OPKb3vuSV7qJwtI3',
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

## 7. Expected UI States (v2)

### 7.1 Eligibility Status Values (GET /registration-eligibility)

These are the **actual v2 values** returned by the backend. Use these when switching on
`eligibility_status`. The old v1 values (`event_full`, `registration_closed`,
`registration_not_open_yet`, `can_register`, `alumni_required`) **do not exist**.

| `eligibility_status` | Meaning | Flutter card colour | Icon | CTA label |
|---|---|---|---|---|
| `eligible` | User can register | `primaryContainer` | `how_to_reg_outlined` | "Register" |
| `already_registered` | Active registration exists | `primaryContainer` | `check_circle_outline` | "Already Registered" |
| `full` | `registered_count >= capacity` | `errorContainer` | `do_not_disturb_outlined` | "Event Full" |
| `closed` | Past `registration_closes_at` | `errorContainer` | `lock_clock_outlined` | "Registration Closed" |
| `not_open_yet` | Before `registration_opens_at` | `tertiaryContainer` | `hourglass_top_outlined` | "Registration Not Open Yet" |
| `ineligible` | Catch-all (non-alumni, inactive, event not found, event not published) | `surface` | `info_outline` | (show `message` field) |

### 7.2 POST Register Error Codes

These are the `detail` values returned in HTTP error responses from `POST /register`.
They are **different** from the eligibility_status values above.

| HTTP | `detail` | Semantic state |
|---|---|---|
| 403 | `alumni_only` | Non-alumni or no `ref_id` |
| 403 | `alumni_not_found` | `ref_id` not in alumni_db |
| 403 | `alumni_not_active` | `registrationstatus` not Active/Self-Verified |
| 404 | `event_not_found` | event_id does not exist |
| 409 | `event_not_published` | event `status != "published"` |
| 409 | `registration_not_open_yet` | before `registration_opens_at` |
| 409 | `registration_closed` | after `registration_closes_at` |
| 409 | `already_registered` | duplicate registration attempt |
| 409 | `event_full` | `registered_count >= capacity` |

### 7.3 Two-Code Cross-Reference

| UI State | GET eligibility_status | POST error detail |
|---|---|---|
| Event full | `full` | `event_full` |
| Registration closed | `closed` | `registration_closed` |
| Not open yet | `not_open_yet` | `registration_not_open_yet` |
| Already registered | `already_registered` | `already_registered` |
| Non-alumni | `ineligible` (message: "Only alumni…") | `alumni_only` |
| Inactive alumni | `ineligible` (message: "Alumni account is not active.") | `alumni_not_active` |
| Not published | `ineligible` (message: "Event is not open…") | `event_not_published` |

> **Rule:** When processing eligibility responses, switch on `eligibility_status`.  
> When catching HTTP errors from POST register, switch on `detail`.  
> Never mix the two code sets.

### 7.4 Join Link Visibility Rules

`join_url` in the `my-registration` response is non-null **only when all three conditions hold:**

| Condition | Check |
|---|---|
| Registration `status = "registered"` | `status != "cancelled"` |
| Event `is_virtual = true` | physical events always return `null` |
| Event `status = "published"` | draft/cancelled events return `null` |

If any condition fails, `join_url` is `null` in the response.

---

## 8. Backend API Curl Reference

> All authenticated endpoints require `Authorization: Bearer ${ACCESS_TOKEN}`.
> Set `ACCESS_TOKEN` as described in [Section 2.2](#22-via-curl-two-step).

### 8.1 Authentication

```bash
# Firebase login (Step 1)
curl -s -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email":"Username2026@gmail.com","password":"Password2026","returnSecureToken":true}'

# Backend token exchange (Step 2)
curl -s -X POST http://localhost:8000/api/v1/auth/firebase \
  -H "Content-Type: application/json" \
  -d '{"token":"<firebase_id_token>"}'

# Verify current user
curl -s http://localhost:8000/api/v1/auth/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 8.2 Public Endpoints (No Auth)

```bash
# List published events
curl -s "http://localhost:8000/api/v1/events/public?page=1&per_page=20"

# Get public event detail
curl -s http://localhost:8000/api/v1/events/public/26
```

### 8.3 Alumni Profile

```bash
curl -s http://localhost:8000/api/v1/alumni/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 8.4 Registration Eligibility

```bash
# Check eligibility for event 25 (physical)
curl -s http://localhost:8000/api/v1/events/25/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Check eligibility for event 26 (virtual)
curl -s http://localhost:8000/api/v1/events/26/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Check eligibility for event 34 (full)
curl -s http://localhost:8000/api/v1/events/34/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Check eligibility for event 35 (closed)
curl -s http://localhost:8000/api/v1/events/35/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Check eligibility for event 36 (not open yet)
curl -s http://localhost:8000/api/v1/events/36/registration-eligibility \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 8.5 Register for Event

```bash
# Register for event 25 (POST — body required, attendee_note optional)
curl -s -X POST http://localhost:8000/api/v1/events/25/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"attendee_note": "Manual test"}'

# Register for event 26 (virtual)
curl -s -X POST http://localhost:8000/api/v1/events/26/register \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 8.6 My Registration (single event)

```bash
curl -s http://localhost:8000/api/v1/events/25/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

curl -s http://localhost:8000/api/v1/events/26/my-registration \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 8.7 My Registrations List

```bash
curl -s http://localhost:8000/api/v1/my/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

### 8.8 Developer Diagnostics (dev only)

```bash
# Registration flow — 13 checks
curl -s http://localhost:8000/api/v1/dev/diagnostics/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool

# Auth check
curl -s http://localhost:8000/api/v1/dev/diagnostics/auth/me \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# DB table list
curl -s http://localhost:8000/api/v1/dev/diagnostics/db/tables \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# DB table content (e.g. registrations)
curl -s http://localhost:8000/api/v1/dev/diagnostics/db/registrations \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool
```

---

## 9. Database Verification Queries

Connect to `events_db`:

```bash
psql -d events_db
```

Connect to `alumni_db`:

```bash
psql -d alumni_db
```

### 9.1 Verify Registrations

```sql
-- All active registrations for test user
SELECT
  r.registration_id,
  r.registration_number,
  r.event_id,
  e.title,
  r.status,
  r.confirmation_email_status,
  r.registered_at
FROM registrations r
JOIN events e ON e.event_id = r.event_id
WHERE r.firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
ORDER BY r.registered_at DESC;
```

### 9.2 Verify Registration Numbers

```sql
-- Check registration numbers match NITKSAA-YYYY-NNNNNN pattern
SELECT
  registration_number,
  event_id,
  status,
  confirmation_email_status
FROM registrations
WHERE registration_number LIKE 'NITKSAA-%'
ORDER BY registration_id DESC
LIMIT 10;
```

### 9.3 Verify Email Status

```sql
-- Confirm email status is never null after registration
SELECT
  registration_id,
  registration_number,
  confirmation_email_status,
  confirmation_email_sent_at
FROM registrations
WHERE firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3'
ORDER BY registered_at DESC;
```

Expected: `confirmation_email_status` is `"sent"` or `"failed"`, never `null`.

### 9.4 Verify Audit Log

```sql
-- Check audit log entries for registrations
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

Expected: At least one row per registration, `event_type` like `"registration_created"`.

### 9.5 Verify Event Configuration

```sql
-- Inspect test events configuration
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

### 9.6 Verify Registered Count for Full Event

```sql
-- Check capacity vs registered count for event 34
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

### 9.7 Verify Join URL Security (events_db)

```sql
-- Confirm virtual_url is stored but never exposed publicly
SELECT
  event_id,
  is_virtual,
  virtual_url IS NOT NULL AS has_virtual_url
FROM events
WHERE event_id = 26;
```

Expected: `has_virtual_url = true`. This confirms the URL is stored server-side only.
The public API must never return this value (verified by NC-08 and diagnostic check 13).

### 9.8 Verify Alumni Record (alumni_db)

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

Expected: `registrationstatus` is `'Active'` or `'Self-Verified'`.

---

## 10. Troubleshooting

### T-01 — user_type is "other" instead of "alumni"

**Symptom:** `POST /api/v1/auth/firebase` returns `user_type: "other"`, `ref_id: null`.

**Cause:** `ALUMNI_DB_URL` is not set or `alumni_db` does not contain a record for `Username2026@gmail.com`.

**Fix:**
1. Check `.env`: `grep ALUMNI_DB_URL backend/.env`
2. Restart backend after setting it.
3. Verify alumni record exists: `psql -d alumni_db -c "SELECT * FROM alumni WHERE email = 'Username2026@gmail.com'"`
4. If no record, insert one: see [Section 9.8](#98-verify-alumni-record-alumni_db).

---

### T-02 — Dev diagnostics returns 404

**Symptom:** `GET /api/v1/dev/diagnostics/registrations` returns HTTP 404.

**Cause:** `APP_ENV` is not `development`.

**Fix:** `grep APP_ENV backend/.env` — should be `APP_ENV=development`. Restart backend after changing.

---

### T-03 — Diagnostics fail: "skipped: user is not alumni or has no ref_id"

**Symptom:** Checks 2–13 all show `status: FAIL` with `error: "skipped: user is not alumni or has no ref_id"`.

**Cause:** Same as T-01. The diagnostics check `is_alumni = user_type == "alumni" AND ref_id != null` before running.

**Fix:** Resolve T-01 first.

---

### T-04 — join_url is null for virtual event

**Symptom:** `GET /api/v1/events/26/my-registration` returns `join_url: null`.

**Cause:** One of the three conditions for `_resolve_join_url()` is not met:
1. Registration `status` is not `"registered"` (e.g. cancelled)
2. Event `is_virtual` is `false`
3. Event `status` is not `"published"` (e.g. cancelled or draft)

**Fix:**
```sql
SELECT event_id, status, is_virtual FROM events WHERE event_id = 26;
SELECT event_id, status FROM registrations WHERE event_id = 26 AND firebase_uid = 'fxvOA6JInMM2OPKb3vuSV7qJwtI3';
```
Correct whichever condition fails.

---

### T-05 — eligibility_status shows "ineligible" when expecting "eligible"

**Symptom:** GET eligibility for event 25 or 26 returns `eligibility_status: "ineligible"`.

**Causes and checks:**
1. `user_type != "alumni"` → fix T-01
2. `ref_id` is null → fix T-01
3. Alumni not in alumni_db → check §9.8
4. Alumni `registrationstatus` not Active/Self-Verified → update alumni_db record
5. Event not published → `SELECT status FROM events WHERE event_id = 25`

---

### T-06 — Event 34 not triggering event_full

**Symptom:** POST to event 34 succeeds instead of returning `409 event_full`.

**Cause:** The filler registration for event 34 is absent.

**Fix:** Check registered count: `SELECT COUNT(*) FROM registrations WHERE event_id = 34 AND status = 'registered'`. If 0, insert a filler registration as shown in §6.3.

---

### T-07 — Backend returns 500 on registration

**Symptom:** POST /register returns HTTP 500.

**Causes:**
- `events_db` connection down → check `EVENTS_DB_URL`
- `alumni_db` connection down (alumni lookup fails) → check `ALUMNI_DB_URL`
- Backend log shows exception → `uvicorn app.main:app --port 8000 --log-level debug`

---

### T-08 — Flutter screen shows "Not logged in"

**Symptom:** Developer Diagnostics screen header shows no user or "Not logged in".

**Cause:** `--dart-define` flags not passed to `flutter run`.

**Fix:** Stop and restart Flutter with:
```bash
flutter run -d chrome \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

---

### T-09 — audit_log row missing after registration

**Symptom:** Diagnostic check 12 fails: "No audit_log row found for registration".

**Cause:** `audit_service.emit()` failed silently (it is wrapped in try/except and never raises).

**Fix:** Check backend logs for `WARNING` messages from the audit service. The registration itself is still valid — only the audit record is missing.

---

### T-10 — email status is "failed" instead of "sent"

**Symptom:** `confirmation_email_status: "failed"`.

**Meaning:** Email delivery failed, but the **registration is still valid**. This is the expected
behavior per the email-after-commit policy — email failure never rolls back a registration.

**Fix:** Check SMTP configuration in `.env`. For manual verification purposes, `"failed"` is an
acceptable state — the diagnostic check accepts both `"sent"` and `"failed"` as PASS.

---

## 11. Final PASS/FAIL Checklist

Use this table to record your manual verification results. All items must be PASS before Week 4 starts.

### 11.1 Setup and Login

| # | Check | Expected | Result |
|---|---|---|---|
| S-01 | Backend starts without errors | `Application startup complete.` | |
| S-02 | `GET /health` returns ok | `{"status":"ok"}` | |
| S-03 | Flutter runs in Chrome with `--dart-define` flags | No startup errors | |
| S-04 | Firebase login succeeds | `idToken` returned | |
| S-05 | Backend token exchange: `user_type = "alumni"` | `{"user_type":"alumni","ref_id":"NITK2026IT001"}` | |
| S-06 | `GET /api/v1/auth/me` confirms alumni user | `user_type: alumni` | |

### 11.2 Developer Diagnostics

| # | Check | Expected | Result |
|---|---|---|---|
| D-01 | `/dev/diagnostics/registrations` returns 13 results | `"total": 13` | |
| D-02 | Check 1: Alumni Profile | `PASS`, `is_active: true` | |
| D-03 | Check 2: Test Virtual Event Setup | `PASS`, `status: "published"` | |
| D-04 | Check 3: Test Capacity Event Setup | `PASS`, `capacity: 1` | |
| D-05 | Check 4: Registration Eligibility | `PASS`, `eligibility_status: "eligible"` | |
| D-06 | Check 5: Register for Event | `PASS`, `status: "registered"` | |
| D-07 | Check 6: My Registration | `PASS`, `join_url` present | |
| D-08 | Check 7: My Registrations List | `PASS`, test registration found | |
| D-09 | Check 8: Duplicate Registration Guard | `PASS`, `409 already_registered` | |
| D-10 | Check 9: Capacity Guard | `PASS`, `409 event_full` | |
| D-11 | Check 10: Join Link Visibility | `PASS`, `join_url_present: true` | |
| D-12 | Check 11: Confirmation Email Status | `PASS`, status `sent` or `failed` | |
| D-13 | Check 12: Audit Log Check | `PASS`, audit row found | |
| D-14 | Check 13: Public API Leak Check | `PASS`, no forbidden fields | |
| D-15 | **Overall: passed == total** | `"passed": 13, "failed": 0` | |

### 11.3 Positive Use Cases

| # | Check | Expected | Result |
|---|---|---|---|
| P-01 | UC-01: Register for event 25 (physical) | HTTP 201, `join_url: null` | |
| P-02 | UC-02: Register for event 26 (virtual) | HTTP 201, `join_url` present | |
| P-03 | UC-03: My registrations list shows both | `total >= 2`, both events present | |
| P-04 | UC-11: GET /alumni/me returns active alumni | `is_active: true`, flat response | |
| P-05 | UC-13: Public events list — no forbidden fields | `virtual_url` absent | |
| P-06 | UC-14: Public event detail — no forbidden fields | `virtual_url` absent, `sessions` list present | |

### 11.4 Negative Use Cases

| # | Check | Expected | Result |
|---|---|---|---|
| N-01 | NC-01: Duplicate registration (event 25) | `409 already_registered` | |
| N-02 | NC-02: Full event registration (event 34) | `409 event_full` | |
| N-03 | NC-03: Closed registration (event 35) | `409 registration_closed` | |
| N-04 | NC-04: Registration not open (event 36) | `409 registration_not_open_yet` | |
| N-05 | NC-05: Non-alumni attempt | `403 alumni_only` | |
| N-06 | NC-06: Inactive alumni attempt | `403 alumni_not_active` | |
| N-07 | NC-07: Unauthenticated — eligibility | `401` | |
| N-08 | NC-07: Unauthenticated — POST register | `401` | |
| N-09 | NC-07: Unauthenticated — my registrations | `401` | |
| N-10 | NC-08: virtual_url absent from public API | `virtual_url present: False` | |

### 11.5 Eligibility Status Values (v2 Compliance)

| # | Check | Expected | Result |
|---|---|---|---|
| E-01 | Event 25/26 eligibility (before registering) | `eligible` | |
| E-02 | Event 25/26 eligibility (after registering) | `already_registered` | |
| E-03 | Event 34 eligibility | `full` (not `event_full`) | |
| E-04 | Event 35 eligibility | `closed` (not `registration_closed`) | |
| E-05 | Event 36 eligibility | `not_open_yet` (not `registration_not_open_yet`) | |
| E-06 | Non-alumni eligibility | `ineligible` + message field | |

### 11.6 Database Verification

| # | Check | Expected | Result |
|---|---|---|---|
| DB-01 | Registrations table has rows for test user | `registration_number` pattern correct | |
| DB-02 | `confirmation_email_status` not null | `"sent"` or `"failed"` | |
| DB-03 | Audit log has rows for test registrations | `entity_type = "registration"` | |
| DB-04 | Event 34 has 1 registered row | `registered_count = 1` | |
| DB-05 | Event 26 has `virtual_url` set in DB | `has_virtual_url = true` | |
| DB-06 | Alumni record active in alumni_db | `registrationstatus = "Active"` | |
| DB-07 | Re-registration after cancellation succeeds (partial index) | HTTP 201, two rows in registrations | |

### 11.7 Security Invariants

| # | Invariant | Verified By | Result |
|---|---|---|---|
| SEC-01 | `virtual_url` never in public API | NC-08, D-14 | |
| SEC-02 | `join_url` only for registered+virtual+published | UC-02 vs UC-01 | |
| SEC-03 | Email failure does not rollback registration | T-10 note | |
| SEC-04 | `audit_service.emit()` never raises | D-13, T-09 | |
| SEC-05 | Dev diagnostics return 404 in non-development | NC-09 | |
| SEC-06 | Authenticated endpoints reject no-token requests | N-07..N-09 | |
| SEC-07 | Cancelled registration returns `join_url: null` | SEC-07 | |
| SEC-08 | Cancelled registration excluded from `registered_count` | SEC-08 | |

### 11.8 API Integrity

| # | Check | Expected | Result |
|---|---|---|---|
| API-01 | No duplicate `registration_number` values | 0 rows from HAVING COUNT(*) > 1 | |
| API-02 | Snapshot fields unchanged after alumni_db profile update | Baseline values unchanged | |

---

### Overall Verification Result

| Section | Total | PASS | FAIL |
|---|---|---|---|
| Setup and Login | 6 | | |
| Developer Diagnostics | 15 | | |
| Positive Use Cases | 6 | | |
| Negative Use Cases | 10 | | |
| Eligibility Status v2 | 6 | | |
| Database Verification | 7 | | |
| Security Invariants | 8 | | |
| API Integrity | 2 | | |
| **TOTAL** | **60** | | |

**Week 4 GO condition:** All 60 checks PASS, or all FAIL items have documented explanations with
resolution plans in the open issues register.

---

*This guide covers Week 3 deliverables only. Attendance, QR codes, waitlist, payment,
and production Flutter registration UI are out of scope for Week 3.*

---

## 12. Week 3 UX Showcase

**Added:** 2026-06-19  
**Location:** Developer Diagnostics → Registration → Week 3 UX Showcase

The Developer Diagnostics screen has been extended into a complete Week 3 UX Demonstration
Center. All sections below are accessible in the same screen used for registration diagnostics.

### 12.1 Access

1. Build the app in debug mode: `flutter run -d chrome`
2. Navigate to **Developer Diagnostics** (long-press the app icon or via the Foundation Ready screen)
3. Open the **Registration** category (expanded by default)
4. Tap **Week 3 UX Showcase** — listed first in the category

### 12.2 Section Overview

| Section | What to Verify |
|---|---|
| §0 Run All Validation | Tap "Run All Registration Diagnostics" — expect 13/13 PASS |
| §1 Alumni Autofill | Tap "Fetch → GET /alumni/me" — profile card populates |
| §2 Eligibility | Enter event ID 25 or 26 → "Check Eligibility" → green "eligible" banner |
| §3 Registration | "Register (Dev)" → registration_number appears |
| §4 Confirmation | Populated after §3 — join_url visible for event 26, hidden for event 25 |
| §5 My Registration | Enter event ID → "Fetch My Registration" → registration card |
| §6 My Registrations | "Fetch My Registrations" → scrollable list |
| §7 Negative Gallery | Static — scroll through 9 error state cards |
| Dev Notes | Static — 7 frontend developer reference rules |
| §8a Join Link Matrix | Static table — confirm 4 rows and highlight rule |
| §8b Public Leak | Enter event ID → "Check Public Event" → expect green PASS badge |
| §9 Audit Trail | "Fetch Audit Log" → latest 8 rows from event_audit_log |
| §10 Email Demo | Populated after §3 — confirm email status card |
| §11 Snapshot Demo | Populated after §1 + §3 — side-by-side profile vs snapshot fields |
| §12 DB Rules | Static — 4 rule cards with green verification badges |

### 12.3 Expected §8b Public Leak Result

Tested with event IDs 25 and 26 (both virtual and physical):

```text
PASS — No sensitive fields leaked
(virtual_url: not present, join_url: not present, created_by_firebase_uid: not present)
```

### 12.4 Expected §9 Audit Trail

After running §3 Registration, tap "Fetch Audit Log". Expect rows with `event_type` values
such as `registration.created`, `event.status_changed` for the diagnostic test events.

### 12.5 Section §11 Snapshot Notes

If the alumni profile has `batch_year=null` or `branch=null`, the snapshot fields will
also show `null` (displayed as `—`). This is expected — null fields are preserved in snapshots.
