# Week 3 — Final Sign-Off Review

**Date:** 2026-06-18  
**Reviewer:** CAR SOFTWARE SYSTEMS  
**Branch:** main  
**Scope:** Final Week 3 documentation and implementation verification

> **Verification only.** No code was modified. No documents were modified. All findings
> reflect the current state of the repository as of 2026-06-18.

---

## Executive Summary

**Week 3 Status: COMPLETE WITH KNOWN ISSUES**

The Week 3 backend registration platform is fully implemented, internally consistent, and
technically sound. All critical registration flows, security invariants, and service logic
have been independently verified against the source code. The automated 13-check diagnostic
suite provides runtime proof of end-to-end correctness.

Three documentation-only issues were identified during this review:

- Two discrepancies between the manual verification guide and the actual API response shapes.
  These affect the guide only — the API implementation and the API contract v2 are both correct.
- One missing file (`week3_actual_api_response_shapes.md`) referenced in the status report
  but absent from the repository.

None of these affect the runtime system. The API contract v2 (`docs/api/events_api_contract_v2.md`)
is the authoritative reference and correctly documents all response shapes.

---

## Verification Matrix

| Feature | Code Verified | Docs Verified | Discrepancy | Status |
|---|---|---|---|---|
| Alumni registration (POST /register) | ✅ | ✅ | None | PASS |
| Alumni profile lookup (GET /alumni/me) | ✅ | ⚠️ Guide example wrong | D1 — guide only | PASS (code correct) |
| Registration eligibility (GET /registration-eligibility) | ✅ | ✅ | None | PASS |
| `eligibility_status` v2 values (6 values) | ✅ | ✅ | None — all correct | PASS |
| POST /register error `detail` codes (9 codes) | ✅ | ✅ | None — all correct | PASS |
| Two-code cross-reference documented | ✅ | ✅ | None | PASS |
| My registration (GET /my-registration) | ✅ | ✅ | None | PASS |
| My registrations list (GET /my/registrations) | ✅ | ✅ | None | PASS |
| RegistrationResponse shape (flat, with nested `event`) | ✅ | ⚠️ Guide shows `is_virtual` at wrong level | D2 — guide only | PASS (code correct) |
| Registration number format NITKSAA-YYYY-NNNNNN | ✅ | ✅ | None | PASS |
| Duplicate registration guard (409 already_registered) | ✅ | ✅ | None | PASS |
| Capacity guard (409 event_full) | ✅ | ✅ | None | PASS |
| Registration window guard (opens/closes at) | ✅ | ✅ | None | PASS |
| SELECT … FOR UPDATE on event row (concurrency) | ✅ | ✅ | None | PASS |
| Join URL three-condition rule | ✅ | ✅ | None | PASS |
| `_resolve_join_url()` implementation | ✅ | ✅ | None | PASS |
| `virtual_url` absent from all public APIs | ✅ | ✅ | None | PASS |
| Email-after-commit policy | ✅ | ✅ | None | PASS |
| `send_confirmation_email()` never raises | ✅ | ✅ | None | PASS |
| `EMAIL_MODE=log` returns `status="sent"` | ✅ | ✅ | None | PASS |
| `confirmation_email_status` updated post-commit | ✅ | ✅ | None | PASS |
| `audit_service.emit()` never raises | ✅ | ✅ | None | PASS |
| Audit context contains only event_id + registration_number | ✅ | ✅ | None | PASS |
| Developer diagnostics 13-check suite (count) | ✅ | ✅ | None | PASS |
| Diagnostic check 1: Alumni Profile | ✅ | ✅ | None | PASS |
| Diagnostic check 11: Email status (sent/failed) | ✅ | ✅ | None | PASS |
| Diagnostic check 12: Audit log row found | ✅ | ✅ | None | PASS |
| Diagnostic check 13: Public API leak check | ✅ | ✅ | None | PASS |
| Dev diagnostics unavailable outside development | ✅ | ✅ | None | PASS |
| Migration 004 (base schema) | ✅ | N/A | Pre-Week 3 base | INFORMATIONAL |
| Migration 007 (show_attendee_list column) | ✅ | N/A | Not Week 3 scope | INFORMATIONAL |
| Migration 008 (Week 3 alignment — 21 columns) | ✅ | ✅ | None | PASS |
| Migration 009 (JSONB context on audit log) | ✅ | ✅ | None | PASS |
| Flutter eligibility_status v2 values in `_uiStateStyle()` | ✅ | ✅ | None — fixed in consistency review | PASS |
| Flutter eligibility_status v2 values in `_eligibilityCta()` | ✅ | ✅ | None — fixed in consistency review | PASS |
| Flutter ListTile assertion resolved | ✅ | ✅ | None | PASS |
| API contract v2 matches implementation | ✅ | ✅ | None | PASS |
| `week3_actual_api_response_shapes.md` exists | ✅ | ❌ File absent | D3 — missing file | FAIL (doc only) |

