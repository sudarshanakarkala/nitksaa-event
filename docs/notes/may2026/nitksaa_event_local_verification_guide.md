# NITKSAA Event App - Local Verification Guide - Authentication

## Purpose

This guide allows Developers, Testers, Product Owners, and QA Engineers to run and verify the complete NITKSAA Event system locally.

### Components Covered

* PostgreSQL Database
* FastAPI Backend
* Firebase Authentication
* Flutter Mobile Application
* Android Emulator
* Developer Diagnostics
* JWT Authentication
* Database Diagnostics APIs

---

# Prerequisites

## Required Software

### macOS

* Git
* PostgreSQL
* Python 3.10+
* Flutter SDK
* Android Studio
* Android Emulator
* Firebase Project Access

### Windows

* Git
* PostgreSQL
* Python 3.10+
* Flutter SDK
* Android Studio
* Android Emulator
* Firebase Project Access

---

# Project Path Convention

Replace:

```text
{NITK_Alumni_Project_Path}
```

with your local project root.

## Example

### macOS

```bash
/Users/john/projects
```

### Windows

```cmd
C:\Projects
```

---

# 1. Verify PostgreSQL Database

## macOS

```bash
psql -d events_db -c "\dt"
```

## Windows

```cmd
psql -d events_db -c "\dt"
```

Verify tables:

```bash
psql -d events_db -c "\d event_users"
psql -d events_db -c "\d events"
psql -d events_db -c "\d registrations"
psql -d events_db -c "\d check_ins"
psql -d events_db -c "\d event_content"
psql -d events_db -c "\d event_audit_log"
psql -d events_db -c "\d notifications"
psql -d events_db -c "\d notification_preferences"
```

Verify user data:

```bash
psql -d events_db -c "SELECT firebase_uid,email,fullname,user_type,last_login FROM event_users ORDER BY last_login DESC LIMIT 5;"
```

Expected:

```text
At least one user record after successful login.
```

---

# 2. Start Backend

## macOS

```bash
cd {NITK_Alumni_Project_Path}/nitksaa-event/backend

python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

## Windows

```cmd
cd {NITK_Alumni_Project_Path}\nitksaa-event\backend

python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Expected:

```text
Application startup complete.
```

---

# 3. Verify Backend Health

Open a second terminal.

## macOS

```bash
curl http://127.0.0.1:8000/api/v1/health
```

## Windows

```cmd
curl http://127.0.0.1:8000/api/v1/health
```

Expected:

```json
{
  "status": "ok",
  "version": "0.1.0-alpha",
  "env": "development",
  "db": "ok"
}
```

---

# 4. Verify Backend Compilation

## macOS

```bash
cd {NITK_Alumni_Project_Path}/nitksaa-event/backend

python -m py_compile app/**/*.py
```

## Windows

```cmd
cd {NITK_Alumni_Project_Path}\nitksaa-event\backend

python -m py_compile app/**/*.py
```

Expected:

```text
No errors.
```

---

# 5. Verify Flutter Project

## macOS

```bash
cd {NITK_Alumni_Project_Path}/nitksaa-event/apps/event_app

flutter analyze
flutter test
```

## Windows

```cmd
cd {NITK_Alumni_Project_Path}\nitksaa-event\apps\event_app

flutter analyze
flutter test
```

Expected:

```text
No issues found.
All tests passed.
```

---

# 6. Verify Android Emulator

## macOS

```bash
adb devices
```

## Windows

```cmd
adb devices
```

Expected:

```text
emulator-5554 device
```

If emulator is not running:

```bash
flutter emulators
```

Start emulator:

```bash
flutter emulators --launch <emulator_id>
```

---

# 7. Verify Emulator Can Reach Backend

Open Chrome inside Android Emulator.

Navigate to:

```text
http://10.0.2.2:8000/api/v1/health
```

Expected:

```json
{
  "status": "ok",
  "db": "ok"
}
```

---

# 8. Run Flutter Application

## macOS

```bash
cd {NITK_Alumni_Project_Path}/nitksaa-event/apps/event_app

flutter run -d emulator-5554 \
--dart-define=DEV_BACKEND_BASE_URL=http://10.0.2.2:8000
```

## Windows

```cmd
cd {NITK_Alumni_Project_Path}\nitksaa-event\apps\event_app

flutter run -d emulator-5554 --dart-define=DEV_BACKEND_BASE_URL=http://10.0.2.2:8000
```

