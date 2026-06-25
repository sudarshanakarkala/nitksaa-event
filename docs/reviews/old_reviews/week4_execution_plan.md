# Week 4 Execution Plan

**Date:** 2026-06-22
**Team:** CAR SOFTWARE SYSTEMS
**Branch:** main
**Deadline:** Jun 30, 2026 beta handoff

---

## Phase 0 — Architecture Review and Decisions (Day 1 morning)

These are not implementation tasks. They are decision gates that unblock implementation.

| Task | Owner | Acceptance |
|---|---|---|
| Agree OI-3 eligibility_status string values (v2 contract) | Backend + Flutter | Written confirmation. Flutter developer has the list before coding. |
| Verify `ALUMNI_DB_URL` on every developer machine | All | Each dev can run `GET /api/v1/alumni/me` against local backend without error. |
| Confirm SMTP credentials location in Secret Manager | Backend | `SMTP_USER` and `SMTP_PASSWORD` identified. Staging env vars named. |
| Confirm Gmail app password is shared with Event App | Product Owner | Same credential as website or a new one provisioned. |
| Confirm attendees vs registrations endpoint naming | Backend | Documented in API contract. Flutter developer and admin portal developer aligned. |
| Review `week4_feedback_architecture_decisions.md` | All | Each decision marked as DECIDED or DEFERRED for Alpha. |

**Phase 0 exit:** All decisions recorded. Every developer can run the full local stack end-to-end.

---

## Phase 1 — Production Readiness Fixes (Day 1–2)

These are pre-conditions for demo reliability. They block the demo, not Day 1 development.

### 1.1 Real email delivery in staging

**File:** `backend/app/services/email_service.py`
**File:** `backend/app/config.py` (already has all SMTP settings)
**File:** staging environment variables (Cloud Run or .env.staging)

Steps:
1. Set `EMAIL_MODE=send` in staging environment.
2. Set `SMTP_USER=nitksaa.infra@gmail.com` (or the designated event account).
3. Set `SMTP_PASSWORD=<gmail_app_password>` from Secret Manager.
4. Set `EMAIL_FROM=nitksaa.infra@gmail.com`.
5. Test: register for a test event, verify email arrives in inbox.

**Acceptance:** Registration confirmation email arrives in a real Gmail inbox within 30 seconds of a
test registration via Swagger or curl.

### 1.2 Fix event loop blocking in email service

**File:** `backend/app/services/email_service.py`

`send_confirmation_email()` is declared `async def` but the inner `smtplib.SMTP()` call is
synchronous. Under concurrent load this blocks the FastAPI event loop for 1–3 seconds per registration.

Fix: wrap the synchronous SMTP block in `asyncio.to_thread()`:

```python
import asyncio

# Replace:
with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
    ...

# With:
await asyncio.to_thread(_send_smtp_sync, from_addr, email_to, msg)
```

Where `_send_smtp_sync` is a regular (non-async) helper that contains the smtplib block.

**Acceptance:** `registration_service.register_for_event()` does not block the event loop during
SMTP. `asyncio.to_thread()` confirmed in code.

### 1.3 Add plain text fallback to email

**File:** `backend/app/services/email_service.py`

The current `_build_html()` produces HTML only. `MIMEMultipart("alternative")` requires a plain text
part or some email clients will show the raw HTML. Reference: `portal-v2/services/email.py` adds both
plain and HTML parts to every message.

Fix: add `_build_plain()` function and `msg.attach(MIMEText(_build_plain(...), "plain"))` before the
HTML part.

**Acceptance:** Outgoing MIME messages contain both a `text/plain` and a `text/html` part.

### 1.4 Stale text fix in RegistrationsPage.jsx

**File:** `admin/event_admin/src/pages/RegistrationsPage.jsx:10`

Line 10 reads: `<p className="page-eyebrow">Coming in Week 3</p>`

The registration backend was built in Week 3 but the admin portal page is still a placeholder.
Update text to reflect actual status ("Backend complete — Admin UI coming in Week 4" or simply remove
the placeholder card if the registration list API is wired in Phase 2).

**Acceptance:** No "Coming in Week 3" text visible in the admin portal.

---

## Phase 2 — Admin Attendee Management (Day 1–4)

The entire admin attendee management layer is unbuilt. Backend and admin portal work can run in parallel.

### 2.1 Backend — Implement attendee list endpoint

**File:** `backend/app/api/admin_events.py` (replace 501 stubs)
**File:** `backend/app/repositories/registration_repository.py` (add query)
**File:** `backend/app/schemas/registrations.py` (add AdminAttendeeListResponse)

Replace the `list_registrations` 501 stub with a real implementation.
The `list_attendees` endpoint should return only `status='registered'` rows.
The `list_registrations` endpoint should return all statuses (for audit).

