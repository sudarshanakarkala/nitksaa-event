# NITKSAA Event App — Week 3 Architecture Review v2.0

**Version:** 2.0  
**Status:** Revised for approval before coding  
**Sprint:** Week 3 — Registration, Confirmation, Alumni Autofill, Protected Join Link  
**Prepared Date:** 2026-06-18  
**Based On:** Week 2 complete tag `week2-complete`, Week 2 API/admin/flutter reports, architecture review observations, Jun 30 beta plan, and the three Week 3 v1 draft documents.

---

## 1. Executive Summary

Week 3 must move the Event App from public event browsing to authenticated alumni registration.

The previous Week 3 v1 documents were scoped as **registration only** and explicitly excluded confirmation email and join-link reveal. That must be changed. The current approved Week 3 goal is:

```text
Alumni can register.
Confirmation email is sent.
Join link is visible after registration for virtual events.
Registration UI flows are demonstrated inside Developer Diagnostics.
No direct production Flutter UI implementation is required this week.
React Admin new registration screens are deferred to Week 4.
```

Week 3 is therefore backend-first, API-contract-first, and diagnostics-UI-first.

---

## 2. Week 2 Baseline

Week 2 is complete and tagged:

```text
week2-complete
```

Week 2 delivered:

- Event CRUD APIs
- Event publish / unpublish / cancel
- Public event list/detail
- Admin Event Management
- Flutter public event list/detail
- Login UX improvements
- Developer Diagnostics access control
- Public event card metadata
- `show_attendee_list`
- Firebase login verification
- Runtime CORS verification
- End-to-end verification

Week 2 also confirmed:

- No registration functionality was added.
- No email functionality was added.
- No attendee management functionality was added.
- `virtual_url` is stored internally but not exposed publicly.
- Public APIs return published events only.

---

## 3. Changes Needed from Week 3 v1 Drafts

The three attached Week 3 v1 documents need these corrections.

### 3.1 Architecture Review Changes

Change sprint from:

```text
Registration Only
```

to:

```text
Registration + Confirmation Email + Protected Join Link + Diagnostics UI Flows
```

Move these items from out of scope to in scope:

- Confirmation email
- Protected virtual join-link reveal after successful registration
- Alumni profile autofill from `alumni_db`
- Developer Diagnostics registration UI flows

Remove these Week 3 v1 items from active implementation:

- Direct Flutter production screen implementation
- React Admin registration page/list/export implementation, unless needed only as diagnostic/API verification

Keep these still out of scope:

- Attendance
- QR check-in
- Waitlist
- Payment
- Check-in status
- Complex admin attendee management
- Public attendee list, unless explicitly required later

### 3.2 Execution Plan Changes

Replace direct Flutter implementation phase with:

```text
Developer Diagnostics UI Flow Implementation
```

This means the backend should expose complete APIs and the Flutter Developer Diagnostics screen should demonstrate all required frontend states so the frontend developer can later implement proper themed production UI.

Diagnostics should show:

- Alumni autofill preview
- Registration eligibility
- Register action
- Duplicate registration state
- Event full state
- Registration closed state
- Confirmation success state
- Confirmation email send result
- My registration response
- Protected join-link reveal for registered virtual event
- Venue/map link state for physical event

### 3.3 API Contract Changes

Add or update:

```http
GET  /api/v1/alumni/me
POST /api/v1/events/{event_id}/register
GET  /api/v1/events/{event_id}/my-registration
GET  /api/v1/my/registrations
```

Optional but useful for diagnostics:

```http
GET  /api/v1/events/{event_id}/registration-eligibility
POST /api/v1/dev/diagnostics/registrations/run
```

Do **not** expose `virtual_url` in public APIs. Return it only from an authenticated user-specific endpoint after that user is registered.

---

## 4. Scope Decision for Week 3 v2

### 4.1 In Scope

#### Backend

- Alumni-only registration
- Alumni profile autofill from `alumni_db`
- Active alumni validation
- Event capacity validation
- Registration deadline validation
- Duplicate active registration prevention
- Dynamic `registered_count`
- Registration confirmation number
- Confirmation email service
- Local email stub/log mode
- Staging email provider mode
- Protected virtual join-link reveal after registration
- My Registration endpoint
- My Registrations endpoint
- Developer Diagnostics registration test endpoint(s)
- Audit logging for registration and email send attempts

