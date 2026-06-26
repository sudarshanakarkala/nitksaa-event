# Week 5 Phase 2 — Engineering Code Review

**Date:** 2026-06-26  
**Reviewer:** Engineering Review (Claude Code)  
**Branch:** main  
**Commit at time of review:** Changes not yet committed — all Phase 2 files are unstaged/untracked  
**Python version:** 3.10 (confirmed via `.venv/lib/python3.10/`)  
**Scope:** Migrations 011–013, People/Speakers, Sponsors/Partners, Analytics, Public API enrichment, Developer Diagnostics, API documentation  

---

## Evidence Base

Every finding in this report references a specific file and line number verified by direct file read. No assumptions are made about correctness without verification.

---

## 1. Week 5 Phase 2 Code Review

### 1.1 Migrations

#### Migration 011 — `backend/migrations/events_db/011_week5_people.sql`

Verified by direct read.

```sql
BEGIN;
CREATE TYPE person_role AS ENUM ('HOST','MODERATOR','SPEAKER','PANELIST',
  'CHIEF_GUEST','GUEST_OF_HONOUR','ORGANIZER');
CREATE TABLE event_people (
    person_id     SERIAL PRIMARY KEY,
    event_id      INTEGER NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    role          person_role NOT NULL,
    fullname      TEXT NOT NULL,
    title         TEXT, organisation TEXT, bio TEXT, photo_url TEXT, linkedin_url TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_visible    BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE session_people (
    session_id  INTEGER NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    person_id   INTEGER NOT NULL REFERENCES event_people(person_id) ON DELETE CASCADE,
    role        person_role NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (session_id, person_id, role)
);
COMMIT;
```

**Verified:** BEGIN/COMMIT wrapper present. Additive only — no existing tables modified. FK to `events(event_id)` with `ON DELETE CASCADE` present. Two composite indexes on `event_people` present. `session_people` indexes present.

**Finding 011-F1 — `updated_at` nullability:** Architecture doc (`event_people_speakers_architecture_v1.md:118`) specifies `updated_at TIMESTAMPTZ` (nullable, no default). Migration has `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`. The implementation is stricter. The `DEFAULT NOW()` prevents null values on creation, and the repository always sets it on update. This is a positive deviation — no data integrity risk.

**Finding 011-F2 — Primary key type:** `person_id SERIAL` (INT4, max ~2.1B). Analytics uses BIGSERIAL. People records are expected to be low-volume. SERIAL is sufficient. No issue.

**Finding 011-F3 — `session_people` PK deviation from architecture:** Architecture (`event_people_speakers_architecture_v1.md:137`) defines `PRIMARY KEY (session_id, person_id)` (2-column). Migration implements `PRIMARY KEY (session_id, person_id, role)` (3-column). This allows the same person to appear in the same session under two different roles. Whether this is intentional is unclear. No client code currently uses `session_people`, so no functional impact today.

**Finding 011-F4 — `person_role` ENUM vs `VARCHAR(30) CHECK`:** Architecture specifies `role VARCHAR(30) CHECK (role IN (...))`. Implementation uses a PostgreSQL ENUM type. Adding a new valid role requires `ALTER TYPE person_role ADD VALUE '...'` (DDL) rather than modifying a CHECK constraint. Both approaches require a migration. The ENUM provides stronger type safety at the DB level. This is a valid architectural choice that differs from the architecture doc.

#### Migration 012 — `backend/migrations/events_db/012_week5_sponsors_partners.sql`

Verified by direct read.

**Verified:** BEGIN/COMMIT present. Additive only. Both tables use `event_id FK → events ON DELETE CASCADE`. TEXT CHECK constraints match schema file values. Composite indexes present.

**Finding 012-F1 — Column name deviation:** Architecture (`event_sponsors_partners_architecture_v1.md:63`) specifies `sort_order INT`. Migration uses `display_order INTEGER`. Column name differs. The schema files, repositories, and API all consistently use `display_order`. The deviation is architectural naming only; the implementation is internally consistent.

**Finding 012-F2 — `updated_at` nullability:** Same deviation as 011-F1. Architecture specifies nullable; migration uses `NOT NULL DEFAULT NOW()`. Positive deviation.

**Finding 012-F3 — Ordering contract violation (sponsors):** Architecture (`event_sponsors_partners_architecture_v1.md:193`) states: "Sponsors ordered: by tier rank first, then by `sort_order`." The `SponsorsRepository.list_public_by_event` (sponsors_partners_repository.py:26) uses `ORDER BY display_order ASC, sponsor_id ASC`. There is no tier-rank ordering. A GOLD_SPONSOR with `display_order=0` will appear before a TITLE_SPONSOR with `display_order=1`, contrary to the architecture design.

**Finding 012-F4 — Ordering contract violation (partners):** Architecture states partners should be "ordered by `partner_type` alphabetically, then by `sort_order`." `PartnersRepository.list_public_by_event` (sponsors_partners_repository.py:97) uses `ORDER BY display_order ASC, partner_id ASC`. No type-based grouping.

#### Migration 013 — `backend/migrations/events_db/013_week5_analytics.sql`

Verified by direct read.

**Verified:** BEGIN/COMMIT present. `activity_id BIGSERIAL` (correct for high-volume). `event_id` uses `ON DELETE SET NULL` (correct — analytics history preserved when event is deleted). Three indexes present.

