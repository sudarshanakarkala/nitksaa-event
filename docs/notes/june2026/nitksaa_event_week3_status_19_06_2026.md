# NITKSAA Event App — Week 1 to Week 3 Progress Status Report

**Status:** Week 1, Week 2, and Week 3 backend scope complete
**Prepared for:** Week 4 Planning
**Scope Reviewed:** Beta Plan, Architecture Review, Architecture Observations, Integration Note, Week 1–3 implementation reports

---

## 1. Executive Summary

| Week   | Goal                                                                               | Current Status                                                                    |
| ------ | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Week 1 | Auth done end-to-end. Backend and DB standing.                                     | Complete                                                                          |
| Week 2 | Staff can create events. Public can browse and view details.                       | Complete                                                                          |
| Week 3 | Alumni can register. Confirmation email sent. Join link visible post-registration. | Backend complete. Developer Diagnostics complete. Production Flutter UI deferred. |
| Week 4 | Admin can manage attendees. Full end-to-end demo-ready.                            | Pending                                                                           |

The original beta plan defines Week 1 as authentication and backend/database foundation, Week 2 as event creation and public event browsing, Week 3 as alumni registration, and Week 4 as attendee management and export.

---

# 2. Week 1 Status — Authentication Foundation

## Goal

Auth done end-to-end. Backend and DB standing.

## Completed

| Area        | Item                        | Status |
| ----------- | --------------------------- | ------ |
| Flutter     | Email/password login        | Done   |
| Flutter     | Google Sign-In              | Done   |
| Flutter     | Auth state stream           | Done   |
| Flutter     | Route guards                | Done   |
| Flutter     | Session persistence         | Done   |
| Flutter     | Shared UI components        | Done   |
| Backend     | FastAPI folder structure    | Done   |
| Backend     | Firebase token verification | Done   |
| Backend     | Backend JWT exchange        | Done   |
| Backend     | `/auth/firebase`            | Done   |
| Backend     | `/auth/me`                  | Done   |
| Backend     | Health endpoint             | Done   |
| Backend     | Request logging             | Done   |
| Backend     | CORS                        | Done   |
| Database    | Initial migrations          | Done   |
| Admin       | Admin login                 | Done   |
| Admin       | Admin route guard           | Done   |
| Admin       | Admin shell layout          | Done   |
| Diagnostics | Auth diagnostics            | Done   |

## In Progress

None.

## Pending

| Item                                                | Reason            |
| --------------------------------------------------- | ----------------- |
| Production deployment auth validation               | Beta/staging task |
| Firebase authorized domain verification for staging | Deployment task   |

## Blockers

None for Week 1.

---

# 3. Week 2 Status — Event Management and Public Listing

## Goal

Staff can create events. Public users can browse and view event details.

## Completed

| Area         | Item                               | Status |
| ------------ | ---------------------------------- | ------ |
| Backend      | Event CRUD APIs                    | Done   |
| Backend      | Create event as draft              | Done   |
| Backend      | Publish / unpublish / cancel       | Done   |
| Backend      | Soft delete / cancel behaviour     | Done   |
| Backend      | Public event listing               | Done   |
| Backend      | Public event detail                | Done   |
| Backend      | Join URL hidden from public APIs   | Done   |
| Backend      | Dynamic public event card metadata | Done   |
| Backend      | `show_attendee_list` flag          | Done   |
| Backend      | Event diagnostics                  | Done   |
| Admin        | Event list                         | Done   |
| Admin        | Event create/edit form             | Done   |
| Admin        | Publish/unpublish/cancel actions   | Done   |
| Flutter      | Public event list                  | Done   |
| Flutter      | Upcoming / Past tabs               | Done   |
| Flutter      | Event cards                        | Done   |
| Flutter      | Event detail                       | Done   |
| Flutter      | Register CTA placeholder           | Done   |
| Verification | End-to-end Week 2 verification     | Done   |

## In Progress

None.

## Pending

| Item                                         | Status                          | Notes                                                                                  |
| -------------------------------------------- | ------------------------------- | -------------------------------------------------------------------------------------- |
| Public slug-based URL alignment              | Pending / needs decision        | Architecture recommends public URLs use slug, not only event ID.                       |
| Separate `registration_open` lifecycle state | Pending / architecture decision | Architecture observation recommends separating published from registration-open state. |
| Website integration API final alignment      | Pending                         | Website will later consume Event APIs directly.                                        |

## Blockers

No active Week 2 blocker.

## Important Architecture Note

