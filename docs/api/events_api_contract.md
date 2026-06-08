# NITKSAA Event App — Week 2 Backend API Contract

**File:** `docs/api/events_api_contract.md`
**Version:** 1.0
**Status:** Approved for Week 2 Implementation
**API Base Path:** `/api/v1`
**Sprint:** Week 2 — Event Creation and Public Listing

---

# 1. Week 2 Goal

Staff can create events.

Public users can browse published events.

Public users can view published event details.

No registration functionality in Week 2.

No attendee management in Week 2.

No email functionality in Week 2.

---

# 2. Architecture Rules

1. Backend APIs must be implemented before UI.
2. Developer Diagnostics must pass before Admin or Flutter UI verification.
3. Flutter and Admin Portal must communicate only through APIs.
4. No direct database access from Flutter or Admin Portal.
5. Existing authentication flow must not be changed.
6. Protected APIs must use internal backend JWT.
7. Admin APIs require admin permission.
8. Public APIs must not require authentication.
9. Public APIs must never expose virtual meeting links.
10. API response fields must remain stable for Week 3 registration work.

---

# 3. API Versioning Policy

Current API version:

```text
/api/v1
```

Rules:

* Do not introduce breaking changes within `/api/v1`.
* New optional fields may be added later.
* Existing field names must remain stable.
* Existing response structures must remain stable.
* Breaking changes require a new API version.
* Flutter App, Admin Portal, and future Website integration must use the same contract.

---

# 4. Authentication and Authorization

## 4.1 Public APIs

No authentication required.

Public APIs:

```http
GET /api/v1/events/public
GET /api/v1/events/public/{event_id}
```

## 4.2 Admin APIs

Authentication required.

Admin APIs require:

```http
Authorization: Bearer <backend_jwt>
```

Admin APIs:

```http
POST   /api/v1/events
GET    /api/v1/events
GET    /api/v1/events/{event_id}
PATCH  /api/v1/events/{event_id}
DELETE /api/v1/events/{event_id}
PATCH  /api/v1/events/{event_id}/status
```

## 4.3 Admin Permission Rule

For Week 2, use the existing backend JWT/admin authorization model.

Minimum requirement:

```text
current_user.is_admin == true
```

Do not create a new role hierarchy in Week 2.

Backend must enforce this rule.

UI hiding is not security.

---

# 5. Event Status Values

Supported Week 2 status values:

```text
draft
published
cancelled
completed
```

Week 2 required transitions:

```text
draft -> published
published -> draft
published -> cancelled
draft -> cancelled
```

`completed` may be reserved for later automation/manual admin update.

---

# 6. Event Type Mapping

The database/backend should use:

```json
"is_virtual": true
```

Frontend may display this as:

```text
Virtual
```

The database/backend should use:

```json
"is_virtual": false
```

Frontend may display this as:

```text
In-person
```

---

# 7. Field Naming Decision

Use backend/database-aligned field names.

## 7.1 Virtual Meeting Link

Use:

```json
"virtual_url"
```

Do not use `join_url` in backend response fields.

Admin UI may label this field as:

```text
Join URL
```

Public APIs must never expose:

```json
"virtual_url"
```

## 7.2 Registration Deadline

Use:

```json
"registration_closes_at"
```

Admin UI may label this field as:

```text
Registration Deadline
```

Optional future field:

```json
"registration_opens_at"
```

---

# 8. Core Event Fields

## 8.1 Admin Event Object

Admin APIs may return the full event object.

```json
{
  "event_id": 1,
  "slug": "breakfast-club-bangalore",
  "title": "Breakfast Club",
  "tagline": null,
  "description": "Monthly NITKSAA alumni breakfast meetup.",
  "status": "draft",
  "start_datetime": "2026-06-12T09:00:00+05:30",
  "end_datetime": "2026-06-12T11:00:00+05:30",
  "timezone": "Asia/Kolkata",
  "location_text": "Bangalore",
  "location_maps_url": null,
  "is_virtual": false,
  "virtual_url": null,
  "thumbnail_url": null,
  "banner_url": null,
  "capacity": 30,
  "registration_opens_at": null,
  "registration_closes_at": "2026-06-11T23:59:00+05:30",
  "registered_count": 0,
  "registration_status": "open",
  "created_by_firebase_uid": "firebase_uid",
  "created_by_name": "NITKSAA Admin",
  "created_at": "2026-06-08T10:00:00+05:30",
  "updated_at": null,
  "published_at": null,
  "cancelled_at": null,
  "cancelled_reason": null
}
```

