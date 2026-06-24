# Backend API Index v3

**Version:** 3.0
**Date:** 2026-06-24
**Status:** AUTHORITATIVE — supersedes `backend_api_index_v2.md`
**Source of truth:** `backend/app/api/` — actual router implementations verified 2026-06-24

> v2 is retained for historical reference. The "Week 4 Planned Endpoints" section in v2 listed
> incorrect paths (`/api/v1/events/{id}/attendees` instead of `/api/v1/admin/events/{id}/attendees`).
> v3 corrects all paths and adds all Week 4 and dev diagnostic endpoints.

---

## Summary of All Implemented Endpoints

| Method | Path | Auth | Module | Week |
|---|---|---|---|---|
| `GET` | `/healthz` | None | health.py | 1 |
| `GET` | `/api/v1/health` | None | health.py | 1 |
| `POST` | `/api/v1/auth/firebase` | Firebase idToken in body | auth.py | 1 |
| `GET` | `/api/v1/auth/me` | Backend JWT | auth.py | 1 |
| `GET` | `/api/v1/alumni/me` | Backend JWT (alumni only) | alumni.py | 3 |
| `GET` | `/api/v1/events/public` | None | events.py | 2 |
| `GET` | `/api/v1/events/public/{event_id}` | None | events.py | 2 |
| `POST` | `/api/v1/events` | X-Dev-User: admin | events.py | 2 |
| `GET` | `/api/v1/events` | X-Dev-User: admin | events.py | 2 |
| `GET` | `/api/v1/events/{event_id}` | X-Dev-User: admin | events.py | 2 |
| `PATCH` | `/api/v1/events/{event_id}/status` | X-Dev-User: admin | events.py | 2 |
| `PATCH` | `/api/v1/events/{event_id}` | X-Dev-User: admin | events.py | 2 |
| `POST` | `/api/v1/events/{event_id}/register` | Backend JWT (alumni only) | registrations.py | 3 |
| `GET` | `/api/v1/events/{event_id}/my-registration` | Backend JWT | registrations.py | 3 |
| `GET` | `/api/v1/my/registrations` | Backend JWT | registrations.py | 3 |
| `GET` | `/api/v1/events/{event_id}/registration-eligibility` | Backend JWT | registrations.py | 3 |
| `POST` | `/api/v1/admin/events` | X-Dev-User: admin | admin_events.py | 2 |
| `PATCH` | `/api/v1/admin/events/{event_id}` | X-Dev-User: admin | admin_events.py | 2 |
| `POST` | `/api/v1/admin/events/{event_id}/publish` | X-Dev-User: admin | admin_events.py | 2 |
| `POST` | `/api/v1/admin/events/{event_id}/close` | X-Dev-User: admin | admin_events.py | 2 |
| `GET` | `/api/v1/admin/events` | X-Dev-User: admin | admin_events.py | 2 |
| `GET` | `/api/v1/admin/events/{event_id}/attendees` | X-Dev-User: admin | admin_events.py | 4 |
| `GET` | `/api/v1/admin/events/{event_id}/attendees/export` | X-Dev-User: admin | admin_events.py | 4 |
| `GET` | `/api/v1/admin/events/{event_id}/registrations` | X-Dev-User: admin | admin_events.py | 4 |
| `GET` | `/api/v1/admin/events/{event_id}/check-ins/verify` | X-Dev-User: admin | admin_events.py | stub |
| `POST` | `/api/v1/admin/events/{event_id}/check-ins` | X-Dev-User: admin | admin_events.py | stub |
| `GET` | `/api/v1/admin/events/{event_id}/check-ins` | X-Dev-User: admin | admin_events.py | stub |
| `GET` | `/api/v1/dev/diagnostics/auth/me` | Backend JWT (dev only) | dev_diagnostics.py | 1 |
| `GET` | `/api/v1/dev/diagnostics/db/tables` | Backend JWT (dev only) | dev_diagnostics.py | 1 |
| `GET` | `/api/v1/dev/diagnostics/db/{table_name}` | Backend JWT (dev only) | dev_diagnostics.py | 1 |
| `GET` | `/api/v1/dev/diagnostics/events` | X-Dev-User or JWT (dev only) | dev_diagnostics.py | 3 |
| `GET` | `/api/v1/dev/diagnostics/registrations` | X-Dev-User or JWT (dev only) | dev_diagnostics.py | 3 |
| `GET` | `/api/v1/dev/diagnostics/attendees` | X-Dev-User or JWT (dev only) | dev_diagnostics.py | 4 |
| `GET` | `/api/v1/dev/diagnostics/alumni/search` | X-Dev-User or JWT (dev only) | dev_diagnostics.py | 3 |
| `GET` | `/api/v1/dev/diagnostics/alumni/search-prefix` | X-Dev-User or JWT (dev only) | dev_diagnostics.py | 3 |
| `GET` | `/api/v1/dev/diagnostics/alumni/login-trace` | X-Dev-User or JWT (dev only) | dev_diagnostics.py | 3 |
| `GET` | `/api/v1/dev/diagnostics/alumni/{alumni_id}` | X-Dev-User or JWT (dev only) | dev_diagnostics.py | 3 |

