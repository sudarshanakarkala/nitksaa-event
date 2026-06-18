# NITKSAA Event App — Week 3 Backend API Contract v2.0

**File:** `docs/api/week3_backend_api_contract.md`  
**Version:** 2.0  
**Status:** Revised for approval before coding  
**API Base Path:** `/api/v1`  
**Sprint:** Week 3 — Registration, Alumni Autofill, Confirmation Email, Protected Join Link

---

## 1. Goal

Provide complete backend APIs for the frontend team to implement registration flows.

Week 3 user-facing behavior:

```text
Alumni opens event detail.
Alumni signs in.
Alumni profile is autofilled from alumni_db.
Alumni confirms details and registers.
System enforces capacity and deadline.
System prevents duplicate registration.
System generates registration number.
System sends confirmation email.
Virtual event join link becomes visible after registration.
Physical event venue/map details remain visible.
```

Production Flutter screens are not implemented this week. Developer Diagnostics will demonstrate the required UI states.

---

## 2. Authentication

All protected APIs use backend JWT:

```http
Authorization: Bearer <backend_jwt>
```

Backend JWT is obtained from:

```http
POST /api/v1/auth/firebase
```

Do not use Firebase ID token directly for Week 3 APIs.

---

## 3. Public Safety Rule

Public APIs must never expose:

```json
"virtual_url"
"join_url"
```

These APIs remain public-safe:

```http
GET /api/v1/events/public
GET /api/v1/events/public/{event_id}
```

Join link is returned only from authenticated user-specific endpoints after successful registration.

---

## 4. Endpoint Summary

### Alumni/Profile

```http
GET /api/v1/alumni/me
```

### Registration

```http
GET  /api/v1/events/{event_id}/registration-eligibility
POST /api/v1/events/{event_id}/register
GET  /api/v1/events/{event_id}/my-registration
GET  /api/v1/my/registrations
```

### Developer Diagnostics

```http
GET  /api/v1/dev/diagnostics/registrations
POST /api/v1/dev/diagnostics/registrations/run
```

### Deferred to Week 4

```http
GET /api/v1/events/{event_id}/attendees
GET /api/v1/events/{event_id}/attendees/export
```

Do not implement production admin attendee screens in Week 3.

---

## 5. Common Error Format

Use FastAPI-compatible error format:

```json
{
  "detail": {
    "code": "event_full",
    "message": "Event is full."
  }
}
```

If current backend convention only supports string detail, use:

```json
{
  "detail": "event_full"
}
```

Recommended status mapping:

| Case | HTTP | Code |
|---|---:|---|
| Missing/invalid token | 401 | unauthorized |
| Non-alumni user | 403 | alumni_required |
| Inactive alumni | 403 | alumni_not_active |
| Suspended event user | 403 | account_suspended |
| Event not found | 404 | event_not_found |
| Alumni profile not found | 404 | alumni_profile_not_found |
| Event not published | 409 | event_not_published |
| Registration not open yet | 409 | registration_not_open_yet |
| Registration closed | 409 | registration_closed |
| Event full | 409 | event_full |
| Already registered | 409 | already_registered |
| Validation error | 422 | validation_error |
| Server error | 500 | server_error |
| Email provider error | 200/201 with email status failed | email_failed |

---

## 6. Data Types and Naming

### Event Field Names

Backend event storage may use:

```json
"virtual_url"
```

User-facing response after registration should use:

```json
"join_url"
```

Physical event maps should use existing Week 2 field:

```json
"location_maps_url"
```

### Registration Status

Week 3 registration row status values:

```text
registered
cancelled
```

Only `registered` is required for the Week 3 demo. `cancelled` may exist if schema already supports it.

Do not add:

```text
checked_in
attended
waitlisted
paid
```

### Event Registration Status

Computed event-level field:

```text
open
closed
full
not_open_yet
not_applicable
```

---

# 7. GET /api/v1/alumni/me

Returns current alumni profile for autofill.

## Auth

Required.

```http
Authorization: Bearer <backend_jwt>
```

## Request

```http
GET /api/v1/alumni/me
```

## Success 200

```json
{
  "status": "ok",
  "alumni": {
    "ref_id": "ALUMNI123",
    "fullname": "NITKSAA Member",
    "email": "member@example.com",
    "phone": "+919999999999",
    "batch_year": 2010,
    "branch": "Information Technology",
    "is_active": true
  }
}
```

