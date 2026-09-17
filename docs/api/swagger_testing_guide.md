# NITKSAA Event App — Swagger Testing Guide

**Version:** 1.1  
**Date:** 2026-06-19  
**Status:** Week 1–3 API Testing Guide  
**Source of Truth:**
- Swagger UI: `/docs` → `http://localhost:8000/docs`
- OpenAPI JSON: `/openapi.json` → `http://localhost:8000/openapi.json`
- `docs/api/backend_api_index_v2.md`
- `docs/api/events_api_contract_v2.md`
- `docs/api/week3_actual_api_response_shapes.md`

---

## Intended Audience

| Role | How to use this guide |
|---|---|
| Frontend developer | Verify API contracts before integrating |
| Backend developer | Confirm endpoint behaviour matches spec |
| QA / testing team | Run all positive and negative test cases |
| Product owner | Visually confirm flows without code |
| New developer onboarding | Learn the API surface from a single document |

---

## Endpoint Inventory Summary

| Week | Endpoint Count | Status |
|---|---|---|
| Week 1 | 3 | Implemented |
| Week 2 | 7 | Implemented |
| Week 3 | 6 | Implemented |
| Developer Diagnostics | Existing dev-only endpoints | Implemented |
| Week 4 | 2 | Planned |
| **Total Implemented** | **19** | **Week 1–3** |

---

## Role / Access Matrix

| Endpoint | Public | Alumni | Admin | Dev Only |
|---|---|---|---|---|
| `GET /api/v1/health` | Yes | Yes | Yes | No |
| `POST /api/v1/auth/firebase` | Yes | Yes | Yes | No |
| `GET /api/v1/auth/me` | No | Yes | Yes | No |
| `GET /api/v1/events/public` | Yes | Yes | Yes | No |
| `GET /api/v1/events/public/{event_id}` | Yes | Yes | Yes | No |
| `POST /api/v1/events` | No | No | Yes | No |
| `GET /api/v1/events` | No | No | Yes | No |
| `GET /api/v1/events/{event_id}` | No | No | Yes | No |
| `PATCH /api/v1/events/{event_id}` | No | No | Yes | No |
| `PATCH /api/v1/events/{event_id}/status` | No | No | Yes | No |
| `GET /api/v1/alumni/me` | No | Yes | No (unless mapped as alumni) | No |
| `GET /api/v1/events/{event_id}/registration-eligibility` | No | Yes | No | No |
| `POST /api/v1/events/{event_id}/register` | No | Yes | No | No |
| `GET /api/v1/events/{event_id}/my-registration` | No | Yes | No | No |
| `GET /api/v1/my/registrations` | No | Yes | No | No |
| `GET /api/v1/dev/diagnostics/*` | No | Authorized dev/test user | Authorized dev/test admin | Yes |

> "Admin" requires a backend JWT from a user with admin/staff `user_type`.  
> "Alumni" requires a backend JWT from a user with `user_type = "alumni"` and a valid `ref_id`.  
> "Dev Only" — these endpoints return `404` when `APP_ENV != "development"`.

---

## 1. What Is Swagger?

Swagger UI is the live API test page generated automatically by FastAPI from the backend source code.

- It allows you to run APIs directly from a browser — no Postman or curl needed
- It shows request schema, response schema, and expected status codes for every endpoint
- It reflects the actual backend routes — if an endpoint exists, it appears in Swagger; if it doesn't, it's absent
- The Swagger page at `http://localhost:8000/docs` is always in sync with the running backend
- This markdown guide explains the business rules, test scenarios, and expected data — use both together

> **Rule:** When Swagger/openapi.json and a markdown doc disagree, the backend source code is the final source of truth. Update the markdown doc if a confirmed mismatch is found.

---

## 2. Start the Backend

Run the backend before opening Swagger:

```bash
cd backend
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Verify these URLs are accessible:

| URL | Purpose |
|---|---|
| `http://localhost:8000/health` | Quick DB + version check |
| `http://localhost:8000/docs` | Swagger UI (interactive test page) |
| `http://localhost:8000/redoc` | ReDoc (read-only reference, better for printing) |
| `http://localhost:8000/openapi.json` | Raw OpenAPI spec (used by Swagger UI) |

Expected `/health` response:

```json
{
  "status": "ok",
  "version": "1.0.0",
  "env": "development",
  "db": "ok"
}
```

If `db` shows an error string instead of `"ok"`, the backend cannot reach the database. Fix `DATABASE_URL` in `.env` before testing.

