# Review Notes — DB Relationship Diagrams v1

Companion to [`db_relationship_diagrams_v1.md`](db_relationship_diagrams_v1.md). Documentation only;
no backend code or migrations were changed while producing either document.

---

## Assumptions found in code (confirmed)

1. `alumni_db` and `events_db` are two separate Postgres databases, connected via two independent
   asyncpg pools (`get_pool()`, `get_alumni_pool()` in `backend/app/database.py`). Confirmed by
   `backend/app/config.py` (`events_db_dsn` / `alumni_db_dsn` as separate properties) and
   `docs/architecture/alumni_db_integration_architecture_v1.md`.
2. `nitksaa-event` never writes to `alumni_db` — no `INSERT`/`UPDATE`/`DELETE` against the alumni
   pool appears anywhere in `backend/app/services/alumni_service.py`, the only module that queries it.
3. `ref_id` on `event_users` and `registrations` is a plain-text value reference to
   `alumni_db.alumni.alumni_id` — explicitly commented as "no FK" in
   `backend/migrations/events_db/001_create_events_alpha_schema.sql:7` and consistent with the live
   Week 3 schema.
4. Registration is alumni-only today: `registration_service.register_for_event` raises
   `403 alumni_only` if `user.user_type != 'alumni'` (`backend/app/services/registration_service.py:78-79`).
5. Snapshot fields (`fullname_snapshot`, `batch_year_snapshot`, `branch_snapshot`, plus `email`/`phone`
   reused as snapshot columns) are written once at INSERT and never updated afterward — confirmed by
   `registration_repository.py.insert()` and the absence of any `UPDATE ... fullname_snapshot` anywhere
   in the codebase.
6. `alumni_db.alumni` now has a `firebase_uid` column (read in
   `alumni_service.get_alumni_profile_by_ref_id`, `backend/app/services/alumni_service.py:53`) that is
   not mentioned in `alumni_db_integration_architecture_v1.md`'s field reference table and is not
   currently used by any downstream logic in `nitksaa-event`. Likely a recent portal-side addition.

---

## Unknowns / risks — flagged rather than assumed

### 1. Two competing schema tracks exist in `backend/migrations/events_db/` (highest priority)

There are two independent, mutually incompatible definitions of `events`, `registrations`, and
`check_ins`:

**Track A — "Alpha schema"**, single file `001_create_events_alpha_schema.sql`:
- `events`: `event_id BIGSERIAL`, `starts_at`/`ends_at`, `venue_name`, `event_type`
- `registrations`: `full_name` (not `fullname_snapshot`), `qr_token` column directly on the table
- **includes a first-class `attendees` table** (`attendee_id`, `registration_id` FK, `attendee_type`)
- `check_ins`: `check_in_id`, `attendee_id` FK, `qr_token`, `checked_in_at`, `checked_in_by`, `method`
- companion `check_in_attempts` audit table

**Track B — sequential Week 1–5 migrations**, `001_events.sql` through `013_week5_analytics.sql`:
- `events`: `event_id SERIAL`, `start_datetime`/`end_datetime`, `location_text`
- `registrations`: `fullname_snapshot`, `badge_name`, no `attendees` table at all
- `check_ins`: `checkin_id`, `scanned_by`, `scanned_at`, `result` (`success`/`duplicate`/`invalid`) —
  no `attendee_id`, no `check_in_attempts` table

These cannot both be applied to the same database — `001_events.sql` runs a bare
`CREATE TABLE events (...)` with no `IF NOT EXISTS`, which would fail if Track A's `events` table
already exists. All currently *live* application code
(`registration_service.py`, `registration_repository.py`, `events_service.py`, `events_repository.py`,
`event_repository.py` (singular, still present) — everything wired into `events.py` and
`registrations.py`) targets **Track B**. This is also what `alumni_db_integration_architecture_v1.md`
(dated 2026-06-24, marked "Authoritative") describes.

However, `backend/app/repositories/checkin_repository.py` and
`backend/app/services/checkin_service.py` — both live, both mounted via
`admin_events.py` → `main.py` (`app.include_router(admin_events.router)`) — are written against
**Track A**:
- `checkin_service.py` imports `EventRepository` from `event_repository.py` (singular — the Track A
  repository using `starts_at`), not `events_repository.py` (plural, Track B, used everywhere else).
- `checkin_service.py` calls `self.reg_repo.get_by_token(...)`,
  `self.reg_repo.get_attendee_by_registration(...)`, and
  `self.reg_repo.set_registration_status(...)` on a `RegistrationRepository` instance — but the only
  `RegistrationRepository` class that exists in the repo
  (`backend/app/repositories/registration_repository.py`) defines none of these three methods.