## Frontend Usage

Use this to autofill the registration confirmation screen:

```text
Name
Email
Phone
Batch year
Branch
```

Fields should be read-only for Week 3 unless backend allows updates.

## Errors

```text
401 unauthorized
403 alumni_required
403 alumni_not_active
404 alumni_profile_not_found
500 alumni_db_error
```

---

# 8. GET /api/v1/events/{event_id}/registration-eligibility

Returns whether current user can register and what UI state should be shown.

This endpoint is optional but strongly recommended for diagnostics and frontend clarity.

## Auth

Required.

## Request

```http
GET /api/v1/events/1/registration-eligibility
Authorization: Bearer <backend_jwt>
```

## Success 200 — Can Register

```json
{
  "status": "ok",
  "event": {
    "event_id": 1,
    "title": "Breakfast Club",
    "capacity": 30,
    "registered_count": 12,
    "registration_status": "open",
    "is_virtual": false,
    "location_text": "Bangalore",
    "location_maps_url": "https://maps.example"
  },
  "alumni": {
    "ref_id": "ALUMNI123",
    "fullname": "NITKSAA Member",
    "email": "member@example.com",
    "phone": "+919999999999",
    "batch_year": 2010,
    "branch": "Information Technology"
  },
  "my_registration": null,
  "eligibility": {
    "can_register": true,
    "reason_code": null,
    "ui_state": "can_register",
    "message": "You can register for this event."
  }
}
```

## Success 200 — Already Registered

```json
{
  "status": "ok",
  "event": {
    "event_id": 2,
    "title": "NITKSAA Webinar",
    "capacity": 100,
    "registered_count": 40,
    "registration_status": "open",
    "is_virtual": true
  },
  "my_registration": {
    "registration_id": 101,
    "registration_number": "NITKSAA-2026-000101",
    "registration_status": "registered",
    "registered_at": "2026-06-18T10:00:00+05:30"
  },
  "eligibility": {
    "can_register": false,
    "reason_code": "already_registered",
    "ui_state": "already_registered",
    "message": "You're already registered."
  }
}
```

## UI State Values

```text
login_required
can_register
already_registered
event_full
registration_closed
registration_not_open_yet
event_not_available
alumni_required
alumni_not_active
```

---

# 9. POST /api/v1/events/{event_id}/register

Registers current active alumni for a published event.

## Auth

Required.

## Request

```http
POST /api/v1/events/1/register
Authorization: Bearer <backend_jwt>
Content-Type: application/json
```

```json
{
  "confirm_profile": true,
  "attendee_note": null
}
```

`confirm_profile` should be required and must be `true` to confirm the autofilled profile.

## Success 201 — Physical Event

```json
{
  "status": "ok",
  "registration": {
    "registration_id": 101,
    "registration_number": "NITKSAA-2026-000101",
    "registration_status": "registered",
    "registered_at": "2026-06-18T10:00:00+05:30",
    "cancelled_at": null
  },
  "alumni": {
    "ref_id": "ALUMNI123",
    "fullname": "NITKSAA Member",
    "email": "member@example.com",
    "phone": "+919999999999",
    "batch_year": 2010,
    "branch": "Information Technology"
  },
  "event": {
    "event_id": 1,
    "title": "Breakfast Club",
    "start_datetime": "2026-06-20T09:00:00+05:30",
    "end_datetime": "2026-06-20T11:00:00+05:30",
    "timezone": "Asia/Kolkata",
    "is_virtual": false,
    "location_text": "Bangalore",
    "location_maps_url": "https://maps.example",
    "capacity": 30,
    "registered_count": 13,
    "registration_status": "open"
  },
  "access": {
    "join_url": null,
    "location_maps_url": "https://maps.example"
  },
  "confirmation_email": {
    "status": "sent",
    "sent_at": "2026-06-18T10:00:05+05:30",
    "message": "Confirmation email sent."
  },
  "ui": {
    "state": "registration_confirmed",
    "primary_message": "You're registered.",
    "secondary_message": "Your registration number is NITKSAA-2026-000101."
  }
}
```

## Success 201 — Virtual Event