> **Auth note — Development mode:** Admin and dev endpoints accept `X-Dev-User: admin` header instead
> of Bearer JWT. Production will use Firebase JWT via `Authorization: Bearer <token>`.
> The `/api/v1/dev/diagnostics/...` endpoints additionally accept `X-Dev-User: admin` as of Week 4.

> **Not implemented:** `DELETE /api/v1/events/{event_id}/register` — registration cancellation is
> deferred. The Week 4 status report incorrectly listed this as implemented; it is not.

> **This document is the authoritative API reference for Week 4 and later.**
> All future development, frontend integration, diagnostics implementation, and QA verification
> should reference this document as the primary source of truth.

---

## Health

### GET /healthz

**Auth:** None
**Module:** `health.py`

Root-level health check.

**Response (HTTP 200):**

```json
{"status": "ok"}
```

---

### GET /api/v1/health

**Auth:** None
**Module:** `health.py`

Full health check with DB connectivity status.

**Response (HTTP 200):**

```json
{
  "status": "ok",
  "version": "1.0.0",
  "env": "development",
  "db": "ok"
}
```

If DB connectivity fails, `"db"` is an error string.

---

## Auth

### POST /api/v1/auth/firebase

**Auth:** Firebase ID token in request body
**Module:** `auth.py`

Exchanges a Firebase ID token for a backend JWT session. Also upserts the user into `event_users`.

**Request body:**

```json
{"token": "<firebase_id_token>"}
```

**Response (HTTP 200):**

```json
{
  "status": "ok",
  "access_token": "<HS256 backend JWT>",
  "token_type": "bearer",
  "firebase_uid": "...",
  "user_type": "alumni",
  "fullname": "Username Alumni",
  "ref_id": "NITK2026IT001",
  "graduation_year": 2026
}
```

For non-alumni: `user_type = "other"`, `ref_id = null`, `graduation_year = null`.

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 400 | `firebase_uid_missing` | No UID in Firebase token |
| 400 | `email_missing` | No email in Firebase token |
| 403 | `account_suspended` | User is suspended in event_users |

---

### GET /api/v1/auth/me

**Auth:** `Authorization: Bearer <backend_access_token>`
**Module:** `auth.py`

Returns the current backend user profile.

**Response (HTTP 200):**

```json
{
  "firebase_uid": "...",
  "email": "username2026@gmail.com",
  "fullname": "Username Alumni",
  "user_type": "alumni",
  "ref_id": "NITK2026IT001",
  "graduation_year": 2026
}
```

---

## Alumni

### GET /api/v1/alumni/me

**Auth:** `Authorization: Bearer <backend_access_token>` (alumni only)
**Module:** `alumni.py`

Returns the authenticated user's alumni profile from `alumni_db`. Response is flat — no wrapper object.

**Response (HTTP 200):**

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

**Field mapping (`alumni_db.alumni` → API):**

| DB column | API field | Notes |
|---|---|---|
| `alumni_id` | `ref_id` | Renamed |
| `graduationyear` | `batch_year` | Renamed |
| `registrationstatus` | `is_active` | `true` when `'Active'` or `'Self-Verified'` |

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 403 | `alumni_only` | `user_type != 'alumni'` or no `ref_id` |
| 404 | `alumni_profile_not_found` | `ref_id` not found in alumni_db |

---

## Public Events

