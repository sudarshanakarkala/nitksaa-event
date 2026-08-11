# Next Week Backend Architecture Plan

**Date:** 2026-07-04
**Status:** Draft — planning only, nothing in this document has been implemented
**Depends on:** [`person_identity_architecture_v1.md`](person_identity_architecture_v1.md),
[`schema_track_cleanup_report.md`](schema_track_cleanup_report.md),
[`db_relationship_diagrams_v1.md`](db_relationship_diagrams_v1.md),
[`db_relationship_diagrams_review_notes.md`](db_relationship_diagrams_review_notes.md)

This plan covers design/documentation work only. No work package in this document authorizes writing
a migration, changing an API, or touching frontend code without a separate, explicit go-ahead.

---

## 1. Goals

- Resolve the two-migration-track ambiguity so every future schema change starts from a known-good
  baseline.
- Produce a reviewed, sign-off-ready design for `person_profiles` / `person_relationships` /
  `event_registrations` (v2) — design only, not yet built.
- Produce a concrete repair plan for the check-in vertical, which is confirmed broken against the
  live schema.
- Draft the next-generation API contract so frontend planning can start in parallel without backend
  code existing yet.
- Do all of this **without touching** the live alumni-only registration flow that the July 10 demo
  depends on.

## 2. Non-goals

- Implementing `person_profiles`, `person_relationships`, or `event_registrations` (v2) in code.
- Writing or running any new migration.
- Changing any existing API request/response shape.
- Building any frontend UI (Flutter or React admin).
- Deciding or implementing multi-tenancy for EV.ENGINEER / EV Society — flagged as a major open
  question, explicitly out of scope for next week.
- Fixing the check-in code itself — only *designing* the fix this week.

## 3. Critical Risks

| Risk | Why it matters | Mitigation this week |
|---|---|---|
| Two incompatible migration tracks in `backend/migrations/events_db/` | Any new table/column added without resolving this inherits the ambiguity | WP-001 resolves this via documentation + verification against a real database, before any schema design is finalized |
| Check-in code (`checkin_service.py`, `checkin_repository.py`) calls `RegistrationRepository` methods that don't exist | Confirmed to raise `AttributeError` at runtime if invoked; a live, mounted, but broken feature | WP-005 documents the repair design; do not attempt the repair itself this week |
| July 10 demo must not regress | Highest-priority constraint from the user | All work packages this week are additive documentation/design; zero production code changes planned |
| `person_profiles.email` uniqueness undecided | Blocks a clean schema design if deferred silently | Captured as an explicit open question in WP-002, not resolved by assumption |
| No multi-tenancy model exists | Requirement #15 implies a scope far beyond "add a table" | Explicitly deferred; do not let it creep into WP-002–004 designs |

## 4. Work Packages

### WP-001 — Migration Track Cleanup

- **Objective:** Produce a definitive, code-grounded map of which migration files belong to which
  track, which live code depends on which track, and a recommendation for archiving the dead track.
- **Files impacted (read-only this week):** `backend/migrations/events_db/*.sql`,
  `backend/app/repositories/event_repository.py`, `events_repository.py`,
  `registration_repository.py`, `checkin_repository.py`, `backend/README.md`.
- **Expected deliverables:** [`schema_track_cleanup_report.md`](schema_track_cleanup_report.md)
  (this week); a follow-up ticket (not filed yet) to actually archive
  `001_create_events_alpha_schema.sql` and correct the README.
- **Risk:** Low — read-only analysis. The only risk is mis-identifying which track is actually live
  in a real database; the report explicitly flags this as unverified from code alone and recommends
  a manual `\d` check against dev/staging.
- **Estimated effort:** 0.5 day (already substantially done as part of this task).
- **Acceptance criteria:** Report lists every migration file, its track, every consumer file, and a
  clear archive/keep recommendation, reviewed by the backend owner.

### WP-002 — Person Identity Model

- **Objective:** Finalize the `person_profiles` table design (columns, enums, constraints) as a
  reviewed proposal.
- **Files impacted (design only, no code changes):** none — output is
  [`person_identity_architecture_v1.md`](person_identity_architecture_v1.md) §5.
- **Expected deliverables:** Table design with explicit rules (alumni_ref_id constraint, source enum,
  verification_status enum), open questions logged (email uniqueness, minor/consent handling).