## 8.2 Public Event Object

Public APIs must return only safe fields.

```json
{
  "event_id": 1,
  "slug": "breakfast-club-bangalore",
  "title": "Breakfast Club",
  "tagline": null,
  "description": "Monthly NITKSAA alumni breakfast meetup.",
  "status": "published",
  "start_datetime": "2026-06-12T09:00:00+05:30",
  "end_datetime": "2026-06-12T11:00:00+05:30",
  "timezone": "Asia/Kolkata",
  "location_text": "Bangalore",
  "location_maps_url": null,
  "is_virtual": false,
  "thumbnail_url": null,
  "banner_url": null,
  "capacity": 30,
  "registered_count": 0,
  "registration_status": "open",
  "published_at": "2026-06-08T10:30:00+05:30"
}
```

Public APIs must not return:

```json
"virtual_url"
"created_by_firebase_uid"
"created_by_name"
"audit information"
"internal notes"
"draft events"
"unpublished events"
```

---

# 9. Computed Fields

## 9.1 registered_count

For Week 2:

```json
"registered_count": 0
```

Registration is not implemented in Week 2, but this field must exist for Week 3 compatibility.

## 9.2 registration_status

Allowed values:

```text
open
closed
full
not_open_yet
not_applicable
```

Week 2 recommended logic:

* If event status is not `published`, return `not_applicable`.
* If capacity is not null and registered_count >= capacity, return `full`.
* If registration_opens_at is set and current time is before registration_opens_at, return `not_open_yet`.
* If registration_closes_at is set and current time is after registration_closes_at, return `closed`.
* Otherwise return `open`.

---

# 10. Error Response Format

Use FastAPI default-compatible error format:

```json
{
  "detail": "Error message"
}
```

HTTP status rules:

| Case                        | Status |
| --------------------------- | ------ |
| Missing or invalid token    | 401    |
| Authenticated but not admin | 403    |
| Event not found             | 404    |
| Invalid status transition   | 409    |
| Validation error            | 422    |
| Server error                | 500    |

---

# 11. Admin API Endpoints

---

## 11.1 Create Event

```http
POST /api/v1/events
```

Authentication:

```text
Required
```

Authorization:

```text
Admin only
```

Request:

```json
{
  "title": "Breakfast Club",
  "tagline": "Monthly alumni meetup",
  "description": "Monthly NITKSAA alumni breakfast meetup.",
  "start_datetime": "2026-06-12T09:00:00+05:30",
  "end_datetime": "2026-06-12T11:00:00+05:30",
  "timezone": "Asia/Kolkata",
  "location_text": "Bangalore",
  "location_maps_url": null,
  "is_virtual": false,
  "virtual_url": null,
  "thumbnail_url": null,
  "banner_url": null,
  "capacity": 30,
  "registration_opens_at": null,
  "registration_closes_at": "2026-06-11T23:59:00+05:30"
}
```

Required fields:

```text
title
start_datetime
end_datetime
timezone
is_virtual
```

Conditional validation:

If `is_virtual = true`:

```text
virtual_url is required for Admin API storage
location_text may be null
```

If `is_virtual = false`:

```text
location_text is required
virtual_url must be null
```

Default status:

```text
draft
```

Backend behavior:

1. Validate admin JWT.
2. Validate request.
3. Generate slug from title.
4. Insert event as draft.
5. Store created_by_firebase_uid.
6. Write audit log: Event Created.
7. Return created event.

Success response:

```json
{
  "status": "ok",
  "event": {
    "event_id": 1,
    "slug": "breakfast-club",
    "title": "Breakfast Club",
    "tagline": "Monthly alumni meetup",
    "description": "Monthly NITKSAA alumni breakfast meetup.",
    "status": "draft",
    "start_datetime": "2026-06-12T09:00:00+05:30",
    "end_datetime": "2026-06-12T11:00:00+05:30",
    "timezone": "Asia/Kolkata",
    "location_text": "Bangalore",
    "location_maps_url": null,
    "is_virtual": false,
    "virtual_url": null,
    "thumbnail_url": null,
    "banner_url": null,
    "capacity": 30,
    "registration_opens_at": null,
    "registration_closes_at": "2026-06-11T23:59:00+05:30",
    "registered_count": 0,
    "registration_status": "not_applicable",
    "created_by_firebase_uid": "firebase_uid",
    "created_by_name": "NITKSAA Admin",
    "created_at": "2026-06-08T10:00:00+05:30",
    "updated_at": null,
    "published_at": null,
    "cancelled_at": null,
    "cancelled_reason": null
  }
}
```

