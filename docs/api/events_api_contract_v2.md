# NITKSAA Event Platform — API Contract v2

**Version:** 2.0  
**Date:** 2026-06-18  
**Status:** AUTHORITATIVE — supersedes `events_api_contract_v1.md`  
**Source of truth:** Implemented code in `backend/app/api/`, `backend/app/schemas/`, `backend/app/services/`

---

## About This Document

Contract v1 was written as a design specification before implementation. Several response shapes
and field names diverged during implementation. This document reflects the **actual** running code.
Do not use v1 shapes in any new code.

---

## Known Deviations from Contract v1

| Endpoint | v1 Specified | v2 Actual | Impact |
|---|---|---|---|
| `GET /alumni/me` | `{"status": "ok", "alumni": {...}}` wrapper | Flat `AlumniProfileResponse` — no wrapper | Flutter/web must read fields directly from the top-level object |
| `GET /events/{id}/registration-eligibility` | Nested `eligibility` sub-object + `event` sub-object + `my_registration` | Flat object with `eligibility_status`, `message`, `registered_count`, `capacity` | Frontend cannot get event details from this endpoint; needs a separate event fetch |
| `eligibility_status` values | `can_register`, `event_full`, `registration_closed`, `registration_not_open_yet`, `alumni_required`, `alumni_not_active` | `eligible`, `full`, `closed`, `not_open_yet`, `ineligible` (see details below) | Frontend CTA/colour logic must use v2 values |
| `POST /events/{id}/register` request body | `{"confirm_profile": true, "attendee_note": "..."}` | `{"attendee_note": "..."}` only — `confirm_profile` is not a field; extra fields are silently ignored by pydantic | Frontend may send `confirm_profile` but it has no effect; not validated |
| All registration responses | Nested sub-objects: `registration.registration_number`, `alumni.fullname`, `access.join_url`, `confirmation_email.status` | Flat: `registration_number`, `fullname_snapshot`, `join_url`, `confirmation_email_status` | All Flutter/web field paths must use flat names |

---

## Base URL

```
http://localhost:8000    (local development)
```

All endpoints are prefixed with `/api/v1`.

---

## Authentication

All alumni and registration endpoints require a backend JWT in the `Authorization` header:

```
Authorization: Bearer <backend_access_token>
```

Obtain the backend access token by:
1. Firebase sign-in → `idToken`
2. `POST /api/v1/auth/firebase` with `{"idToken": "..."}` → `{"access_token": "..."}`

Public event endpoints do not require authentication.

---

## Alumni Endpoints

### GET /api/v1/alumni/me

Returns the authenticated user's alumni profile from `alumni_db`.

**Auth:** Required  
**Alumni only:** Returns `403` if `user_type != 'alumni'` or `ref_id` is null

**Successful response — HTTP 200:**

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

**Field notes:**
- `ref_id` — maps from `alumni_db.alumni.alumni_id`
- `batch_year` — maps from `alumni_db.alumni.graduationyear`
- `is_active` — `true` when `registrationstatus` is `'Active'` or `'Self-Verified'`; `false` otherwise
- `phone`, `batch_year`, `branch` — optional; may be `null` if not set in alumni_db
- Response is flat — there is no `{"status": "ok", "alumni": {...}}` wrapper

**Error responses:**

| HTTP | detail | Meaning |
|---|---|---|
| 403 | `alumni_only` | `user_type != 'alumni'` or `ref_id` is null in event_users |
| 404 | `alumni_profile_not_found` | `ref_id` not found in alumni_db |

---

## Registration Endpoints

### POST /api/v1/events/{event_id}/register

Register the authenticated alumni for an event.

**Auth:** Required  
**Alumni only:** Returns `403` if user is not alumni or alumni profile is not active  
**Success status:** HTTP 201

**Request body:**

```json
{
  "attendee_note": "optional note, max 500 characters"
}
```

`attendee_note` is the only accepted field. `confirm_profile` was specified in contract v1 but is
not a backend field — the backend uses pydantic's `extra="ignore"` so it will silently discard it
if sent.

**Successful response — HTTP 201:**

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

For a virtual event, `join_url` is populated:

```json
{
  "registration_number": "NITKSAA-2026-000005",
  "join_url": "https://meet.google.com/nitksaa-demo-webinar",
  "event": {
    "is_virtual": true,
    ...
  }
}
```