See `docs/api/week4_attendee_management_api_contract.md` for full response shapes.

**Acceptance:**
- `GET /api/v1/admin/events/{event_id}/attendees` returns paginated list of registered attendees.
- Search by name (`?search=`) filters `fullname_snapshot ILIKE '%search%'`.
- Filter by batch year (`?batch_year=`) filters `batch_year_snapshot = batch_year`.
- Requires admin auth (`get_admin_user` dependency — already wired).
- Returns 200 with empty `attendees: []` for event with no registrations.
- Returns 404 for unknown `event_id`.
- Returns 403 for non-admin caller.

### 2.2 Backend — Implement CSV export endpoint

**File:** `backend/app/api/admin_events.py`

New endpoint: `GET /api/v1/admin/events/{event_id}/attendees/export`

Returns `Content-Type: text/csv; charset=utf-8` with `Content-Disposition: attachment; filename=...`

CSV columns (in order): `registration_number`, `fullname_snapshot`, `email_snapshot`,
`batch_year_snapshot`, `branch_snapshot`, `phone_snapshot`, `registered_at`, `status`

Use `io.StringIO` + `csv.DictWriter`. Return via FastAPI `StreamingResponse`.

**Acceptance:**
- Browser download triggered from admin portal returns a `.csv` file.
- File opens correctly in Excel/Numbers (UTF-8 with BOM if needed for Excel compatibility).
- Filename format: `attendees-{event_id}-{YYYY-MM-DD}.csv`

### 2.3 Admin portal — Wire AttendeesPage.jsx to real API

**File:** `admin/event_admin/src/pages/AttendeesPage.jsx` (replace placeholder)
**File:** `admin/event_admin/src/api/eventsApi.js` (add attendee API calls)

Build a functional page:
- Table: columns for Name, Batch Year, Branch, Registered At, Status
- Search bar (name) — debounced, fires on input change
- Batch year filter dropdown (unique years from response)
- Pagination (page controls if total > page size)
- CSV export button — triggers `GET .../export` download
- Event summary card (top of page): total registered / capacity, registration deadline, event status

**Acceptance:**
- Page loads attendee list for selected event.
- Search by name filters the table.
- CSV export button downloads a valid CSV.
- Empty state visible when event has no attendees.

### 2.4 Admin portal — Event summary card on AttendeesPage

Display at the top of the attendees page:
- Event title + status badge
- Registered count / capacity (e.g., "14 / 30" or "14 registered — no cap")
- Registration opens / closes dates
- Created by (firebase_uid or name if available)

Data available from `GET /api/v1/admin/events` response shape (already implemented).

---

## Phase 3 — Production Flutter Registration UI (Day 1–5)

The Flutter developer has a 7-section UX prototype in `developer_diagnostics_screen.dart` as an exact
reference. All backend endpoints are verified. Use the prototype sections as the specification.

### 3.1 Registration screen

**File to create:** `apps/event_app/lib/features/registration/presentation/register_screen.dart`

Triggered from `EventDetailScreen` when user taps the Register CTA.

Flow:
1. Call `GET /api/v1/alumni/me` — autofill name, batch year, branch (read-only display).
2. Optional `attendee_note` text field (max 200 chars).
3. Confirm details, single "Register" tap.
4. Call `POST /api/v1/events/{event_id}/register`.
5. On 201: navigate to confirmation screen.
6. On 409 `already_registered`: show "You are already registered" banner, navigate to my-registration.
7. On 409 `event_full`: show "This event is at capacity" banner.
8. On 403 `alumni_not_active`: show "Your alumni account is not currently active".
9. On network error: show retry option.

**Acceptance:**
- Prototype section `_registerProto` in diagnostics screen matches production screen behavior.
- All error codes listed above produce appropriate user-facing messages (no raw error codes visible).
- Registration number is visible on success.

### 3.2 Confirmation screen

**File to create:** `apps/event_app/lib/features/registration/presentation/confirmation_screen.dart`

Shows after successful registration:
- "Registration Confirmed" header
- Registration number (e.g., `NITKSAA-2026-000042`)
- Event title, date/time (formatted in event timezone)
- Location text (physical) or "Join link available" (virtual — reveal join_url from RegistrationResponse)
- "View my registrations" link

**Acceptance:**
- `registration_number` is displayed.
- Virtual events show `join_url` (only present for published+virtual+registered).
- Physical events show `location_text`.

### 3.3 My-registrations screen

**File to create:** `apps/event_app/lib/features/registration/presentation/my_registrations_screen.dart`

Calls `GET /api/v1/my/registrations`. Displays list of all user registrations.

