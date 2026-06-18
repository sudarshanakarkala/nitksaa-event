# NITKSAA Event App

# Week 2 Development Plan

## Sprint: Jun 7 – Jun 13

## Status: Approved for Development

---

# Sprint Goal

Staff can create events.

Public can browse published events.

Public can view published event details.

No registration functionality in Week 2.

No attendee management in Week 2.

No email functionality in Week 2.

---

# Success Criteria

## Admin Portal

Staff can:

* Login
* Create Event
* Edit Event
* Publish Event
* Unpublish Event
* Cancel Event
* View Event List

---

## Backend

Event APIs functional.

Public APIs functional.

Status management functional.

Audit logging functional.

---

## Flutter

Public event listing visible.

Public event detail visible.

Upcoming and Past tabs functional.

Join URL hidden.

---

## Developer Diagnostics

All Event Management diagnostics pass.

Diagnostics become the official verification mechanism before UI acceptance.

---

# Architecture Principles

1. API First
2. Backend Before Frontend
3. Developer Diagnostics Before UI Verification
4. Flutter and Admin communicate only through APIs
5. No direct database access from UI
6. Reuse existing authentication architecture
7. Existing authentication flow must not change
8. Backend enforces authorization
9. Public APIs never expose protected links
10. Follow Architecture Review v1.0

---

# Week 2 Scope

## Included

### Event Creation

Staff creates events.

### Event Editing

Staff updates events.

### Event Publishing

Staff publishes events.

### Event Cancellation

Staff cancels events.

### Public Event Listing

Public users browse events.

### Public Event Detail

Public users view event details.

### Event Diagnostics

All APIs verified through diagnostics.

---

## Not Included

Registration

Attendee Management

Email

CSV Export

QR Check-In

Payments

Waitlist

Notifications

Analytics

Sessions Management

Speaker Management

Sponsor Management

---

# Event Status Model

Week 2 approved statuses:

```text
draft
published
registration_open
cancelled
archived
```

Week 2 usage:

```text
draft
published
cancelled
```

registration_open reserved for Week 3.

archived reserved for future.

---

# Backend API Contract

Base Path:

```text
/api/v1
```

---

## Admin APIs

### Create Event

```http
POST /api/v1/events
```

### List Events

```http
GET /api/v1/events
```

### Event Detail

```http
GET /api/v1/events/{event_id}
```

### Update Event

```http
PATCH /api/v1/events/{event_id}
```

### Change Status

```http
PATCH /api/v1/events/{event_id}/status
```

---

## Public APIs

### Public Event Listing

```http
GET /api/v1/events/public
```

### Public Event Detail

```http
GET /api/v1/events/public/{event_id}
```

---

## Removed API

Do NOT implement:

```http
DELETE /api/v1/events/{event_id}
```

Events are never hard deleted.

Use:

```json
{
  "status": "cancelled"
}
```

instead.

---

# Event Model

## Core Fields

```text
event_id
slug
title
tagline
description

status

start_datetime
end_datetime
timezone

location_text
location_maps_url

is_virtual
virtual_url

thumbnail_url
banner_url

capacity

registration_opens_at
registration_closes_at

created_by_firebase_uid
created_at
updated_at

published_at

cancelled_at
cancelled_reason
```

---

## Validation Rules

### Date Validation

```text
end_datetime > start_datetime
```

---

### Capacity Validation

```text
capacity = null
or
capacity > 0
```

---

### Physical Event

Required:

```text
location_text
```

Must not contain:

```text
virtual_url
```

---

### Virtual Event

Required:

```text
virtual_url
```

location_text optional.

---

### Default Status

All newly created events:

```text
draft
```

Status must not be passed during create.

---

# Public API Rules

Public APIs:

```text
No authentication required
```

Must return:

```text
Published events only
```

Must never return:

```text
virtual_url
created_by_firebase_uid
audit information
internal notes
```

---

# Backend Development Order

## Phase 1

Schemas

Files:

```text
schemas/event_create.py
schemas/event_update.py
schemas/event_status.py
schemas/event_response.py
```

