# Week 4 — Admin Attendee Management API Contract

**Date:** 2026-06-22
**Version:** v1 (Week 4)
**Status:** PROPOSED — requires team agreement before implementation
**Extends:** `events_api_contract_v2.md`, `event_admin_api_usage_v2.md`

---

## Summary

This document defines the three new admin attendee management endpoints for Week 4:

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/admin/events/{event_id}/attendees` | Paginated list of active attendees (Week 4 primary) |
| GET | `/api/v1/admin/events/{event_id}/attendees/export` | CSV export of attendees |
| GET | `/api/v1/admin/events/{event_id}/registrations` | Full registration list including cancelled rows |

All three endpoints are currently 501 stubs in `backend/app/api/admin_events.py`.

---

## Naming Decision: Attendees vs. Registrations

The codebase has two stubs with different names:
- `list_registrations` at `GET .../registrations`
- `list_attendees` at `GET .../attendees`

**Recommendation: implement both with distinct semantics.**

| Endpoint | Returns | Admin use case |
|---|---|---|
| `/attendees` | `status='registered'` rows only | Day-of event management, headcount, CSV export |
| `/registrations` | All rows (all statuses) | Audit trail, cancellation investigation |

The admin portal `AttendeesPage.jsx` and the beta plan both reference `/attendees` for the Week 4
operational use case. The `RegistrationsPage.jsx` placeholder represents the full audit view.

---

## Authentication and Authorization

All three endpoints use the existing `get_admin_user` dependency in `app/middleware/dev_auth.py`.
This is consistent with all existing admin endpoints.

No new auth changes required.

**Error if not admin:**
```json
HTTP 403
{
  "detail": "admin_required"
}
```

---

## GET /api/v1/admin/events/{event_id}/attendees

Returns the paginated list of alumni who have an active registration (`status='registered'`) for
the event. This is the primary operational view.

### Path Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `event_id` | integer | Yes | Internal event ID |

### Query Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `search` | string | — | Case-insensitive filter on `fullname_snapshot`. Applied as `ILIKE '%search%'`. |
| `batch_year` | integer | — | Exact match on `batch_year_snapshot`. |
| `page` | integer | 1 | 1-indexed page number. |
| `per_page` | integer | 50 | Page size. Max: 200. |

### Response — 200 OK

```json
{
  "event_id": 3,
  "event_title": "NITKonnect Breakfast Club — July 2026",
  "total": 14,
  "page": 1,
  "per_page": 50,
  "attendees": [
    {
      "registration_id": 42,
      "registration_number": "NITKSAA-2026-000042",
      "fullname_snapshot": "Priya Nair",
      "email_snapshot": "priya.nair@example.com",
      "phone_snapshot": "+91-9876543210",
      "batch_year_snapshot": 2005,
      "branch_snapshot": "Computer Science",
      "attendee_note": "",
      "registered_at": "2026-06-25T14:32:00+05:30",
      "status": "registered",
      "confirmation_email_status": "sent"
    }
  ]
}
```

### Notes

- `email_snapshot` and `phone_snapshot` are sensitive — this endpoint is admin-only.
- `confirmation_email_status`: `pending` | `sent` | `failed` | `skipped`
- `attendee_note` maps to the `notes` column in the registrations table.
- `registered_at` is always timezone-aware (ISO 8601 with offset).
- Results are ordered by `registered_at ASC` (first registered first).

### Error Responses

| Code | `detail` value | Condition |
|---|---|---|
| 403 | `admin_required` | Caller is not an admin |
| 404 | `event_not_found` | `event_id` does not exist |
| 400 | `invalid_per_page` | `per_page` > 200 |

---

## GET /api/v1/admin/events/{event_id}/attendees/export

Returns a CSV file download of all active attendees for the event.

### Path Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `event_id` | integer | Yes | Internal event ID |

### Query Parameters

Same as attendee list: `search`, `batch_year`. No pagination — export returns all matching rows.

### Response — 200 OK

```
Content-Type: text/csv; charset=utf-8
Content-Disposition: attachment; filename="attendees-3-2026-06-25.csv"
```

CSV columns (in this order, with header row):

```
registration_number,fullname_snapshot,email_snapshot,batch_year_snapshot,branch_snapshot,phone_snapshot,registered_at,status
NITKSAA-2026-000042,Priya Nair,priya.nair@example.com,2005,Computer Science,+91-9876543210,2026-06-25T14:32:00+05:30,registered
```

### Notes

- Filename format: `attendees-{event_id}-{YYYY-MM-DD}.csv` where the date is the export date.
- `registered_at` is exported as ISO 8601 (not localised — admin tools handle timezone display).
- `virtual_url` and `join_url` are **NOT** included in the CSV export (security).
- If no attendees match the filter, the CSV contains only the header row (no 404).
- Encoding: UTF-8 with BOM (`utf-8-sig`) for Excel compatibility on Windows.

### Error Responses

| Code | `detail` value | Condition |
|---|---|---|
| 403 | `admin_required` | Caller is not an admin |
| 404 | `event_not_found` | `event_id` does not exist |

---

## GET /api/v1/admin/events/{event_id}/registrations

Returns all registration rows for the event regardless of status. Used for audit and
cancellation investigation.

### Path Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `event_id` | integer | Yes | Internal event ID |

### Query Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `status` | string | — | Filter by status. Values: `registered`, `cancelled`. If omitted, returns all. |
| `page` | integer | 1 | 1-indexed page number. |
| `per_page` | integer | 50 | Page size. Max: 200. |

### Response — 200 OK

```json
{
  "event_id": 3,
  "event_title": "NITKonnect Breakfast Club — July 2026",
  "total": 16,
  "page": 1,
  "per_page": 50,
  "registrations": [
    {
      "registration_id": 42,
      "registration_number": "NITKSAA-2026-000042",
      "fullname_snapshot": "Priya Nair",
      "email_snapshot": "priya.nair@example.com",
      "phone_snapshot": "+91-9876543210",
      "batch_year_snapshot": 2005,
      "branch_snapshot": "Computer Science",
      "attendee_note": "",
      "registered_at": "2026-06-25T14:32:00+05:30",
      "cancelled_at": null,
      "status": "registered",
      "confirmation_email_status": "sent",
      "confirmation_email_sent_at": "2026-06-25T14:32:05+05:30",
      "updated_at": null
    }
  ]
}
```

### Notes

- This endpoint is for admin audit only. Do not surface it in the main attendee management UI.
- `cancelled_at` is populated for cancelled rows, null otherwise.
- `confirmation_email_sent_at` is useful for debugging email delivery issues.

---

## Backward Compatibility Notes

### What these endpoints replace

The 501 stubs in `admin_events.py`:
```python
@router.get("/events/{event_id}/registrations")  # → replace with real implementation
@router.get("/events/{event_id}/attendees")       # → replace with real implementation
```

The HTTP path, HTTP method, and auth dependency are unchanged. Only the response body changes from
`{"detail": "admin_registration_list_not_implemented"}` to real data.

### What does NOT change

- All existing Week 3 registration endpoints (`/api/v1/events/{id}/register`, `/api/v1/my/registrations`,
  etc.) are not modified.
- `RegistrationResponse` schema used by alumni-facing endpoints is not modified.
- The `registrations` table schema is not changed in Week 4.
- `get_admin_user` dependency is reused as-is — no auth changes.

### New schema for admin responses

`AdminAttendeeListResponse` and `AdminRegistrationListResponse` are new Pydantic models in
`app/schemas/registrations.py`. They are additive — they do not replace any existing schema.

---

## Repository Layer

The implementation adds two new methods to `RegistrationRepository`:

```python
async def list_for_admin_attendees(
    event_id: int,
    search: str | None = None,
    batch_year: int | None = None,
    page: int = 1,
    per_page: int = 50,
) -> tuple[list[Record], int]:
    ...  # returns (rows, total_count)