Per item:
- Event title
- Registration number
- Status badge (registered / cancelled)
- Event date/time
- For registered virtual events: "View join link" tap → opens join_url

Empty state: "No registrations yet — browse events to register."

**Acceptance:**
- All registrations (active and cancelled) are listed.
- Join link accessible for eligible registrations.
- Empty state shown when `total: 0`.

### 3.4 Registration CTA on EventDetailScreen

**File:** `apps/event_app/lib/features/events/presentation/event_detail_screen.dart`

Update the event detail screen CTA button based on eligibility:

| eligibility_status | CTA state |
|---|---|
| `eligible` | "Register" (active, navigates to RegisterScreen) |
| `already_registered` | "View my registration" (navigates to my-registration for this event) |
| `full` | "Event is full" (disabled) |
| `closed` | "Registration closed" (disabled) |
| `not_open_yet` | "Registration opens soon" (disabled, show opens_at date) |
| `ineligible` | "Alumni only" (disabled) |
| Not authenticated | "Sign in to register" (navigates to login) |

**Acceptance:**
- CTA correctly reflects eligibility state for authenticated users.
- Unauthenticated users see "Sign in to register".
- `OI-3` values (`eligible`, `full`, `closed`, `not_open_yet`, `ineligible`) are used — not v1 values.

### 3.5 Flutter polish (error states, skeletons, edge cases)

Per beta plan Week 4 Flutter scope:

- Error state widgets on listing screen (network failure, server error)
- Loading skeleton on event list and event detail (shimmer or placeholder cards)
- Empty state on listing when no events published
- Edge case: registration deadline passed — CTA replaced with "Registration closed"
- Edge case: event cancelled — banner on detail page
- `flutter analyze` clean — all warnings resolved

---

## Phase 4 — Architecture Documentation (Day 4–5)

Phase 4 produces architecture documents only. No migrations, no backend changes, no frontend changes.
Each document defines the schema design, API shape, and deferred implementation plan for the architecture
gaps identified in the Week 4 review meeting.

**Rule: Do not implement any Phase 4 item in Week 4 unless the product owner explicitly approves in
writing before implementation begins. Writing the document is the Week 4 deliverable.**

### 4.1 Login UI cleanup (Flutter — Day 4, implement approved)

This is the one Phase 4 item that IS approved for implementation — it is a small, low-risk Flutter
change with no schema or API impact.

**File:** `apps/event_app/lib/features/auth/presentation/screens/login_screen.dart`
**File:** `apps/event_app/lib/features/auth/services/auth_controller.dart`

Issues:
- `_statusMessage = 'Signing in with Firebase...'` — "Firebase" is a technical internal term
- `'Backend session validated. Opening diagnostics...'` — leaks internal routing logic
- `auth_controller.dart:188` catch-all: `error.message ?? 'Firebase authentication failed.'` — may
  expose raw Firebase SDK error messages for unmapped codes

Fixes:
- Replace "Signing in with Firebase..." with "Signing in..."
- Replace "Backend session validated. Opening..." with "Signed in successfully."
- Add common unmapped error codes to the switch statement:
  `'too-many-requests' => 'Too many attempts. Try again later.'`
  `'network-request-failed' => 'Network error. Check your connection.'`
  `'popup-blocked' => 'Sign-in popup was blocked. Allow popups and try again.'`

**Acceptance:**
- No word "Firebase" visible in user-facing status or error messages.
- No internal route names visible in user-facing messages.
- 3 additional error codes handled with friendly messages.

### 4.2 Architecture document — Event people, speakers, sessions

**Output:** `docs/architecture/event_people_speakers_architecture_v1.md`

Covers:
- Problem statement: sessions table exists; speakers/sessions exposed as empty or hard-coded in public API
- Why speakers and people must be designed together (speaker is one role, not the only role)
- Proposed `event_people` table and `session_people` join table
- Role enum: HOST, MODERATOR, SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR, ORGANIZER
- API response shape: `people[]`, `speakers[]` (derived subset), `sessions[].speakers[]`
- Backward compatibility: `speakers` field derived from `event_people` where role in speaker-class roles
- Admin UI future needs
- Flutter and public website impact
- Do not implement: this is architecture documentation only

### 4.3 Architecture document — Sponsors and partners (separate)

**Output:** `docs/architecture/event_sponsors_partners_architecture_v1.md`

Covers:
- Why sponsors and partners are not the same concept
- `event_sponsors` table with `sponsor_type` enum (TITLE, GOLD, SILVER, BRONZE, ASSOCIATE)
- `event_partners` table with `partner_type` enum (COMMUNITY, KNOWLEDGE, MEDIA, VENUE, TECHNOLOGY,
  ECOSYSTEM, HIRING)
