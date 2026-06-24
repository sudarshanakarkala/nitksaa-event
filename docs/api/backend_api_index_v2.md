# Backend API Index v2

**Version:** 2.0
**Date:** 2026-06-19
**Status:** SUPERSEDED by `backend_api_index_v3.md` (2026-06-24)
**Known issues in this version:** Admin attendee paths in "Week 4 Planned" section are wrong
(`/api/v1/events/{id}/attendees` should be `/api/v1/admin/events/{id}/attendees`).
Use v3 for all new development.

---

> `backend_api_index_v1.md` is retained for historical reference only. All entries in v1 that
> were marked "Planned / Placeholder" have either been implemented (see below) or remain planned
> for Week 4 (marked clearly). Do not use v1 response shapes in any new frontend code.

---

## Summary of Implemented Endpoints

| Method | Path | Auth | Week | Status |
|---|---|---|---|---|
| `GET` | `/api/v1/health` | None | 1 | Implemented |
| `POST` | `/api/v1/auth/firebase` | Firebase idToken in body | 1 | Implemented |
| `GET` | `/api/v1/auth/me` | Backend JWT | 1 | Implemented |
| `GET` | `/api/v1/events/public` | None | 2 | Implemented |
| `GET` | `/api/v1/events/public/{event_id}` | None | 2 | Implemented |
| `POST` | `/api/v1/events` | Backend JWT (admin) | 2 | Implemented |
| `GET` | `/api/v1/events` | Backend JWT (admin) | 2 | Implemented |
| `GET` | `/api/v1/events/{event_id}` | Backend JWT (admin) | 2 | Implemented |
| `PATCH` | `/api/v1/events/{event_id}` | Backend JWT (admin) | 2 | Implemented |
| `PATCH` | `/api/v1/events/{event_id}/status` | Backend JWT (admin) | 2 | Implemented |
| `GET` | `/api/v1/alumni/me` | Backend JWT (alumni only) | 3 | Implemented |
| `POST` | `/api/v1/events/{event_id}/register` | Backend JWT (alumni only) | 3 | Implemented |
| `GET` | `/api/v1/events/{event_id}/registration-eligibility` | Backend JWT | 3 | Implemented |
| `GET` | `/api/v1/events/{event_id}/my-registration` | Backend JWT | 3 | Implemented |
| `GET` | `/api/v1/my/registrations` | Backend JWT | 3 | Implemented |
| `GET` | `/api/v1/dev/diagnostics/db/tables` | Backend JWT (dev only) | 1 | Implemented |
| `GET` | `/api/v1/dev/diagnostics/db/{table_name}` | Backend JWT (dev only) | 1 | Implemented |
| `GET` | `/api/v1/dev/diagnostics/auth/me` | Backend JWT (dev only) | 1 | Implemented |
| `GET` | `/api/v1/dev/diagnostics/registrations` | Backend JWT (dev only) | 3 | Implemented |
| `GET` | `/api/v1/events/{event_id}/attendees` | Backend JWT (admin) | 4 | **Planned** |
| `GET` | `/api/v1/events/{event_id}/attendees/export` | Backend JWT (admin) | 4 | **Planned** |

---

## Health

### GET /api/v1/health

**Auth:** None  
**Status:** Implemented — Week 1

```http
GET /api/v1/health
```

Response:

```json
{
  "status": "ok",
  "version": "1.0.0",
  "env": "development",
  "db": "ok"
}
```

If database connectivity fails, `db` contains an error string instead of `"ok"`.

---

## Authentication

### POST /api/v1/auth/firebase

**Auth:** Firebase ID token in request body (not as a header)  
**Status:** Implemented — Week 1

Exchanges a fresh Firebase ID token for a backend JWT session.

**Request body:**

```json
{
  "token": "<firebase_id_token>"
}
```

> The field name is `token`. Firebase's own API response uses the field name `idToken` — copy that
> value and send it as `token` to this endpoint.

**Success response (HTTP 200):**

