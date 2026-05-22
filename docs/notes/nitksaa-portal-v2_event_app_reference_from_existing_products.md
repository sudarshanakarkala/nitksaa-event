# Flutter Event App Reference from Existing NITKSAA Products

This reference reviews `nitksaa-portal-v2` and sibling repo `nitksaa-website` for a separate Flutter Event App. It is intentionally a reuse guide, not an implementation plan for merging Flutter into the website.

## Product Boundary

- The Event App should be a separate Flutter app.
- Do not merge Flutter into `nitksaa-website`.
- Do not create a new identity system.
- Do not create a new Firebase project.
- Do not create a new role model unless event requirements cannot be satisfied by existing roles plus event-specific permissions.
- Keep alumni identity anchored to `alumni_db.alumni` and Firebase UID.

## Exact Files Reviewed

### `nitksaa-portal-v2`

- `.firebaserc`
- `.gcloudignore`
- `Dockerfile`
- `README.md`
- `DESIGN_DOC.md`
- `firebase.json`
- `docs/nitksaa-portal-v2_existing_system_review.md`
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
- `webapp/frontend/src/styles/admin.css`
- `webapp/frontend/src/styles/dashboard.css`
- `webapp/frontend/src/styles/global.css`
- `webapp/frontend/src/styles/nav.css`

### `nitksaa-website`

- `.gcloudignore`
- `Dockerfile`
- `README.md`
- `backend/server.py`
- `backend/src/api/alumni_directory.py`
- `backend/src/api/auth.py`
- `backend/src/api/health.py`
- `backend/src/config/settings.py`
- `backend/src/config/tenant_config.py`
- `backend/src/config/tenants.yaml`
- `backend/src/middleware/firebase.py`
- `backend/src/services/alumni.py`
- `backend/src/services/db.py`
- `frontend/.env.production`
- `frontend/src/api.js`
- `frontend/src/firebase.js`
- `frontend/src/components/core/EntityCard.jsx`
- `frontend/src/components/core/EntityCollection.jsx`
- `frontend/src/components/core/FilterSidebar.jsx`
- `frontend/src/components/core/PageHeader.jsx`
- `frontend/src/hooks/useFilters.js`
- `frontend/src/pages/DirectoryPage.jsx`
- `frontend/src/pages/Login.jsx`
- `frontend/src/pages/StoriesPage.jsx`
- `frontend/src/styles/global.css`
- `frontend/src/styles/tokens.css`

## 1. Firebase Project Details

Both existing products use the same Firebase project:

- Project ID: `project-d22bed42-f302-4e23-8dc`
- Firebase Hosting project in portal `.firebaserc`: `project-d22bed42-f302-4e23-8dc`
- Portal backend default `FIREBASE_PROJECT_ID`: `project-d22bed42-f302-4e23-8dc`
- Website tenant Firebase project in `backend/src/config/tenants.yaml`: `project-d22bed42-f302-4e23-8dc`
- Website production Firebase web app config:
  - `VITE_FIREBASE_AUTH_DOMAIN=project-d22bed42-f302-4e23-8dc.firebaseapp.com`
  - `VITE_FIREBASE_PROJECT_ID=project-d22bed42-f302-4e23-8dc`
  - `VITE_FIREBASE_STORAGE_BUCKET=project-d22bed42-f302-4e23-8dc.firebasestorage.app`
  - `VITE_FIREBASE_MESSAGING_SENDER_ID=246773894709`
  - `VITE_FIREBASE_APP_ID=1:246773894709:web:c4d4d005ec66432a33ab7c`

Backend Firebase verification uses Firebase Admin SDK with Application Default Credentials:

- Local: `gcloud auth application-default login`
- Cloud Run: service account ADC

Flutter recommendation:

- Configure Flutter Firebase against the same Firebase project.
- Support Google sign-in and email magic link only if needed for parity with the existing products.
- Treat Firebase ID tokens as login proofs only; exchange them for the backend JWT before calling protected APIs.

## 2. Auth/JWT Flow

### Portal Alumni Flow

Existing flow in `webapp/backend/routers/auth_v1.py` and `webapp/frontend/src/firebase.js`:

1. User signs in through Firebase Google OAuth or email magic link.
2. Client receives a Firebase ID token.
3. Client posts it to `POST /api/v1/auth/alumni/firebase` as `{ "firebase_token": "<token>" }`.
4. Backend verifies the Firebase token with Admin SDK.
5. Backend looks up `alumni_db.alumni` by email.
6. Backend blocks admin emails from using the alumni Firebase path.
7. Backend gates on `registrationstatus`.
8. Backend writes `last_login`, stores `firebase_uid` with `COALESCE`, and transitions `Unregistered` or `Inactive` to `Active`.
9. Backend returns an internal JWT.

Alumni JWT response shape:

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

JWT claims for alumni:

- `sub`: email
- `alumni_id`
- `firebase_uid`
- `role`: `alumni`
- `fullname`
- `exp`

### Portal Admin Flow

Existing flow in `webapp/backend/routers/auth_v1.py`:

- `POST /api/v1/auth/check-email` routes email to admin password flow or alumni magic-link flow.
- `POST /api/v1/auth/admin/login` checks password and TOTP.
- First-time admin TOTP setup returns `status: "totp_setup_required"`, `setup_token`, and `qr_code`.
- Existing TOTP users receive `status: "totp_required"` until `totp_code` is supplied.
- Full admin JWT uses `role` of `staff_admin` or `super_admin`.

Admin expiry:

- `super_admin`: 4 hours
- `staff_admin`: 8 hours

### Website Flow

Existing flow in `backend/src/api/auth.py` and `backend/src/middleware/firebase.py`:

1. Client signs in through Firebase.
2. Client posts `POST /api/v1/auth/firebase` as `{ "token": "<firebase-id-token>" }`.
3. Backend verifies Firebase token using tenant Firebase project.
4. Backend looks up matching alumni email in `alumni_db`.
5. Backend upserts `website_users`.
6. Backend writes Firebase UID back to `alumni_db.alumni` with `COALESCE`.
7. Backend issues an internal JWT with 8-hour expiry.

Website JWT response includes:

- `access_token`
- `firebase_uid`
- `user_type`
- `fullname`
- `ref_id`
- `is_admin`
- `is_content_editor`
- `graduation_year`

Flutter recommendation:

- Use one event backend auth exchange endpoint that follows one of the existing contracts.
- Prefer the website-style `firebase_uid + ref_id` contract for public event browsing and event participation.
- Reuse `Authorization: Bearer <internal-jwt>` for all protected APIs.
- Do not call Firebase Admin from Flutter; Flutter should only obtain the Firebase ID token.
- Do not invent a second JWT issuer or claim language.

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
- Admin-only portal features are gated through `staff_admin` and `super_admin`.
- Website content review uses boolean flags such as `is_admin` and `is_content_editor`.

Flutter Event App recommendation:

- Public/alumni app access: use existing alumni identity.
- Event admin access: reuse `staff_admin` and `super_admin` first.
- If event-specific delegation is required, add a narrow event permission table or flag, for example `event_admins(firebase_uid/ref_id, scope)`, rather than creating a parallel global role model.
- Keep `ref_id` as the alumni reference and `firebase_uid` as the login identity.

## 4. API Response/Error Format

Existing APIs use FastAPI defaults plus small response conventions.

Success conventions:

- Auth success: `{ "status": "ok", ... }`
- Mutations commonly return `{ "status": "ok", "message": "...", ... }`
- Lists return metadata and arrays, for example:
  - Portal alumni search: `{ "total", "page", "page_size", "results" }`
  - Website directory: `{ "total", "page", "limit", "pages", "results" }`
  - Admin users: `{ "users": [...] }`

Error conventions:

- FastAPI `HTTPException` returns `{ "detail": "message" }`.
- Validation errors return FastAPI 422 with `detail` as an array of validation objects.
- Frontends flatten `detail` arrays into joined messages.
- Existing machine-readable auth errors include:
  - `not_admin`
  - `alumni_not_found`
  - `registration_pending`
  - `account_blocked`
  - `account_inactive`
  - `registration_already_pending`
  - `email_already_registered`

Flutter recommendation:

- Build one API client that handles:
  - `401`: clear internal JWT and return user to sign-in.
  - `403`: show permission/status-specific messaging.
  - `404` with `alumni_not_found`: send to self-registration or a blocked event state, depending on product decision.
  - `422`: flatten validation details.