### GET /api/v1/events/public

**Auth:** None
**Module:** `events.py`
**Security:** `virtual_url` and `join_url` are never present

Returns paginated list of published events.

**Query params:**

| Param | Type | Default | Notes |
|---|---|---|---|
| `page` | int | 1 | Page number |
| `per_page` | int | 20 | 1–100 |
| `period` | string | null | `upcoming`, `past`, or `all` |

**Response (HTTP 200):**

```json
{
  "events": [
    {
      "event_id": 101,
      "title": "Breakfast Club Bangalore",
      "description": "...",
      "status": "published",
      "is_virtual": false,
      "location_text": "The Leela Palace, Bangalore",
      "start_datetime": "2026-06-24T11:08:00Z",
      "end_datetime": "2026-06-24T14:08:00Z",
      "timezone": "Asia/Kolkata",
      "capacity": 30,
      "registered_count": 2,
      "registration_opens_at": null,
      "registration_closes_at": null,
      "registration_status": "open"
    }
  ],
  "total": 4,
  "page": 1,
  "per_page": 20
}
```

**`registration_status` values:** `open`, `full`, `closed`, `not_open_yet`

---

### GET /api/v1/events/public/{event_id}

**Auth:** None
**Module:** `events.py`
**Security:** `virtual_url` and `join_url` are never present

Returns a single published event. **Response wraps event in `"event"` key.**

**Response (HTTP 200):**

```json
{
  "event": {
    "event_id": 101,
    "title": "Breakfast Club Bangalore",
    "description": "...",
    "status": "published",
    "is_virtual": false,
    "location_text": "The Leela Palace, Bangalore",
    "start_datetime": "2026-06-24T11:08:00Z",
    "end_datetime": "2026-06-24T14:08:00Z",
    "timezone": "Asia/Kolkata",
    "capacity": 30,
    "registered_count": 2,
    "registration_opens_at": null,
    "registration_closes_at": null,
    "registration_status": "open",
    "sessions": [],
    "speakers": []
  }
}
```

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 404 | `event_not_found` | No published event with this ID |

---

## Admin Events (`/api/v1/events/...`)

> These routes are in `events.py` and use `X-Dev-User: admin` auth.
> Used by the Flutter dev diagnostics screen.

### GET /api/v1/events

**Auth:** X-Dev-User: admin

Returns all events (all statuses). Used by the Flutter dev diagnostics Smart Event Selector.

**Query params:** `page`, `per_page`, `status`, `is_virtual`, `search`

**Response:** `{"events": [...], "total": N, "page": 1, "per_page": 20}`

---

### GET /api/v1/events/{event_id}

**Auth:** X-Dev-User: admin

Returns full admin event detail including `virtual_url` and `created_by_firebase_uid`.

**Response:** `{"event": {...}}` — note the `event` wrapper key.

---

### PATCH /api/v1/events/{event_id}/status

**Auth:** X-Dev-User: admin

Updates event lifecycle status.

**Request body:** `{"status": "published"}` or `"draft"`, `"cancelled"`, `"completed"`

**Supported transitions:**

| From | To |
|---|---|
| `draft` | `published` |
| `published` | `draft` |
| `draft` or `published` | `cancelled` |
| Any | `completed` |

> There is no `DELETE /api/v1/events/{event_id}`. Cancellation uses this endpoint with `{"status": "cancelled"}`.

---

### POST /api/v1/events

**Auth:** X-Dev-User: admin

Creates a new event as `draft`.

---

### PATCH /api/v1/events/{event_id}

**Auth:** X-Dev-User: admin

Updates editable event fields (partial update — all fields optional).

---

## Admin Portal Events (`/api/v1/admin/...`)

> These routes are in `admin_events.py` with prefix `/api/v1/admin`.
> Used by the NITKSAA React Admin Portal at `localhost:5173`.

### POST /api/v1/admin/events

**Auth:** X-Dev-User: admin

Creates a new event. Returns created event as `EventResponse`.

---

### PATCH /api/v1/admin/events/{event_id}

**Auth:** X-Dev-User: admin

Updates an event. Returns updated event as `EventResponse`.

---

### POST /api/v1/admin/events/{event_id}/publish

**Auth:** X-Dev-User: admin

Sets event status to `published`.

---

