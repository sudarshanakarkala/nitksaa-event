# Flutter Event App Reference from Existing NITKSAA Products

This document reviews `nitksaa-portal-v2` and `nitksaa-website` as source material for a separate Flutter Event App. It is a reuse reference for identity, API, database, UI, admin, and deployment patterns. It is not a proposal to merge Flutter into the website.

## Product Boundary

- The Event App is a separate Flutter app.
- Do not merge the Flutter app into `nitksaa-website`.
- Do not create a new identity system.
- Do not create a new Firebase project.
- Do not create a new global role model unless event requirements cannot be satisfied by existing roles plus narrow event-scoped permissions.
- Keep alumni identity anchored to Firebase UID plus `alumni_db.alumni.alumni_id` / website `ref_id`.

## Exact Files Reviewed

### `nitksaa-portal-v2`

- `.firebaserc`
- `.gcloudignore`
- `Dockerfile`
- `README.md`
- `DESIGN_DOC.md`
- `firebase.json`
- `docs/nitksaa-portal-v2_existing_system_review.md`
- `docs/nitksaa-portal-v2_event_app_reference_from_existing_products.md`
- `webapp/backend/config.py`
- `webapp/backend/database.py`
- `webapp/backend/dependencies.py`
- `webapp/backend/main.py`
- `webapp/backend/models.py`
- `webapp/backend/routers/admin.py`
- `webapp/backend/routers/alumni.py`
- `webapp/backend/routers/auth_v1.py`
- `webapp/backend/routers/me.py`
- `webapp/backend/routers/registration.py`
- `webapp/frontend/src/api.js`
- `webapp/frontend/src/firebase.js`
- `webapp/frontend/src/context/AppContext.jsx`
- `webapp/frontend/src/components/Navbar.jsx`
- `webapp/frontend/src/pages/Login.jsx`
- `webapp/frontend/src/pages/AdminUsers.jsx`
- `webapp/frontend/src/pages/AuditLog.jsx`
- `webapp/frontend/src/pages/RegistrationReview.jsx`
- `webapp/frontend/src/styles/admin.css`
- `webapp/frontend/src/styles/dashboard.css`
- `webapp/frontend/src/styles/global.css`
- `webapp/frontend/src/styles/nav.css`

### `nitksaa-website`

- `.gcloudignore`
- `Dockerfile`
- `README.md`
- `docs/nitksaa-website-existing_system_review.md`
- `backend/server.py`
- `backend/src/api/alumni_directory.py`
- `backend/src/api/auth.py`
- `backend/src/api/health.py`
- `backend/src/config/settings.py`
- `backend/src/config/tenant_config.py`
- `backend/src/config/tenants.yaml`
- `backend/src/middleware/firebase.py`
- `backend/src/middleware/tenant.py`
- `backend/src/services/alumni.py`
- `backend/src/services/db.py`
- `frontend/.env.production`
- `frontend/src/api.js`
- `frontend/src/firebase.js`
- `frontend/src/App.jsx`
- `frontend/src/components/Navbar.jsx`
- `frontend/src/components/alumni/AlumniFilterSidebar.jsx`
- `frontend/src/components/alumni/AlumniMapView.jsx`
- `frontend/src/components/alumni/AlumniSearchBar.jsx`
- `frontend/src/components/alumni/ViewToggle.jsx`
- `frontend/src/components/core/EntityCard.jsx`
- `frontend/src/components/core/EntityCollection.jsx`
- `frontend/src/components/core/FilterSidebar.jsx`
- `frontend/src/components/core/PageHeader.jsx`
- `frontend/src/hooks/useFilters.js`
- `frontend/src/pages/DirectoryPage.jsx`
- `frontend/src/pages/Login.jsx`
- `frontend/src/pages/StoriesPage.jsx`
- `frontend/src/styles/entity-card.css`
- `frontend/src/styles/entity-collection.css`
- `frontend/src/styles/filter-sidebar.css`
- `frontend/src/styles/global.css`
- `frontend/src/styles/navbar.css`
- `frontend/src/styles/tokens.css`