**Finding 013-F1 — Columns omitted from architecture:** Architecture (`event_analytics_architecture_v1.md:66`) defines: `alumni_ref_id VARCHAR(128)`, `session_id INT REFERENCES sessions ON DELETE SET NULL`, `ip_hash TEXT`, `user_agent TEXT`. None of these are present in the implementation. They are clearly deferred, but should be noted as gaps against the architecture.

**Finding 013-F2 — Action type casing mismatch:** Architecture uses lowercase (`event_viewed`, `registration_completed`). Implementation uses uppercase (`EVENT_VIEWED`, `REGISTRATION_COMPLETED`). This is a consistent deviation — all values are uppercase throughout schemas, repository, service, and diagnostics. No functional issue; the DB CHECK constraint enforces the uppercase values.

**Finding 013-F3 — `source_app` values mismatch:** Architecture defines `source_app IN ('flutter', 'admin', 'website')`. Implementation defines `source_app IN ('FLUTTER','ADMIN','BACKEND','EMAIL','SYSTEM')`. The implementation adds `BACKEND`, `EMAIL`, `SYSTEM` (all needed for the registration flow) and uses uppercase. The architecture did not anticipate backend-generated events being a source. The implementation is more complete than the architecture for this use case.

**Finding 013-F4 — `metadata` vs `metadata_json` column name:** Architecture calls it `metadata_json`. Implementation column is named `metadata`. The implementation uses the shorter name consistently across migration, service, and diagnostics. No functional issue.

---

### 1.2 Schemas

#### `backend/app/schemas/people.py` — verified at lines 1–86

**Verified:** `VALID_ROLES` set (7 values) matches migration ENUM values. `PersonCreate.validate_role` calls `.upper()` and checks membership. `PersonUpdate.validate_role` handles `None` guard. `PersonResponse` includes `is_visible`, `created_at`, `updated_at`. `PublicPersonResponse` excludes these fields.

**Finding SCH-F1 — Unused import:** `from pydantic import HttpUrl` (line 3) is imported but never used. `photo_url` and `linkedin_url` are typed `Optional[str]`, not `Optional[HttpUrl]`. This is dead code.

**Finding SCH-F2 — `PublicPersonResponse` defined but never used in routing:** `PublicPersonResponse` (line 73) is defined but the actual public API response goes through `dict(r)` from repository records in `events_service.py:199`. FastAPI does not validate the public event detail response against this schema. The schema serves no runtime purpose as currently wired.

**Finding SCH-F3 — Column name deviations from architecture:** Architecture (`event_people_speakers_architecture_v1.md:98–117`) specifies:
- `full_name` → implementation: `fullname`
- `designation` → implementation: `title`
- `organization` → implementation: `organisation` (British spelling)
- `sort_order` → implementation: `display_order`

All four names differ from the architecture. The implementation is internally consistent across migration, schema, repository, and API. The deviation is from the architecture document only.

#### `backend/app/schemas/sponsors_partners.py` — verified

**Verified:** `VALID_SPONSOR_TYPES` (5 values) and `VALID_PARTNER_TYPES` (7 values) match migration CHECK constraints. Validators with `.upper()` present for both. Separate Create/Update/Response/PublicResponse schemas for Sponsor and Partner.

**Finding SCH-F4 — `PublicSponsorResponse` and `PublicPartnerResponse` defined but unused:** Same issue as SCH-F2. These schemas exist but the public event detail routes return `dict(r)` directly.

#### `backend/app/schemas/analytics.py` — verified

**Verified:** `VALID_ACTION_TYPES` and `VALID_SOURCE_APPS` constants present. `ActivityLogResponse` defined but has no associated read endpoint (intentional — analytics are write-only in Phase 2).

---

### 1.3 Repositories

#### `backend/app/repositories/people_repository.py` — verified at lines 1–79

**Verified:** `list_by_event` uses `SELECT *` (admin, returns all including hidden), ordered by `display_order ASC, person_id ASC`. `list_public_by_event` uses explicit column list (excludes `is_visible`, `created_at`, `updated_at`), `WHERE is_visible = true`. `create` uses positional parameters — no SQL injection risk. `get` fetches by `person_id` only. `delete` returns bool based on result string comparison.

**Finding REPO-F1 — Dynamic UPDATE with f-string column interpolation** (`people_repository.py:59–70`):

```python
set_parts.append(f"{key} = ${i}")
```

Column names come from `data.model_dump(exclude_unset=True)` where `data` is a `PersonUpdate` Pydantic model. The keys are Python attribute names from a controlled schema definition — they cannot contain user input. However, this pattern is fragile: adding any new field to `PersonUpdate` automatically allows it to be updated without explicit opt-in. Values are still parameterized (`$i`), so SQL injection via values is not possible. SQL injection via column names is not possible since the source is Pydantic model field names. Low risk, but non-idiomatic.

**Finding REPO-F2 — `list_by_event` uses `SELECT *`:** For admin routes, this is acceptable since all columns are relevant. Not a security issue since admin responses correctly include `is_visible`. Would be affected by future schema changes silently.

**Finding REPO-F3 — `update` returns `Optional[asyncpg.Record]` but effectively always returns a record:** After the UPDATE executes, `self.get(person_id)` is called. If the row was deleted between UPDATE and GET (race condition), this returns None. The router does not handle `None` from update — would cause a Pydantic validation error. Extremely unlikely in practice, but technically possible.

