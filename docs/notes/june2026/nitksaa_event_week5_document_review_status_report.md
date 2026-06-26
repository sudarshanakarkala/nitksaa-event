# NITKSAA Event Platform — Document Review Status Report

**Date:** 2026-06-26  
**Review scope:**

1. `nitksaa_event_beta_plan_jun30_pw.md` — Jun 30 Beta Plan
2. `nitksaa-event-app-integration-note_pw.md` — Integration & Architecture Alignment Note
3. Current project status shared in this chat through Week 5 verification reports

**Verdict:** Week 1–Week 5 development is substantially complete for local development and verification. The remaining blockers are operational, testing-infrastructure, and deferred-scope items rather than core Week 1–Week 5 feature implementation.

---

## 1. Executive Summary

The original Jun 30 Beta Plan targeted a focused beta system covering authentication, event creation, public listing, registration, confirmation email, attendee list, and CSV export. It explicitly kept sessions/tracks and QR check-in out of scope.

Based on the Week 5 verification reports shared in this chat, the platform has gone beyond the original beta plan in some areas by adding event options, people/speakers foundation, sponsors, partners, analytics logging, developer diagnostics, and admin enrichment management.

However, the Integration & Architecture Alignment Note contains some architecture expectations that are either intentionally changed, partially implemented, or deferred. These should be tracked clearly before beta handoff and before website integration.

---

## 2. Status by Week

### Week 1 — Auth, Backend, DB, Admin Shell

| Requirement | Status | Notes |
|---|---:|---|
| Flutter email/password sign-in | Done | Authentication foundation exists. |
| Flutter Google Sign-In | Done | Firebase login flow is part of completed Week 1–4 foundation. |
| Auth state stream / persistence | Done | Verified earlier through auth flow and app startup. |
| Route guards | Done | Implemented in Flutter/admin flows. |
| Shared Flutter UI components | Done | Repository includes shared widgets such as scaffold, card, buttons, loading/error/empty views. |
| Backend folder structure | Done | Backend has `api`, `schemas`, `services`, `repositories`, `middleware`. |
| `events_db` migrations foundation | Done | Migrations 001–013 now exist. |
| Firebase token verification / backend JWT | Done | Auth exchange and `/auth/me` are implemented. |
| Health endpoint | Done | `/api/v1/health` verified PASS. |
| Request logging middleware | Not confirmed from current evidence | Needs code-level confirmation if required for closure. |
| Admin portal login and shell | Done | Admin portal build passes and pages exist. |

**Week 1 verdict:** PASS, with one minor confirmation item: request logging middleware.

---

### Week 2 — Event CRUD and Public Browsing

| Requirement | Status | Notes |
|---|---:|---|
| Public event listing | Done | `/api/v1/events/public` implemented and verified. |
| Public event detail | Done | `/api/v1/events/public/{event_id}` implemented and verified. |
| Join link hidden until registration | Done | Public API leak test verified; `virtual_url`/`join_url` are not exposed publicly. |
| Admin event creation form | Done | Event form exists and was extended in Week 5. |
| Admin event list | Done | Event list exists and now shows Full Day / Free / Paid pills. |
| Publish / close status operations | Done | Admin status workflows exist. |
| Event CRUD backend | Mostly done | Create, read, update, status changes done. General hard delete is intentionally not implemented, which is correct for audit safety. |
| Flutter event list/detail | Done | Existing tests and models cover public event list/detail. |
| Simple speaker list | Superseded | Week 5 replaces this with event people/speakers foundation; Flutter display still deferred. |

**Week 2 verdict:** PASS. Hard delete is not done by design and should remain out.

---

### Week 3 — Registration, Alumni, Email, Join Link

| Requirement | Status | Notes |
|---|---:|---|
| Alumni autofill `/alumni/me` | Done | Alumni DB read-only integration documented and implemented. |
| Registration endpoint | Done | `/api/v1/events/{event_id}/register` implemented. |
| Active alumni validation | Done | Verified through diagnostics and alumni DB rules. |
| Capacity enforcement | Done | Verified through diagnostics and concurrency review. |
| Duplicate registration guard | Done | Verified. |
| Registration deadline guards | Done | Closed / not-open-yet statuses verified. |
| Confirmation screen / registration number | Done | Flutter UI implemented earlier. |
| Confirmation email | Done | SMTP/log modes implemented; email status tracked. |
| My registration endpoint | Done | Implemented and verified. |
| My registrations list | Done | Implemented and verified. |
| Virtual join link visible post-registration | Done | Join URL rules implemented in registration responses. |
| Audit log on registration/email | Done | Registration audit/logging foundation exists; Week 5 added separate analytics log. |

**Week 3 verdict:** PASS.

---

### Week 4 — Attendee Management and Demo Readiness

