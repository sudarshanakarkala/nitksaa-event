# Cross-Repo Alumni DB Investigation Report

**Date:** 2026-06-19
**Scope:** Event App vs NITKSAA Website / Portal-v2 alumni lookup discrepancy
**Status:** ROOT CAUSE CONFIRMED — no production data modified

---

## Summary

The Event App local development environment is connected to a **local dummy `alumni_db`** containing only 4 test seed records. The NITKSAA Website and Portal-v2 connect to the real Cloud SQL `alumni_db` (via Cloud SQL Proxy in dev, via socket in production), which contains the full alumni dataset.

- `sudarshana.ashwini@gmail.com` exists in the **real Cloud SQL alumni_db** (visible in Portal UI) but is **absent from the Event App local dummy alumni_db** → Event App auth returns `user_type=other`.
- `Username2026@gmail.com` (`username2026@gmail.com`) exists only in the **Event App local dummy alumni_db** as a test seed record → Event App diagnostics resolves it as `user_type=alumni`.

A secondary bug exists independently: the `ON CONFLICT` clause in `_upsert_event_user` does not update `user_type`, `ref_id`, or `graduation_year` for existing rows. Even after the DB is fixed, users who previously logged in as `other` will remain frozen until their `event_users` row is deleted and they re-login.

---

## Repositories Reviewed

| Repository | Files Reviewed |
|---|---|
| `nitksaa-event/backend` | `app/config.py`, `app/database.py`, `app/api/auth.py`, `app/api/dev_diagnostics.py`, `app/services/alumni_service.py`, `backend/.env` |
| `nitksaa-website/backend` | `src/config/settings.py`, `src/services/db.py`, `src/services/alumni.py`, `src/api/auth.py`, `src/config/tenants.yaml` |
| `nitksaa-portal-v2/webapp/backend` | `config.py`, `database.py`, `routers/auth_v1.py`, `routers/alumni.py`, `routers/me.py` |

---

## Database Connections Compared

| App | DB Host | DB Port | DB Name | DB User | Cloud SQL Instance | Same as Real Alumni DB? |
|---|---|---|---|---|---|---|
| **Event App** | `127.0.0.1` | `5432` | `alumni_db` | `ananth` (local superuser) | None — no proxy configured | ❌ NO — local dummy only |
| **Website** (dev) | `127.0.0.1` | `5432` | `alumni_db` | `website_app` | Cloud SQL Proxy required | ✅ YES (via proxy in dev) |
| **Website** (prod) | Cloud SQL socket | — | `alumni_db` | `website_app` | `nitksaa-alumni-db` (asia-south1) | ✅ YES |
| **Portal-v2** (dev) | `127.0.0.1` | `5432` | `alumni_db` | `portal_user` | Cloud SQL Proxy (`./cloud-sql-proxy` binary present) | ✅ YES (via proxy in dev) |
| **Portal-v2** (prod) | Cloud SQL socket | — | `alumni_db` | `portal_user` | `nitksaa-alumni-db` (asia-south1) | ✅ YES |

**Key finding:** The local PostgreSQL instance (port 5432) has only one role: `ananth` (superuser). Neither `portal_user` nor `website_app` exists locally. The Website and Portal-v2 dev setups require the Cloud SQL Proxy to be running on port 5432 to forward to the real `nitksaa-alumni-db` Cloud SQL instance. The Event App bypasses this entirely and connects directly to the local `alumni_db` as user `ananth`.

**Source config evidence:**

- Event App `.env`: `ALUMNI_DB_URL=postgresql://ananth@localhost:5432/alumni_db`
- Website `settings.py` (prod path): `/cloudsql/project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db`
- Portal-v2 `database.py` (prod path): `/cloudsql/project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db`
- Portal-v2: `cloud-sql-proxy` binary present in `webapp/backend/` for local dev

---

## Actual Event App Alumni DB Verification

```
current_database(): alumni_db
PostgreSQL version: 18.3 (Homebrew) on aarch64-apple-darwin25.2.0
Local DB user: ananth (superuser — local dev only)
```

**Tables in local alumni_db:**

```
alumni  (only table — no audit_log, no secondary tables)
```

**alumni_count:**

```
4 records
```

**This is a local dummy DB, not the real NITKSAA alumni database.**

**Full contents of local dummy alumni_db:**