#### `backend/app/repositories/sponsors_partners_repository.py` — verified at lines 1–152

**Verified:** `SponsorsRepository` and `PartnersRepository` follow the identical pattern as `PeopleRepository`. Dynamic UPDATE present with same f-string column interpolation pattern. `list_public_by_event` for both correctly excludes `is_visible`.

---

### 1.4 Analytics Service

#### `backend/app/services/analytics_service.py` — verified

**Verified:** `log_event_activity` is `async`, catches all exceptions via bare `except Exception as exc`, logs `WARNING`, never re-raises. Uses `get_pool()` → `pool.acquire()` for its own connection (independent of any calling transaction).

**Finding ANLYT-F1 — `json.dumps()` for JSONB:** `asyncpg` natively accepts Python `dict` for JSONB columns. The implementation calls `json.dumps(metadata or {})` and passes the resulting string. `asyncpg` then receives a JSON string for a `JSONB` parameter. This works because asyncpg handles JSON string→JSONB coercion, but it is non-idiomatic. The idiomatic form is to pass the dict directly.

**Finding ANLYT-F2 — REGISTRATION_FAILED logs inside transaction:** In `registration_service.py:120–127`, `log_event_activity("REGISTRATION_FAILED")` is called inside `async with conn.transaction()`. Since `log_event_activity` acquires its own pool connection, the write is independent and commits immediately on its own connection. The outer transaction rolling back does not affect the analytics row. This is correct behavior for fire-and-forget analytics.

---

### 1.5 API Routers

#### `backend/app/api/people.py` — verified at lines 1–80

**Verified:** All 4 routes use `Depends(get_admin_user)`. `_require_event` validates event existence. `_require_person` validates person exists AND belongs to the given `event_id` (cross-event access prevented). `DELETE` returns `204`. `POST` returns `201`.

**Finding API-F1 — URL prefix deviation from architecture:** Architecture specifies `/api/v1/admin/events/{id}/people`. Implementation uses `router = APIRouter(prefix="/api/v1/events")` (line 11) → routes are at `/api/v1/events/{id}/people`. This deviates from the established `admin_events.py` pattern (`/api/v1/admin/events/{id}`) and from the architecture spec. The routes are still admin-only (auth guard present), but the URL does not signal "admin" — a public API consumer could mistake these as public endpoints. This is the most significant structural deviation from the established convention.

**Finding API-F2 — `PUT` instead of architecture's `PATCH`:** Architecture specifies PATCH. Implementation uses PUT. PUT semantics imply full replacement, but the implementation performs partial updates (using `exclude_unset=True`). The route uses PUT semantics for a PATCH operation. In practice this works fine since the body is fully optional, but it is semantically incorrect.

**Finding API-F3 — No `GET /api/v1/events/{event_id}/people/{person_id}` endpoint:** There is no single-person read endpoint. Admin list returns all. Not in the architecture spec either, so this is not a deviation, but it is a functional gap if an admin UI needs to fetch a single person.

#### `backend/app/api/sponsors_partners.py` — verified at lines 1–139

**Verified:** Same pattern as `people.py`. All 8 routes admin-only. Sponsors and partners in the same file with shared `_require_event` helper.

**Finding API-F4 — Inconsistent event validation helpers between people and sponsors/partners:** `people.py` uses dedicated `_require_person` helper for update/delete (which validates event ownership). `sponsors_partners.py` uses inline `repo.get(id)` + `existing["event_id"] != event_id` check for update/delete (lines 60–63, 75–78, 119–122, 134–137). Both approaches are functionally equivalent and correct, but the pattern is inconsistent within the same codebase.

---

### 1.6 Events Service — Public Event Enrichment

#### `backend/app/services/events_service.py:189–208` — verified

```python
async def get_public_event(self, event_id: int) -> Dict[str, Any]:
    record = await self.repo.get_public_event(event_id)
    if not record:
        raise HTTPException(status_code=404, detail="event_not_found")
    d = self._to_dict(record)
    _with_public_card_metadata(d)
    d["sessions"] = []

    people_rows = await PeopleRepository(self.conn).list_public_by_event(event_id)
    people = [dict(r) for r in people_rows]
    d["people"] = people
    d["speakers"] = [p for p in people if p["role"] == "SPEAKER"]

    sponsor_rows = await SponsorsRepository(self.conn).list_public_by_event(event_id)
    d["sponsors"] = [dict(r) for r in sponsor_rows]

    partner_rows = await PartnersRepository(self.conn).list_public_by_event(event_id)
    d["partners"] = [dict(r) for r in partner_rows]

    return d
```

**Verified:** People, sponsors, and partners fetched using the same connection (`self.conn`). `is_visible` filtering delegated to repository `list_public_by_event` methods. `people`, `speakers`, `sponsors`, `partners` keys added to response dict. Empty `sessions` returned as `[]`.

**Finding ENRICH-F1 — `speakers[]` derivation deviates from architecture:** Architecture (`event_people_speakers_architecture_v1.md:230–233`) specifies:

```python
speakers = [p for p in people if p["role"] in (
    "SPEAKER", "PANELIST", "CHIEF_GUEST", "GUEST_OF_HONOUR"
)]
```

Implementation (`events_service.py:200`):

```python
d["speakers"] = [p for p in people if p["role"] == "SPEAKER"]
```