- Preserve existing error strings for shared flows.
- For new event endpoints, use `{ "status": "ok" }`, list metadata, and FastAPI `detail` errors consistently.

## 5. Cloud SQL/Database Names and Connection Pattern

Cloud SQL instance:

- `project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db`

Production socket:

- `/cloudsql/project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db`

Existing databases:

- `alumni_db`: alumni identity, profile data, portal admin users, audit logs.
- `website_db`: website features, `website_users`, communities, stories, mentorship, career, contact data.

Portal connection pattern:

- `webapp/backend/database.py` initializes two `psycopg2.pool.ThreadedConnectionPool` pools.
- `get_db()` connects to `alumni_db`.
- `get_website_db()` connects to `website_db`.
- Production uses Cloud SQL Unix socket.
- Local uses `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_SSLMODE`.

Website connection pattern:

- `backend/src/services/db.py` lazily initializes `SimpleConnectionPool`.
- `get_db()` connects to `website_db`.
- `get_alumni_db()` connects to `alumni_db`.
- `backend/src/config/settings.py` builds `db_url` and `alumni_db_url`.

Event database recommendation:

- Reuse the same Cloud SQL instance.
- Create an event-specific database or schema, for example `events_db`, if event data has a clean lifecycle boundary.
- Keep `alumni_db` as read-only identity source except for existing Firebase UID backfill behavior.
- Do not use cross-database foreign keys.
- Store references by value:
  - `firebase_uid`
  - `ref_id` / `alumni_id`
  - optional denormalized display fields where needed for event snapshots
- Merge cross-database data in backend code, not SQL joins across databases.

## 6. Existing Alumni Lookup/ref_id Logic

Portal alumni lookup:

- `POST /api/v1/auth/alumni/firebase` matches Firebase token email against `alumni.email`.
- If found, the JWT carries `alumni_id`.
- `firebase_uid` is stored on `alumni` with `COALESCE(firebase_uid, uid)`.
- `Pending`, `Blocked`, and `Deceased` are denied.
- `Unregistered` and `Inactive` become `Active` on successful login.

Website alumni/ref_id lookup:

- `POST /api/v1/auth/firebase` matches Firebase token email against `alumni_db.alumni`.
- Matching alumni get `ref_id = alumni.alumni_id` and `user_type = "alumni"`.
- `website_users` upsert uses existing seeded stubs when `ref_id` exists.
- Resolved values come back from `website_users`, so manual overrides are respected.
- `alumni_db.alumni.firebase_uid` is backfilled with `COALESCE`.
- `backend/src/services/alumni.py` fetches alumni info by `firebase_uid` and caches it for 5 minutes.

Event App recommendation:

- Use `ref_id` consistently for event registration linkage.
- Do not duplicate alumni profiles into event tables.
- Event registration tables should reference `ref_id` and/or `firebase_uid` as values.
- Fetch live alumni display fields from `alumni_db` when privacy and freshness matter.
- For performance, use a short-lived cache like `fetch_alumni_info()`.

## 7. Existing Theme Colors, Typography, Spacing

Core design tokens from both products:

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
- Off white: `#f8f5ef`
- Dark text primary: `#f0e6c8` or `#f0ead8`
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
- Small radius: `6px`
- Medium radius: `12px`
- Large radius: `20px`
- Buttons: `10px 22px`, small radius, inline-flex, 8px gap
- Cards: 24px padding, subtle border, translucent surface
- Admin filters: 8px radius, compact fields, 1rem gaps

Flutter recommendation:

- Build a Flutter theme with these exact colors and fonts.
- Use `DM Sans` for body and controls; use `Crimson Pro` for major titles.
- Keep dark navy/gold as the default visual identity.
- Add light mode only if the Flutter scope requires parity with the website light theme.
- Use consistent spacing tokens: 6, 8, 10, 12, 16, 24, 32, 40.

## 8. Reusable UI Patterns for Flutter Equivalent

Reusable portal and website patterns:

- Fixed top navigation / authenticated app shell.
- Page header: uppercase eyebrow, serif heading, gold divider, optional subtitle.
- Search topbar with filter toggle and result count.
- Filter sidebar driven by section definitions.
- Persist filters per module in session-like storage.
- Grid/table view toggle for browsable collections.
- Entity cards with avatar, title, subtitle, tags, and meta slot.
- Paginated collection component with loading skeletons, empty state, error state, and retry.
- Badges for status, role, and metadata.
- Own-card gold tint for user-owned records.
- Admin data tables with compact uppercase headers, filter bar, chips, and pagination.
- Toast success and error banners for admin operations.

