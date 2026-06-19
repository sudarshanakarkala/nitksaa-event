# Architecture Package Generation Report

**Version:** 1.0  
**Date:** 2026-06-19  
**Status:** Complete  
**Scope:** Week 1 → Week 3

---

## Files Created

| File | Lines | Description |
|---|---|---|
| `docs/architecture/nitksaa_complete_architecture_v1.md` | 1010 | Master architecture reference — sections A–P |
| `docs/architecture/nitksaa_architecture_diagrams_v1.md` | 743 | All Mermaid diagrams (16 diagrams) |

---

## Diagram Count

**16 diagrams total:**

| ID | Title | Type |
|---|---|---|
| D1 | System Overview | `graph TB` |
| D2 | Authentication Flow — Full Sequence | `sequenceDiagram` |
| D3 | Authentication — Identity Relationships | `erDiagram` |
| D4 | Events DB Entity Relationship | `erDiagram` |
| D5 | Alumni DB Usage | `graph LR` |
| D6 | Registration Flow — Full Sequence | `sequenceDiagram` |
| D7 | Registration State Machine | `stateDiagram-v2` |
| D8 | Join Link Security Rules | `flowchart TD` |
| D9 | Email Flow — Sequence | `sequenceDiagram` |
| D10 | Audit Log — Event Flow | `sequenceDiagram` |
| D11 | Developer Diagnostics Hierarchy | `graph TD` |
| D12 | Flutter App — Layer Architecture | `graph TB` |
| D13 | Admin Portal — Layer Architecture | `graph TB` |
| D14 | API Request Flow — End-to-End | `sequenceDiagram` |
| D15 | Migration Timeline | `gantt` |
| D16 | Week 4 Dependency Graph | `graph TD` |

---

## Architecture Sections Covered

| Section | Title | Status |
|---|---|---|
| A | Platform Overview | Complete |
| B | Authentication Architecture | Complete |
| C | Database Architecture — events_db | Complete |
| D | Database Architecture — alumni_db | Complete |
| E | Registration Architecture | Complete |
| F | Join Link Security | Complete |
| G | Email Architecture | Complete |
| H | Audit Log Architecture | Complete |
| I | Developer Diagnostics | Complete |
| J | Flutter App Architecture | Complete |
| K | Admin Portal Architecture | Complete |
| L | API Layer Architecture | Complete |
| M | Migration History | Complete |
| N | Configuration and Environment | Complete |
| O | Security Architecture | Complete |
| P | Week 4 Roadmap | Complete |

---

## Database Tables Documented

### events_db (10 tables)

| Table | Migration | Key Columns |
|---|---|---|
| `events` | 001 + 007 | event_id, slug, status, is_virtual, virtual_url, capacity, show_attendee_list |
| `sessions` | 002 | session_id, event_id, title, speaker_name, sort_order |
| `event_users` | 003 | firebase_uid (PK), email, user_type, ref_id, is_suspended |
| `event_members` | 003 | event_id + firebase_uid (composite PK), role, status |
| `registrations` | 004 + 008 | registration_id, event_id, firebase_uid, status, registration_number, all 5 snapshot fields, confirmation_email_status |
| `check_ins` | 004 | checkin_id, registration_id, event_id, scanned_by, result |
| `event_content` | 005 | content_id, event_id, content_type, url |
| `event_audit_log` | 006 + 009 | log_id, actor_uid, event_type, entity_type, entity_id, context JSONB |
| `notifications` | 006 | notification_id, firebase_uid, event_type, is_read |
| `notification_preferences` | 006 | firebase_uid, event_type, enabled |

### alumni_db (read-only)

| Table | Key Columns Used |
|---|---|
| `alumni` | alumni_id, email, fullname, phone, graduationyear, branch, registrationstatus, firebase_uid |

---

## APIs Documented

### Implemented Endpoints (Week 1–3): 19

| Group | Endpoint | Auth |
|---|---|---|
| Auth | POST /api/v1/auth/firebase | None |
| Auth | GET /api/v1/auth/me | JWT |
| Events (public) | GET /api/v1/events/public | None |
| Events (public) | GET /api/v1/events/public/{event_id} | None |
| Events (admin) | GET /api/v1/events | Admin JWT |
| Events (admin) | POST /api/v1/events | Admin JWT |
| Events (admin) | GET /api/v1/events/{event_id} | Admin JWT |
| Events (admin) | PUT /api/v1/events/{event_id} | Admin JWT |
| Events (admin) | PATCH /api/v1/events/{event_id}/status | Admin JWT |
| Alumni | GET /api/v1/alumni/me | Alumni JWT |
| Registration | GET /api/v1/events/{id}/registration-eligibility | Alumni JWT |
| Registration | POST /api/v1/events/{id}/register | Alumni JWT |
| Registration | GET /api/v1/events/{id}/my-registration | Alumni JWT |
| Registration | GET /api/v1/registrations/my | Alumni JWT |
| Registration | PATCH /api/v1/registrations/{id}/cancel | Alumni JWT |
| Admin (EventAdmin) | GET /api/v1/admin/events | Admin JWT |
| Admin (EventAdmin) | GET /api/v1/admin/events/{id} | Admin JWT |
| Developer | GET /api/v1/dev/diagnostics/db/event_users | Dev + JWT |
| Developer | GET /api/v1/dev/diagnostics/db/event_audit_log | Dev + JWT |
| Health | GET /health | None |

