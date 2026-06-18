# Getting Started — Week 3 Local Development Setup

**Audience:** New developers onboarding to the NITKSAA Event App backend.  
**Scope:** Week 3 — Registration APIs, Alumni integration, Developer Diagnostics.  
**Last updated:** 2026-06-18

---

## Prerequisites

- PostgreSQL 14 or later (running locally)
- Python 3.11 or later
- Flutter 3.x (for running the Developer Diagnostics prototype)
- Firebase project credentials (for JWT token auth)

---

## 1. Clone and Navigate

```bash
git clone <repo-url>
cd nitksaa-event
```

---

## 2. PostgreSQL Database Setup

Week 3 requires **two databases**:

| Database | Purpose |
|---|---|
| `events_db` | Registrations, events, audit log (primary app DB) |
| `alumni_db` | Alumni profiles — source of truth for alumni validation |

> `alumni_db` does **not** come with migrations in this repo. It represents an external system
> (the NITKSAA alumni directory). You must create it manually for local development.

### 2a. Create `events_db`

```bash
createdb events_db
```

Run all migrations in order:

```bash
cd backend
python -m alembic upgrade head
```

This creates all tables in `events_db`: `events`, `registrations`, `audit_log`, etc.

### 2b. Create `alumni_db` — Manual Setup

```bash
createdb alumni_db
```

Connect to the database:

```bash
psql alumni_db
```

Create the `alumni` table (must match the column names the app queries):

```sql
CREATE TABLE alumni (
  alumni_id          TEXT PRIMARY KEY,
  fullname           TEXT NOT NULL,
  email              TEXT NOT NULL,
  phone              TEXT,
  graduationyear     INTEGER,
  branch             TEXT,
  registrationstatus TEXT NOT NULL DEFAULT 'Active',
  firebase_uid       TEXT
);
```

> **Column name reference:** `backend/app/services/alumni_service.py` queries these
> exact column names. Do not rename them.

Insert a test alumni record:

```sql
INSERT INTO alumni (
  alumni_id,
  fullname,
  email,
  phone,
  graduationyear,
  branch,
  registrationstatus,
  firebase_uid
) VALUES (
  'NITK2026IT001',
  'Test Alumni',
  'testuser@example.com',
  '+919876543210',
  2026,
  'Information Technology',
  'Active',
  NULL  -- populate with your Firebase UID after login
);
```

> **Active alumni:** `registrationstatus` must be `'Active'` or `'Self-Verified'` for the user to
> pass the alumni validation check. Any other value makes the user ineligible.
>
> **firebase_uid:** Leave `NULL` initially. After testing a login flow, update this field with the
> UID from your Firebase test user (or use the `find_alumni_by_email` code path which looks up by
> email instead of UID).

---

## 3. Environment Variables

Create a `.env` file in the `backend/` directory:

```bash
cp backend/.env.example backend/.env
```

If `.env.example` does not exist, create `backend/.env` with:

```env
# Database connections
EVENTS_DB_URL=postgresql://localhost/events_db
ALUMNI_DB_URL=postgresql://localhost/alumni_db

# Auth
SECRET_KEY=dev-event-secret-change-me
ACCESS_TOKEN_EXPIRE_MINUTES=480

# Firebase (required for JWT validation)
FIREBASE_PROJECT_ID=your-firebase-project-id

# Email — use "log" to print to console instead of sending
EMAIL_MODE=log

# CORS
ALLOWED_ORIGINS=http://localhost:5173,http://localhost:3000

# SMTP — only required when EMAIL_MODE=send
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
```

### Variable Reference

| Variable | Default | Required | Notes |
|---|---|---|---|
| `EVENTS_DB_URL` | — | Yes | `postgresql://user:pass@host/events_db` |
| `ALUMNI_DB_URL` | — | Yes | `postgresql://user:pass@host/alumni_db` |
| `SECRET_KEY` | `dev-event-secret-change-me` | Change for production | JWT signing key |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `480` | No | 8 hours |
| `FIREBASE_PROJECT_ID` | — | Yes | From Firebase console |
| `EMAIL_MODE` | `log` | No | `log` → console, `send` → SMTP |
| `ALLOWED_ORIGINS` | `http://localhost:5173` | No | Comma-separated |
| `SMTP_HOST` | `smtp.gmail.com` | Only if EMAIL_MODE=send | |
| `SMTP_PORT` | `587` | Only if EMAIL_MODE=send | |
| `SMTP_USERNAME` | — | Only if EMAIL_MODE=send | |
| `SMTP_PASSWORD` | — | Only if EMAIL_MODE=send | |

> **Unknown env vars:** The config uses `extra = "ignore"`. Extra variables in `.env` are silently
> ignored — they do not crash the app. It is safe to have variables from other projects in the
> same `.env` file.

---

## 4. Install Backend Dependencies

```bash
cd backend
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

---

## 5. Start the Backend

```bash
cd backend
uvicorn app.main:app --reload --port 8000
```

The API is now available at `http://localhost:8000`.

Verify it is running:

```bash
curl http://localhost:8000/api/v1/events/public
```

You should get a JSON response (empty array `[]` if no events are published).

---

## 6. Start the Flutter App (Developer Diagnostics)

