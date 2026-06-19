# Alumni DB Diagnostics Review

**Date:** 2026-06-19  
**Scope:** Developer Diagnostics — Alumni Database Verification Tools

---

## Summary

Added developer-only diagnostics to verify alumni records in `alumni_db` and trace why login
mapping may produce `user_type = other` / `ref_id = NULL` in `event_users`.

Root cause confirmed and documented. All validation checks pass.

---

## APIs Added

Four read-only development-only endpoints, registered under
`/api/v1/dev/diagnostics/alumni/`. All require backend JWT and return `404` unless
`APP_ENV = development`.

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/v1/dev/diagnostics/alumni/search?email=<email>` | Exact email search (case-insensitive, TRIM) |
| `GET` | `/api/v1/dev/diagnostics/alumni/search-prefix?prefix=<prefix>` | Email prefix or name fragment search |
| `GET` | `/api/v1/dev/diagnostics/alumni/{alumni_id}` | Full row lookup by alumni_id |
| `GET` | `/api/v1/dev/diagnostics/alumni/login-trace?email=<email>` | Trace auth login mapping — alumni_db → event_users |

**Route ordering:** `/alumni/search`, `/alumni/search-prefix`, and `/alumni/login-trace` are
registered before `/alumni/{alumni_id}` so FastAPI resolves static paths first.

**Source file:** `backend/app/api/dev_diagnostics.py`

---

## Flutter UI Added

New `Alumni Database` category added to `Developer Diagnostics` screen.

Four new cards:

| DiagnosticId | Title | Detail Screen |
|---|---|---|
| `alumniSearchEmail` | Search by Email | Input email → Found/Not Found badge + full record + JSON |
| `alumniSearchPrefix` | Search by Prefix | Input prefix → list of matches, tap to lookup by ID |
| `alumniLookupId` | Lookup by Alumni ID | Input alumni_id → full raw record + JSON |
| `alumniLoginTrace` | Login Mapping Trace | Input email → PASS/FAIL diagnosis with full trace |

All four tools:
- Accept free-form user input — no hardcoded values anywhere
- Show request URL and query parameters implicitly via the API details card
- Show HTTP status (errors surface as `_errorChip`)
- Show raw JSON response in an expandable tile with a **Copy JSON** button
- Do not display auth token

**Source file:**
`apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart`

---

## Root Cause Findings

### Root Cause 1 — ON CONFLICT does not update `user_type` / `ref_id` (PRIMARY)

**File:** `backend/app/api/auth.py` — `_upsert_event_user()`, lines 120–141

```sql
INSERT INTO event_users (firebase_uid, email, fullname, user_type, ref_id,
                         graduation_year, last_login)
VALUES ($1, $2, $3, $4, $5, $6, now())
ON CONFLICT (firebase_uid) DO UPDATE
SET email = EXCLUDED.email,
    fullname = EXCLUDED.fullname,
    last_login = now()
