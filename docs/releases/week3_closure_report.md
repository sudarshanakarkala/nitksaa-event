# Week 3 Closure Report

**Date:** 2026-06-18  
**Team:** CAR SOFTWARE SYSTEMS  
**Branch:** main  
**Status:** CLOSED

---

## Summary

Week 3 goal: alumni can register for events, receive a confirmation email, and see their join link
for virtual events. A developer diagnostics system provides verifiable end-to-end validation of the
entire registration flow.

All goals achieved. The week ran in 4 phases:

| Phase | Title | Status |
|---|---|---|
| Phase 1 | Dependency review + schema verification | COMPLETE |
| Phase 2 | Backend foundation (5 endpoints, 3 services, 2 repositories) | COMPLETE |
| Phase 2B | Backend runtime verification (63 checks) | COMPLETE — 63/63 PASS |
| Phase 3 | Developer diagnostics registration category (13 checks) | COMPLETE |
| Phase 3B | Flutter UX prototype validation (15 use cases) | COMPLETE — ALL PASS |

---

## Week 3 Deliverables

### Backend — New Files

| File | Purpose |
|---|---|
| `backend/app/api/alumni.py` | `GET /api/v1/alumni/me` |
| `backend/app/api/registrations.py` | 4 registration endpoints |
| `backend/app/services/audit_service.py` | `emit()` — audit log writer, never raises |
| `backend/app/services/email_service.py` | Confirmation email, log + SMTP modes |

### Backend — Rewritten Files

| File | Reason |
|---|---|
| `backend/app/repositories/registration_repository.py` | Alpha-era code referenced missing `attendees` table and wrong columns |
| `backend/app/services/registration_service.py` | Alpha-era class referenced `RegistrationService`, `generate_qr_token`, wrong schema |
| `backend/app/schemas/registrations.py` | Alpha-era `AttendeeResponse`, wrong field names |

### Backend — Modified Files

| File | Change |
|---|---|
| `backend/app/config.py` | Added 8 email settings; added `extra = "ignore"` to `Settings.Config` |
| `backend/app/services/alumni_service.py` | Added `ACTIVE_ALUMNI_STATUSES`, `is_alumni_active()`, `get_alumni_profile_by_ref_id()` |
| `backend/app/repositories/events_repository.py` | Added live `registered_count` correlated subquery |
| `backend/app/services/events_service.py` | `d["registered_count"] = 0` → `d.setdefault("registered_count", 0)` |
| `backend/app/main.py` | Registered `alumni.router` and `registrations.router` |
| `backend/app/api/admin_events.py` | Removed broken alpha imports; stubbed admin endpoints as `501` |
| `backend/app/api/dev_diagnostics.py` | Added `GET /api/v1/dev/diagnostics/registrations` (13-check suite); 3 bugs fixed during verification |

### Flutter — Modified Files

| File | Change |
|---|---|
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Added `_RegistrationDiagnosticDetail` with 7 prototype sections, Event ID Picker, and Frontend Developer Reference Notes; field mapping corrected for flat API shapes |

### Documentation

| File | Content |
|---|---|
| `docs/reviews/week3_phase2_backend_foundation_report.md` | Phase 2 implementation detail |
| `docs/reviews/week3_phase2b_backend_runtime_verification_report.md` | 63-check curl verification results |
| `docs/reviews/week3_phase3_developer_diagnostics_report.md` | Diagnostics endpoint design and validation |
| `docs/reviews/week3_phase3b_registration_ux_prototype_validation_report.md` | Flutter UX prototype + all 15 UC results |
| `docs/releases/week3_readiness_review.md` | Go/no-go gate review |
| `docs/releases/week3_closure_report.md` | This file |
| `docs/api/events_api_contract_v2.md` | Updated API contract — actual shapes |

---

## Registration Flow — End-to-End Verified

```
Alumni logs in (Firebase + backend JWT)
  ↓
GET /api/v1/alumni/me
  → returns flat AlumniProfileResponse (fullname, email, phone, batch_year, branch, is_active)

GET /api/v1/events/{id}/registration-eligibility   [optional pre-check]
  → eligibility_status: eligible / already_registered / full / closed / not_open_yet / ineligible

POST /api/v1/events/{id}/register
  → SELECT ... FOR UPDATE on event (prevents race condition at capacity)
  → INSERT registration, UPDATE registration_number (within transaction)
  → COMMIT
  → send_confirmation_email() (post-commit, non-blocking)
  → update_email_status() (separate connection)
  → audit_service.emit() (never raises)
  → returns flat RegistrationResponse with embedded event sub-object

GET /api/v1/events/{id}/my-registration
  → same flat RegistrationResponse; join_url present only if virtual+published+registered

GET /api/v1/my/registrations
  → { registrations: [...], total: N }
  → per item: same flat RegistrationResponse; join_url at top level
```

---

## Security — All Invariants Closed

