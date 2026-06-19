# API Documentation Consistency Review

**Version:** 1.0  
**Date:** 2026-06-19  
**Reviewer:** Claude Code (automated review against backend source)  
**Scope:** All `docs/api/` files against `backend/app/api/` and `backend/app/schemas/`  
**Recommendation:** PASS WITH FIXES APPLIED

---

## 1. Summary

A line-by-line review of all API documentation files was conducted against the backend
implementation as the source of truth. Eleven known-issue categories were checked.

| Category | Issues found | Fixed? |
|---|---|---|
| Auth body field name (`idToken` vs `token`) | 1 | Yes — `events_api_contract_v2.md` |
| Public event detail response wrapper | 1 | Yes — `events_api_contract_v2.md` |
| Registration status values (`confirmed` vs `registered`) | 1 | Isolated to v1 historical doc |
| `confirmation_email_sent` boolean vs `confirmation_email_status` string | 1 | Isolated to v1 historical doc |
| Admin event path param (`{slug}` vs `{event_id}`) | 2 | Yes — `event_admin_api_usage_v2.md` |
| Admin endpoint auth claim ("No auth" vs JWT required) | 2 | Yes — `event_admin_api_usage_v2.md` |
| Missing DELETE endpoint clarification | 1 | Documented in v2 index and contract |
| Attendee endpoints returning 501 not documented | 1 | Yes — `backend_api_index_v2.md` |
| Eligibility status value set incomplete in older docs | 1 | Documented in v2 index |
| `join_url` level in response (top-level, not nested) | 1 | Documented in v2 index and shapes doc |
| `is_virtual` level in response (nested in `event`, not top-level) | 1 | Documented in v2 index |

**Total issues found:** 13  
**Issues fixed inline:** 4 (in `events_api_contract_v2.md` and new v2 documents)  
**Issues isolated to v1 historical documents (no fix needed):** 9 — v1 documents are superseded

---

## 2. Documents Reviewed

| File | Status | Notes |
|---|---|---|
| `docs/api/backend_api_index_v1.md` | Historical — superseded | Multiple inaccuracies; see §Issues Found |
| `docs/api/backend_auth_api_v1.md` | Accurate | All auth fields and error codes correct |
| `docs/api/event_admin_api_usage_v1.md` | Historical — superseded | Wrong path params, wrong auth claims |
| `docs/api/events_api_contract_v1.md` | Historical — pre-implementation design | §7.1 says "do not use `join_url`" — now outdated |
| `docs/api/events_api_contract_v2.md` | Updated (2 fixes) | `idToken` → `token`; public detail shape corrected |
| `docs/api/week3_actual_api_response_shapes.md` | Accurate | All response shapes verified against backend |

---

## 3. Source of Truth Hierarchy

Priority order used for resolving conflicts:

1. **Backend router and schema files** (`backend/app/api/*.py`, `backend/app/schemas/*.py`)
2. **`docs/api/week3_actual_api_response_shapes.md`** — runtime-verified Week 3 responses
3. **`docs/api/events_api_contract_v2.md`** — Week 3 design contract
4. **v1 documents** — pre-implementation design, lowest authority

---

## 4. Issues Found

### Issue 01 — `idToken` field name in backend auth call