| Requirement | Status | Notes |
|---|---:|---|
| Flutter error/loading/empty states | Mostly done | Earlier Week 4 verification says production cleanup completed; one Flutter test harness issue remains. |
| Registration closed CTA | Done | Verified in eligibility and UI behavior. |
| Cancelled event banner | Done / reported | Included in manual verification scope; not rechecked in attached docs. |
| `flutter analyze` clean | Done | Current report: 0 issues. |
| Admin attendee list | Done | `/api/v1/admin/events/{event_id}/attendees`. |
| Search/filter attendee list | Done | Search and batch-year filter documented and verified. |
| CSV export | Done | CSV export endpoint and security checks exist. |
| Event summary card | Done | Admin attendee page includes summary card. |
| Audit trail / admin registrations | Done | `/api/v1/admin/events/{event_id}/registrations` exists. |
| Load test both events | Partially confirmed | Diagnostics and E2E flows pass; formal load test evidence not shown in current files. |

**Week 4 verdict:** PASS for beta functionality. Formal load-test evidence remains a nice-to-have unless required by stakeholder.

---

### Week 5 — Event Enrichment and Diagnostics

| Requirement | Status | Notes |
|---|---:|---|
| Full Day events | Done | Migration 010, backend, admin, public API, diagnostics. |
| Free / Paid display fields | Done | `is_free`, `ticket_price`; no payment gateway, correctly deferred. |
| People / Speakers backend | Done | `event_people`, `session_people`, CRUD, public arrays. |
| Speakers derivation | Done | `SPEAKER`, `PANELIST`, `CHIEF_GUEST`, `GUEST_OF_HONOUR`. |
| Sponsors backend/admin CRUD | Done | `event_sponsors`, tier ordering, hidden filtering. |
| Partners backend/admin CRUD | Done | `event_partners`, ordering, hidden filtering. |
| Analytics logging foundation | Done | `event_activity_log`, non-blocking service, registration/email hooks. |
| Developer diagnostics | Done | Week 5 diagnostics: 48/48 PASS. |
| Admin enrichment UI | Done | `EventEnrichmentPanel` with People/Sponsors/Partners tabs. |
| Flutter Week 5 diagnostics category | Done | Added to developer diagnostics screen. |
| Flutter display of people/sponsors/partners | Pending / deferred | Backend/admin ready; user-facing Flutter display is a future sprint. |
| Cloud SQL migrations 010–013 | Blocking for cloud beta | Local migrations done; Cloud SQL execution still pending product-owner approval. |

**Week 5 verdict:** PASS locally. Cloud readiness is pending migration execution and validation.

---

## 3. Integration & Architecture Alignment Review

### 3.1 Identity and Firebase

| Architecture requirement | Status | Notes |
|---|---:|---|
| Use same Firebase project | Done / assumed | Current implementation uses Firebase auth; confirm production Firebase project before beta. |
| Backend JWT exchange after Firebase ID token | Done | `/api/v1/auth/firebase` and `/auth/me` implemented. |
| Shared JWT claim names | Done / likely | Claims include `firebase_uid`, `user_type`, `ref_id`, `graduation_year`. |
| `event_users` as login table | Done | Implemented. |
| Suspension enforcement | Needs confirmation | Mentioned in architecture note; not strongly evidenced in latest reports. |

**Risk:** Low. Confirm Firebase project ID and suspension behavior before public beta.

---

### 3.2 Alumni DB Read-Only Rule

| Architecture requirement | Status | Notes |
|---|---:|---|
| `alumni_db` is source of truth | Done | Documented and implemented. |
| Event app never writes to `alumni_db` | Done / documented | Manual verification guide explicitly warns not to write/migrate alumni DB. |
| Fetch alumni data for registration snapshot | Done | Registration stores snapshot fields at registration time. |
| Avoid stale profile data in `event_users`/registrations | Partially aligned | `registrations` intentionally stores snapshots. This is acceptable for audit/registration history, though original note warned against stale duplication. |

**Risk:** Low. Snapshotting registration data is intentional and already documented.

---

### 3.3 Event as Group / Role Model

| Architecture requirement | Status | Notes |
|---|---:|---|
| Event has coordinator / volunteers / attendees via `event_members` | Partially done | Base table exists from early migrations. Full coordinator/volunteer workflow is not a current beta focus. |
| Coordinator must be verified alumnus | Pending / not confirmed | Needs API-level verification before enabling coordinator assignment. |
| Volunteer is event-scoped, not global | Done at schema level | `event_members` supports event-scoped roles. |
| Avoid global `is_volunteer` | Done | No evidence of global volunteer flag. |

**Risk:** Medium for future operations workflow, low for current beta if admin access remains dev/admin-gated.

---

### 3.4 Notifications and `emit()` Pattern

| Architecture requirement | Status | Notes |
|---|---:|---|
| Use cloned `notify.py` / `emit()` | Partially implemented / uncertain | Repository has `backend/src/services/notify.py`, but current Week 3–5 implementation mainly references `email_service`, `audit_service`, and `analytics_service`. |
| Route handlers should not call mail service directly | Potential deviation | Current registration flow uses email service after registration; this may be intentional simplification but differs from integration note. |
| Audit and email should not roll back registration | Done | Email failure never rolls back registration. |
| In-app notifications | Pending / not beta-critical | Notifications table exists from migration 006, but user-facing notification bell is not part of current beta evidence. |