- **Risk:** Medium — a wrong `person_type` enum or missing rule now means a migration rewrite later.
  Mitigated by treating this week's design as reviewed-but-not-final.
- **Estimated effort:** 1 day (design + review cycle with backend owner).
- **Acceptance criteria:** Backend owner signs off on column list and rules before any migration is
  written in a future week.

### WP-003 — Relationship Model

- **Objective:** Finalize `person_relationships` design, including the `SELF` relationship
  convention and the `can_register_on_behalf` / `can_manage_profile` authorization flags.
- **Files impacted:** none this week — design output only
  ([`person_identity_architecture_v1.md`](person_identity_architecture_v1.md) §5, §11).
- **Expected deliverables:** Relationship type enum, authorization flag semantics, privacy rule
  (never exposed cross-user).
- **Risk:** Low-medium — relationship semantics are easy to under-specify (e.g. can a relationship be
  bidirectional?). This week's design treats all relationships as directed
  (`primary → related`), which should be explicitly confirmed with the backend owner.
- **Estimated effort:** 0.5 day.
- **Acceptance criteria:** Directionality, `SELF`-row convention, and privacy rule are explicitly
  confirmed, not just documented.

### WP-004 — Registration v2 Design

- **Objective:** Decide and document whether `event_registrations` (v2) is a new table or an
  in-place extension of `registrations`, and produce the full column design either way.
- **Files impacted:** none this week — recommendation only
  ([`person_identity_architecture_v1.md`](person_identity_architecture_v1.md) §5, §10 Phase 4).
- **Expected deliverables:** A recommendation (this document recommends **new table**) with
  reasoning, plus the full column list, ready for backend-owner sign-off.
- **Risk:** High relative to the other design WPs — this decision affects admin attendee export,
  analytics, and audit code that are all working today. Get explicit sign-off before Phase 4
  implementation in a future week.
- **Estimated effort:** 1 day (includes reasoning about reporting/analytics continuity).
- **Acceptance criteria:** Backend owner has explicitly chosen new-table vs. alter-table, with the
  tradeoffs from §10 acknowledged.

### WP-005 — Check-in Repair Design

- **Objective:** Fully document what's broken in the check-in vertical and design (not implement)
  the repaired version.
- **Files impacted (read-only this week):** `backend/app/services/checkin_service.py`,
  `backend/app/repositories/checkin_repository.py`, `backend/app/api/admin_events.py`,
  `backend/app/repositories/registration_repository.py`.
- **Expected deliverables:** [`person_identity_architecture_v1.md`](person_identity_architecture_v1.md)
  §12 — broken-method list, target schema, QR token security rules.
- **Risk:** Medium — check-in is demo-adjacent (badge/attendee features could touch it); must be
  clearly labeled "broken today, not to be relied on" so nobody assumes it works before the repair
  ships.
- **Estimated effort:** 0.5 day (analysis + design; actual repair is future work, not this week).
- **Acceptance criteria:** Backend owner confirms whether check-in is intentionally
  deprecated/pending rewrite (open question from the cleanup report) — this determines whether WP-005's
  design is acted on next, or the feature is shelved entirely.

### WP-006 — API Contract Draft

- **Objective:** Draft the future API surface (`/person/*`, `/register-v2`, admin speaker/guest/
  check-in endpoints) so frontend teams can plan against a stable contract before backend
  implementation begins.
- **Files impacted:** none — draft only
  ([`person_identity_architecture_v1.md`](person_identity_architecture_v1.md) §13).
- **Expected deliverables:** Table of endpoints with purpose, auth, request/response shape, and
  security notes.
- **Risk:** Low — a draft contract can change before implementation; explicitly labeled as draft.
- **Estimated effort:** 0.5 day.
- **Acceptance criteria:** Frontend leads have reviewed the draft and flagged any shape they'd need
  changed before committing to build against it.

### WP-007 — Frontend Impact Notes

- **Objective:** Give the Flutter and React admin teams a heads-up list of screens/flows that will be
  needed once the backend work lands, without building anything now.
- **Files impacted:** none.
- **Expected deliverables:** [`person_identity_architecture_v1.md`](person_identity_architecture_v1.md)
  §14 — bullet list of future UI work.
