# Admin Event Creation — Unexpected Sign-Out: Investigation & Fix Report

**Project:** NITKSAA-EVENT
**Sprint:** Admin Event Creation + Unexpected Sign-Out Fix
**Priority:** BLOCKER
**Date:** 2026-09-07
**Status:** FIXED & VERIFIED (browser-level E2E is a scripted manual step — see §Live Browser E2E)

---

## 1. Executive Summary

An authenticated administrator could sign in and view the Dashboard, but was
**automatically signed out and redirected to `/login` the moment they invoked
almost any real admin action** — Create Event, the Events list, Registrations,
Attendees, event enrichment, etc.

The defect has two independent layers, both addressed:

| Layer | Where | Nature | Fix |
|---|---|---|---|
| **1 — the sign-out itself** | `admin/event_admin/src/api/apiClient.js` | The shared API client treated **`401 || 403` identically** — `clearSession()` + `window.location.replace('/login')`. Any `403` (ordinary RBAC / event-scope denial), and any un-recoverable `401`, destroyed a perfectly valid session. There was **no attempt to refresh** an expired backend JWT from the still-live Firebase sign-in. | Only a genuinely un-recoverable **401** clears the session now. `403/404/409/422/5xx/network` raise a **typed `ApiError`** and keep the session. On `401`, the client makes **one silent recovery attempt** (force-refresh Firebase ID token → re-exchange for a new backend JWT → replay the request once) before failing closed. |
| **2 — why a `403` happened at all** | Environment / data | The signed-in Firebase admin (`sudarshana.ashwini@gmail.com`, uid `adW99tFFnDPp10cTd2vUMfEGCxS2`) held **no `platform_admin` grant**: `PLATFORM_ADMIN_FIREBASE_UIDS` was unset in `backend/.env` and there was no `payment_platform_roles` row. Every `platform_admin`-scoped route therefore correctly returned `403 payment_role_required`. | Added the uid to `PLATFORM_ADMIN_FIREBASE_UIDS` in `backend/.env` (the designed bootstrap mechanism). **No RBAC code was changed or weakened.** |

**Backend security model is fully preserved.** No dev-auth reintroduction, no
RBAC bypass, no token-verification weakening. In fact the admin frontend no
longer sends the `X-Dev-User` header at all (it was dead weight the backend
already ignored on every admin route).

**Regression status:** backend `pytest -q` → **339 passed, 4 skipped, 0 failed**
(328 baseline + 11 new). Frontend `vitest` → **15 passed**. `eslint` → 0 errors.
`vite build` → success.

---

## 2. User-Reported Symptom

> "An authenticated administrator can log in and access Admin functionality, but
> when trying to create an event or use other admin options, the application
> signs the administrator out automatically. The issue appears broader than only
> Create Event."

Confirmed verbatim, including the "broader than Create Event" observation — it
affects **every** admin screen that calls a `platform_admin`- or
`event_admin`-scoped endpoint.

---

## 3. Repository / Architecture

| Component | Path | Tech |
|---|---|---|
| Backend API | `backend/app` | FastAPI, asyncpg/PostgreSQL (`events_db`) |
| Admin frontend | `admin/event_admin` | **React 18 + Vite 5 + react-router-dom 6**, Firebase Web SDK 10 |
| Attendee app | `apps/event_app` | Flutter (not involved) |
| `EventAdmin/` (repo sibling) | `../EventAdmin` | Throwaway Node scripts (`set-admin.js`, `verify-admin.js`) for Firebase custom claims — **not** the admin frontend, and the backend does not read Firebase custom claims for RBAC |

### Auth / session chain (admin frontend)

```
LoginPage (Firebase signInWithEmailAndPassword / signInWithPopup)
  → cred.user.getIdToken(true)                         Firebase ID token
  → AuthProvider.loginWithFirebaseToken()
  → POST /api/v1/auth/firebase        {token}          → backend HS256 JWT (access_token_expire_minutes = 480)
  → setAccessToken(jwt)  → localStorage['nitksaa_event_admin_access_token']
  → GET /api/v1/auth/me                                → AuthProvider.user  → isAuthenticated
RequireAuth  →  AdminLayout  →  pages
  every protected call: apiClient.request() → Authorization: Bearer <backend jwt>
```

### Backend admin RBAC (`app/middleware/admin_auth.py`, unchanged)

- `require_platform_role("platform_admin")` — `POST/GET /api/v1/events`,
  `POST/GET /api/v1/admin/events` (no `event_id` to scope to).
- `require_event_admin` — `/api/v1/events/{event_id}`,
  `/api/v1/events/{event_id}/status`, all `/api/v1/events/{event_id}/people|sponsors|partners`,
  all `/api/v1/admin/events/{event_id}/*`.
- Roles resolved **only** from: `settings.platform_admin_firebase_uids`
  (env bootstrap), `payment_platform_roles` table, `event_members` table.
  **Never** from request body / query / headers.

---

## 4. Environment

| Item | Value |
|---|---|
| Backend | `uvicorn app.main:app` :8000 (dev), `APP_ENV=development` |
| DB | `postgresql://ananth@localhost:5432/events_db` (reachable, 21 tables, seeded) |
| Admin frontend | `npm run dev` (Vite) :5173, `VITE_BACKEND_BASE_URL=http://localhost:8000` |
| Firebase project | `project-d22bed42-f302-4e23-8dc` |
| Test admin identity | `sudarshana.ashwini@gmail.com` / `adW99tFFnDPp10cTd2vUMfEGCxS2` (most recent real login: 2026-09-07 11:28 IST) |
| Backend Python | 3.10, `.venv`, pytest 8.2.0 |
| Node | v22.22.2, npm 10.9.7 |

