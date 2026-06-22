# NITKSAA Event App — Week 3 Document Review

**Date:** 2026-06-18  
**Phase:** 0 — Pre-development review  
**Reviewer:** Claude Code (automated)  
**Sprint:** Week 3 — Registration, Confirmation Email, Protected Join Link, Diagnostics UI

---

## 1. Document Existence Check

All required documents exist.

| Document | Path | Status |
|---|---|---|
| Beta Plan | docs/notes/june2026/nitksaa_event_beta_plan_jun30_pw.md | FOUND |
| Week 3 Backend API Contract v2 | docs/notes/june2026/nitksaa_event_week3_backend_api_contract_v2.md | FOUND |
| Architecture Observations | docs/notes/june2026/nitksaa-event_app_architecture_review_observations.md | FOUND |
| Architecture Review v1.0 | docs/notes/june2026/nitksaa-event_architecture_review_v1.0.md | FOUND |
| Week 3 Architecture Review v2 | docs/notes/june2026/nitksaa_event_week3_architecture_review_v2.md | FOUND |
| Week 3 Execution Plan v2 | docs/notes/june2026/nitksaa_event_week3_execution_plan_v2.md | FOUND |
| Week 3 Backend API Contract v2 | docs/notes/june2026/nitksaa_event_week3_backend_api_contract_v2.md | FOUND |
| Week 3 Use Cases and Test Cases v2 | docs/notes/june2026/nitksaa_event_week3_usecases_and_testcases_v2.md | FOUND |
| Week 3 Architecture Diagrams v2 | docs/notes/june2026/nitksaa_event_week3_architecture_diagrams_v2.md | FOUND |
| Events API Contract v1 | docs/api/events_api_contract_v1.md | FOUND |
| Backend API Index v1 | docs/api/backend_api_index_v1.md | FOUND |
| Backend Auth API v1 | docs/api/backend_auth_api_v1.md | FOUND |
| Event Admin API Usage v1 | docs/api/event_admin_api_usage_v1.md | FOUND |
| Week 2 Flutter Report | docs/reviews/old_reviews/week2_flutter_report.txt | FOUND |
| Week 2 Backend API Report | docs/reviews/old_reviews/week2_backend_api_report.txt | FOUND |
| Week 2 End-to-End Verification | docs/reviews/old_reviews/week2_end_to_end_verification_report.txt | FOUND |
| Week 2 Admin Portal Report | docs/reviews/old_reviews/week2_admin_portal_report.txt | FOUND |

**Result: 17/17 documents present. No missing documents.**

---

## 2. Beta Plan vs Week 3 Alignment

The beta plan (jun30_pw.md) Week 3 goal:

```
Alumni can register.
Confirmation email sent.
Join link visible post-registration.
```

Week 3 v2 documents correctly expand this to:

```
Registration + Confirmation Email + Protected Join Link + Diagnostics UI Flows
```

### Alignment issues noted

**None.** The v2 documents are correctly aligned with the beta plan. The key expansion from v1 to v2 (adding confirmation email and join-link reveal to Week 3 scope) is properly documented and consistent across all v2 files.

---

## 3. API Contract Consistency

All five v2 documents are internally consistent. Cross-document checks:

| API Endpoint | Architecture v2 | Execution Plan v2 | API Contract v2 | Use Cases v2 | Diagrams v2 |
|---|---|---|---|---|---|
| GET /alumni/me | YES | Phase 3 | Section 7 | UC-01 | Flow 2 |
| POST /events/{id}/register | YES | Phase 5 | Section 9 | UC-02/UC-03 | Flow 2 |
| GET /events/{id}/registration-eligibility | Optional | Optional | Section 8 | Referenced | Flow 2 |
| GET /events/{id}/my-registration | YES | Phase 5 | Section 10 | UC-13 | Flow 3 |
| GET /my/registrations | YES | Phase 5 | Section 11 | UC-14 | Flow 2 |
| GET /dev/diagnostics/registrations | YES | Phase 9 | Section 12.1 | UC-15 | Flow 6 |
| POST /dev/diagnostics/registrations/run | YES | Phase 9 | Section 12.2 | UC-15 | Flow 6 |

No contradictions between documents.

---

## 4. Registration Status Values

The v2 documents define these registration row statuses:

```
registered
cancelled
```

Existing migration 004 has `DEFAULT 'confirmed'`. **This is a mismatch.** The migration default must be changed to `'registered'` via Week 3 schema migration. See Schema Review for full details.

---

## 5. Event Registration_Status Computed Values

Documents define:

```
open
closed
full
not_open_yet
not_applicable
```

This matches the existing `_compute_registration_status()` implementation in `backend/app/services/events_service.py`. No change needed to the computation logic.

---

## 6. Public Safety Rule

All v2 documents consistently state:

```
virtual_url must never appear in public API responses.
join_url exposed only via authenticated user-specific endpoints after registration.
```

Week 2 verification confirmed this is working for the events API. Week 3 must extend this rule to all registration response paths. See Dependency Review for specific code locations that must not expose virtual_url.

---

## 7. Error Code Consistency

The API contract defines structured error codes. Current backend raises:

```python
HTTPException(status_code=400, detail="event_not_published")
HTTPException(status_code=409, detail="capacity_reached")
HTTPException(status_code=409, detail="registration_duplicate")
```

Week 3 contract requires:

```json
409 event_not_published
409 event_full
409 already_registered
```

**Issues:**
- Old service uses status 400 for event_not_published; contract says 409.
- Old service uses `capacity_reached`; contract says `event_full`.
- Old service uses `registration_duplicate`; contract says `already_registered`.

All old registration service code will be rewritten for Week 3 so these will be fixed then. Do not patch the old code.

---

## 8. Email Architecture Consistency

Across v2 documents, email is consistently described as:

- Required for Week 3 staging (not just local stub)
- EmailService abstraction with log and send modes
- Registration saved even if email fails
- email status returned in registration response as `sent | failed | skipped`

This is consistent across all documents. No contradictions.

---

## 9. Flutter Scope Clarity

All documents consistently say:

```
No production Flutter registration screens this week.
Developer Diagnostics shows registration UI flows.
```

This is correct. Week 3 Flutter work is limited to adding a Registration Flow section to the existing Developer Diagnostics screen, not building themed registration UI.

---

## 10. React Admin Scope Clarity

All documents consistently say:

```
No new production React Admin screens in Week 3.
Week 4: attendee list, search, export.
```

Correct. Admin portal Week 3 work is zero production changes.

---

## 11. Deferred Items Consistency

Items consistently deferred across all v2 documents:

- Attendance / QR check-in
- Waitlist
- Payment
- Admin attendee list/export (Week 4)
- Production Flutter registration screens
- Production React Admin registration screens

No document tries to add these back into Week 3.

---

## 12. Week 2 Baseline Confirmed

From Week 2 verification reports:

| Item | Status |
|---|---|
| No registration functionality added | CONFIRMED |
| No email functionality added | CONFIRMED |
| No join URL exposed publicly | CONFIRMED |
| Public APIs return published events only | CONFIRMED |
| Backend compile PASS | CONFIRMED |
| Diagnostics 8/8 PASS | CONFIRMED |
| Flutter analyze PASS | CONFIRMED |
| Flutter test 16/16 PASS | CONFIRMED |
| Admin build + lint PASS | CONFIRMED |
| virtual_url not in public responses | CONFIRMED |

Week 3 starts from a clean, verified Week 2 baseline.

---

## 13. Open Items from Architecture Observations Document

The observations doc raised three items. Status:

| Item | Description | Status for Week 3 |
|---|---|---|
| Remove DELETE /events/{id} | Hard delete not implemented in Week 2 | DONE (405 confirmed) |
| Published → Registration Open distinction | Observed as needed but v2 documents resolved as: use registration_opens_at field, not a new status | RESOLVED by computed registration_status |
| Email mandatory for staging | Closed as YES | CONFIRMED in Week 3 scope |

The `event_members` table documentation gap (observation 4) is noted but not a Week 3 blocker.

---

## 14. Summary

All Week 3 v2 documents are internally consistent, aligned with the beta plan, and form a coherent implementation guide. The document review gate is clear.

**Primary risk areas identified from documents that require schema/code review:**
- Registration table schema gaps (see Schema Review)
- alumni_db integration details (see Dependency Review)
- registered_count currently hardcoded 0 (see Schema Review)
- Email service does not exist yet (see Dependency Review)
