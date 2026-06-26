# Week 5 — Manual Verification Guide

**Date:** 2026-06-26
**Purpose:** Official manual verification guide for the full nitksaa-event local stack.
**Scope:** Infrastructure, alumni DB, admin portal, Flutter E2E, email, database, diagnostics,
negative testing.

Run the startup steps in order. Each section opens a **separate terminal tab**.

---

## Do Not Do

Before starting, read and follow these rules for every session:

- **Do not run migrations on alumni_db** — alumni_db is owned by nitksaa-portal-v2.
- **Do not write to alumni_db** — read-only consumer only.
- **Do not commit `backend/.env`** — it contains DB passwords and SMTP credentials.
- **Do not expose credentials in screenshots, reports, or chat.**
- **Do not use the Cloud SQL public IP (`34.180.35.168`) directly** unless your current outbound
  IP has been added to Cloud SQL Authorized Networks in GCP Console. The preferred local access
  method is always the **Cloud SQL Auth Proxy on port 5433**.

---

## Prerequisites

- [ ] `cloud-sql-proxy` binary present in working directory or on PATH
- [ ] `backend/.env` — `ALUMNI_DB_URL` points to proxy on port 5433 (already configured)
- [ ] Local PostgreSQL running with `events_db` database present
- [ ] Flutter SDK installed (`flutter --version`)
- [ ] Node.js installed (`node --version`)

---

## Startup — Four Terminals

### Terminal 1 — Cloud SQL Auth Proxy

Start this first. All alumni DB lookups depend on this tunnel.

```bash
./cloud-sql-proxy project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db --port 5433
```

**Expected output:**
```
Authorizing with Application Default Credentials
Listening on [::1]:5433
```

Leave this terminal running. Do not close it.

**Approved alumni DB proxy config:**

| Setting | Value |
|---|---|
| Cloud SQL instance | `project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db` |
| Proxy port | `5433` |
| DB user | `eventmgmt_app` |
| ALUMNI_DB_URL | `postgresql://eventmgmt_app:***REDACTED***@127.0.0.1:5433/alumni_db?sslmode=disable` |

> **Why `sslmode=disable`?** The Cloud SQL Auth Proxy creates an encrypted TLS tunnel between
> your machine and Cloud SQL. The PostgreSQL connection runs inside that tunnel. Adding TLS
> again at the psql layer would double-encrypt unnecessarily. `sslmode=disable` is correct and
> safe when connecting through the proxy. It must **not** be used for direct IP connections.
>
> **Direct IP note:** Connecting to `34.180.35.168:5432` directly will time out unless your
> current outbound IP is listed in Cloud SQL → Connections → Authorized Networks. Always
> prefer the proxy for local development.

**Quick proxy test (run in any other shell):**
```bash
psql "postgresql://eventmgmt_app:***REDACTED***@127.0.0.1:5433/alumni_db?sslmode=disable" \
     -c "SELECT current_database(), current_user;"
# Expected: alumni_db | eventmgmt_app
```

---

### Terminal 2 — Backend (FastAPI / uvicorn)

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/backend

source .venv/bin/activate

# Override EVENTS_DB_URL if your local PostgreSQL user is not 'postgres'.
# On this machine the local PG role is 'ananth'.
EVENTS_DB_URL="postgresql://ananth@localhost:5432/events_db" \
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Expected output:**
```
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     Application startup complete.
```

---

### Terminal 3 — Admin Portal (React / Vite)

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/admin/event_admin

npm install        # first time or after package changes only
npm run dev
```

**Expected output:**
```
VITE ready in ...ms
➜  Local:   http://localhost:5173/
```

Open **<http://localhost:5173>** in a browser.

---

### Terminal 4 — Flutter Event App

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/apps/event_app

flutter pub get    # first time or after pubspec changes only

# Web (Chrome) — backend auto-resolved to http://127.0.0.1:8000
flutter run -d chrome --web-port 5200

# iOS Simulator
flutter run -d [ios-device-id]

# Android Emulator — backend auto-resolved to http://10.0.2.2:8000
flutter run -d [android-device-id]

# Override backend URL explicitly
flutter run -d chrome \
  --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8000 \
  --web-port 5200
```

