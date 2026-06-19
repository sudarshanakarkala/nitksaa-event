# Swagger Testing Guide Creation Report

**Version:** 1.0  
**Date:** 2026-06-19  
**Status:** Complete  
**Recommendation:** PASS — guide is self-contained and ready for use

---

## Summary

A standalone Swagger-based API testing guide was created for the NITKSAA Event App covering
all implemented Week 1–3 endpoints. The guide is written for mixed audiences (developers,
QA, product owners, new onboarding) and can be used without developer assistance.

34 test cases were documented: 14 positive, 16 negative, 2 security, and 2 Week 4 placeholders.

---

## File Created

```text
docs/api/swagger_testing_guide.md
```

---

## Source Documents Reviewed

| Document | Reviewed | Notes |
|---|---|---|
| `docs/api/backend_api_index_v2.md` | Yes | Endpoint inventory, response shapes |
| `docs/api/backend_auth_api_v1.md` | Yes | Auth flow, error codes |
| `docs/api/event_admin_api_usage_v2.md` | Yes | Admin portal patterns, apiClient behaviour |
| `docs/api/events_api_contract_v2.md` | Yes | Business rules, join link policy, eligibility values |
| `docs/api/week3_actual_api_response_shapes.md` | Yes | Runtime-verified response shapes |
| `docs/validation/backend_week3_manual_verification_guide_v2.md` | Yes | Test event IDs, SQL recreation |
| `docs/releases/week3_status_report_2026-06-18.md` | Yes | Deliverable matrix, deferred items |
| `docs/reviews/api_documentation_consistency_review.md` | Yes | Known issues, superseded docs |

Live Swagger comparison: `http://localhost:8000/docs` was not accessible during guide creation
(backend not running). All endpoint shapes were derived from backend source files and the
verified response shapes document.

---

## Week 1 Tests Covered

| ID | API | Type |
|---|---|---|
| W1-P1 | GET /api/v1/health | Positive |
| W1-P2 | POST /api/v1/auth/firebase | Positive |
| W1-P3 | GET /api/v1/auth/me | Positive |
| W1-N1 | GET /api/v1/auth/me (no auth) | Negative |
| W1-N2 | POST /api/v1/auth/firebase (invalid token) | Negative |

**Week 1 total:** 5 (3 positive, 2 negative)

---

## Week 2 Tests Covered

| ID | API | Type |
|---|---|---|
| W2-P1 | GET /api/v1/events/public | Positive |
| W2-P2 | GET /api/v1/events/public/{event_id} | Positive |
| W2-N1 | GET /api/v1/events/public/{event_id} (not found) | Negative |
| W2-P3 | POST /api/v1/events | Positive |
| W2-P4 | PATCH /api/v1/events/{event_id}/status (publish) | Positive |
| W2-P5 | PATCH /api/v1/events/{event_id} | Positive |
| W2-P6 | PATCH /api/v1/events/{event_id}/status (cancel) | Positive |
| W2-N2 | Admin endpoints without JWT | Negative |
| W2-N3 | POST /api/v1/events (invalid dates) | Negative |
| W2-N4 | POST /api/v1/events (capacity ≤ 0) | Negative |

**Week 2 total:** 10 (5 positive, 4 negative + 1 for wrapped public detail shape)

---

## Week 3 Tests Covered

| ID | API | Type |
|---|---|---|
| W3-P1 | GET /api/v1/alumni/me | Positive |
| W3-N1 | GET /api/v1/alumni/me (no auth) | Negative |
| W3-P2 | GET /api/v1/events/{id}/registration-eligibility | Positive |
| W3-P3 | POST /api/v1/events/25/register (physical) | Positive |
| W3-P4 | POST /api/v1/events/26/register (virtual) | Positive |
| W3-P5 | GET /api/v1/events/26/my-registration | Positive |
| W3-P6 | GET /api/v1/my/registrations | Positive |
| W3-P7 | GET /api/v1/dev/diagnostics/registrations | Positive |
| W3-N2 | Duplicate registration | Negative |
| W3-N3 | Event full (event 34) | Negative |
| W3-N4 | Registration closed (event 35) | Negative |
| W3-N5 | Registration not open yet (event 36) | Negative |
| W3-N6 | Non-alumni user | Negative |
| W3-N7 | Inactive alumni | Negative |
| W3-N8 | Public API leak check (virtual_url / join_url absent) | Security |
| W3-N9 | Dev diagnostics hidden in production | Security |

**Week 3 total:** 16 (7 positive, 7 negative, 2 security)

---

## Week 4 Planned Coverage

| ID | API | Status |
|---|---|---|
| W4-P1 | GET /api/v1/events/{event_id}/attendees | TO BE DONE |
| W4-P2 | GET /api/v1/events/{event_id}/attendees/export | TO BE DONE |

Guide explicitly notes: Week 4 endpoints currently return 501 or 404. This is expected and is not a Week 3 bug.

---

## Positive Cases Covered

14 total:

- Health check
- Firebase token exchange
- Auth me
- Alumni profile
- Registration eligibility (eligible state)
- Physical event registration
- Virtual event registration
- My registration detail
- My registrations list
- Registration diagnostics (13-check suite)
- Public event list
- Public event detail
- Admin create event
- Admin publish/update/cancel event (covered under W2-P3 through W2-P6)

---

## Negative Cases Covered

16 total:

- Auth me without JWT
- Invalid Firebase token
- Public event not found
- Admin endpoints without JWT
- Invalid event dates
- Invalid capacity
- Alumni me without JWT
- Duplicate registration
- Event full
- Registration closed
- Registration not open yet
- Non-alumni user registration
- Inactive alumni registration
- Public API join_url leak check
- Dev diagnostics hidden in production

---

## Authorization Notes

The guide covers two paths for obtaining a backend JWT:

**Option A (recommended for quick testing):** Use Flutter Developer Diagnostics screen to
extract the `access_token` from the Backend Auth Test or /auth/me check.

**Option B (advanced):** Use Firebase REST API to get an `idToken`, then exchange it via
`POST /api/v1/auth/firebase` using Swagger itself, then copy the `access_token`.

Key distinction documented clearly: Firebase `idToken` ≠ backend `access_token`. Pasting the
wrong token into Swagger Authorize is the most common setup error.

---

## Remaining Open Items

| Item | Notes |
|---|---|
| Week 4 attendee endpoint shapes | Not yet defined — placeholders only in the checklist |
| Live Swagger URL verification | Backend was not running during guide creation — all shapes derived from source files |
| Non-alumni test account | Guide documents the scenario but does not provide a specific test account for `user_type = "other"` |
| Inactive alumni test account | Same — scenario described, no dedicated test credential provided |

---

## PASS / FAIL Recommendation

**PASS**

The Swagger testing guide covers all 19 implemented Week 1–3 endpoints with:
- Exact Swagger UI interaction steps
- Correct request bodies (using `token` not `idToken`)
- Verified response shapes (including `{"event": {...}}` wrapper on public detail)
- All 6 registration error conditions (event_full, registration_closed, registration_not_open_yet, already_registered, alumni_only, alumni_not_active)
- Correct field names (`status = "registered"`, `confirmation_email_status` as string)
- Security invariant checks (join_url absent from public API)
- 12 troubleshooting entries for common failure scenarios

Week 4 is included as explicitly planned with expected 501/404 behaviour noted.