## 1. Firebase Project Details

Both existing products use the same Firebase project:

- Project ID: `project-d22bed42-f302-4e23-8dc`
- Firebase Hosting default project in portal `.firebaserc`: `project-d22bed42-f302-4e23-8dc`
- Portal backend default `FIREBASE_PROJECT_ID`: `project-d22bed42-f302-4e23-8dc`
- Website tenant Firebase project in `backend/src/config/tenants.yaml`: `project-d22bed42-f302-4e23-8dc`
- Website production Firebase web app config:
  - `VITE_FIREBASE_AUTH_DOMAIN=project-d22bed42-f302-4e23-8dc.firebaseapp.com`
  - `VITE_FIREBASE_PROJECT_ID=project-d22bed42-f302-4e23-8dc`
  - `VITE_FIREBASE_STORAGE_BUCKET=project-d22bed42-f302-4e23-8dc.firebasestorage.app`
  - `VITE_FIREBASE_MESSAGING_SENDER_ID=246773894709`
  - `VITE_FIREBASE_APP_ID=1:246773894709:web:c4d4d005ec66432a33ab7c`

Backend Firebase verification uses Firebase Admin SDK with Application Default Credentials:

- Local development: `gcloud auth application-default login`
- Cloud Run: service account ADC

Flutter implementation should configure Firebase against this same project. Flutter should obtain Firebase ID tokens through Firebase Auth, then exchange those tokens with the Event backend for an internal JWT. Flutter should not call Firebase Admin SDK and should not introduce a second Firebase project.

## 2. Auth/JWT Flow

### Portal Alumni Flow

Source files: `webapp/backend/routers/auth_v1.py`, `webapp/backend/dependencies.py`, `webapp/frontend/src/firebase.js`, `webapp/frontend/src/api.js`, `webapp/frontend/src/pages/Login.jsx`.

1. User signs in through Firebase Google OAuth or email magic link.
2. Client receives a Firebase ID token.
3. Client posts to `POST /api/v1/auth/alumni/firebase` as `{ "firebase_token": "<token>" }`.
4. Backend verifies the Firebase token with Firebase Admin SDK.
5. Backend looks up `alumni_db.alumni` by email.
6. Backend blocks admin emails from the alumni Firebase path.
7. Backend gates on `registrationstatus`.
8. Backend stores `firebase_uid` using `COALESCE(firebase_uid, uid)`, updates `last_login`, and transitions `Unregistered` or `Inactive` to `Active`.
9. Backend returns an internal JWT.

Portal alumni auth response:

```json
{
  "status": "ok",
  "access_token": "...",
  "token_type": "bearer",
  "role": "alumni",
  "alumni_id": "ALUMNI-000001",
  "fullname": "Name",
  "expires_in": 3600
}
```

Portal alumni JWT claims:

- `sub`: email
- `alumni_id`
- `firebase_uid`
- `role`: `alumni`
- `fullname`
- `exp`

### Portal Admin Flow

Source files: `webapp/backend/routers/auth_v1.py`, `webapp/backend/dependencies.py`, `webapp/frontend/src/pages/Login.jsx`.

- `POST /api/v1/auth/check-email` routes an email to admin password flow or alumni magic-link flow.
- `POST /api/v1/auth/admin/login` validates password, account state, lockout, and TOTP.
- First-time TOTP setup returns `status: "totp_setup_required"`, `setup_token`, and `qr_code`.
- Existing TOTP users receive `status: "totp_required"` until `totp_code` is supplied.
- Full admin JWT carries `role` as `staff_admin` or `super_admin`.
- `totp_setup` is an intermediate role and is blocked by `get_current_user`.
- Admin expiry is 4 hours for `super_admin` and 8 hours for `staff_admin`.

### Website Flow

Source files: `backend/src/api/auth.py`, `backend/src/middleware/firebase.py`, `frontend/src/firebase.js`, `frontend/src/api.js`.