---

## 11.2 List Events — Admin

```http
GET /api/v1/events
```

Authentication:

```text
Required
```

Authorization:

```text
Admin only
```

Query parameters:

```text
page optional, default 1
per_page optional, default 20
status optional
is_virtual optional
search optional
```

Example:

```http
GET /api/v1/events?page=1&per_page=20&status=draft
```

Success response:

```json
{
  "events": [
    {
      "event_id": 1,
      "slug": "breakfast-club",
      "title": "Breakfast Club",
      "tagline": "Monthly alumni meetup",
      "description": "Monthly NITKSAA alumni breakfast meetup.",
      "status": "draft",
      "start_datetime": "2026-06-12T09:00:00+05:30",
      "end_datetime": "2026-06-12T11:00:00+05:30",
      "timezone": "Asia/Kolkata",
      "location_text": "Bangalore",
      "location_maps_url": null,
      "is_virtual": false,
      "virtual_url": null,
      "thumbnail_url": null,
      "banner_url": null,
      "capacity": 30,
      "registration_opens_at": null,
      "registration_closes_at": "2026-06-11T23:59:00+05:30",
      "registered_count": 0,
      "registration_status": "not_applicable",
      "created_by_firebase_uid": "firebase_uid",
      "created_by_name": "NITKSAA Admin",
      "created_at": "2026-06-08T10:00:00+05:30",
      "updated_at": null,
      "published_at": null,
      "cancelled_at": null,
      "cancelled_reason": null
    }
  ],
  "total": 1,
  "page": 1,
  "per_page": 20
}
```

---

## 11.3 Get Event Detail — Admin

```http
GET /api/v1/events/{event_id}
```

Authentication:

```text
Required
```

Authorization:

```text
Admin only
```

Success response:

```json
{
  "event": {
    "event_id": 1,
    "slug": "breakfast-club",
    "title": "Breakfast Club",
    "tagline": "Monthly alumni meetup",
    "description": "Monthly NITKSAA alumni breakfast meetup.",
    "status": "draft",
    "start_datetime": "2026-06-12T09:00:00+05:30",
    "end_datetime": "2026-06-12T11:00:00+05:30",
    "timezone": "Asia/Kolkata",
    "location_text": "Bangalore",
    "location_maps_url": null,
    "is_virtual": false,
    "virtual_url": null,
    "thumbnail_url": null,
    "banner_url": null,
    "capacity": 30,
    "registration_opens_at": null,
    "registration_closes_at": "2026-06-11T23:59:00+05:30",
    "registered_count": 0,
    "registration_status": "not_applicable",
    "created_by_firebase_uid": "firebase_uid",
    "created_by_name": "NITKSAA Admin",
    "created_at": "2026-06-08T10:00:00+05:30",
    "updated_at": null,
    "published_at": null,
    "cancelled_at": null,
    "cancelled_reason": null
  }
}
```

---

## 11.4 Update Event

```http
PATCH /api/v1/events/{event_id}
```

Authentication:

```text
Required
```

Authorization:

```text
Admin only
```

Request:

All fields optional.

```json
{
  "title": "Updated Breakfast Club",
  "tagline": "Updated alumni meetup",
  "description": "Updated event description.",
  "start_datetime": "2026-06-12T09:30:00+05:30",
  "end_datetime": "2026-06-12T11:30:00+05:30",
  "timezone": "Asia/Kolkata",
  "location_text": "Bangalore",
  "location_maps_url": null,
  "is_virtual": false,
  "virtual_url": null,
  "thumbnail_url": null,
  "banner_url": null,
  "capacity": 30,
  "registration_opens_at": null,
  "registration_closes_at": "2026-06-11T23:59:00+05:30"
}
```

Backend behavior:

1. Validate admin JWT.
2. Validate event exists.
3. Validate fields.
4. Update event.
5. Set updated_at.
6. Write audit log: Event Updated.
7. Return updated event.

Important:

* Do not change slug automatically after event is published.
* If title changes while event is still draft, slug may be regenerated only if approved by implementation team.
* Public event links should remain stable.

Success response:

```json
{
  "status": "ok",
  "event": {
    "event_id": 1,
    "slug": "breakfast-club",
    "title": "Updated Breakfast Club",
    "status": "draft",
    "start_datetime": "2026-06-12T09:30:00+05:30",
    "end_datetime": "2026-06-12T11:30:00+05:30",
    "timezone": "Asia/Kolkata",
    "location_text": "Bangalore",
    "is_virtual": false,
    "virtual_url": null,
    "capacity": 30,
    "registration_closes_at": "2026-06-11T23:59:00+05:30",
    "registered_count": 0,
    "registration_status": "not_applicable",
    "updated_at": "2026-06-08T11:00:00+05:30"
  }
}
```

---

## 11.5 Delete Event

```http
DELETE /api/v1/events/{event_id}
```

Authentication:

```text
Required
```

Authorization:

```text
Admin only
```

Week 2 behavior:

Use soft delete if existing schema supports it.

Recommended Week 2 implementation:

```text
Set status = cancelled
Set cancelled_at = now()
Set cancelled_reason = "Deleted by admin"
```

Do not physically delete if registrations will depend on this table in Week 3.

Backend behavior:

1. Validate admin JWT.
2. Validate event exists.
3. Mark event cancelled/deleted.
4. Write audit log: Event Deleted.
5. Return success.

Success response:

```json
{
  "status": "ok",
  "message": "Event deleted successfully",
  "event_id": 1
}
```

If hard delete is used for temporary diagnostic-created events only, it must not be used for real published events without approval.

---

## 11.6 Change Event Status

```http
PATCH /api/v1/events/{event_id}/status
```

Authentication:

```text
Required
```

Authorization:

```text
Admin only
```

Request:

```json
{
  "status": "published"
}
```

Allowed request values:

```text
draft
published
cancelled
completed
```

Backend behavior:

If status is `published`:

1. Validate required event fields.
2. Set status = published.
3. Set published_at = now() if not already set.
4. Write audit log: Event Published.

If status is `draft` from published:

1. Set status = draft.
2. Do not clear published_at unless implementation team approves.
3. Write audit log: Event Unpublished.

If status is `cancelled`:

1. Set status = cancelled.
2. Set cancelled_at = now().
3. Write audit log: Event Cancelled.

Success response:

```json
{
  "status": "ok",
  "event": {
    "event_id": 1,
    "slug": "breakfast-club",
    "title": "Breakfast Club",
    "status": "published",
    "published_at": "2026-06-08T10:30:00+05:30",
    "registration_status": "open"
  }
}
```

Validation before publishing:

Physical event requires:

```text
title
description
start_datetime
end_datetime
timezone
location_text
capacity
```

Virtual event requires:

```text
title
description
start_datetime
end_datetime
timezone
virtual_url
capacity
```

---

# 12. Public API Endpoints

---

## 12.1 Public Event Listing

```http
GET /api/v1/events/public
```

Authentication:

```text
Not required
```

Returns:

```text
Published events only
```

Must exclude:

```text
virtual_url
created_by_firebase_uid
created_by_name
audit information
draft events
cancelled events unless explicitly allowed later
```

Query parameters:

```text
page optional, default 1
per_page optional, default 20
period optional: upcoming | past | all
```

Example:

```http
GET /api/v1/events/public?period=upcoming&page=1&per_page=20
```

Success response:

```json
{
  "events": [
    {
      "event_id": 1,
      "slug": "breakfast-club",
      "title": "Breakfast Club",
      "tagline": "Monthly alumni meetup",
      "description": "Monthly NITKSAA alumni breakfast meetup.",
      "status": "published",
      "start_datetime": "2026-06-12T09:00:00+05:30",
      "end_datetime": "2026-06-12T11:00:00+05:30",
      "timezone": "Asia/Kolkata",
      "location_text": "Bangalore",
      "location_maps_url": null,
      "is_virtual": false,
      "thumbnail_url": null,
      "banner_url": null,
      "capacity": 30,
      "registered_count": 0,
      "registration_status": "open",
      "published_at": "2026-06-08T10:30:00+05:30"
    }
  ],
  "total": 1,
  "page": 1,
  "per_page": 20
}
```

Flutter usage:

* Upcoming tab calls `period=upcoming`.
* Past tab calls `period=past`.

---

## 12.2 Public Event Detail

```http
GET /api/v1/events/public/{event_id}
```

Authentication:

```text
Not required
```

Returns:

```text
Published event only
```

Must exclude:

```text
virtual_url
created_by_firebase_uid
created_by_name
audit information
internal notes
```

Success response:

```json
{
  "event": {
    "event_id": 1,
    "slug": "breakfast-club",
    "title": "Breakfast Club",
    "tagline": "Monthly alumni meetup",
    "description": "Monthly NITKSAA alumni breakfast meetup.",
    "status": "published",
    "start_datetime": "2026-06-12T09:00:00+05:30",
    "end_datetime": "2026-06-12T11:00:00+05:30",
    "timezone": "Asia/Kolkata",
    "location_text": "Bangalore",
    "location_maps_url": null,
    "is_virtual": false,
    "thumbnail_url": null,
    "banner_url": null,
    "capacity": 30,
    "registered_count": 0,
    "registration_status": "open",
    "sessions": [],
    "speakers": [],
    "published_at": "2026-06-08T10:30:00+05:30"
  }
}
```

Week 2 speaker rule:

If speaker/session data is not implemented yet, return:

```json
"speakers": []
```

Do not return `null`.

Week 2 sessions rule:

If sessions are not implemented yet, return:

```json
"sessions": []
```

Do not return `null`.

---

# 13. Public Detail ID vs Slug Decision

For Week 2 implementation, use:

```http
GET /api/v1/events/public/{event_id}
```

Reason:

* Week 2 execution plan explicitly uses ID.
* Admin diagnostics can reuse created event ID.
* Flutter can navigate using event_id.

Forward compatibility:

* Keep `slug` in all event responses.
* Website integration may later introduce:

```http
GET /api/v1/events/public/slug/{slug}
```

Do not remove `slug`.

---

# 14. Demo Data Requirements

Create and verify two published events.

---

## 14.1 Breakfast Club

```json
{
  "title": "Breakfast Club",
  "description": "Monthly NITKSAA alumni breakfast meetup in Bangalore.",
  "start_datetime": "2026-06-12T09:00:00+05:30",
  "end_datetime": "2026-06-12T11:00:00+05:30",
  "timezone": "Asia/Kolkata",
  "location_text": "Bangalore",
  "is_virtual": false,
  "virtual_url": null,
  "capacity": 30,
  "registration_closes_at": "2026-06-11T23:59:00+05:30",
  "status": "published"
}
```

Expected public display:

```text
Venue: Bangalore
Capacity: 30
Type: In-person
Register CTA visible
```

---

## 14.2 Webinar

```json
{
  "title": "Webinar",
  "description": "NITKSAA online alumni webinar.",
  "start_datetime": "2026-06-13T18:00:00+05:30",
  "end_datetime": "2026-06-13T19:00:00+05:30",
  "timezone": "Asia/Kolkata",
  "location_text": null,
  "is_virtual": true,
  "virtual_url": "https://meet.example.com/nitksaa-webinar",
  "capacity": 100,
  "registration_closes_at": "2026-06-13T17:00:00+05:30",
  "status": "published"
}
```

Expected public display:

```text
Online
Timezone: Asia/Kolkata
Capacity: 100
Register CTA visible
Join URL hidden
```

---

# 15. Audit Logging Requirements

The following actions must create records in `event_audit_log`:

```text
Event Created
Event Updated
Event Published
Event Unpublished
Event Cancelled
Event Deleted
```

Recommended audit mapping:

| Action          | event_type        | entity_type |
| --------------- | ----------------- | ----------- |
| Create Event    | event_created     | event       |
| Update Event    | event_updated     | event       |
| Publish Event   | event_published   | event       |
| Unpublish Event | event_unpublished | event       |
| Cancel Event    | event_cancelled   | event       |
| Delete Event    | event_deleted     | event       |

Minimum fields:

```text
actor_uid
event_type
entity_type
entity_id
created_at
```

Use existing `event_audit_log` table from migration 006.

---

# 16. Developer Diagnostics Contract

Developer Diagnostics must have a category:

```text
Event Management
```

Each diagnostic must display:

```text
Feature Name
Backend API
HTTP Method
Authentication Required
Request Payload
Response Payload
Result
Duration
Timestamp
```

Standard diagnostic result:

```json
{
  "feature": "Event Create Test",
  "api": "/api/v1/events",
  "method": "POST",
  "auth_required": true,
  "request": {},
  "response": {},
  "status": "PASS",
  "duration_ms": 123,
  "timestamp": "2026-06-09T10:00:00Z"
}
```

---

## 16.1 Events List Test

API:

```http
GET /api/v1/events
```

Auth required:

```text
Yes
```

Expected:

```text
Admin events list returned
```

---

## 16.2 Event Detail Test

API:

```http
GET /api/v1/events/{event_id}
```

Auth required:

```text
Yes
```

Expected:

```text
Event detail returned
```

---

## 16.3 Event Create Test

