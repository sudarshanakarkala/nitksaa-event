# NITKSAA Event App — Week 2 Execution Plan

Version: 1.0
Sprint: Week 2 (Jun 7 – Jun 13)
Status: Approved Planning Document

---

# Week 2 Goal

Staff can create events.
Public can browse events.
Public can view event details.
No registration functionality in Week 2.
No attendee management in Week 2.
No email functionality in Week 2.

---

# Week 2 Success Criteria

Admin Portal:

* Staff logs in
* Creates event
* Publishes event

Backend:

* Event APIs functional
* Event status management functional
* Public APIs functional

Flutter:

* Public event listing visible
* Event detail visible

Developer Diagnostics:

* Every Event API verified
* All diagnostics pass

---

# Architecture Principles

1. API First
2. Backend before Frontend
3. Developer Diagnostics before UI verification
4. Admin Portal and Flutter communicate only via APIs
5. No direct database access from UI
6. Reuse existing authentication architecture
7. Follow Architecture Review v1.0

---

# Week 2 Features

## Backend Features

### Event CRUD

POST /api/v1/events

GET /api/v1/events

GET /api/v1/events/{id}

PATCH /api/v1/events/{id}

DELETE /api/v1/events/{id}

PATCH /api/v1/events/{id}/status

### Public Event APIs

GET /api/v1/events/public

GET /api/v1/events/public/{id}

Rules:

* No authentication required
* Only published events returned
* join_url must never be returned

---

## Flutter Features

### Event Listing

Public access

Tabs:

* Upcoming
* Past

Event Card:

* Title
* Date
* Event Type
* Capacity Indicator

### Event Detail

Show:

* Title
* Description
* Date
* Time
* Timezone
* Location
* Online Indicator
* Speakers
* Register CTA

Join URL hidden.

---

## Admin Portal Features

### Event List

Columns:

* Title
* Status
* Event Type
* Capacity
* Start Date
* Actions

### Event Create

Fields:

* Title
* Description
* Start Date
* End Date
* Timezone
* Event Type
* Venue
* Join URL
* Capacity
* Registration Deadline

### Publish

Publish

Unpublish

Draft

Status Badge

---

# Event Model

Minimum Week 2 Fields

event_id

title

description

start_datetime

end_datetime

timezone

location_text

is_virtual

join_url

capacity

registration_deadline

status

created_by

updated_by

created_at

updated_at

---

# Developer Diagnostics

Developer Diagnostics becomes the official verification tool.

UI completion is not accepted until diagnostics pass.

---

# Category

Event Management

---

## Diagnostic 1

Events List Test

Purpose:

Verify:

GET /api/v1/events

Checks:

* API reachable
* Authentication works
* Response valid
* Event count returned

Display:

Backend API

Method

Request

Response

Result

---

## Diagnostic 2

Event Detail Test

Purpose:

Verify:

GET /api/v1/events/{id}

Checks:

* Event exists
* Event returned
* Fields validated

Display:

Event ID

Response

Result

---

## Diagnostic 3

Event Create Test

Purpose:

Verify:

POST /api/v1/events

Creates temporary test event.

Checks:

* Event created
* ID generated
* Response valid

Display:

Payload

Response

Result

---

## Diagnostic 4

Event Update Test

Purpose:

Verify:

PATCH /api/v1/events/{id}

Checks:

* Update succeeds
* Data persists

Display:

Request

Response

Result

---

## Diagnostic 5

Event Publish Test

Purpose:

Verify:

PATCH /api/v1/events/{id}/status

Checks:

* Draft → Published
* Published → Draft

Display:

Old Status

New Status

Result

---

## Diagnostic 6

Event Delete Test

Purpose:

Verify:

DELETE /api/v1/events/{id}

Checks:

* Event removed
* Event not returned afterwards

Display:

Result

---

## Diagnostic 7

Public Events Test

Purpose:

Verify:

GET /api/v1/events/public

Checks:

* Published events only
* No join_url returned

Display:

Response

Result

---

## Diagnostic 8

Public Event Detail Test

Purpose:

Verify:

GET /api/v1/events/public/{id}

Checks:

* Event visible
* join_url hidden

Display:

Response

Result

---

# Admin Portal Verification

Event Create

PASS

Event Edit

PASS

Event Publish

PASS

Event List

PASS

Status Badges

PASS

---

# Flutter Verification

Upcoming Tab

PASS

Past Tab

PASS

Event Card

PASS

Event Detail

PASS

Venue Display

PASS

Online Display

PASS

Register CTA

PASS

Join URL Hidden

PASS

---

# Demo Data

## Physical Event

Breakfast Club

Location:

Bangalore

Capacity:

30

Status:

Published

---

## Virtual Event

Webinar

Timezone:

Asia/Kolkata

Capacity:

100

Status:

Published

Join URL stored internally

Not visible publicly

---

# Week 2 Demo

Scenario 1

Admin creates Breakfast Club.

Publishes event.

Flutter shows:

* Venue
* Capacity
* Register CTA

---

Scenario 2

Admin creates Webinar.

Publishes event.

Flutter shows:

* Online
* Timezone
* Register CTA

Flutter must not show join URL.

---

# Not In Scope

Registration

Email

Attendees

CSV Export

QR

Check-In

Payments

Notifications

Waitlist

Analytics

---

# Deliverables

Backend

* Event CRUD
* Event Publish
* Public APIs

Developer Diagnostics

* Event Diagnostics Functional

Admin Portal

* Event List
* Event Create
* Event Publish

Flutter

* Event List
* Event Detail

Documentation

* API Documentation Updated

---

# Week 2 Completion Criteria

All Event Management Diagnostics PASS.

Admin can create and publish events.

Flutter can display published events.

Week 2 Demo succeeds.

Only then Week 2 is complete.