**Field notes:**
- Response is flat. There are no nested `registration`, `alumni`, `access`, or `confirmation_email` sub-objects.
- `fullname_snapshot`, `email_snapshot`, `phone_snapshot`, `batch_year_snapshot`, `branch_snapshot` — copied from alumni_db at registration time; unchanged if alumni profile changes later
- `email_snapshot` maps from the `registrations.email` column
- `phone_snapshot` maps from the `registrations.phone` column
- `attendee_note` maps from the `registrations.notes` column
- `join_url` — see Join Link Rules section
- `confirmation_email_status` — `"sent"`, `"failed"`, or `"skipped"` — updated post-commit, never blocks registration

**Registration number format:** `NITKSAA-{year}-{registration_id:06d}`  
Example: `NITKSAA-2026-000004` (registration_id=4, year=2026)

**Error responses:**

| HTTP | detail | Meaning |
|---|---|---|
| 403 | `alumni_only` | `user_type != 'alumni'` or no `ref_id` |
| 403 | `alumni_not_found` | `ref_id` not in alumni_db |
| 403 | `alumni_not_active` | `registrationstatus` not in `{'Active', 'Self-Verified'}` |
| 404 | `event_not_found` | `event_id` does not exist |
| 409 | `event_not_published` | `events.status != 'published'` |
| 409 | `registration_not_open_yet` | `now < registration_opens_at` |
| 409 | `registration_closed` | `now > registration_closes_at` |
| 409 | `already_registered` | Active registration exists for this user + event |
| 409 | `event_full` | `COUNT(status='registered') >= capacity` |

**Concurrency safety:** The service issues `SELECT ... FOR UPDATE` on the event row before the
capacity check and INSERT. This prevents double-registration under concurrent requests.

---

### GET /api/v1/events/{event_id}/my-registration

Returns the authenticated user's registration for a specific event.

**Auth:** Required  
**Success status:** HTTP 200

**Successful response:** Same flat `RegistrationResponse` shape as `POST /register`. Key field:
- `join_url` — present only if `status='registered'` AND `is_virtual=true` AND `event_status='published'`

**Error responses:**

| HTTP | detail | Meaning |
|---|---|---|
| 404 | `registration_not_found` | No registration record for this user + event |

---

### GET /api/v1/my/registrations

Returns all registrations for the authenticated user across all events.

**Auth:** Required  
**Success status:** HTTP 200

**Successful response:**

```json
{
  "registrations": [
    {
      "registration_number": "NITKSAA-2026-000005",
      "status": "registered",
      "registered_at": "2026-06-18T09:56:44.833099Z",
      "join_url": "https://meet.google.com/nitksaa-demo-webinar",
      "event": {
        "event_id": 26,
        "title": "Webinar Demo",
        "is_virtual": true,
        "start_datetime": "...",
        "end_datetime": "...",
        "timezone": "Asia/Kolkata",
        "location_text": null,
        "location_maps_url": null
      },
      "registration_id": 5,
      "event_id": 26,
      "firebase_uid": "...",
      "ref_id": "NITK2026IT001",
      "fullname_snapshot": "Username Alumni",
      "email_snapshot": "username2026@gmail.com",
      "phone_snapshot": "+919876543210",
      "batch_year_snapshot": 2026,
      "branch_snapshot": "Information Technology",
      "attendee_note": null,
      "cancelled_at": null,
      "confirmation_email_status": "sent",
      "confirmation_email_sent_at": "...",
      "updated_at": null
    }
  ],
  "total": 2
}
```

**Field notes:**
- `join_url` is at the top level of each item, not nested under `access`
- Items are ordered by `registered_at DESC` (most recent first)
- `total` is the count of items returned

---

### GET /api/v1/events/{event_id}/registration-eligibility

Checks whether the authenticated user can register for the specified event.

**Auth:** Required  
**Success status:** HTTP 200 (always — even when ineligible)

**Successful response:**

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

**`eligibility_status` values — ACTUAL (use these, not v1 values):**

| Value | Meaning | `registered_count` / `capacity` present? |
|---|---|---|
| `eligible` | User can register | Yes — both present |
| `already_registered` | Active registration exists for this user | No |
| `full` | `registered_count >= capacity` | Yes — both present |
| `closed` | `now > registration_closes_at` | No |
| `not_open_yet` | `now < registration_opens_at` | No |
| `ineligible` | Non-alumni, alumni not found, alumni not active, event not found, or event not published — see `message` for reason | No |

> **Frontend note:** The `ineligible` status is a catch-all. Parse the `message` field to distinguish
> the specific reason if you need to display different UI for "not an alumni" vs. "profile not active".
> Alternatively, call `GET /alumni/me` first and gate the registration UI on `is_active == true`.