Only real (non-`TEST_*`) `platform_admin` in the DB before this fix:
`6JJcpk614NSTqmlGbuZACQ2ysy22` (`ravi.test@nitksaa.dev`). The account actually
being used for admin work had no grant.

---

## 5. Pre-Fix Baseline

### BACKEND BASELINE (`cd backend && .venv/bin/python -m pytest -q`)

```
328 passed, 4 skipped, 5 warnings in 142.80s
```
- passed: 328
- failed: 0
- skipped: 4
- duration: 142.80 s

### ADMIN FRONTEND BASELINE

- framework: React 18 + Vite 5 (no test runner existed prior to this sprint)
- lint/analyze (`npm run lint`): 0 errors, 1 pre-existing warning
  (`AttendeesPage.jsx:42` unused `perPage` — untouched by this sprint)
- unit tests: **none existed**
- integration/E2E: **none existed**
- build (`npm run build`): success (78 modules, ~408 kB JS)

### ORIGINAL BUG REPRODUCED: **YES**

---

## 6. Reproduction Steps

**Environment reproduction — captured from the user's own running server** while
signed in as `sudarshana.ashwini@gmail.com`:

```
POST /api/v1/auth/firebase        200 OK      ← login works
GET  /api/v1/auth/me              200 OK      ← session established
GET  /api/v1/health              200 OK      ← Dashboard renders (only unauth call it makes)
GET  /api/v1/events?page=1&per_page=100   403 Forbidden   ← Registrations/Attendees page
GET  /api/v1/health              200 OK      ← app has hard-redirected to /login (LoginPage healthCheck)
POST /api/v1/auth/firebase        200 OK      ← user signs in again
GET  /api/v1/auth/me              200 OK
GET  /api/v1/events?page=1&per_page=20    403 Forbidden   ← Events list page
GET  /api/v1/health              200 OK      ← redirected to /login again
```

Manual UI path that triggers it:

```
Login  →  Dashboard (OK)  →  click "Events" in sidebar
  →  EventsPage mounts  →  listEvents() → GET /api/v1/events → 403
  →  apiClient: clearSession() + window.location.replace('/login')
  →  user is on the login screen, session gone
```

Create Event specifically: `Events → + Create Event → fill form → Submit →
POST /api/v1/events → 403 → signed out` (and the list page that precedes it
already signs them out for the same reason).

**Independent confirmation via a clean backend + TestClient** (`tests/test_admin_signout_regression.py`)
and via live `curl` against a fresh `uvicorn` instance — see §14 and §18.

---

## 7. Network / API Evidence

| # | Action | Method | Endpoint | Backend dep | Status (pre-fix) | Detail body | Frontend consequence (pre-fix) |
|---|---|---|---|---|---|---|---|
| 1 | Login | POST | `/api/v1/auth/firebase` | — | 200 | `{access_token…}` | session created |
| 2 | Session check | GET | `/api/v1/auth/me` | `get_current_user` | 200 | user | — |
| 3 | Dashboard health | GET | `/api/v1/health` | none | 200 | — | — |
| 4 | **Events list** | GET | `/api/v1/events?page=1&per_page=20` | `require_platform_role("platform_admin")` | **403** | `{"detail":"payment_role_required"}` | **clearSession + redirect /login** |
| 5 | **Create Event** | POST | `/api/v1/events` | `require_platform_role("platform_admin")` | **403** | `{"detail":"payment_role_required"}` | **clearSession + redirect /login** |
| 6 | Registrations/Attendees | GET | `/api/v1/events?page=1&per_page=100` | `require_platform_role("platform_admin")` | **403** | `{"detail":"payment_role_required"}` | **clearSession + redirect /login** |
| 7 | Open/Edit a specific event | GET/PATCH | `/api/v1/events/{id}` | `require_event_admin` | **403** (or 404) | `{"detail":"event_admin_required"}` | **clearSession + redirect /login** |
| 8 | Enrichment (people/sponsors/partners) | * | `/api/v1/events/{id}/…` | `require_event_admin` | **403** | `{"detail":"event_admin_required"}` | **clearSession + redirect /login** |

Redaction: no JWTs, refresh tokens, passwords, or secrets are reproduced in this
report. `curl` evidence used server-minted test JWTs only.

---

## 8. Firebase / Auth Evidence

- Firebase sign-in **succeeds** — `POST /api/v1/auth/firebase` returns `200`
  before and after the failing action; `auth.currentUser` remains populated.
- The backend JWT **is** attached (`Authorization: Bearer …`) on the failing
  calls — the failure is not "missing bearer". Confirmed: the same token returns
  `200` from `/api/v1/auth/me` immediately before the `403`.
- ID token available before request: **yes**. After request: **yes** (Firebase
  session was never touched by the backend `403`).
- Token refresh attempted (pre-fix): **no** — the frontend never called
  `getIdToken()` again after initial login; the 8-hour backend JWT was used
  until expiry, then hard logout.
- Explicit `signOut()` on the failing path (pre-fix): **no Firebase `signOut()`**,
  but `clearSession()` (localStorage wipe) + `window.location.replace('/login')`
  in `apiClient.request()` — functionally a sign-out.
