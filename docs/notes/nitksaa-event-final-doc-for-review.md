# Final Documents for Review

## NITKSAA Event App — Jun 30 Beta Plan

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/notes/june2026/nitksaa_event_beta_plan_jun30_pw.md


### Integration & Architecture Alignment Note

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/notes/june2026/nitksaa-event-app-integration-note_pw.md

### Architecture Review Observations & Feedback

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/architecture/week3_nitksaa_complete_architecture_v1.md

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/architecture/week3_nitksaa_architecture_diagrams_v1.md

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/notes/june2026/nitksaa-event_architecture_review_v1.0.md

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/notes/june2026/nitksaa-event_app_architecture_review_observations.md

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/architecture/alumni_db_integration_architecture_v1.md



### API Docs

https://github.com/sudarshanakarkala/nitksaa-event/tree/main/docs/api


### Swagger Testing Guide

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/api/swagger_testing_guide.md


### Week 3 — Manual Verification Guide v2

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/validation/old/backend_week3_manual_verification_guide_v2.md

### Week 3 — Backend Status

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/releases/week3_status_report_2026-06-18.md


### Week 4 — Backend & Admin portal Status

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/releases/week4_status_report_24-06-2026.md

https://github.com/sudarshanakarkala/nitksaa-event/blob/main/docs/releases/week4_closure_report_2026-06-24.md



# NITKSAA Event Platform — Local Development Startup Guide

**Purpose:** Start the complete local development environment for the NITKSAA Event Platform.

Open **4 separate terminal windows/tabs** and execute the following commands.

---

# Terminal 1 — Cloud SQL Auth Proxy (alumni_db)

This creates a secure tunnel to the Cloud SQL `alumni_db` instance.

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-portal-v2/webapp/backend

./cloud-sql-proxy project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db --port 5433
```

Expected output:

```text
Authorizing with Application Default Credentials
Listening on 127.0.0.1:5433
The proxy has started successfully and is ready for new connections.
```

Leave this terminal running.

---

# Terminal 2 — FastAPI Backend

Navigate to the backend:

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/backend
```

Activate the virtual environment:

```bash
source .venv/bin/activate
```

Start the backend:

```bash
EVENTS_DB_URL="postgresql://ananth@localhost:5432/events_db" \
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Expected output:

```text
INFO: Uvicorn running on http://0.0.0.0:8000
INFO: Application startup complete.
```

---

## Verify Backend

Open another temporary terminal and execute:

```bash
curl -s http://localhost:8000/api/v1/health
```

Expected:

```json
{
  "status": "ok",
  "version": "...",
  "env": "development",
  "db": "ok"
}
```

---

# Terminal 3 — Flutter Event App

Navigate to the Flutter application:

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/apps/event_app
```

Run Flutter:

```bash
flutter run \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

If running on Chrome, you may optionally specify:

```bash
flutter run -d chrome \
  --web-port 5200 \
  --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

---

# Terminal 4 — React Admin Portal

Navigate to the admin portal:

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/admin/event_admin
```

Start the Vite development server:

```bash
npm run dev
```

Expected output:

```text
VITE ready...

Local: http://localhost:5173
```

---

# Running Services

| Service                      | Port | URL                   |
| ---------------------------- | ---- | --------------------- |
| Cloud SQL Proxy (alumni_db)  | 5433 | 127.0.0.1:5433        |
| Local PostgreSQL (events_db) | 5432 | localhost:5432        |
| FastAPI Backend              | 8000 | http://localhost:8000 |
| React Admin Portal           | 5173 | http://localhost:5173 |
| Flutter Web (optional)       | 5200 | http://localhost:5200 |

---

# Startup Order

Always start services in this order:

1. Cloud SQL Proxy
2. FastAPI Backend
3. React Admin Portal
4. Flutter Event App

---

# Shutdown Order

Stop services in the reverse order:

1. Flutter Event App
2. React Admin Portal
3. FastAPI Backend
4. Cloud SQL Proxy

---

# Notes

* Keep the Cloud SQL Proxy running throughout development.
* The backend depends on the proxy for access to the production/staging `alumni_db`.
* `events_db` continues to use the local PostgreSQL instance.
* If the backend reports `Address already in use`, free port **8000** before restarting:

```bash
lsof -i :8000
kill <PID>
```

or, if necessary:

```bash
kill -9 <PID>
```
