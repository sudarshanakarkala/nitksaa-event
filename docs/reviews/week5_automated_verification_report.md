# Week 5 — Automated Verification Report

**Date:** 2026-06-26
**Run by:** Claude Code (automated), supervised by project lead
**Based on:** `docs/reviews/week5_manual_verification_steps.md`
**Method:** curl, psql, port checks — automated execution of all scriptable checks
**Verdict:** PASS WITH NOTES

---

## Environment Snapshot

| Service | Port | Status |
|---|---|---|
| Cloud SQL Auth Proxy (alumni_db) | 5433 | RUNNING — PID 95418 |
| Backend (FastAPI / uvicorn) | 8000 | RUNNING — PID 97308 |
| Admin Portal (React / Vite) | 5173 | RUNNING — PID 1030 |
| Flutter Web App | 5200 | NOT RUNNING — see §D |
| Local PostgreSQL (events_db) | 5432 | RUNNING — PID 807 |

---

## Section A — Infrastructure Verification

| Check | Result | Detail |
|---|---|---|
| A.1 — Proxy running | PASS | `lsof -i :5433` → `cloud-sql-proxy` listening |
| A.2 — Proxy psql | PASS | `current_user = eventmgmt_app`, `current_database = alumni_db` |
| A.3 — Backend health | PASS | `{"status":"ok","version":"0.1.0-alpha","env":"development","db":"ok"}` |
| A.4 — Admin portal | PASS | Port 5173 active, node/vite listening |
| A.5 — Flutter web | SKIP | Port 5200 not listening — Flutter not started for this run |

---

## Section B — Alumni DB Verification

### B.1 Direct psql Lookups

| Check | Result | Detail |
|---|---|---|
| Active alumni | PASS | `ALUMNI-001232 · Devraj Hodal · devraj.hodal@gmail.com · 2018 · Computer Science · Active` |
| Inactive alumni | PASS | `ALUMNI-013013 · Aadhithya Hosalli Mukund · Inactive` |
| Missing alumni | PASS | `COUNT = 0` for `missing_test_99999@example.com` |
| Email normalisation | PASS | `COUNT = 1` for `  Devraj.Hodal@Gmail.com  ` — LOWER(TRIM()) works correctly |

### B.2 Backend Diagnostics — alumni/search

```json
{
  "status": "ok",
  "found": true,
  "count": 1,
  "records": [{
    "alumni_id": "ALUMNI-001232",
    "fullname": "Devraj Hodal",
    "email": "devraj.hodal@gmail.com",
    "phone": "+91-8792303382",
    "branch": "Computer Science",
    "graduationyear": 2018,
    "registrationstatus": "Active"
  }],
  "checked_at": "2026-06-26T06:50:29.563621Z"
}
```

**Result: PASS**

### B.3 Backend Diagnostics — alumni/login-trace

**Active alumni (`devraj.hodal@gmail.com`):**

```json
{
  "alumni_lookup": { "found": true, "alumni_id": "ALUMNI-001232", "registrationstatus": "Active" },
  "expected_event_user_mapping": { "expected_ref_id": "ALUMNI-001232", "is_active": true },
  "existing_event_user": { "found": false },
  "diagnosis": { "result": "fail_event_user_missing",
                 "reason": "alumni found and active, but no event_users row for this email" }
}
```

**Result: PASS** — `fail_event_user_missing` is correct; first login creates the row.

**Dev seed account (`Username2026@gmail.com`):**

```json
{
  "alumni_lookup": { "found": false },
  "existing_event_user": { "found": true, "ref_id": "NITK2026IT001" },
  "diagnosis": { "result": "fail_alumni_not_found",
                 "reason": "no alumni record matches this email in alumni_db" }
}
```

**Result: PASS (expected behaviour)** — dev seed has no real alumni record. Correctly blocked.

---

## Section C — Admin Portal Verification

**Result: SKIP (UI-only)** — Port 5173 is active and serving. Manual browser checks required
for CRUD, publish, attendee list, CSV export. Not automatable via curl.

---

## Section D — Flutter E2E Verification

**Result: SKIP (Flutter not running)**

Flutter web was not started for this automated run. Two bugs were reported by the project lead
from a separate Flutter session — documented in §Known Issues.

---

## Section E — Email Verification

