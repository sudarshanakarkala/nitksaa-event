# Event Admin API Usage v2

**Version:** 2.0  
**Date:** 2026-06-19  
**Status:** AUTHORITATIVE — supersedes `event_admin_api_usage_v1.md`  
**Frontend:** NITKSAA React Event Admin portal (`EventAdmin/`)  
**Backend router files:** `backend/app/api/auth.py`, `backend/app/api/events.py`

> `event_admin_api_usage_v1.md` is retained for historical reference. The "Future APIs Planned"
> sections in v1 used `{slug}` path parameters (now `{event_id}`) and incorrectly listed several
> admin-only endpoints as "No auth". Do not use v1 planned paths in new frontend code.

---

## Admin Portal Overview

The NITKSAA React Event Admin portal uses two groups of backend routes:

| Route group | Router file | Auth | Purpose |
|---|---|---|---|
| `/api/v1/auth/...` | `auth.py` | Firebase → JWT exchange | Login, session management |
| `/api/v1/events/...` | `events.py` | Backend JWT (admin) | Event CRUD, status management |
| `/api/v1/events/public/...` | `events.py` | None | Public preview (read-only) |

> There is also a separate `admin_events.py` router at `/api/v1/admin/...` used by the
> EventAdmin portal for a different set of admin workflows. That router is not covered here.
> See `backend_api_index_v2.md` for the full endpoint inventory.

---

## Week 1 — Authentication APIs

### GET /api/v1/health

- **Auth required:** No
- **Request body:** None
- **Request headers:** None
- **Used by:** LoginPage (health indicator), Header (health dot), DashboardPage (health card)
- **Response:**

```json
{
  "status": "ok",
  "version": "1.0.0",
  "env": "development",
  "db": "ok"
}
```

- **Frontend usage:** `authApi.healthCheck()` → `apiClient.get('/api/v1/health')`

---

### POST /api/v1/auth/firebase

- **Auth required:** Firebase ID token in request body (NOT as `Authorization` header)
- **Request body:**

```json
{
  "token": "<firebase_id_token>"
}
```

> Field name is `token`. Firebase SDK itself uses the field name `idToken` in its own
> response — copy that value and pass it as `token` here.

- **Request headers:** `Content-Type: application/json`
- **Used by:** AuthProvider `loginWithFirebaseToken()` → `authApi.exchangeFirebaseToken()`
- **Response:**

```json
{
  "status": "ok",
  "access_token": "<backend_jwt>",
  "token_type": "bearer",
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "user_type": "alumni",
  "fullname": "NITKSAA Member",
  "ref_id": "ALUMNI123",
  "graduation_year": 2010
}
```

- **Frontend usage:**
  - `authApi.exchangeFirebaseToken(firebaseIdToken)` uses `fetch` directly (not apiClient)
    to avoid attaching any stale stored JWT as `Authorization` header
  - On success: `setAccessToken(data.access_token)` stores JWT in `localStorage`
  - Firebase ID token is NOT stored after this call

---

### GET /api/v1/auth/me

- **Auth required:** Backend JWT (`Authorization: Bearer <access_token>`)
- **Request body:** None
- **Used by:**
  - AuthProvider `loginWithFirebaseToken()` — validates session after token exchange
  - AuthProvider `restore()` useEffect — validates stored JWT on page reload
- **Response:**

```json
{
  "firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
  "email": "member@example.com",
  "fullname": "NITKSAA Member",
  "user_type": "alumni",
  "ref_id": "ALUMNI123",
  "graduation_year": 2010
}
```