### POST /api/v1/admin/events/{event_id}/close

**Auth:** X-Dev-User: admin

Sets event status to `cancelled` or `completed` (closes it).

---

### GET /api/v1/admin/events

**Auth:** X-Dev-User: admin

Returns all events for the admin portal list view.

---

### GET /api/v1/admin/events/{event_id}/attendees

**Auth:** X-Dev-User: admin
**Week 4**

Returns paginated list of registered attendees for an event.

**Query params:**

| Param | Type | Default | Notes |
|---|---|---|---|
| `page` | int | 1 | Page number |
| `per_page` | int | 20 | Items per page |
| `search` | string | null | Filter by name or email |
| `batch_year` | int | null | Filter by graduation year |

**Response (HTTP 200):**

```json
{
  "attendees": [
    {
      "registration_id": 5,
      "registration_number": "NITKSAA-2026-000005",
      "fullname_snapshot": "Username Alumni",
      "email_snapshot": "username2026@gmail.com",
      "phone_snapshot": "+919876543210",
      "batch_year_snapshot": 2026,
      "branch_snapshot": "Information Technology",
      "attendee_note": null,
      "registered_at": "2026-06-19T09:56:44Z",
      "status": "registered",
      "confirmation_email_status": "sent"
    }
  ],
  "total": 2,
  "page": 1,
  "per_page": 20
}
```

**Security:** Only `status='registered'` rows are returned. Cancelled registrations are excluded.

---

### GET /api/v1/admin/events/{event_id}/attendees/export

**Auth:** X-Dev-User: admin
**Week 4**

Returns a CSV file of all registered attendees.

**Response:** `text/csv` with UTF-8 BOM for Excel compatibility.

**CSV columns:**

```
registration_number, fullname_snapshot, email_snapshot, batch_year_snapshot,
branch_snapshot, phone_snapshot, registered_at, status
```

**Security:** `virtual_url`, `join_url`, and `qr_token` are never included.

---

### GET /api/v1/admin/events/{event_id}/registrations

**Auth:** X-Dev-User: admin
**Week 4**

Returns a paginated list of all registration records (registered + cancelled) for audit purposes.

**Query params:** `page`, `per_page`, `status` (`registered` or `cancelled`)

**Response (HTTP 200):**

```json
{
  "registrations": [
    {
      "registration_id": 5,
      "registration_number": "NITKSAA-2026-000005",
      "status": "registered",
      "fullname_snapshot": "Username Alumni",
      "email_snapshot": "username2026@gmail.com",
      "registered_at": "2026-06-19T09:56:44Z",
      "cancelled_at": null,
      "confirmation_email_status": "sent"
    }
  ],
  "total": 2,
  "page": 1,
  "per_page": 20
}
```

---

## Registration

### POST /api/v1/events/{event_id}/register

**Auth:** `Authorization: Bearer <backend_access_token>` (alumni only)
**Module:** `registrations.py`
**Success status:** HTTP 201

**Request body:**

```json
{"attendee_note": "optional, max 500 chars"}
```

Empty body `{}` is valid. `attendee_note` is the only accepted field.

**Response (HTTP 201) — flat with nested `event` object:**

```json
{
  "registration_id": 5,
  "registration_number": "NITKSAA-2026-000005",
  "event_id": 101,
  "firebase_uid": "...",
  "ref_id": "NITK2026IT001",
  "status": "registered",
  "fullname_snapshot": "Username Alumni",
  "email_snapshot": "username2026@gmail.com",
  "phone_snapshot": "+919876543210",
  "batch_year_snapshot": 2026,
  "branch_snapshot": "Information Technology",
  "attendee_note": null,
  "registered_at": "2026-06-24T09:56:44Z",
  "cancelled_at": null,
  "confirmation_email_status": "sent",
  "confirmation_email_sent_at": "2026-06-24T09:56:44Z",
  "join_url": null,
  "event": {
    "event_id": 101,
    "title": "Breakfast Club Bangalore",
    "start_datetime": "2026-06-24T11:08:00Z",
    "end_datetime": "2026-06-24T14:08:00Z",
    "timezone": "Asia/Kolkata",
    "is_virtual": false,
    "location_text": "The Leela Palace, Bangalore",
    "location_maps_url": null
  },
  "updated_at": null
}
```