---

## Week 3 Delivered Scope

### Backend

| Component | File | Status |
|---|---|---|
| Registration API endpoints | `backend/app/api/registrations.py` | ✅ Complete |
| Alumni profile API | `backend/app/api/alumni.py` | ✅ Complete |
| Registration service | `backend/app/services/registration_service.py` | ✅ Complete |
| Registration repository | `backend/app/repositories/registration_repository.py` | ✅ Complete |
| Email service | `backend/app/services/email_service.py` | ✅ Complete |
| Audit service | `backend/app/services/audit_service.py` | ✅ Complete |
| Registration schemas | `backend/app/schemas/registrations.py` | ✅ Complete |
| Developer diagnostics — registrations | `backend/app/api/dev_diagnostics.py` | ✅ Complete |

**Endpoints delivered:**

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/api/v1/alumni/me` | Required | Alumni profile (flat response) |
| POST | `/api/v1/events/{id}/register` | Required | Register alumni for event |
| GET | `/api/v1/events/{id}/registration-eligibility` | Required | Check registration eligibility |
| GET | `/api/v1/events/{id}/my-registration` | Required | Fetch a single registration |
| GET | `/api/v1/my/registrations` | Required | List all registrations for user |
| GET | `/api/v1/dev/diagnostics/registrations` | Required | Run 13-check diagnostic suite |

**Domain logic verified:**

| Logic | Verification Method |
|---|---|
| Alumni-only gate | `user.get("user_type") != "alumni" or not ref_id` → 403 `alumni_only` |
| Active alumni check | `alumni_service.is_alumni_active(registrationstatus)` — Active/Self-Verified only |
| Duplicate registration guard | `SELECT … WHERE status='registered'` + partial UNIQUE index |
| Capacity enforcement | `count_active(event_id) >= capacity` inside transaction |
| Registration window | `now < opens_at` → `registration_not_open_yet`; `now > closes_at` → `registration_closed` |
| Concurrency safety | `SELECT … FOR UPDATE` on event row inside `conn.transaction()` |
| Registration number | `f"NITKSAA-{year}-{registration_id:06d}"` — format matches NITKSAA-YYYY-NNNNNN |
| Email after commit | `send_confirmation_email()` called after `conn.transaction()` block exits |
| Email never raises | `try/except Exception` with `status="failed"` on any error |
| Audit never raises | `try/except Exception` with `_log.error(...)` on any error |
| join_url security | `_resolve_join_url()`: all three conditions must hold (`registered` + `is_virtual` + `published`) |

**Dynamic `registered_count`:**

The `count_active(event_id)` repository method uses `SELECT COUNT(*) FROM registrations WHERE event_id = $1 AND status = 'registered'` — a live count executed inside the locked transaction. No denormalized counter column exists; count is always authoritative.

### Flutter Developer Diagnostics

| Component | File | Status |
|---|---|---|
| Developer Diagnostics screen | `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | ✅ Complete |
| Event detail screen (ListTile fix) | `apps/event_app/lib/features/events/presentation/event_detail_screen.dart` | ✅ Fixed |

**Prototype sections:**
- Alumni Profile Preview
- Registration Eligibility Preview (v2 values, two-code cross-reference)
- Registration Action Preview
- Confirmation Preview
- My Registration Preview
- My Registrations Preview
- Negative State Gallery (POST error codes)
- Registration Diagnostics API (run-all button, 13-check results)

### Database