- **Frontend usage:**
  - Normal call: `authApi.getCurrentUser()` → `apiClient.get('/api/v1/auth/me')`
    (apiClient attaches `Authorization: Bearer <stored_jwt>`)
  - Restore call: raw `fetch` with manual `Authorization` header
    (avoids apiClient's 401 hard-redirect during initial auth check)

---

## Auth Header Format

```
Authorization: Bearer <backend_access_token>
```

The `<backend_access_token>` is the JWT returned by `POST /api/v1/auth/firebase`.  
It is stored in `localStorage` under the key `nitksaa_event_admin_access_token`.

The `apiClient.js` automatically attaches this header to all requests except those
with `skipAuth: true`.

---

## Token Storage Policy

| Token | Stored? | Where |
|---|---|---|
| Firebase ID token | Never | Memory only — discarded after use |
| Backend JWT | Yes | `localStorage` → `nitksaa_event_admin_access_token` |
| User summary | Yes (for offline restore) | `localStorage` → `nitksaa_event_admin_user` |

---

## Error Handling Policy

| Scenario | apiClient behaviour |
|---|---|
| Network unreachable | Throws `Error: Network error: cannot reach backend at <URL>` |
| HTTP 401 Unauthorized | `clearSession()` + `window.location.replace('/login')` |
| HTTP 403 Forbidden | `clearSession()` + `window.location.replace('/login')` |
| HTTP 4xx (other) | Throws with `detail` / `message` from response body |
| HTTP 5xx | Throws with `HTTP 5xx` message |
| Auth restore 401/network | Handled locally in `AuthProvider.restore()` — no hard redirect |

**Note:** The `POST /api/v1/auth/firebase` call uses raw `fetch` (not apiClient),
so it does NOT trigger the 401 hard-redirect. It throws instead, and LoginPage
catches the error and shows a user-friendly message.

---

## Environment Variables

| Variable | Used by |
|---|---|
| `VITE_BACKEND_BASE_URL` | `apiClient.js` (BASE_URL), `AuthProvider.jsx` |
| `VITE_FIREBASE_API_KEY` | `firebase.js` |
| `VITE_FIREBASE_AUTH_DOMAIN` | `firebase.js` |
| `VITE_FIREBASE_PROJECT_ID` | `firebase.js`, `SettingsPage.jsx` (display) |
| `VITE_FIREBASE_APP_ID` | `firebase.js` |

All variables must be prefixed with `VITE_` to be exposed to the browser by Vite.

---

## Week 2 — Event Management APIs

> All `/api/v1/events` endpoints below (except `/public/` variants) require
> `Authorization: Bearer <backend_jwt>`. In development, the backend `X-Dev-User: admin`
> middleware bypass is also accepted.

---

### POST /api/v1/events

- **Auth required:** Backend JWT (admin)
- **Purpose:** Create a new event (created as `draft`)
- **Request body:** `EventCreate` schema

```json
{
  "title": "Annual Alumni Meet 2026",
  "description": "...",
  "is_virtual": false,
  "location_text": "NITK Surathkal",
  "location_maps_url": null,
  "virtual_url": null,
  "capacity": 200,
  "start_datetime": "2026-10-01T09:00:00Z",
  "end_datetime": "2026-10-01T18:00:00Z",
  "timezone": "Asia/Kolkata",
  "registration_opens_at": null,
  "registration_closes_at": null
}
```

- **Response (HTTP 201):**

```json
{
  "status": "ok",
  "event": {
    "event_id": 27,
    "slug": "annual-alumni-meet-2026",
    "title": "Annual Alumni Meet 2026",
    "status": "draft",
    ...
  }
}
```

---

### GET /api/v1/events

- **Auth required:** Backend JWT (admin)

> **v1 correction:** This endpoint was listed as "No auth" in `event_admin_api_usage_v1.md`.
> It requires a valid backend JWT. Unauthenticated requests return `401`.

- **Purpose:** List all events (all statuses — not just published)
- **Query parameters:** `page`, `per_page`, `status`, `is_virtual`, `search`
- **Response (HTTP 200):**

```json
{
  "events": [
    {
      "event_id": 26,
      "title": "Webinar Demo",
      "status": "published",
      "registered_count": 3,
      "capacity": 100,
      "start_datetime": "2026-08-02T00:00:00Z",
      ...
    }
  ],
  "total": 5,
  "page": 1,
  "per_page": 20
}
```

- **Week 3 registration count visibility:** `registered_count` is a live count of
  registrations with `status = "registered"`. The admin portal can read this field
  from the list response to show capacity utilisation without an extra API call.

---

### GET /api/v1/events/{event_id}

- **Auth required:** Backend JWT (admin)

> **v1 correction:** The path was shown as `/api/v1/events/{slug}` in v1. The actual
> path parameter is `event_id` (integer), not `slug`.

- **Purpose:** Full event detail including admin-only fields (`virtual_url`, `created_by_firebase_uid`)
- **Response (HTTP 200):**

```json
{
  "event": {
    "event_id": 26,
    "slug": "webinar-demo",
    "title": "Webinar Demo",
    "status": "published",
    "is_virtual": true,
    "virtual_url": "https://meet.google.com/nitksaa-demo-webinar",
    "created_by_firebase_uid": "fxvOA6JInMM2OPKb3vuSV7qJwtI3",
    "registered_count": 3,
    "capacity": 100,
    ...
  }
}
```

---

### PATCH /api/v1/events/{event_id}

- **Auth required:** Backend JWT (admin)
- **Purpose:** Update editable event fields (partial update — all fields optional)

> **v1 correction:** Path parameter is `event_id` (integer), not `slug`.

- **Request body:** `EventUpdate` schema (any subset of `EventCreate` fields)

```json
{
  "title": "Updated Title",
  "capacity": 150
}
```

- **Response (HTTP 200):**

```json
{
  "status": "ok",
  "event": { "event_id": 26, "title": "Updated Title", "capacity": 150, ... }
}
```

---

### PATCH /api/v1/events/{event_id}/status

- **Auth required:** Backend JWT (admin)
- **Purpose:** Manage event lifecycle status (publish, unpublish, cancel, complete)

> There is NO `DELETE /api/v1/events/{event_id}` endpoint. Cancellation must be done
> via this status endpoint with `{"status": "cancelled"}`.

- **Request body:**

```json
{
  "status": "published"
}
```

**Supported status transitions:**

| Action | `status` value | Effect |
|---|---|---|
| Publish | `"published"` | Makes event visible in public API |
| Unpublish / return to draft | `"draft"` | Hides from public API |
| Cancel | `"cancelled"` | Soft-cancel — event is retained with `status = "cancelled"` |
| Complete | `"completed"` | Manual completion (or automated at event end) |

- **Response (HTTP 200):**

```json
{
  "status": "ok",
  "event": { "event_id": 26, "status": "cancelled", ... }
}
```

---

### GET /api/v1/events/public (Public preview — no auth)

- **Auth required:** None
- **Purpose:** Same endpoint used by the Flutter app — the admin portal may use this
  to preview what the public sees

> See `backend_api_index_v2.md §Public Events` for the full response shape.
> Note the list response: `{"events": [...], "total": N}` — not the same structure as
> the admin list response.

---

### GET /api/v1/events/public/{event_id} (Public preview — no auth)

- **Auth required:** None
- **Response:** `{"event": {...}}` — the event object is wrapped in an `event` key

> Shape difference: admin `GET /api/v1/events/{event_id}` also returns `{"event": {...}}`.
> The public detail endpoint returns the same shape but without admin-only fields.
> Always access the event as `response.event.title`, not `response.title`.

---

## Week 3 — Registration Count Visibility

The admin portal gains visibility into registration counts as a side-effect of the
Week 3 registration system.

**What is already available via Week 2 event list/detail:**

- `registered_count` — live count of active (`status = "registered"`) registrations
- `capacity` — max registrations allowed

**What is NOT yet implemented (Week 4):**

- Registration list / attendee table per event
- Search registrations by name, batch year
- CSV export of attendees
- Individual registration cancel action (admin-initiated)

See the Week 4 planned section below.

---

## Week 4 — Attendee Management APIs (Planned)

> Not yet implemented. These endpoints will return `501 Not Implemented` if called.
> Do not add frontend code for these until the backend implementation is confirmed.

### GET /api/v1/events/{event_id}/attendees (Planned)

**Planned scope:** Paginated list of registrations for an event, with alumni snapshot data.

```
GET /api/v1/events/{event_id}/attendees
Authorization: Bearer <backend_jwt>
```

Expected response shape (subject to change):

```json
{
  "event_id": 26,
  "registrations": [
    {
      "registration_id": 5,
      "registration_number": "NITKSAA-2026-000005",
      "status": "registered",
      "fullname_snapshot": "Username Alumni",
      "email_snapshot": "username2026@gmail.com",
      "batch_year_snapshot": 2026,
      "branch_snapshot": "Information Technology",
      "registered_at": "2026-06-19T09:56:44Z"
    }
  ],
  "total": 1
}
```

---

### GET /api/v1/events/{event_id}/attendees/export (Planned)

**Planned scope:** Download CSV of all registrations for the event.

```
GET /api/v1/events/{event_id}/attendees/export
Authorization: Bearer <backend_jwt>
```

Expected response: `text/csv` file download.

---

## Admin Registration Management — Not Yet Implemented

The following was listed in `event_admin_api_usage_v1.md` under "Future APIs" and remains
unimplemented. These are distinct from the generic attendee endpoints above:

| Feature | Status |
|---|---|
| Search registrations by name | Planned — Week 4 |
| Filter by batch year | Planned — Week 4 |
| Cancel individual registration (admin) | Planned — Week 4 |
| Registration dashboard summary | Planned — Week 4 |

The backend schema and database constraints are ready (registrations table exists with
`status = "registered" / "cancelled"` and snapshot fields). Only the API layer needs
to be built.

---

## v1 Corrections Summary

| v1 entry | Correction in v2 |
|---|---|
| `GET /api/v1/events` — "No auth" | Admin JWT required |
| `GET /api/v1/events/{slug}` | Path param is `event_id` (integer), not `slug` |
| `PATCH /api/v1/events/{id}/status` — "No auth"| Admin JWT required |
| `POST /api/v1/events/{id}/register` — listed as admin usage | Alumni JWT only — not an admin action |
| `GET /api/v1/events/{id}/attendees` — listed as implemented | Returns `501` — Week 4 planned |

---

*For full endpoint inventory: `docs/api/backend_api_index_v2.md`*  
*For response shapes and field-level accuracy: `docs/api/week3_actual_api_response_shapes.md`*  
*For registration eligibility rules and join link policy: `docs/api/events_api_contract_v2.md`*