---

## Phase 2

Repositories

Files:

```text
repositories/events_repository.py
```

---

## Phase 3

Services

Files:

```text
services/events_service.py
services/slug_service.py
```

---

## Phase 4

Audit Logging

Write audit records for:

```text
event_created
event_updated
event_published
event_unpublished
event_cancelled
```

---

## Phase 5

Admin APIs

Implement:

```text
POST
GET
PATCH
PATCH status
```

---

## Phase 6

Public APIs

Implement:

```text
GET public list
GET public detail
```

---

# Developer Diagnostics

Diagnostics must be completed before UI verification.

Diagnostics must be disabled when:

```text
ENV=production
```

---

## Category

Event Management

---

## Diagnostic 1

Events List Test

API:

```http
GET /api/v1/events
```

---

## Diagnostic 2

Event Detail Test

API:

```http
GET /api/v1/events/{event_id}
```

---

## Diagnostic 3

Event Create Test

API:

```http
POST /api/v1/events
```

---

## Diagnostic 4

Event Update Test

API:

```http
PATCH /api/v1/events/{event_id}
```

---

## Diagnostic 5

Event Publish Test

API:

```http
PATCH /api/v1/events/{event_id}/status
```

Checks:

```text
draft -> published
published -> draft
```

---

## Diagnostic 6

Event Cancel Test

API:

```http
PATCH /api/v1/events/{event_id}/status
```

Checks:

```text
published -> cancelled
```

---

## Diagnostic 7

Public Events Test

API:

```http
GET /api/v1/events/public
```

Checks:

```text
Published events only
virtual_url hidden
```

---

## Diagnostic 8

Public Event Detail Test

API:

```http
GET /api/v1/events/public/{event_id}
```

Checks:

```text
Event visible
virtual_url hidden
```

---

# Admin Portal

Location:

```text
admin/event_admin/
```

---

## Event List

Columns:

```text
Title
Status
Event Type
Capacity
Start Date
Actions
```

---

## Event Create

Fields:

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

---

## Conditional Fields

Physical:

```text
Show Venue
Hide Join URL
```

Virtual:

```text
Show Join URL
Hide Venue
```

---

## Status Actions

```text
Publish
Unpublish
Cancel
```

---

# Flutter

Location:

```text
apps/event_app/
```

---

## Public Event Listing

No login required.

Tabs:

```text
Upcoming
Past
```

Event Card:

```text
Title
Date
Type Badge
Capacity Indicator
```

---

## Event Detail

Display:

```text
Title
Description
Date
Time
Timezone
Venue
Online Indicator
Speaker List
Register CTA
```

---

## Register CTA

Unauthenticated:

```text
Navigate to Login
```

Authenticated:

```text
Registration Coming Soon
```

---

## Join URL

Must remain hidden.

---

# Demo Data

## Event 1

Breakfast Club

```text
Type: Physical
Location: Bangalore
Capacity: 30
Status: Published
```

Expected Flutter:

```text
Venue Visible
Register CTA Visible
```

---

## Event 2

Webinar

```text
Type: Virtual
Timezone: Asia/Kolkata
Capacity: 100
Status: Published
```

Expected Flutter:

```text
Online Indicator Visible
Timezone Visible
Register CTA Visible
Join URL Hidden
```

---

# Verification

Backend:

```bash
python -m compileall app
```

Flutter:

```bash
flutter analyze
flutter test
```

Admin:

```bash
npm run build
npm run lint
```

---

# Reports

Create:

```text
docs/reviews/week2_backend_api_report.txt

docs/reviews/week2_diagnostics_report.txt

docs/reviews/week2_admin_portal_report.txt

docs/reviews/week2_flutter_report.txt

docs/reviews/week2_end_to_end_verification_report.txt
```

---

# Week 2 Completion Criteria

Backend APIs complete.

Diagnostics pass.

Admin Portal complete.

Flutter public event listing complete.

Flutter event detail complete.

Public APIs verified.

virtual_url hidden.

Breakfast Club demo successful.

Webinar demo successful.

Documentation updated.