```json
{
  "status": "ok",
  "access_token": "<HS256 backend JWT>",
  "token_type": "bearer",
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "user_type": "alumni",
  "fullname": "Username Alumni",
  "ref_id": "NITK2026IT001",
  "graduation_year": 2026
}
```

For non-alumni users: `user_type = "other"`, `ref_id = null`, `graduation_year = null`.

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 400 | `firebase_uid_missing` | Firebase token contained no UID |
| 400 | `email_missing` | Firebase token contained no email |
| 403 | `account_suspended` | User exists in event_users but `is_suspended = true` |
| 422 | (Pydantic validation) | Request body missing `token` field or token is empty |

---

### GET /api/v1/auth/me

**Auth:** Backend JWT (`Authorization: Bearer <access_token>`)  
**Status:** Implemented — Week 1

Returns the current backend user profile.

**Success response (HTTP 200):**

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

**Error responses:**

| HTTP | Cause |
|---|---|
| 401 | Missing, expired, or invalid bearer token |

---

## Public Events (No Auth)

### GET /api/v1/events/public

**Auth:** None  
**Status:** Implemented — Week 2

Returns a paginated list of published events.

**Query parameters:**

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `page` | int | 1 | Page number (≥1) |
| `per_page` | int | 20 | Items per page (1–100) |
| `period` | string | null | `"upcoming"`, `"past"`, or `"all"` |

**Success response (HTTP 200):**

```json
{
  "events": [
    {
      "event_id": 26,
      "slug": "webinar-on-ai",
      "title": "Webinar on AI",
      "description": "...",
      "status": "published",
      "is_virtual": true,
      "location_text": null,
      "location_maps_url": null,
      "start_datetime": "2026-08-02T00:00:00Z",
      "end_datetime": "2026-08-02T02:00:00Z",
      "timezone": "Asia/Kolkata",
      "capacity": 100,
      "registered_count": 1,
      "registration_opens_at": null,
      "registration_closes_at": null,
      "registration_status": "open"
    }
  ],
  "total": 1,
  "page": 1,
  "per_page": 20
}
```

**Security invariant:** `virtual_url`, `join_url`, and `created_by_firebase_uid` are never present in any item in this list.

---

### GET /api/v1/events/public/{event_id}

**Auth:** None  
**Status:** Implemented — Week 2

Returns a single published event. The event is wrapped in an `event` key.

> **Shape difference from list:** The list endpoint returns `{"events": [...]}`. The detail endpoint
> returns `{"event": {...}}`. Access event fields via `response.event.<field>`.

**Success response (HTTP 200):**

```json
{
  "event": {
    "event_id": 26,
    "slug": "webinar-on-ai",
    "title": "Webinar on AI",
    "description": "...",
    "status": "published",
    "is_virtual": true,
    "location_text": null,
    "location_maps_url": null,
    "start_datetime": "2026-08-02T00:00:00Z",
    "end_datetime": "2026-08-02T02:00:00Z",
    "timezone": "Asia/Kolkata",
    "capacity": 100,
    "registered_count": 1,
    "registration_opens_at": null,
    "registration_closes_at": null,
    "registration_status": "open",
    "sessions": [],
    "speakers": []
  }
}
```

**Security invariant:** `virtual_url`, `join_url`, and `created_by_firebase_uid` are never present.

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 404 | `event_not_found` | No published event with this ID |

---

## Admin Event Endpoints (Backend JWT Required)

> These endpoints require an `Authorization: Bearer <backend_access_token>` header.
> In development, the backend uses an `X-Dev-User: admin` middleware guard.
> Admin endpoints are accessible from the NITKSAA React Admin Portal.

### POST /api/v1/events

**Auth:** Backend JWT (admin)  
**Status:** Implemented — Week 2

Creates a new event as `draft`.

**Request body:** `EventCreate` schema (title, is_virtual, capacity, dates, etc.)

**Success response (HTTP 201):**

