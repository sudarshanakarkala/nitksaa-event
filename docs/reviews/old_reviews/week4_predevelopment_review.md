# Week 4 Pre-Development Review

**Date:** 2026-06-22
**Reviewer:** CAR SOFTWARE SYSTEMS
**Branch:** main
**Scope:** Week 4 readiness gate — registration backend, email, admin attendee management, Flutter login UI,
alumni_db integration, and architecture decisions for new feedback items.

---

## Summary

Week 3 closed with all 15 in-scope deliverables complete and all 12 quality gates passing. The registration
backend is production-ready. The confirmation email service exists but runs in log mode only — no real email
has been sent in staging or production. The admin attendee management layer is entirely unbuilt (two 501
stubs). The production Flutter registration UI was correctly deferred from Week 3 but must be built in
Week 4. Week 4 carries a larger implementation load than the beta plan implies: it includes the deferred
Flutter production UI, admin attendee management from scratch, production readiness fixes, and architecture
decisions for eight new product feedback items.

**Conditional GO for Week 4.** Five open issues from Week 3 carry forward. Three architecture decisions must
be resolved before implementation begins.

---

## Week 3 Final Status

| Deliverable | Status | Notes |
|---|---|---|
| Registration data model (migration 008) | DONE | 21-column registrations table |
| Audit log column (migration 009) | DONE | `context` column on event_audit_log |
| `GET /api/v1/alumni/me` | DONE | Flat AlumniProfileResponse |
| `POST /api/v1/events/{id}/register` | DONE | SELECT FOR UPDATE, capacity check, email post-commit |
| `GET /api/v1/events/{id}/my-registration` | DONE | join_url only for virtual+published+registered |
| `GET /api/v1/my/registrations` | DONE | Flat list with embedded event sub-object |
| `GET /api/v1/events/{id}/registration-eligibility` | DONE | 6 eligibility states |
| Confirmation email service | DONE | log mode only — see Email Gap section |
| Audit service (`emit()`) | DONE | Never raises; no PII in context |
| `registered_count` live subquery | DONE | Correlated subquery in events endpoints |
| Developer diagnostics (13 checks) | DONE | 13/13 PASS |
| Flutter UX prototype (7 sections) | DONE | Reference for production UI |
| Production Flutter registration UI | **NOT BUILT** | Correctly deferred, must be built Week 4 |
| Admin registration management | **NOT BUILT** | 501 stubs — must be built Week 4 |

Runtime verification: 63/63 PASS. Flutter analyze: 0 issues. Flutter test: 16/16 PASS.

---

## Pending Blockers

### BLOCKER 1 — Real confirmation email is not delivered

`EMAIL_MODE=log` is the default and current staging configuration. The email service writes to the Python
logger and returns `status='sent'`, so the registration row shows `confirmation_email_status='sent'` even
though no email reached the user's inbox. An alumnus registering via the production Flutter app would
receive no confirmation email.

**Required before Week 4 demo:** `EMAIL_MODE=send` with SMTP credentials (`SMTP_USER`, `SMTP_PASSWORD`)
set in the staging environment. The SMTP configuration already exists in `app/config.py` — only the
environment variables are missing.

**Secondary issue:** `email_service.send_confirmation_email()` is `async def` but uses `smtplib.SMTP`,
which is synchronous. Under load, the SMTP connection (1–3 seconds) will block the FastAPI async event
loop. Fix: wrap the SMTP call in `asyncio.to_thread()` or switch to BackgroundTasks as portal-v2 does.

### BLOCKER 2 — Admin attendee management backend is a 501 stub

Both `GET /api/v1/admin/events/{event_id}/registrations` and `GET /api/v1/admin/events/{event_id}/attendees`
in `admin_events.py` raise `HTTPException(status_code=501)`. The admin portal `AttendeesPage.jsx` is a
placeholder. The `RegistrationsPage.jsx` still says "Coming in Week 3" (stale text — must be updated).
No search, filter, or CSV export is implemented anywhere. The entire admin attendee management layer needs
to be built from scratch in Week 4.