No registration functionality added.

No attendee functionality added.

No email functionality added.

---

For Week 2, I recommend 8 phases. This keeps the work reviewable and reduces rework.

# Phase 0 — Documentation Freeze

Goal: Finalize requirements before coding.

Deliverables
Final events_api_contract.md
Final Week 2 Execution Plan
Product Owner observations merged
Architecture review updates merged
Exit Criteria
No open questions
API contract approved
Development can start

# Phase 1 — Backend API Foundation

Goal: Create Event domain backend.

Deliverables
Schemas
Repository
Service Layer
Slug generation
Audit logging
Event APIs
APIs
POST  /api/v1/events
GET   /api/v1/events
GET   /api/v1/events/{event_id}
PATCH /api/v1/events/{event_id}
PATCH /api/v1/events/{event_id}/status
GET   /api/v1/events/public
GET   /api/v1/events/public/{event_id}
Exit Criteria
Backend compiles
Unit verification complete
API contract implemented

# Phase 2 — Developer Diagnostics

Goal: Verify APIs before UI.

Deliverables
Events List Test
Event Detail Test
Event Create Test
Event Update Test
Event Publish Test
Event Cancel Test
Public Events Test
Public Event Detail Test
Exit Criteria
All diagnostics PASS

# Phase 3 — Admin Portal Event List

Goal: Replace placeholder Event page.

Deliverables
Event List
Status badges
Filters
Actions column
Exit Criteria
Admin can view events

# Phase 4 — Admin Portal Event Create/Edit

Goal: Staff can create and update events.

Deliverables
Create Event Screen
Edit Event Screen
Validation
Physical / Virtual toggle
Exit Criteria
Event creation successful
Event editing successful

# Phase 5 — Admin Portal Publish/Cancel

Goal: Event lifecycle management.

Deliverables
Publish
Unpublish
Cancel
Exit Criteria
Status transitions verified

# Phase 6 — Flutter Public Event Listing

Goal: Public browsing.

Deliverables
Upcoming Tab
Past Tab
Event Cards
Capacity Indicator
Exit Criteria
Published events visible

# Phase 7 — Flutter Event Detail

Goal: Public event detail.

Deliverables
Title
Description
Date
Timezone
Venue
Online Indicator
Register CTA
Exit Criteria
Detail page verified
Join URL hidden

# Phase 8 — End-to-End Verification & Reports

Goal: Sprint closure.

Demo Data
Breakfast Club
Webinar
Verification
python -m compileall app
flutter analyze
flutter test
npm run build
npm run lint
Reports
week2_backend_api_report.txt
week2_diagnostics_report.txt
week2_admin_portal_report.txt
week2_flutter_report.txt
week2_end_to_end_verification_report.txt
Exit Criteria
Breakfast Club demo PASS
Webinar demo PASS
All diagnostics PASS
All reports generated
Sprint accepted
Recommended Workflow
Phase 0 -> Review with ChatGPT
Phase 1 -> Claude Code Implementation
Review with ChatGPT

Phase 2 -> Claude Code Implementation
Review with ChatGPT

Phase 3 -> Claude Code Implementation
Review with ChatGPT

Phase 4 -> Claude Code Implementation
Review with ChatGPT

Phase 5 -> Claude Code Implementation
Review with ChatGPT

Phase 6 -> Claude Code Implementation
Review with ChatGPT

Phase 7 -> Claude Code Implementation
Review with ChatGPT

Phase 8 -> Claude Code Implementation
Final Review with ChatGPT

This gives you 8 development phases + 1 documentation freeze phase, which is a manageable structure for Week 2 and aligns with the architecture and Product Owner feedback.

_____

# Implementation Sequence

1. Update Documentation
2. Backend Schemas
3. Backend Repository
4. Backend Services
5. Audit Logging
6. Admin APIs
7. Public APIs
8. Developer Diagnostics
9. Admin Portal Event Screens
10. Flutter Event Screens
11. Demo Data
12. Verification
13. Reports
14. Sprint Review

END OF WEEK 2 DEVELOPMENT PLAN