- `access_token_expire_minutes = 480` (config default) — so **token expiry is
  not the trigger** for the reported deterministic case; the trigger is the
  `403`. Token expiry is a *secondary* path the same bug mishandled.

---

## 9. Logout / signOut Call-Site Audit

| File | Function | Trigger | HTTP / error condition | Expected? | Evidence / resolution |
|---|---|---|---|---|---|
| `src/api/apiClient.js` | `request()` | **`response.status === 401 || 403`** → `clearSession()` + `window.location.replace('/login')` | **any 403**, any 401 | ❌ **NO — this is the bug** | Fixed: 403 now keeps session; 401 attempts recovery first, only then clears. Redirect guarded against `/login` loop. |
| `src/auth/AuthProvider.jsx` | `restore()` (mount) | `!response.ok` from `GET /auth/me` → `clearSession()` | 401 on reload with expired backend JWT | ⚠️ partial — dropped session on reload despite live Firebase | Fixed: attempts `refreshBackendToken()` and re-checks `/auth/me` before clearing. |
| `src/auth/AuthProvider.jsx` | `logout()` | user clicks **Logout** | explicit user action | ✅ yes | unchanged |
| `src/pages/SettingsPage.jsx` | `handleLogout()` / `handleClearSession()` | explicit **Logout** / **Clear Local Session** buttons | explicit user action | ✅ yes | unchanged |
| `src/auth/RequireAuth.jsx` | route guard | `!isAuthenticated` after `isLoading` resolves | genuine unauthenticated state only | ✅ yes | unchanged — never redirects while `isLoading`; only reacts to `AuthProvider` state, which the `403` no longer disturbs |
| `src/api/attendeesApi.js` | `exportAttendeesCSV()` (manual fetch) | `!response.ok` → `throw` | any | ✅ yes | never called `clearSession()`; only removed the `X-Dev-User` header |

**No `if (any error) signOut()` / `catch(Exception) clear session` pattern
remains.** The single offending condition was the `|| 403` in `apiClient.js`.

---

## 10. API Interceptor Audit

`apiClient.js` `request()` is the one central interceptor for every JSON admin
call. Post-fix behaviour:

| Condition | Session | UX signal (typed `ApiError.category`) |
|---|---|---|
| 2xx | kept | resolves with body |
| **401**, recoverable via Firebase | **kept** | silent: refresh + replay once, resolves |
| **401**, un-recoverable | **cleared** + redirect `/login` (once) | `category:'auth'` |
| **403** | **kept** | `category:'forbidden'` — "You do not have permission…" |
| **404** | **kept** | `category:'not_found'` |
| **409** | **kept** | `category:'conflict'` |
| **422** | **kept** | `category:'validation'` (+ backend field detail) |
| **5xx** | **kept** | `category:'server'` |
| network / transport | **kept** | `category:'network'` |
| other non-OK | **kept** | `category:'error'` |

`ApiError extends Error`, so existing `catch (err) { setApiError(err.message) }`
call sites keep working unchanged.

Concurrency: concurrent `401`s share a single in-flight refresh
(`refreshInFlight` promise) — no refresh storm, no double replay.

---

## 11. Route Guard Audit

`src/auth/RequireAuth.jsx`:

```
if (isLoading)          return <LoadingView … />        // NOT a redirect
if (!isAuthenticated)   return <Navigate to="/login" replace />
return <Outlet />
```

| Situation | Behaviour | Correct? |
|---|---|---|
| Firebase auth loading | shows `LoadingView`, no redirect | ✅ |
| backend token refreshing | `isAuthenticated` stays true (user object untouched) | ✅ |
| transient API failure (`403/404/409/422/5xx/network`) | `AuthProvider.user` untouched → guard does nothing | ✅ (was ❌ via `apiClient` side-effect, now fixed at source) |
| genuine un-recoverable 401 | `apiClient` clears session + redirects; guard would also redirect on next render | ✅ fail-closed |
| redirect loop | `redirectToLogin()` no-ops when `pathname === '/login'`; `RequireAuth` uses `replace` | ✅ no loop (test: *redirect loop guard*) |

---

## 12. RBAC Audit

**No backend RBAC change.** Verified current policy from source
(`app/api/events.py`, `app/api/admin_events.py`, `app/api/people.py`,
`app/api/sponsors_partners.py`, `app/middleware/admin_auth.py`):

| Operation | Endpoint | Required role |
|---|---|---|
| Create event | `POST /api/v1/events`, `POST /api/v1/admin/events` | `platform_admin` |
| List all events (admin) | `GET /api/v1/events`, `GET /api/v1/admin/events` | `platform_admin` |
| Get / edit / status / publish / close event | `/api/v1/events/{id}`, `/api/v1/events/{id}/status`, `/api/v1/admin/events/{id}/publish|close` | `platform_admin` **or** `event_admin` for that `event_id` |
| Sessions | `POST /api/v1/admin/events/{id}/sessions` | `platform_admin` or event's `event_admin` |
| People / Sponsors / Partners | `/api/v1/events/{id}/{people|sponsors|partners}…` | `platform_admin` or event's `event_admin` |
| Attendees / registrations / check-in admin | `/api/v1/admin/events/{id}/…` | `platform_admin` or event's `event_admin` |
| Payment config (read) | `/api/v1/admin/events/{id}/payment-config` (GET) | `platform_admin`/`finance_operator`/`auditor`/`support` (platform-wide) or event's `event_admin` |
| Payment config (mutate) | same (PUT/POST) | `platform_admin` or event's `event_admin` |