```json
{
  "status": "ok",
  "event": {
    "event_id": 27,
    "slug": "...",
    "title": "New Event",
    "status": "draft",
    "is_virtual": false,
    "registered_count": 0,
    ...
  }
}
```

---

### GET /api/v1/events

**Auth:** Backend JWT (admin)  
**Status:** Implemented — Week 2

Returns a paginated list of all events (all statuses — not just published).

**Query parameters:** `page`, `per_page`, `status`, `is_virtual`, `search`

**Success response (HTTP 200):**

```json
{
  "events": [ { ... } ],
  "total": 5,
  "page": 1,
  "per_page": 20
}
```

---

### GET /api/v1/events/{event_id}

**Auth:** Backend JWT (admin)  
**Status:** Implemented — Week 2

Returns full event detail including `virtual_url`, `created_by_firebase_uid`, and other admin-only fields.

**Success response (HTTP 200):**

```json
{
  "event": {
    "event_id": 26,
    "title": "...",
    "virtual_url": "https://meet.google.com/...",
    "created_by_firebase_uid": "...",
    ...
  }
}
```

---

### PATCH /api/v1/events/{event_id}

**Auth:** Backend JWT (admin)  
**Status:** Implemented — Week 2

Updates editable event fields (title, description, dates, capacity, virtual_url, etc.).

**Request body:** `EventUpdate` schema — all fields optional (partial update).

**Success response (HTTP 200):**

```json
{
  "status": "ok",
  "event": { ... }
}
```

---

### PATCH /api/v1/events/{event_id}/status

**Auth:** Backend JWT (admin)  
**Status:** Implemented — Week 2

Updates the event lifecycle status.

**Request body:**

```json
{
  "status": "published"
}
```

Supported transitions:

| From | To | Notes |
|---|---|---|
| `draft` | `published` | Makes event visible in public API |
| `published` | `draft` | Hides event from public API |
| `draft` or `published` | `cancelled` | Soft-cancel — event is retained with `status = "cancelled"` |
| Any | `completed` | Reserved for manual or automated completion |

> There is no `DELETE /api/v1/events/{event_id}` endpoint. Cancellation is done via this status
> endpoint with `{"status": "cancelled"}`. Hard deletes are not supported — they would orphan
> registration, audit log, and future payment records.

**Success response (HTTP 200):**

```json
{
  "status": "ok",
  "event": { "event_id": 26, "status": "cancelled", ... }
}
```

---

## Alumni Endpoint

### GET /api/v1/alumni/me

**Auth:** Backend JWT (alumni only)  
**Status:** Implemented — Week 3

Returns the authenticated user's alumni profile from `alumni_db`.

**Success response (HTTP 200) — flat, no wrapper:**

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

**Field mapping (DB column → API field):**

| `alumni_db.alumni` column | API field | Notes |
|---|---|---|
| `alumni_id` | `ref_id` | Renamed |
| `fullname` | `fullname` | Direct |
| `email` | `email` | Direct |
| `phone` | `phone` | Nullable |
| `graduationyear` | `batch_year` | Renamed |
| `branch` | `branch` | Nullable |
| `registrationstatus` | _(not in response)_ | Computed → `is_active` |

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 403 | `alumni_only` | `user_type != "alumni"` or `ref_id` is null |
| 404 | `alumni_profile_not_found` | `ref_id` not found in alumni_db |

---

## Registration Endpoints

### POST /api/v1/events/{event_id}/register

**Auth:** Backend JWT (alumni only)  
**Status:** Implemented — Week 3  
**Success status:** HTTP 201

Registers the authenticated alumni for an event.

**Request body:**

```json
{
  "attendee_note": "optional string, max 500 chars"
}
```

Empty body `{}` is valid. The only accepted field is `attendee_note`.

**Success response (HTTP 201) — flat, with nested `event` object:**