API:

```http
POST /api/v1/events
```

Auth required:

```text
Yes
```

Expected:

```text
Temporary diagnostic event created
```

---

## 16.4 Event Update Test

API:

```http
PATCH /api/v1/events/{event_id}
```

Auth required:

```text
Yes
```

Expected:

```text
Temporary diagnostic event updated
```

---

## 16.5 Event Publish Test

API:

```http
PATCH /api/v1/events/{event_id}/status
```

Auth required:

```text
Yes
```

Expected:

```text
Draft event becomes published
Published event becomes draft
```

---

## 16.6 Event Delete Test

API:

```http
DELETE /api/v1/events/{event_id}
```

Auth required:

```text
Yes
```

Expected:

```text
Temporary diagnostic event deleted or cancelled
```

---

## 16.7 Public Events Test

API:

```http
GET /api/v1/events/public
```

Auth required:

```text
No
```

Expected:

```text
Only published events returned
virtual_url not present in response
```

---

## 16.8 Public Event Detail Test

API:

```http
GET /api/v1/events/public/{event_id}
```

Auth required:

```text
No
```

Expected:

```text
Published event detail returned
virtual_url not present in response
```

---

# 17. Admin Portal Contract

Admin Portal must use only these APIs:

```http
GET    /api/v1/events
POST   /api/v1/events
GET    /api/v1/events/{event_id}
PATCH  /api/v1/events/{event_id}
PATCH  /api/v1/events/{event_id}/status
DELETE /api/v1/events/{event_id}
```

Admin Event List columns:

```text
Title
Status
Event Type
Capacity
Start Date
Actions
```

Admin Event Create fields:

```text
Title
Description
Start Date
End Date
Timezone
Event Type
Venue
Join URL
Capacity
Registration Deadline
```

Conditional UI:

If physical:

```text
Show Venue
Hide Join URL
```

If virtual:

```text
Show Join URL
Venue optional/hidden
```

---

# 18. Flutter Contract

Flutter public app must use only these APIs:

```http
GET /api/v1/events/public?period=upcoming
GET /api/v1/events/public?period=past
GET /api/v1/events/public/{event_id}
```

Flutter listing tabs:

```text
Upcoming
Past
```

Event card fields:

```text
Title
Date
Event Type Badge
Capacity Indicator
```

Event detail fields:

```text
Title
Description
Date
Time
Timezone
Venue or Online Indicator
Speaker List
Register CTA
```

Rules:

* Join URL must remain hidden.
* Registration is not implemented in Week 2.
* Register CTA should redirect unauthenticated users to Login.
* If user is already authenticated, CTA may show placeholder message: `Registration coming soon`.

---

# 19. Verification Requirements

Before Week 2 is accepted, run:

```bash
flutter analyze
flutter test
npm run build
npm run lint
python -m compileall app
```

Also verify:

```text
All Event Management diagnostics PASS
Admin can create event
Admin can publish event
Admin can unpublish event
Admin can view events
Flutter can show public upcoming events
Flutter can show public past events
Flutter can show event detail
Public APIs do not expose virtual_url
Demo data works
```

---

# 20. Required Reports

Create these files:

```text
docs/reviews/week2_backend_api_report.txt
docs/reviews/week2_diagnostics_report.txt
docs/reviews/week2_admin_portal_report.txt
docs/reviews/week2_flutter_report.txt
docs/reviews/week2_end_to_end_verification_report.txt
```

---

# 21. Week 2 Completion Criteria

Week 2 is complete only when:

* All Event Management diagnostics PASS.
* Event CRUD APIs PASS.
* Public APIs PASS.
* Admin Portal event management PASS.
* Flutter event listing PASS.
* Flutter event detail PASS.
* Public APIs do not expose `virtual_url`.
* Documentation is updated.
* Breakfast Club demo succeeds.
* Webinar demo succeeds.
* Reports are created.
* No registration functionality is added.
* No attendee management functionality is added.
* No email functionality is added.

---

# 22. Implementation Sequence

Mandatory order:

1. Backend Schemas
2. Backend Repositories
3. Backend Services
4. Admin Event APIs
5. Public Event APIs
6. Audit Logging
7. Developer Diagnostics
8. Admin Portal Event List
9. Admin Portal Event Create/Edit
10. Admin Portal Publish/Unpublish
11. Flutter Public Event Listing
12. Flutter Public Event Detail
13. Demo Data
14. Verification Reports

Do not start UI implementation before backend APIs and Event Management diagnostics pass.