Expected:

```text
Application launches successfully.
```

---

# 9. Verify Authentication Flow

Inside the Mobile App:

```text
Open App
→ Login with Google
→ Navigate to Developer Diagnostics
```

Run:

```text
Dev: Get Firebase ID Token
Run Full Validation
```

Expected:

```text
Firebase Login      PASSED
Backend Login       PASSED
JWT Generated       PASSED
/auth/me            PASSED
Database Tables     PASSED
event_users         PASSED
```

---

# 10. Verify Backend Login

Copy Firebase ID Token from Developer Diagnostics.

Replace:

```text
<FIREBASE_ID_TOKEN>
```

Execute:

```bash
curl -X POST http://127.0.0.1:8000/api/v1/auth/firebase \
-H "Content-Type: application/json" \
-d '{"token":"<FIREBASE_ID_TOKEN>"}'
```

Expected:

```json
{
  "status": "ok",
  "access_token": "...",
  "token_type": "bearer"
}
```

Save:

```text
access_token
```

for the next step.

---

# 11. Verify /auth/me

Replace:

```text
<ACCESS_TOKEN>
```

Execute:

```bash
curl http://127.0.0.1:8000/api/v1/auth/me \
-H "Authorization: Bearer <ACCESS_TOKEN>"
```

Expected:

```json
{
  "firebase_uid": "...",
  "email": "...",
  "fullname": "..."
}
```

---

# 12. Verify Diagnostics APIs

## Table Counts

```bash
curl http://127.0.0.1:8000/api/v1/dev/diagnostics/db/tables \
-H "Authorization: Bearer <ACCESS_TOKEN>"
```

Expected:

```json
{
  "status": "ok"
}
```

---

## event_users

```bash
curl http://127.0.0.1:8000/api/v1/dev/diagnostics/db/event_users \
-H "Authorization: Bearer <ACCESS_TOKEN>"
```

Expected:

```json
{
  "status": "ok",
  "row_count": 1
}
```

---

# Final Acceptance Checklist

## Backend

* [ ] FastAPI starts successfully
* [ ] Health endpoint returns OK
* [ ] Backend compilation succeeds

## Database

* [ ] events_db exists
* [ ] All required tables exist
* [ ] event_users record inserted

## Flutter

* [ ] flutter analyze passes
* [ ] flutter test passes
* [ ] Application launches

## Authentication

* [ ] Google Login works
* [ ] Firebase Token generated
* [ ] Backend Login works
* [ ] JWT generated
* [ ] /auth/me returns authenticated user

## Diagnostics

* [ ] Table Counts visible
* [ ] event_users visible
* [ ] Full Validation passes

---

# Sprint 1 Success Criteria

An Alumni user can:

```text
Open App
→ Login with Google
→ Reach Home Screen
→ Backend validates Firebase Token
→ JWT generated
→ User stored in event_users
→ Developer Diagnostics confirms success
```

## Sprint 1 Status

```text
Authentication Foundation COMPLETE
Developer Diagnostics COMPLETE
Database Verification COMPLETE
Ready for Sprint 2
```

# NITKSAA Event App — Week 1 Status Review

**Review Date:** 2026-05-31

Reference:

* Beta Plan
* Integration Note
* Local Verification Guide

---

# Week 1 Goal

> Auth done end-to-end. Backend and DB standing.

Status: **~70% Complete**

---

# Flutter (Attendee App)

| Item                   | Status             | Notes                        |
| ---------------------- | ------------------ | ---------------------------- |
| Email/Password Sign-In | ⏳ Unknown          | Not yet verified             |
| Google Sign-In         | ✅ Done             | Login working                |
| authStateChanges()     | ⏳ Needs Review     | Verify implementation        |
| Route Guards           | ⏳ Needs Review     | Not yet validated            |
| Session Persistence    | ⏳ Needs Validation | Restart test pending         |
| Shared UI Library      | ❌ Not Started      | AppScaffold, AppCard, etc.   |
| Refactor Screens       | ❌ Not Started      | Splash/Login/HomePlaceholder |

## Flutter Progress

Completed:

* Google Login
* Firebase Authentication
* Developer Diagnostics
* Backend Validation
* JWT Validation

Pending:

* Shared UI Components
* Route Guard Verification
* Session Persistence Validation
* Email/Password Authentication Verification

---

# FastAPI Backend