Only SPEAKER-role persons appear in `speakers[]`. A CHIEF_GUEST or PANELIST added to an event will appear in `people[]` but NOT in `speakers[]`. If the Flutter app uses `speakers[]` to display all presentation-role people (as the architecture intends), CHIEF_GUEST and PANELIST speakers will not be displayed.

**Finding ENRICH-F2 — N+3 queries per public event detail call:** Each call to `get_public_event` now runs 4 queries: `get_public_event` (base event), `list_public_by_event` (people), `list_public_by_event` (sponsors), `list_public_by_event` (partners). All run on the same connection inside a single request. This is acceptable at Alpha scale. No connection pool exhaustion risk. No issue for production at current volume, but worth noting for future caching consideration.

**Finding ENRICH-F3 — `_enrich` vs `_with_public_card_metadata` duplication (pre-existing):** These two functions are identical (`events_service.py:46–55`). This is a pre-existing issue not introduced by Week 5, but Phase 2 code calls `_with_public_card_metadata` while Phase 1 admin code calls `_enrich`. No functional impact.

---

### 1.7 `main.py` Registration — Verified

```python
from app.api import (
    health, events, admin_events, auth, dev_diagnostics, alumni, registrations,
    people, sponsors_partners, week5_diagnostics,
)
# ...
app.include_router(week5_diagnostics.router)
app.include_router(people.router)
app.include_router(sponsors_partners.router)
```

Verified: All three new routers registered. Import order is clean. No duplicate registrations. Backend import check runs without error (verified: `python -c "from app.api import ..."` → `All imports: OK`).

---

### 1.8 Registration Service Analytics Integration — Verified

Verified at `registration_service.py:23, 120–127, 129–139, 158–163, 174–181`.

Four analytics events hooked:
- `REGISTRATION_FAILED` — `already_registered` (inside transaction, own connection)
- `REGISTRATION_FAILED` — `event_full` (inside transaction, own connection)
- `REGISTRATION_COMPLETED` — after transaction commits (outside transaction)
- `EMAIL_SENT` / `EMAIL_FAILED` — after email send attempt (outside transaction)

All calls are `await log_event_activity(...)` — the function internally catches exceptions. No audit log interference — analytics and audit log use separate tables and separate write paths.

---

## 2. Architecture Compliance Report

### 2.1 People/Speakers (`event_people_speakers_architecture_v1.md`)

| Architecture Requirement | Implementation | Status |
|---|---|---|
| `full_name` column | `fullname` | DEVIATION |
| `designation` column | `title` | DEVIATION |
| `organization` column | `organisation` | DEVIATION |
| `sort_order` column | `display_order` | DEVIATION |
| `role VARCHAR(30) CHECK` | `role person_role ENUM` | DEVIATION (same values, different type) |
| `session_people PK (session_id, person_id)` | PK (session_id, person_id, role) | DEVIATION |
| `speakers` subset includes PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR | Subset is `role == "SPEAKER"` only | **FUNCTIONAL DEVIATION** |
| Admin endpoints at `/api/v1/admin/events/{id}/people` | At `/api/v1/events/{id}/people` | DEVIATION |
| Update via PATCH | Update via PUT | DEVIATION |
| `updated_at` nullable | `NOT NULL DEFAULT NOW()` | Positive deviation |

### 2.2 Sponsors/Partners (`event_sponsors_partners_architecture_v1.md`)

| Architecture Requirement | Implementation | Status |
|---|---|---|
| `sort_order` column | `display_order` | DEVIATION |
| `updated_at` nullable | `NOT NULL DEFAULT NOW()` | Positive deviation |
| Sponsors ordered by tier rank first | Ordered by `display_order` only | **FUNCTIONAL DEVIATION** |
| Partners ordered by type alphabetically | Ordered by `display_order` only | DEVIATION |
| Admin endpoints at `/api/v1/admin/events/{id}/sponsors` | At `/api/v1/events/{id}/sponsors` | DEVIATION |
| Update via PATCH | Update via PUT | DEVIATION |

### 2.3 Analytics (`event_analytics_architecture_v1.md`)

| Architecture Requirement | Implementation | Status |
|---|---|---|
| `alumni_ref_id` column | Not present | OMITTED (deferred) |
| `session_id` FK column | Not present | OMITTED (deferred) |
| `ip_hash` column | Not present | OMITTED (deferred) |
| `user_agent` column | Not present | OMITTED (deferred) |
| `metadata_json` column name | `metadata` | DEVIATION (harmless) |
| Lowercase action types | UPPERCASE | CONSISTENT DEVIATION |
| `source_app IN ('flutter','admin','website')` | IN ('FLUTTER','ADMIN','BACKEND','EMAIL','SYSTEM') | EXTENDED (BACKEND, EMAIL, SYSTEM added) |
| `ON DELETE SET NULL` for event_id | Implemented | COMPLIANT |
| BIGSERIAL PK | Implemented | COMPLIANT |
| Fire-and-forget pattern | Implemented | COMPLIANT |
| No PII in metadata | Verified via diagnostics | COMPLIANT |
| Separate from audit log | Confirmed — separate table and write path | COMPLIANT |

---

## 3. API Compatibility Report

### 3.1 Backward Compatibility of Public Event Detail

`GET /api/v1/events/public/{event_id}` response shape — Phase 2 adds:
- `people: []` — new key, empty array default for events with no people
- `speakers: []` — new key, empty array default
- `sponsors: []` — new key, empty array default
- `partners: []` — new key, empty array default