Test admin's **actual** role, pre-fix: **none** (not `platform_admin`,
`event_admin`, `finance_operator`, `auditor`, or `support`). Post-fix:
`platform_admin` via `PLATFORM_ADMIN_FIREBASE_UIDS` bootstrap.

`finance_operator` / `auditor` / `support` remain **unable** to reach
event-management routes (`require_event_admin` deliberately excludes them) —
re-verified by `tests/test_admin_rbac.py` and `tests/test_admin_auth_unification.py`
(both green).

---

## 13. Event API Contract Audit

Frontend `EventFormPage.buildPayload()` vs backend `app/schemas/event_create.EventCreate`:

| Field | Frontend sends | Backend schema | Match |
|---|---|---|---|
| `title` | trimmed str | `str` 1–255 required | ✅ |
| `tagline` / `description` | str \| null | `Optional[str]` | ✅ |
| `start_datetime` / `end_datetime` | ISO `…:00+05:30` (offset from tz table) | `datetime` required | ✅ |
| `timezone` | IANA str | `str` ≤60, default `Asia/Kolkata` | ✅ |
| `is_virtual` | bool | `bool` | ✅ |
| `location_text` | str\|null (null when virtual) | `Optional[str]`; required-if-physical via `model_validator` | ✅ |
| `virtual_url` | str\|null (null when physical) | `Optional[str]`; required-if-virtual | ✅ |
| `capacity` | `parseInt` \| null | `Optional[int] gt=0` | ✅ |
| `show_attendee_list`, `is_full_day`, `is_free` | bool | bool | ✅ |
| `registration_opens_at` / `registration_closes_at` | ISO \| null | `Optional[datetime]` | ✅ |
| `thumbnail_url` / `banner_url` | str \| null | `Optional[str]` | ✅ |
| `ticket_price` | `parseFloat` \| null | `Optional[Decimal] ge=0`; required-if-paid | ✅ |
| `location_maps_url` | *not sent* | `Optional[str]` | ✅ (optional) |

**No schema drift.** `EventCreate` is not `extra="forbid"`, so unknown keys would
be ignored anyway. A malformed create returns a normal **422 with field-level
`detail`** (verified live) — which the fixed frontend surfaces as a validation
error **without** signing out.

---

## 14. Root Cause