**`join_url` rules:** Non-null only when `status='registered'` AND `event.is_virtual=true` AND event is `published`.

**`registration_number` format:** `NITKSAA-{year}-{registration_id:06d}`

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 403 | `alumni_only` | Not alumni or no `ref_id` |
| 403 | `alumni_not_found` | `ref_id` not in alumni_db |
| 403 | `alumni_not_active` | Alumni `registrationstatus` not Active/Self-Verified |
| 404 | `event_not_found` | Event does not exist |
| 409 | `event_not_published` | Event status is not published |
| 409 | `registration_not_open_yet` | Before `registration_opens_at` |
| 409 | `registration_closed` | After `registration_closes_at` |
| 409 | `already_registered` | Active registration already exists |
| 409 | `event_full` | Capacity reached |

---

### GET /api/v1/events/{event_id}/my-registration

**Auth:** Backend JWT
**Module:** `registrations.py`

Returns the authenticated user's registration for a specific event. Same `RegistrationResponse` shape as POST `/register`.

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 404 | `registration_not_found` | No registration for this user + event |

---

### GET /api/v1/my/registrations

**Auth:** Backend JWT
**Module:** `registrations.py`

Returns all registrations for the authenticated user. Ordered by `registered_at DESC`.

**Response (HTTP 200):**

```json
{
  "registrations": [ { "<RegistrationResponse>" } ],
  "total": 2
}
```

---

### GET /api/v1/events/{event_id}/registration-eligibility

**Auth:** Backend JWT
**Module:** `registrations.py`
**Always returns HTTP 200** — never 4xx for eligibility reasons

**Response (HTTP 200):**

```json
{
  "event_id": 101,
  "firebase_uid": "...",
  "eligibility_status": "eligible",
  "message": "You are eligible to register.",
  "registered_count": 2,
  "capacity": 30
}
```

**`eligibility_status` values (confirmed from `registration_service.py`):**

| Value | Meaning | `registered_count`/`capacity` present? |
|---|---|---|
| `eligible` | User can register | Yes |
| `already_registered` | Active registration exists | No |
| `full` | `registered_count >= capacity` | Yes |
| `closed` | Past `registration_closes_at` | No |
| `not_open_yet` | Before `registration_opens_at` | No |
| `ineligible` | Non-alumni, inactive, not found, not published — read `message` | No |

> **Two-code distinction:** These eligibility codes differ from the POST `/register` error `detail` values.
> `full` (eligibility) vs `event_full` (register error), `closed` vs `registration_closed`, etc.

---

## Developer Diagnostics (`/api/v1/dev/diagnostics/...`)

> All endpoints return `404` when `APP_ENV != "development"`.
> Auth: Backend JWT **or** `X-Dev-User: admin` header (both accepted as of Week 4).

### GET /api/v1/dev/diagnostics/auth/me

Returns the current user from `event_users`.

---

### GET /api/v1/dev/diagnostics/db/tables

Returns a list of all accessible tables with row counts.

```json
{"tables": [{"name": "event_users", "available": true, "row_count": 1}]}
```

---

### GET /api/v1/dev/diagnostics/db/{table_name}

Returns rows from a supported table.

Supported tables: `event_users`, `events`, `sessions`, `registrations`, `check_ins`,
`event_content`, `event_audit_log`, `notifications`, `notification_preferences`

---

### GET /api/v1/dev/diagnostics/events

Runs event management diagnostic checks: public event list, admin event list, join URL leak checks.

**Response:**

```json
{
  "status": "ok",
  "total": N,
  "passed": N,
  "failed": 0,
  "results": [{"feature": "...", "status": "PASS", "detail": {}}]
}
```

---

### GET /api/v1/dev/diagnostics/registrations

Runs 13 end-to-end registration checks against the live backend and database.

**Checks include:** alumni profile, test event setup, eligibility, register, my-registration,
my-registrations list, duplicate guard, capacity guard, join link visibility,
confirmation email status, audit log, public API leak check.

**Response:**

```json
{
  "status": "ok",
  "category": "Registration Flow",
  "total": 13,
  "passed": 13,
  "failed": 0,
  "results": [{"feature": "...", "status": "PASS"}]
}
```

---

### GET /api/v1/dev/diagnostics/attendees