**Verified by diagnostics** (`week5/event-options`, test `eo_06`): Existing events that have no people/sponsors/partners return empty arrays. Flutter `fromJson` with `??` fallbacks is unaffected.

**Finding COMPAT-F1 — `sessions` field:** `events_service.py:195` hardcodes `d["sessions"] = []`. Sessions are not fetched. This is pre-existing behavior (sessions were never wired), but Week 5 did not change this. No regression.

### 3.2 Admin API — New Endpoints

All new admin endpoints are behind `Depends(get_admin_user)`. No existing admin endpoints modified.

| Endpoint | Method | Auth | Status code | Verified |
|---|---|---|---|---|
| `/api/v1/events/{id}/people` | GET | Admin | 200 | Source reviewed |
| `/api/v1/events/{id}/people` | POST | Admin | 201 | Source reviewed |
| `/api/v1/events/{id}/people/{pid}` | PUT | Admin | 200 | Source reviewed |
| `/api/v1/events/{id}/people/{pid}` | DELETE | Admin | 204 | Source reviewed |
| `/api/v1/events/{id}/sponsors` | GET | Admin | 200 | Source reviewed |
| `/api/v1/events/{id}/sponsors` | POST | Admin | 201 | Source reviewed |
| `/api/v1/events/{id}/sponsors/{sid}` | PUT | Admin | 200 | Source reviewed |
| `/api/v1/events/{id}/sponsors/{sid}` | DELETE | Admin | 204 | Source reviewed |
| `/api/v1/events/{id}/partners` | GET | Admin | 200 | Source reviewed |
| `/api/v1/events/{id}/partners` | POST | Admin | 201 | Source reviewed |
| `/api/v1/events/{id}/partners/{pid}` | PUT | Admin | 200 | Source reviewed |
| `/api/v1/events/{id}/partners/{pid}` | DELETE | Admin | 204 | Source reviewed |

### 3.3 API Contract vs Implementation

`docs/api/week5_event_enrichment_api_contract.md` documents the **actual implemented** paths (not the architecture paths). The contract is internally consistent with the code. No consumer of the contract would find a discrepancy between the doc and the running API.

---

## 4. Migration Review

| Migration | File | Wrapper | Additive | FKs | Indexes | Applied locally | Cloud SQL |
|---|---|---|---|---|---|---|---|
| 011 | `011_week5_people.sql` | BEGIN/COMMIT | Yes | ON DELETE CASCADE | 3 indexes | Yes | NOT YET |
| 012 | `012_week5_sponsors_partners.sql` | BEGIN/COMMIT | Yes | ON DELETE CASCADE | 4 indexes | Yes | NOT YET |
| 013 | `013_week5_analytics.sql` | BEGIN/COMMIT | Yes | ON DELETE SET NULL | 3 indexes | Yes | NOT YET |

**Critical:** All three migrations are applied to local `events_db` only. They have NOT been applied to Cloud SQL. This is the primary production blocker. Evidence: git status shows all three migration files as untracked (not committed) and no record of cloud migration in `week5_cloud_db_validation_report.md`.

**Migration ordering:** 011 must run before 012 and 013 (no cross-dependencies, but sequential numbering maintains history integrity). `session_people` in 011 references `sessions(session_id)` from migration 002 — dependency satisfied.

**No rollback scripts:** None of the migrations include a DOWN section. In a production scenario, reversing migration 011 would require `DROP TYPE person_role CASCADE` which could affect `session_people`. This is acceptable for an Alpha project but should be noted.

---

## 5. Documentation Review

| Document | Status | Finding |
|---|---|---|
| `docs/api/week5_event_enrichment_api_contract.md` | Accurate | Reflects implementation, not architecture paths |
| `docs/api/backend_api_index_v3.md` | Modified | 17 new endpoints added; not reviewed in full but consistent with implementation |
| `docs/reviews/week5_phase2_backend_foundations_verification.md` | Accurate | Matches diagnostics output |
| `docs/reviews/week5_developer_workflows_verification.md` | Accurate | Matches diagnostics endpoint behavior |
| `docs/reviews/week5_phase1_event_options_verification.md` | Accurate | Phase 1 smoke test recorded |
| `docs/reviews/week5_manual_verification_steps.md` | Modified | Section K added; not read in full |

**Finding DOC-F1 — Architecture vs. API contract discrepancy not documented:** The deviations between `event_people_speakers_architecture_v1.md` (specifying `/api/v1/admin/events`, PATCH, `full_name`, `sort_order`) and the actual implementation are not called out anywhere in the documentation. A future developer reading the architecture doc would implement different column names and URL paths than what exists.

**Finding DOC-F2 — `speakers[]` derivation discrepancy not documented:** The architecture specifies `speakers = [p for p in people if p["role"] in ("SPEAKER", "PANELIST", "CHIEF_GUEST", "GUEST_OF_HONOUR")]`. The implementation uses `role == "SPEAKER"` only. Neither the API contract nor the verification report notes this difference.

**Finding DOC-F3 — `week5_cloud_db_migration_and_validation_plan.md` exists but migrations not applied:** The plan document exists but Cloud SQL migration has not been executed. This is recorded in `week5_phase2_backend_foundations_verification.md` section "Known Gaps."

---

## 6. Developer Diagnostics Review

### 6.1 `backend/app/api/week5_diagnostics.py` — Verified