- **Risk:** Low.
- **Estimated effort:** 0.25 day.
- **Acceptance criteria:** Frontend teams acknowledge the list; no UI work is scheduled from it yet.

### WP-008 — Verification Plan

- **Objective:** Define how each future phase (Phase 1–7 in §10 of the person identity doc) will be
  verified before being considered done, so "documentation only" this week doesn't become
  "undocumented and unverified" next month.
- **Files impacted:** none this week.
- **Expected deliverables:** §7 checklist below.
- **Risk:** Low.
- **Estimated effort:** 0.25 day.
- **Acceptance criteria:** Checklist reviewed and accepted as the bar for "Phase N done."

---

## 5. Recommended Implementation Order

1. WP-001 (migration track cleanup) — must land first; every other design depends on knowing the
   real live schema.
2. WP-002 + WP-003 (person + relationship model design) — can proceed in parallel once WP-001's
   findings are confirmed.
3. WP-004 (registration v2 design) — depends on WP-002/003 being stable.
4. WP-005 (check-in repair design) — depends on WP-004's decision (check-in must attach to whichever
   registration model wins).
5. WP-006 (API contract draft) — depends on WP-002–005 being drafted, even if not yet signed off.
6. WP-007 (frontend impact notes) — depends on WP-006.
7. WP-008 (verification plan) — can be drafted in parallel with any of the above, finalized last.

## 6. What Not To Do Next Week

- Do not write any migration file, even an additive one.
- Do not modify `registration_service.py`, `registration_repository.py`, `checkin_service.py`, or
  `checkin_repository.py`.
- Do not touch `backend/app/main.py` router mounting.
- Do not start Flutter or React admin UI work based on the draft API contract — it is not final.
- Do not attempt to design or implement multi-tenancy — explicitly deferred.
- Do not delete `001_create_events_alpha_schema.sql` or any other file — archive/rename
  recommendations are documented, not executed, this week.
- Do not commit any of this week's documents without the user's explicit request.

## 7. Verification Checklist

For each future phase, before it is considered "done":

- [ ] **Phase 1 (track cleanup):** A manual schema dump (`\d` in `psql`) against the actual dev
      database confirms which track is live, matching or correcting this week's documented
      assumption.
- [ ] **Phase 2 (`person_profiles`):** Backfill row count matches distinct `ref_id`/`firebase_uid`
      count in `event_users` + `registrations`; no alumni row is duplicated.
- [ ] **Phase 3 (`person_relationships`):** Every backfilled `ALUMNI` person has exactly one `SELF`
      relationship row.
- [ ] **Phase 4 (`event_registrations` v2):** Old `registrations` table remains untouched and
      queryable; new table's capacity/eligibility checks are covered by tests equivalent to the
      existing `register_for_event` transaction-safety tests.
- [ ] **Phase 5 (family/friend/guest APIs):** Authorization checks (`can_register_on_behalf`) are
      covered by a negative test (unauthorized relationship cannot register).
- [ ] **Phase 6 (check-in repair):** `POST /check-ins` and `GET /check-in-attempts` are exercised
      end-to-end against the corrected schema, not just unit-tested against mocks.
- [ ] **Phase 7 (payments):** Not scoped yet — no checklist until design exists.

## 8. Decision Log

| Date | Decision | Rationale | Decided by |
|---|---|---|---|
| 2026-07-04 | Rename `attendee_profiles`/`attendee_relationships` to `person_profiles`/`person_relationships` | Not every person is an attendee (speakers, sponsors, volunteers who may never check in); person-first model is more general | This document, per explicit user direction |
| 2026-07-04 | Recommend `event_registrations` as a new table, not an in-place `registrations` extension | Isolates new schema risk from the working, demo-critical admin/analytics/audit read paths | This document — **pending backend-owner sign-off**, not final |
| 2026-07-04 | Check-in repair design deferred to after registration v2 lands | Check-in must attach to a stable registration model; building it against a model still in flux would mean redoing it twice | This document |
| 2026-07-04 | Multi-tenancy explicitly out of scope for next week | Requirement #15 is a substantial new architectural axis with no existing scaffolding (`tenant_id` appears nowhere in the codebase) | This document, flagged for future dedicated design work |