1. User signs in through Firebase.
2. Client posts to `POST /api/v1/auth/firebase` as `{ "token": "<firebase-id-token>" }`.
3. Backend verifies Firebase token using the tenant Firebase project.
4. Backend looks up matching alumni email in `alumni_db.alumni`.
5. Backend upserts `website_users`.
6. Backend writes Firebase UID back to `alumni_db.alumni` with `COALESCE`.
7. Backend issues an internal JWT with 8-hour expiry.

Website auth response includes:

- `status`
- `access_token`
- `token_type`
- `firebase_uid`
- `user_type`
- `fullname`
- `ref_id`
- `is_admin`
- `is_content_editor`
- `graduation_year`

Website JWT claims include:

- `sub`: email
- `firebase_uid`
- `user_type`
- `ref_id`
- `is_admin`
- `is_content_editor`
- `graduation_year`
- `exp`

Flutter recommendation:

- Prefer a website-style Event App auth contract for attendee and public browsing flows: `firebase_uid`, `user_type`, `ref_id`, and admin flags.
- For event admin screens, either use existing portal admin auth directly or bridge existing admin roles into the event backend. Do not create a parallel admin login system.
- Use `Authorization: Bearer <internal-jwt>` for all protected event APIs.
- Centralize token refresh by obtaining a fresh Firebase ID token and exchanging it again for the internal JWT.

## 3. User Role Model

Existing portal roles:

- `alumni`
- `staff_admin`
- `super_admin`
- `totp_setup`, temporary and blocked from normal endpoints

Existing website user model:

- `user_type`: commonly `alumni` or `other`
- `ref_id`: alumni reference, normally `ALUMNI-...`
- `is_admin`: boolean
- `is_content_editor`: boolean

Existing enforcement:

- Portal uses `get_current_user` and `require_role(...)` in `webapp/backend/dependencies.py`.
- Website uses `get_current_user` and `require_user_type(...)` in `backend/src/middleware/firebase.py`.
- Admin portal features are gated by `staff_admin` and `super_admin`.
- Website content review uses boolean flags such as `is_admin` and `is_content_editor`.
- Community-level admin is modeled as scoped membership data, not a new global role.

Flutter Event App recommendation:

- Public/alumni app access should reuse existing alumni identity.
- Event admin access should reuse `staff_admin` and `super_admin` first.
- If event-specific delegation is needed, add a narrow event permission table such as `event_admins(firebase_uid, ref_id, event_id, scope)` rather than creating new global roles.
- Keep `firebase_uid` as login identity and `ref_id` / `alumni_id` as alumni record identity.

## 4. API Response/Error Format

Existing products use FastAPI defaults plus lightweight response conventions.

Success conventions:

- Auth success: `{ "status": "ok", ... }`
- Pending self-registration: `{ "status": "pending", "alumni_id": "..." }`
- Mutations often return `{ "status": "ok", "message": "...", ... }`
- Lists return metadata and arrays:
  - Portal alumni search: `{ "total", "page", "page_size", "results" }`
  - Website directory: `{ "total", "page", "limit", "pages", "results" }`
  - Admin users: `{ "users": [...] }`
  - Website map: `{ "total", "mapped_total", "locations" }`

Error conventions:

- FastAPI `HTTPException` returns `{ "detail": "message" }`.
- Validation errors return FastAPI 422 with `detail` as an array of validation objects.
- Frontends flatten `detail` arrays into joined messages.
- `401` clears local/session auth and returns the user to sign-in.
- `403` is used for account state or permission blocks.

Existing machine-readable auth/status errors include:

- `not_admin`
- `alumni_not_found`
- `registration_pending`
- `account_blocked`
- `account_inactive`
- `registration_already_pending`
- `email_already_registered`
- `email_required`

Flutter recommendation:

- Build one API client that handles FastAPI `detail` consistently.
- On `401`, clear internal JWT and return to sign-in.
- On `403`, show account-state or permission-specific messaging.
- On `404` with `alumni_not_found`, route to the existing self-registration decision path or event-specific blocked state.
- On `422`, flatten validation messages.
- For new event endpoints, use the same simple success envelope and FastAPI error shape instead of inventing a new response envelope.

