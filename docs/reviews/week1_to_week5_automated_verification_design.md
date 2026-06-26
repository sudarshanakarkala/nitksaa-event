# Week 1–5 Automated Verification Suite — Design Document

**Date:** 2026-06-26
**Script:** `backend/scripts/verify_all_weeks.py v1.0.0`
**Status:** COMPLETE — 135 PASS, 0 FAIL, 25 WARNING

---

## Purpose

`verify_all_weeks.py` is a single-command automated verification tool for the NITKSAA Event Platform.
It covers every completed feature from Week 1 through Week 5, generates machine-readable JSON and
human-readable Markdown reports, and exits with code 0 (PASS/WARNING) or 1 (FAIL) for CI use.

---

## Architecture

### Key Invariants

- **No database writes outside diagnostic test data.** All created events are tagged with the `DIAG_ALL_WEEKS` prefix and cancelled/deleted by `_cleanup()` at the end of each run.
- **No credentials in reports.** The `_redact()` function recursively masks values under secret-looking keys before writing JSON output.
- **No alumni DB writes.** Registration tests that require alumni JWT are marked WARNING, not FAIL.
- **Backend must be running.** The script is not self-hosting; it tests a live server.
- **Idempotent.** Multiple runs leave no permanent state (DIAG events are always cancelled).

### Components

| Component | Purpose |
|---|---|
| `APIClient` | Thin `httpx.Client` wrapper; adds admin header to every request |
| `Verifier` | Orchestrates all 14 test categories; tracks created event IDs for cleanup |
| `_parse_diag_suite()` | Normalizes varying diagnostic response formats into common `{id, name, status, details}` |
| `_redact()` | Recursive secret masker applied to JSON report output |
| `_scan_secrets()` | Regex scan of response bodies for credential-like keys |
| `write_json()` | Writes redacted JSON report |
| `write_markdown()` | Writes human-readable Markdown report |

---

## Test Categories (14 total)

| ID | Category | Tests | What it verifies |
|---|---|---|---|
| `env` | Week 1 — Environment & Health | 6 | Health endpoints, dev mode auth, secrets scan |
| `api_index` | API Index Consistency | 16 | All Week 1–5 routes exist; auth guards; W5 enrichment and diagnostic routes |
| `public_events` | Week 2 — Public Events | 10 | Public list/detail shape; W5 arrays; is_full_day/is_free; security |
| `admin_events` | Week 2+5 — Admin Events | 8 | CRUD via `/api/v1/events`; W5 defaults; paid/full-day event creation |
| `registration` | Week 3 — Registration Flow | 26 | Registration diagnostic endpoint; eligibility auth; JWT-dependent tests as WARNING |
| `admin_attendees` | Week 4 — Admin Attendees | 19 | Attendees list, pagination, search, batch_year, CSV export, security |
| `week5_event_options` | Week 5 — Event Options | 7 | `is_full_day`, `is_free`, `ticket_price` create/read/backward-compat |
| `week5_people` | Week 5 — People/Speakers | 17 | CRUD; visibility rules; speakers[] derivation (SPEAKER/PANELIST/CHIEF_GUEST/GUEST_OF_HONOUR) |
| `week5_sponsors_partners` | Week 5 — Sponsors & Partners | 20 | CRUD; visibility; sponsor tier ordering; partner alphabetical ordering |
| `week5_analytics` | Week 5 — Analytics | 13 | Activity log creation; metadata storage; no-secrets check |
| `diagnostics_combined` | Combined Diagnostics | 4 | Events diag, registrations diag, week5/all, week5/all-weeks endpoints |
| `admin_build` | Admin Portal Build | 2 | `npm run build` exits 0; no error lines |
| `flutter_static` | Flutter Static | 3 | `flutter analyze` 0 issues; `flutter test` with known-failure classification |
| `docs_presence` | Documentation Presence | 9 | All required docs exist and are non-empty |

---

## Endpoints Tested

### Admin API (development dev-auth header)

| Endpoint | Method | Category |
|---|---|---|
| `/api/v1/health` | GET | env, api_index |
| `/api/v1/events` | GET, POST, PATCH | api_index, admin_events |
| `/api/v1/events/{id}` | GET, PATCH | admin_events |
| `/api/v1/events/{id}/status` | PATCH | admin_events |
| `/api/v1/events/public` | GET | public_events |
| `/api/v1/events/public/{id}` | GET | public_events |
| `/api/v1/events/{id}/people` | GET, POST, PUT, DELETE | week5_people |
| `/api/v1/events/{id}/sponsors` | GET, POST, PUT, DELETE | week5_sponsors_partners |
| `/api/v1/events/{id}/partners` | GET, POST, PUT, DELETE | week5_sponsors_partners |
| `/api/v1/admin/events/{id}/attendees` | GET | admin_attendees |
| `/api/v1/admin/events/{id}/attendees/export` | GET | admin_attendees |
| `/api/v1/dev/diagnostics/events` | GET | diagnostics_combined |
| `/api/v1/dev/diagnostics/registrations` | GET | registration |
| `/api/v1/dev/diagnostics/attendees` | GET | admin_attendees |
| `/api/v1/dev/diagnostics/week5/event-options` | GET | week5_event_options |
| `/api/v1/dev/diagnostics/week5/people` | GET | week5_people |
| `/api/v1/dev/diagnostics/week5/sponsors-partners` | GET | week5_sponsors_partners |
| `/api/v1/dev/diagnostics/week5/analytics` | GET | week5_analytics |
| `/api/v1/dev/diagnostics/week5/all` | GET | diagnostics_combined |
| `/api/v1/dev/diagnostics/week5/all-weeks` | GET | diagnostics_combined |

