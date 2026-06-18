# Week 3 — Manual Verification Guide Update Report

**Date:** 2026-06-18  
**Status:** COMPLETE  
**Backend changes:** None  
**Flutter changes:** None

---

## Summary

Five new manual verification test cases were added to
`docs/validation/backend_week3_manual_verification_guide.md`. The additions cover two security
invariants (join_url cancellation behavior and capacity counting), two API integrity checks
(registration number uniqueness and snapshot immutability), and one database constraint test
(partial unique index enabling re-registration). The PASS/FAIL checklist was updated to include
all five new checks. Total checklist count increased from 55 to 60.

---

## File Updated

`docs/validation/backend_week3_manual_verification_guide.md`

---

## Test Cases Added

### SEC-07 — Cancelled Registration Hides join_url

**Location:** Section 5.1  
**Purpose:** Verify that `_resolve_join_url()` returns `null` when `status = 'cancelled'`, even
for a virtual published event.

**Key steps:**
1. Confirm `join_url` is non-null for a registered virtual event (UC-02 baseline).
2. Cancel the registration via controlled `psql UPDATE` (no public cancel endpoint in Week 3).
3. Call `GET /events/26/my-registration` — confirm `join_url` is `null`.
4. Restore the registration.

**Rule validated:**
```
join_url != null  ⟺  status='registered' AND is_virtual=true AND event_status='published'
```

---

### SEC-08 — Cancelled Registration Not Counted in registered_count

**Location:** Section 5.1  
**Purpose:** Verify that capacity enforcement and `registered_count` are computed only from
`status='registered'` rows — cancelled rows do not consume capacity.

**Key steps:**
1. Record `registered_count` via eligibility endpoint.
2. Confirm DB `COUNT(status='registered')` matches.
3. Cancel a registration via `psql UPDATE`.
4. Confirm API `registered_count` decreases by 1.
5. Confirm DB shows the cancelled row retained (not deleted).
6. Restore.

**SQL provided for verification:**
```sql
SELECT
  COUNT(*) FILTER (WHERE status = 'registered') AS active_count,
  COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled_count
FROM registrations WHERE event_id = 25;
```

---

### API-01 — Registration Number Uniqueness

**Location:** Section 5.2  
**Purpose:** Verify `registration_number` uniqueness and correct format across all registrations.

**Key queries provided:**
- Duplicate detection: `GROUP BY registration_number HAVING COUNT(*) > 1` → 0 rows expected.
- Format check: `NOT LIKE 'NITKSAA-____-______'` → 0 rows expected.
- Sequence verification: `split_part(..., '-', 3)` equals `registration_id` for all rows.

---

### API-02 — Registration Snapshots Unchanged After Alumni Profile Change

**Location:** Section 5.2  
**Purpose:** Verify that snapshot fields (`fullname_snapshot`, `email_snapshot`, `phone_snapshot`,
`batch_year_snapshot`, `branch_snapshot`) are frozen at registration time. A later update to
`alumni_db.alumni` must not alter existing registration records.

**Key steps:**
1. Record baseline snapshot from `GET /events/25/my-registration`.
2. Temporarily update `alumni_db.alumni` — fullname, phone, graduationyear, branch.
3. Confirm `GET /alumni/me` reflects the change (live profile updated).
4. Confirm `GET /events/25/my-registration` snapshot fields are unchanged.
5. **Restore `alumni_db`** — mandatory; other tests depend on the record.

**Warning included:** Failure to restore the alumni record will cause NC-06, UC-11, and
diagnostics checks to fail.

---

### DB-07 — Partial Unique Index Allows Re-Registration After Cancellation

**Location:** Section 5.3  
**Purpose:** Verify migration 008 replaced a hard `UNIQUE(event_id, firebase_uid)` constraint
with a partial unique index (`WHERE status = 'registered'`), enabling re-registration after
cancellation.

**Key steps:**
1. Confirm active registration exists for event 25.
2. Attempt duplicate registration — confirm `409 already_registered`.
3. Cancel via `psql UPDATE`.
4. Re-register — confirm HTTP `201`, new `registration_number`.
5. Verify two rows coexist: one `cancelled`, one `registered`, same `firebase_uid`.
6. Optionally inspect `pg_indexes` for the partial index predicate.

**FAIL condition documented:** If Step 4 returns `409`, migration 008 was not applied or was
rolled back.

---

## Checklist Count Before / After

| Section | Before | After | Delta |
| --- | --- | --- | --- |
| 11.1 Setup and Login | 6 | 6 | — |
| 11.2 Developer Diagnostics | 15 | 15 | — |
| 11.3 Positive Use Cases | 6 | 6 | — |
| 11.4 Negative Use Cases | 10 | 10 | — |
| 11.5 Eligibility Status v2 | 6 | 6 | — |
| 11.6 Database Verification | 6 | 7 | +1 (DB-07) |
| 11.7 Security Invariants | 6 | 8 | +2 (SEC-07, SEC-08) |
| 11.8 API Integrity | — | 2 | +2 (API-01, API-02) |
| **TOTAL** | **55** | **60** | **+5** |

---

## Assumptions

1. **No public cancel endpoint in Week 3.** SEC-07, SEC-08, and DB-07 all require cancelling a
   registration. Since no cancel endpoint is exposed, the guide uses controlled `psql UPDATE`
   commands. This is clearly marked as a local-dev-only operation with a warning not to run
   in staging or production.

2. **Test event IDs.** New tests reference events 25 and 26 — the same physical and virtual
   events already used by UC-01 and UC-02. If these events are recreated with different IDs,
   the test steps must be updated accordingly.

3. **alumni_db restoration is mandatory.** API-02 temporarily modifies `alumni_db.alumni`. The
   restoration step (Step 6 in API-02) is marked as REQUIRED because NC-06, UC-11, and
   diagnostics test D-02 all depend on the alumni record being in its original Active state.

4. **Snapshot DB column names.** The `RegistrationResponse` field names (`fullname_snapshot`,
   `email_snapshot`, etc.) do not all match the DB column names. The mapping table in API-02
   documents the correct correspondence.

5. **DB-07 partial index.** The test assumes migration 008 was applied. If the database was
   created from scratch without running all migrations, the test may behave differently.

---

## PASS / FAIL Status

| Gate | Status |
| --- | --- |
| Backend code modified | NOT MODIFIED |
| Flutter code modified | NOT MODIFIED |
| New test cases added to guide | COMPLETE — 5 test cases |
| Table of Contents updated | COMPLETE — sections 5.1, 5.2, 5.3 added |
| Documentation warning added | COMPLETE — before section 5.1 |
| Checklist §11.6 updated | COMPLETE — DB-07 added |
| Checklist §11.7 updated | COMPLETE — SEC-07, SEC-08 added |
| Checklist §11.8 created | COMPLETE — API-01, API-02 |
| Overall totals updated | COMPLETE — 55 → 60 |

**Overall: COMPLETE**

---

## Next Steps

- Run the new test cases (SEC-07, SEC-08, API-01, API-02, DB-07) during Week 3 manual verification.
- If a public cancel endpoint is added in Week 4, update SEC-07, SEC-08, and DB-07 to use the
  API instead of direct psql updates.
- If test event IDs change (events recreated), update event_id references in the new sections.