#### Flutter

No production Flutter registration screens this week.

Instead, Developer Diagnostics should include registration UI flow previews and API test panels for frontend developers.

#### React Admin

No new production admin registration screens this week.

Admin portal Week 4 will implement attendee list and export. Week 3 may expose backend/admin APIs only if needed for diagnostics or count verification.

### 4.2 Out of Scope

- Attendance
- QR check-in
- Offline check-in
- Waitlist
- Payment
- Refunds
- Coupons
- Public attendee list
- Complex attendee type configuration
- Guest/family registration
- Admin production attendee page
- Admin production CSV export page
- Certificate/reminder/notification features beyond registration confirmation email

---

## 5. System Architecture

```text
                ┌────────────────────┐
                │  Firebase Auth      │
                └─────────┬──────────┘
                          │ Firebase ID token
                          ▼
                ┌────────────────────┐
                │ POST /auth/firebase │
                └─────────┬──────────┘
                          │ backend JWT
                          ▼
┌────────────────────┐    ┌────────────────────────────┐
│ Flutter Diagnostics │───▶│ FastAPI Event Backend       │
│ Registration Flows  │    │ /api/v1                     │
└────────────────────┘    └─────────────┬──────────────┘
                                         │
                         ┌───────────────┼────────────────┐
                         ▼               ▼                ▼
                  ┌────────────┐  ┌────────────┐  ┌──────────────┐
                  │ events_db   │  │ alumni_db  │  │ Email Provider│
                  │ events      │  │ alumni     │  │ SendGrid/etc. │
                  │ users       │  │ profiles   │  │ or local stub │
                  │ registrations│ └────────────┘  └──────────────┘
                  └────────────┘
```

---

## 6. Database Ownership

| Database | Purpose | Week 3 Usage |
|---|---|---|
| `events_db` | Event business data | events, event_users, registrations, audit log |
| `alumni_db` | Alumni source of truth | name, batch year, branch, active status, phone/email if available |
| `website_db` | Website/community data | Not required for Week 3 unless existing profile lookup logic depends on it |

Rules:

- Do not directly access DB from Flutter or React.
- Backend owns all DB access.
- Do not create cross-database foreign keys.
- Use `ref_id` as a value reference to alumni records.
- Duplicate only a minimal registration-time snapshot for audit/export/email stability.

---

## 7. Do We Need Details from `nitksaa-portal-v2` or `nitksaa-website`?

### 7.1 Required from `nitksaa-portal-v2`

Yes, we likely need **limited backend reference details** from `nitksaa-portal-v2`, because alumni data already exists in `alumni_db` and Week 3 requires active alumni validation and autofill.

Required details:

1. Alumni table name and exact columns:
   - alumni id / ref id
   - full name
   - email
   - phone
   - batch/graduation year
   - branch/department
   - active/member status
   - suspension/deactivation status, if any

2. Existing `fetch_alumni_info()` pattern:
   - function name
   - DB connection method
   - query style
   - error mapping
   - active alumni checks

3. Identity mapping:
   - how Firebase UID maps to alumni record
   - whether mapping uses email, `ref_id`, or another join table
   - whether duplicate email cases exist

4. Environment/config:
   - alumni DB connection string
   - local/staging Cloud SQL setup
   - secrets naming convention

5. Data privacy convention:
   - which fields can be exposed to frontend
   - which fields can be included in email
   - which fields can be stored as registration snapshot

### 7.2 Required from `nitksaa-website`

Not required for Week 3 core registration unless one of these is true:

- Website already has public event route/slug conventions that must be reused.
- Website already has email templates or branding assets.
- Website will consume the same public event APIs immediately.
- Website has an existing “Add to Calendar” or event detail URL pattern.

Recommended approach:

```text
Use nitksaa-portal-v2 for alumni/profile/auth data pattern.
Use nitksaa-website only for branding/public URL/email template consistency if available.
Do not block Week 3 backend on website code.
```

