# Event Admin API Usage

Frontend: `admin/event_admin/`
Backend: shared backend at `/backend/`
API reference: `docs/api/backend_api_index.md`

---

## APIs Currently Used (Week 1)

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

- **Auth required:** Firebase ID token in request body (NOT as Authorization header)
- **Request body:**
```json
{
  "token": "<firebase_id_token>"
}
```
- **Request headers:** `Content-Type: application/json`
- **Used by:** AuthProvider `loginWithFirebaseToken()` → `authApi.exchangeFirebaseToken()`
- **Response:**
```json
{
  "status": "ok",
  "access_token": "<backend_jwt>",
  "token_type": "bearer",
  "firebase_uid": "...",
  "user_type": "alumni",
  "fullname": "NITKSAA Member",
  "ref_id": "ALUMNI123",
  "graduation_year": 2010
}
```
- **Frontend usage:**
  - `authApi.exchangeFirebaseToken(firebaseIdToken)` uses `fetch` directly (not apiClient)
    to avoid adding any stale stored JWT as Authorization header
  - On success: `setAccessToken(data.access_token)` stores JWT in localStorage
  - Firebase ID token is NOT stored anywhere after this call

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
  "firebase_uid": "...",
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

| Token              | Stored?                  | Where                              |
|--------------------|--------------------------|-------------------------------------|
| Firebase ID token  | Never                    | Memory only, discarded after use    |
| Backend JWT        | Yes                      | `localStorage` → `nitksaa_event_admin_access_token` |
| User summary       | Yes (for offline restore)| `localStorage` → `nitksaa_event_admin_user` |

---

## Error Handling Policy

| Scenario                     | apiClient behaviour                                           |
|------------------------------|---------------------------------------------------------------|
| Network unreachable          | Throws `Error: Network error: cannot reach backend at <URL>` |
| HTTP 401 Unauthorized        | `clearSession()` + `window.location.replace('/login')`        |
| HTTP 403 Forbidden           | `clearSession()` + `window.location.replace('/login')`        |
| HTTP 4xx (other)             | Throws with `detail` / `message` from response body          |
| HTTP 5xx                     | Throws with `HTTP 5xx` message                                |
| Auth restore 401/network     | Handled locally in `AuthProvider.restore()` — no hard redirect|

**Note:** The `POST /api/v1/auth/firebase` call uses raw `fetch` (not apiClient),
so it does NOT trigger the 401 hard-redirect. It throws instead, and LoginPage
catches the error and shows a user-friendly message.

---

## Environment Variables

| Variable                    | Used by                                      |
|-----------------------------|----------------------------------------------|
| `VITE_BACKEND_BASE_URL`     | `apiClient.js` (BASE_URL), `AuthProvider.jsx`|
| `VITE_FIREBASE_API_KEY`     | `firebase.js`                                |
| `VITE_FIREBASE_AUTH_DOMAIN` | `firebase.js`                                |
| `VITE_FIREBASE_PROJECT_ID`  | `firebase.js`, `SettingsPage.jsx` (display)  |
| `VITE_FIREBASE_APP_ID`      | `firebase.js`                                |

All variables must be prefixed with `VITE_` to be exposed to the browser by Vite.

---

## Future APIs Planned

### Week 2 — Event Management

| Method | Path                           | Auth            | Description             |
|--------|--------------------------------|-----------------|-------------------------|
| GET    | /api/v1/events                 | No              | List published events   |
| GET    | /api/v1/events/{slug}          | No              | Event detail            |
| POST   | /api/v1/events                 | Admin/Staff     | Create event            |
| PATCH  | /api/v1/events/{id}/status     | Admin/Staff     | Publish / unpublish     |

### Week 3 — Registrations

| Method | Path                                     | Auth         | Description             |
|--------|------------------------------------------|--------------|-------------------------|
| POST   | /api/v1/events/{id}/register             | Backend JWT  | Register attendee       |
| GET    | /api/v1/events/{id}/my-registration      | Backend JWT  | Check registration      |

### Week 4 — Attendees

| Method | Path                                     | Auth         | Description             |
|--------|------------------------------------------|--------------|-------------------------|
| GET    | /api/v1/events/{id}/attendees            | Admin/Staff  | List attendees          |
| GET    | /api/v1/events/{id}/attendees/export     | Admin/Staff  | Export CSV              |