Open **<http://localhost:5200>** in a browser (Chrome run only).

---

## Add Event Organiser / Admin (events_db)

In development, admin API access uses the `X-Dev-User: admin` header — no database row is
required for API testing. For real Firebase-authenticated users, insert into `event_members`:

```bash
psql "postgresql://ananth@localhost:5432/events_db"
```

```sql
-- 1. Find firebase_uid of the user to promote
SELECT firebase_uid, email, fullname, user_type
FROM event_users
WHERE email = '<target_email>';

-- 2. Find the event_id
SELECT event_id, title, status FROM events ORDER BY event_id DESC LIMIT 10;

-- 3. Insert organiser row
INSERT INTO event_members (event_id, firebase_uid, role, status)
VALUES (<event_id>, '<firebase_uid>', 'organiser', 'active')
ON CONFLICT (event_id, firebase_uid)
DO UPDATE SET role = 'organiser', status = 'active';

-- 4. Verify
SELECT em.event_id, e.title, eu.email, em.role, em.status
FROM event_members em
JOIN events e  ON e.event_id   = em.event_id
JOIN event_users eu ON eu.firebase_uid = em.firebase_uid
ORDER BY em.joined_at DESC LIMIT 5;
```

**Current event_users in local events_db:**

| firebase_uid | email | fullname | user_type |
|---|---|---|---|
| R6rnLD2HLlPeXiWGGtqxA7TdWl53 | sudarshana.karkala@gmail.com | Sudarshana Karkala | alumni |
| 4tGxuBWNAUViVNPg6MiLUePcMLT2 | sudhan.infotech@gmail.com | Sudarshana Karkala | other |
| fxvOA6JInMM2OPKb3vuSV7qJwtI3 | username2026@gmail.com | Username Alumni | alumni |

---

## Section A — Infrastructure Verification

| Check | Command | Expected |
|---|---|---|
| Proxy running | `lsof -i :5433` | process listening |
| Proxy psql | `psql "...alumni_db..." -c "SELECT current_user;"` | `eventmgmt_app` |
| Backend health | `curl -s http://localhost:8000/api/v1/health` | `{"status":"ok","db":"ok"}` |
| Admin portal | Browser → <http://localhost:5173> | Login page or dashboard loads |
| Flutter web | Browser → <http://localhost:5200> | App loads, no console errors |

---

## Section B — Alumni DB Verification

> **Note on `DEV_DIAGNOSTICS_EMAIL` (`Username2026@gmail.com`):** This address exists in the
> local `event_users` seed but has **no record in the real alumni_db**. Diagnostics for this
> email will correctly return `fail_alumni_not_found`. This is expected — it is a local dev
> seed account only, not a real NITK alumnus.

### B.1 Direct psql lookups

**Active alumni:**
```bash
psql "postgresql://eventmgmt_app:***@127.0.0.1:5433/alumni_db?sslmode=disable" -c "
SELECT alumni_id, fullname, email, graduationyear, branch, registrationstatus
FROM alumni
WHERE lower(trim(email)) = lower(trim('devraj.hodal@gmail.com'))
LIMIT 1;"
# Expected: 1 row, registrationstatus = Active
```

**Inactive alumni:**
```bash
psql "postgresql://eventmgmt_app:***@127.0.0.1:5433/alumni_db?sslmode=disable" -c "
SELECT alumni_id, fullname, registrationstatus
FROM alumni
WHERE registrationstatus = 'Inactive'
  AND email IS NOT NULL
LIMIT 1;"
# Expected: 1 row, registrationstatus = Inactive
```

**Missing alumni:**
```bash
psql "postgresql://eventmgmt_app:***@127.0.0.1:5433/alumni_db?sslmode=disable" -c "
SELECT COUNT(*) FROM alumni
WHERE lower(trim(email)) = lower(trim('missing_test_99999@example.com'));"
# Expected: 0
```

**Email normalisation:**
```bash
psql "postgresql://eventmgmt_app:***@127.0.0.1:5433/alumni_db?sslmode=disable" -c "
SELECT COUNT(*) FROM alumni
WHERE lower(trim(email)) = lower(trim('  Devraj.Hodal@Gmail.com  '));"
# Expected: 1 — same row as the active alumni lookup
```