---

## 3. Swagger URLs

### Swagger UI — `http://localhost:8000/docs`

Use for: interactive testing — expand an endpoint, click **Try it out**, fill in fields, and click **Execute**.

### ReDoc — `http://localhost:8000/redoc`

Use for: reading the full API reference in a clean format. No interactive testing — documentation only.

### OpenAPI JSON — `http://localhost:8000/openapi.json`

Use for: importing into Postman, generating client SDKs, or diffing the spec across branches.

---

## 4. How to Authorize in Swagger

Swagger does not accept an email and password directly. It requires a backend JWT (access token).

**Authorization flow:**

```text
Firebase Login
  → Firebase returns: idToken
  → POST /api/v1/auth/firebase  with body: {"token": "<firebase_idToken>"}
  → Backend returns: access_token
  → Swagger Authorize: paste access_token (NOT the Firebase idToken)
```

> Swagger's **Authorize** button accepts the backend `access_token`, not the Firebase `idToken`.
> These are two different tokens. Do not confuse them.

---

### Option A — Get Backend JWT from Flutter Developer Diagnostics (Recommended for Quick Testing)

1. Start Flutter with dev credentials:

```bash
cd apps/event_app
flutter run -d chrome \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=UUsername2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

2. Log in with the dev account.
3. Open **Developer Diagnostics** from the app menu.
4. Run the **Backend Auth Test** or **/auth/me Test** check.
5. If the token is displayed in the results, copy the `access_token` value.
6. In Swagger, click the **Authorize** button (top right of the page).
7. Paste only the token value — do **not** include the word `Bearer`.
8. Click **Authorize**, then **Close**.

---

### Option B — Firebase REST API then Backend Exchange (Advanced)

Use this when Flutter is not running or for automated token generation.

**Step 1 — Get Firebase ID token via REST:**

```bash
FIREBASE_API_KEY="your-firebase-web-api-key"

curl -s -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "UUsername2026@gmail.com",
    "password": "Password2026",
    "returnSecureToken": true
  }'
