# Final Updates for docs/api/events_api_contract.md

## Version

Document: events_api_contract.md

Version: 1.0

Status: Approved for Week 2 Implementation

---

# API Versioning Policy

Current Version:

/api/v1

Rules:

* Do not introduce breaking changes within v1.
* New optional fields may be added.
* Existing field names must remain stable.
* Existing response structures must remain stable.
* Breaking changes require a new API version.
* Flutter App, Website, and Admin Portal must use the same contract.

---

# Audit Logging Requirements

The following actions must create records in event_audit_log:

* Event Created
* Event Updated
* Event Published
* Event Unpublished
* Event Cancelled
* Event Deleted

Recommended Fields:

event_id

firebase_uid

action

old_value

new_value

timestamp

Purpose:

* Operational audit
* Security review
* Future compliance reporting

Migration 006 already provides audit infrastructure.

---

# Developer Diagnostics Standard Result

All diagnostics should return/display a consistent result format.

Example:

{
"feature": "Event Create Test",
"api": "/api/v1/events",
"method": "POST",
"auth_required": true,
"status": "PASS",
"duration_ms": 123,
"timestamp": "2026-06-09T10:00:00Z"
}

Display:

* Feature Name
* API Endpoint
* HTTP Method
* Authentication Requirement
* Request Payload
* Response Payload
* Result
* Execution Time
* Last Run Time

---

# Admin Permission Matrix

Week 2 Permissions

| Operation            | Admin             |
| -------------------- | ----------------- |
| View Events          | Yes               |
| Create Event         | Yes               |
| Update Event         | Yes               |
| Publish Event        | Yes               |
| Unpublish Event      | Yes               |
| Cancel Event         | Yes               |
| Delete Event         | Yes               |
| Public Event Listing | No Authentication |
| Public Event Detail  | No Authentication |

Week 2 recommendation:

Use existing:

website_users.is_admin = true

No new role hierarchy required.

---

# Public API Security Rules

Public APIs must never expose:

* join_url
* virtual_url
* created_by_firebase_uid
* updated_by_firebase_uid
* audit information
* internal notes
* unpublished events
* draft events

Public APIs may expose:

* event_id
* slug
* title
* description
* date/time
* venue
* capacity
* registration status

---

# Week 3 Forward Compatibility

Week 3 introduces:

POST /api/v1/events/{id}/register

GET /api/v1/events/{id}/my-registration

Registration records

Confirmation emails

Join URL visibility

Therefore the following fields must remain stable:

event_id

slug

capacity

registration_status

registered_count

is_virtual

location_text

timezone

No breaking changes allowed.

---

# Event Ownership

For Week 2 APIs:

Store:

created_by_firebase_uid

Optionally expose to Admin APIs:

created_by_name

Example:

{
"created_by_firebase_uid": "firebase_uid",
"created_by_name": "NITKSAA Admin"
}

Do not expose ownership information in public APIs.

---

# Week 2 Implementation Sequence

Mandatory sequence:

1. Backend Schemas
2. Backend Services
3. Backend Repositories
4. Event APIs
5. API Documentation
6. Developer Diagnostics
7. Admin Portal
8. Flutter Event Listing
9. Flutter Event Detail
10. End-to-End Verification

No UI implementation should be considered complete until the corresponding Developer Diagnostics test passes.

---

# Week 2 Completion Criteria

Week 2 is complete only when:

* All Event Management diagnostics PASS
* Event CRUD APIs PASS
* Public APIs PASS
* Admin Portal event management PASS
* Flutter event listing PASS
* Flutter event detail PASS
* Public APIs do not expose join_url
* Documentation updated
* Demo scenarios succeed

Status:

APPROVED FOR WEEK 2 IMPLEMENTATION
Version: 1.0