Hard delete should not be used for events. Events should move to cancelled or archived state so registrations, audit logs, and future payment records remain consistent.

---

# 4. Week 3 Status — Registration, Alumni Autofill, Email, Join Link

## Goal

Alumni can register. Confirmation email sent. Join link visible post-registration.

## Completed — Backend

| Area    | Item                                               | Status |
| ------- | -------------------------------------------------- | ------ |
| Backend | `GET /api/v1/alumni/me`                            | Done   |
| Backend | `POST /api/v1/events/{id}/register`                | Done   |
| Backend | `GET /api/v1/events/{id}/registration-eligibility` | Done   |
| Backend | `GET /api/v1/events/{id}/my-registration`          | Done   |
| Backend | `GET /api/v1/my/registrations`                     | Done   |
| Backend | Alumni-only validation                             | Done   |
| Backend | Active alumni validation                           | Done   |
| Backend | Capacity enforcement                               | Done   |
| Backend | Duplicate prevention                               | Done   |
| Backend | Registration deadline enforcement                  | Done   |
| Backend | Registration number generation                     | Done   |
| Backend | Dynamic `registered_count`                         | Done   |
| Backend | Confirmation email service                         | Done   |
| Backend | Email-after-commit behaviour                       | Done   |
| Backend | Join URL reveal for registered virtual events      | Done   |
| Backend | Public API leak protection                         | Done   |
| Backend | Audit logging                                      | Done   |

## Completed — Database

| Item                                                  | Status |
| ----------------------------------------------------- | ------ |
| Migration 008 — registration schema alignment         | Done   |
| Migration 009 — audit log JSONB context               | Done   |
| Partial unique index for active registrations         | Done   |
| `qrtoken` nullable because QR is deferred             | Done   |
| Registration status aligned to `registered/cancelled` | Done   |

## Completed — Flutter Diagnostics

| Item                                         | Status |
| -------------------------------------------- | ------ |
| Developer Diagnostics registration category  | Done   |
| Registration UX prototype inside diagnostics | Done   |
| Alumni profile preview                       | Done   |
| Eligibility preview                          | Done   |
| Register action preview                      | Done   |
| Confirmation preview                         | Done   |
| My Registration preview                      | Done   |
| My Registrations preview                     | Done   |
| Negative state gallery                       | Done   |
| Public leak check                            | Done   |

## Completed — Documentation

| Document                            | Status |
| ----------------------------------- | ------ |
| Week 3 backend API contract v2      | Done   |
| Week 3 actual API response shapes   | Done   |
| Week 3 manual verification guide    | Done   |
| Week 3 getting started guide        | Done   |
| Week 3 closure report               | Done   |
| Week 3 readiness review             | Done   |
| Week 3 documentation cleanup report | Done   |

## In Progress

| Item                                                                               | Status                          |
| ---------------------------------------------------------------------------------- | ------------------------------- |
| Additional manual verification guide update: SEC-07, SEC-08, API-01, API-02, DB-07 | Pending documentation update    |
| Week 3 UX showcase in Developer Diagnostics                                        | Optional / recommended for demo |

## Pending

| Area                  | Item                                                   | Status           |
| --------------------- | ------------------------------------------------------ | ---------------- |
| Flutter Production UI | Registration screen                                    | Pending / Week 4 |
| Flutter Production UI | Autofill name + batch year on real registration screen | Pending / Week 4 |
| Flutter Production UI | Single register tap production flow                    | Pending / Week 4 |
| Flutter Production UI | Event Full disabled CTA                                | Pending / Week 4 |
| Flutter Production UI | Already Registered state                               | Pending / Week 4 |
| Flutter Production UI | Confirmation screen                                    | Pending / Week 4 |
| Flutter Production UI | Add to Calendar prompt                                 | Pending / Week 4 |
| Flutter Production UI | Post-registration Event Detail state                   | Pending / Week 4 |
| Flutter Production UI | Join link shown on production detail screen            | Pending / Week 4 |
| Flutter Production UI | Venue map link for physical event                      | Pending / Week 4 |
| React Admin           | Attendee list page                                     | Pending / Week 4 |
| React Admin           | Search registrations                                   | Pending / Week 4 |
| React Admin           | Batch year filter                                      | Pending / Week 4 |
| React Admin           | CSV export                                             | Pending / Week 4 |
| React Admin           | Registered count summary card                          | Pending / Week 4 |

## Blockers