```

From the response, copy the `idToken` field value.

**Step 2 — Exchange for backend JWT using Swagger:**

1. In Swagger, expand `POST /api/v1/auth/firebase`
2. Click **Try it out**
3. Enter the request body:

```json
{
  "token": "<paste_firebase_idToken_here>"
}
```

4. Click **Execute**
5. From the response, copy the `access_token` value

**Step 3 — Authorize Swagger:**

1. Click **Authorize** (top right)
2. Paste the backend `access_token` (not the Firebase `idToken`)
3. Click **Authorize**, then **Close**

---

## 5. Test Account

```text
Email:           UUsername2026@gmail.com
Password:        Password2026
Firebase UID:    fxvOA6JInMM2OPKb3vuSV7qJwtI3
Alumni ref_id:   NITK2026IT001
user_type:       alumni
alumni_db:       Active (eligible to register)
```

> If this user logs in as `user_type = "other"` instead of `"alumni"`, check:
> - `ALUMNI_DB_URL` is set in `.env` and pointing to `alumni_db`
> - The email `UUsername2026@gmail.com` is mapped in `event_users` with a non-null `ref_id`
> - The corresponding record exists in `alumni_db.alumni` with `registrationstatus` in `{'Active', 'Self-Verified'}`

---

## 6. Test Event IDs

| event_id | Type | Status | Condition |
|---|---|---|---|
| 25 | Physical | Published | Registration open |
| 26 | Virtual | Published | Registration open |
| 34 | Any | Published | **Full** — `registered_count >= capacity` |
| 35 | Any | Published | **Closed** — past `registration_closes_at` |
| 36 | Any | Published | **Not open yet** — before `registration_opens_at` |

> If these event IDs do not exist in your local database, use equivalent published test events
> or recreate them following the SQL in `docs/validation/backend_week3_manual_verification_guide_v2.md §10`.

---

## 7. Week 1 — Foundation and Authentication

### Goal

Backend is running. Firebase login exchange works. Backend JWT works. All protected endpoints reject unauthenticated requests.

### Endpoints

| API | Auth | Expected |
|---|---|---|
| `GET /api/v1/health` | None | 200 OK |
| `POST /api/v1/auth/firebase` | Firebase token in body | 200 OK + backend JWT |
| `GET /api/v1/auth/me` | Backend JWT | 200 OK + user profile |

---

### W1-P1 — Health Check

1. Expand `GET /api/v1/health`
2. Click **Try it out** → **Execute**

Expected:

```json
{
  "status": "ok",
  "version": "1.0.0",
  "env": "development",
  "db": "ok"
}
```

PASS criteria:
- HTTP 200
- `status = "ok"`
- `db = "ok"` (or an error string if DB is intentionally down — this is a diagnostic field, not a hard failure)

---

### W1-P2 — Firebase Token Exchange

1. Expand `POST /api/v1/auth/firebase`
2. Click **Try it out**
3. Enter:

```json
{
  "token": "<firebase_id_token>"
}
```

4. Click **Execute**

Expected:

```json
{
  "status": "ok",
  "access_token": "<backend_jwt>",
  "token_type": "bearer",
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "user_type": "alumni",
  "fullname": "Username Alumni",
  "ref_id": "NITK2026IT001",
  "graduation_year": 2026
}
```

PASS criteria:
- `access_token` is present and non-empty
- `user_type = "alumni"`
- `ref_id` is present and matches alumni record

---

### W1-P3 — Auth Me

Precondition: Swagger is authorized (see §4).

1. Click **Authorize** and paste backend JWT
2. Expand `GET /api/v1/auth/me`
3. Click **Try it out** → **Execute**

Expected:

```json
{
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "email": "username2026@gmail.com",
  "fullname": "Username Alumni",
  "user_type": "alumni",
  "ref_id": "NITK2026IT001",
  "graduation_year": 2026
}
```

PASS criteria:
- HTTP 200
- `user_type = "alumni"`
- `ref_id` present

---

### W1-N1 — Protected Endpoint Without Auth

Clear Swagger authorization (click **Authorize** → **Logout** → **Close**).

Call `GET /api/v1/auth/me`.

Expected: HTTP 401

PASS criteria: Endpoint rejects unauthenticated request.

---

### W1-N2 — Invalid Firebase Token

Call `POST /api/v1/auth/firebase` with:

```json
{
  "token": "invalid-token-string"
}
```

Expected: HTTP 401 or 403

PASS criteria: No `access_token` returned.

---

## 8. Week 2 — Event Management and Public Events

### Goal

Admin can create, update, publish, and cancel events. Public users can browse published events. Admin-only endpoints reject unauthenticated calls.

### Endpoints

**Public (no auth):**

| API | Auth | Expected |
|---|---|---|
| `GET /api/v1/events/public` | None | Published events only |
| `GET /api/v1/events/public/{event_id}` | None | One published event (wrapped) |

**Admin (JWT required):**

| API | Auth | Expected |
|---|---|---|
| `POST /api/v1/events` | Backend JWT | Create event as draft |
| `GET /api/v1/events` | Backend JWT | List all events (all statuses) |
| `GET /api/v1/events/{event_id}` | Backend JWT | Full event detail |
| `PATCH /api/v1/events/{event_id}` | Backend JWT | Update event fields |
| `PATCH /api/v1/events/{event_id}/status` | Backend JWT | Publish / unpublish / cancel |

---

### W2-P1 — Public Event List

1. Expand `GET /api/v1/events/public`
2. Click **Try it out**
3. Set: `page = 1`, `per_page = 20`, `period = upcoming`
4. Click **Execute**

Expected:

```json
{
  "events": [
    {
      "event_id": 26,
      "title": "Webinar on AI",
      "status": "published",
      "is_virtual": true,
      "registered_count": 1,
      "registration_status": "open"
    }
  ],
  "total": 1,
  "page": 1,
  "per_page": 20
}
```

PASS criteria:
- HTTP 200
- Only `status = "published"` events appear
- No `virtual_url` field in any item
- No `join_url` field in any item
- No `created_by_firebase_uid` field in any item

---

### W2-P2 — Public Event Detail (Wrapped Response)

1. Expand `GET /api/v1/events/public/{event_id}`
2. Enter `event_id = 26`
3. Click **Execute**

Expected shape — note the `event` wrapper:

```json
{
  "event": {
    "event_id": 26,
    "title": "Webinar on AI",
    "status": "published",
    "is_virtual": true,
    "sessions": [],
    "speakers": []
  }
}
```

PASS criteria:
- HTTP 200
- Response has top-level `event` key (not flat)
- Access fields as `response.event.title`, not `response.title`
- No `virtual_url` field
- No `join_url` field
- No `created_by_firebase_uid` field

---

### W2-N1 — Public Event Detail Not Found

Use a draft, cancelled, or non-existent event ID (e.g., `event_id = 9999`).

Expected:

```json
{
  "detail": "event_not_found"
}
```

HTTP 404.

---

### W2-P3 — Admin Create Event

Precondition: Swagger authorized with admin backend JWT.

1. Expand `POST /api/v1/events`
2. Click **Try it out**
3. Enter:

```json
{
  "title": "Swagger Test Event",
  "description": "Created from Swagger testing guide",
  "is_virtual": false,
  "location_text": "NITK Surathkal",
  "location_maps_url": null,
  "virtual_url": null,
  "capacity": 50,
  "start_datetime": "2026-08-01T09:00:00Z",
  "end_datetime": "2026-08-01T11:00:00Z",
  "timezone": "Asia/Kolkata",
  "registration_opens_at": null,
  "registration_closes_at": null
}
```

4. Click **Execute**

Expected:

```json
{
  "status": "ok",
  "event": {
    "event_id": 40,
    "status": "draft",
    "title": "Swagger Test Event"
  }
}
```

PASS criteria:
- HTTP 201
- `event.status = "draft"`
- `event.event_id` is assigned (note it for W2-P4 and W2-P5)

---

### W2-P4 — Admin Publish Event

Use the `event_id` from W2-P3.

1. Expand `PATCH /api/v1/events/{event_id}/status`
2. Enter the `event_id`
3. Body:

```json
{
  "status": "published"
}
```

Expected:

```json
{
  "status": "ok",
  "event": {
    "event_id": 40,
    "status": "published",
    "registration_status": "open"
  }
}
```

PASS criteria:
- HTTP 200
- `event.status = "published"`
- Event now appears in `GET /api/v1/events/public`

---

### W2-P5 — Admin Update Event

Use the same `event_id` from W2-P3.

1. Expand `PATCH /api/v1/events/{event_id}`
2. Body:

```json
{
  "description": "Updated from Swagger",
  "capacity": 60
}
```

Expected:
- HTTP 200
- `event.capacity = 60`

---

### W2-P6 — Admin Cancel Event

Use the same `event_id`.

1. Expand `PATCH /api/v1/events/{event_id}/status`
2. Body:

```json
{
  "status": "cancelled"
}
```

Expected:
- HTTP 200
- `event.status = "cancelled"`
- Event no longer appears in `GET /api/v1/events/public`

> There is no `DELETE /api/v1/events/{event_id}` endpoint. Cancellation is the only way to
> remove an event from public view. Hard deletes are not supported.

---

### W2-N2 — Admin Endpoints Without JWT

Clear Swagger authorization.

Try each of these without auth:
- `POST /api/v1/events`
- `GET /api/v1/events`
- `PATCH /api/v1/events/{event_id}`

Expected: HTTP 401 or 403 for all.

PASS criteria: Admin endpoints are protected.

---

### W2-N3 — Invalid Event Dates

1. Expand `POST /api/v1/events`
2. Body with `end_datetime` before `start_datetime`:

```json
{
  "title": "Bad Date Event",
  "description": "Invalid",
  "is_virtual": false,
  "location_text": "NITK",
  "capacity": 50,
  "start_datetime": "2026-08-01T12:00:00Z",
  "end_datetime": "2026-08-01T10:00:00Z",
  "timezone": "Asia/Kolkata"
}
```

Expected: HTTP 422 or 400

PASS criteria: Backend rejects `end_datetime <= start_datetime`.

---

### W2-N4 — Invalid Capacity

Try creating an event with `capacity = 0` or `capacity = -1`.

Expected: HTTP 422 or 400

PASS criteria: Backend rejects non-positive capacity.

---

## Registration State Diagram

Before testing Week 3, understand the possible registration states:

```text
                        ┌─────────────────────┐
                        │  Check Eligibility   │
                        │  GET /eligibility    │
                        └──────────┬──────────┘
                                   │
                   ┌───────────────┴───────────────────┐
                   │ eligible                           │ blocked
                   ▼                                   ▼
         ┌──────────────────┐              ┌─────────────────────────┐
         │ POST /register   │              │ Blocked states:         │
         └────────┬─────────┘              │  already_registered     │
                  │ HTTP 201               │  full                   │
                  ▼                        │  closed                 │
         ┌──────────────────┐              │  not_open_yet           │
         │  status:         │              │  ineligible             │
         │  "registered"    │              └─────────────────────────┘
         └────────┬─────────┘
                  │
         ┌────────┴─────────┐
         │ (future cancel)  │
         ▼                  │
  status: "cancelled"       │
  (soft-delete, retained)   │
                            │
              ┌─────────────┘
              │
              ▼
  GET /my-registration
  GET /my/registrations
  → show join_url if:
      status="registered"
      AND event.is_virtual=true
      AND event.status="published"
