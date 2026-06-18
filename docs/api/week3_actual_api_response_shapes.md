# Week 3 — Actual API Response Shapes

**Version:** 1.0  
**Date:** 2026-06-18  
**Status:** Runtime-verified — derived from `backend/app/schemas/registrations.py` and
`backend/app/services/registration_service.py`

> This document provides verbatim JSON shapes for every Week 3 registration endpoint.
> All examples reflect the actual running implementation.
> Use these shapes when building Flutter production UI or writing integration tests.
>
> **Authoritative reference:** `docs/api/events_api_contract_v2.md`  
> This file provides standalone JSON examples; the contract v2 provides full field notes and rules.

---

## Common Notes

- All registration responses are **flat**. There are no nested `registration`, `alumni`, `access`,
  or `confirmation_email` sub-objects.
- `event` is a nested sub-object inside `RegistrationResponse`. It is not the registration record itself.
- `is_virtual` lives at `event.is_virtual`, not at the top level of the registration response.
- `join_url` is a **top-level** field (not inside `event`).
- `registrationstatus` is never returned in any API response — it is computed server-side into `is_active`.

---

## 1. GET /api/v1/alumni/me

Returns the authenticated user's alumni profile from `alumni_db`.

**Schema:** `AlumniProfileResponse` (`backend/app/schemas/registrations.py`)

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

**Field mapping (DB → API):**

| `alumni_db.alumni` column | API field | Notes |
|---|---|---|
| `alumni_id` | `ref_id` | Primary identifier |
| `fullname` | `fullname` | Direct |
| `email` | `email` | Direct |
| `phone` | `phone` | Nullable |
| `graduationyear` | `batch_year` | Renamed |
| `branch` | `branch` | Nullable |
| `registrationstatus` | _(not in response)_ | Computed → `is_active` |

**Nullable fields:**

`phone`, `batch_year`, `branch` may be `null` if not set in `alumni_db`.

```json
{
  "ref_id": "NITK2026IT001",
  "fullname": "Username Alumni",
  "email": "username2026@gmail.com",
  "phone": null,
  "batch_year": null,
  "branch": null,
  "is_active": true
}
```

**Error responses:**

| HTTP | `detail` | Cause |
|---|---|---|
| 401 | (standard auth error) | No or invalid token |
| 403 | `alumni_only` | `user_type != "alumni"` or `ref_id` is null |
| 404 | `alumni_profile_not_found` | `ref_id` not found in `alumni_db` |

---

## 2. GET /api/v1/events/{event_id}/registration-eligibility

Checks whether the authenticated user can register for the event.

**Schema:** `RegistrationEligibilityResponse` (`backend/app/schemas/registrations.py`)

**Always returns HTTP 200** — even when ineligible. Never returns a 4xx for eligibility reasons.

### 2a. Eligible

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

### 2b. Already Registered

```json
{
  "event_id": 25,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "eligibility_status": "already_registered",
  "message": "You are already registered for this event.",
  "registered_count": null,
  "capacity": null
}
```

### 2c. Event Full

```json
{
  "event_id": 34,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "eligibility_status": "full",
  "message": "Event is at full capacity.",
  "registered_count": 1,
  "capacity": 1
}
```

### 2d. Registration Closed

```json
{
  "event_id": 35,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "eligibility_status": "closed",
  "message": "Registration is closed.",
  "registered_count": null,
  "capacity": null
}
```

### 2e. Registration Not Open Yet

```json
{
  "event_id": 36,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "eligibility_status": "not_open_yet",
  "message": "Registration has not opened yet.",
  "registered_count": null,
  "capacity": null
}
```

### 2f. Ineligible — Non-Alumni

```json
{
  "event_id": 25,
  "firebase_uid": "some-other-firebase-uid",
  "eligibility_status": "ineligible",
  "message": "Only alumni can register for events.",
  "registered_count": null,
  "capacity": null
}
```

### 2g. Ineligible — Alumni Not Active (or not found in alumni_db)