### BLOCKER 3 — Production Flutter registration UI was not built

The production registration screen (triggered from EventDetailScreen), the my-registrations screen, and
the confirmation screen are not implemented. Only the developer diagnostics prototype exists as a reference.
The Flutter app has no way for an alumnus to complete a real registration end-to-end. This was the correct
deferral in Week 3 but is now the highest-priority Flutter item in Week 4.

### OPEN ISSUE — OI-3: Eligibility status values must be agreed before Flutter UI is coded

`eligibility_status` strings in the backend (`eligible`, `full`, `closed`, `not_open_yet`, `ineligible`)
differ from contract v1 (`can_register`, `event_full`, `registration_closed`, etc.). The API contract v2
documents the actual values. The Flutter developer must use v2 values — **this agreement must happen
before any production eligibility UI code is written.**

### OPEN ISSUE — ALUMNI_DB_URL local dev setup

Any developer onboarding to a new machine will have no local `alumni_db` and no `ALUMNI_DB_URL` in their
`.env`. All alumni-gated flows (registration, eligibility, autofill) will fail silently or 500. The local
setup guide must include these steps before Week 4 Flutter work begins.

---

## Review Meeting Feedback

The following items were raised in the architecture review meeting. They are **not casual future ideas**.
They are confirmed architecture gaps that require design documentation in Week 4. Implementation of each
is deferred unless the product owner explicitly approves it. Full decisions and table schemas are in
`docs/reviews/week4_feedback_architecture_decisions.md`.

### WhatsApp Review Feedback Summary

The following specific points were raised in the review discussion:

1. **Sessions table exists but speakers and sessions are exposed as empty arrays or hard-coded** in the
   current public event detail API. This is not a missing feature — it is an incomplete wire-up of
   existing schema to the API response.
2. **Speakers are not the only event people.** A speaker is one role. The model must also accommodate
   hosts, moderators, panelists, chief guests, guests of honour, and organizers. A flat `speaker_name`
   field per session does not scale.
3. **Sponsors and partners must not be merged.** Sponsors provide financial/brand support. Partners
   provide collaboration support (media, knowledge, venue, technology, community). They have different
   display conventions, different tier models, and should not share a table or a type enum.
4. **Performance vs. extensibility tradeoff acknowledged.** Separate sponsors/partners tables add joins.
   For public event detail the backend fetches and merges them. This is the correct tradeoff — clarity
   and extensibility over premature optimization. Caching can be added later.

### Architecture Gap Table

| Item | Current State | Architecture Status | Implementation |
|---|---|---|---|
| Full day / all day event | `start_datetime`/`end_datetime` only. No `is_full_day` or duration type | **Architecture required Week 4** | Deferred unless approved |
| People — speakers, hosts, moderators, panelists | Sessions table: one `speaker_name` per session. No event-level people model | **Architecture required Week 4** | Deferred unless approved |
| Sponsors | No schema. Not in any migration | **Architecture required Week 4** | Deferred unless approved |
| Partners | No schema. Not in any migration. Must not be merged with sponsors | **Architecture required Week 4** | Deferred unless approved |
| Meeting link generation | `virtual_url` is a static text field | Architecture documented — manual URL is permanent Alpha choice | OAuth deferred indefinitely |
| Analytics / event activity log | `registered_count` correlated subquery only. No analytics table | **Architecture required Week 4** | Deferred unless approved |
| Engagement rewards | Not in any schema | **Architecture required Week 4** | Deferred — do not implement |
| Registration fee / paid events | Not in schema. Payment explicitly out of scope | **Architecture required Week 4** | Payment deferred — free only for Alpha |

---

## Week 4 Scope Recommendation

Week 4 carries two mandatory deliverables from the beta plan plus one deferred item from Week 3:

**Must complete to meet Jun 30 beta:**
1. Production Flutter registration UI — registration screen, confirmation screen, my-registrations screen
2. Admin attendee management — backend list endpoint, search/filter, CSV export, admin portal table page
3. Production readiness — real email delivery in staging, event loop fix on SMTP call

**Should complete in Week 4:**
4. Flutter production error states, loading skeletons, empty states (listed in beta plan)
5. Login UI cleanup — remove "Signing in with Firebase..." technical status messages
6. RegistrationsPage.jsx stale text fix ("Coming in Week 3" → appropriate message)

**Defer from Week 4:**
- All feedback items (full day, people, sponsors, analytics, rewards, payment)
- QR check-in
- Waitlist
- Sessions/tracks UI in Flutter

---

## What To Implement First

**Day 1–2 of Week 4 (unblock the Flutter developer):**
1. Resolve OI-3 eligibility status values (10-minute decision, not an implementation task)
2. Confirm `ALUMNI_DB_URL` setup for each developer machine
3. Set `EMAIL_MODE=send` + SMTP credentials in staging environment
4. Fix `send_confirmation_email()` event loop blocking (wrap in `asyncio.to_thread()`)

**Backend (Day 1–3):**
5. Implement `GET /api/v1/admin/events/{event_id}/attendees` with pagination + search
6. Implement `GET /api/v1/admin/events/{event_id}/attendees/export` (CSV)
7. Replace 501 stubs in `admin_events.py`

**Flutter (Day 1–5, can run in parallel with backend):**
8. Production registration screen (autofill from `/alumni/me`, confirm, single-tap register)
9. Confirmation screen (registration number, event summary)
10. My-registrations screen (list view)
11. Error states, loading skeletons, empty states across all screens

**Admin portal (Day 3–5):**
12. Wire `AttendeesPage.jsx` to real API
13. Add search bar (name) and batch year filter
14. Add CSV export button
15. Update `RegistrationsPage.jsx` stale text

---

## What To Defer

**Architecture documents must be written in Week 4 for all items in this table.**
Implementation is deferred unless the product owner explicitly approves it before work begins.

| Item | Architecture Doc | Implementation |
|---|---|---|
| Full day / all day event (`event_duration_type` enum) | `docs/architecture/` — required Week 4 | Deferred — requires migration + admin form + Flutter display |
| People — speakers, hosts, moderators, panelists, chief guests | `event_people_speakers_architecture_v1.md` — required Week 4 | Deferred — requires new table, session_people join table, API update |
| Sponsors (financial/brand support, tiered) | `event_sponsors_partners_architecture_v1.md` — required Week 4 | Deferred — new table + admin UI |
| Partners (media, knowledge, venue, etc. — separate from sponsors) | Same doc as above | Deferred — separate table + admin UI |
| Meeting link generation (OAuth) | Architecture documented — manual URL is permanent Alpha | OAuth deferred indefinitely; static `virtual_url` is the production answer for Alpha |
| Analytics / event activity log | `event_analytics_architecture_v1.md` — required Week 4 | Deferred — new table, no Flutter UI change in Alpha |
| Engagement rewards | `engagement_rewards_architecture_v1.md` — required Week 4 | Deferred — do not implement, no exceptions |
| Registration fee / paid events | `paid_events_architecture_v1.md` — required Week 4 | Payment deferred — free only for Alpha, no payment gateway |
| Sessions/tracks Flutter UI | Covered in people/speakers arch doc | Deferred — not in Week 4 beta plan scope |
| QR check-in | No new arch doc needed | Deferred — not in Week 4 beta plan scope |
| Waitlist | No new arch doc needed | Deferred — not in Week 4 beta plan scope |

---

## Risks

| Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|
| Week 4 scope is larger than the beta plan implies | HIGH | CERTAIN | Production Flutter UI + admin layer + readiness fixes are all Week 4 — plan accordingly |
| Email never lands in user inbox (staging) | HIGH | CERTAIN if unaddressed | Set EMAIL_MODE=send + SMTP credentials before any demo |
| SMTP call blocks event loop under load | MEDIUM | HIGH under concurrent registrations | Fix with asyncio.to_thread() early in the week |
| OI-3 disagreement delays Flutter production UI | HIGH | LOW if resolved Day 1 | Resolve immediately; record in writing |
| alumni_db not set up on new developer machines | MEDIUM | HIGH | Add to setup guide; verify before Flutter work starts |
| Admin portal RegistrationsPage.jsx still shows "Coming in Week 3" | LOW | CERTAIN | One-line fix; do not demo with stale text |
| Login screen leaks "Signing in with Firebase..." to users | LOW | LOW operational impact | Fix during Flutter polish phase |
| Event loop SMTP blocking causes 5–30s registration delay per user | MEDIUM | HIGH if untreated | asyncio.to_thread() is a one-line fix |

---

## Required Architecture Decisions

These three decisions must be resolved before implementation begins. Decisions affect which migration is
written and what API shape the Flutter developer codes against.

| Decision | Options | Recommendation |
|---|---|---|
| **D-1: Email delivery in staging** | log mode, Gmail SMTP, SendGrid | Use Gmail SMTP (same as website and portal-v2). Set `EMAIL_MODE=send` with existing gmail app password from Secret Manager. |
| **D-2: Attendees endpoint naming** | `/attendees` (active only) vs `/registrations` (all statuses) | Implement both. `/attendees` returns `status='registered'` rows for admin display. `/registrations` returns all statuses for audit purposes. See API contract doc. |
| **D-3: Eligibility status strings** | Keep actual v2 values vs rename to v1 values | Keep actual v2 values (`eligible`, `full`, `closed`, `not_open_yet`, `ineligible`). Document in v2 contract. Flutter developer must use v2 values. |

See `docs/reviews/week4_feedback_architecture_decisions.md` for the eight feedback-item decisions.

---

## Recommended Phase Plan

| Phase | Scope | Days | Owner |
|---|---|---|---|
| Phase 0 | Architecture decisions, OI-3 resolution, env setup | Day 1 | All |
| Phase 1 | Production readiness fixes (email, event loop, stale text) | Day 1–2 | Backend |
| Phase 2 | Admin attendee management backend + portal UI | Day 1–4 | Backend + Frontend |
| Phase 3 | Production Flutter registration UI + confirmation + my-registrations | Day 1–5 | Flutter |
| Phase 4 | Flutter polish (error states, skeletons, empty states, login cleanup) | Day 4–5 | Flutter |
| Verification | End-to-end demo walkthrough (both event types) | Day 5 | All |

Full execution detail in `docs/reviews/week4_execution_plan.md`.

---

## PASS / FAIL To Start Week 4

| Gate | Status |
|---|---|
| Week 3 backend implementation complete | **PASS** |
| Week 3 quality gates (63/63, 13/13, 15/15) | **PASS** |
| Week 3 security invariants verified | **PASS** |
| Open issues are non-blockers for starting | **PASS** (with conditions below) |
| Real email delivery in staging | **FAIL** — EMAIL_MODE=log, no SMTP credentials |
| Admin attendee management backend implemented | **FAIL** — 501 stubs |
| Production Flutter registration UI | **FAIL** — not yet built |
| Login UI: no raw Firebase technical messages | **RISK** — unmapped error codes expose SDK messages |
| ALUMNI_DB_URL documented for new developers | **RISK** — memory note exists, no README entry |
| OI-3 eligibility_status values agreed | **RISK** — must resolve before production Flutter UI |

### Verdict: CONDITIONAL GO

**GO conditions (must be resolved before Week 4 production code is accepted):**

1. OI-3 eligibility_status values agreed in writing before Flutter registration UI is written.
2. `ALUMNI_DB_URL` setup verified on every developer machine before Flutter testing begins.
3. `EMAIL_MODE=send` + SMTP credentials confirmed in staging before Week 4 demo.
4. `send_confirmation_email()` async/event-loop fix applied before load testing.