**Week 4**

Runs UC-01 through UC-10 attendee management checks.

**Query params:**

| Param | Type | Required | Notes |
|---|---|---|---|
| `event_id` | int | Yes | Event to run diagnostics against |

**Response:**

```json
{
  "passed": 10,
  "failed": 0,
  "total": 10,
  "results": [
    {"uc": "UC-01", "name": "attendees visible (status=registered only)", "status": "PASS", "detail": {}}
  ]
}
```

> **Field names:** Results use `"uc"` and `"name"` keys (not `"feature"`). Flutter diagnostic screen
> reads `r['uc']` and `r['name']` accordingly.

---

### GET /api/v1/dev/diagnostics/alumni/search

**Query params:** `email` (required)

Looks up an alumni record in `alumni_db` by exact email. Used for diagnosing login mapping.

---

### GET /api/v1/dev/diagnostics/alumni/search-prefix

**Query params:** `q` (required, min 3 chars)

Prefix search across `fullname` and `email` in `alumni_db`.

---

### GET /api/v1/dev/diagnostics/alumni/login-trace

**Query params:** `email` (required)

Traces the full login flow for a given email: event_users lookup → alumni_db lookup → is_active check.

---

### GET /api/v1/dev/diagnostics/alumni/{alumni_id}

Looks up an alumni record by `alumni_id` directly from `alumni_db`.

---

## Not Implemented / Deferred

| Endpoint | Status | Notes |
|---|---|---|
| `DELETE /api/v1/events/{event_id}/register` | **Not implemented** | Cancellation deferred to Week 5+ |
| `GET /api/v1/admin/events/{id}/check-ins/verify` | Stub | QR check-in deferred |
| `POST /api/v1/admin/events/{id}/check-ins` | Stub | QR check-in deferred |
| `GET /api/v1/admin/events/{id}/check-ins` | Stub | QR check-in deferred |

---

## Documentation Version Matrix

| Document | Status |
|---|---|
| `backend_api_index_v1.md` | Deprecated |
| `backend_api_index_v2.md` | Deprecated |
| `backend_api_index_v3.md` | Authoritative |
| `events_api_contract_v2.md` | Authoritative |
| `alumni_db_integration_architecture_v1.md` | Authoritative |

---

## Corrections vs v2

| v2 Claim | v3 Correction |
|---|---|
| `GET /api/v1/events/{id}/attendees` (planned) | Actual path: `GET /api/v1/admin/events/{id}/attendees` |
| `GET /api/v1/events/{id}/attendees/export` (planned) | Actual path: `GET /api/v1/admin/events/{id}/attendees/export` |
| `GET /healthz` not documented | Added — root-level health check |
| Dev diagnostics listed only 4 endpoints | 11 endpoints exist — all documented above |
| Auth notes missing for dev endpoints | All dev endpoints accept `X-Dev-User: admin` (added Week 4) |

---

## Schema Source Reference

| Schema | File |
|---|---|
| `AlumniProfileResponse` | `backend/app/schemas/registrations.py` |
| `RegisterRequest` | `backend/app/schemas/registrations.py` |
| `RegistrationResponse` | `backend/app/schemas/registrations.py` |
| `RegistrationEligibilityResponse` | `backend/app/schemas/registrations.py` |
| `MyRegistrationsListResponse` | `backend/app/schemas/registrations.py` |
| `AdminAttendeeItem` | `backend/app/schemas/registrations.py` |
| `AdminAttendeeListResponse` | `backend/app/schemas/registrations.py` |
| `AdminRegistrationItem` | `backend/app/schemas/registrations.py` |
| `AdminRegistrationListResponse` | `backend/app/schemas/registrations.py` |
| `EventCreate` | `backend/app/schemas/event_create.py` |
| `EventUpdate` | `backend/app/schemas/event_update.py` |
| `EventStatusUpdate` | `backend/app/schemas/event_status.py` |
| `EventResponse` | `backend/app/schemas/events.py` |
| `FirebaseLoginRequest` / `AuthResponse` | `backend/app/api/auth.py` |

---

*For join link rules and email confirmation rules: `docs/api/events_api_contract_v2.md`*
*For registration error codes vs eligibility status cross-reference: `docs/api/events_api_contract_v2.md`*
