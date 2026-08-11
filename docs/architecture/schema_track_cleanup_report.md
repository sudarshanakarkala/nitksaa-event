# Schema Track Cleanup Report

**Date:** 2026-07-04
**Status:** Draft — analysis only, no files archived/deleted/renamed
**Related:** [`db_relationship_diagrams_review_notes.md`](db_relationship_diagrams_review_notes.md)
(original finding), [`person_identity_architecture_v1.md`](person_identity_architecture_v1.md) §11–12,
[`next_week_backend_architecture_plan.md`](next_week_backend_architecture_plan.md) WP-001

This report is grounded entirely in static code inspection (migrations directory + `grep`/`import`
tracing across `backend/app/`). It does not connect to any database — the "which track is actually
live" conclusion is inferred from which application code imports which repository, not from
inspecting a running schema. That distinction is called out explicitly below and should be verified
against a real database before acting on this report.

---

## Alpha schema files (Track A)

**Single file:** `backend/migrations/events_db/001_create_events_alpha_schema.sql`

Defines, in one migration:
- `events` — `event_id BIGSERIAL`, `starts_at`/`ends_at`, `venue_name`, `venue_address`, `city`,
  `country`, `event_type`
- `sessions` — `speaker_name`, `track_name`
- `registrations` — `full_name`, `qr_token` (directly on the table), `registration_source`,
  `metadata JSONB`
- `attendees` — **a first-class attendee entity**, FK to `registrations`, `attendee_type`,
  `display_name`, `badge_name`
- `check_ins` — `check_in_id`, `attendee_id` FK, `qr_token`, `checked_in_at`, `checked_in_by`,
  `method`, unique on `(event_id, registration_id)`
- `check_in_attempts` — `attempt_id`, `attempt_status` CHECK (`success`/`duplicate`/`invalid`/
  `unauthorized`), `attempted_by`, `attempted_at`

Comment at the top of the file: *"Rules: No cross-database foreign keys ... ref_id = ...
alumni_id stored as plain TEXT reference"* — the cross-DB design principle is correct and consistent
with Track B; only the table shapes diverge.

## Current schema files (Track B)

**Sequential files, in order:**

| File | What it adds |
|---|---|
| `001_events.sql` | `events` — `event_id SERIAL`, `start_datetime`/`end_datetime`, `location_text`, `location_maps_url`, `is_virtual`, `virtual_url`, `capacity` |
| `002_sessions.sql` | `sessions` (Track B shape — not inspected in this report, no conflicting consumer found) |
| `003_event_users_and_event_members.sql` | `event_users`, `event_members` |
| `004_registrations_and_check_ins.sql` | `registrations` — `firebase_uid` FK, `badge_name`, `qrtoken` (nullable later), `attendee_type` (added, never used downstream — see below); `check_ins` — `checkin_id`, `scanned_by`, `scanned_at`, `result` CHECK (`success`/`duplicate`/`invalid`) |
| `005_event_content.sql` | event content tables (not inspected — no conflict found) |
| `006_audit_notifications.sql` | `event_audit_log`, `notifications`, `notification_preferences` |
| `007_add_show_attendee_list.sql` | adds `show_attendee_list` flag to events |
| `008_week3_registration_alignment.sql` | **Major rewrite of `registrations`**: drops `confirmation_email_sent`, adds `fullname_snapshot`, `batch_year_snapshot`, `branch_snapshot`, `registration_number`, 3-column email-status tracking, `updated_at`; converts hard unique `(event_id, firebase_uid)` to a partial unique index on active registrations |
| `009_add_audit_log_context.sql` | adds `context JSONB` to `event_audit_log` |
| `010_week5_phase1_event_options.sql` | event options (not inspected — no conflict found) |
| `011_week5_people.sql` | `event_people`, `session_people` — **display-only** speaker/host/guest cards, unrelated to registration/attendance |
| `012_week5_sponsors_partners.sql` | `event_sponsors`, `event_partners` — **display-only** organization banners, no person/representative column |
| `013_week5_analytics.sql` | analytics tables (not inspected — no conflict found) |