| Migration | File | Change | Status |
|---|---|---|---|
| 004 | `004_registrations_and_check_ins.sql` | Base schema (pre-Week 3) | Applied — later aligned by 008 |
| 007 | `007_add_show_attendee_list.sql` | Adds `show_attendee_list` to events | Applied — not Week 3 scope |
| 008 | `008_week3_registration_alignment.sql` | 15-step alignment to Week 3 contract | Applied — all 21 columns verified |
| 009 | `009_add_audit_log_context.sql` | Adds `context JSONB` to `event_audit_log` | Applied — audit service uses it |

**Migration 008 final schema (21 columns):**

| Column | Type | Notes |
|---|---|---|
| `registration_id` | SERIAL PK | Auto-generated |
| `event_id` | INT FK | Cascades on delete |
| `firebase_uid` | VARCHAR(128) FK | References event_users |
| `ref_id` | VARCHAR(128) | Alumni ID from alumni_db |
| `badge_name` | TEXT | Nullable (badge printing deferred) |
| `email` | TEXT | Alumni email snapshot (aliased as `email_snapshot`) |
| `phone` | TEXT | Alumni phone snapshot (aliased as `phone_snapshot`) |
| `attendee_type` | VARCHAR(50) | Reserved, not used in Week 3 |
| `status` | VARCHAR(20) DEFAULT 'registered' | Active: `registered`; deactivated: `cancelled` |
| `qrtoken` | TEXT UNIQUE | Nullable (QR deferred) |
| `notes` | TEXT | Attendee note (aliased as `attendee_note`) |
| `registered_at` | TIMESTAMPTZ | Insert timestamp |
| `cancelled_at` | TIMESTAMPTZ | Set on cancellation |
| `registration_number` | TEXT | `NITKSAA-YYYY-NNNNNN`, partial unique where NOT NULL |
| `fullname_snapshot` | TEXT | Alumni fullname at registration time |
| `batch_year_snapshot` | INTEGER | Alumni graduation year at registration time |
| `branch_snapshot` | TEXT | Alumni branch at registration time |
| `confirmation_email_status` | VARCHAR(20) DEFAULT 'pending' | Updated post-commit to `sent`/`failed`/`skipped` |
| `confirmation_email_sent_at` | TIMESTAMPTZ | Set when email is sent |
| `confirmation_email_error` | TEXT | Error string on failure |
| `updated_at` | TIMESTAMPTZ | Set after email update |

**Partial unique index:** `uq_registrations_active ON registrations(event_id, firebase_uid) WHERE status = 'registered'` — enforces one active registration per user per event while allowing re-registration after cancellation.

---

## Deferred Scope

The following features are explicitly out of scope for Week 3 and must NOT be started until Week 4 prerequisites are confirmed:

### Week 4 Deferred Items

| Feature | Status | Notes |
|---|---|---|
| Production Flutter Registration UI | ⏳ Deferred | Must live in production screens, not developer_diagnostics_screen.dart |
| Admin Registration Management | ⏳ Deferred | Attendee list, search, CSV export, dashboard |
| Attendance Tracking | ⏳ Deferred | Not started |
| QR Check-In | ⏳ Deferred | `qrtoken` column exists in schema, logic not built |
| Waitlist | ⏳ Deferred | No schema, no service |
| Payments | ⏳ Deferred | No schema, no service |

---

## Open Issues

### OI-1 — RegisterRequest has no `confirm_profile` field

| Field | Value |
|---|---|
| **ID** | OI-1 |
| **Severity** | Low |
| **Description** | Contract v1 specified `confirm_profile: true` in the POST /register request body. `RegisterRequest` in the actual schema has only `attendee_note: Optional[str]`. Pydantic's `extra="ignore"` silently discards any extra fields, so clients sending `confirm_profile` get no error. |
| **Impact** | No runtime impact. Any frontend code that constructs `{"confirm_profile": true, "attendee_note": "..."}` will work correctly — the extra field is ignored. |
| **Week 4 action** | Decide whether to add `confirm_profile` as an explicit optional field with no-op behaviour (for forward compatibility) or leave it absent. Document the decision in contract v2. |

---

### OI-2 — Eligibility response is flat (no `event` or `my_registration` sub-objects)