| alumni_id | fullname | email | branch | graduationyear | registrationstatus | firebase_uid |
|---|---|---|---|---|---|---|
| NITK2019EC002 | Priya Kumari Test | priya.test@nitksaa.dev | Electronics | 2019 | Self-Verified | TEST_ALUMNI_UID_002 |
| NITK2020CS001 | Ravi Shankar Test | ravi.test@nitksaa.dev | Computer Science | 2020 | Active | TEST_ALUMNI_UID_001 |
| NITK2021ME003 | Ajay Inactive Test | ajay.inactive@nitksaa.dev | Mechanical | 2021 | Pending | (null) |
| NITK2026IT001 | Username Alumni | username2026@gmail.com | Information Technology | 2026 | Active | fxvOA6JInMM2OPKb3vuSV7qJwtI3 |

**Local dummy alumni_db columns:**

```
alumni_id           text   NOT NULL
fullname            text   nullable
email               text   nullable
phone               text   nullable
graduationyear      integer nullable
branch              text   nullable
registrationstatus  text   nullable
firebase_uid        text   nullable
```

8 columns total. The real Cloud SQL alumni_db has at least 22 columns (evidenced by Portal-v2 me.py and alumni.py queries).

---

## Email Lookup Results

Queries run directly against the Event App local alumni_db:

```sql
-- Exact email lookup (mirrors find_alumni_by_email production logic)
SELECT alumni_id, fullname, email, registrationstatus
FROM alumni
WHERE LOWER(TRIM(email)) = LOWER(TRIM($1));

-- Prefix search
SELECT alumni_id, fullname, email, registrationstatus
FROM alumni
WHERE LOWER(TRIM(email)) LIKE LOWER(TRIM($1 || '%'));
```

| Email / Prefix | Found in Event App alumni_db (local) | Expected in Real Cloud SQL alumni_db | Notes |
|---|---|---|---|
| `sudarshana.ashwini@gmail.com` | ❌ NOT FOUND (0 rows) | ✅ EXISTS (Portal UI confirms) | Root cause of `user_type=other` in Event App |
| `Username2026@gmail.com` | ✅ FOUND — `NITK2026IT001`, Active | ❌ NOT expected to exist (test seed only) | Confirms local dummy DB is being used |
| prefix `sudarshana` (email or name) | ❌ NOT FOUND (0 rows) | ✅ EXISTS (Portal UI confirms) | No whitespace or case mismatch — record simply absent |

**There is no whitespace or case mismatch issue for `sudarshana.ashwini@gmail.com`. The record is simply not present in the local dummy database.**

---

## Column Mapping

Columns that exist in the real alumni_db (evidenced by Portal-v2 and Website code) vs the local dummy:

| Column | Portal / Website queries it | Event App alumni_service.py expects it | Exists in local dummy alumni_db |
|---|---|---|---|
| `alumni_id` | ✅ | ✅ | ✅ |
| `fullname` | ✅ | ✅ | ✅ |
| `email` | ✅ | ✅ | ✅ |
| `phone` | ✅ | ✅ | ✅ |
| `graduationyear` | ✅ | ✅ | ✅ |
| `branch` | ✅ | ✅ (in `get_alumni_profile_by_ref_id`) | ✅ |
| `registrationstatus` | ✅ | ✅ | ✅ |
| `firebase_uid` | ✅ | ✅ | ✅ |
| `secondaryemail` | ✅ (portal alumni.py export, me.py) | ❌ not queried | ❌ MISSING |
| `secondaryphone` | ✅ (portal alumni.py export, me.py) | ❌ not queried | ❌ MISSING |
| `degree` | ✅ (portal alumni.py) | ❌ not queried | ❌ MISSING |
| `gender` | ✅ (portal me.py) | ❌ not queried | ❌ MISSING |
| `dateofbirth` | ✅ (portal me.py) | ❌ not queried | ❌ MISSING |
| `currentlocation` | ✅ (portal alumni.py) | ❌ not queried | ❌ MISSING |
| `linkedin` | ✅ (portal alumni.py) | ❌ not queried | ❌ MISSING |
| `directory_visible` | ✅ (website alumni.py, portal alumni.py) | ❌ not queried | ❌ MISSING |
| `show_location` | ✅ (portal alumni.py, me.py) | ❌ not queried | ❌ MISSING |
| `show_linkedin` | ✅ (portal alumni.py, me.py) | ❌ not queried | ❌ MISSING |
| `show_company` | ✅ (portal me.py) | ❌ not queried | ❌ MISSING |
| `created_at` | ✅ (portal alumni.py export) | ❌ not queried | ❌ MISSING |
| `updated_at` | ✅ (portal alumni.py export) | ❌ not queried | ❌ MISSING |
| `last_login` | ✅ (portal alumni.py export) | ❌ not queried | ❌ MISSING |