### B.2 Backend diagnostics — alumni/search

```bash
curl -s -H "X-Dev-User: admin" \
  "http://localhost:8000/api/v1/dev/diagnostics/alumni/search?email=devraj.hodal%40gmail.com" \
  | python3 -m json.tool
```
Expected: `"found": true`, `"registrationstatus": "Active"`

### B.3 Backend diagnostics — alumni/login-trace

```bash
# Active alumni (first login — no event_users row yet)
curl -s -H "X-Dev-User: admin" \
  "http://localhost:8000/api/v1/dev/diagnostics/alumni/login-trace?email=devraj.hodal%40gmail.com" \
  | python3 -m json.tool
# Expected: alumni_lookup.found=true, is_active=true, diagnosis=fail_event_user_missing (correct — not yet logged in)

# Dev seed account (not in real alumni_db)
curl -s -H "X-Dev-User: admin" \
  "http://localhost:8000/api/v1/dev/diagnostics/alumni/login-trace?email=Username2026%40gmail.com" \
  | python3 -m json.tool
# Expected: alumni_lookup.found=false, diagnosis=fail_alumni_not_found
```

---

## Section C — Admin Portal Verification

Open http://localhost:5173. Use Firebase/Google login with an admin account.

| Step | Action | Expected |
|---|---|---|
| C.1 | Create draft event | Form submits → event appears in list with status `draft` |
| C.2 | Publish event | Status changes to `published`; event appears in public events list |
| C.3 | Edit event | Title/description/dates update saves correctly |
| C.4 | Cancel event | Status changes to `cancelled`; cancellation banner shown in Flutter app |
| C.5 | Close registration | `registrationStatus` changes to `closed` |
| C.6 | Event summary card | All fields visible (title, dates, venue/virtual, capacity, registered count) |
| C.7 | Attendees page | List loads; shows registered attendees with snapshot fields |
| C.8 | Attendee search | Search by name or email filters the list correctly |
| C.9 | Batch year filter | Filter by graduation year returns correct subset |
| C.10 | CSV export | File downloads successfully |
| C.11 | CSV safety check | Open CSV — must **not** contain `join_url`, `virtual_url`, `qr_token`, or `firebase_uid` |

---

## Section D — Flutter E2E Verification

Open http://localhost:5200 (Chrome) or run on device.

| Step | Scenario | Expected |
|---|---|---|
| D.1 | Login (Firebase / Google) | Auth completes; alumni profile loaded |
| D.2 | Events list | Published events display correctly; pagination works |
| D.3 | Public event detail (physical) | All fields shown; no join URL visible |
| D.4 | Register for physical event | Registration succeeds; confirmation screen shown |
| D.5 | Register for virtual event | Registration succeeds; confirmation screen shown |
| D.6 | Confirmation screen | Shows registration number (`NITKSAA-YYYY-NNNNNN`) |
| D.7 | My Registrations screen | Registered events listed |
| D.8 | Join URL — virtual registered | Join URL visible on event detail after registration |
| D.9 | Join URL — physical event | No join URL shown at any point |
| D.10 | Join URL — virtual unregistered | No join URL shown before registration |
| D.11 | Already registered | Re-registration attempt shows `already_registered` message |
| D.12 | Full event | Register button disabled or shows `event_full` |
| D.13 | Registration closed | Register button shows `Registration Closed` |
| D.14 | Not open yet | Register button shows `Registration Opens Soon` |
| D.15 | Cancelled event | Cancellation banner shown prominently on event detail |

---

## Section E — Email Verification

| Step | Action | Expected |
|---|---|---|
| E.1 | Register for an event | Registration completes (201) |
| E.2 | Check inbox | Confirmation email received at registered email address |
| E.3 | DB: email status | `SELECT confirmation_email_status FROM registrations ORDER BY registered_at DESC LIMIT 1;` → `sent` |
| E.4 | DB: sent timestamp | `confirmation_email_sent_at` is populated (not NULL) |
| E.5 | SMTP failure resilience | Temporarily break SMTP config; register again; confirm registration row exists even though email failed; `confirmation_email_status = failed`; registration is **not** rolled back |