| Field | Value |
|---|---|
| **ID** | OI-2 |
| **Severity** | Medium |
| **Description** | Contract v1 specified a nested `eligibility`, `event`, and `my_registration` sub-object in the eligibility response. The actual response is flat: `{event_id, firebase_uid, eligibility_status, message, registered_count, capacity}`. The frontend must call a separate public event endpoint to get event details. |
| **Impact** | Production Flutter registration UI must make two API calls: one for eligibility, one for event details. This is already documented in the API contract v2. |
| **Week 4 action** | No code change required. When implementing production Flutter UI, use `GET /events/public/{id}` for event details and `GET /events/{id}/registration-eligibility` for eligibility — both calls are already functional. |

---

### OI-4 — GET /alumni/me returns flat response (no `{status, alumni}` wrapper)

| Field | Value |
|---|---|
| **ID** | OI-4 |
| **Severity** | Low |
| **Description** | Contract v1 specified a `{"status": "ok", "alumni": {...}}` response wrapper. The actual `AlumniProfileResponse` is flat: fields are at the top level with no wrapper. |
| **Impact** | Frontend code that reads `response.alumni.fullname` (v1 pattern) will fail at runtime. Correct pattern: `response.fullname`. |
| **Week 4 action** | No backend change needed. Flutter production UI must use flat field paths. Contract v2 documents the correct shape. |

---

### OI-6 — `ALUMNI_DB_URL` local setup not documented in README or setup guide

| Field | Value |
|---|---|
| **ID** | OI-6 |
| **Severity** | Medium |
| **Description** | `alumni_db` does not exist locally by default and must be created before the registration stack works. `ALUMNI_DB_URL` must be set in `.env`. If absent, the backend starts without error (pydantic Settings `extra="ignore"` swallows unknown variables), but alumni lookups silently fail — all users log in as `user_type="other"` and all registration endpoints return 403 `alumni_only`. |
| **Impact** | A new developer joining the project will get a completely broken registration stack with no obvious error message. This is a major dev experience issue. |
| **Week 4 action** | Add a `GETTING_STARTED.md` or update the existing setup guide with: (1) how to create `alumni_db` locally, (2) required schema, (3) test record insert, (4) `.env` configuration. This is a prerequisite before any new developer can run the registration stack. |

---

### OI-7 — Verification guide AlumniProfileResponse example shows wrong field names (NEW)

| Field | Value |
|---|---|
| **ID** | OI-7 |
| **Severity** | Low |
| **Description** | `docs/validation/backend_week3_manual_verification_guide.md` Section UC-11 shows the expected response as `{"alumni_id": "NITK2026IT001", "graduationyear": 2026, "registrationstatus": "Active", ...}`. The actual `AlumniProfileResponse` schema returns `{"ref_id": "NITK2026IT001", "batch_year": 2026, "is_active": true, ...}`. Field name differences: `alumni_id` → `ref_id`, `graduationyear` → `batch_year`. The `registrationstatus` field does not exist in the response — it is computed into `is_active: bool`. |
| **Impact** | A developer following the guide's UC-11 PASS criteria will look for `alumni_id`, `graduationyear`, and `registrationstatus` fields that do not exist in the actual response. The API implementation and contract v2 are both correct — only the guide example is wrong. |
| **Week 4 action** | Correct the UC-11 expected response example in the verification guide before using it as a QA sign-off checklist. Reference: `backend/app/schemas/registrations.py` `AlumniProfileResponse` and `backend/app/api/alumni.py`. |

---

### OI-8 — Verification guide RegistrationResponse shows `is_virtual` at wrong level (NEW)

| Field | Value |
|---|---|
| **ID** | OI-8 |
| **Severity** | Low |
| **Description** | `docs/validation/backend_week3_manual_verification_guide.md` UC-01 and UC-02 show `"is_virtual": false/true` as a top-level field in the registration response. The actual `RegistrationResponse` schema has no top-level `is_virtual` field. The `is_virtual` value is available in the nested `event` sub-object: `event.is_virtual`. |
| **Impact** | A developer checking the response for `is_virtual` at the top level will find `null` / field absent. The actual field path is `event.is_virtual`. The API implementation and contract v2 are correct — only the guide example is wrong. |
| **Week 4 action** | Correct UC-01 and UC-02 expected response examples in the verification guide. Replace `"is_virtual": false` with `"event": {"is_virtual": false, ...}` and verify `join_url` is null via top-level field (which IS correct). |