The Event App `alumni_service.py` only queries `alumni_id`, `fullname`, `email`, `phone`, `graduationyear`, `branch`, `registrationstatus`, `firebase_uid` — exactly the 8 columns that happen to exist in the dummy DB. **This is a schema mismatch risk:** if the Event App is ever connected to the real alumni_db and queries that expect only these columns are run, the real DB may have different constraints or data types that need verification.

---

## Root Cause

**Root Cause A — confirmed primary root cause.**

The Event App local development environment is connected to a local PostgreSQL `alumni_db` database (user `ananth`, port 5432) that contains only 4 test seed records. This is not the real NITKSAA alumni database.

The real NITKSAA alumni database resides in a Cloud SQL PostgreSQL instance (`project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db`). The Website and Portal-v2 connect to it via Cloud SQL Proxy (local dev) or Unix socket (production). The Event App has no Cloud SQL Proxy configured and no `portal_user` / `website_app` credentials in its `.env`.

Because the local dummy alumni_db contains `username2026@gmail.com` as a seeded test alumni but does **not** contain `sudarshana.ashwini@gmail.com`, the Event App alumni lookup:
- Returns `alumni` for `username2026@gmail.com` → correct against the dummy DB, but meaningless
- Returns `other` for `sudarshana.ashwini@gmail.com` → incorrect; they exist in the real Cloud SQL alumni_db

**Root Cause E — confirmed secondary bug (independent of Root Cause A).**