```

**Two-code rule:** `eligibility_status` values (GET eligibility) differ from POST `/register` error `detail` codes:

| Eligibility GET value | POST error `detail` | Meaning |
|---|---|---|
| `full` | `event_full` | Capacity reached |
| `closed` | `registration_closed` | Past deadline |
| `not_open_yet` | `registration_not_open_yet` | Too early |
| `ineligible` | `alumni_only` or `alumni_not_active` | Not eligible alumni |
| `already_registered` | `already_registered` | Same in both |

---

## 9. Week 3 — Registration, Alumni Autofill, Confirmation Email, Join Link

### Goal

Alumni can register for events. Confirmation email is tracked. Join link is revealed only to registered alumni for virtual events. Public APIs never expose the join link.

### Endpoints

| API | Auth | Expected |
|---|---|---|
| `GET /api/v1/alumni/me` | Backend JWT | Alumni profile |
| `GET /api/v1/events/{event_id}/registration-eligibility` | Backend JWT | Eligibility status |
| `POST /api/v1/events/{event_id}/register` | Backend JWT | Registration (201) |
| `GET /api/v1/events/{event_id}/my-registration` | Backend JWT | Registration detail |
| `GET /api/v1/my/registrations` | Backend JWT | All registrations |
| `GET /api/v1/dev/diagnostics/registrations` | Backend JWT (dev only) | 13 automated checks |

---

### W3-P1 — Alumni Profile

Precondition: Swagger authorized.

1. Expand `GET /api/v1/alumni/me`
2. Click **Try it out** → **Execute**

Expected:

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

PASS criteria:
- HTTP 200
- `is_active = true`
- `ref_id` matches test account

---

### W3-N1 — Alumni Profile Without Auth

Clear authorization. Call `GET /api/v1/alumni/me`.

Expected: HTTP 401

---

### W3-P2 — Registration Eligibility (Eligible)

1. Expand `GET /api/v1/events/{event_id}/registration-eligibility`
2. Enter `event_id = 25`
3. Execute

Expected:

```json
{
  "event_id": 25,
  "eligibility_status": "eligible",
  "message": "You are eligible to register.",
  "registered_count": 0,
  "capacity": 50
}
```

PASS criteria:
- HTTP 200 (always — eligibility endpoint never returns 4xx)
- `eligibility_status = "eligible"`

> `eligibility_status` values and POST `/register` error `detail` codes are different.
> See the cross-reference table in `docs/api/events_api_contract_v2.md`.

---

### W3-P3 — Register Physical Event

1. Expand `POST /api/v1/events/{event_id}/register`
2. Enter `event_id = 25`
3. Body:

```json
{
  "attendee_note": "Testing from Swagger"
}
```

4. Execute

Expected:

```json
{
  "registration_id": 5,
  "registration_number": "NITKSAA-2026-000005",
  "event_id": 25,
  "status": "registered",
  "join_url": null,
  "confirmation_email_status": "sent",
  "event": {
    "is_virtual": false
  }
}
```

PASS criteria:
- HTTP 201
- `status = "registered"` (never `"confirmed"`)
- `join_url = null` (physical event — no join link)
- `confirmation_email_status` is `"sent"`, `"failed"`, or `"skipped"` — never a boolean
- `registration_number` follows format `NITKSAA-{year}-{id:06d}`

---

### W3-P4 — Register Virtual Event

1. Expand `POST /api/v1/events/{event_id}/register`
2. Enter `event_id = 26`
3. Body: `{}` (empty is valid — `attendee_note` is optional)
4. Execute

Expected:

```json
{
  "registration_number": "NITKSAA-2026-000006",
  "status": "registered",
  "join_url": "https://meet.google.com/nitksaa-demo-webinar",
  "confirmation_email_status": "sent",
  "event": {
    "event_id": 26,
    "is_virtual": true
  }
}
```

PASS criteria:
- HTTP 201
- `join_url` is non-null
- `event.is_virtual = true` — note: `is_virtual` is inside the nested `event` object, not at the top level

---

### W3-P5 — My Registration Detail

1. Expand `GET /api/v1/events/{event_id}/my-registration`
2. Enter `event_id = 26`
3. Execute

Expected:

```json
{
  "registration_number": "NITKSAA-2026-000006",
  "status": "registered",
  "join_url": "https://meet.google.com/nitksaa-demo-webinar",
  "event": {
    "event_id": 26,
    "is_virtual": true
  }
}
```

PASS criteria:
- HTTP 200
- `join_url` visible for registered virtual event

---

### W3-P6 — My Registrations List

1. Expand `GET /api/v1/my/registrations`
2. Execute

Expected:

```json
{
  "registrations": [
    {
      "registration_number": "NITKSAA-2026-000006",
      "status": "registered",
      "join_url": "https://meet.google.com/nitksaa-demo-webinar",
      "event": {
        "event_id": 26,
        "is_virtual": true
      }
    },
    {
      "registration_number": "NITKSAA-2026-000005",
      "status": "registered",
      "join_url": null,
      "event": {
        "event_id": 25,
        "is_virtual": false
      }
    }
  ],
  "total": 2
}
```

PASS criteria:
- `registrations` list present
- Event 26 (virtual): `join_url` is non-null
- Event 25 (physical): `join_url` is null

---

### W3-P7 — Registration Diagnostics (13-Check Suite)

1. Expand `GET /api/v1/dev/diagnostics/registrations`
2. Execute

Expected:

```json
{
  "status": "ok",
  "category": "Registration Flow",
  "total": 13,
  "passed": 13,
  "failed": 0,
  "results": [ ... ]
}
```

PASS criteria: 13/13 passed

> This endpoint is only available when `APP_ENV = "development"`. It returns HTTP 404 in production.

---

### W3-N2 — Duplicate Registration

Register for event 25 again (already done in W3-P3).

Expected:

```json
{
  "detail": "already_registered"
}
```

HTTP 409.

Eligibility equivalent for same state: `"eligibility_status": "already_registered"`

---

### W3-N3 — Event Full

1. Expand `POST /api/v1/events/{event_id}/register`
2. Enter `event_id = 34` (full event)
3. Execute

Expected:

```json
{
  "detail": "event_full"
}
```

HTTP 409.

Eligibility equivalent: `"eligibility_status": "full"`

---

### W3-N4 — Registration Closed

1. Enter `event_id = 35` (closed event)
2. Execute

Expected:

```json
{
  "detail": "registration_closed"
}
```

HTTP 409.

Eligibility equivalent: `"eligibility_status": "closed"`

---

### W3-N5 — Registration Not Open Yet

1. Enter `event_id = 36` (not open yet)
2. Execute

Expected:

```json
{
  "detail": "registration_not_open_yet"
}
```

HTTP 409.

Eligibility equivalent: `"eligibility_status": "not_open_yet"`

---

### W3-N6 — Non-Alumni User

Obtain a backend JWT for a non-alumni user (one with `user_type = "other"`). Authorize Swagger with that token.

Try `POST /api/v1/events/25/register`.

Expected:

```json
{
  "detail": "alumni_only"
}
```

HTTP 403.

Eligibility equivalent: `"eligibility_status": "ineligible"` with message explaining the reason.

---

### W3-N7 — Inactive Alumni

Obtain a backend JWT for an alumni account where `registrationstatus NOT IN ('Active', 'Self-Verified')` in `alumni_db`.

Try `POST /api/v1/events/25/register`.

Expected:

```json
{
  "detail": "alumni_not_active"
}
```

HTTP 403.

Eligibility equivalent: `"eligibility_status": "ineligible"`

---

### W3-N8 — Public API Leak Check (Security)

Without authorization (or with any token — public endpoint ignores auth):

1. Expand `GET /api/v1/events/public/{event_id}`
2. Enter `event_id = 26` (virtual event)
3. Execute

Check the response carefully.

PASS criteria — none of these fields must appear:
- `virtual_url`
- `join_url`
- `created_by_firebase_uid`

FAIL if any of the above appear in the response object.

---

### W3-N9 — Dev Diagnostics Hidden in Production

If the backend is running with `APP_ENV = "production"`:

Call `GET /api/v1/dev/diagnostics/registrations`.

Expected: HTTP 404

PASS criteria: Diagnostics endpoint is not accessible outside development.

---

## 10. Week 4 — Planned (TO BE DONE)

### Goal

Admin can view and manage attendees for each event.

### Planned Endpoints

| API | Status |
|---|---|
| `GET /api/v1/events/{event_id}/attendees` | Planned — Week 4 |
| `GET /api/v1/events/{event_id}/attendees/export` | Planned — Week 4 |
| Admin registration search by name | Planned — Week 4 |
| Batch year filter | Planned — Week 4 |
| CSV export | Planned — Week 4 |
| Attendance tracking / QR check-in | Not Week 4 unless separately approved |

### Current Swagger State for Week 4 Endpoints

These endpoints may not appear in Swagger at all, or they may return:

```json
{
  "detail": "Not Implemented"
}
```

HTTP 501.

> Do not treat Week 4 attendee endpoint failures as Week 3 bugs. These are intentionally
> deferred. The backend database schema and registration table are already in place;
> only the API layer is pending.

### Week 4 Test Placeholder

| ID | API | Expected |
|---|---|---|
| W4-P1 | `GET /api/v1/events/{event_id}/attendees` | TO BE DONE |
| W4-P2 | `GET /api/v1/events/{event_id}/attendees/export` | TO BE DONE |

---

## API Coverage Summary

```text
Implemented APIs:          19
Active Swagger test cases: 32
Positive tests:            14
Negative tests:            16
Security tests:             2
Week 4 planned placeholders: 2
Total rows in checklist:   34
```

---

## 11. Final Swagger Test Checklist

Use this table to record results during a test session.

| ID | Week | API | Type | Expected | Actual | PASS/FAIL | Notes |
|---|---|---|---|---|---|---|---|
| W1-P1 | 1 | GET /api/v1/health | Positive | HTTP 200, status=ok, db=ok | | | |
| W1-P2 | 1 | POST /api/v1/auth/firebase | Positive | HTTP 200, access_token present, user_type=alumni | | | |
| W1-P3 | 1 | GET /api/v1/auth/me | Positive | HTTP 200, user_type=alumni | | | |
| W1-N1 | 1 | GET /api/v1/auth/me (no auth) | Negative | HTTP 401 | | | |
| W1-N2 | 1 | POST /api/v1/auth/firebase (invalid token) | Negative | HTTP 401 or 403 | | | |
| W2-P1 | 2 | GET /api/v1/events/public | Positive | HTTP 200, published only, no join_url | | | |
| W2-P2 | 2 | GET /api/v1/events/public/{event_id} | Positive | HTTP 200, wrapped {event: {...}}, no join_url | | | |
| W2-N1 | 2 | GET /api/v1/events/public/{event_id} (not found) | Negative | HTTP 404, event_not_found | | | |
| W2-P3 | 2 | POST /api/v1/events | Positive | HTTP 201, status=draft | | | |
| W2-P4 | 2 | PATCH /api/v1/events/{event_id}/status (publish) | Positive | HTTP 200, status=published | | | |
| W2-P5 | 2 | PATCH /api/v1/events/{event_id} | Positive | HTTP 200, fields updated | | | |
| W2-P6 | 2 | PATCH /api/v1/events/{event_id}/status (cancel) | Positive | HTTP 200, status=cancelled | | | |
| W2-N2 | 2 | Admin endpoints without JWT | Negative | HTTP 401 or 403 | | | |
| W2-N3 | 2 | POST /api/v1/events (invalid dates) | Negative | HTTP 422 or 400 | | | |
| W2-N4 | 2 | POST /api/v1/events (capacity ≤ 0) | Negative | HTTP 422 or 400 | | | |
| W3-P1 | 3 | GET /api/v1/alumni/me | Positive | HTTP 200, is_active=true | | | |
| W3-N1 | 3 | GET /api/v1/alumni/me (no auth) | Negative | HTTP 401 | | | |
| W3-P2 | 3 | GET /api/v1/events/25/registration-eligibility | Positive | HTTP 200, eligibility_status=eligible | | | |
| W3-P3 | 3 | POST /api/v1/events/25/register | Positive | HTTP 201, status=registered, join_url=null | | | |
| W3-P4 | 3 | POST /api/v1/events/26/register | Positive | HTTP 201, status=registered, join_url non-null | | | |
| W3-P5 | 3 | GET /api/v1/events/26/my-registration | Positive | HTTP 200, join_url visible | | | |
| W3-P6 | 3 | GET /api/v1/my/registrations | Positive | HTTP 200, list with event 25 and 26 | | | |
| W3-P7 | 3 | GET /api/v1/dev/diagnostics/registrations | Positive | HTTP 200, 13/13 passed | | | |
| W3-N2 | 3 | POST /api/v1/events/25/register (duplicate) | Negative | HTTP 409, already_registered | | | |
| W3-N3 | 3 | POST /api/v1/events/34/register (full) | Negative | HTTP 409, event_full | | | |
| W3-N4 | 3 | POST /api/v1/events/35/register (closed) | Negative | HTTP 409, registration_closed | | | |
| W3-N5 | 3 | POST /api/v1/events/36/register (not open yet) | Negative | HTTP 409, registration_not_open_yet | | | |
| W3-N6 | 3 | POST /api/v1/events/25/register (non-alumni) | Negative | HTTP 403, alumni_only | | | |
| W3-N7 | 3 | POST /api/v1/events/25/register (inactive alumni) | Negative | HTTP 403, alumni_not_active | | | |
| W3-N8 | 3 | GET /api/v1/events/public/26 (leak check) | Security | No virtual_url / join_url in response | | | |
| W3-N9 | 3 | GET /api/v1/dev/diagnostics/registrations (prod) | Security | HTTP 404 in production | | | |
| W4-P1 | 4 | GET /api/v1/events/{event_id}/attendees | Planned | TO BE DONE | | | |
| W4-P2 | 4 | GET /api/v1/events/{event_id}/attendees/export | Planned | TO BE DONE | | | |

**Total tests:** 34 (32 active + 2 Week 4 planned)  
**Positive cases:** 14  
**Negative cases:** 16  
**Security cases:** 2  
**Planned (Week 4):** 2

---

## 12. Troubleshooting

### Swagger Authorize not working / 401 on all protected endpoints

Most likely causes:
- Firebase `idToken` pasted instead of backend `access_token` — they are different tokens
- Token expired (Firebase tokens expire after 1 hour; re-run the auth flow)
- Forgot to click **Authorize** after pasting
- Backend restarted with a different `JWT_SECRET` — existing tokens are now invalid

Fix: repeat the auth flow (§4), get a fresh `access_token`, click **Authorize**, paste it.

---

### 403 alumni_only

Causes:
- Logged-in user has `user_type = "other"` not `"alumni"`
- `ALUMNI_DB_URL` not set in `.env` — alumni lookup fails silently
- `event_users.ref_id` is null for this user
- Alumni record in `alumni_db.alumni` is missing

Fix: check `GET /api/v1/auth/me` — if `user_type != "alumni"`, resolve the DB mapping issue.

---

### 404 event_not_found

Causes:
- Event is in `draft` or `cancelled` status (public API only returns `published`)
- Wrong `event_id` — check the test event IDs table (§6)
- Event ID was recreated with a different ID in your local DB

---

### 409 already_registered

Cause: You already registered for this event in a previous test run.

Options:
- Use a different event ID
- Cancel the registration directly in the database: `UPDATE registrations SET status = 'cancelled' WHERE event_id = 25 AND firebase_uid = '...'`
- Run a new registration against a fresh test event created in W2-P3

---

### 409 event_full / registration_closed / registration_not_open_yet

These are expected for events 34, 35, 36 respectively. They are not errors — they are the correct negative test outcomes.

---

### Public API shows no join_url — is this a bug?

No. This is correct and required behaviour. `join_url` is only returned in authenticated
registration responses (`POST /register`, `GET /my-registration`, `GET /my/registrations`)
for users who have `status = "registered"`. It must never appear in the public event list
or public event detail endpoint.

---

### Swagger shows an endpoint but response differs from this guide

Rule: Swagger reflects the live backend. If the response shape in Swagger differs from this
guide, the backend is the authoritative source. File a documentation update, not a backend bug.

Check `docs/reviews/api_documentation_consistency_review.md` for the history of known documentation
mismatches that have already been resolved.

---

### Week 4 attendee endpoints return 501 or 404

Expected. Week 4 endpoints are not yet implemented. Do not treat this as a bug.

---

## Reference

| Resource | URL / Path |
|---|---|
| Swagger UI | `http://localhost:8000/docs` |
| ReDoc | `http://localhost:8000/redoc` |
| OpenAPI JSON | `http://localhost:8000/openapi.json` |
| Backend index | `docs/api/backend_api_index_v2.md` |
| API contract | `docs/api/events_api_contract_v2.md` |
| Response shapes | `docs/api/week3_actual_api_response_shapes.md` |
| Admin portal guide | `docs/api/event_admin_api_usage_v2.md` |
| Manual verification guide | `docs/validation/backend_week3_manual_verification_guide_v2.md` |
| Consistency review | `docs/reviews/api_documentation_consistency_review.md` |
