# Week 4 Phase 1 — Production Readiness Verification

**Date:** 2026-06-22
**Phase:** Week 4 Phase 1
**Status:** COMPLETE

---

## Scope

Phase 1 addressed six production readiness items identified in the Week 4 pre-development review.
No new features were implemented. No API contracts were changed. No migrations were created.

---

## Item 1 — Real Email Delivery Readiness

**Goal:** Document and verify that `EMAIL_MODE=send` can be configured for real SMTP delivery.

**Changes:**
- `backend/.env.example` — added `ALUMNI_DB_URL`, `EMAIL_MODE`, and all SMTP variables with
  inline comments explaining when each is required
- `backend/README.md` — added "Email Setup" section documenting Gmail App Password requirement,
  `EMAIL_MODE` toggle, and test instructions

**Verification:**
- `app/config.py` already defines `email_mode`, `smtp_user`, `smtp_password`, `smtp_host`,
  `smtp_port`, `email_from`, `email_reply_to` — all wired; no config changes needed
- `.env.example` now reflects all configurable email variables
- `EMAIL_MODE=log` remains the default; no accidental email sends possible in dev

**Status:** DONE

---

## Item 2 — Email Event-Loop Blocking Fix

**Goal:** Remove synchronous `smtplib.SMTP` calls from the async event loop in
`send_confirmation_email()`.

**File changed:** `backend/app/services/email_service.py`

**Changes:**
- Added `import asyncio`
- Extracted SMTP block to `_send_smtp_sync(msg_string, smtp_host, smtp_port, smtp_user,
  smtp_password, from_addr, email_to)` — a plain synchronous function with no async context
- Replaced the inline `with smtplib.SMTP(...) as smtp:` block with:
  ```python
  await asyncio.to_thread(
      _send_smtp_sync,
      msg.as_string(), settings.smtp_host, settings.smtp_port,
      settings.smtp_user, settings.smtp_password, from_addr, email_to,
  )
  ```
- All exceptions from `asyncio.to_thread` are caught by the existing `except Exception as exc`
  block — no new error path introduced

**Before:** `smtplib.SMTP` (synchronous TCP + TLS handshake) ran on the asyncio event loop
thread, blocking all concurrent requests during email delivery.

**After:** SMTP I/O runs in a thread pool worker via `asyncio.to_thread`. The event loop is
never blocked regardless of SMTP latency or timeout.

**Status:** DONE

---

## Item 3 — Plain Text Email Fallback

**Goal:** Add a `text/plain` part to the confirmation email so clients that do not render HTML
(e.g., corporate mail filters, screen readers, plain-text mail clients) receive readable content.

**File changed:** `backend/app/services/email_service.py`

**Changes:**
- Added `_build_plain(fullname, event_title, registration_number, join_url)` — returns a
  plain-text version of the confirmation with the same information as the HTML template
- In `send_confirmation_email()`, attached plain text before HTML:
  ```python
  msg.attach(MIMEText(_build_plain(...), "plain"))
  msg.attach(MIMEText(_build_html(...), "html"))
  ```

**Why order matters:** `MIMEMultipart("alternative")` requires the plain text part to be
attached before the HTML part. RFC 2046 specifies that the last part in an `alternative`
multipart is the preferred representation. Mail clients display the HTML part when capable,
plain text otherwise.

**Before:** `MIMEMultipart("alternative")` had only the HTML part. Plain-text clients displayed
raw HTML source.

**After:** All clients receive readable content.

**Status:** DONE

---

## Item 4 — Alumni DB Local/Staging Setup Documentation

**Goal:** Document how to create and configure `alumni_db` locally so developers can run alumni
eligibility checks without connecting to production data.

**Files changed:**
- `backend/.env.example` — added `ALUMNI_DB_URL` with explanatory comment
- `backend/README.md` — added "alumni_db Local Setup" section with:
  - Explanation of dual-database architecture (`events_db` + `alumni_db`)
  - Graceful degradation note (backend runs without alumni_db for non-eligibility tasks)
  - `createdb alumni_db` command
  - Minimal seed SQL for local testing (two test alumni profiles)
  - Staging configuration guidance

**Verification:**
- `app/config.py` already defines `alumni_db_url` and `alumni_db_dsn` — wired but undocumented
- Memory note `project_alumni_db_local.md` confirmed this was a known undocumented gap
- No schema migration created — alumni_db schema is owned by `nitksaa-portal-v2`

**Status:** DONE

---

## Item 5 — Login Page Message Cleanup

**Goal:** Remove implementation-internal strings ("Firebase", "Backend session validated") from
user-facing status messages on the login screen.