---

## Section F — Database Verification

### F.1 Registration snapshot fields

```bash
psql "postgresql://ananth@localhost:5432/events_db" -c "
SELECT
  registration_id,
  registration_number,
  status,
  ref_id,
  fullname_snapshot,
  email,
  phone,
  batch_year_snapshot,
  branch_snapshot,
  confirmation_email_status,
  confirmation_email_sent_at
FROM registrations
ORDER BY registered_at DESC
LIMIT 5;"
```

Expected for each row:

- `registration_number` — `NITKSAA-YYYY-NNNNNN` format, not NULL
- `fullname_snapshot` — alumni name from alumni_db at registration time, not NULL
- `batch_year_snapshot` — graduation year integer, not NULL
- `branch_snapshot` — branch string, not NULL
- `ref_id` — alumni_id from alumni_db, not NULL
- `email` — alumni email, not NULL
- `confirmation_email_status` — `sent`, `failed`, or `skipped` (not `pending` after processing)
- `confirmation_email_sent_at` — timestamp, not NULL if status is `sent`

### F.2 Audit log entries

```bash
psql "postgresql://ananth@localhost:5432/events_db" -c "
SELECT log_id, event_type, entity_type, entity_id, actor_uid, context, created_at
FROM event_audit_log
ORDER BY created_at DESC
LIMIT 10;"
```

Expected entries (at minimum):

- Event created — `event_type` contains `created`
- Event published — `event_type` contains `published`
- Registration created — `entity_type` = `registration`, `context` contains `registration_number`
- Email sent/failed — audit entry or `context` reflects email outcome

### F.3 Attendee export row count

```bash
# Count registered attendees for a specific event
psql "postgresql://ananth@localhost:5432/events_db" -c "
SELECT COUNT(*) FROM registrations
WHERE event_id = <event_id> AND status = 'registered';"
# This count must match the number of rows in the CSV export from the Admin Portal.
```

---

## Section G — Developer Diagnostics Verification

Use the developer diagnostics screen in the Flutter app or via curl.

| Check | Endpoint | Expected |
|---|---|---|
| Event diagnostics | `GET /api/v1/dev/diagnostics/events` | Runs 8 event management checks (creates/cancels a test event); all checks PASS |
| Registration diagnostics | `GET /api/v1/dev/diagnostics/registrations` | Runs 13 registration flow checks; all checks PASS |
| Attendee diagnostics | `GET /api/v1/dev/diagnostics/attendees?event_id=<id>` | Runs 10 attendee management checks; `event_id` query param required |
| Alumni search | `GET /api/v1/dev/diagnostics/alumni/search?email=...` | `"found": true` for known active alumni; status shown as `Active` |
| Alumni login-trace | `GET /api/v1/dev/diagnostics/alumni/login-trace?email=...` | Full login trace with `diagnosis` field |

All diagnostics endpoints require `X-Dev-User: admin` header in development mode.

---

## Section H — Error and Negative Testing

| Scenario | How to trigger | Expected behaviour |
|---|---|---|
| Backend stopped | `Ctrl+C` in Terminal 2 | Flutter shows network error with Retry button |
| Proxy stopped | `Ctrl+C` in Terminal 1 | Alumni lookup fails gracefully; no crash; error message shown |
| Invalid event ID | `GET /api/v1/events/public/99999` | 404 response; Flutter shows "Event not found" screen |
| Missing alumni | Login with email not in alumni_db | Login blocked; `fail_alumni_not_found` |
| Inactive alumni | Login with Inactive alumni email | Login blocked; registration not permitted |
| Duplicate registration | Register for same event twice | `already_registered` error; second row not created |
| Capacity full | Register when `registered_count >= capacity` | `event_full` response; button disabled in Flutter |
| Registration closed | Register when `registrationStatus = closed` | `registration_closed` response |
| Session expired / invalid token | Use an expired JWT | 401 returned; Flutter returns user to login or shows friendly error |

---

## Section I — Verification Endpoints Reference