## 5. Cloud SQL/Database Names and Connection Pattern

Cloud SQL instance:

- `project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db`

Production socket:

- `/cloudsql/project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db`

Existing databases:

- `alumni_db`: alumni identity, profile data, portal admin users, audit logs.
- `website_db`: website users and website features, including communities, stories, mentorship, career, contact requests, and connections.

Portal connection pattern:

- `webapp/backend/database.py` initializes two `psycopg2.pool.ThreadedConnectionPool` pools.
- `get_db()` connects to `alumni_db`.
- `get_website_db()` connects to `website_db`.
- Production uses Cloud SQL Unix socket.
- Local development uses `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_SSLMODE`.
- Pool exhaustion returns `503` rather than hanging.

Website connection pattern:

- `backend/src/services/db.py` lazily initializes two `SimpleConnectionPool` pools.
- `get_db()` connects to `website_db`.
- `get_alumni_db()` connects to `alumni_db`.
- `backend/src/config/settings.py` builds `db_url` and `alumni_db_url`.
- Production DSNs use the Cloud SQL Unix socket; local DSNs use host/port.

Event database recommendation:

- Reuse the same Cloud SQL instance.
- Create an event-specific database or schema, for example `events_db` or an `events` schema, if event data has a clean lifecycle boundary.
- Keep `alumni_db` as the identity source of truth and mostly read-only, except for the existing Firebase UID backfill behavior.
- Do not use cross-database foreign keys.
- Store references by value:
  - `firebase_uid`
  - `ref_id` / `alumni_id`
  - optional denormalized display fields for immutable event snapshots
- Merge cross-database data in backend code, not SQL joins across databases.

## 6. Existing Alumni Lookup/ref_id Logic

Portal alumni lookup:

- `POST /api/v1/auth/alumni/firebase` matches Firebase token email against `alumni.email`.
- If found, the JWT carries `alumni_id`.
- `firebase_uid` is stored on `alumni` using `COALESCE(firebase_uid, uid)`.
- `Pending`, `Blocked`, and `Deceased` are denied.
- `Unregistered` and `Inactive` become `Active` on successful login.
- Self-registration creates a `Pending` `alumni` row with an `ALUMNI-NNNNNN` ID generated by scanning the current maximum.

Website alumni/ref_id lookup:

- `POST /api/v1/auth/firebase` matches Firebase token email against `alumni_db.alumni`.
- Matching alumni get `ref_id = alumni.alumni_id` and `user_type = "alumni"`.
- `website_users` upsert uses existing seeded stubs when `ref_id` exists.
- Resolved values are read back from `website_users`, so manual overrides are respected.
- `alumni_db.alumni.firebase_uid` is backfilled using `COALESCE`.
- `backend/src/services/alumni.py` fetches alumni display info by `firebase_uid` and caches it for 5 minutes.

Directory/privacy logic:

- Website directory requires `user_type = "alumni"`.
- Directory list and map filter `directory_visible = true`.
- Deceased alumni are excluded.
- Detail responses apply privacy flags by nulling hidden `email`, `phone`, `currentlocation`, and `linkedin`.
- Map responses only include users with `show_location = true` and geocoded coordinates.

Event App recommendation:

- Use `ref_id` consistently for event registration linkage.
- Do not duplicate alumni profiles into event tables as the primary source.
- Event registrations should reference `firebase_uid` and/or `ref_id` by value.
- Fetch live alumni fields from `alumni_db` when privacy and freshness matter.
- For event attendee lists, apply the same privacy flags before exposing contact or location data.
- Use a short-lived backend cache like `fetch_alumni_info()` for display fields.

## 7. Existing Theme Colors, Typography, Spacing

Core tokens from `nitksaa-website/frontend/src/styles/tokens.css` and portal `global.css`:

- Navy: `#0f2744`
- Deep navy: `#09192e`
- Canvas: `#070f1c`
- Mid navy: `#162f52`
- Light navy: `#1e3f6e`
- Muted navy: `#2a5298`
- Gold: `#c9a84c`
- Gold light: `#e2c97e`
- Gold pale: `#f5ecd4`
- Gold dim: `#8a6e2f`
- White: `#ffffff`
- Off white: `#f8f5ef`
- Dark text primary: `#f0e6c8` on website, `#f0ead8` in portal
- Text secondary: `#9db4d0`
- Text muted: `#5a7a9a`

Typography:

- Serif display: `Crimson Pro`, fallback `Georgia`, `serif`
- Sans UI: `DM Sans`, fallback `system-ui`, `sans-serif`
- Headings use the serif family.
- Labels, controls, nav, tables, and body use the sans family.

Spacing and shape:

- Container max width: `1520px`
- Desktop horizontal padding: `40px`
- Nav height: `68px`
- Website topbar height: `56px`
- Small radius: `6px`
- Medium radius: `12px`
- Large radius: `20px`
- Buttons: `10px 22px`, small radius, inline-flex, 8px gap
- Cards: `24px` padding, subtle border, translucent surface
- Admin filters: 8px radius, compact inputs, 1rem gaps

Flutter theme recommendation:

- Build a Flutter theme from website `tokens.css`; use portal admin styles for dense admin screens.
- Use `DM Sans` for body, controls, labels, tables, and nav.
- Use `Crimson Pro` for major titles and page headings.
- Keep dark navy/gold as the default identity.
- Add light mode only if Flutter scope requires parity with website light theme.
- Use spacing tokens: 6, 8, 10, 12, 16, 24, 32, 40.

## 8. Reusable UI Patterns for Flutter Equivalent

Reusable patterns from website and portal:

- Fixed top navigation / authenticated app shell.
- Page header with uppercase eyebrow, serif heading, gold divider, optional subtitle.
- Search topbar with filter toggle and result count.
- Filter sidebar driven by section definitions.
- Persistent filters per module.
- Grid/table view toggle for browsable collections.
- Entity card with avatar, title, subtitle, tags, and meta slot.
- Paginated collection surface with loading skeletons, empty state, error state, retry, and pagination.
- Badges for status, role, metadata, and review states.
- Own-card gold tint for user-owned records.
- Modal/detail-page split for dense object details.
- Admin data table with compact rows, uppercase headers, filters above table, chips, and pagination.
- Success/error banners or toast equivalents for admin operations.

Flutter widget equivalents:

- `AppShell`
- `PageHeader`
- `SearchTopBar`
- `FilterDrawer` or `FilterSheet`
- `ViewToggle`
- `EntityCard`
- `EntityCollection`
- `StatusBadge`
- `DetailSheet` or `DetailPage`
- `AdminDataTable`
- `LoadingSkeleton`
- `EmptyState`
- `ApiErrorBanner`

For the Event App, map these patterns to event concepts:

- Event list: collection page with search, date/category/status filters, cards, empty state, and retry.
- Event detail: detail page or sheet with event metadata, host, schedule, registration state, and CTA.
- My Events: personal hub equivalent to website self-service pages.
- Attendee list: admin data table equivalent with filters, status badges, export, and pagination.
- Check-in queue: compact admin table/list with search, status chips, and explicit actions.

## 9. Admin Portal Patterns to Reuse for Event Admin

Portal admin patterns to reuse:

- Admin login remains email/password/TOTP.
- `super_admin` manages admin users.
- `staff_admin` and `super_admin` can operate admin queues.
- Audit logs are filterable by actor, action, resource, and date range.
- Admin tables use compact rows, uppercase headers, filters above the table, small chips, and explicit pagination.
- Mutations write audit log entries, but audit failure should not break the primary operation.
- CSV export requires explicit purpose and should be audited.
- Sensitive exports should remain super-admin-only unless a narrower event export permission is introduced.

Event admin reuse:

- Gate event admin pages behind `staff_admin` and `super_admin` initially.
- Use existing `admin_users` for event administrators unless event-specific scoping is required.
- Add event audit actions following existing style, for example `EVENT_CREATED`, `EVENT_UPDATED`, `EVENT_REGISTRATION_APPROVED`, `EVENT_CHECKED_IN`, `EVENT_EXPORT`.
- Reuse filterable queues for event registrations, check-ins, refunds, attendee review, and exports.
- Keep destructive or sensitive actions explicit and logged.

Do not reinvent:

- Admin authentication.
- TOTP setup.
- Global admin role names.
- Audit log style.
- Admin table layout.
- Export purpose/audit patterns.

## 10. Website Patterns to Reuse for Public Event Browsing

Website public/authenticated browsing patterns:

- Collection pages use shared page headers.
- Directory, stories, mentorship, career, and communities use filter sections and persistent filter hooks.
- `EntityCollection` owns loading, empty, error, grid/table display, pagination, and retry states.
- Topbar ordering convention: personal hub on the left, primary action on the right.
- Cards use consistent avatar/title/subtitle/tags/meta composition.
- Own items receive a gold-tinted visual treatment.
- Tenant config exposes display name, theme, and enabled features.
- Map/list browsing follows the same filters and count conventions.

Event browsing reuse:

- Event list should behave like existing directory/story lists:
  - search
  - filter chips/selects
  - date/status/category filters
  - paginated cards
  - empty and retry states
- Event detail can reuse modal/detail-page patterns from person, story, job, and mentor flows.
- Registration state should be shown as badges and CTAs, not a separate identity concept.
- "My Events" should be the personal hub.
- "Register" should be the terminal attendee action.
- "Create Event" or "Manage Event" should appear only for event admins.

Do not reuse website by merging Flutter into it. Reuse product patterns, visual language, and backend conventions in the separate Flutter app.

## 11. Existing Deployment/Cloud Run/Secret Manager Setup

Portal deployment:

- Multi-stage Docker build.
- Stage 1: Node 20 builds React/Vite frontend.
- Stage 2: Python 3.11 installs backend dependencies and serves built frontend through FastAPI.
- Cloud Run starts `uvicorn main:app --host 0.0.0.0 --port $PORT`.
- Firebase Hosting rewrites all routes to Cloud Run:
  - Service: `nitksaa-alumni-portal`
  - Region: `asia-south1`
- `/healthz` is lightweight Cloud Run liveness/startup with no DB dependency.
- `/api/v1/health` checks database and performs lightweight cleanup.

Website deployment:

- Multi-stage Docker build.
- Stage 1: Node 20 builds React/Vite frontend.
- Stage 2: Python 3.12 runs `uvicorn backend.server:app`.
- Cloud Run injects `PORT`, default 8080.
- Backend serves static SPA assets and fallback when frontend build exists.
- Website production Cloud Run domain appears in tenant config as `nitksaa-website-246773894709.asia-south1.run.app`.

Secrets/config:

- `.gcloudignore` excludes `.env` and local artifacts.
- Website `.gcloudignore` excludes docs, tests, scripts, and all env files except `frontend/.env.production`.
- Portal `.gcloudignore` excludes `.env`, data files, local source folders, and intentionally includes frontend production env.
- Backend secrets are expected through environment variables or Secret Manager.
- Portal feedback code documents `gcloud secrets create` and Cloud Run `--set-secrets` for `GMAIL_APP_PASSWORD`.
- DB password and JWT signing secret are environment variables: `DB_PASSWORD`, `SECRET_KEY`.

Event deployment recommendation:

- Deploy Flutter mobile/web separately from `nitksaa-website`.
- Event backend should run on Cloud Run in `asia-south1`.
- Reuse the same Cloud SQL instance and ADC-based Firebase Admin verification.
- Store DB password, JWT secret, payment/webhook secrets, email secrets, and any event provider secrets in Secret Manager.
- Use `/healthz` for no-DB liveness and `/api/v1/health` for DB-aware checks.
- Keep Firebase Hosting rewrites or subdomain routing explicit if a Flutter web build is shipped.

## 12. Gaps/Risks for Event App Integration