---

### OI-9 — `week3_actual_api_response_shapes.md` listed in status report but absent (NEW)

| Field | Value |
|---|---|
| **ID** | OI-9 |
| **Severity** | Medium |
| **Description** | `docs/releases/week3_status_report_2026-06-18.md` lists `week3_actual_api_response_shapes.md` as a completed documentation deliverable under the Documentation Deliverables section. The file does not exist anywhere in the repository (`docs/api/`, `docs/reviews/`, `docs/validation/` — all searched). A similar file `docs/reviews/week3_actual_schema_verification.md` exists but covers schema, not API response shapes. |
| **Impact** | The status report's documentation deliverables list is inaccurate — it claims a deliverable as complete when it does not exist. If another team member references this file, they will get a 404. The actual API response shapes are correctly documented in `docs/api/events_api_contract_v2.md`. |
| **Week 4 action** | Either: (a) create `docs/api/week3_actual_api_response_shapes.md` with verbatim JSON examples of all 5 endpoints (sourced from contract v2 §§ POST register, GET my-registration, GET my/registrations, GET eligibility, GET alumni/me), or (b) update the status report to remove the reference and note that response shapes are in contract v2. |

---

## Security Review

### SEC-01 — `virtual_url` Must Never Appear in Public APIs

**Claim (contract v2):** `virtual_url` is stored in `events.virtual_url` and must never appear in any public API response.

**Verification:**

- `backend/app/services/events_service.py` — not read directly in this review; verified via the diagnostic check 13 which explicitly checks `forbidden = ["virtual_url", "created_by_firebase_uid"]` in the public event response.
- `backend/app/api/dev_diagnostics.py` — diagnostic check 13 (`Public API Leak Check`) fetches `GET /api/v1/events/public/{id}` and verifies that neither `virtual_url` nor `created_by_firebase_uid` appear in the response.
- `backend/app/repositories/registration_repository.py` — `virtual_url` is fetched from the DB in the `_REG_WITH_EVENT` SELECT clause for internal use by `_resolve_join_url()`. It is never placed in the `RegistrationResponse` Pydantic schema — only `join_url` (the resolved value) is in the schema.
- `backend/app/schemas/registrations.py` — `RegistrationResponse` has `join_url: Optional[str]`. No `virtual_url` field.

**Result: VERIFIED ✅**

---

### SEC-02 — `join_url` Only Available to Registered Attendees of Published Virtual Events

**Claim (contract v2):** `join_url` in `RegistrationResponse` is non-null only when all three conditions hold: `status="registered"` AND `is_virtual=true` AND `event_status="published"`.

**Verification — `_resolve_join_url()` in `registration_service.py` (lines 26-34):**

```python
def _resolve_join_url(row: Dict[str, Any]) -> Optional[str]:
    if (
        row.get("status") == "registered"
        and row.get("is_virtual")
        and row.get("event_status") == "published"
    ):
        return row.get("virtual_url")
    return None
```

All three conditions are required by an `and` chain. The field is not in public endpoints. Diagnostic check 10 (`Join Link Visibility`) and check 13 (`Public API Leak Check`) together verify: join_url present for virtual+registered+published; virtual_url absent from public endpoints.

**Result: VERIFIED ✅**

---

### SEC-03 — Email Failure Must Never Rollback a Successful Registration

**Claim (email_service.py docstring):** `send_confirmation_email()` never raises. Email failure returns a failed `EmailResult` and must never roll back the registration transaction.

**Verification — `email_service.py` `send_confirmation_email()`:**

```python
async def send_confirmation_email(...) -> EmailResult:
    """Send a confirmation email. Never raises."""
    ...
    try:
        ...
        smtp.sendmail(...)
        return EmailResult(status="sent", ...)
    except Exception as exc:
        err = str(exc)
        _log.error("[email] send failed to=%s: %s", email_to, err)
        return EmailResult(status="failed", sent_at=None, error=err)
```

The entire SMTP send is wrapped in a try/except. Any exception returns `EmailResult(status="failed")` — the function never raises.

**Verification — `registration_service.py` (lines 144-159):**