- API response shape: `sponsors[]` and `partners[]` as separate arrays in public event detail
- Performance/extensibility tradeoff
- Do not implement: architecture documentation only

### 4.4 Architecture document — Event analytics / activity log

**Output:** `docs/architecture/event_analytics_architecture_v1.md`

Covers:
- Audit log vs. analytics log: they are not the same
- Required action types: `event_viewed`, `register_clicked`, `registration_completed`,
  `registration_failed`, `join_link_clicked`, `add_to_calendar_clicked`, `venue_map_clicked`,
  `email_sent`, `email_failed`, `event_shared`, `attendance_checked_in`
- Proposed `event_activity_log` table
- Privacy rules: no unnecessary PII, no public exposure, no mixing with audit/security log
- Source app tracking: `flutter`, `admin`, `website`
- Do not implement: architecture documentation only

### 4.5 Architecture document — Engagement rewards

**Output:** `docs/architecture/engagement_rewards_architecture_v1.md`

Covers:
- Rewardable actions and their dependency on analytics and check-in
- `engagement_rules` table (action_type, points, active, limits)
- `engagement_ledger` table (per-user, per-event points tracking)
- `user_engagement_summary` table (total points, events attended)
- Dependency chain: rewards require analytics + check-in to be live first
- Do not implement: architecture documentation only

### 4.6 Architecture document — Paid events

**Output:** `docs/architecture/paid_events_architecture_v1.md`

Covers:
- Free vs. paid event concept
- `registration_fee_type` enum on events table: FREE, PAID
- `registration_fee_amount`, `registration_fee_currency`, `payment_required` fields
- Future `event_payments` table design
- Alpha decision: all events are free; no payment gateway
- Do not implement payment: architecture documentation only

---

**Phase 4 deliverables checklist:**

| Document | Status |
|---|---|
| Login UI cleanup (Flutter — implement approved) | [ ] |
| `event_people_speakers_architecture_v1.md` | [ ] |
| `event_sponsors_partners_architecture_v1.md` | [ ] |
| `event_analytics_architecture_v1.md` | [ ] |
| `engagement_rewards_architecture_v1.md` | [ ] |
| `paid_events_architecture_v1.md` | [ ] |

---

## Verification Plan

End-to-end verification before demo, against the staging environment (not localhost).

### Breakfast Club scenario (physical event, 30 capacity)

1. Admin creates event in admin portal → publishes
2. Alumni opens Flutter app → logs in
3. Navigates to event → CTA shows "Register"
4. Taps Register → autofill shows name/batch/branch → confirms
5. Confirmation screen shows registration number
6. Confirmation email arrives in inbox within 60 seconds
7. Event detail screen CTA now shows "View my registration"
8. My-registrations screen shows the registration
9. 30 alumni register → 31st sees "Event is full" CTA
10. Admin opens attendees page → sees 30 registrations
11. Admin searches by name → filtered correctly
12. Admin downloads CSV → valid file with 30 rows

### Webinar scenario (virtual event)

1. Admin creates virtual event with join_url → publishes
2. Alumni registers → confirmation screen shows "Join link available"
3. Tapping join link opens `virtual_url`
4. My-registrations screen shows join link for this event
5. Another alumnus views event detail without registering → no join link visible
6. Admin exports CSV → `virtual_url` is NOT in CSV (admin security check)

### Error scenarios

- Attempt to register when not logged in → redirected to login
- Inactive alumni account → "Your alumni account is not currently active"
- Backend offline → error state with retry visible (not spinner forever)
- Network loss after registration → confirmation screen still shows (optimistic state)

---

## Demo Notes

**Jun 30 beta demo targets:**

1. Two scenarios back to back (Breakfast Club physical + Webinar virtual) — see Verification Plan above
2. Admin portal attendee table + CSV export must be functional
3. Confirmation email must arrive during the live demo — test with a real Gmail inbox before demo

**Known limitations to state explicitly at demo:**

- QR check-in not implemented
- Session/track management not exposed in Flutter app
- Payment not implemented — all events are free for Alpha
- Sponsors/partners fields not in the UI
- Full day events not specially handled
- Meeting link is static (no Zoom/GMeet OAuth generation)

**Do not demo:**
- Dev diagnostics screen (internal tool — do not expose)
- Raw API responses (Swagger is for dev use, not demo)
- The `EMAIL_MODE=log` fallback — all demo emails must be real

**Staging environment checklist before demo:**
- [ ] `EMAIL_MODE=send` set
- [ ] SMTP credentials active in staging
- [ ] At least one physical and one virtual test event published
- [ ] Test alumni account with `user_type='alumni'` + active status in alumni_db
- [ ] Admin portal deployed and pointing to staging API
- [ ] Flutter build pointing to staging backend URL