| Attribute | Detail |
|---|---|
| **File** | `docs/api/events_api_contract_v2.md` lines 49-50 |
| **Incorrect text** | `POST /api/v1/auth/firebase` with `{"idToken": "..."}` |
| **Correct text** | `POST /api/v1/auth/firebase` with `{"token": "<firebase_id_token>"}` |
| **Source of truth** | `backend/app/api/auth.py` → `FirebaseLoginRequest.token: str = Field(..., min_length=1)` |
| **Fix applied** | Yes — corrected in `events_api_contract_v2.md` |
| **Remaining occurrences** | `backend_week3_manual_verification_guide_v2.md` uses `idToken` in a step explaining what Firebase returns — this is contextually correct (Firebase's own response field is named `idToken`). Not a documentation error. |

---

### Issue 02 — Public event detail response not wrapped

| Attribute | Detail |
|---|---|
| **File** | `docs/api/events_api_contract_v2.md` §GET /api/v1/events/public/{event_id} |
| **Incorrect text** | "Returns a single published event. Same shape as the list item above." (implying flat, not wrapped) |
| **Correct text** | Returns `{"event": {...}}` — the event object is nested one level deeper than the list items |
| **Source of truth** | `backend/app/api/events.py`: `return {"event": event}` |
| **Fix applied** | Yes — section replaced with wrapped response shape and frontend access guidance |
| **Impact** | Frontend code reading `response.title` instead of `response.event.title` would break |

---

### Issue 03 — Registration status `"confirmed"` does not exist

| Attribute | Detail |
|---|---|
| **File** | `docs/api/backend_api_index_v1.md` |
| **Incorrect text** | `"status": "confirmed"` in registration response examples |
| **Correct values** | `"registered"` and `"cancelled"` only |
| **Source of truth** | `backend/app/schemas/registrations.py` `RegistrationResponse.status` |
| **Fix applied** | Not needed — v1 is superseded by `backend_api_index_v2.md` which uses correct values |

---

### Issue 04 — `confirmation_email_sent: true` boolean field does not exist

| Attribute | Detail |
|---|---|
| **File** | `docs/api/backend_api_index_v1.md` |
| **Incorrect text** | `"confirmation_email_sent": true` in registration response |
| **Correct field** | `"confirmation_email_status": "sent"` (string — `"sent"`, `"failed"`, or `"skipped"`) |
| **Source of truth** | `backend/app/schemas/registrations.py` `RegistrationResponse.confirmation_email_status` |
| **Fix applied** | Not needed — v1 is superseded by `backend_api_index_v2.md` |

---

### Issue 05 — Admin event path param `{slug}` should be `{event_id}`

| Attribute | Detail |
|---|---|
| **Files** | `docs/api/event_admin_api_usage_v1.md` §Future APIs, `docs/api/backend_api_index_v1.md` |
| **Incorrect text** | `GET /api/v1/events/{slug}`, `PATCH /api/v1/events/{slug}/status` |
| **Correct text** | `GET /api/v1/events/{event_id}`, `PATCH /api/v1/events/{event_id}/status` |
| **Source of truth** | `backend/app/api/events.py`: `@router.get("/{event_id}", ...)` |
| **Fix applied** | Corrected in `event_admin_api_usage_v2.md` and `backend_api_index_v2.md` |

---

### Issue 06 — Admin event list listed as "No auth"

| Attribute | Detail |
|---|---|
| **File** | `docs/api/event_admin_api_usage_v1.md` §Future APIs Week 2 |
| **Incorrect text** | `GET /api/v1/events — Auth: No` |
| **Correct text** | Auth: Backend JWT required |
| **Source of truth** | `backend/app/api/events.py`: `GET /` uses `current_user: CurrentUser = Depends(get_current_user)` |
| **Fix applied** | Corrected in `event_admin_api_usage_v2.md` with explicit note |

---

### Issue 07 — No DELETE endpoint clarification missing

| Attribute | Detail |
|---|---|
| **Files** | v1 docs made no mention of the absence; could lead to adding a DELETE call |
| **Correct behaviour** | There is no `DELETE /api/v1/events/{event_id}` route. Soft-cancel via `PATCH .../status` with `{"status": "cancelled"}` |
| **Source of truth** | `backend/app/api/events.py` — no `@router.delete(...)` route defined |
| **Fix applied** | Explicitly documented in `event_admin_api_usage_v2.md` and `backend_api_index_v2.md` |

---

### Issue 08 — Attendee endpoints return 501 (not yet implemented)

| Attribute | Detail |
|---|---|
| **Files** | `event_admin_api_usage_v1.md` listed attendee endpoints as "planned" without noting they raise 501 |
| **Correct behaviour** | `GET /api/v1/events/{event_id}/attendees` and `export` route exist in `admin_events.py` but raise `501 Not Implemented` |
| **Fix applied** | `backend_api_index_v2.md` and `event_admin_api_usage_v2.md` explicitly flag as Week 4 planned with 501 note |

---

### Issue 09 — `eligibility_status` value set incomplete

| Attribute | Detail |
|---|---|
| **Files** | Older docs referenced `"can_register"` and `"alumni_required"` (pre-implementation names) |
| **Correct values** | `eligible`, `already_registered`, `full`, `closed`, `not_open_yet`, `ineligible` |
| **Source of truth** | `backend/app/api/registrations.py` eligibility endpoint return values |
| **Fix applied** | Full correct value set documented in `backend_api_index_v2.md` with the two-code rule |

---

### Issue 10 — `join_url` level in registration response

| Attribute | Detail |
|---|---|
| **Files** | Some design notes had `join_url` inside a nested `access` object |
| **Correct shape** | `join_url` is a **top-level field** in `RegistrationResponse` — not nested |
| **Source of truth** | `backend/app/schemas/registrations.py` `RegistrationResponse.join_url` |
| **Fix applied** | Response shapes in `backend_api_index_v2.md` show the correct flat structure |

---

### Issue 11 — `is_virtual` level in registration response

| Attribute | Detail |
|---|---|
| **Files** | Flutter diagnostics screen had `is_virtual` at top-level initially (fixed in Week 3 Flutter bug fix) |
| **Correct shape** | `is_virtual` is inside the **nested `event` object** within `RegistrationResponse`, not at the top level |
| **Source of truth** | `backend/app/schemas/registrations.py` `EventSummary.is_virtual` — nested inside `RegistrationResponse.event` |
| **Fix applied** | `backend_api_index_v2.md` explicitly notes the nesting level with field path guidance |

---

## 5. Documents Created

| File | Purpose |
|---|---|
| `docs/api/backend_api_index_v2.md` | Authoritative endpoint inventory — all implemented endpoints with correct paths, auth, and response shapes. Supersedes v1. |
| `docs/api/event_admin_api_usage_v2.md` | Admin portal API usage guide — Week 1–3 implemented, Week 4 planned. Supersedes v1. |
| `docs/reviews/api_documentation_consistency_review.md` | This review document |

---

## 6. Documents Updated

| File | Changes |
|---|---|
| `docs/api/events_api_contract_v2.md` | Fix 1: `idToken` → `token` in auth flow description (lines 49-50). Fix 2: Public event detail `GET /events/public/{event_id}` response shape corrected from "same as list item" to correct `{"event": {...}}` wrapped shape. |

---

## 7. Deprecated / Superseded Documents

These documents are retained for historical reference but must not be used for new frontend
code or documentation. They are superseded by the v2 documents listed in §5 and §6.

| File | Superseded by | Why |
|---|---|---|
| `docs/api/backend_api_index_v1.md` | `backend_api_index_v2.md` | Wrong registration status, wrong email field, missing Week 3 endpoints, `{slug}` path params |
| `docs/api/event_admin_api_usage_v1.md` | `event_admin_api_usage_v2.md` | Wrong path params, wrong auth claims, attendee endpoints inaccurately described |
| `docs/api/events_api_contract_v1.md` | `events_api_contract_v2.md` | Pre-implementation design document; §7.1 says "do not use `join_url`" — now incorrect |

The following document is accurate and does not need a v2 replacement:

| File | Status | Notes |
|---|---|---|
| `docs/api/backend_auth_api_v1.md` | Accurate | Correct `token` field, correct error codes — no v2 needed |
| `docs/api/week3_actual_api_response_shapes.md` | Accurate | Runtime-verified shapes — no changes needed |

---

## 8. Final API Source of Truth

For any backend API question, consult in this order:

1. **`backend/app/api/*.py`** — router definitions (paths, auth, HTTP status codes)
2. **`backend/app/schemas/*.py`** — request/response field names and types
3. **`docs/api/week3_actual_api_response_shapes.md`** — runtime-verified JSON examples
4. **`docs/api/backend_api_index_v2.md`** — human-readable endpoint inventory
5. **`docs/api/events_api_contract_v2.md`** — business rules (join link policy, email rules, eligibility)

Do not use `v1` documents as authoritative sources. They are frozen historical artifacts.

---

## 9. Remaining Open Questions

| # | Question | Impact | Status |
|---|---|---|---|
| OQ-01 | Should public event URLs use `/events/public/{slug}` alongside `/events/public/{event_id}`? | Frontend SEO and deep-link sharing | Architecture decision pending — tracked in `nitksaa_event_week3_status_19_06_2026.md` §3 |
| OQ-02 | Will `admin_events.py` routes (`/api/v1/admin/...`) be used by the NITKSAA React Admin Portal or only by the EventAdmin portal? | Determines which portal handles Week 4 attendee management | Week 4 planning decision |
| OQ-03 | Should `PATCH /api/v1/events/{event_id}/status` with `"cancelled"` also trigger confirmation emails to registered alumni? | Cancellation email flow | Not yet designed |
| OQ-04 | What is the pagination behaviour for `GET /api/v1/my/registrations`? | Frontend needs to know whether pagination params apply | Source code shows all returned by default — clarify if limit will be added |

---

## 10. Incorrect String Audit Results

Strings searched across all `docs/api/` files with `grep -r`:

| String | Occurrences | Status |
|---|---|---|
| `"idToken"` (as backend request field) | 1 — fixed in `events_api_contract_v2.md` | Resolved |
| `idToken` (as Firebase response field, contextually correct) | Multiple in v2 guide | Correct — describes Firebase SDK output |
| `"confirmed"` (as registration status) | Only in `backend_api_index_v1.md` | Historical — superseded |
| `confirmation_email_sent: true` | Only in `backend_api_index_v1.md` | Historical — superseded |
| `can_register` | Only in `docs/notes/` and `events_api_contract_v1.md` | Historical design names — superseded |
| `alumni_required` | Only in `docs/notes/` | Historical design names — superseded |
| `{slug}` (as event path param) | In `event_admin_api_usage_v1.md` and `events_api_contract_v1.md` | Historical — superseded |
| `registration_number`, `access.join_url`, `confirmation_email.status` (nested) | Only in `events_api_contract_v2.md` Known Deviations table | Intentional — documents old design vs new for migration reference |

---

## 11. PASS / FAIL Recommendation

| Document | Verdict | Notes |
|---|---|---|
| `docs/api/backend_auth_api_v1.md` | **PASS** | Accurate — no changes needed |
| `docs/api/week3_actual_api_response_shapes.md` | **PASS** | Runtime-verified — accurate |
| `docs/api/events_api_contract_v2.md` | **PASS** (after fixes) | 2 issues fixed during this review |
| `docs/api/backend_api_index_v2.md` | **PASS** | New document — all entries verified against backend |
| `docs/api/event_admin_api_usage_v2.md` | **PASS** | New document — all issues from v1 corrected |
| `docs/api/backend_api_index_v1.md` | **SUPERSEDED** | Multiple inaccuracies — do not use |
| `docs/api/event_admin_api_usage_v1.md` | **SUPERSEDED** | Multiple inaccuracies — do not use |
| `docs/api/events_api_contract_v1.md` | **SUPERSEDED** | Pre-implementation design — do not use as source of truth |

**Overall recommendation: PASS** — all actionable issues have been fixed or isolated to
superseded documents. The v2 document set is consistent with the backend implementation.