```json
{
  "registration_id": 5,
  "registration_number": "NITKSAA-2026-000005",
  "event_id": 26,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "ref_id": "NITK2026IT001",
  "status": "registered",
  "fullname_snapshot": "Username Alumni",
  "email_snapshot": "username2026@gmail.com",
  "phone_snapshot": "+919876543210",
  "batch_year_snapshot": 2026,
  "branch_snapshot": "Information Technology",
  "attendee_note": null,
  "registered_at": "2026-06-19T09:56:44.833099Z",
  "cancelled_at": null,
  "confirmation_email_status": "sent",
  "confirmation_email_sent_at": "2026-06-19T09:56:44.851099Z",
  "join_url": "https://meet.google.com/nitksaa-demo-webinar",
  "event": {
    "event_id": 26,
    "title": "Webinar Demo",
    "start_datetime": "2026-08-02T00:00:00Z",
    "end_datetime": "2026-08-02T02:00:00Z",
    "timezone": "Asia/Kolkata",
    "is_virtual": true,
    "location_text": null,
    "location_maps_url": null
  },
  "updated_at": null
}
```

**Critical field notes:**

- `status` values: `"registered"` or `"cancelled"` — never `"confirmed"`
- `join_url`: top-level field, non-null only when `status="registered"` AND `event.is_virtual=true` AND event is published
- `event.is_virtual`: inside nested `event` object — NOT at the top level of the registration response
- `confirmation_email_status`: `"sent"`, `"failed"`, or `"skipped"` — never `null` after registration; never a boolean
- `registration_number` format: `NITKSAA-{year}-{registration_id:06d}`

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 403 | `alumni_only` | `user_type != "alumni"` or no `ref_id` |
| 403 | `alumni_not_found` | `ref_id` not in alumni_db |
| 403 | `alumni_not_active` | `registrationstatus` not in `{'Active', 'Self-Verified'}` |
| 404 | `event_not_found` | event_id does not exist |
| 409 | `event_not_published` | `events.status != "published"` |
| 409 | `registration_not_open_yet` | `now < registration_opens_at` |
| 409 | `registration_closed` | `now > registration_closes_at` |
| 409 | `already_registered` | Active registration already exists |
| 409 | `event_full` | `COUNT(status='registered') >= capacity` |

---

### GET /api/v1/events/{event_id}/registration-eligibility

**Auth:** Backend JWT  
**Status:** Implemented — Week 3  
**Always returns HTTP 200** — never 4xx for eligibility reasons

**Success response (HTTP 200):**

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

**`eligibility_status` values (v2 — use these, not v1 values):**

| Value | Meaning | `registered_count`/`capacity` present? |
|---|---|---|
| `eligible` | User can register | Yes |
| `already_registered` | Active registration exists | No |
| `full` | `registered_count >= capacity` | Yes |
| `closed` | Past `registration_closes_at` | No |
| `not_open_yet` | Before `registration_opens_at` | No |
| `ineligible` | Non-alumni, inactive, event not found, not published — read `message` | No |

> **Two-code rule:** `eligibility_status` values (GET) differ from POST `/register` error `detail`
> codes. `full` vs `event_full`, `closed` vs `registration_closed`, etc. Never mix the two sets.
> See `docs/api/events_api_contract_v2.md` for the full cross-reference table.

---

### GET /api/v1/events/{event_id}/my-registration

**Auth:** Backend JWT  
**Status:** Implemented — Week 3

Returns the authenticated user's registration for a specific event. Same `RegistrationResponse` shape as `POST /register`.

**Error responses:**

| HTTP | detail | Cause |
|---|---|---|
| 404 | `registration_not_found` | No registration for this user + event |

---

### GET /api/v1/my/registrations

**Auth:** Backend JWT  
**Status:** Implemented — Week 3

Returns all registrations for the authenticated user across all events.

**Success response (HTTP 200):**

```json
{
  "registrations": [
    { "<full RegistrationResponse>" }
  ],
  "total": 2
}
```

Items ordered by `registered_at DESC`. Each item is a full `RegistrationResponse` (same shape as POST `/register`).

---

## Developer Diagnostics (Development Only)

> All `/dev/diagnostics/` endpoints return `404` when `APP_ENV != "development"`.
> They require a backend JWT for authentication.