**Risk:** Medium for future website/platform integration. Not blocking current Week 5 commit, but should be explicitly documented as an intentional architecture deviation if not using `emit()`.

---

### 3.5 Public API Contract for Website Integration

| Architecture requirement | Current implementation | Status |
|---|---|---:|
| Public list at `GET /api/v1/events` | Current public list is `/api/v1/events/public` | Deviation |
| Public detail by slug: `GET /api/v1/events/{slug}` | Current public detail is `/api/v1/events/public/{event_id}` | Deviation |
| Slug stable public identifier | Events table has slug, but current public detail uses event_id | Partial |
| Public API includes coordinator object | Current API evidence does not show coordinator object | Pending |
| Sessions array always returned | Done; currently returns `[]` | Done |
| Post-event content object | Not confirmed / pending | Deferred |
| `virtual_url` not public | Done | Done |

**Risk:** High for future NITKSAA Website integration if website team expects the original contract. Current app is internally consistent, but public website-facing API should be aligned before website integration.

---

## 4. Blocking Items

These are the items that can block beta/cloud handoff or future integration.

| Blocker | Impact | Recommended action |
|---|---|---|
| Cloud SQL migrations 010–013 not applied | Week 5 features will not work in cloud/staging | Get product-owner approval, backup, apply one migration at a time, validate each. |
| Public API path mismatch with integration note | Website integration may require rework | Decide whether to support compatibility aliases: `/api/v1/events` and `/api/v1/events/{slug}` while keeping current endpoints. |
| `emit()` / notification architecture deviation | Future shared notification/audit integration may diverge | Document deviation or refactor later to use `emit()` pattern consistently. |
| Flutter test harness failure | Automated test suite not fully green | Fix GoRouter test harness in a test-maintenance sprint. |
| Local pytest DB config issue | Backend automated tests cannot be trusted locally | Make tests read DB user/URL from env instead of hardcoded role. |

---

## 5. Pending / Deferred Items

These are not blockers for the local Week 5 commit, but should remain in the roadmap.

| Pending item | Status | Suggested sprint |
|---|---:|---|
| Cloud SQL migration execution | Pending | Immediate operational step |
| Deployed staging / Cloud Run beta environment | Pending from Jun 30 beta handoff | Beta readiness sprint |
| Staff walkthrough doc | Pending / not shown | Beta handoff |
| Known issues list | Partially done via Week 5 status report | Beta handoff |
| Flutter people/speakers/sponsors/partners display | Deferred | Week 6 |
| Payment gateway | Deferred | Future |
| Rewards | Deferred | Future after analytics + QR |
| QR attendance/check-in | Deferred | Future |
| Meeting provider OAuth | Deferred | Future |
| Advanced analytics dashboard | Deferred | Future |
| Coordinator/volunteer operational workflows | Partial | Future admin/security sprint |
| Website integration public API aliases | Pending | Before website consumes event APIs |
| Post-event content display | Not confirmed | Future |
| Formal load test evidence | Partial | Before production use |

---

## 6. Recommended Next Actions

### Immediate — before Cloud/Beta

1. Commit the completed Week 5 local implementation and verification docs.
2. Apply Cloud SQL migrations 010–013 only after backup and approval.
3. Run Week 1–5 automated verification against cloud/staging.
4. Create beta staff walkthrough document.
5. Create final known-issues list for NITKSAA staff.

### Before Website Integration

1. Decide public API contract:
   - Keep current `/api/v1/events/public/{event_id}` for Flutter, and
   - Add website-compatible aliases `/api/v1/events` and `/api/v1/events/{slug}`, or update the integration note.
2. Confirm whether coordinator object is required in public responses.
3. Confirm post-event content response shape.
4. Reconcile notification `emit()` pattern with current email/audit implementation.

### Test Maintenance

1. Fix Flutter GoRouter test harness.
2. Fix pytest DB configuration to read from environment.
3. Add automated Week 1–5 verification suite if not already implemented.

---

## 7. Final Verdict

| Area | Verdict |
|---|---|
| Week 1–5 local development | PASS |
| Week 5 commit readiness | PASS |
| Cloud beta readiness | PENDING — migrations and staging validation required |
| Website integration readiness | PENDING — public API contract alignment required |
| Test automation maturity | PARTIAL — diagnostics strong, pytest/flutter harness issues remain |
| Overall | READY TO COMMIT LOCALLY; NOT YET READY TO DECLARE CLOUD BETA COMPLETE |

---

## 8. Short Status Summary

**Done:** Auth, event CRUD, public listing/detail, registration, alumni lookup, email confirmation, attendee management, CSV export, admin enrichment, Week 5 people/sponsors/partners/analytics foundations, diagnostics, and documentation.

**Blocking:** Cloud SQL migrations 010–013 and public API contract alignment for future website integration.

**Pending:** Cloud deployment validation, staff walkthrough, known issues list, Flutter enrichment display, test harness fixes, website-compatible public endpoints, and future out-of-scope features such as payment, QR, rewards, OAuth, and analytics dashboard.
