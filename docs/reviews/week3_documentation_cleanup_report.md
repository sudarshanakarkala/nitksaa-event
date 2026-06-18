# Week 3 — Documentation Cleanup Report

**Date:** 2026-06-18  
**Triggered by:** `docs/reviews/week3_final_signoff_review.md`  
**Scope:** Close OI-6, OI-7, OI-8, OI-9 — documentation only  
**Backend changes:** None  
**Flutter changes:** None

---

## Summary

The Week 3 final sign-off review identified four open issues in the documentation layer.
All four have been resolved. No code was modified.

---

## OI-7 — Resolved

**Issue:** `backend_week3_manual_verification_guide.md` UC-11 showed wrong field names in
`AlumniProfileResponse` example.

**Root cause:** Guide was written before schemas were finalised. The DB-to-API mapping
renames columns: `alumni_id → ref_id`, `graduationyear → batch_year`. The `registrationstatus`
column is computed server-side into `is_active` and never appears in any API response.

**Fix applied:**

| Before (incorrect) | After (correct) |
| --- | --- |
| `"alumni_id": "NITK2026IT001"` | `"ref_id": "NITK2026IT001"` |
| `"graduationyear": 2026` | `"batch_year": 2026` |
| `"registrationstatus": "Active"` | _(removed — not in API response)_ |
| _(missing)_ | `"phone": null` |

PASS criteria updated: removed `registrationstatus` bullet; added `ref_id` and `batch_year`
bullets; added explicit note that `registrationstatus` does not appear in any API response.

**File modified:** `docs/validation/backend_week3_manual_verification_guide.md` (UC-11 section)  
**Source of truth:** `backend/app/schemas/registrations.py` — `AlumniProfileResponse`

---

## OI-8 — Resolved

**Issue:** `backend_week3_manual_verification_guide.md` UC-01 and UC-02 showed `is_virtual`
as a top-level field in `RegistrationResponse`.

**Root cause:** `RegistrationResponse` has no top-level `is_virtual` field. It exists only
inside the nested `event: EventSummary` object. The guide examples were copied from a draft
schema that predated the nested `event` sub-object design.

**Fix applied — UC-01 (physical event):**

Before: flat response with `"is_virtual": false` at top level.  
After: top-level `is_virtual` removed; nested `event` object added with `"is_virtual": false`.

**Fix applied — UC-02 (virtual event):**

Before: flat response with `"is_virtual": true` at top level.  
After: top-level `is_virtual` removed; nested `event` object added with `"is_virtual": true`.

PASS criteria updated for both use cases: `event.is_virtual` bullet added; explicit note added
stating `is_virtual` is inside the nested `event` object, not at top level.

**File modified:** `docs/validation/backend_week3_manual_verification_guide.md` (UC-01, UC-02)  
**Source of truth:** `backend/app/schemas/registrations.py` — `RegistrationResponse`, `EventSummary`

---

## OI-9 — Resolved

**Issue:** `week3_status_report_2026-06-18.md` listed `week3_actual_api_response_shapes.md`
as a delivered documentation artifact, but the file did not exist in the repository.

**Fix:** Created `docs/api/week3_actual_api_response_shapes.md`.

**Content covers:**

| Endpoint | Shapes documented |
| --- | --- |
| `GET /api/v1/alumni/me` | Success (full + nullable variant); 401, 403, 404 errors |
| `GET /api/v1/events/{id}/registration-eligibility` | All 7 states (eligible, already_registered, full, closed, not_open_yet, ineligible × 2) |
| `POST /api/v1/events/{id}/register` | Success (physical + virtual); all 9 error codes |
| `GET /api/v1/events/{id}/my-registration` | Success; join_url visibility rules |
| `GET /api/v1/my/registrations` | Success (multi-item list); field notes |

Also includes the two-code cross-reference table (GET eligibility vs POST error codes) and
the schema source reference table pointing to exact file locations.

**File created:** `docs/api/week3_actual_api_response_shapes.md`  
**Status report updated:** `docs/releases/week3_status_report_2026-06-18.md` — Documentation
Cleanup Addendum section added

---

## OI-6 — Resolved

**Issue:** No documentation explained how to set up `alumni_db` for local development.
New developers had no guidance on the required table schema, column names, or sample data,
making it impossible to run the registration APIs locally without reading service source code.

**Fix:** Created `docs/GETTING_STARTED_WEEK3.md`.

**Content covers:**

- Prerequisites (PostgreSQL, Python, Flutter, Firebase)
- `events_db` creation and Alembic migration
- `alumni_db` manual creation — exact `CREATE TABLE` statement with correct column names
- Sample `INSERT` for a test alumni record
- Complete `.env` file template with all required variables
- Variable reference table (name, default, required flag, notes)
- Backend startup (`uvicorn`)
- Flutter startup with `DEV_DIAGNOSTICS_EMAIL` dart-define
- Test event INSERT for `events_db`
- End-to-end verification (curl commands for all 4 steps)
- Common problems and fixes (9 scenarios)
- Swagger UI location

**File created:** `docs/GETTING_STARTED_WEEK3.md`

---

## Files Modified

| File | Change |
| --- | --- |
| `docs/validation/backend_week3_manual_verification_guide.md` | 3 edits: UC-11 AlumniProfileResponse, UC-01 RegistrationResponse, UC-02 RegistrationResponse |
| `docs/releases/week3_status_report_2026-06-18.md` | Documentation Cleanup Addendum section added |

## Files Created

| File | Purpose | Resolves |
| --- | --- | --- |
| `docs/api/week3_actual_api_response_shapes.md` | Verbatim JSON payloads for all 5 endpoints | OI-9 |
| `docs/GETTING_STARTED_WEEK3.md` | Local dev setup guide including `alumni_db` | OI-6 |
| `docs/reviews/week3_documentation_cleanup_report.md` | This report | — |

---

## Remaining Open Issues

All four targeted OIs are resolved. The following issues from the sign-off review were
classified as Week 4 decisions and remain open by design:

| # | Issue | Classification |
| --- | --- | --- |
| OI-1 | `RegisterRequest` has no `confirm_profile` field | Week 4 UX decision |
| OI-2 | Eligibility response has no `event` or `my_registration` sub-objects | Week 4 UX decision |
| OI-4 | `GET /alumni/me` returns flat response (no `profile` wrapper) | Accepted deviation — no change needed |

No backend code changes. No Flutter changes. All open issues are Week 4 scope.

---

## Week 3 Closure Recommendation

**CLOSED.**

All Week 3 documentation now accurately reflects the running implementation:

- API response shapes match `backend/app/schemas/registrations.py`
- Field names match the DB-to-API mapping in `alumni_service.py` and `registration_service.py`
- Security rules (virtual_url protection, join_url visibility, email-after-commit) are correctly documented
- Local dev setup is documented end-to-end
- Verification guide examples are accurate

**Week 4 may proceed.**