| Item                | Status   | Notes                           |
| ------------------- | -------- | ------------------------------- |
| Folder Structure    | ✅ Done   | api, middleware, services, etc. |
| Firebase Middleware | ✅ Done   | Working                         |
| Health Endpoint     | ✅ Done   | Verified                        |
| Request Logging     | ⏳ Verify | Need confirmation               |
| events_db Created   | ✅ Done   |                                 |
| Migrations Applied  | ✅ Done   |                                 |
| JWT Generation      | ✅ Done   |                                 |
| /auth/me            | ✅ Done   |                                 |

## Backend Progress

Completed:

* Firebase Token Verification
* JWT Minting
* User Upsert
* Health Endpoint
* Developer Diagnostics APIs
* Database Diagnostics APIs
* event_users population

Pending:

* Request Logging Middleware verification

---

# Database

| Item                     | Status |
| ------------------------ | ------ |
| events_db                | ✅      |
| event_users              | ✅      |
| events                   | ✅      |
| sessions                 | ✅      |
| registrations            | ✅      |
| check_ins                | ✅      |
| event_content            | ✅      |
| event_audit_log          | ✅      |
| notifications            | ✅      |
| notification_preferences | ✅      |

## Database Progress

Completed:

* Database created
* Migrations executed
* Tables verified
* User insertion verified

Verified Example:

```text
event_users row_count = 1
firebase_uid = adW99tFFnDPp10cTd2vUMfEGCxS2
email = sudarshana.ashwini@gmail.com
fullname = Ashwini Sudarshana
```

---

# Authentication Flow

| Validation          | Status |
| ------------------- | ------ |
| Firebase Login      | ✅      |
| Backend Login       | ✅      |
| JWT Generation      | ✅      |
| /auth/me            | ✅      |
| Database Insert     | ✅      |
| User Data Retrieval | ✅      |
| Table Counts        | ✅      |

## Authentication Status

```text
Firebase Login        PASSED
Backend Login         PASSED
JWT Generation        PASSED
/auth/me              PASSED
Database Insert       PASSED
User Data Retrieval   PASSED
Table Counts          PASSED
```

---

# Developer Diagnostics

| Feature                | Status |
| ---------------------- | ------ |
| Firebase Validation    | ✅      |
| Backend Validation     | ✅      |
| JWT Validation         | ✅      |
| /auth/me Validation    | ✅      |
| Table Counts           | ✅      |
| Table Viewer           | ✅      |
| event_users Viewer     | ✅      |
| Full Validation Button | ✅      |
| Status Chips           | ✅      |
| Responsive UI          | ✅      |

Status:

```text
Developer Diagnostics = COMPLETE
```

---

# React Admin Portal

| Item           | Status |
| -------------- | ------ |
| Login          | ❌      |
| Route Guard    | ❌      |
| Sidebar Layout | ❌      |
| Header Layout  | ❌      |

Status:

```text
Not Started
```

---

# Week 1 Milestone Review

Expected:

```text
Alumni logs in
→ Firebase Auth
→ Backend validates token
→ JWT generated
→ Home Screen
→ Developer Diagnostics confirms success
```

Actual:

```text
Firebase Login
→ Backend Validation
→ JWT Generated
→ /auth/me Verified
→ event_users Inserted
→ Diagnostics Verified
```

Status:

✅ Milestone Achieved

---

# Remaining Week 1 Tasks

## High Priority

### Flutter

* Verify authStateChanges()
* Verify route guards
* Verify session persistence after app restart

### Backend

* Verify request logging middleware

### React Admin

* Login
* Route Guards
* Basic Layout

---

# Recommendation

Do NOT start Week 2 Event CRUD yet.

First complete:

1. Route Guards
2. Session Persistence
3. Request Logging Middleware
4. React Admin Login

After those are complete:

```text
Week 1 = 100% Complete
```

Then start:

```text
Week 2 = Event Creation + Public Listing
```

---

# Current Overall Status

```text
Authentication Foundation      ✅ COMPLETE
Developer Diagnostics          ✅ COMPLETE
Database Foundation            ✅ COMPLETE
JWT Flow                       ✅ COMPLETE
User Persistence               ✅ COMPLETE

Route Guards                   ⏳ Pending
Session Persistence            ⏳ Pending
Request Logging                ⏳ Pending
React Admin Portal             ❌ Not Started

Week 1 Progress: ~70%
Ready to close Week 1 after remaining validation items.
```