| Invariant | Verified by |
|---|---|
| `virtual_url` absent from public event API | Phase 2B Test 10 + Phase 3B Diagnostics check 13 |
| `join_url` absent from public event API | Phase 3B Public API Leak Verification |
| `join_url` only in authenticated reg responses, only when virtual+published+registered | Phase 2B Test 4 + Phase 3B UC-13 |
| Email failure does not rollback registration | Phase 2B Test 9 — DB snapshot shows committed row with email status field only |
| `emit()` never raises | Code: `try/except Exception` — no re-raise |
| Audit log context: no PII | Phase 2B — `context` contains `event_id` + `registration_number` only |

---

## Bugs Found and Fixed

### Runtime / Backend Bugs (Phase 2B, Phase 3)

| # | Bug | Root Cause | Fix |
|---|---|---|---|
| B-1 | App startup fails — `ValidationError: Extra inputs are not permitted` | `Settings` used `extra="forbid"` (pydantic default); `.env` contained `DEV_DIAGNOSTICS_*` vars | Added `extra = "ignore"` to `Settings.Config` |
| B-2 | `alumni_db` database missing locally | Cloud SQL db not provisioned for local dev | Created local `alumni_db`, inserted test records, added `ALUMNI_DB_URL` to `.env` |
| B-3 | Diagnostics endpoint 500 — FK violation on capacity filler | Synthetic `firebase_uid` had no matching `event_users` row; `registrations.firebase_uid` FK to `event_users` | Insert temp `event_users` row before filler registration; delete in `finally` |
| B-4 | Diagnostics audit log check FAIL — `column "audit_id" does not exist` | Wrong PK column name; actual column is `log_id` | Changed `SELECT audit_id` to `SELECT log_id` |
| B-5 | Diagnostics audit log check FAIL — type mismatch | `str(registration_id)` passed to integer-typed asyncpg param | Removed `str()` cast |

### Flutter Bugs (Phase 3B)

| # | Bug | Root Cause | Fix |
|---|---|---|---|
| B-6 | All 5 prototype sections show placeholder after successful API call | Prototype widgets used nested response paths from contract v1 — actual API is flat | Updated all field paths in `_alumniAutofillProto`, `_eligibilityProto`, `_registerProto`, `_confirmationProto`, `_myRegistrationProto`, `_registrationListCard` |

---

## What Worked Well

- Transaction safety design (SELECT FOR UPDATE) prevented capacity race condition
- Email-after-commit policy cleanly separates registration success from email delivery
- `_resolve_join_url()` as a single central function for join link security — easy to audit
- Developer diagnostics approach: running 13 real API calls with real test data is far more reliable
  than mocking; found 5 real bugs that mocks would have hidden
- Phase 3B prototype sections gave the Flutter developer an exact visual and data reference before
  any production code was written

---

## What to Watch in Week 4

1. **OI-3 — eligibility_status values.** The service returns `full`, `closed`, `not_open_yet`,
   `ineligible`. The original contract doc said `event_full`, `registration_closed`, etc. The Flutter
   developer writing the production eligibility UI must use the v2 contract values, not v1.

2. **OI-2 — Eligibility endpoint missing event context.** The eligibility response has no `event`
   sub-object and no `my_registration`. The frontend currently needs a second GET for event details.
   Consider adding this in Week 4 if the UX flow requires it.

3. **ALUMNI_DB_URL in local dev.** Any new developer or new machine will fail alumni flows until
   they create `alumni_db` locally or point `ALUMNI_DB_URL` at the staging database.

4. **Admin endpoints are stubs.** `admin_events.py` registration and attendee endpoints return `501`.
   Do not build admin UI expecting these to work until they are implemented.

---

## Validation Summary

| Gate | Result |
|---|---|
| `python -m compileall app` | 40 files, 0 errors |
| App loads + routes registered | 37 routes, 0 import errors |
| Phase 2B runtime verification | 63/63 PASS |
| Phase 3 diagnostics endpoint | 13/13 PASS |
| Phase 3B use case verification | 15/15 PASS |
| `flutter analyze` | 0 issues |
| `flutter test` | 16/16 passed |

---

## Open Issues at Closure

| # | Issue | Severity |
|---|---|---|
| OI-1 | `RegisterRequest` — no `confirm_profile` field (contract v1 specified it) | Low |
| OI-2 | Eligibility response has no `event` or `my_registration` sub-objects | Medium |
| OI-3 | `eligibility_status` string values differ from contract v1 | Medium |
| OI-4 | `GET /alumni/me` — flat response, no `{status:ok, alumni:{...}}` wrapper | Low |
| OI-5 | `ListTile` / `DecoratedBox` assertion in event list screen (debug, pre-existing) | Low |
| OI-6 | `ALUMNI_DB_URL` local setup not documented | Medium |

All open issues are documentation/design clarifications. None block production functionality.

---

## Not Built (Correctly Deferred)

| Item | Reason deferred |
|---|---|
| Production Flutter registration screen | Week 4 scope; prototype complete as reference |
| Production my-registrations screen | Week 4 scope |
| Production confirmation screen | Week 4 scope |
| Admin registration management UI | Not scoped for Week 3 or 4 |
| Attendance / QR / waitlist / payment | Not scoped |

---

## Week 3 Status: CLOSED — ALL DELIVERABLES COMPLETE

**GO for Week 4.**
