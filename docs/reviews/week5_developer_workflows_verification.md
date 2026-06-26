# Week 5 — Developer Workflows Verification

**Date:** 2026-06-26  
**Scope:** All Week 5 backend diagnostic endpoints  
**Status:** PASS (48/48) — updated after corrective sprint

All diagnostics are development-only — return `404 not_found` when `APP_ENV != development`.

---

## Quick Reference

```bash
BASE=http://localhost:8000/api/v1/dev/diagnostics/week5

# Run all Week 5 diagnostics in one call
curl -H "X-Dev-User: admin" $BASE/all

# Individual suites
curl -H "X-Dev-User: admin" $BASE/event-options
curl -H "X-Dev-User: admin" $BASE/people
curl -H "X-Dev-User: admin" $BASE/sponsors-partners
curl -H "X-Dev-User: admin" $BASE/analytics
```

---

## Endpoint Reference

| Endpoint | Scope | Tests | Status |
| --- | --- | --- | --- |
| `GET /api/v1/dev/diagnostics/week5/event-options` | Phase 1 (full-day + paid) | 6 | PASS 6/6 |
| `GET /api/v1/dev/diagnostics/week5/people` | People/Speakers foundation | 14 | PASS 14/14 |
| `GET /api/v1/dev/diagnostics/week5/sponsors-partners` | Sponsors + Partners | 17 | PASS 17/17 |
| `GET /api/v1/dev/diagnostics/week5/analytics` | Analytics logging | 11 | PASS 11/11 |
| `GET /api/v1/dev/diagnostics/week5/all` | Combined summary | 48 | PASS 48/48 |

---

## Response Format

Every individual diagnostic returns:

```json
{
  "status": "ok" | "warning" | "failed",
  "scope": "week5_event_options",
  "started_at": "2026-06-26T10:00:00Z",
  "completed_at": "2026-06-26T10:00:05Z",
  "total": 6,
  "passed": 6,
  "failed": 0,
  "warnings": 0,
  "test_event_id": 137,
  "results": [
    {
      "id": "eo_01",
      "name": "Create full-day event",
      "status": "PASS",
      "details": "event_id=137 is_full_day=True"
    }
  ]
}
```

`week5/all` wraps all four results under a `suites` array.

---

## What Each Suite Verifies

### `week5/event-options`

1. `eo_01` — Create full-day event (is_full_day=true)
2. `eo_02` — Admin response includes is_full_day, is_free, ticket_price
3. `eo_03` — Create paid event (is_free=false, ticket_price=500)
4. `eo_04` — Public detail includes full-day fields
5. `eo_05` — Public detail includes paid fields
6. `eo_06` — Existing events have boolean defaults (backward compat)

**Data management:** Creates and cancels 2 test events per run. Prefixed `DIAG_WEEK5_FULLDAY_*` and `DIAG_WEEK5_PAID_*`.

---

### `week5/people`

1. `people_01` — Create diagnostic event
2. `people_02` — Add HOST person
3. `people_03` — Add SPEAKER person
4. `people_04` — Add PANELIST person
5. `people_05` — Add CHIEF_GUEST person
6. `people_06` — Add GUEST_OF_HONOUR person
7. `people_07` — Add hidden SPEAKER (`is_visible=false`)
8. `people_08` — Admin list: 6 people including hidden
9. `people_09` — Public `people[]`: 5 visible people
10. `people_10` — Hidden person NOT in public response
11. `people_11` — Speakers[] contains SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR (4 roles)
12. `people_12` — HOST not in speakers[]
13. `people_13` — Update person title
14. `people_14` — Delete person

**Speakers derivation rule:** `speakers[]` includes visible people whose role is one of `{SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR}`. HOST, MODERATOR, and ORGANIZER are excluded.

**Data management:** Event is cancelled at end. Names prefixed `DIAG_HOST`, `DIAG_SPEAKER`, etc.

---

### `week5/sponsors-partners`

1. `sp_01` — Create diagnostic event
2. `sp_02` — Add GOLD_SPONSOR (display_order=0, created first — lower ID)
3. `sp_03` — Add TITLE_SPONSOR (display_order=0, created second — higher ID)
4. `sp_04` — Add hidden BRONZE_SPONSOR
5. `sp_05` — Add KNOWLEDGE_PARTNER (display_order=0, created first)
6. `sp_06` — Add COMMUNITY_PARTNER (display_order=0, created second)
7. `sp_07` — Add hidden MEDIA_PARTNER
8. `sp_08` — Admin sponsors list: 3 (including hidden)
9. `sp_09` — Admin partners list: 3 (including hidden)
10. `sp_10` — Public sponsors: 2 visible, no `is_visible` field
11. `sp_10_tier` — Sponsor tier ordering: TITLE_SPONSOR first (despite higher ID and same display_order)
12. `sp_11` — Public partners: 2 visible
13. `sp_11_alpha` — Partner alphabetical ordering: COMMUNITY_PARTNER first (despite higher ID and same display_order)
14. `sp_12` — Sponsors use `sponsor_id`, partners use `partner_id`
15. `sp_13` — Update sponsor description
16. `sp_14` — Update partner description
17. `sp_15` — Delete all 6 test records