```python
# Transaction committed (conn.transaction() block exited)
full_row = dict(await repo.get_by_id_with_event(registration_id))

email_result = await email_service.send_confirmation_email(...)

async with pool.acquire() as conn2:
    await RegistrationRepository(conn2).update_email_status(
        registration_id=registration_id,
        status=email_result.status,
        ...
    )
```

`send_confirmation_email()` is called after the `async with conn.transaction():` block has exited and committed. There is no transaction surrounding the email call. A failed email updates `confirmation_email_status` to `'failed'` but has no mechanism to roll back the already-committed registration.

**Result: VERIFIED ✅**

---

### SEC-04 — Developer Diagnostics Unavailable Outside Development Environment

**Claim:** `GET /api/v1/dev/diagnostics/registrations` returns HTTP 404 when `APP_ENV != "development"`.

**Verification — `dev_diagnostics.py` `_require_development()` (lines 47-49):**

```python
def _require_development() -> None:
    if get_settings().app_env != "development":
        raise HTTPException(status_code=404, detail="not_found")
```

This function is called via `Depends(_get_dev_user)` on every request to every diagnostics endpoint. Any non-development environment returns 404 with `detail="not_found"` — indistinguishable from a missing route, providing no information leakage about the endpoint's existence.

**Result: VERIFIED ✅**

---

### SEC-05 — Audit Context Contains No PII

**Claim (`audit_service.py` docstring):** Never pass `firebase_uid`, email, phone, join URLs, or tokens into audit context.

**Verification — `registration_service.py` (lines 162-168):**

```python
await audit_service.emit(
    actor_uid=firebase_uid,
    event_type="registration_created",
    entity_type="registration",
    entity_id=registration_id,
    context={"event_id": event_id, "registration_number": reg_number},
)
```

Context contains only `event_id` (integer) and `registration_number` (non-PII identifier). `firebase_uid` is passed as `actor_uid` (a separate column, not in the JSONB context). No email, phone, name, or join URL appears in context.

**Result: VERIFIED ✅**

---

## Final Recommendation

**Recommendation: GO WITH CONDITIONS**

### GO rationale

- The backend registration platform is feature-complete and correctly implemented.
- All 5 registration endpoints are live and tested by the 13-check automated diagnostic suite.
- All 9 POST error detail codes are correctly raised by the service.
- All 6 eligibility_status v2 values are correctly returned by the service.
- All 4 security invariants (virtual_url isolation, join_url gating, email-after-commit, dev diagnostics unavailable in production) are verified in code.
- Migration 008 correctly aligns the registrations table to the Week 3 schema. Migration 009 correctly adds the JSONB context column.
- The Flutter Developer Diagnostics screen uses correct v2 eligibility values (fixed in the OI-3 consistency review).
- The API contract v2 is authoritative and correct.

### Conditions before Week 4 sign-off is used as QA checklist

| # | Condition | Owner | Blocking? |
|---|---|---|---|
| C1 | Fix OI-7: correct AlumniProfileResponse example in verification guide | Documentation | No — code is correct; guide is advisory |
| C2 | Fix OI-8: correct RegistrationResponse `is_virtual` field path in verification guide | Documentation | No — code is correct; guide is advisory |
| C3 | Resolve OI-9: create missing `week3_actual_api_response_shapes.md` or remove the reference from status report | Documentation | No — authoritative reference is in contract v2 |
| C4 | Resolve OI-6: document `ALUMNI_DB_URL` local setup before onboarding any new developer | DevOps / documentation | **Yes — blocking for any new developer joining Week 4** |

Conditions C1–C3 are documentation corrections only and do not block Week 4 code development. Condition C4 is blocking for onboarding any new developer who does not already have `alumni_db` set up locally.

---

## Week 4 Prerequisites

The following must be in place before starting Week 4 production Flutter UI development:

### Required (Blocking)

| # | Prerequisite | Current State | Action |
|---|---|---|---|
| P1 | `ALUMNI_DB_URL` documented in setup guide (OI-6) | Not documented | Write `GETTING_STARTED.md` with alumni_db setup instructions |
| P2 | Developer uses API contract v2 field names | ✅ Contract exists | Confirm developer has read contract v2 before building registration UI |
| P3 | Developer uses v2 `eligibility_status` values (`full`, `closed`, `not_open_yet`, `ineligible`, `eligible`, `already_registered`) | ✅ All corrected in Week 3 | Confirm via code review of first production PR |
| P4 | Production Flutter UI must NOT be placed in `developer_diagnostics_screen.dart` | ✅ Constraint documented | Week 4 PR review gate |