Flutter equivalents:

- `AppShell`
- `PageHeader`
- `SearchTopBar`
- `FilterDrawer` or `FilterSheet`
- `EntityCard`
- `EntityCollection`
- `StatusBadge`
- `AdminDataTable`
- `LoadingSkeleton`
- `EmptyState`
- `ApiErrorBanner`

## 9. Admin Portal Patterns to Reuse for Event Admin

Portal admin patterns:

- Admin login remains email/password/TOTP, not Firebase.
- Super admin manages admin users.
- Staff admin and super admin can review pending registrations.
- Audit logs are filterable by actor, action, resource, and date range.
- Admin tables use compact rows, uppercase headers, filters above the table, small chips, and explicit pagination.
- Mutations write audit log entries but audit failure must not break the primary operation.

Event admin reuse:

- Gate event admin pages behind `staff_admin` and `super_admin` initially.
- Use existing `admin_users` for event administrators unless finer event scoping is required.
- Add event audit actions following existing verbs, for example `EVENT_CREATED`, `EVENT_UPDATED`, `EVENT_REGISTRATION_APPROVED`.
- Reuse filterable queues for event registrations, check-ins, refunds, and attendee exports.
- Use export patterns from `webapp/backend/routers/alumni.py`: streaming CSV, purpose/audit fields, super-admin-only for sensitive exports.

Do not reinvent:

- Admin authentication.
- TOTP setup.
- Role names.
- Audit log style.
- Admin table layout.

## 10. Website Patterns to Reuse for Public Event Browsing

Website browsing patterns:

- Public-facing authenticated modules use collection pages with a shared page header.
- Directory, stories, mentorship, career, and communities all use filter sections and persistent filter hooks.
- `EntityCollection` handles loading, empty, error, grid/table display, and pagination.
- Topbar ordering convention: personal hub left, primary action right.
- Cards use a consistent avatar/title/subtitle/tags/meta composition.
- Own items receive a gold-tinted visual treatment.
- Tenant config exposes display name, theme, and enabled features.

Event browsing reuse:

- Event list should behave like existing directory/story lists:
  - search
  - filter chips/selects
  - date/status/category filters
  - paginated cards
  - empty and retry states
- Event detail can reuse modal/detail-page patterns from person, story, job, and mentor detail flows.
- "My Events" should be the personal hub.
- "Register" or "Create Event" should be the terminal primary action, depending on role.

Do not reuse website by merging Flutter into it. Reuse the product patterns and backend conventions in the separate Flutter app.

## 11. Existing Deployment/Cloud Run/Secret Manager Setup

Portal deployment:

- Multi-stage Docker build.
- Stage 1: Node 20 builds React/Vite frontend.
- Stage 2: Python 3.11 installs backend dependencies and serves built frontend through FastAPI.
- Cloud Run starts `uvicorn main:app --host 0.0.0.0 --port $PORT`.
- Firebase Hosting rewrites all routes to Cloud Run service:
  - Service: `nitksaa-alumni-portal`
  - Region: `asia-south1`
- `/healthz` is lightweight Cloud Run liveness/startup.
- `/api/v1/health` checks database.

Website deployment:

- Multi-stage Docker build.
- Stage 1: Node 20 builds React/Vite frontend.
- Stage 2: Python 3.12 runs `uvicorn backend.server:app`.
- Cloud Run injects `PORT`, default 8080.
- Backend serves static SPA fallback when frontend build exists.

Secrets/config:

- `.gcloudignore` excludes `.env` and local artifacts.
- Website `.gcloudignore` excludes docs, tests, scripts, and all env files except `frontend/.env.production`.
- Portal `.gcloudignore` excludes `.env`, data files, local source folders, and intentionally includes `webapp/frontend/.env.production`.
- Backend secrets expected through environment variables or Secret Manager.
- `webapp/backend/routers/feedback.py` documents `gcloud secrets create` and `--set-secrets` for `GMAIL_APP_PASSWORD`.

Event deployment recommendation:

- Flutter mobile/web build should be deployed separately from `nitksaa-website`.
- Backend should run on Cloud Run in `asia-south1`, reuse the same Cloud SQL instance, and use ADC for Firebase Admin.
- Store DB password, JWT secret, and event provider secrets in Secret Manager.
- Use `/healthz` for no-DB liveness and `/api/v1/health` for DB-aware checks.
- Keep Firebase Hosting rewrites/subdomain routing consistent if a web version is shipped.

## 12. Gaps/Risks for Event App Integration

- Two internal JWT contracts exist today: portal uses `role/alumni_id`; website uses `user_type/ref_id/is_admin`. The Event App should pick one backend contract and document it clearly.
- Portal and website both use the same Firebase project but different frontend storage keys (`localStorage` versus `sessionStorage`). Flutter should use secure storage and should not depend on browser storage conventions.
- Event-specific permissions are not modeled yet. Reuse existing roles first, but scoped event admin delegation may need a new table.
- `alumni_db` is the identity source of truth, but existing products sometimes write `firebase_uid` back to it. Event backend should avoid new write paths unless explicitly needed.
- Cross-database joins are avoided by convention. Event reporting may require careful backend aggregation.
- Existing public website tenant model has duplicate localhost domain entries in `tenants.yaml`; event web routing should be explicit for production/staging.
- API error shapes are mostly conventional rather than formally standardized. Flutter should centralize error parsing.
- No CI/CD workflow files were found in the reviewed repo files; deployment appears to rely on manual `gcloud` flows.
- Some design tokens differ slightly between portal and website (`text-primary` values). Pick the website `tokens.css` version as the Flutter source of truth unless portal admin parity is more important.
- Event payment, QR check-in, push notification, and offline scan behavior are not present in existing products and will need new backend contracts.

## Reusable Patterns

- Firebase token exchange into internal JWT.
- Bearer JWT dependency on every protected API.
- Existing status gates: pending, blocked, deceased, inactive/unregistered transitions.
- `firebase_uid` plus `ref_id/alumni_id` identity linkage.
- Cloud SQL Unix socket in production and local host/port config in development.
- Separate pools for identity DB and product DB.
- `COALESCE` for first-time Firebase UID backfill.
- FastAPI `HTTPException(detail=...)` errors.
- Paginated list responses with total/page metadata.
- Page header, gold divider, filter sidebar, collection cards, loading/empty/error states.
- Admin filter bars, audit logs, compact tables, CSV export streaming.

## Do-Not-Reinvent Rules

- Do not create a new Firebase project.
- Do not create separate Firebase users for events.
- Do not authenticate event users directly against Cloud SQL passwords.
- Do not create a separate admin password/TOTP system.
- Do not create unrelated global roles when `alumni`, `staff_admin`, `super_admin`, and scoped event permissions will work.
- Do not duplicate alumni profile data into event tables as the primary source.
- Do not create cross-database foreign keys.
- Do not bypass privacy flags when showing alumni data in event contexts.
- Do not invent a new response/error envelope unless the existing APIs are also migrated.
- Do not merge the Flutter Event App into `nitksaa-website`.

## Recommendations for Flutter Implementation

1. Use Firebase Auth in Flutter with the existing project and providers.
2. Exchange Firebase ID token for an internal event JWT through the event backend.
3. Store internal JWT in secure storage; refresh by re-fetching Firebase ID token and exchanging again.
4. Model the authenticated user as:
   - `firebaseUid`
   - `email`
   - `userType` or `role`
   - `refId/alumniId`
   - `isAdmin`
   - `isContentEditor` if website-style claims are reused
5. Use `ref_id` as the event registration alumni reference.
6. Build event tables in `events_db` or an event schema, linked by `firebase_uid` and `ref_id`.
7. Use existing admin roles for event administration first.
8. Add event-scoped permissions only when a non-global event manager is required.
9. Implement a shared Flutter API client that understands FastAPI `detail` errors and 422 validation arrays.
10. Build a Flutter design system from `tokens.css`/`global.css`: navy/gold colors, `DM Sans`, `Crimson Pro`, 6/12/20 radii, 40px desktop padding equivalents, and compact admin surfaces.
11. Recreate reusable UI patterns as Flutter widgets instead of copying React structure literally.
12. Keep public event browsing closer to website patterns and event admin closer to portal admin patterns.