---

## Conflicting tables

| Table | Track A shape | Track B shape | Conflict |
|---|---|---|---|
| `events` | `event_id BIGSERIAL`, `starts_at`/`ends_at`, `venue_name` | `event_id SERIAL`, `start_datetime`/`end_datetime`, `location_text` | Different PK type and different column names for the same concept — cannot coexist under one `CREATE TABLE events` |
| `registrations` | `full_name`, `qr_token` directly on table, `metadata JSONB` | `fullname_snapshot`, `badge_name`, `qrtoken` (post-008), no `metadata` | Different column sets entirely |
| `check_ins` | `check_in_id`, `attendee_id` FK, `qr_token`, `checked_in_at`, `checked_in_by`, `method` | `checkin_id`, `scanned_by`, `scanned_at`, `result` (no `attendee_id`, no `qr_token` on this table) | Different PK name, different column set, Track A assumes an `attendees` table that Track B never creates |
| `attendees` | Exists as a first-class table | **Does not exist at all** | Not a naming conflict — a structural one. Track B has no attendee entity separate from `registrations`. |
| `check_in_attempts` | Exists | **Does not exist at all** | Same as above |

Both tracks number their first migration `001`, and neither uses `IF NOT EXISTS` consistently enough
to make applying both safe — `001_events.sql`'s bare `CREATE TABLE events (...)` would fail outright
if Track A's `events` (from `001_create_events_alpha_schema.sql`) already exists in the same
database.

## Conflicting columns

- `registrations.attendee_type` (Track B, added in `004_registrations_and_check_ins.sql`) is a
  **third, unrelated** definition of "attendee type" — distinct from Track A's `attendees.attendee_type`
  and distinct from the `person_type` enum proposed in
  [`person_identity_architecture_v1.md`](person_identity_architecture_v1.md). It survived migration
  `008`'s column rewrite (which dropped `confirmation_email_sent` but left `attendee_type` alone) and
  is not read or written by any current service/repository code —
  `grep -rn "attendee_type" backend/app/` outside migration files returns no hits. It appears to be
  dead schema.

---

## Live code target

Confirmed by import tracing:

| API module | Service | Repository | Schema columns used | Track |
|---|---|---|---|---|
| `api/events.py` | `events_service.py` | `events_repository.py` (plural) | `start_datetime`, `end_datetime`, `location_text` | **B** |
| `api/registrations.py` | `registration_service.py` | `registration_repository.py` | `fullname_snapshot`, `batch_year_snapshot`, `branch_snapshot`, `registration_number` | **B** |
| `api/admin_events.py` (check-in endpoints) | `checkin_service.py` | `event_repository.py` (singular) + `checkin_repository.py` + `registration_repository.py` | `starts_at` (via singular `event_repository.py`), `attendee_id`, `qr_token`, `checked_in_at` (via `checkin_repository.py`) | **A**, mixed with a Track-B `RegistrationRepository` it doesn't match |

`docs/architecture/alumni_db_integration_architecture_v1.md` (dated 2026-06-24, marked
"Authoritative") documents the Track B registration flow exclusively — further evidence Track B is
the intended live schema.

**This conclusion is inferred from code, not verified against a running database.** Confirm with:

```sql
\d events
\d registrations
\d check_ins
\d attendees   -- expect: does not exist, if Track B is truly what's live
```

against the actual dev/staging `events_db` before treating this as settled fact.

---

## Dead / orphaned code

- `backend/app/repositories/event_repository.py` (singular) and
  `backend/app/services/event_service.py` (singular) — Track A repository/service pair. Only
  consumer is `checkin_service.py`. Not used by `api/events.py` (which uses the plural
  `events_repository.py`/`events_service.py` pair).