```json
{
  "status": "ok",
  "registration": {
    "registration_id": 102,
    "registration_number": "NITKSAA-2026-000102",
    "registration_status": "registered",
    "registered_at": "2026-06-18T10:00:00+05:30"
  },
  "event": {
    "event_id": 2,
    "title": "NITKSAA Webinar",
    "start_datetime": "2026-06-21T18:00:00+05:30",
    "end_datetime": "2026-06-21T19:00:00+05:30",
    "timezone": "Asia/Kolkata",
    "is_virtual": true,
    "capacity": 100,
    "registered_count": 41,
    "registration_status": "open"
  },
  "access": {
    "join_url": "https://meet.example/join",
    "location_maps_url": null
  },
  "confirmation_email": {
    "status": "sent",
    "sent_at": "2026-06-18T10:00:05+05:30",
    "message": "Confirmation email sent."
  },
  "ui": {
    "state": "registration_confirmed",
    "primary_message": "You're registered.",
    "secondary_message": "Join link is now available for this webinar."
  }
}
```

## Success 201 — Email Failed But Registration Saved

```json
{
  "status": "ok",
  "registration": {
    "registration_id": 103,
    "registration_number": "NITKSAA-2026-000103",
    "registration_status": "registered"
  },
  "confirmation_email": {
    "status": "failed",
    "sent_at": null,
    "message": "Registration saved, but confirmation email could not be sent."
  },
  "ui": {
    "state": "registration_confirmed_email_failed",
    "primary_message": "You're registered.",
    "secondary_message": "Confirmation email could not be sent. Please save your registration number."
  }
}
```

## Errors

```text
401 unauthorized
403 alumni_required
403 alumni_not_active
404 event_not_found
409 event_not_published
409 registration_not_open_yet
409 registration_closed
409 event_full
409 already_registered
422 confirm_profile_required
500 server_error
```

---

# 10. GET /api/v1/events/{event_id}/my-registration

Returns current user's registration status for one event.

## Auth

Required.

## Request

```http
GET /api/v1/events/2/my-registration
Authorization: Bearer <backend_jwt>
```

## Success 200 — Registered Virtual Event

```json
{
  "status": "ok",
  "registered": true,
  "registration": {
    "registration_id": 102,
    "registration_number": "NITKSAA-2026-000102",
    "registration_status": "registered",
    "registered_at": "2026-06-18T10:00:00+05:30",
    "confirmation_email_status": "sent"
  },
  "event": {
    "event_id": 2,
    "title": "NITKSAA Webinar",
    "start_datetime": "2026-06-21T18:00:00+05:30",
    "end_datetime": "2026-06-21T19:00:00+05:30",
    "timezone": "Asia/Kolkata",
    "is_virtual": true,
    "registration_status": "open",
    "registered_count": 41,
    "capacity": 100
  },
  "access": {
    "join_url": "https://meet.example/join",
    "location_maps_url": null
  },
  "ui": {
    "state": "already_registered",
    "primary_message": "You're already registered.",
    "secondary_message": "Use the join link when the webinar starts."
  }
}
```

## Success 200 — Registered Physical Event

```json
{
  "status": "ok",
  "registered": true,
  "registration": {
    "registration_id": 101,
    "registration_number": "NITKSAA-2026-000101",
    "registration_status": "registered"
  },
  "event": {
    "event_id": 1,
    "title": "Breakfast Club",
    "is_virtual": false,
    "location_text": "Bangalore",
    "location_maps_url": "https://maps.example"
  },
  "access": {
    "join_url": null,
    "location_maps_url": "https://maps.example"
  }
}
```

## Success 200 — Not Registered

```json
{
  "status": "ok",
  "registered": false,
  "registration": null,
  "event": {
    "event_id": 2,
    "title": "NITKSAA Webinar",
    "is_virtual": true,
    "registered_count": 40,
    "capacity": 100,
    "registration_status": "open"
  },
  "access": {
    "join_url": null,
    "location_maps_url": null
  },
  "ui": {
    "state": "can_register",
    "primary_message": "Register",
    "secondary_message": "Please confirm your profile details before registering."
  }
}
```

---

# 11. GET /api/v1/my/registrations

Lists current user's registrations.

## Auth

Required.

## Query Parameters

```text
status optional: registered | cancelled | all
period optional: upcoming | past | all
page optional, default 1
per_page optional, default 20
```

