# NITKSAA Event App — Week 3 Execution Plan v2.0

**Version:** 2.0  
**Status:** Revised for approval before coding  
**Sprint:** Week 3 — Registration, Confirmation Email, Protected Join Link, Diagnostics UI  
**Prepared Date:** 2026-06-18  
**Starting Point:** Git tag `week2-complete`

---

## 1. Required Gate

Do not start coding until these documents are approved:

```text
week3_architecture_review_v2.md
week3_execution_plan_v2.md
week3_backend_api_contract_v2.md
week3_usecases_and_testcases_v2.md
week3_architecture_diagrams_v2.md
```

---

## 2. Branch Plan

```bash
git checkout week2-complete
git checkout -b week3-registration-confirmation
```

Recommended commit checkpoints:

```text
docs-week3-v2-approved
schema-review-complete
alumni-api-complete
registration-api-complete
email-service-complete
diagnostics-ui-complete
week3-verification-complete
```

---

## 3. Phase 0 — Repository, Schema, and Cross-Project Review

### 3.1 Review Current Event App Repository

Inspect:

```text
backend/migrations/
backend/app/api/
backend/app/repositories/
backend/app/services/
backend/app/schemas/
backend/app/models/
backend/app/database.py
backend/app/config.py
apps/event_app/lib/
admin/event_admin/src/
docs/
```

Confirm:

- `events` table columns
- `registrations` table columns
- `event_users` table columns
- `event_audit_log` structure
- existing auth dependency
- existing admin dependency
- existing event serializer
- existing dynamic fields
- existing developer diagnostics routing
- current local/staging env config style

Deliverable:

```text
docs/reviews/week3_schema_and_repo_review.md
```

### 3.2 Review `nitksaa-portal-v2`

Required only for alumni data integration.

Find and document:

- `alumni_db` connection pattern
- alumni lookup function or equivalent `fetch_alumni_info()`
- alumni table and column names
- active alumni/member status logic
- Firebase UID/email/ref_id mapping logic
- profile fields available for autofill
- phone field availability
- privacy rules used by portal

Deliverable:

```text
docs/reviews/week3_alumni_db_integration_review.md
```

### 3.3 Review `nitksaa-website`

Not required for core Week 3 backend.

Review only if available and quick:

- email branding/template assets
- public event URL format
- website domain used in emails
- “Add to calendar” UX, if existing

Do not block Week 3 on website review.

---

## 4. Phase 1 — API Contract Finalization

Create:

```text
docs/api/week3_backend_api_contract.md
```

Must include:

- `GET /api/v1/alumni/me`
- `POST /api/v1/events/{event_id}/register`
- `GET /api/v1/events/{event_id}/my-registration`
- `GET /api/v1/my/registrations`
- optional `GET /api/v1/events/{event_id}/registration-eligibility`
- Developer Diagnostics APIs
- confirmation email status
- join-link reveal rules
- all error cases
- frontend UI state mapping
- curl examples
- JSON response examples

No backend coding before API contract approval.

---

## 5. Phase 2 — Database/Migration Plan

### 5.1 Confirm Current Registration Schema

Check whether existing `registrations` supports:

```text
registration_id
event_id
firebase_uid
ref_id
status
registered_at
cancelled_at
```

### 5.2 Add Missing Columns If Needed

Recommended additions:

```text
registration_number
fullname_snapshot
email_snapshot
phone_snapshot
batch_year_snapshot
branch_snapshot
confirmation_email_status
confirmation_email_sent_at
confirmation_email_error
created_at
updated_at
```

### 5.3 Add Safety Constraints