- `backend/app/services/checkin_service.py` and `backend/app/repositories/checkin_repository.py` —
  live-mounted (via `admin_events.py` → `main.py`) but calling non-existent
  `RegistrationRepository` methods; see "Check-in mismatch" below.
- `registrations.attendee_type` column (Track B) — unused by any application code.
- `001_create_events_alpha_schema.sql` itself — superseded by the sequential track; kept only for
  historical reference unless actively still applied somewhere.

## Check-in mismatch (detail)

`checkin_service.py` calls three methods on its `RegistrationRepository` instance that do not exist
on the shipped class (`backend/app/repositories/registration_repository.py`):

- `get_by_token(qr_token)` — no method of this name exists; the closest live method is none (Track B
  `registrations` has a nullable `qrtoken` column but no repository method to look up by it).
- `get_attendee_by_registration(registration_id)` — assumes a separate `attendees` entity that does
  not exist in Track B's schema at all.
- `set_registration_status(registration_id, status)` — the live repository only has narrow,
  purpose-built updates (`set_registration_number`, `update_email_status`); no generic status setter.

**Runtime consequence:** `POST /api/v1/events/{event_id}/check-ins`,
`GET /api/v1/events/{event_id}/check-ins`, and
`GET /api/v1/events/{event_id}/check-in-attempts` (all mounted via `admin_events.py`) would raise
`AttributeError` the first time any of them is actually invoked, regardless of which migration track
is applied to the database — the code itself is internally inconsistent, independent of the schema
question.

---

## README correction needed

`backend/README.md` "Setup" and "DB Migration" sections currently instruct:

```bash
psql -d events_db -f migrations/events_db/001_create_events_alpha_schema.sql
# ... through the latest migration file
```

and separately state: *"Tables created: `events`, `sessions`, `registrations`, `attendees`,
`check_ins`, `check_in_attempts`"* — describing Track A's table set, not Track B's. A developer
following this literally would apply Track A first, then hit a `CREATE TABLE events` failure when
attempting `001_events.sql` from Track B (or vice versa, depending on directory sort order). The
README needs correction to reference only the Track B sequence (`001_events.sql` through
`013_week5_analytics.sql`) once Track A is confirmed dead.

---

## Recommended cleanup plan

1. **Verify** (not yet done) — run the `\d` checks above against the actual dev database to confirm
   Track B is what's live before touching anything.
2. **Archive, don't delete** — move `001_create_events_alpha_schema.sql` into a clearly-named
   location (e.g. `backend/migrations/events_db/archive/001_create_events_alpha_schema.sql` or a
   `0_DEPRECATED_` rename) so it's preserved for history but can't be mistaken for part of the active
   sequence. Do not delete it outright — it documents the `attendees`/`check_in_attempts` design
   intent that may still be useful input for the check-in repair (§12 of the person identity doc).
3. **Correct `backend/README.md`** — update "Setup" and "DB Migration" to reference only the Track B
   file sequence and its actual table set.
4. **Decide the fate of `event_repository.py` (singular) / `event_service.py` (singular)** — either
   repair `checkin_service.py` to use the plural Track B repositories, or explicitly mark the singular
   pair deprecated pending the check-in rewrite (§12 of the person identity doc). Do not leave both
   pairs present with no documentation of which is authoritative.
5. **Decide the fate of `registrations.attendee_type`** — either repurpose it as part of the future
   `registration_type` design (§5 of the person identity doc) or explicitly document it as dead and
   slated for removal in a future migration (not this week).
6. **Prevent recurrence** — once cleaned up, adopt a single incrementing migration number sequence
   with no duplicate `001` files, and consider adding a lightweight `schema_migrations` tracking table
   so "which migrations have run" is queryable rather than inferred.

None of steps 2–6 are executed by this report — it is analysis and recommendation only, per this
week's documentation-only scope.