### GET /api/v1/dev/diagnostics/db/tables

Returns a list of all accessible tables with row counts.

```json
{
  "tables": [
    { "name": "event_users", "available": true, "row_count": 1 }
  ]
}
```

---

### GET /api/v1/dev/diagnostics/db/{table_name}

Returns rows from a supported table. Supported tables:

```
event_users, events, sessions, registrations, check_ins,
event_content, event_audit_log, notifications, notification_preferences
```

---

### GET /api/v1/dev/diagnostics/auth/me

Returns the current user from `event_users`, equivalent to a dev-mode `/auth/me`.

---

### GET /api/v1/dev/diagnostics/registrations

Runs 13 end-to-end registration checks against the live backend and database.

**Success response summary:**

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

The 13 checks cover: alumni profile, test event setup (×2), eligibility, register, my-registration, my-registrations list, duplicate guard, capacity guard, join link visibility, confirmation email status, audit log, and public API leak check.

---

## Week 4 Planned Endpoints

Not yet implemented. These stubs exist in the codebase and return `501 Not Implemented`.

### GET /api/v1/events/{event_id}/attendees

**Planned:** Admin attendee list — Week 4

### GET /api/v1/events/{event_id}/attendees/export

**Planned:** Admin CSV attendee export — Week 4

> The admin attendee management endpoints at `/api/v1/admin/events/{event_id}/...` (from
> `admin_events.py`) follow the same pattern but are routed under a different prefix used by
> the EventAdmin portal, not the NITKSAA React Admin Portal.

---

## Deprecated / Invalid Paths from v1

The following paths were listed in `backend_api_index_v1.md` and are either wrong or superseded:

| v1 Path | Status | Correct Path |
|---|---|---|
| `GET /api/v1/events` (public, no auth) | **Wrong** — admin only, requires JWT | `GET /api/v1/events/public` for public listing |
| `GET /api/v1/events/{slug}` | **Wrong** — path param is `event_id` not `slug` | `GET /api/v1/events/{event_id}` (admin) or `GET /api/v1/events/public/{event_id}` (public) |
| `POST /api/v1/events/{id}/register` returning `"status": "confirmed"` | **Wrong status value** | Correct status is `"registered"` |
| `GET /api/v1/events/{id}/my-registration` returning `"status": "confirmed"` | **Wrong** | Correct status is `"registered"` |
| `"confirmation_email_sent": true` | **Wrong field** | Correct field is `"confirmation_email_status": "sent"` |
| `GET /api/v1/dev/diagnostics/audit` | **Not implemented** | Use `GET /api/v1/dev/diagnostics/db/event_audit_log` |
| `DELETE /api/v1/events/{event_id}` | **Not implemented** | Use `PATCH /api/v1/events/{event_id}/status` with `{"status": "cancelled"}` |

---

## Schema Source Reference

| Schema class | File |
|---|---|
| `AlumniProfileResponse` | `backend/app/schemas/registrations.py` |
| `RegistrationResponse` | `backend/app/schemas/registrations.py` |
| `RegistrationEligibilityResponse` | `backend/app/schemas/registrations.py` |
| `MyRegistrationsListResponse` | `backend/app/schemas/registrations.py` |
| `RegisterRequest` | `backend/app/schemas/registrations.py` |
| `EventCreate` | `backend/app/schemas/event_create.py` |
| `EventUpdate` | `backend/app/schemas/event_update.py` |
| `EventStatusUpdate` | `backend/app/schemas/event_status.py` |
| `FirebaseLoginRequest` | `backend/app/api/auth.py` |
| `AuthResponse` | `backend/app/api/auth.py` |
| `CurrentUserResponse` | `backend/app/api/auth.py` |

---

*For detailed response shapes with all fields: `docs/api/week3_actual_api_response_shapes.md`*  
*For join link rules and email confirmation rules: `docs/api/events_api_contract_v2.md`*  
*For manual verification steps: `docs/validation/backend_week3_manual_verification_guide_v2.md`*