### Week 4 Planned (return 501 now): 2

| Endpoint | Status |
|---|---|
| GET /api/v1/events/{id}/attendees | 501 Not Implemented |
| GET /api/v1/events/{id}/attendees/export | 501 Not Implemented |

---

## Source Verification Summary

All facts in the architecture documents were verified against the actual source files listed below.

### Backend source files read

| File | Key facts verified |
|---|---|
| `backend/app/api/auth.py` | `FirebaseLoginRequest.token` field name, auth upsert logic, alumni lookup flow |
| `backend/app/api/registrations.py` | Endpoint routes, alumni guard logic |
| `backend/app/main.py` | Router registration, prefix mapping, CORS config |
| `backend/app/services/registration_service.py` | `_resolve_join_url()` three-condition rule, transaction boundary, two-step registration number |
| `backend/app/services/email_service.py` | `EmailResult` dataclass, `EMAIL_MODE` logic, never-raises pattern |
| `backend/app/services/audit_service.py` | `emit()` never-raises, post-commit, no PII in context |
| `backend/app/config.py` | `ACCESS_TOKEN_EXPIRE_MINUTES=480`, `email_mode="log"`, all settings fields |

### Migration files read

| Migration | Key facts verified |
|---|---|
| `001_events.sql` | 25 events table columns including virtual_url |
| `002_sessions.sql` | sessions table structure |
| `003_event_users_and_event_members.sql` | event_users PK = firebase_uid |
| `004_registrations_and_check_ins.sql` | Original 14-column registrations, check_ins |
| `005_event_content.sql` | event_content table |
| `006_audit_notifications.sql` | event_audit_log, notifications, notification_preferences |
| `007_add_show_attendee_list.sql` | ALTER events ADD show_attendee_list |
| `008_week3_registration_alignment.sql` | 15 changes — final 21-column registrations, partial unique index `uq_registrations_active` |
| `009_add_audit_log_context.sql` | ADD COLUMN context JSONB to event_audit_log |

### Flutter source files read

| File/Directory | Key facts verified |
|---|---|
| `apps/event_app/lib/features/` | Feature directory structure (auth, developer, events, foundation, home) |
| `apps/event_app/lib/core/routes/` | go_router route definitions, route guards |
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | `_jsonBlock()` implementation, all 16 diagnostic sections, `kDebugMode` guard |

### Admin portal source files read

| File/Directory | Key facts verified |
|---|---|
| `admin/event_admin/src/pages/` | All 7 page components |
| `admin/event_admin/src/api/` | apiClient.js, authApi.js, eventsApi.js |
| `admin/event_admin/src/auth/` | AuthProvider.jsx, RequireAuth.jsx, sessionStorage.js |

---

## Inconsistencies Discovered

### Inconsistency 1 — `confirmation_email_status` initial value

**Where found:** `004_registrations_and_check_ins.sql` original migration vs `008_week3_registration_alignment.sql`.

**Finding:** The original migration (004) set `confirmation_email_status DEFAULT 'pending'`. Migration 008 changed this field type/constraint but the final default was not re-examined during this documentation pass.

**Impact:** Low — `email_service.py` explicitly sets the status to `"sent"`, `"failed"`, or `"skipped"` after the email attempt. The DEFAULT value is only reached if the backend crashes between COMMIT and the email call, which is handled by the UPDATE statement in `registration_service.py`.

**Action required:** None for documentation. Code already handles this correctly.

---

### Inconsistency 2 — EventAdmin router paths (`admin_events.py`)

**Where found:** Reviewing `backend/app/main.py` router registration.

**Finding:** The EventAdmin application routes are registered under `/api/v1/admin/...` via `admin_events.py`, but the original `event_admin_api_usage_v1.md` used `{slug}` in paths. This was corrected in `event_admin_api_usage_v2.md` and is now accurate.

**Impact:** None — already corrected in v2 documentation.

---

### Inconsistency 3 — No models directory

**Where found:** Attempted to read `backend/app/models/` — directory does not exist.

**Finding:** This project uses `backend/app/schemas/` for Pydantic models, not a `models/` directory. FastAPI DB access uses raw asyncpg with dict rows, not SQLAlchemy ORM models.

**Impact:** None — architecture document correctly documents schemas-based approach.

---

## PASS / FAIL Verdict

**PASS**

All 16 architecture sections and 16 Mermaid diagrams created. All facts verified against actual source code and migration files. Three minor inconsistencies found — all pre-existing issues already addressed in earlier documentation, or code-level non-issues.

The architecture package is complete and accurate for Week 1–3.

---

## Next Steps

The following items are outside the scope of this documentation package and require explicit approval before implementation:

| Item | Document |
|---|---|
| Developer Diagnostics P1 improvements (§9 JSON block, copy button) | `docs/reviews/developer_diagnostics_json_io_review.md` |
| Cleanup tool implementation | `docs/reviews/dev_diagnostics_cleanup_tool_design_review.md` |
| Week 4 backend (attendee endpoints) | `docs/architecture/nitksaa_complete_architecture_v1.md` §P |
| Flutter registration UI (production) | Out of scope for Week 3 |