**Guard:** `_require_development()` (line 26–28) raises `404 not_found` when `app_env != "development"`. Called from `_get_admin` (line 35) which is a dependency for all 5 endpoints. Guard is effective.

**Dev auth:** `_get_admin` (line 31–41) accepts `X-Dev-User: admin` header or a Bearer JWT decoded via `decode_access_token`. When `app_env != "development"`, the function raises before either check. Auth bypass only works in development.

**Finding DIAG-F1 — `_get_admin` duplicates `_get_dev_user` from `dev_diagnostics.py`:** The same pattern is implemented twice. Not a security issue, but a maintenance risk — if the dev auth pattern changes, it must be updated in two places.

**Finding DIAG-F2 — Duplicate import inside `_create_diag_event`:** `from app.schemas.event_status import EventStatusUpdate` is imported at line 89 and again at line 112 of `week5_diagnostics.py`. The second import is redundant. Python handles re-imports gracefully (cached), so no error results.

**Finding DIAG-F3 — `datetime.utcnow()` deprecated in Python 3.12+:** `_run_event_options:133`, `_summary:68`, and multiple other locations use `datetime.utcnow()`. The backend runs Python 3.10, so this is not yet a problem. The isoformat+Z pattern (`started.isoformat() + "Z"`) manually appends the Z suffix to a naive datetime, which is fragile.

**Finding DIAG-F4 — `_cancel_events` swallows all exceptions silently:** `_cancel_events` (line 117–125) catches `Exception` and passes silently. If event cancellation fails (e.g., already cancelled), there is no warning log. Diagnostic cleanup failures are invisible in the response.

**Finding DIAG-F5 — `an_09` metadata type check accepts strings:** `week5_diagnostics.py:655`:
```python
meta_ok = all(isinstance(r["metadata"], (dict, str)) for r in rows)
```
asyncpg returns JSONB columns as Python `dict`. If the value were a string, it would indicate a serialization issue. The test accepting both `dict` and `str` makes it a weaker assertion than intended. Should be `isinstance(r["metadata"], dict)`.

**Finding DIAG-F6 — Analytics diagnostic creates test rows that persist:** The analytics suite (`_run_analytics`) explicitly documents that log rows are kept (append-only). However, the diagnostic event_id can be used to identify and clean up rows manually if needed. This is an intentional design choice, correctly documented in `week5_developer_workflows_verification.md:139`.

**Data cleanup verification:** `_run_people` cancels its diagnostic event at `week5_diagnostics.py:371`. `_run_sponsors_partners` cancels at line 573. `_run_event_options` cancels at line 222. Cleanup is present for all non-analytics suites.

**Rerunability:** Verified via diagnostics run (43/43 PASS). Timestamps in title prevent naming collisions across runs.

---

## 7. Repository Change Summary

### New Files (Untracked — Not Committed)

| File | Purpose |
|---|---|
| `backend/app/api/people.py` | Admin CRUD for event_people |
| `backend/app/api/sponsors_partners.py` | Admin CRUD for event_sponsors and event_partners |
| `backend/app/api/week5_diagnostics.py` | Dev-only diagnostic suite (5 endpoints) |
| `backend/app/repositories/people_repository.py` | PeopleRepository |
| `backend/app/repositories/sponsors_partners_repository.py` | SponsorsRepository, PartnersRepository |
| `backend/app/schemas/analytics.py` | ActivityLogResponse schema |
| `backend/app/schemas/people.py` | PersonCreate/Update/Response/PublicPersonResponse |
| `backend/app/schemas/sponsors_partners.py` | Sponsor and Partner schemas |
| `backend/app/services/analytics_service.py` | log_event_activity (fire-and-forget) |
| `backend/migrations/events_db/010_week5_phase1_event_options.sql` | Phase 1 migration (full-day, free/paid) |
| `backend/migrations/events_db/011_week5_people.sql` | event_people, session_people tables |
| `backend/migrations/events_db/012_week5_sponsors_partners.sql` | event_sponsors, event_partners tables |
| `backend/migrations/events_db/013_week5_analytics.sql` | event_activity_log table |
| `docs/api/week5_event_enrichment_api_contract.md` | API contract for Phase 2 |
| `docs/reviews/week5_developer_workflows_verification.md` | Diagnostics reference doc |
| `docs/reviews/week5_feature_implementation_plan.md` | Feature plan |
| `docs/reviews/week5_phase1_event_options_verification.md` | Phase 1 verification |
| `docs/reviews/week5_phase2_backend_foundations_verification.md` | Phase 2 verification |

### Modified Files (Unstaged)

| File | Change |
|---|---|
| `admin/event_admin/src/pages/EventFormPage.jsx` | Full-day toggle, pricing section, eyebrow text update |
| `admin/event_admin/src/styles/event-form.css` | New prefix-wrap styles |
| `apps/event_app/lib/features/events/domain/public_event.dart` | New fields: is_full_day, is_free, ticket_price |
| `apps/event_app/lib/features/events/domain/public_event_detail.dart` | New fields: people, speakers, sponsors, partners |
| `apps/event_app/lib/features/events/presentation/event_detail_screen.dart` | UI wiring for new fields |
| `backend/app/main.py` | Added people, sponsors_partners, week5_diagnostics router imports |
| `backend/app/repositories/events_repository.py` | Queries updated for Phase 1 columns |
| `backend/app/schemas/event_create.py` | Added is_full_day, is_free, ticket_price |
| `backend/app/schemas/event_response.py` | Added is_full_day, is_free, ticket_price |
| `backend/app/schemas/event_update.py` | Added is_full_day, is_free, ticket_price |
| `backend/app/services/events_service.py` | Added people/sponsors/partners enrichment in get_public_event |
| `backend/app/services/registration_service.py` | Added analytics hooks |
| `docs/api/backend_api_index_v3.md` | 17 new endpoint entries |
| `docs/reviews/week5_manual_verification_steps.md` | Section K added |