- Two internal JWT contracts exist today: portal uses `role/alumni_id`; website uses `user_type/ref_id/is_admin`. The Event App backend should choose one primary contract and document it.
- Portal and website both use the same Firebase project but different frontend storage keys and browser storage models. Flutter should use secure storage and should not depend on browser storage conventions.
- Event-specific permissions are not modeled yet. Reuse existing admin roles first, then add a scoped event permission table only if needed.
- `alumni_db` is the identity source of truth, but existing products write `firebase_uid` back with `COALESCE`. Avoid adding new alumni write paths unless explicitly required.
- Cross-database joins are avoided by convention. Event reporting may require backend aggregation and careful pagination.
- API error shapes are conventional, not formally standardized. Flutter needs centralized error parsing.
- No CI/CD workflow files were found in the reviewed files; deployment appears to rely on manual `gcloud`/Firebase flows.
- Some design tokens differ slightly between portal and website. Use website `tokens.css` as the attendee/public source of truth and portal `admin.css` for admin density.
- Event payment, QR check-in, push notification, offline scan, seat inventory, waitlist, and refunds are not present in existing products and need new backend contracts.
- Privacy flags exist for alumni contact/location fields. Event attendee and admin views must decide which fields are operationally necessary and privacy-gated.
- Website tenant config has localhost in multiple tenants. Event web routing should be explicit for production and staging to avoid ambiguous host resolution.

## Reusable Patterns

- Firebase token exchange into an internal JWT.
- Bearer JWT dependency on every protected API.
- Existing account-state gates: pending, blocked, deceased, inactive/unregistered transitions.
- `firebase_uid` plus `ref_id` / `alumni_id` identity linkage.
- Cloud SQL Unix socket in production and host/port config in development.
- Separate connection pools for identity DB and product DB.
- `COALESCE` for first-time Firebase UID backfill.
- FastAPI `HTTPException(detail=...)` errors.
- Paginated list responses with total/page metadata.
- Page header, gold divider, filter sidebar, collection cards, loading/empty/error states.
- Admin filter bars, audit logs, compact tables, CSV export streaming.
- Privacy enforcement at API boundary before returning alumni contact/location fields.

## Do-Not-Reinvent Rules

- Do not create a new Firebase project.
- Do not create separate Firebase users for events.
- Do not authenticate event users directly against Cloud SQL passwords.
- Do not create a separate admin password/TOTP system.
- Do not create unrelated global roles when `alumni`, `staff_admin`, `super_admin`, and scoped event permissions will work.
- Do not duplicate alumni profile data into event tables as the primary source.
- Do not create cross-database foreign keys.
- Do not bypass privacy flags when showing alumni data in event contexts.
- Do not invent a new response/error envelope unless existing APIs are also migrated.
- Do not merge the Flutter Event App into `nitksaa-website`.

## Recommendations for Flutter Implementation

1. Use Firebase Auth in Flutter with the existing project and enabled providers.
2. Exchange the Firebase ID token for an internal Event backend JWT.
3. Store the internal JWT in secure storage; refresh by re-fetching a Firebase ID token and exchanging it again.
4. Model the authenticated user as `firebaseUid`, `email`, `userType` or `role`, `refId/alumniId`, `isAdmin`, and optional scoped event permissions.
5. Use `ref_id` as the event registration alumni reference.
6. Build event data in `events_db` or an event schema, linked by `firebase_uid` and `ref_id`.
7. Use existing admin roles for event administration first.
8. Add event-scoped permissions only when a non-global event manager is required.
9. Implement a shared Flutter API client that understands FastAPI `detail` errors, 422 validation arrays, and session expiry.
10. Build a Flutter design system from `tokens.css` and portal admin styles: navy/gold colors, `DM Sans`, `Crimson Pro`, 6/12/20 radii, compact admin controls, and collection browsing patterns.
11. Recreate reusable UI patterns as Flutter widgets instead of copying React component structure literally.
12. Keep public event browsing close to website patterns and event admin close to portal admin patterns.