**Field notes:**
- No `event` sub-object — event title, dates, etc. require a separate `GET /events/public/{id}` call
- No `my_registration` sub-object — use `GET /events/{id}/my-registration` for that
- This endpoint never returns an HTTP error for ineligibility — it always returns 200 with a status string

---

## Public Event Endpoints (No Auth Required)

These endpoints are unchanged from v1 but documented here for completeness.

### GET /api/v1/events/public

Returns a paginated list of published events.

**Security invariant:** `virtual_url` and `join_url` are never present in this response.

**Response shape (per item):**

```json
{
  "event_id": 26,
  "title": "Webinar Demo",
  "description": "...",
  "event_type": "webinar",
  "status": "published",
  "is_virtual": true,
  "location_text": null,
  "location_maps_url": null,
  "start_datetime": "...",
  "end_datetime": "...",
  "timezone": "Asia/Kolkata",
  "capacity": 100,
  "registered_count": 1,
  "registration_opens_at": null,
  "registration_closes_at": null,
  "registration_status": "open"
}
```

Note: `virtual_url` is intentionally absent. `is_virtual: true` tells the frontend the event is
virtual but the join URL is only available after registration.

### GET /api/v1/events/public/{event_id}

Returns a single published event. Same shape as the list item above.

**Security invariant verified:** `virtual_url` key is absent from the response object.

---

## Join Link Rules

`join_url` is computed by `_resolve_join_url()` in `registration_service.py`.

**Rule — `join_url` is non-null only when ALL three conditions are true:**

1. `registrations.status = 'registered'` (not cancelled)
2. `events.is_virtual = true`
3. `events.status = 'published'`

**`join_url` presence matrix:**

| Scenario | join_url |
|---|---|
| Registered, virtual event, published | `"https://..."` (the virtual URL) |
| Registered, physical event, published | `null` |
| Cancelled registration, virtual event | `null` |
| Any public event endpoint | Key absent entirely |
| Any event list / admin endpoint | Key absent entirely |

**Security rule:** `virtual_url` is stored in `events.virtual_url`. It is fetched by the
registration repository's JOIN but is never returned directly in any response. It is only exposed
through `_resolve_join_url()`, which maps it to `join_url` under the three conditions above.

Never read `virtual_url` from an event object and display it as a join link. Use `join_url` from
the registration response.

---

## Email Confirmation Rules

Confirmation emails are sent after the registration transaction commits.

**Policy:**
- Transaction commits → registration is permanent
- `send_confirmation_email()` is called with the committed data
- If email succeeds: `confirmation_email_status = 'sent'`, `confirmation_email_sent_at` = timestamp
- If email fails: `confirmation_email_status = 'failed'`, `confirmation_email_sent_at = null`
- Email failure **never rolls back** the registration

**`confirmation_email_status` values:**

| Value | Meaning |
|---|---|
| `sent` | Email was sent (or logged in development) |
| `failed` | Send attempted but failed — registration is still valid |
| `skipped` | `EMAIL_MODE` is neither `log` nor `send` |

**Frontend rule:** Show `confirmation_email_status` as informational only. If `failed`, show:
_"Confirmation email could not be sent. Please save your registration number."_
Never block or error the confirmation screen based on email status.

**`EMAIL_MODE` settings (backend configuration):**

| Mode | Behaviour |
|---|---|
| `log` (default dev) | Logs to Python logger; returns `status="sent"` |
| `send` | Uses SMTP; returns `status="sent"` or `status="failed"` |
| other | Returns `status="skipped"` |

---

## Error Codes Reference

### Registration Errors (POST /register)

| HTTP | detail | Cause |
|---|---|---|
| 403 | `alumni_only` | `user_type != 'alumni'` OR no `ref_id` in event_users |
| 403 | `alumni_not_found` | `ref_id` not found in alumni_db |
| 403 | `alumni_not_active` | alumni `registrationstatus` not in `{'Active', 'Self-Verified'}` |
| 404 | `event_not_found` | event_id does not exist in events table |
| 409 | `event_not_published` | `events.status != 'published'` (e.g., draft, cancelled) |
| 409 | `registration_not_open_yet` | current time is before `registration_opens_at` |
| 409 | `registration_closed` | current time is after `registration_closes_at` |
| 409 | `already_registered` | active (non-cancelled) registration row exists for this user + event |
| 409 | `event_full` | `COUNT(status='registered') >= events.capacity` |

### My Registration Errors

| HTTP | detail | Cause |
|---|---|---|
| 404 | `registration_not_found` | No row in registrations for this firebase_uid + event_id |

### Alumni Profile Errors

| HTTP | detail | Cause |
|---|---|---|
| 403 | `alumni_only` | `user_type != 'alumni'` OR no `ref_id` |
| 404 | `alumni_profile_not_found` | `ref_id` not found in alumni_db |