**Critical observation:** None of the Week 5 changes are committed. The entire Phase 2 implementation exists only in the working tree. Loss of local state (disk failure, accidental `git checkout .`) would lose all work.

---

## 8. Production Readiness Assessment

| Area | Status | Detail |
|---|---|---|
| Local backend import | PASS | `All imports: OK` verified |
| Migrations applied locally | PASS | 011, 012, 013 applied to local events_db |
| Migrations applied to Cloud SQL | **FAIL** | Not applied — production blocker |
| Diagnostic suite | PASS | 43/43 — verified in prior session |
| Admin auth on new endpoints | PASS | `Depends(get_admin_user)` on all 12 routes |
| Public event backward compat | PASS | Empty arrays default, Flutter fromJson unaffected |
| Analytics fire-and-forget | PASS | Exceptions caught, never propagate to caller |
| Secrets in analytics metadata | PASS | `an_11` verified no secret keys in metadata |
| Dev-only guard on diagnostics | PASS | 404 when APP_ENV != development |
| Unit/integration tests for Week 5 | **FAIL** | No tests exist for event_people, event_sponsors, event_partners, event_activity_log |
| Code committed to git | **FAIL** | All Phase 2 files are unstaged/untracked |
| Cloud SQL migration plan | EXISTS | `week5_cloud_db_migration_and_validation_plan.md` — not executed |
| Admin portal UI for people management | NOT IMPLEMENTED | Deferred to future phase |
| Flutter UI for enrichment display | PARTIAL | `fromJson` fields added; display UI not verified here |

---

## 9. Risk Register