```json
{
  "event_id": 25,
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "eligibility_status": "ineligible",
  "message": "Alumni account is not active.",
  "registered_count": null,
  "capacity": null
}
```

> **Note:** Both `alumni_not_found` and `alumni_not_active` cases return
> `eligibility_status: "ineligible"` with the same message. The POST `/register` endpoint
> distinguishes them with separate `detail` codes (`alumni_not_found` vs `alumni_not_active`).

### `eligibility_status` values — complete list

| Value | Condition | `registered_count` present? |
|---|---|---|
| `eligible` | Can register | Yes |
| `already_registered` | Active registration exists | No |
| `full` | `COUNT(status='registered') >= capacity` | Yes |
| `closed` | `now > registration_closes_at` | No |
| `not_open_yet` | `now < registration_opens_at` | No |
| `ineligible` | Non-alumni, inactive, not found, or event not published | No |

---

## 3. POST /api/v1/events/{event_id}/register

Registers the authenticated alumni for the event.

**Request body:**

```json
{
  "attendee_note": "optional string, max 500 chars"
}
```

Empty body `{}` is also valid — `attendee_note` defaults to `null`.

**Schema:** `RegistrationResponse` (`backend/app/schemas/registrations.py`)

**Successful response — HTTP 201:**

### 3a. Physical event (join_url is null)

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
    "location_text": "NIT Karnataka, Surathkal",
    "location_maps_url": null
  },
  "updated_at": null
}
```

### 3b. Virtual event (join_url is populated)

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
  "registered_at": "2026-06-18T09:56:44.833099Z",
  "cancelled_at": null,
  "confirmation_email_status": "sent",
  "confirmation_email_sent_at": "2026-06-18T09:56:44.851032Z",
  "join_url": "https://meet.google.com/nitksaa-demo-webinar",
  "event": {
    "event_id": 26,
    "title": "Webinar Demo",
    "start_datetime": "2026-08-02T00:56:44.833099Z",
    "end_datetime": "2026-08-02T02:56:44.833099Z",
    "timezone": "Asia/Kolkata",
    "is_virtual": true,
    "location_text": null,
    "location_maps_url": null
  },
  "updated_at": null
}
```

**Field notes:**

| Field | Source | Notes |
|---|---|---|
| `registration_id` | DB auto-increment | `SERIAL` PK |
| `registration_number` | Service-generated | Format: `NITKSAA-{year}-{registration_id:06d}` |
| `email_snapshot` | `registrations.email` | DB column alias |
| `phone_snapshot` | `registrations.phone` | DB column alias |
| `attendee_note` | `registrations.notes` | DB column alias |
| `confirmation_email_status` | Updated post-commit | `"sent"`, `"failed"`, or `"skipped"` |
| `join_url` | Resolved by service | Non-null only for registered + virtual + published |
| `event` | Joined from `events` table | Nested sub-object |
| `event.is_virtual` | `events.is_virtual` | NOT at top level of RegistrationResponse |

**Error responses:**

| HTTP | `detail` | Cause |
|---|---|---|
| 403 | `alumni_only` | `user_type != "alumni"` or no `ref_id` |
| 403 | `alumni_not_found` | `ref_id` not in `alumni_db` |
| 403 | `alumni_not_active` | `registrationstatus` not in `{'Active', 'Self-Verified'}` |
| 404 | `event_not_found` | `event_id` does not exist |
| 409 | `event_not_published` | `events.status != "published"` |
| 409 | `registration_not_open_yet` | `now < registration_opens_at` |
| 409 | `registration_closed` | `now > registration_closes_at` |
| 409 | `already_registered` | Active registration already exists |
| 409 | `event_full` | `COUNT(status='registered') >= capacity` |

---

## 4. GET /api/v1/events/{event_id}/my-registration

Returns the user's most recent registration for a specific event.

**Schema:** Same `RegistrationResponse` as POST /register (§3 above).

**Successful response — HTTP 200:**