---

## 8. Identity and Authorization

### 8.1 Current Auth Flow

```text
Firebase Sign-In
→ POST /api/v1/auth/firebase
→ Backend verifies Firebase ID token
→ Backend upserts/reads event_users
→ Backend returns backend JWT
→ Protected APIs use Authorization: Bearer <backend_jwt>
```

### 8.2 Registration User Rule

Week 3 registration requires:

```text
current_user.user_type == alumni
current_user.ref_id is not null
current_user is not suspended
alumni_db record is active
```

If any check fails, registration must be rejected.

Recommended error:

```http
403 alumni_required
```

or:

```http
403 alumni_not_active
```

### 8.3 Admin Rule

React Admin production screens are deferred, but any admin registration endpoints or diagnostics that expose PII must require:

```text
current_user.is_admin == true
```

---

## 9. Registration Domain Model

Recommended response object:

```json
{
  "registration_id": 101,
  "registration_number": "NITKSAA-2026-000101",
  "event_id": 1,
  "firebase_uid": "firebase-user-id",
  "ref_id": "ALUMNI123",
  "fullname": "NITKSAA Member",
  "email": "member@example.com",
  "phone": "+91...",
  "batch_year": 2010,
  "branch": "Information Technology",
  "status": "registered",
  "registered_at": "2026-06-18T10:00:00+05:30",
  "cancelled_at": null,
  "confirmation_email_status": "sent"
}
```

Recommended stored snapshot fields:

- `ref_id`
- `firebase_uid`
- `fullname_snapshot`
- `email_snapshot`
- `phone_snapshot`
- `batch_year_snapshot`
- `branch_snapshot`
- `registration_number`
- `status`
- `registered_at`
- `cancelled_at`
- `confirmation_email_status`
- `confirmation_email_sent_at`
- `confirmation_email_error`

If current migration does not have these columns, add a Week 3 migration or use existing flexible metadata column if available.

---

## 10. Event and Registration Status

### 10.1 Event Status

Keep existing Week 2 event status values:

```text
draft
published
cancelled
completed
```

Do not add `registration_open` as a separate event status in Week 3.

### 10.2 Computed Registration Status

Use existing Week 2 computed field:

```text
open
closed
full
not_open_yet
not_applicable
```

This handles the operational difference:

```text
published but not yet registerable
```

using:

```text
registration_opens_at
registration_closes_at
capacity
registered_count
```

---

## 11. Capacity and Deadline Rules

Registration is allowed only when:

```text
event.status == published
current_user is active alumni
registration_status == open
capacity is null OR active_registered_count < capacity
current time >= registration_opens_at, if set
current time <= registration_closes_at, if set
user has no active registered row for event
```

When blocked:

| Condition | HTTP | Code |
|---|---:|---|
| Not logged in | 401 | unauthorized |
| Non-alumni user | 403 | alumni_required |
| Alumni inactive | 403 | alumni_not_active |
| Event missing | 404 | event_not_found |
| Event not published | 409 | event_not_published |
| Registration not open yet | 409 | registration_not_open_yet |
| Registration closed | 409 | registration_closed |
| Event full | 409 | event_full |
| Already registered | 409 | already_registered |

---

## 12. Protected Join-Link Policy

Public APIs must never expose:

```json
"virtual_url"
```

Join link may be returned only by:

```http
GET /api/v1/events/{event_id}/my-registration
GET /api/v1/my/registrations
```

and only when:

```text
event.is_virtual == true
user has active registered registration for event
event.status == published
registration.status == registered
```

Response should use frontend-friendly naming:

```json
"join_url": "https://..."
```

Backend storage may still use:

```json
"virtual_url"
```

For physical events, return:

```json
"venue_maps_url": "https://..."
```

or existing field:

```json
"location_maps_url": "https://..."
```

---

## 13. Confirmation Email Architecture

### 13.1 Email Modes

Use an email service abstraction:

```text
EmailService
├── LocalLogEmailProvider
└── TransactionalEmailProvider
```

Local development:

```text
EMAIL_MODE=log
```

Staging:

```text
EMAIL_MODE=send
EMAIL_PROVIDER=sendgrid or equivalent
```