The `ON CONFLICT` clause in `_upsert_event_user` ([auth.py:127–131](../../backend/app/api/auth.py#L127)) only updates `email`, `fullname`, and `last_login` on conflict:

```sql
ON CONFLICT (firebase_uid) DO UPDATE
SET email = EXCLUDED.email,
    fullname = EXCLUDED.fullname,
    last_login = now()
```

It does **not** update `user_type`, `ref_id`, or `graduation_year`. Consequence: if a user previously logged in and was registered as `user_type=other` with `ref_id=NULL` (because the alumni lookup failed at that time), and the DB is later corrected to point to Cloud SQL, re-login will find the alumni record and compute `user_type=alumni` — but the `ON CONFLICT` will leave the existing `event_users` row with `user_type=other`. The `RETURNING` clause returns the stale pre-conflict values, so the issued JWT will still say `other`.

Root Causes B (wrong column names), C (email in different field), and D (whitespace/case mismatch) were ruled out:
- The Event App queries columns that exist (`email`, `alumni_id`, `fullname`, `graduationyear`) and match what the real DB has.
- No whitespace mismatch for `sudarshana.ashwini@gmail.com` — prefix search also returned 0 rows.
- The real DB stores the email in the `email` column (not `secondaryemail`), confirmed by Portal and Website auth code both querying `WHERE LOWER(email) = LOWER(%s)`.

---

## Fix Recommendation

**Do not modify production data. Do not implement until approved.**

### Option 1 — Connect Event App to real alumni_db via Cloud SQL Proxy (recommended for integration testing)

Set up Cloud SQL Proxy locally on a distinct port (e.g., 5433) to forward to `nitksaa-alumni-db`:

```bash
./cloud-sql-proxy project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db \
  --port=5433
```

Update `backend/.env`:

```env
ALUMNI_DB_URL=postgresql://portal_user:N1TK_AppUser@127.0.0.1:5433/alumni_db
```

This gives the Event App the same real alumni dataset that the Portal and Website use.

> **Risk:** The real alumni_db contains PII. Do not expose endpoints beyond localhost. Do not commit this URL with production credentials. Use `ALUMNI_DB_URL` (not hardcoded) — already wired correctly in `config.py`.

### Option 2 — Import a safe anonymized snapshot of alumni_db for local dev

Create a `scripts/seed_alumni_dev.sql` with ~20–50 realistic anonymized alumni rows covering:
- Various `registrationstatus` values (Active, Self-Verified, Pending, Blocked, Deceased)
- A superset of real column names (including `secondaryemail`, `degree`, `directory_visible`, etc.)
- At least one row matching a known real test account

This avoids any direct connection to Cloud SQL for local dev.

### Option 3 — Document the current seed rows as canonical dev test data

If Option 1 or 2 is not pursued, document in `backend/README.md` that the local dummy alumni_db is intentionally disconnected from Cloud SQL, and that `DEV_DIAGNOSTICS_EMAIL=Username2026@gmail.com` is the only valid test alumni in local dev. All lookups for real alumni emails are expected to return `other` in local dev.

### Option 4 (secondary — fix the ON CONFLICT bug regardless of DB choice)

Update `_upsert_event_user` to also update `user_type`, `ref_id`, and `graduation_year` on conflict, but only if the new values are non-null / represent a promotion (i.e., `other` → `alumni`). For example:

```sql
ON CONFLICT (firebase_uid) DO UPDATE
SET email          = EXCLUDED.email,
    fullname       = EXCLUDED.fullname,
    user_type      = EXCLUDED.user_type,
    ref_id         = EXCLUDED.ref_id,
    graduation_year= EXCLUDED.graduation_year,
    last_login     = now()
```

This must be decided deliberately — there may be cases where a manual override of `user_type` should be preserved. Confirm intent before implementing.

---

## Safe Verification Commands

Run these psql commands to verify DB identity at any time:

```bash
# Which DB is the Event App actually connected to?
psql "postgresql://ananth@localhost:5432/alumni_db" \
  -c "SELECT current_database(), current_user;"

# How many alumni records?
psql "postgresql://ananth@localhost:5432/alumni_db" \
  -c "SELECT COUNT(*) AS alumni_count FROM alumni;"

# What columns exist in the alumni table?
psql "postgresql://ananth@localhost:5432/alumni_db" \
  -c "SELECT column_name, data_type FROM information_schema.columns \
      WHERE table_name='alumni' ORDER BY ordinal_position;"

# Test email lookup — sudarshana
psql "postgresql://ananth@localhost:5432/alumni_db" \
  -c "SELECT alumni_id, fullname, email, registrationstatus \
      FROM alumni WHERE LOWER(TRIM(email)) = LOWER(TRIM('sudarshana.ashwini@gmail.com'));"

# Prefix search — sudarshana
psql "postgresql://ananth@localhost:5432/alumni_db" \
  -c "SELECT alumni_id, fullname, email FROM alumni \
      WHERE LOWER(email) LIKE 'sudarshana%' OR LOWER(fullname) LIKE '%sudarshana%';"
```

If connected to real Cloud SQL via proxy on port 5433:

```bash
psql "postgresql://portal_user:N1TK_AppUser@127.0.0.1:5433/alumni_db" \
  -c "SELECT COUNT(*) AS alumni_count FROM alumni;"
```

A real alumni_db should return a count in the thousands.

---

## Risks

- **Do not write to alumni_db.** All auth flows in the Event App only read from it. The `get_alumni_pool()` connection must remain read-only by convention.
- **Do not expose alumni search endpoints outside development.** The `/api/v1/dev/diagnostics/alumni/*` endpoints are gated by `APP_ENV=development` (`_require_development()` check). Do not deploy them to production.
- **Do not copy production PII into the repository.** If creating a dev snapshot (Option 2), use synthetic/anonymized data only.
- **Do not commit `.env` secrets.** The `ALUMNI_DB_URL` and `DB_PASSWORD` for Cloud SQL must not appear in version control. Already excluded via `.gitignore` (verify).
- **Do not use `portal_user` credentials in Event App configs.** The Event App should have its own dedicated DB user with read-only access to `alumni_db`.

---

## PASS / FAIL Recommendation

**FAIL**

The Event App alumni lookup is **invalid** for real alumni in local development. The connected `alumni_db` is a local dummy database with 4 synthetic test records. It does not represent the real NITKSAA alumni dataset.

- Diagnostics showing `sudarshana.ashwini@gmail.com` as `other` or not found are **not trustworthy** — they reflect the local dummy DB state, not production alumni_db state.
- Diagnostics showing `Username2026@gmail.com` as `alumni` are **not trustworthy** — this is a test seed record with no counterpart in the real alumni_db.

All alumni lookup diagnostics must be re-run after connecting to the real Cloud SQL `alumni_db` (Options 1 or 2 above).

---

## Optional: Recommended Dev Diagnostics Enhancement

Add a `/api/v1/dev/diagnostics/alumni/db-info` endpoint (development only) that returns:

```json
{
  "current_database": "alumni_db",
  "alumni_count": 4,
  "is_dummy_db": true,
  "db_host_label": "localhost:5432",
  "warning": "alumni_count < 100: likely local dummy DB, not real Cloud SQL alumni_db"
}
```

This would make the DB identity immediately visible in the Flutter diagnostics UI without exposing passwords or full DSN. Implementation should be approved before proceeding.

---

*Report generated 2026-06-19 from direct read-only source code review and SQL queries. No data was modified. No emails were hardcoded in application code.*