```bash
cd apps/event_app
flutter pub get
flutter run -d chrome \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=testuser@example.com
```

> `DEV_DIAGNOSTICS_EMAIL` is the email that pre-fills the developer diagnostics email field.
> Replace it with the email of the alumni record you inserted in step 2b.

---

## 7. Create a Test Event in `events_db`

The registration endpoints require an existing event. Insert one:

```bash
psql events_db
```

```sql
INSERT INTO events (
  title,
  description,
  start_datetime,
  end_datetime,
  timezone,
  is_virtual,
  location_text,
  location_maps_url,
  virtual_url,
  status,
  capacity,
  registration_opens_at,
  registration_closes_at,
  created_at
) VALUES (
  'Dev Test Event',
  'Local dev test event',
  NOW() + interval '7 days',
  NOW() + interval '7 days' + interval '2 hours',
  'Asia/Kolkata',
  false,
  'NIT Karnataka, Surathkal',
  NULL,
  NULL,
  'published',
  50,
  NOW() - interval '1 day',
  NOW() + interval '6 days',
  NOW()
) RETURNING event_id;
```

Note the `event_id` returned — you will need it for the diagnostics UI.

---

## 8. Obtain a Test Firebase JWT Token

To call authenticated endpoints manually (via curl or the Swagger UI):

1. Log into the Flutter app in development mode.
2. Open browser dev tools and inspect the network request to any backend endpoint.
3. Copy the `Authorization: Bearer <token>` value from the request header.

Or use the Firebase REST API:

```bash
# Exchange Firebase ID token for a backend-compatible token (if your app uses Firebase Auth)
# See Firebase REST Auth docs for your project's sign-in method
```

---

## 9. Verify End-to-End

### A. Check alumni profile (requires valid JWT)

```bash
curl -H "Authorization: Bearer <your-token>" http://localhost:8000/api/v1/alumni/me
```

Expected response:

```json
{
  "ref_id": "NITK2026IT001",
  "fullname": "Test Alumni",
  "email": "testuser@example.com",
  "phone": "+919876543210",
  "batch_year": 2026,
  "branch": "Information Technology",
  "is_active": true
}
```

### B. Check eligibility

```bash
curl -H "Authorization: Bearer <your-token>" \
  "http://localhost:8000/api/v1/events/<event_id>/registration-eligibility"
```

Expected: `"eligibility_status": "eligible"`

### C. Register for the event

```bash
curl -X POST \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "http://localhost:8000/api/v1/events/<event_id>/register"
```

Expected: HTTP 201 with `RegistrationResponse` including a nested `event` object.

### D. Run the Developer Diagnostics suite

In the Flutter app, navigate to **Developer → Registration Diagnostics** and press
**Run All Checks**. All 13 checks should pass if the backend is running correctly.

---

## 10. Common Problems

### `ALUMNI_DB_URL not set` or connection error

The backend will fail to start if `ALUMNI_DB_URL` is missing or the database does not exist.
Create the database and table per §2b before starting the backend.

### `alumni_profile_not_found` on GET /alumni/me

The authenticated user's `ref_id` is not in `alumni_db`. Either:
- Insert the alumni row with the correct `alumni_id` matching the user's `ref_id` in the JWT.
- Or update the existing alumni row's `firebase_uid` to match the test user's Firebase UID.

### `alumni_not_active` on POST /register

The `registrationstatus` column in `alumni_db.alumni` is not `'Active'` or `'Self-Verified'`.
Update the row:

```sql
UPDATE alumni SET registrationstatus = 'Active' WHERE alumni_id = 'NITK2026IT001';
```

### `event_not_found` or `event_not_published`

Either the event doesn't exist, or `status != 'published'`. Check:

```sql
SELECT event_id, title, status FROM events ORDER BY event_id DESC LIMIT 5;
```

### `registration_not_open_yet` or `registration_closed`

The event's registration window is not active. Check:

```sql
SELECT registration_opens_at, registration_closes_at FROM events WHERE event_id = <id>;
```

Adjust the window:

```sql
UPDATE events
SET registration_opens_at = NOW() - interval '1 day',
    registration_closes_at = NOW() + interval '6 days'
WHERE event_id = <id>;
```

### Email errors not crashing the server (expected behavior)

With `EMAIL_MODE=log`, email output goes to the console. If `EMAIL_MODE=send` is set but SMTP
credentials are wrong, the registration still succeeds — email failure is non-blocking.
The `confirmation_email_status` field in the response will be `'failed'` instead of `'sent'`.

---

## 11. Swagger UI

Interactive API documentation is available at:

```
http://localhost:8000/docs
```

All Week 3 endpoints are visible here. Use the **Authorize** button to paste a Bearer token
for testing authenticated routes directly in the browser.

---

## 12. Reference Documents

| Document | Purpose |
|---|---|
| `docs/api/events_api_contract_v2.md` | Full API contract with field notes and security rules |
| `docs/api/week3_actual_api_response_shapes.md` | Verbatim JSON shapes for all 5 endpoints |
| `docs/validation/backend_week3_manual_verification_guide.md` | Step-by-step manual test guide |
| `docs/releases/week3_closure_report.md` | Week 3 scope and design decisions |