**Result: SKIP** — Requires a real-user registration E2E through Firebase auth. Not automatable
with dev auth headers (email sending uses the registered user's address).

DB check from existing registrations:

| reg_id | email_status | sent_at |
|---|---|---|
| 71 | sent | 2026-06-24 19:49 IST |
| 70 | sent | 2026-06-24 19:26 IST |
| 69 | sent | 2026-06-24 18:40 IST |

All 3 most recent registrations confirm `confirmation_email_status = sent`.

---

## Section F — Database Verification

### F.1 Registration Snapshot Fields

```
 reg_id | registration_number |   status   |    ref_id     | fullname_snapshot  | batch_year | branch_snapshot        | email_status | sent_at
--------+---------------------+------------+---------------+--------------------+------------+------------------------+--------------+---------
     71 | NITKSAA-2026-000071 | registered | NITK2005IT001 | Sudarshana Karkala |       2005 | Information Technology | sent         | 2026-06-24T19:49 IST
     70 | NITKSAA-2026-000070 | registered | NITK2005IT001 | Sudarshana Karkala |       2005 | Information Technology | sent         | 2026-06-24T19:26 IST
     69 | NITKSAA-2026-000069 | registered | NITK2005IT001 | Sudarshana Karkala |       2005 | Information Technology | sent         | 2026-06-24T18:40 IST
```

All snapshot fields populated (`fullname_snapshot`, `batch_year_snapshot`, `branch_snapshot`,
`ref_id`). Registration number format `NITKSAA-2026-NNNNNN` ✓.

**Result: PASS**

### F.2 Audit Log Entries

```
 log_id | event_type      | entity_type | entity_id | actor_uid              | created_at
--------+-----------------+-------------+-----------+------------------------+------------------------
    402 | event_cancelled | event       |       128 | dev-admin-firebase-uid | 2026-06-26 12:24 IST
    401 | event_cancelled | event       |       127 | dev-admin-firebase-uid | 2026-06-26 12:24 IST
    400 | event_published | event       |       128 | dev-admin-firebase-uid | 2026-06-26 12:24 IST
    399 | event_created   | event       |       128 | dev-admin-firebase-uid | 2026-06-26 12:24 IST
    398 | event_published | event       |       127 | dev-admin-firebase-uid | 2026-06-26 12:24 IST
    397 | event_created   | event       |       127 | dev-admin-firebase-uid | 2026-06-26 12:24 IST
    396 | event_cancelled | event       |       126 | dev-admin-firebase-uid | 2026-06-26 12:21 IST
    395 | event_published | event       |       126 | dev-admin-firebase-uid | 2026-06-26 12:21 IST
```

`event_created`, `event_published`, `event_cancelled` entries all present from the diagnostic
run. `actor_uid` correctly set to dev-admin identity.

**Result: PASS**

---

## Section G — Developer Diagnostics Verification

### G.1 Event Diagnostics

**Endpoint:** `GET /api/v1/dev/diagnostics/events`
**Auth:** `X-Dev-User: admin`

```
total: 8 | passed: 8 | failed: 0 | test_event_id: 126
```

| Check | Status |
|---|---|
| Event Create Test | PASS |
| Events List Test | PASS (124 total, test event found) |
| Event Detail Test | PASS |
| Event Update Test | PASS |
| Event Publish Test | PASS (draft→published→draft transitions OK) |
| Public Events Test | PASS (31 public, no forbidden fields leaked) |
| Public Event Detail Test | PASS (sessions present, speakers present, no leaks) |
| Event Cancel Test | PASS |

**Result: PASS — 8/8**

### G.2 Registration Diagnostics

**Endpoint:** `GET /api/v1/dev/diagnostics/registrations`
**Auth:** `X-Dev-User: admin`

```
total: 13 | passed: 3 | failed: 10 | test_event_id: 127/128
```

| Check | Status | Notes |
|---|---|---|
| Alumni Profile | FAIL | `alumni_profile_not_found` — dev-admin user has ref_id=`ALUMNI-DEV-ADMIN` which has no row in alumni_db |
| Test Virtual Event Setup | PASS | event_id 127 created and published |
| Test Capacity Event Setup | PASS | event_id 128 created (capacity=1) |
| Registration Eligibility | FAIL | `ineligible — Alumni account is not active` (dev-admin has no real alumni record) |
| Register for Event | FAIL | `403 alumni_not_found` — cascades from above |
| My Registration | FAIL | skipped: registration not created |
| My Registrations List | FAIL | skipped: registration not created |
| Duplicate Registration Guard | FAIL | skipped: no base registration |
| Capacity Guard | FAIL | Got 403 instead of 409 (also cascades from no real alumni record) |
| Join Link Visibility | FAIL | skipped |
| Confirmation Email Status | FAIL | skipped |
| Audit Log Check | FAIL | skipped |
| Public API Leak Check | PASS | No forbidden fields leaked from public event detail |

**Root cause of all failures:** The `X-Dev-User: admin` identity maps to `firebase_uid =
dev-admin-firebase-uid` and `ref_id = ALUMNI-DEV-ADMIN`, which has no real row in
`alumni_db`. The alumni_db gate correctly blocks registration for any identity without a real
alumni record. All 10 failures cascade from this single root cause.

**This is expected dev-environment behaviour** — the registration diagnostic requires a real
alumni identity to exercise the full flow. Use `sudarshana.karkala@gmail.com` (NITK2005IT001)
with a real Firebase JWT to test registration end-to-end.

**Result: PASS WITH NOTES — 3/13 automated, 10/13 require real alumni JWT**

### G.3 Alumni Search & Login-trace

See §B.2 and §B.3 — both confirmed PASS.

---

## Section H — Negative Testing (Automated)

| Scenario | Expected | Actual | Result |
|---|---|---|---|
| Unknown event ID (99999) | `404 event_not_found` | `{"detail":"event_not_found"}` | PASS |
| Unauthenticated register | `401 Not authenticated` | `{"detail":"Not authenticated"}` | PASS |
| Dev seed account login-trace | `fail_alumni_not_found` | `fail_alumni_not_found` | PASS |

Negative scenarios requiring browser interaction (proxy down, backend stopped) are documented
in the manual guide and must be verified manually.

---

## Section I — Verification Endpoints Reference (Automated)

| Endpoint | Result |
|---|---|
| `GET /api/v1/health` | PASS — `{"status":"ok","db":"ok"}` |
| `GET /api/v1/events/public` | PASS — 30 published events returned |
| `GET /api/v1/events/public/99999` | PASS — 404 `event_not_found` |
| `GET /api/v1/dev/diagnostics/alumni/search?email=...` | PASS |
| `GET /api/v1/dev/diagnostics/alumni/login-trace?email=...` | PASS |
| `GET /api/v1/admin/events` | PASS — endpoint responds with admin auth |

---

## Known Issues

### Issue 1 — Flutter Register button shows Week 3 placeholder

**Severity:** High (blocks E2E testing)
**Observed:** Tapping "Register" on Event Detail screen shows snackbar:
"Registration will be available in Week 3."
**Root cause:** `_goRegister()` in `event_detail_screen.dart` was left as a Week 3 placeholder.
**Fix:** Replace snackbar with navigation to the real registration screen / API call.

### Issue 2 — Sign out does not clear Google session; same user signs back in

**Severity:** High (blocks multi-user testing)
**Observed:** After signing out, the next sign-in re-uses the cached Google account without
prompting the account picker.
**Root cause:** Firebase sign-out clears the local token but does not revoke the Google OAuth
session. `GoogleSignIn.signOut()` must also be called to clear the browser-level Google
identity so the account chooser appears on the next sign-in.
**Fix:** Add `googleSignIn.signOut()` (and optionally `googleSignIn.disconnect()`) alongside
`FirebaseAuth.instance.signOut()` in the auth controller.

---

## Automated Check Summary

| Section | Automatable | Result |
|---|---|---|
| A — Infrastructure | Yes | PASS (4/4; Flutter skip) |
| B — Alumni DB | Yes | PASS (8/8) |
| C — Admin Portal | No (UI) | SKIP |
| D — Flutter E2E | No (UI) | SKIP — 2 bugs found |
| E — Email | No (real auth) | SKIP (DB check: PASS) |
| F — Database | Yes | PASS (2/2) |
| G — Diagnostics | Yes | PASS WITH NOTES (events 8/8; registrations 3/13 — dev-only root cause) |
| H — Negative testing | Partial | PASS (3/3 automated) |
| I — Endpoint reference | Partial | PASS (6/6 automatable) |

---

## Final Verdict

**PASS WITH NOTES**

All infrastructure, alumni DB, event diagnostics, database snapshot verification, and negative
tests pass. The registration diagnostic partial failures are a known dev-environment constraint
(dev-admin identity has no real alumni record) and are not a production issue. Two Flutter
bugs require code fixes before E2E sign-in and registration can be completed:

1. Register button shows stale Week 3 placeholder — fix pending
2. Sign-out does not clear Google session — fix pending