## Success 200

```json
{
  "status": "ok",
  "registrations": [
    {
      "registration_id": 102,
      "registration_number": "NITKSAA-2026-000102",
      "registration_status": "registered",
      "registered_at": "2026-06-18T10:00:00+05:30",
      "confirmation_email_status": "sent",
      "event": {
        "event_id": 2,
        "title": "NITKSAA Webinar",
        "start_datetime": "2026-06-21T18:00:00+05:30",
        "end_datetime": "2026-06-21T19:00:00+05:30",
        "timezone": "Asia/Kolkata",
        "is_virtual": true,
        "location_text": null,
        "location_maps_url": null,
        "registration_status": "open"
      },
      "access": {
        "join_url": "https://meet.example/join"
      }
    }
  ],
  "total": 1,
  "page": 1,
  "per_page": 20
}
```

Rule:

```text
Only include join_url for events where current user has active registered status.
```

---

# 12. Developer Diagnostics APIs

## 12.1 GET /api/v1/dev/diagnostics/registrations

Returns diagnostics metadata and latest status.

Auth:

```text
Backend JWT required.
Development/debug environment only.
```

Success:

```json
{
  "status": "ok",
  "category": "Registration",
  "checks": [
    {
      "name": "Alumni Autofill",
      "endpoint": "GET /api/v1/alumni/me",
      "status": "not_run",
      "ui_state": "profile_autofill"
    },
    {
      "name": "Register Physical Event",
      "endpoint": "POST /api/v1/events/{event_id}/register",
      "status": "not_run",
      "ui_state": "registration_confirmation"
    },
    {
      "name": "Join Link Reveal",
      "endpoint": "GET /api/v1/events/{event_id}/my-registration",
      "status": "not_run",
      "ui_state": "join_link_visible"
    }
  ]
}
```

## 12.2 POST /api/v1/dev/diagnostics/registrations/run

Runs one selected diagnostics scenario.

Request:

```json
{
  "scenario": "register_virtual_event"
}
```

Supported scenarios:

```text
alumni_autofill
eligibility_open
register_physical_event
register_virtual_event
duplicate_registration
event_full
registration_closed
my_registration_join_link
my_registrations_list
email_stub
```

---

# 13. Frontend UI State Contract

Frontend developer should map API responses to these states.

| UI State | Meaning | Primary CTA |
|---|---|---|
| `login_required` | User not signed in | Login |
| `profile_autofill` | Alumni profile loaded | Confirm |
| `can_register` | Event open and user eligible | Register |
| `registration_confirmed` | Registration success | View Registration |
| `registration_confirmed_email_failed` | Registered, email failed | Save Registration Number |
| `already_registered` | Duplicate active registration | View Details |
| `event_full` | Capacity reached | Disabled |
| `registration_closed` | Deadline passed | Disabled |
| `registration_not_open_yet` | Opens later | Disabled |
| `alumni_required` | Non-alumni user | Contact Support |
| `alumni_not_active` | Alumni inactive | Contact Support |

---

# 14. Add to Calendar Contract

Week 3 backend may return calendar metadata; generating `.ics` file can be deferred.

Recommended response section:

```json
"calendar": {
  "title": "Breakfast Club",
  "start_datetime": "2026-06-20T09:00:00+05:30",
  "end_datetime": "2026-06-20T11:00:00+05:30",
  "timezone": "Asia/Kolkata",
  "location": "Bangalore",
  "description": "NITKSAA event registration NITKSAA-2026-000101"
}
```

Diagnostics can show “Add to Calendar prompt” using this data.

---

# 15. Verification Checklist

Backend:

- `GET /alumni/me` returns profile.
- Non-alumni blocked.
- Inactive alumni blocked.
- Register published physical event succeeds.
- Register published virtual event succeeds.
- Duplicate registration blocked.
- Full event blocked.
- Closed event blocked.
- Not-open-yet event blocked.
- Draft event blocked.
- Confirmation number generated.
- Email sent/logged.
- Email failure does not rollback registration.
- Public API does not expose join link.
- My-registration endpoint exposes join link only for registered virtual event.
- Dynamic `registered_count` updates.

Diagnostics:

- All registration UI states visible.
- All diagnostics route guarded.
- Frontend developer can use diagnostics payloads as UI reference.