| Blocker                                      | Severity    | Status                             |
| -------------------------------------------- | ----------- | ---------------------------------- |
| `ALUMNI_DB_URL` local setup was undocumented | Resolved    | `GETTING_STARTED_WEEK3.md` created |
| API response shape mismatch in manual guide  | Resolved    | Guide corrected                    |
| Missing actual API response shapes document  | Resolved    | Document created                   |
| Production Flutter UI not built              | Not blocker | Deferred by design                 |
| Admin attendee management not built          | Not blocker | Week 4 scope                       |

---

# 5. Architecture Compliance Review

| Architecture Rule                            | Status |
| -------------------------------------------- | ------ |
| Same Firebase identity anchor                | Done   |
| Backend JWT after Firebase exchange          | Done   |
| `events_db` owns event data                  | Done   |
| `alumni_db` remains source of truth          | Done   |
| Frontend does not access DB directly         | Done   |
| Public APIs hide virtual/join URL            | Done   |
| Protected APIs require backend JWT           | Done   |
| Admin actions protected by backend           | Done   |
| Developer diagnostics environment gated      | Done   |
| Audit records for sensitive actions          | Done   |
| Email failure does not rollback registration | Done   |

The architecture review states that the Event App must reuse the same identity/infrastructure approach and keep `events_db` and `alumni_db` separate.

---

# 6. Deferred Scope

The following are intentionally not done yet:

| Feature                            | Target                 |
| ---------------------------------- | ---------------------- |
| Production Flutter registration UI | Week 4                 |
| Admin attendee management          | Week 4                 |
| CSV export                         | Week 4                 |
| Attendance tracking                | Future                 |
| QR check-in                        | Future                 |
| Waitlist                           | Future                 |
| Payments                           | Future                 |
| Sessions/tracks                    | Deferred from June MVP |
| Push notifications                 | Future                 |
| Analytics dashboard                | Future                 |

The beta plan explicitly keeps sessions/tracks and QR check-in out of scope for the Jun 30 beta.

---

# 7. Week 4 Recommended Start Scope

## Phase 1 — Flutter Production Registration UI

| Deliverable                    | Priority |
| ------------------------------ | -------- |
| Registration screen            | High     |
| Alumni autofill display        | High     |
| Eligibility state handling     | High     |
| Confirmation screen            | High     |
| My Registrations screen        | High     |
| Join link / venue map handling | High     |
| Add to calendar prompt         | Medium   |

## Phase 2 — Admin Attendee Management

| Deliverable                         | Priority |
| ----------------------------------- | -------- |
| Attendee list endpoint verification | High     |
| Admin attendee table                | High     |
| Search by name                      | High     |
| Batch year filter                   | Medium   |
| CSV export                          | High     |
| Event registration summary          | High     |

## Phase 3 — Beta Readiness

| Deliverable             | Priority |
| ----------------------- | -------- |
| Staging deployment      | High     |
| Staff walkthrough guide | High     |
| Known issues list       | High     |
| Final beta demo script  | High     |

---

# 8. Final Status Matrix

| Category                           |    Done |                In Progress |                      Pending | Blocker           |
| ---------------------------------- | ------: | -------------------------: | ---------------------------: | ----------------- |
| Week 1 Auth                        |    100% |                         0% |                           0% | No                |
| Week 2 Event Management            |    100% |                         0% | Minor architecture alignment | No                |
| Week 3 Backend Registration        |    100% |                         0% |                           0% | No                |
| Week 3 Diagnostics Prototype       |    100% |       Optional UX showcase |                           0% | No                |
| Week 3 Documentation               | 95–100% | Additional 5 tests pending |   Small documentation update | No                |
| Production Flutter Registration UI |      0% |                         0% |                         100% | No — Week 4 scope |
| Admin Attendee Management          |      0% |                         0% |                         100% | No — Week 4 scope |
| Beta Deployment                    |      0% |                         0% |                         100% | Upcoming          |

---

# 9. Recommendation

Week 1, Week 2, and Week 3 should be considered complete for backend, diagnostics, and documentation scope.

Before tagging `week3-complete`, complete one final documentation update:

* Add SEC-07
* Add SEC-08
* Add API-01
* Add API-02
* Add DB-07

Then commit and tag:

```bash
git add .
git commit -m "Complete Week 3 registration backend diagnostics and documentation"
git tag week3-complete
git push origin main --tags
```

After tagging, start Week 4 planning.

---

# 10. Overall Recommendation

**GO for Week 4 planning.**

Week 4 should focus on production Flutter registration UI and Admin attendee management, not backend registration redesign.