async def list_for_admin_all(
    event_id: int,
    status_filter: str | None = None,
    page: int = 1,
    per_page: int = 50,
) -> tuple[list[Record], int]:
    ...  # returns (rows, total_count)
```

These are additive to `backend/app/repositories/registration_repository.py` — no existing methods
are changed.

---

## Scope Boundary — What This Contract Does Not Cover

This contract covers admin attendee and registration management only. It does not cover:

- People, speakers, hosts, moderators, or panelists associated with the event
- Sponsors or partners
- Event analytics or activity log endpoints
- Engagement reward endpoints

These are separate architecture concerns documented in `docs/architecture/`. When implemented, they
will be surfaced through the **public event detail endpoint** (`GET /api/v1/events/{slug}` or
`GET /api/v1/events/public/{id}`), not through the admin attendee endpoints.

The future public event detail response shape will expand to include:

```json
{
  "event": {},
  "sessions": [],
  "people": [],
  "speakers": [],
  "sponsors": [],
  "partners": []
}
```

The `speakers` field will be a **derived subset** of `people` (roles: SPEAKER, PANELIST,
CHIEF_GUEST, GUEST_OF_HONOUR) for backward compatibility. The `people` field will include all
event-level people regardless of role.

The attendee management endpoints defined in this document (`/attendees`, `/attendees/export`,
`/registrations`) are unaffected by these additions. Their response shapes, query parameters,
and auth requirements do not change when people/sponsors/partners are added.

---

## Admin Portal Integration

`AttendeesPage.jsx` calls `GET .../attendees` (not `.../registrations`).

New API client methods in `admin/event_admin/src/api/eventsApi.js`:
```javascript
export async function getEventAttendees(token, eventId, { search, batchYear, page, perPage }) { ... }
export async function exportEventAttendeesCsv(token, eventId, { search, batchYear }) { ... }
```

The CSV export triggers a browser download by creating a temporary anchor element with the
response blob URL. No new page navigation required.