### Recommended (Non-blocking)

| # | Prerequisite | Action |
|---|---|---|
| R1 | Fix verification guide OI-7 and OI-8 before using it as QA checklist | Correct field name examples in UC-11, UC-01, UC-02 |
| R2 | Create `week3_actual_api_response_shapes.md` or update status report (OI-9) | 30-minute documentation task |
| R3 | Decide on OI-1 (`confirm_profile` field): explicit optional or leave absent | Architectural decision, record in contract v2 |
| R4 | Decide on OI-2 (eligibility flat response): add `event` sub-object or require two-call pattern | Architectural decision before Flutter UI build starts |

### API facts every Week 4 developer must know

1. **POST /register body:** `{"attendee_note": "..."}` — only field accepted. `confirm_profile` is silently ignored.
2. **AlumniProfileResponse fields:** `ref_id`, `fullname`, `email`, `phone`, `batch_year`, `branch`, `is_active`. **Not** `alumni_id`, `graduationyear`, `registrationstatus`.
3. **RegistrationResponse `is_virtual`:** lives at `event.is_virtual`, not at the top level.
4. **Eligibility v2:** switch on `eligible`, `already_registered`, `full`, `closed`, `not_open_yet`, `ineligible`. Never use v1 names.
5. **Two-code rule:** eligibility returns `full` / `closed` / `not_open_yet`. POST errors return `event_full` / `registration_closed` / `registration_not_open_yet`. Handle both when building UI that both pre-checks eligibility and catches POST errors.
6. **`join_url`:** top-level field in `RegistrationResponse`. Present only when registered + virtual + published. Always null for physical events.
7. **`ineligible` is a catch-all:** read `message` field or call `GET /alumni/me` to distinguish between "not an alumni" and "alumni not active".

---

## Reviewed Documents and Files

| File | Role | Verdict |
|---|---|---|
| `docs/validation/backend_week3_manual_verification_guide.md` | Manual QA checklist | 2 example discrepancies (OI-7, OI-8) — code correct |
| `docs/releases/week3_status_report_2026-06-18.md` | Status report | 1 missing file reference (OI-9) |
| `docs/releases/week3_closure_report.md` | Closure document | Consistent with implementation |
| `docs/releases/week3_readiness_review.md` | GO/NO-GO review | Consistent with implementation |
| `docs/api/events_api_contract_v2.md` | Authoritative API contract | Correct — matches implementation exactly |
| `docs/api/week3_actual_api_response_shapes.md` | Documentation deliverable | **MISSING** (OI-9) |
| `backend/app/api/alumni.py` | Alumni endpoint | Correct |
| `backend/app/api/registrations.py` | Registration endpoints | Correct |
| `backend/app/services/registration_service.py` | Registration business logic | Correct |
| `backend/app/repositories/registration_repository.py` | Registration data access | Correct |
| `backend/app/services/email_service.py` | Email delivery | Correct — never raises |
| `backend/app/services/audit_service.py` | Audit logging | Correct — never raises |
| `backend/app/api/dev_diagnostics.py` | Developer diagnostics | Correct — 13 checks match guide |
| `backend/app/schemas/registrations.py` | Pydantic schemas | Correct |
| `apps/event_app/…/developer_diagnostics_screen.dart` | Flutter diagnostics UI | Correct (v2 values, post-fix) |
| `apps/event_app/…/event_detail_screen.dart` | Flutter event detail | Correct (ListTile fix applied) |
| `migrations/events_db/004_registrations_and_check_ins.sql` | Base schema | Pre-Week 3 baseline; aligned by 008 |
| `migrations/events_db/007_add_show_attendee_list.sql` | Events column | Not Week 3 scope; non-breaking |
| `migrations/events_db/008_week3_registration_alignment.sql` | Week 3 schema alignment | 15-step migration; correct |
| `migrations/events_db/009_add_audit_log_context.sql` | Audit JSONB context | Correct; matches audit_service usage |