Preferred:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_registration
ON registrations(event_id, firebase_uid)
WHERE status = 'registered';
```

If partial index is not possible immediately, implement service-level duplicate guard and document DB index as follow-up.

### 5.4 Migration Deliverable

```text
backend/migrations/events_db/00X_week3_registrations.sql
```

---

## 6. Phase 3 — Alumni Autofill Backend

### 6.1 Implement API

```http
GET /api/v1/alumni/me
```

### 6.2 Behavior

- Requires backend JWT.
- Verifies current user is alumni.
- Uses `ref_id` or approved mapping to fetch from `alumni_db`.
- Returns safe frontend fields only.

### 6.3 Response Fields

```text
ref_id
fullname
email
phone
batch_year
branch
is_active
```

### 6.4 Error Cases

```text
401 unauthorized
403 alumni_required
403 alumni_not_active
404 alumni_profile_not_found
500 alumni_db_error
```

### 6.5 Deliverables

```text
backend/app/api/alumni.py
backend/app/services/alumni_service.py
backend/app/repositories/alumni_repository.py
backend/app/schemas/alumni.py
```

Follow current project naming conventions if different.

---

## 7. Phase 4 — Registration Service

### 7.1 Core Functions

Implement:

```text
get_registration_eligibility()
register_for_event()
get_my_event_registration()
list_my_registrations()
compute_registered_count()
compute_registration_status()
generate_registration_number()
```

### 7.2 Register Flow

```text
1. Validate backend JWT.
2. Load event_user.
3. Validate user_type == alumni.
4. Fetch alumni profile from alumni_db.
5. Validate alumni active.
6. Load event.
7. Validate event is published.
8. Compute registration_status.
9. Lock event row or run transaction-safe capacity check.
10. Check duplicate active registration.
11. Insert/reactivate registration.
12. Commit.
13. Send confirmation email.
14. Update email status.
15. Return registration + event summary + email result.
```

### 7.3 Transaction Safety

Use transaction around:

- event row lock
- active count
- duplicate check
- registration insert/update

Avoid race condition where two users register for last seat.

---

## 8. Phase 5 — Registration APIs

Implement:

```http
POST /api/v1/events/{event_id}/register
GET  /api/v1/events/{event_id}/my-registration
GET  /api/v1/my/registrations
```

Optional for diagnostics/frontend clarity:

```http
GET /api/v1/events/{event_id}/registration-eligibility
```

Do not implement production cancel registration unless approved. The current Week 3 goal does not mention cancellation; it can be deferred unless existing v1 scope is retained.

Recommended: include cancellation as optional backend-only if already simple, but do not expose production UI.

---

## 9. Phase 6 — Confirmation Email Service

### 9.1 Implement Abstraction

```text
EmailService
EmailMessage
EmailProvider
```

Provider modes:

```text
log
sendgrid
```

### 9.2 Environment Variables

```text
EMAIL_MODE=log|send
EMAIL_PROVIDER=sendgrid
SENDGRID_API_KEY=
EMAIL_FROM=
EMAIL_REPLY_TO=
APP_PUBLIC_BASE_URL=
```

### 9.3 Email Template

Create template:

```text
NITKSAA Event Registration Confirmation
```

Include:

- attendee name
- registration number
- event title
- date/time/timezone
- venue or online indicator
- physical event map link
- virtual event join instruction/link based on policy
- support contact

### 9.4 Failure Policy

Registration succeeds even if email fails.

Store:

```text
confirmation_email_status = sent | failed | skipped
confirmation_email_sent_at
confirmation_email_error
```

Return email status to diagnostics/frontend.

---

## 10. Phase 7 — Protected Join-Link Reveal

### 10.1 Backend Rule

`virtual_url` must remain hidden from:

```http
GET /api/v1/events/public
GET /api/v1/events/public/{event_id}
```

`join_url` may be returned only from:

```http
GET /api/v1/events/{event_id}/my-registration
GET /api/v1/my/registrations
```

when current user is actively registered.

### 10.2 Physical Event Rule

For physical events, return:

```text
location_text
location_maps_url
```

No `join_url`.

---

## 11. Phase 8 — Update Event Serializers

Update existing event serializers so dynamic values are correct:

- `registered_count`
- `registration_status`
- capacity/full state
- registration closed state

Public APIs must continue to hide:

- `virtual_url`
- audit fields
- created_by fields
- attendee PII

---

## 12. Phase 9 — Developer Diagnostics UI Flows

### 12.1 Backend Diagnostics Endpoint

Implement:

```http
GET /api/v1/dev/diagnostics/registrations
```

Optional action endpoint:

```http
POST /api/v1/dev/diagnostics/registrations/run
```

Diagnostics must be development-only guarded.

### 12.2 Flutter Developer Diagnostics UI

Create a “Registration Flow” diagnostics section.

Panels:

1. Alumni Profile Autofill
2. Event Eligibility
3. Registration Screen Preview
4. Register API Test
5. Confirmation Screen Preview
6. Confirmation Email Result
7. Duplicate Registration Guard
8. Event Full Preview
9. Registration Closed Preview
10. My Registration Detail
11. Join Link Reveal Preview
12. My Registrations List Preview

### 12.3 Frontend Handoff Purpose

The diagnostics UI becomes the reference implementation for the frontend developer.

Each flow should clearly show:

- UI state
- API endpoint
- response payload
- error case
- expected production screen behavior

---

## 13. Phase 10 — React Admin Scope

No new production React Admin screens in Week 3.

Allowed backend-only verification:

- registration count visible in existing event detail/list if already supported by serializer
- optional API test from diagnostics
- no full attendee list/export page

Move these to Week 4:

- Attendee list page
- Search/filter
- CSV export button
- Admin attendee management

---

## 14. Phase 11 — Use Cases and Test Cases

Create:

```text
docs/reviews/week3_usecases_and_testcases.md
```

Must cover:

- successful physical event registration
- successful virtual event registration
- alumni autofill
- non-alumni blocked
- inactive alumni blocked
- duplicate registration blocked
- full event blocked
- registration not open yet
- registration closed
- draft event blocked
- cancelled event blocked
- join link hidden publicly
- join link visible after registration
- confirmation email sent
- email failure handled
- my registrations list
- diagnostics route guarded

---

## 15. Phase 12 — Verification Commands

Backend:

```bash
cd backend
python -m compileall app
```

Flutter:

```bash
cd apps/event_app
flutter analyze
flutter test
```

Admin, only if touched:

```bash
cd admin/event_admin
npm run build
npm run lint
```

Diagnostics:

```text
GET /api/v1/dev/diagnostics/registrations
```

Manual/staging:

```text
Physical event registration
Virtual event registration
Confirmation email received
Join link visible after registration
Duplicate register blocked
Full event blocked
Closed event blocked
```

---

## 16. Phase 13 — Completion Reports

Create:

```text
docs/reviews/week3_backend_api_report.md
docs/reviews/week3_diagnostics_ui_report.md
docs/reviews/week3_email_verification_report.md
docs/reviews/week3_end_to_end_verification_report.md
docs/reviews/week3_known_issues.md
```

---

## 17. Week 3 Acceptance Criteria

Week 3 is complete only when:

- Alumni autofill API works.
- Active alumni validation works.
- Registration API works.
- Capacity is enforced.
- Deadline is enforced.
- Duplicate active registration is blocked.
- Dynamic `registered_count` is correct.
- Confirmation number is generated.
- Confirmation email is sent in staging or clearly logged locally.
- Email failure does not break registration.
- Public APIs still hide join link.
- Authenticated registered user can see join link for virtual event.
- Diagnostics UI demonstrates required frontend flows.
- No attendance/check-in/QR added.
- No waitlist/payment added.
- No production React Admin attendee screen added.