| ID | Risk | Severity | Likelihood | Evidence |
|---|---|---|---|---|
| R-01 | **Cloud SQL migrations 011–013 not applied** — production deploy will fail if backend restarts against Cloud SQL without these tables | CRITICAL | Certain | git status shows all migration files untracked; no cloud execution logged |
| R-02 | **Code not committed** — entire Phase 2 lost on disk failure | CRITICAL | Low-probability, high-impact | git status shows 18 untracked/unstaged files |
| R-03 | **`speakers[]` derivation bug** — PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR do not appear in speakers[] per the architecture contract | HIGH | Certain (it's in the code now) | `events_service.py:200` vs `event_people_speakers_architecture_v1.md:230` |
| R-04 | **Admin URL prefix breaks `/api/v1/admin/` convention** — future admin clients (portal, tooling) that discover admin endpoints by prefix will not find people/sponsors/partners | MEDIUM | Medium | `people.py:11` prefix is `/api/v1/events`, not `/api/v1/admin/events` |
| R-05 | **No tier-based ordering for public sponsors** — a GOLD_SPONSOR can appear before TITLE_SPONSOR if display_order values are equal | MEDIUM | Medium | `sponsors_partners_repository.py:26` |
| R-06 | **No unit tests for Week 5 code** — regression not caught by automated test run | MEDIUM | High | `backend/tests/` contains only `test_email.py` and `test_event_flow.py` |
| R-07 | **Dynamic UPDATE f-string column interpolation** — fragile pattern; adding a field to `PersonUpdate` automatically makes it updatable | LOW | Low | `people_repository.py:59`, `sponsors_partners_repository.py:62,128` |
| R-08 | **`json.dumps()` for JSONB** — non-idiomatic; works but may cause unexpected behavior with special characters or nested structures | LOW | Low | `analytics_service.py` |
| R-09 | **`PublicPersonResponse`, `PublicSponsorResponse`, `PublicPartnerResponse` unused** — dead code schemas; response shape not validated by FastAPI for public endpoint | LOW | Certain | `people.py:73`, not used in `events_service.py:199` |
| R-10 | **`HttpUrl` unused import in `people.py` schema** — static analysis tool or linter will flag | TRIVIAL | Certain | `schemas/people.py:3` |
| R-11 | **`_get_admin` duplicated in `week5_diagnostics.py`** — maintenance burden if auth pattern changes | LOW | Low | `week5_diagnostics.py:31` vs `dev_diagnostics.py` |
| R-12 | **`datetime.utcnow()` deprecated** — will raise `DeprecationWarning` in Python 3.12+ | LOW | Future | `week5_diagnostics.py` multiple locations |

---

## 10. Final Verdict

### Summary by Layer

| Layer | Verdict | Key Finding |
|---|---|---|
| Migrations 011–013 (structure) | PASS | Additive, wrapped, FK-correct |
| Migrations (applied to production) | FAIL | Cloud SQL not updated |
| Schema layer | PASS WITH MINOR ISSUES | Unused import, unused Public schemas |
| Repository layer | PASS WITH MINOR ISSUES | Dynamic UPDATE pattern, SELECT * for admin list |
| Analytics service | PASS WITH MINOR ISSUES | `json.dumps()` non-idiomatic |
| Analytics hooks in registration | PASS | Fire-and-forget, independent connections |
| Admin API routers | PASS WITH MINOR ISSUES | URL prefix breaks convention, PUT vs PATCH |
| Public event enrichment | PASS WITH ISSUES | speakers[] derivation deviates from architecture |
| Developer diagnostics | PASS WITH MINOR ISSUES | Duplicate auth helper, `an_09` weak assertion, utcnow deprecated |
| Documentation | PASS WITH ISSUES | Architecture deviations not documented |
| Architecture compliance | CONDITIONAL | Multiple structural deviations from architecture docs |
| Tests | FAIL | No automated tests for any Week 5 code |
| Code committed | FAIL | All Phase 2 in working tree only |

### Overall Verdict

## CONDITIONAL PASS

**Conditions that must be met before production deploy:**

1. **Apply migrations 011, 012, 013 to Cloud SQL** (R-01 — blocks production).
2. **Commit all Phase 2 files to git** (R-02 — data integrity).

**Issues that should be addressed before Alpha demo:**

3. **Fix `speakers[]` derivation** — include PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR as specified in the architecture, or update the architecture document to reflect the deliberate decision to restrict `speakers[]` to SPEAKER role only (R-03).

**Issues to address in a follow-up sprint:**

4. **Standardize admin URL prefix** — move people/sponsors/partners endpoints to `/api/v1/admin/events/{id}/...` to match the established convention, OR update the architecture docs to record the intentional deviation (R-04).
5. **Implement tier-based ordering for sponsors** (R-05).
6. **Add automated tests** for people, sponsors, partners CRUD and analytics logging (R-06).
7. **Remove unused `HttpUrl` import** and unused `PublicPersonResponse/PublicSponsorResponse/PublicPartnerResponse` schemas or wire them into the public response (R-09, R-10).
8. **Replace `json.dumps()` with dict pass-through** in analytics_service (R-08).
9. **Document architecture deviations** — update architecture docs to reflect actual column names, URL paths, and `speakers[]` derivation rule (DOC-F1, DOC-F2).

---

## 11. Corrective Sprint Resolution (2026-06-26)

Applied immediately after the initial review. All changes made before the first commit.

### Fixed

| Finding | Resolution | File |
| --- | --- | --- |
| R-03: `speakers[]` derivation incorrect | Fixed: `speakers[]` now includes SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR | `events_service.py:200` |
| R-05: Sponsor ordering — no tier rank | Fixed: ORDER BY CASE sponsor_type (TITLE=1…ASSOCIATE=5), display_order, sponsor_id | `sponsors_partners_repository.py:26` |
| R-05: Partner ordering — no type grouping | Fixed: ORDER BY partner_type ASC, display_order ASC, partner_id ASC | `sponsors_partners_repository.py:97` |
| R-08: `json.dumps()` for JSONB | Fixed: codec registered per-connection via `conn.set_type_codec()` — dict passed directly | `analytics_service.py` |
| R-09: Unused Public schemas | Fixed: `PublicPersonResponse`, `PublicSponsorResponse`, `PublicPartnerResponse` removed | `schemas/people.py`, `schemas/sponsors_partners.py` |
| R-10: Unused `HttpUrl` import | Fixed: import removed | `schemas/people.py:3` |
| DOC-F2: `speakers[]` rule not documented | Fixed: API contract updated with exact derivation rule | `docs/api/week5_event_enrichment_api_contract.md` |
| Missing diagnostics for new rules | Fixed: People suite expanded (11→14 tests); SP suite expanded (15→17 tests) | `api/week5_diagnostics.py` |

### Diagnostics After Corrective Sprint

```text
OVERALL: status=ok  passed=48/48  failed=0  warnings=0

  week5_event_options:     ok   6/6
  week5_people:            ok  14/14
  week5_sponsors_partners: ok  17/17
  week5_analytics:         ok  11/11
```

### Intentionally Deferred (Not in This Sprint)

| Finding | Reason |
| --- | --- |
| R-04: Admin URL prefix (`/api/v1/events/` vs `/api/v1/admin/events/`) | Path change would break existing diagnostics and API docs. Deferred to a dedicated routing alignment sprint. |
| R-06: No automated unit/integration tests for Week 5 code | Requires test framework setup and DB fixtures. Deferred. |
| R-11: `_get_admin` duplicated in `week5_diagnostics.py` | Refactor risk low; deferred with architecture deviations doc. |
| R-12: `datetime.utcnow()` deprecated | Python 3.10 in use; safe until 3.12 upgrade. Deferred. |
| Cloud SQL migrations 010–013 | Requires explicit approval and cloud access. Checklist created at `docs/reviews/week5_cloud_migration_execution_checklist.md`. |

### Not Changed (Intentional)

| Item | Reason |
| --- | --- |
| Column names (`fullname`, `title`, `organisation`, `display_order`) | Architecture doc names differ (`full_name`, `designation`, etc.) but all code is internally consistent. Renaming columns requires a migration and is a breaking change. Deferred architecture alignment. |
| `session_people` PK (3-column vs 2-column in architecture) | No client code currently uses `session_people`. Low risk. Left as-is pending session UI implementation. |
| `SELECT *` in `list_by_event` admin queries | Correct for admin use (all fields needed). Acceptable. |

---

*Review performed against actual source code. All findings reference specific file paths and line numbers.*