Same shape as §3. Key difference: `join_url` reflects the current event state at query time.
If the event was published at registration but later cancelled, `join_url` will be `null`.

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
  "registered_at": "2026-06-18T09:56:44.833099Z",
  "cancelled_at": null,
  "confirmation_email_status": "sent",
  "confirmation_email_sent_at": "2026-06-18T09:56:44.851032Z",
  "join_url": "https://meet.google.com/nitksaa-demo-webinar",
  "event": {
    "event_id": 26,
    "title": "Webinar Demo",
    "start_datetime": "2026-08-02T00:56:44.833099Z",
    "end_datetime": "2026-08-02T02:56:44.833099Z",
    "timezone": "Asia/Kolkata",
    "is_virtual": true,
    "location_text": null,
    "location_maps_url": null
  },
  "updated_at": null
}
```

**join_url visibility rules:**

| Condition | `join_url` |
|---|---|
| `status="registered"` AND `is_virtual=true` AND `event_status="published"` | Non-null (the URL) |
| Any condition fails | `null` |

**Error responses:**

| HTTP | `detail` | Cause |
|---|---|---|
| 404 | `registration_not_found` | No registration record for this user + event |

---

## 5. GET /api/v1/my/registrations

Returns all registrations for the authenticated user across all events.

**Schema:** `MyRegistrationsListResponse` (`backend/app/schemas/registrations.py`)

**Successful response — HTTP 200:**

```json
{
  "registrations": [
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
      "registered_at": "2026-06-18T09:56:44.833099Z",
      "cancelled_at": null,
      "confirmation_email_status": "sent",
      "confirmation_email_sent_at": "2026-06-18T09:56:44.851032Z",
      "join_url": "https://meet.google.com/nitksaa-demo-webinar",
      "event": {
        "event_id": 26,
        "title": "Webinar Demo",
        "start_datetime": "2026-08-02T00:56:44.833099Z",
        "end_datetime": "2026-08-02T02:56:44.833099Z",
        "timezone": "Asia/Kolkata",
        "is_virtual": true,
        "location_text": null,
        "location_maps_url": null
      },
      "updated_at": null
    },
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
        "location_text": "NIT Karnataka, Surathkal",
        "location_maps_url": null
      },
      "updated_at": null
    }
  ],
  "total": 2
}
```

**Field notes:**

- Items are ordered by `registered_at DESC` (most recent first).
- `total` is the count of items in the `registrations` array.
- Each item is a full `RegistrationResponse` — same shape as §3/§4.
- `join_url` at top level of each item (not nested under `event`).
- `event.is_virtual` inside nested `event` object.

---

## Two-Code Cross-Reference

> **Critical:** The eligibility endpoint and POST register endpoint use **different string values**
> for the same semantic states. Never mix them.

| UI State | `eligibility_status` (GET) | `detail` (POST error) |
|---|---|---|
| Event full | `full` | `event_full` |
| Registration closed | `closed` | `registration_closed` |
| Not open yet | `not_open_yet` | `registration_not_open_yet` |
| Already registered | `already_registered` | `already_registered` |
| Non-alumni | `ineligible` (msg: "Only alumni…") | `alumni_only` |
| Alumni not active | `ineligible` (msg: "Alumni account is not active.") | `alumni_not_active` |
| Alumni not found | `ineligible` (msg: "Alumni account is not active.") | `alumni_not_found` |
| Not published | `ineligible` (msg: "Event is not open for registration.") | `event_not_published` |
| Can register | `eligible` | _(no error)_ |

---

## Schema Source Reference

| Schema class | File |
|---|---|
| `AlumniProfileResponse` | `backend/app/schemas/registrations.py:18` |
| `EventSummary` | `backend/app/schemas/registrations.py:30` |
| `RegistrationResponse` | `backend/app/schemas/registrations.py:43` |
| `RegistrationEligibilityResponse` | `backend/app/schemas/registrations.py:77` |
| `MyRegistrationsListResponse` | `backend/app/schemas/registrations.py:88` |
| `RegisterRequest` | `backend/app/schemas/registrations.py:8` |