**Practical implication:** calling `POST /api/v1/events/{event_id}/check-ins` or
`GET /api/v1/events/{event_id}/check-in-attempts` today would raise an `AttributeError` at runtime
against the live `RegistrationRepository`, regardless of which migration track is actually applied to
the running database. The check-in feature appears to be dead/orphaned code left over from an earlier
Alpha slice that was never updated when `registrations`/`events` were redesigned for Week 3.

**Question for backend owner:** Is the check-in vertical (`admin_events.py` check-in endpoints,
`checkin_service.py`, `checkin_repository.py`, `event_repository.py` singular) intentionally
deprecated/pending a rewrite, or is there a missing piece (e.g. an uncommitted
`RegistrationRepository` extension) that would make it work? Should Track A's
`001_create_events_alpha_schema.sql` be deleted from the migrations directory to avoid a future
developer applying it by mistake, per the `backend/README.md` setup instructions which still tell new
developers to run it first?

### 2. Which migration track is actually applied to any real (dev/staging/prod) database is not verifiable from code alone

The repo contains SQL files for both tracks; there is no migration-runner tool or `schema_version`
table checked into the repo to record which files have actually been executed against a given
database. `backend/README.md` instructs `psql -d events_db -f
migrations/events_db/001_create_events_alpha_schema.sql` as the first setup step, then says
"... through the latest migration file" — implying a developer following the README literally would
try to apply both tracks and hit a `CREATE TABLE events` conflict on `001_events.sql`. This document's
main diagrams assume **Track B is what's actually running**, because that's what the live service/
repository code (and the "Authoritative" alumni integration doc) requires to function — but this
should be confirmed against the actual dev/staging database, not just inferred from code.

### 3. `attendee_type` column exists in two places with different meanings

- Track A's `attendees.attendee_type` (`TEXT NOT NULL DEFAULT 'alumni'`) — describes the *kind of
  person* attending.
- Track B's `registrations.attendee_type` (`VARCHAR(50)`, from `004_registrations_and_check_ins.sql`)
  — added in an early migration but never populated or read anywhere in current service/repository
  code (`grep` for `attendee_type` in `backend/app/` outside migrations returns no hits). It survived
  migration 008's column rewrite without being dropped or documented.

Given the future model in this document introduces its own `attendee_type` enum on
`attendee_profiles`, recommend explicitly deciding whether to repurpose the existing (currently
unused) `registrations.attendee_type` column or formally drop it as dead, rather than leaving a third,
undocumented meaning in place.

### 4. `event_members` table is unused by any current API path

`003_event_users_and_event_members.sql` defines `event_members` (event_id, firebase_uid, role,
status) — no service or repository file in `backend/app/` references it. Purpose and intended
consumer (admin roles per event? speaker/organizer assignment?) is unclear from code alone.

### 5. `alumni.firebase_uid` — new column, purpose unconfirmed

Flagged in "Assumptions" above. Worth confirming with `nitksaa-portal-v2` whether this is intended to
eventually replace `ref_id`-by-email matching in `find_alumni_by_email`, or is unrelated to
`nitksaa-event`'s integration.

### 6. No `payments` table exists yet anywhere in the codebase

Section 9/16's `PAYMENTS_FUTURE` entity in the future ER diagram is speculative and not grounded in
any existing schema, migration, or service code — included only because the task brief asked for it
as an optional future element. Treat it as a placeholder, not a proposal with any design detail behind
it.

---

## Recommended questions for the backend owner

1. Is the `admin_events.py` check-in vertical known to be broken, or is there context (uncommitted
   work, a different branch) that resolves the `RegistrationRepository` method mismatch?
2. Which migration files have actually been applied, in which order, to the current dev/staging
   database? Is `001_create_events_alpha_schema.sql` still needed, or safe to remove/archive?
3. What was `registrations.attendee_type` (migration 004) originally intended for, and is it safe to
   drop before building the future `attendee_type` enum on `attendee_profiles`?
4. Is `event_members` (migration 003) planned for use (e.g., event-level admin/organizer roles), or
   is it dead schema that predates a different authorization design?
5. Does `alumni.firebase_uid` (read in `alumni_service.get_alumni_profile_by_ref_id`) have a planned
   use in `nitksaa-event`, or is it currently vestigial from the portal side?
6. For Phase 3 in the migration strategy (§13 of the main doc): is extending `registrations` in place
   acceptable, or must the July 10 demo path be fully isolated via a new `event_registrations_v2`
   table for the rest of the Week 5+ timeline?
