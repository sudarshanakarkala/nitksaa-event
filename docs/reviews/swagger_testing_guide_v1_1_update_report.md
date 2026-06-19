# Swagger Testing Guide v1.1 — Update Report

**Version:** 1.0  
**Date:** 2026-06-19  
**Status:** Complete  
**File Updated:** `docs/api/swagger_testing_guide.md` (v1.0 → v1.1)

---

## Summary

Four new sections were added to `docs/api/swagger_testing_guide.md`. No test cases were
removed or modified. All v1.0 content is preserved.

---

## Changes Made

### 1. Version Bump

Header updated: `Version: 1.0` → `Version: 1.1`

---

### 2. Endpoint Inventory Summary (new section, added after Intended Audience)

A summary table showing the number of endpoints per week:

| Week | Endpoint Count | Status |
|---|---|---|
| Week 1 | 3 | Implemented |
| Week 2 | 7 | Implemented |
| Week 3 | 6 | Implemented |
| Developer Diagnostics | Existing dev-only endpoints | Implemented |
| Week 4 | 2 | Planned |
| Total Implemented | 19 | Week 1–3 |

---

### 3. Role / Access Matrix (new section, added after Endpoint Inventory)

A 16-row table mapping every implemented endpoint to four access roles:

- **Public** — no auth required
- **Alumni** — backend JWT with `user_type = "alumni"` and valid `ref_id`
- **Admin** — backend JWT with admin/staff `user_type`
- **Dev Only** — `APP_ENV = "development"` required, returns 404 in production

Key access facts captured in the matrix:
- `GET /api/v1/events` (admin list — all statuses) is **Admin only** — not public
- `GET /api/v1/alumni/me` is **Alumni only** (admin can access if also mapped as alumni)
- All registration endpoints (`/register`, `/my-registration`, `/my/registrations`, `/eligibility`) are **Alumni only** — admin cannot register as admin
- All `/dev/diagnostics/*` are **Dev Only** — hidden in production

---

### 4. Registration State Diagram (new section, added before Week 3 section)

An ASCII diagram showing the registration lifecycle:

- Entry point: `GET /eligibility`
- Happy path: `eligible` → `POST /register` → `status: "registered"`
- Future cancellation path: `status: "cancelled"`
- Blocked states: `already_registered`, `full`, `closed`, `not_open_yet`, `ineligible`
- Join link reveal conditions: `status="registered"` AND `event.is_virtual=true` AND `event.status="published"`

Also includes the **Two-code rule** table cross-referencing eligibility GET values with POST error detail codes — this is the most common source of confusion when interpreting test results.

---

### 5. API Coverage Summary (new section, added before Final Checklist)

```text
Implemented APIs:            19
Active Swagger test cases:   32
Positive tests:              14
Negative tests:              16
Security tests:               2
Week 4 planned placeholders:  2
Total rows in checklist:      34
```

---

## Location of Each Addition in File

| Addition | Inserted Before |
|---|---|
| Endpoint Inventory Summary | §1 What Is Swagger? |
| Role / Access Matrix | §1 What Is Swagger? (after Endpoint Inventory) |
| Registration State Diagram | §9 Week 3 |
| API Coverage Summary | §11 Final Swagger Test Checklist |

---

## What Was NOT Changed

- All 34 test cases (W1-P1 through W4-P2) are unchanged
- All response shape examples are unchanged
- All troubleshooting entries are unchanged
- Authorization flow (Option A / Option B) is unchanged
- Test event IDs (25, 26, 34, 35, 36) are unchanged

---

## Validation

Documentation only — no backend or Flutter code was modified.

`docs/api/swagger_testing_guide.md` lint status: MD060 table column style warnings
are pre-existing across all documentation files in this project and are non-blocking.