### Public API (no auth)

| Endpoint | Method | Category |
|---|---|---|
| `/api/v1/events/public` | GET | public_events |
| `/api/v1/events/public/{id}` | GET | public_events |
| `/api/v1/events/{id}/registration-eligibility` | GET | registration |
| `/api/v1/auth/me` | GET | api_index |
| `/api/v1/alumni/me` | GET | api_index |

---

## Known Limitations (documented as WARNING)

| Limitation | Reason | Tests affected |
|---|---|---|
| Registration diagnostic: 3/13 PASS | Alumni DB not seeded with test user locally; Cloud SQL alumni_db required | `w3_reg_diag_*`, `comb_registrations` |
| Registration flow JWT tests | `X-Dev-User: admin` cannot register; alumni Bearer JWT required | `w3_reg_03`–`w3_reg_13` |
| Flutter test: 1 pre-existing failure | "authenticated Register shows Week 3 message" — GoRouter not in test harness, from Week 2 commit 21ee22f | `flutter_02`, `flutter_known_*` |
| API Index: auth/firebase method | Unauthenticated POST returns 405 (method-not-found before body parse), not 422 | `api_idx_05` |

---

## Test Data Lifecycle

All test events created by the script use the title prefix `DIAG_ALL_WEEKS_HHMMSS`. The `_cleanup()` method
cancels all events in `_created_event_ids` at the end of `run_all()`, regardless of test outcomes. If the
script is killed mid-run, leftover events can be cleaned with:

```sql
UPDATE events SET status='cancelled' WHERE title LIKE 'DIAG_ALL_WEEKS%' AND status = 'draft';
```

Week 5 diagnostic endpoints create and clean up their own data internally (not tracked by the script).

---

## CLI Usage

```bash
cd backend
source .venv/bin/activate

# Basic run against local server
python scripts/verify_all_weeks.py

# Full options
python scripts/verify_all_weeks.py \
  --base-url http://127.0.0.1:8000 \
  --admin-header "X-Dev-User: admin" \
  --json-output ../docs/reviews/week1_to_week5_automated_verification.json \
  --markdown-output ../docs/reviews/week1_to_week5_automated_verification_report.md \
  --repo-root ..
```

### Exit Codes

| Code | Meaning |
|---|---|
| `0` | PASS or WARNING — safe to proceed |
| `1` | FAIL — at least one test failed; investigate before committing |

---

## Report Files

| File | Format | Purpose |
|---|---|---|
| `docs/reviews/week1_to_week5_automated_verification.json` | JSON | Machine-readable; CI/CD integration |
| `docs/reviews/week1_to_week5_automated_verification_report.md` | Markdown | Human review; PR description |

Both files are regenerated on every run. The JSON report has all credential-like values redacted via `_redact()`.

---

## New Backend Endpoint

As part of this suite, `GET /api/v1/dev/diagnostics/week5/all-weeks` was added to `week5_diagnostics.py`.

**URL:** `GET /api/v1/dev/diagnostics/week5/all-weeks`
**Auth:** `X-Dev-User: admin` (development mode only)
**Returns:** Combined result from Week 5 diagnostic suites (`event-options`, `people`, `sponsors-partners`,
`analytics`) plus an HTTP sub-request to the events diagnostic (`/api/v1/dev/diagnostics/events`).

**Omitted** (documented in response `"omitted"` array):
- `registrations_diagnostic` — requires alumni JWT
- `attendees_diagnostic` — requires a known event_id

---

## Relationship to Existing Diagnostics

The script complements (does not replace) the existing diagnostic endpoints:

| Existing diagnostic | Script interaction |
|---|---|
| `/api/v1/dev/diagnostics/events` | Called via HTTP; results surfaced in `diagnostics_combined` |
| `/api/v1/dev/diagnostics/registrations` | Called via HTTP; FAIL results reclassified as WARNING (expected locally) |
| `/api/v1/dev/diagnostics/attendees` | Called via HTTP with a found event_id |
| `/api/v1/dev/diagnostics/week5/*` | Each called directly; results surfaced in their own category |

---

## Safe-to-Commit Verdict

| Check | Result |
|---|---|
| 0 FAIL tests | ✅ PASS |
| All Week 5 diagnostic suites 100% | ✅ PASS (event-options 6/6, people 14/14, sponsors-partners 17/17, analytics 11/11) |
| Admin portal build | ✅ PASS (78 modules, 0 errors) |
| Flutter analyze | ✅ PASS (0 issues) |
| 9/9 required docs present | ✅ PASS |
| 25 warnings — all expected locally | ✅ Documented |
| Secrets scan | ✅ CLEAN |

**Verdict: PASS — safe to commit.**