---

## Data Sources

| Data | Source |
|---|---|
| Alumni profile (fullname, email, phone, batch_year, branch) | `alumni_db.alumni` — authoritative |
| Snapshot fields in registrations | Copied from alumni_db at registration time; does not change if alumni profile changes |
| Event details in registration response | `events_db.events` via JOIN in repository query |
| virtual_url | `events_db.events.virtual_url` — fetched but never directly returned; only via `join_url` |
| registered_count | Live correlated subquery: `SELECT COUNT(*) FROM registrations WHERE event_id=? AND status='registered'` |

---

## Frontend Registration Flow

The recommended integration sequence for the production registration UI:

```
① GET /api/v1/alumni/me
      ↓ AlumniProfileResponse (flat)
      Display read-only profile fields
      Check is_active — if false, show error state

② GET /api/v1/events/{id}/registration-eligibility   [optional pre-check]
      ↓ RegistrationEligibilityResponse
      Use eligibility_status to determine CTA:
        "eligible"           → show Register button
        "already_registered" → show View My Registration button
        "full"               → disable Register, show "Event is full"
        "closed"             → disable Register, show "Registration is closed"
        "not_open_yet"       → disable Register, show "Registration opens on {date}"
        "ineligible"         → show error from message field

③ POST /api/v1/events/{id}/register
      Body: {"attendee_note": "optional"}
      ↓ RegistrationResponse (flat, HTTP 201)
      Show confirmation screen:
        - registration_number (prominent, monospace font)
        - join_url (only if event.is_virtual == true AND join_url != null)
        - confirmation_email_status (non-blocking row)

④ GET /api/v1/events/{id}/my-registration
      ↓ RegistrationResponse
      Show registration detail card

⑤ GET /api/v1/my/registrations
      ↓ { registrations: [...], total: N }
      Show registrations list
```

---

## Pydantic Schemas (Actual)

### `RegisterRequest`

```python
class RegisterRequest(BaseModel):
    attendee_note: Optional[str] = Field(None, max_length=500)
```

### `AlumniProfileResponse`

```python
class AlumniProfileResponse(BaseModel):
    ref_id: str
    fullname: str
    email: str
    phone: Optional[str] = None
    batch_year: Optional[int] = None
    branch: Optional[str] = None
    is_active: bool
```

### `EventSummary`

```python
class EventSummary(BaseModel):
    event_id: int
    title: str
    start_datetime: datetime
    end_datetime: datetime
    timezone: str
    is_virtual: bool
    location_text: Optional[str] = None
    location_maps_url: Optional[str] = None
```

### `RegistrationResponse`

```python
class RegistrationResponse(BaseModel):
    registration_id: int
    registration_number: Optional[str] = None
    event_id: int
    firebase_uid: str
    ref_id: Optional[str] = None
    status: str
    fullname_snapshot: Optional[str] = None
    email_snapshot: Optional[str] = None
    phone_snapshot: Optional[str] = None
    batch_year_snapshot: Optional[int] = None
    branch_snapshot: Optional[str] = None
    attendee_note: Optional[str] = None
    registered_at: datetime
    cancelled_at: Optional[datetime] = None
    confirmation_email_status: Optional[str] = None
    confirmation_email_sent_at: Optional[datetime] = None
    join_url: Optional[str] = None
    event: Optional[EventSummary] = None
    updated_at: Optional[datetime] = None
```

### `RegistrationEligibilityResponse`

```python
class RegistrationEligibilityResponse(BaseModel):
    event_id: int
    firebase_uid: str
    eligibility_status: str
    message: str
    registered_count: Optional[int] = None
    capacity: Optional[int] = None
```

### `MyRegistrationsListResponse`

```python
class MyRegistrationsListResponse(BaseModel):
    registrations: List[RegistrationResponse]
    total: int
```

---

## Out of Scope (Not Yet Implemented)

The following are not implemented and have no functional endpoints:

| Feature | Status |
|---|---|
| Admin registration management | `501 Not Implemented` stub |
| Attendance / check-in | Not started |
| QR code | Not started |
| Waitlist | Not started |
| Payment | Not started |
| Registration cancellation | Not started (no `cancel` endpoint exists) |

---

## Changelog

| Version | Date | Changes |
|---|---|---|
| v1.0 | Week 3 (before implementation) | Original design spec |
| v2.0 | 2026-06-18 | Updated to match actual implementation: flat response shapes, actual eligibility_status values, removed confirm_profile from RegisterRequest, documented join link and email rules |