### 13.2 Email Trigger

Email is sent after successful registration commit.

Recommended order:

1. Validate registration.
2. Insert/reactivate registration transactionally.
3. Commit DB transaction.
4. Attempt confirmation email.
5. Update registration email status.
6. Return registration response.

This prevents email from being sent for a failed DB registration.

### 13.3 Email Failure Policy

Registration should remain successful even if email send fails.

Response example:

```json
"confirmation_email": {
  "status": "failed",
  "message": "Registration saved, but confirmation email could not be sent."
}
```

Diagnostics must clearly show email status.

### 13.4 Email Content

Minimum email content:

- NITKSAA Event Registration Confirmation
- Registration number
- Attendee name
- Event title
- Event date/time/timezone
- Venue or online indicator
- Physical event: venue/map link
- Virtual event: join link if policy allows email to include it
- Support contact or reply-to address

Security decision:

```text
For Week 3 staging demo, join link may be included in confirmation email only if NITKSAA approves.
If not approved, email should say “Join link is available inside the app after login.”
```

---

## 14. Developer Diagnostics UI Architecture

Because direct production Flutter UI is not to be developed in Week 3, Developer Diagnostics becomes the reference UI/prototype for frontend developers.

Diagnostics should include a new section:

```text
Registration Flow
```

Recommended panels:

1. Alumni Profile Autofill
2. Event Registration Eligibility
3. Register for Event
4. Duplicate Registration Guard
5. Confirmation Result
6. Confirmation Email Result
7. My Registration Detail
8. Join Link Reveal
9. Physical Venue/Map Link
10. My Registrations List
11. Capacity Full Scenario
12. Registration Closed Scenario

Each panel should show:

- Purpose
- API endpoint
- Method
- Auth requirement
- Request sample
- Response sample
- UI state that frontend should implement
- Last run status
- Error detail

---

## 15. Backend Module Architecture

Recommended files:

```text
backend/app/api/alumni.py
backend/app/api/registrations.py
backend/app/api/dev_diagnostics_registrations.py

backend/app/schemas/alumni.py
backend/app/schemas/registrations.py

backend/app/repositories/alumni_repository.py
backend/app/repositories/registrations_repository.py
backend/app/repositories/events_repository.py

backend/app/services/alumni_service.py
backend/app/services/registration_service.py
backend/app/services/email_service.py
backend/app/services/calendar_service.py
```

If the project currently uses different names, follow current conventions.

---

## 16. Audit Events

Recommended audit actions:

```text
registration_created
registration_reactivated
registration_duplicate_blocked
registration_cancelled
confirmation_email_sent
confirmation_email_failed
join_link_revealed
registration_diagnostics_run
```

Do not log tokens or full join URLs in audit logs.

---

## 17. Architectural Decision Log

| Topic | Decision |
|---|---|
| Week 3 scope | Registration + confirmation email + protected join-link reveal |
| Direct production Flutter UI | Do not implement this week |
| Developer Diagnostics UI | Implement as reference/testing UI |
| React Admin new screens | Defer to Week 4 |
| Alumni source | `alumni_db` |
| Portal dependency | Need limited `nitksaa-portal-v2` alumni lookup details |
| Website dependency | Not required unless branding/public URL/email templates are reused |
| Join link public exposure | Not allowed |
| Join link after registration | Allowed only through authenticated user-specific endpoints |
| Confirmation email | Required for Week 3 staging demo |
| Email local mode | Stub/log allowed |
| Email staging mode | Real provider required |
| Attendance/check-in/QR | Deferred |
| Waitlist/payment | Deferred |

---

## 18. Approval Checklist

Before coding, approve:

- [ ] Week 3 includes confirmation email.
- [ ] Week 3 includes protected join-link reveal after registration.
- [ ] Developer Diagnostics will show registration UI flows.
- [ ] Direct production Flutter registration screens are deferred.
- [ ] React Admin registration screens are deferred to Week 4.
- [ ] `nitksaa-portal-v2` alumni lookup details will be reviewed.
- [ ] Email provider/staging mode is selected.
- [ ] Join link in email is approved or explicitly disabled.
