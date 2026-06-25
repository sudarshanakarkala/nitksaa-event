# Week 4 Phase 2 — Attendee Management Verification

Date: 2026-06-24

## Scope

Phase 2 implements admin attendee management for the NITKSAA Event App. This document records the implementation decisions, deliverables, and verification checklist.

---

## Business Rule: show_attendee_list is Ignored by Admin Endpoints

**Decision:** All admin attendee and registration endpoints intentionally ignore the `show_attendee_list` flag on the event.

**Reason:** `show_attendee_list` controls whether the public event listing exposes attendee counts or attendee details to unauthenticated users. It is a **public-facing visibility flag**. Admins require unconditional access to attendee data to operate the event regardless of the public visibility setting.

**Where enforced:**
- `RegistrationRepository._attendee_where()` — filters by `status='registered'` only, never checks `show_attendee_list`
- `RegistrationRepository._registration_where()` — filters by `event_id` only
- `admin_events.py` — all three admin endpoints use `get_admin_user` dependency; no `show_attendee_list` check

**Documentation site:** This decision is also recorded as a comment in `registration_repository.py`.

---

## Deliverables

### Backend

| File | Change |
|---|---|
| `backend/app/repositories/registration_repository.py` | Added `list_attendees`, `count_attendees`, `export_attendees`, `list_registrations`, `count_registrations` |
| `backend/app/schemas/registrations.py` | Added `AdminAttendeeItem`, `AdminAttendeeListResponse`, `AdminRegistrationItem`, `AdminRegistrationListResponse` |
| `backend/app/api/admin_events.py` | Replaced 501 stubs; added `GET /attendees`, `GET /attendees/export`, `GET /registrations` |
| `backend/app/api/dev_diagnostics.py` | Added `GET /api/v1/dev/diagnostics/attendees` |

### Admin Portal

| File | Change |
|---|---|
| `admin/event_admin/src/api/attendeesApi.js` | New — `listAdminAttendees`, `exportAttendeesCSV`, `listAdminRegistrations`, `listAdminEvents` |
| `admin/event_admin/src/styles/attendees.css` | New — styles for AttendeesPage and RegistrationsPage |
| `admin/event_admin/src/pages/AttendeesPage.jsx` | Full implementation — event selector, search, batch filter, CSV export, summary card, table |
| `admin/event_admin/src/pages/RegistrationsPage.jsx` | Full implementation — event selector, status filter pills, registrations table |

---

## Endpoint Specifications

### GET /api/v1/admin/events/{event_id}/attendees

- **Purpose:** Operational attendee list
- **Returns:** `status='registered'` rows only
- **Query params:** `search` (ILIKE fullname), `batch_year` (exact), `page` (default 1), `per_page` (default 50, max 200)
- **Ordering:** `registered_at ASC`
- **Response fields:** `registration_id`, `registration_number`, `fullname_snapshot`, `email_snapshot`, `phone_snapshot`, `batch_year_snapshot`, `branch_snapshot`, `registered_at`, `status`, `confirmation_email_status`
- **Does NOT include:** `virtual_url`, `join_url`, `qr_token`, `firebase_uid`, audit metadata

### GET /api/v1/admin/events/{event_id}/attendees/export

- **Purpose:** CSV export of active attendees
- **Same filters:** `search`, `batch_year` (no pagination)
- **CSV columns:** `registration_number`, `fullname_snapshot`, `email_snapshot`, `batch_year_snapshot`, `branch_snapshot`, `phone_snapshot`, `registered_at`, `status`
- **Encoding:** UTF-8 with BOM (`utf-8-sig`) for Excel compatibility
- **Content-Type:** `text/csv; charset=utf-8`
- **Filename:** `attendees-event-{event_id}.csv`

### GET /api/v1/admin/events/{event_id}/registrations

- **Purpose:** Audit view — all registration statuses
- **Query params:** `status` (optional: `registered` | `cancelled`), `page`, `per_page`
- **Ordering:** `registered_at ASC`
- **Response fields:** `registration_id`, `registration_number`, `fullname_snapshot`, `email_snapshot`, `status`, `registered_at`, `cancelled_at`
- **Note:** Future statuses are automatically compatible — no code changes needed

---

## Use Case Verification

Verified via `GET /api/v1/dev/diagnostics/attendees?event_id={id}` in development mode.

| UC | Name | Verification Method |
|---|---|---|
| UC-01 | Attendees visible | `list_attendees` returns only `status='registered'` rows |
| UC-02 | Search works | ILIKE filter on `fullname_snapshot` narrows results correctly |
| UC-03 | Batch filter works | Exact `batch_year_snapshot` filter returns matching rows only |
| UC-04 | Pagination works | Page 1 and page 2 return non-overlapping rows, each ≤ per_page |
| UC-05 | CSV export works | `export_attendees` returns rows with all 8 required columns |
| UC-06 | Cancelled hidden from attendees | `list_attendees` WHERE clause enforces `status='registered'` |
| UC-07 | Cancelled visible in registrations | `list_registrations` with `status='cancelled'` returns cancelled rows |
| UC-08 | Admin required | All routes use `Depends(get_admin_user)` — structural guarantee |
| UC-09 | Event not found | Endpoints return 404 via explicit event existence check before repo calls |
| UC-10 | Empty attendee list | Returns `attendees: [], total: 0` — no crash |

---

## Load Testing Scenarios

### Scenario 1: Breakfast Club (in-person, capacity 30)

- Create event with `capacity=30`
- Register 30 alumni → all succeed
- Register user 31 → expect `409 event_full`
- `GET /attendees` → `total=30`, all `status='registered'`
- `GET /attendees/export` → CSV contains 30 rows
- **Expected:** Capacity enforcement holds; export is exact

### Scenario 2: Webinar (virtual event)

- Create event with `is_virtual=true`, `virtual_url` set
- Register alumni → `join_url` present in registration response
- `GET /attendees` → attendees listed without `virtual_url` or `join_url`
- `GET /attendees/export` → CSV contains no URL fields
- **Expected:** Attendee export safe; join link not leaked to CSV

---

## Repository Layer Design

Explicit methods are created for each semantic operation:

| Method | Semantics |
|---|---|
| `list_attendees` | Active registrations only (operational) |
| `count_attendees` | Count for pagination (active only) |
| `export_attendees` | All active rows, no pagination (for CSV) |
| `list_registrations` | All statuses with optional filter (audit) |
| `count_registrations` | Count for pagination (all statuses) |

The attendee and registration semantics are kept strictly separate. There are no generic catch-all methods.

---

## Admin Portal UI

### AttendeesPage

- Event selector dropdown (loads all events)
- Search by name (debounced via controlled input + `useEffect`)
- Batch year filter dropdown (1960 to current year)
- Export CSV button (triggers blob download)
- Summary card: status, capacity, attendee count, remaining seats, deadline, created/published info
- Attendee table: Name + registration number, Batch, Branch, Email, Phone, Registered At, Email Status
- Pagination (prev/next) with row range display

### RegistrationsPage

- Event selector dropdown
- Status filter pills: All / Registered / Cancelled
- Registrations table: Registration Number, Name + email, Status badge, Registered At, Cancelled At
- Pagination

---

## What Was NOT Implemented

Per Phase 2 scope (explicitly deferred):

- Flutter registration UI
- QR attendance / check-in rewards
- Meeting provider OAuth
- Analytics / engagement rewards
- Paid events / payment gateway
- Full audit viewer
- Session / speaker / sponsor management