**Proven, with runtime evidence (user's server logs + TestClient + live curl):**

1. **Primary (frontend defect).** `admin/event_admin/src/api/apiClient.js`,
   `request()`:

   ```js
   if (response.status === 401 || response.status === 403) {
     clearSession();
     window.location.replace('/login');
     throw new Error('Session expired. Please log in again.');
   }
   ```

   A `403 Forbidden` (authenticated, but not authorized for this
   role/event-scope) is **not** an authentication failure. Collapsing it into
   the `401` branch destroys a valid session. The same block also made every
   `401` a permanent logout with **no refresh/recovery attempt**, despite a
   live Firebase session capable of minting a fresh backend JWT.

2. **Secondary (provisioning gap) — why the `403` fired.** The Firebase account
   in use had no `platform_admin` grant. `settings.platform_admin_firebase_uids`
   was empty (`PLATFORM_ADMIN_FIREBASE_UIDS` unset in `backend/.env`) and there
   was no active `payment_platform_roles` row for the uid, so
   `require_platform_role("platform_admin")` correctly raised
   `403 payment_role_required` on `POST/GET /api/v1/events` — and
   `require_event_admin` correctly raised `403 event_admin_required` on every
   `/events/{id}` route.

The user's experience = (2) generates the `403`, (1) converts it into a
sign-out, on *every* admin screen.

---

## 15. Fix Implemented

### A. `admin/event_admin/src/api/apiClient.js` — rewritten `request()`

- New exported **`class ApiError extends Error`** with `status`, `category`
  (`auth|forbidden|not_found|conflict|validation|server|network|error`),
  `detail`.
- **401 path:** if `!skipAuth` and not already retried → `await
  refreshBackendToken()` (force-refresh Firebase ID token → `POST
  /api/v1/auth/firebase` → `setAccessToken`) → **replay the original request
  once** with the new bearer. Only if recovery yields no token →
  `clearSession()` + `redirectToLogin()` + `throw ApiError(category:'auth')`.
- **403 / 404 / 409 / 422 / 5xx / any other non-OK:** `throw ApiError` with the
  right `category` and the backend `detail`. **Session untouched. No redirect.**
- **Network/transport throw:** `throw ApiError(category:'network')`. Session
  untouched.
- `refreshBackendToken()` exported; concurrent callers share one in-flight
  promise (`refreshInFlight`).
- `redirectToLogin()` no-ops when already on `/login` (loop guard).
- **Removed** the `X-Dev-User` request header (`import.meta.env.VITE_DEV_USER`)
  entirely — the backend admin RBAC never read it; it was a latent violation of
  the "no dev-auth headers" rule.

### B. `admin/event_admin/src/auth/AuthProvider.jsx` — `restore()`

- On `401` from `GET /api/v1/auth/me` during mount, call
  `refreshBackendToken()` and re-check `/auth/me` with the fresh token before
  `clearSession()`. Prevents a reload from ending a session that Firebase can
  still vouch for. Also persists the refreshed user via `setStoredUser`.

### C. `admin/event_admin/src/api/attendeesApi.js`

- Removed the `X-Dev-User` header from the manual CSV-export `fetch`.

### D. `admin/event_admin/.env` & `.env.example`

- Removed `VITE_DEV_USER=admin` and its comment block; replaced with a note that
  admin RBAC is granted server-side.

### E. `backend/.env` (git-ignored local config — not a code change)

- `PLATFORM_ADMIN_FIREBASE_UIDS=adW99tFFnDPp10cTd2vUMfEGCxS2`
  (`sudarshana.ashwini@gmail.com`) — the designed bootstrap mechanism.
  **No RBAC source code touched.**

### F. Test infrastructure (new)

- `admin/event_admin/` gains `vitest` + `jsdom` (devDeps), `vitest.config.js`,
  `npm test` script.

---

## 16. Files Changed

| File | Type | Change |
|---|---|---|
| `admin/event_admin/src/api/apiClient.js` | **prod** | `request()` rewrite: 401-only fail-closed w/ silent Firebase recovery + replay; typed `ApiError`; keep session on 403/404/409/422/5xx/network; redirect loop guard; drop `X-Dev-User` |
| `admin/event_admin/src/auth/AuthProvider.jsx` | **prod** | `restore()`: refresh-and-recheck before clearing session on reload |
| `admin/event_admin/src/api/attendeesApi.js` | **prod** | drop `X-Dev-User` header from CSV export fetch |
| `admin/event_admin/src/pages/EventFormPage.jsx` | **prod** | `friendlySaveError()` — render a plain-language message ("…you are still signed in") for `forbidden`/`network`/`server`/`conflict` instead of the raw backend slug; validation still shows the field `detail` |
| `admin/event_admin/.env`, `.env.example` | config | remove `VITE_DEV_USER` |
| `backend/.env` | local config (git-ignored) | add `PLATFORM_ADMIN_FIREBASE_UIDS` bootstrap entry |
| `admin/event_admin/src/api/apiClient.test.js` | **new test** | 14 session-preservation / recovery tests |
| `admin/event_admin/vitest.config.js` | **new** | jsdom test env |
| `admin/event_admin/package.json`, `package-lock.json` | build | `vitest`, `jsdom` devDeps; `test` script |
| `backend/tests/test_admin_signout_regression.py` | **new test** | 11 backend RBAC-status-contract tests |
| `docs/admin/ADMIN_EVENT_UNEXPECTED_SIGNOUT_FIX_REPORT.md` | doc | this report |

**No backend application code (`backend/app/**`) was modified.**

---

## 17. Tests Added / Changed

### Frontend — `admin/event_admin/src/api/apiClient.test.js` (vitest, 15 tests, all green)

- successful request → resolves, session kept, no redirect
- **403, 404, 409, 422, 500, 503** (parametrized) → typed `ApiError`, token
  still in `localStorage`, `location.replace` **not** called, **no retry**
- network failure → `ApiError(category:'network')`, session kept
- 401 + no Firebase user → session cleared, `replace('/login')` once,
  `ApiError(category:'auth')`
- 401 + live Firebase user + successful exchange → refresh, **replay**, resolves
  with new data, new JWT stored, replayed call carries `Bearer new.backend.jwt`
- 401 + Firebase exchange fails (`401`) → fail closed (session cleared, redirect)
- 401 + replayed request still 401 → **no loop**: exactly 3 fetches
  (original + exchange + one replay), one redirect
- redirect loop guard: already on `/login` → session cleared but
  `location.replace` not called
- `skipAuth` 401 → no Firebase recovery, no session clear, no redirect

### Backend — `backend/tests/test_admin_signout_regression.py` (pytest, 11 tests, all green)

- authenticated **non-admin** → `POST /api/v1/events`, `GET /api/v1/events`,
  `POST /api/v1/admin/events`, `GET /api/v1/admin/events` all **403**
  (`payment_role_required`), **never 401**
- event-scoped denial for authenticated non-admin → **403**
  (`event_admin_required`)
- missing bearer → rejected (401/403), no token leak
- invalid bearer → **401** `invalid_or_expired_token`
- expired bearer → **401** `invalid_or_expired_token`
- role injection via header (`X-Dev-User`, `X-Dev-Role`, `X-Role`) + body
  (`role`, `user_type`) + query (`?role=platform_admin`) → **403**, cannot elevate
- provisioned `platform_admin` → create → read → update → publish all **2xx**,
  no 401/403 anywhere in the chain
- malformed create as authorized admin → **422** (not 401/403)

---

## 18. Admin Operation Verification Matrix

Executed live via `curl` against a fresh `uvicorn` (`:8100`) with
`PLATFORM_ADMIN_FIREBASE_UIDS=adW99tFFnDPp10cTd2vUMfEGCxS2`, using a
server-minted backend JWT for that uid (identical to what
`POST /api/v1/auth/firebase` mints after the Firebase popup). Non-admin =
`sudarshana.karkala@gmail.com` (`R6rnLD2HLlPeXiWGGtqxA7TdWl53`, no role).

| Admin Operation | Endpoint | Required role | Before fix | After fix | Session retained (after fix) |
|---|---|---|---|---|---|
| Session check | `GET /api/v1/auth/me` | any authed | 200 | **200** | ✅ |
| List Events | `GET /api/v1/events` | platform_admin | 403 → **logout** | **200** | ✅ |
| Create Event | `POST /api/v1/events` | platform_admin | 403 → **logout** | **201** (event 15762, `status:draft`, `created_by=adW99…`) | ✅ |
| View Event | `GET /api/v1/events/15762` | platform_admin/event_admin | 403 → **logout** | **200** | ✅ |
| Edit Event | `PATCH /api/v1/events/15762` | platform_admin/event_admin | 403 → **logout** | **200** | ✅ |
| Publish Event | `PATCH /api/v1/events/15762/status {published}` | platform_admin/event_admin | 403 → **logout** | **200** | ✅ |
| Close/Cancel Event | `PATCH …/status {cancelled}` | platform_admin/event_admin | 403 → **logout** | **200** (cleanup of test event) | ✅ |
| Sessions | `POST /api/v1/admin/events/{id}/sessions` | platform_admin/event_admin | 403 → logout | RBAC passes (covered by `test_admin_rbac.py`) | ✅ |
| People / Sponsors / Partners | `/api/v1/events/{id}/…` | platform_admin/event_admin | 403 → logout | RBAC passes (`test_admin_auth_unification.py`) | ✅ |
| Check-In admin | `/api/v1/admin/events/{id}/check-ins` | platform_admin/event_admin | 403 → logout | RBAC passes (`test_admin_rbac.py`) | ✅ |
| Payment Admin / Config | `/api/v1/admin/events/{id}/payment-config…` | see §12 | 403 → logout | RBAC unchanged (`test_payment_rbac.py`, `test_payment_admin_config.py`) | ✅ |
| **Negative:** non-admin Create | `POST /api/v1/events` | — | 403 → **logout** | **403** `payment_role_required` → **stays logged in**, "no permission" UX | ✅ |
| **Negative:** malformed Create (admin) | `POST /api/v1/events` | platform_admin | n/a | **422** field errors → **stays logged in** | ✅ |
| **Negative:** missing event (admin) | `GET /api/v1/events/999999999` | platform_admin | n/a | **404** `event_not_found` → **stays logged in** | ✅ |
| **Negative:** invalid JWT | `GET /api/v1/events` | — | 401/403 → logout | **401** → silent Firebase refresh + replay; logout only if unrecoverable | ✅ / fail-closed |

---

## 19. Live Browser E2E

**Status: PARTIAL (scripted, not executed here).** A real browser + Firebase
Google popup + Vite dev server cannot be driven from this headless environment.
The equivalent **full HTTP stack** (real FastAPI, real Postgres, real RBAC, real
`EventsService`/`EventsRepository`) was exercised end-to-end via `curl` (§18) and
the frontend session logic is covered by vitest (§17).

Manual procedure for the user (all steps must keep the **same** Firebase session):

1. `cd backend && source .venv/bin/activate && python -m uvicorn app.main:app --reload`
   — **restart** so the new `PLATFORM_ADMIN_FIREBASE_UIDS` in `.env` is read
   (uvicorn `--reload` does not watch `.env`; `get_settings()` is `lru_cache`d).
2. `cd admin/event_admin && npm install && npm run dev` (picks up the new
   `apiClient.js`; `.env` no longer sets `VITE_DEV_USER`).
3. Browser → `http://localhost:5173` → sign in as `sudarshana.ashwini@gmail.com`.
4. Dashboard → **Events** → list loads (was: instant logout).
5. **+ Create Event** → fill → **Create Event** → redirects to the new event's
   edit page (was: logout).
6. Edit a field → **Update Event** → back to list, still signed in.
7. On the list, **Publish** the draft → confirm → toast, still signed in.
8. Navigate **Registrations** → **Attendees** → **Settings** → back to
   **Events** — Firebase session still active throughout.
9. Negative checks, still signed in each time:
   - submit Create with a blank title / bad date → inline **422** validation, no logout;
   - sign in with a second account that has **no** role → any admin screen shows
     **"You do not have permission…"**, **not** a logout;
   - stop the backend, click Refresh → **network error** message, **not** a logout.

---

## 20. Backend Regression

`cd backend && .venv/bin/python -m pytest -q`

```
Baseline : 328 passed, 4 skipped, 0 failed  (142.80s)
Post-fix : 339 passed, 4 skipped, 0 failed  (142.92s)   ← +11 new (test_admin_signout_regression.py)
```

**0 failures. No test deleted or weakened.** PASS.

---

## 21. Frontend Regression

| Check | Command | Result |
|---|---|---|
| Lint | `npm run lint` | 0 errors, 1 **pre-existing** warning (`AttendeesPage.jsx:42`, untouched) |
| Unit tests | `npm test` (`vitest run`) | **15 passed** (1 file) |
| Build | `npm run build` | success (78 modules, 408.02 kB JS / 105.54 kB gzip) |
| Integration / E2E | — | none in repo; see §19 for the manual browser script |

PASS (no new failures).

---

## 22. Payment Regression

Included in the `pytest -q` = **339 passed**. Explicitly:

| Suite | Status |
|---|---|
| `tests/test_payments.py` | PASS |
| `tests/test_payment_rbac.py` | PASS |
| `tests/test_payment_scheduler.py` | PASS |
| `tests/test_payment_admin_config.py` | PASS |
| `tests/test_payment_gateway_foundation.py` | PASS |
| `tests/test_payment_lifecycle_expiry.py` | PASS |
| `tests/test_payment_webhook_freshness.py` | PASS |

Admin auth/RBAC is shared with payment administration; no payment behaviour
changed (no backend code changed). PASS.

---

## 23. Security Verification

| Check | Result | Evidence |
|---|---|---|
| Missing JWT denied | ✅ | `test_missing_bearer_is_rejected` (401/403, no token leak) |
| Invalid JWT denied | ✅ | `test_invalid_bearer_is_401` + live curl → `401 invalid_or_expired_token` |
| Expired / revoked token handled safely | ✅ | `test_expired_bearer_is_401`; frontend: silent refresh, else fail-closed (`apiClient.test.js`) |
| `X-Dev-User` cannot authenticate | ✅ | not sent by frontend anymore; backend admin routes never read it; `test_role_injection_*` |
| `X-Dev-Role` cannot elevate | ✅ | `test_role_injection_via_headers_body_query_cannot_elevate` → 403 |
| role in JSON body cannot elevate | ✅ | same test (`"role":"platform_admin"` in body) → 403 |
| role in query string cannot elevate | ✅ | same test (`?role=platform_admin`) → 403 |
| role in headers cannot elevate | ✅ | same test (`X-Role`, `X-Dev-Role`) → 403 |
| `event_admin` cannot administer unauthorized event | ✅ | `test_admin_rbac.py`, `test_admin_auth_unification.py` (unchanged, green) |
| finance/auditor/support cannot gain event-admin | ✅ | `require_event_admin` excludes them; `test_admin_rbac.py` green |
| No secret / token leakage in errors, logs, diagnostics | ✅ | `ApiError` carries only backend `detail` strings (`payment_role_required`, `event_not_found`, field names); no JWT/secret in any body or this report |
| No unsafe CORS workaround | ✅ | CORS untouched; `allow_origins` = explicit list (`:5173`, `:5200`); preflights returned `200` in repro |
| Valid auth state not corrupted by API errors | ✅ | 403/404/409/422/5xx/network keep session (`apiClient.test.js`) |

No dev-auth fallback reintroduced. No RBAC weakened. PASS.

---

## 24. Concurrency Regression

No backend code changed → event-lifecycle concurrency guarantees intact.
Re-verified green:

- `tests/test_admin_event_verification_closure.py` — atomic status transitions,
  exactly-one successful transition under contention, no duplicate success audit
  side-effects.
- `tests/test_admin_event_management.py` — event lifecycle.
- `tests/test_event_flow.py` — check-in uniqueness / registration flow.

Frontend: concurrent `401`s now share one in-flight refresh
(`refreshInFlight`) — verified by `apiClient.test.js` (single exchange call).
PASS.

---

## 25. Verification Acceptance Criteria

| # | Criterion | Grade |
|---|---|---|
| 1 | Original automatic-sign-out bug reproduced before fix | **PASS** |
| 2 | Exact failing action identified | **PASS** (any `platform_admin`/`event_admin` call; first hit is usually the Events list, then Create Event) |
| 3 | Exact API status/error that triggers logout identified | **PASS** (`403`, `payment_role_required` / `event_admin_required`; and un-recovered `401`) |
| 4 | Root cause proven | **PASS** (§14, runtime evidence) |
| 5 | All logout/signOut call sites inventoried | **PASS** (§9) |
| 6 | API interceptor behaviour audited | **PASS** (§10) |
| 7 | Route guard behaviour audited | **PASS** (§11) |
| 8 | Firebase auth-state lifecycle audited | **PASS** (§8) |
| 9 | Bearer-token attachment verified | **PASS** (§8) |
| 10 | Token refresh verified | **PASS** (added + tested; §15A, §17) |
| 11 | Role / custom-claim behaviour verified | **PASS** (backend ignores Firebase custom claims; roles from settings/DB; §12) |
| 12 | Create Event API contract verified | **PASS** (§13, no drift) |
| 13 | CORS / preflight verified | **PASS** (explicit origin list; preflights 200) |
| 14 | Authorized admin can create an event | **PASS** (live 201; §18) |
| 15 | Created event can be read | **PASS** (live 200) |
| 16 | Event can be edited | **PASS** (live 200) |
| 17 | Event can be published | **PASS** (live 200) |
| 18 | Other admin modules tested | **PASS** (RBAC suites green; matrix §18) |
| 19 | Successful admin action does not sign out | **PASS** (`apiClient.test.js`) |
| 20 | 403 does not sign out | **PASS** |
| 21 | 404 does not sign out | **PASS** |
| 22 | 409 does not sign out | **PASS** |
| 23 | 422 does not sign out | **PASS** |
| 24 | 5xx does not sign out | **PASS** |
| 25 | Network failure does not sign out | **PASS** |
| 26 | Genuinely invalid auth remains fail-closed | **PASS** (401 → recover-or-logout) |
| 27 | No dev-auth fallback | **PASS** (`X-Dev-User` removed from frontend; backend unchanged) |
| 28 | No RBAC weakening | **PASS** (zero backend code change) |
| 29 | Privilege-injection tests pass | **PASS** (§23) |
| 30 | Cross-event scope protected | **PASS** (`require_event_admin` unchanged; tests green) |
| 31 | Event lifecycle concurrency protected | **PASS** (§24) |
| 32 | Live browser E2E passes | **PARTIAL** (HTTP-stack E2E executed; browser-popup E2E scripted for the user — §19) |
| 33 | Backend regression passes | **PASS** (339/0) |
| 34 | Frontend regression passes | **PASS** (14/0, lint, build) |
| 35 | Payment/security/scheduler regression passes | **PASS** (§22) |
| 36 | No token/secret leakage | **PASS** (§23) |
| 37 | RGIS complete | **PASS** (§27) |
| 38 | DoD complete | **PASS** (§28) |
| 39 | Verification report created | **PASS** (this file) |

---

## 26. RGIS

### R — Reliability — **PASS**
- Admin login stable (`POST /auth/firebase` 200 across repeated repro cycles).
- Create/read/edit/publish work repeatedly (live curl; backend lifecycle test).
- Transient API failures (`403/404/409/422/5xx/network`) no longer destroy auth —
  6 parametrized + 2 dedicated vitest cases.
- Token refresh reliable and non-looping: force-refresh → exchange → single
  replay; shared in-flight promise; loop guard test green.

### G — Governance — **PASS**
- Correct roles enforced, unchanged (`admin_auth.py` untouched); policy table §12.
- Event scope enforced (`require_event_admin`); cross-event denial test green.
- No dev-auth fallback — `X-Dev-User` removed from the client; backend admin
  routes never consumed it.
- Audit preserved — `EventsService` still emits `event_created/updated/published/…`;
  `test_admin_auth_unification.py` audit assertions green.
- Denied roles remain denied — non-admin & finance/auditor/support → 403, verified.

### I — Integration — **PASS**
Real chain exercised end to end (live `curl`, fresh uvicorn, real DB):
`backend JWT (= /auth/firebase output) → Authorization: Bearer → app.middleware.auth.get_current_user
→ admin_auth.require_platform_role / require_event_admin → EventsService → EventsRepository
→ PostgreSQL events_db → JSON response → (fixed) apiClient → page`.
Create returned a real row (`event_id 15762`, `created_by_firebase_uid=adW99…`,
`created_by_name="Ashwini Sudarshana"` resolved from `event_users`).

### S — Security — **PASS**
- Invalid / missing / expired identity → fail-closed (401 → recover-or-logout).
- No role injection via header / body / query (test green).
- No dev-header bypass (removed client-side; ignored server-side).
- No cross-event privilege (scope check unchanged).
- No token leakage (errors carry only backend `detail` slugs).
- No unsafe CORS workaround (explicit origins; unchanged).
- API errors do not corrupt valid auth state (session-preservation tests).
- Concurrency protection retained (no backend change; suites green).

**Sprint closure gate: R=PASS, G=PASS, I=PASS, S=PASS → satisfied.**

---

## 27. Definition of Done

| Item | Grade |
|---|---|
| repository / admin architecture audited | **PASS** |
| baseline reproduced | **PASS** (328/0) |
| sign-out issue reproduced | **PASS** |
| root cause proven | **PASS** |
| smallest safe fix implemented | **PASS** (1 core function + 1 mount effect + header removal; no backend code) |
| logout call sites audited | **PASS** |
| API error semantics fixed / verified | **PASS** |
| Firebase lifecycle verified | **PASS** |
| RBAC preserved | **PASS** |
| Create Event contract aligned | **PASS** (already aligned) |
| Create Event live-tested | **PASS** (201) |
| read / edit / publish live-tested | **PASS** (200/200/200) |
| admin operation matrix tested | **PASS** (§18) |
| 403/404/409/422/5xx/network behaviour tested | **PASS** |
| genuine invalid auth fails closed | **PASS** |
| frontend regression green | **PASS** |
| backend regression green | **PASS** (339/0) |
| payment regression green | **PASS** |
| security regression green | **PASS** |
| concurrency regression green | **PASS** |
| no secrets exposed | **PASS** |
| RGIS all PASS | **PASS** |
| verification report created | **PASS** |

---

## 28. Known Limitations

1. **Browser-popup E2E not executed here** — no headless browser / Firebase
   Google-popup capability in this environment. Compensated by full HTTP-stack
   `curl` E2E + vitest coverage of the frontend session logic. Manual script in §19.
2. **`backend/.env` change requires a server restart** — `uvicorn --reload` does
   not watch `.env` and `get_settings()` is `lru_cache`d. The user's currently
   running instance will keep returning `403` until restarted.
3. **`admin/event_admin` gained `vitest` + `jsdom` devDependencies.** `npm audit`
   reports pre-existing advisories in the transitive dev tree (not shipped to
   production; `vite build` output unaffected).
4. **Provisioning is per-identity.** Any *other* Firebase account used for admin
   work still needs a `platform_admin` (or event-scoped `event_admin`) grant —
   otherwise it will now see a clean "no permission" message instead of a logout,
   but still cannot manage events.
5. `AttendeesPage.jsx:42` unused-var lint warning is pre-existing and untouched.

---

## 29. Remaining Blockers

**None for the sign-out defect.** The fix is complete and verified at the API +
unit level.

Operational follow-up (not a code blocker): restart the dev backend so the
bootstrap grant loads, then run the §19 browser script to close criterion #32
from PARTIAL → PASS.

---

## 30. Exactly One Recommended Next Step

**Restart the dev backend (`Ctrl-C` the running `uvicorn`, start it again) so
`PLATFORM_ADMIN_FIREBASE_UIDS` loads, then run the §19 browser E2E script once as
`sudarshana.ashwini@gmail.com` to confirm Create → Edit → Publish → cross-module
navigation all keep the same Firebase session.**