| Purpose | Method | Endpoint | Auth |
|---|---|---|---|
| Health check | GET | `/api/v1/health` | None |
| Public events (upcoming) | GET | `/api/v1/events/public?period=upcoming` | None |
| Public event detail | GET | `/api/v1/events/public/{id}` | None |
| Admin events list | GET | `/api/v1/admin/events` | `X-Dev-User: admin` |
| Dev event list (paginated) | GET | `/api/v1/events?page=1&per_page=20` | `X-Dev-User: admin` |
| Create draft event | POST | `/api/v1/admin/events` | `X-Dev-User: admin` |
| Publish event | POST | `/api/v1/admin/events/{id}/publish` | `X-Dev-User: admin` |
| Admin attendees | GET | `/api/v1/admin/events/{id}/attendees` | `X-Dev-User: admin` |
| Attendee CSV export | GET | `/api/v1/admin/events/{id}/attendees/export` | `X-Dev-User: admin` |
| Alumni search | GET | `/api/v1/dev/diagnostics/alumni/search?email=...` | `X-Dev-User: admin` |
| Alumni login-trace | GET | `/api/v1/dev/diagnostics/alumni/login-trace?email=...` | `X-Dev-User: admin` |
| Register for event | POST | `/api/v1/events/{id}/register` | Bearer JWT |
| My registrations | GET | `/api/v1/my/registrations` | Bearer JWT |

---

## Section J — Final Validation Reports to Create

After completing all sections above, create these three report files:

| Report | Path |
|---|---|
| Cloud DB validation | `docs/reviews/week5_cloud_db_validation_report.md` *(already created)* |
| Flutter E2E validation | `docs/reviews/week5_flutter_e2e_validation_report.md` |
| Admin portal validation | `docs/reviews/week5_admin_portal_validation_report.md` |

Each report must include: date, environment, tester, section results (PASS / FAIL / SKIP per
item), issues found, and final verdict.

---

## Quick Reference — Port Map

| Service | Port | URL |
|---|---|---|
| Cloud SQL Proxy (alumni_db) | 5433 | `127.0.0.1:5433` |
| Local PostgreSQL (events_db) | 5432 | `localhost:5432` |
| Backend API | 8000 | <http://localhost:8000> |
| Admin Portal (React) | 5173 | <http://localhost:5173> |
| Flutter Web App | 5200 | <http://localhost:5200> |

---

## Quick Reference — Dev Auth Headers

| Header value | Role | Permissions |
|---|---|---|
| `X-Dev-User: admin` | Admin | create, update, checkin, export |
| `X-Dev-User: attendee` | Attendee | register only |

Only active when `APP_ENV=development`. Rejected in production.

---

## Pass / Fail Criteria

### PASS

All of the following must be true:

- [ ] Backend health returns `{"status":"ok","db":"ok"}`
- [ ] Alumni DB proxy lookup returns correct active alumni record
- [ ] Admin portal starts and all CRUD operations work
- [ ] Flutter registration E2E completes: login → event detail → register → confirmation screen
- [ ] Confirmation email received in inbox; `confirmation_email_status = sent` in DB
- [ ] All four snapshot fields populated: `fullname_snapshot`, `batch_year_snapshot`, `branch_snapshot`, `ref_id`
- [ ] Developer diagnostics report PASS for all checks
- [ ] CSV export does not contain `join_url`, `virtual_url`, `qr_token`, or `firebase_uid`

### PASS WITH NOTES

Core registration flow works, but one or more of the following are pending:

- Optional negative-case scenarios not yet tested
- Additional browser or device checks pending
- Non-critical UI/UX issues noted but not blocking

### FAIL

Any one of the following:

- Alumni DB lookup fails (proxy down or credentials wrong)
- Registration fails (any step: login, register call, confirmation)
- Snapshot fields are NULL on registration rows
- Join URL exposed to unauthenticated users or non-registered physical event attendees
- Admin attendee CSV export fails or contains sensitive fields
- Backend or Flutter app cannot start

---

## Shutdown Order

Stop in this order to avoid connection errors in logs:

1. Flutter (`Ctrl+C` in Terminal 4)
2. Admin Portal (`Ctrl+C` in Terminal 3)
3. Backend (`Ctrl+C` in Terminal 2)
4. Cloud SQL Proxy (`Ctrl+C` in Terminal 1) — **always stop last**