### 5a — Login Screen (`apps/event_app/lib/features/auth/presentation/screens/login_screen.dart`)

**Changes:**

| Location | Before | After |
|---|---|---|
| `_runLogin()` initial status | `'Signing in with Firebase...'` | `'Signing in...'` |
| `_runLogin()` success status | `'Backend session validated. Opening diagnostics...'` or `'Backend session validated. Opening home...'` | `'Signed in successfully.'` |

The success status message is visible for approximately 200–400ms before navigation occurs.
The simplified message is consistent for both admin (diagnostics) and standard (home) routing.

### 5b — Auth Controller (`apps/event_app/lib/features/auth/services/auth_controller.dart`)

**Changes in `_friendlyAuthError()`:**

Added three previously unmapped Firebase error codes:

| Code | User-facing message |
|---|---|
| `too-many-requests` | `'Too many attempts. Please wait a moment and try again.'` |
| `network-request-failed` | `'A network error occurred. Check your connection and try again.'` |
| `popup-blocked` | `'Sign-in popup was blocked. Please allow popups and try again.'` |

Fixed the catch-all and non-Firebase fallback:

| Path | Before | After |
|---|---|---|
| `FirebaseAuthException` catch-all | `error.message ?? 'Firebase authentication failed.'` | `'Sign in failed. Please try again or use Google Sign-In.'` |
| Non-`FirebaseAuthException` fallback | `error.toString()` (exposes raw exception) | `'Sign in failed. Please try again.'` |

**Before:** Unknown Firebase error codes and non-Firebase exceptions surfaced raw SDK messages or
Dart exception strings to the user.

**After:** All error paths produce a user-friendly message. Raw SDK strings never reach the UI.

**Status:** DONE

---

## Item 6 — Stale "Coming in Week 3" Text

**Goal:** Remove the stale placeholder text in `RegistrationsPage.jsx`. Registration APIs were
built in Week 3; the text implied they were not yet implemented.

**File changed:** `admin/event_admin/src/pages/RegistrationsPage.jsx`

**Changes:**

| Element | Before | After |
|---|---|---|
| Page eyebrow | `Coming in Week 3` | `Week 4` |
| Page subtitle | `...will be implemented in Week 3...` | `Registration backend is live. Admin UI...coming in Week 4.` |
| Notice text | `Registration APIs will be implemented in Week 3...` | `Registration APIs are live (Week 3). This page will display...coming in Week 4.` |
| Section heading | `Planned APIs` | `Live APIs` |

**Status:** DONE

---

## Files Changed

| File | Change type |
|---|---|
| `backend/app/services/email_service.py` | Modified — asyncio.to_thread, plain text part, _build_plain() |
| `backend/.env.example` | Modified — added ALUMNI_DB_URL and email variables |
| `backend/README.md` | Modified — alumni_db setup section, email setup section |
| `apps/event_app/lib/features/auth/presentation/screens/login_screen.dart` | Modified — status message cleanup |
| `apps/event_app/lib/features/auth/services/auth_controller.dart` | Modified — error code expansion, catch-all fix |
| `admin/event_admin/src/pages/RegistrationsPage.jsx` | Modified — stale placeholder text |

---

## Files Created (Phase 1 docs)

| File | Description |
|---|---|
| `docs/architecture/event_duration_architecture_v1.md` | Full-day and multi-day event schema design |
| `docs/architecture/meeting_provider_architecture_v1.md` | Zoom/Meet/Teams OAuth integration design |
| `docs/reviews/week4_phase1_production_readiness_verification.md` | This document |

---

## What Was Not Changed

Per Phase 1 scope, the following were explicitly excluded:

- No attendee management implementation
- No Flutter registration UI changes
- No `event_people` / `session_people` schema or backend changes
- No `event_sponsors` / `event_partners` schema or backend changes
- No analytics implementation
- No engagement rewards implementation
- No paid events or payment gateway integration
- No meeting provider OAuth implementation
- No full-day event migration
- No Week 1–3 API contracts modified
- No existing migration files modified

---

## Open Items Carried Forward

These items from `week3_readiness_review.md` remain open and are not addressed in Phase 1:

| ID | Item |
|---|---|
| OI-1 | Admin attendee management UI (list + export) |
| OI-2 | Flutter registration UI (register CTA, confirmation screen) |
| OI-3 | Event people/speakers schema and API wiring |
| OI-4 | `event_audit_log` query endpoint for admin |
| OI-5 | Email delivery monitoring (distinguish log-mode from real send in health checks) |
| OI-6 | Registration capacity race condition test under concurrent load |