```

The `ON CONFLICT` clause updates only `email`, `fullname`, and `last_login`.
It does **not** update `user_type`, `ref_id`, or `graduation_year`.

**Consequence:** A user who logged in before their alumni record existed in `alumni_db`
(or before `ALUMNI_DB_URL` was configured) was inserted as `user_type = other`,
`ref_id = NULL`. Every subsequent login finds the existing `firebase_uid` row and
only updates `last_login` — the user_type/ref_id mismatch is permanently frozen.

**Diagnosis returned by `/alumni/login-trace`:**
```
fail_alumni_exists_but_event_user_not_mapped
```

**Fix (not applied in this session — separate change required):**
Add `user_type`, `ref_id`, and `graduation_year` to the `DO UPDATE SET` clause.
Only apply if the incoming lookup resolved an alumni record (i.e. only update
upward from `other → alumni`, not in the other direction).

### Root Cause 2 — `find_alumni_by_email` does not TRIM (SECONDARY)

**File:** `backend/app/services/alumni_service.py` — `find_alumni_by_email()`, line 23

```sql
WHERE lower(email) = lower($1)
```

This is case-insensitive but does not trim whitespace. If the email stored in
`alumni_db` has leading or trailing spaces, the match fails.

The diagnostic `/alumni/login-trace` detects this by running a second query with
`LOWER(TRIM(...))`. If the trimmed query finds a row but the untrimmed one does not,
the diagnosis is `warning_email_case_or_whitespace_mismatch`.

The `/alumni/search` endpoint uses `LOWER(TRIM(...))` to surface these records even
when production lookup would fail.

---

## Test Inputs Used

The diagnostics are designed for free-form input. No hardcoded emails appear in backend
or Flutter code. Example usage patterns:

- **Search by Email:** enter the full address observed in `event_users.email`
- **Search by Prefix:** enter a first name or partial email to locate records
- **Lookup by Alumni ID:** copy a `ref_id` from event_users to verify the alumni row
- **Login Mapping Trace:** enter the same email the user logs in with to get a PASS/FAIL

---

## Example Results

### Pass (correctly mapped)

```json
{
  "alumni_lookup": { "found": true, "alumni_id": "...", "registrationstatus": "Self-Verified" },
  "expected_event_user_mapping": { "expected_user_type": "alumni", "expected_ref_id": "..." },
  "existing_event_user": { "found": true, "user_type": "alumni", "ref_id": "..." },
  "diagnosis": { "result": "pass_mapping_correct" }
}
```

### Fail (alumni exists, event_user not mapped)

```json
{
  "alumni_lookup": { "found": true, "registrationstatus": "Self-Verified" },
  "expected_event_user_mapping": { "expected_user_type": "alumni", "expected_ref_id": "..." },
  "existing_event_user": { "found": true, "user_type": "other", "ref_id": null },
  "diagnosis": {
    "result": "fail_alumni_exists_but_event_user_not_mapped",
    "reason": "alumni found and active, but event_users row has user_type='other' ref_id=None. Root cause: ON CONFLICT in _upsert_event_user does not update user_type/ref_id/graduation_year for existing rows."
  }
}
```

### Warning (whitespace mismatch)

```json
{
  "alumni_lookup": { "found": true },
  "diagnosis": {
    "result": "warning_email_case_or_whitespace_mismatch",
    "reason": "alumni found only after trimming whitespace — production lookup (no TRIM) will fail for this email"
  }
}
```

---

## Verification Steps

1. Start backend: `cd backend && uvicorn app.main:app --reload`
2. Start Flutter: `cd apps/event_app && flutter run`
3. Sign in with a user account
4. Open `Developer Diagnostics` (visible in debug builds only)
5. Scroll to **Alumni Database** section
6. Open **Search by Email** → enter an email → verify Found/Not Found badge and JSON
7. Open **Search by Prefix** → enter a partial name → tap a result → verify full record loads
8. Open **Lookup by Alumni ID** → paste an alumni_id → verify full record
9. Open **Login Mapping Trace** → enter the email of a known affected user → check FAIL diagnosis
10. Copy JSON using the **Copy JSON** button and verify clipboard content

---

## PASS / FAIL Status

| Check | Status |
|-------|--------|
| `python -m compileall app` | PASS |
| `flutter analyze` | PASS (no issues) |
| `flutter test` (16 tests) | PASS |
| No hardcoded emails in backend or Flutter | PASS |
| No alumni_db writes in new endpoints | PASS |
| Endpoints return 404 outside development | PASS (via `_require_development()` in `_get_dev_user`) |
| Routes ordered: static before parameterized | PASS |

---

## Open Issues

1. **Fix not applied:** The `ON CONFLICT` bug in `_upsert_event_user` (Root Cause 1) is
   documented here but the fix requires a separate change with careful testing to avoid
   downgrading alumni users to `other` on re-login. Recommend a dedicated fix session.

2. **TRIM fix not applied:** `find_alumni_by_email` should add `TRIM($1)` to handle
   whitespace in stored email addresses. Low risk, low impact.

3. **No write path:** The diagnostics are read-only. A "fix mapping" button that calls a
   new admin endpoint (`PATCH /api/v1/admin/event-users/{firebase_uid}/remap-alumni`) is
   not in scope for this session.