**Ordering rules verified:**

- Sponsors: tier rank (TITLE=1, GOLD=2, SILVER=3, BRONZE=4, ASSOCIATE=5), then display_order ASC, then sponsor_id ASC
- Partners: partner_type ASC (alphabetical), then display_order ASC, then partner_id ASC

**Data management:** All sponsors/partners deleted in `sp_15`. Event cancelled at end.

---

### `week5/analytics`

1. `an_01` — Create diagnostic event
2. `an_02` — Log `EVENT_DETAIL_OPENED` (source: BACKEND)
3. `an_03` — Log `REGISTER_CLICKED` (source: FLUTTER)
4. `an_04` — Log `REGISTRATION_COMPLETED` (source: BACKEND)
5. `an_05` — Log `REGISTRATION_FAILED` (source: BACKEND)
6. `an_06` — Log `EMAIL_SENT` (source: EMAIL)
7. `an_07` — Log `EMAIL_FAILED` (source: EMAIL)
8. `an_08` — Rows present in `event_activity_log`
9. `an_09` — Metadata JSON stored correctly
10. `an_10` — `source_app` present in all rows
11. `an_11` — No secrets in metadata

**Data management:** Event cancelled at end. Log rows are intentionally kept — `event_activity_log` is append-only. Rows are easily identifiable by `event_id` from the diagnostic run.

---

## QA Checklist

Run before every deployment and after any backend change to Week 5 code:

- [ ] Backend starts cleanly (`curl http://localhost:8000/api/v1/health` returns `{"status":"ok"}`)
- [ ] `week5/all` returns `status=ok` with 0 failed
- [ ] No `WARNING` items in any suite result
- [ ] `test_event_id` is set in each suite (confirms event creation worked)
- [ ] Re-running is safe (no duplicate key errors, no leftover data issues)
- [ ] Admin build clean: `cd admin/event_admin && npm run build` exits 0
- [ ] Flutter analyze clean: `flutter analyze lib/features/developer/presentation/developer_diagnostics_screen.dart`

---

## Flutter Developer Diagnostics — Week 5 Category

The Flutter `DeveloperDiagnosticsScreen` now includes a **Week 5 — Event Enrichment** category with 5 items:

| Diagnostic Item | Backend Endpoint | Tests |
| --- | --- | --- |
| Week 5 — All Suites | `GET /api/v1/dev/diagnostics/week5/all` | 48 |
| Event Options Diagnostic | `GET /api/v1/dev/diagnostics/week5/event-options` | 6 |
| People / Speakers Diagnostic | `GET /api/v1/dev/diagnostics/week5/people` | 14 |
| Sponsors & Partners Diagnostic | `GET /api/v1/dev/diagnostics/week5/sponsors-partners` | 17 |
| Analytics Logging Diagnostic | `GET /api/v1/dev/diagnostics/week5/analytics` | 11 |

All 5 use `X-Dev-User: admin` header (dev mode). Each shows:

- Run Diagnostic button
- Overall status / passed / failed / warnings
- Per-suite breakdown (for "All Suites")
- Per-test result rows with id, name, status (PASS/FAIL/WARNING), and details

The category is `initiallyExpanded: false` (collapsed by default) — tap to expand.

---

## Admin Portal — Week 5 UI

The Event Admin Portal now supports Week 5 enrichment management. See `week5_admin_enrichment_ui_verification.md` for full detail.

### Quick reference

| Workflow | Location | How to access |
| --- | --- | --- |
| Create event with Full Day / Paid settings | `EventFormPage` | `/events/new` |
| Manage People / Speakers | `EventEnrichmentPanel` — People tab | `/events/{id}/edit` (below form) |
| Manage Sponsors | `EventEnrichmentPanel` — Sponsors tab | `/events/{id}/edit` (below form) |
| Manage Partners | `EventEnrichmentPanel` — Partners tab | `/events/{id}/edit` (below form) |
| See Full Day / Paid indicators | `EventsPage` table | `/events` |

After creating a new event, the admin portal navigates directly to the edit page so the enrichment panel is immediately accessible.

---

## Verification Run (2026-06-26)

```text
OVERALL: status=ok  passed=48/48  failed=0  warnings=0

  week5_event_options:     ok  6/6
  week5_people:            ok  14/14
  week5_sponsors_partners: ok  17/17
  week5_analytics:         ok  11/11
```

Backend import check: clean.
Admin build: 78 modules, 0 errors, 0 warnings.
Flutter analyze (diagnostics screen): 0 issues.
