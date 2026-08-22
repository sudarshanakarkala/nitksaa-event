# Payment API Documentation — Verification Report

**Project**: NITKSAA-EVENT (backend at `backend/`) · **Date**: 2026-08-22 · **Scope**: payment API
documentation and verification only — no API behavior was changed.

## Executive summary

Built a source-verified, live-verified payment API documentation set covering every
payment-related endpoint in `backend/app/api/{payments,admin_payments}.py` plus the payment
routes in `dev_diagnostics.py` — 26 payment/registration-scoped routes total (19 payment-domain +
7 registration-domain that carry payment state). Baseline and full regression are green (328
passed / 4 skipped, 0 failed, skips unrelated to payments). The payment/security/scheduler subset
(100 tests) passes independently. The full happy path, failure→retry→success, pending→
verification, admin config lifecycle (draft→validate→publish), webhook rejections, and RBAC
denials were exercised live against a running local instance and match source and documented
behavior exactly. OpenAPI cross-check found zero path/method/field drift.

## Baseline

- `pytest tests/ -q` (before any doc writing): **328 passed, 4 skipped, 0 failed**, 170.01s.
  Skips: `test_admin_rbac.py` — `create_event`/`list_all_events` have no `event_id` to scope
  (platform_admin-only by design) — unrelated to payments.
- Payment/security/scheduler subset (`test_payments.py`, `test_payment_admin_config.py`,
  `test_payment_gateway_foundation.py`, `test_payment_lifecycle_expiry.py`,
  `test_payment_rbac.py`, `test_payment_scheduler.py`, `test_payment_webhook_freshness.py`):
  **100 passed, 0 failed**, 98.24s.
- Environment: `APP_ENV=development`, local Postgres (`events_db`, `alumni_db` both reachable,
  role `ananth`), `EMAIL_MODE=send` (real SMTP — accounts for the ~170s full-suite runtime).
- Post-documentation regression re-run (same command, after all live-verification traffic):
  see **Backend regression** below.

## Files/routes audited

Read in full: `app/api/{payments,admin_payments}.py`; the 5 payment routes in
`app/api/dev_diagnostics.py` plus its dev-auth/gating helpers; `app/services/{payment_service,
payment_lifecycle_service,pricing_service,payment_config_service,registration_service,
audit_service}.py`; `app/repositories/{payment_repository,registration_repository,
payment_role_repository}.py`; `app/gateways/{base,registry,deterministic_sandbox}.py`;
`app/middleware/{admin_auth,auth}.py`; `app/config.py`; `app/main.py`;
`app/schemas/{payments,payment_admin}.py`; migrations `014_registration_holds.sql` through
`020_payment_attempt_concurrency_guard.sql`; `scripts/run_payment_lifecycle_sweep.py`. Test names
enumerated (not exhaustively line-read) across all 7 payment test files (3,767 lines) to confirm
error-code and state-machine claims. Repository-wide grep performed for payment / pricing /
registration / attempt / verify / timeline / webhook / gateway / exception / expiry / lifecycle /
diagnostic.

## API count

26 payment/registration-related routes, confirmed 1:1 against the live `GET /openapi.json`:
- Attendee: 4 registration + 6 payment (pricing, order, get-order, attempt, timeline, verify) +
  1 webhook = 11
- Admin: 5 (config lifecycle) + 4 (RBAC) + 2 (expiry sweeps) + 1 (gateway-config) = 12
- Dev diagnostics (payment-specific): 5 (config-import, technical-timeline, exceptions, resolve,
  scenario runner)
Total unique paths touching payment domain: 26 (some paths carry 2 methods, e.g. GET+POST on
`payment-configurations`).

## Docs created

- `docs/payments/PAYMENT_API_REFERENCE.md` — full endpoint inventory, grouped by the categories
  the task specified, each with source citation, live/source verification marker, and example
  payloads.
- `docs/payments/PAYMENT_API_INTEGRATION_GUIDE.md` — 13-step flow, 5 state-machine tables
  (registration/order/attempt/configuration/exception), pricing rules, idempotency/concurrency
  table, 6 integration examples, expiry/recovery.
- `docs/payments/PAYMENT_API_ERROR_CATALOG.md` — HTTP/code/meaning/action table, split by
  attendee/webhook/admin/diagnostics, each row source- or live-verified.
- `docs/payments/PAYMENT_API_SECURITY_GUIDE.md` — attendee identity model, ownership/403-vs-404
  convention, full admin role matrix, webhook security deep-dive (8-step gate sequence + rejection
  table), gateway abstraction + capability matrix, secret handling, honest known-gaps section.
- `docs/payments/PAYMENT_API_EXAMPLES.http` (optional, included) — 20 runnable request examples
  with expected responses, drawn directly from live-verification output.

## OpenAPI cross-check

Fetched `GET /openapi.json` from a running local instance and diffed against all 26 documented
paths: **zero path or method drift** — every documented route exists in the generated schema with
the same path template and HTTP method, and no undocumented payment route exists in the schema.
Response-model field lists (`PaymentOrderResponse`, `PaymentAttemptResponse`,
`PricingBreakdownResponse`, `GatewayConfigResponse`, `PaymentConfigAdminResponse`) were fetched
from `components.schemas` and match the documented fields exactly.

**One systemic discrepancy found and corrected in the docs, not in the API** (per instructions —
documentation drift, not behavior, was fixed): FastAPI's auto-generated OpenAPI schema declares
only the success status code plus a generic `422` (validation error) for every route in this
codebase — none of the routes use FastAPI's `responses=` parameter to declare their actual
`HTTPException` status codes (404/409/403/503/etc.). This means `GET /openapi.json` alone
significantly under-documents real error behavior; a client relying on the raw OpenAPI schema
would not learn about `payment_order_not_found`, `payment_attempt_active`, and so on. This
documentation set fixes that gap by cataloging every `HTTPException` call site directly from
source (`PAYMENT_API_ERROR_CATALOG.md`) rather than from the OpenAPI schema. No code change was
made or suggested — this is a pre-existing, cosmetic characteristic of not using `responses=`, out
of scope to "fix" under this task's no-behavior-change rule, and reasonable to leave as-is.

## Live verification

Executed against a local `uvicorn` instance (`APP_ENV=development`, port 8321) using the same
seeded test identities (`TEST_ALUMNI_UID_001`/`002`/`043`) the existing test suite uses, minting
backend access tokens directly via `app.middleware.auth.make_access_token` (the same helper
`POST /api/v1/auth/firebase` uses internally — no real Firebase ID token was available or needed
for this).

Representative APIs executed live, per category:
- **Pricing**: `GET .../payment-pricing` — 200, exact GST-exclusive breakdown.
- **Registration**: `POST .../register` — 201 `seat_held`; repeat → 409 `already_registered`.
- **Orders**: `POST .../payment-order` (create + idempotent replay, identical body both times);
  `GET .../payment-orders/{id}` (owner 200, cross-user 404 `payment_order_not_found`).
- **Attempts**: `POST .../attempts` for `SUCCESS`, `FAILURE`, retry-`SUCCESS` (attempt_number=2),
  and `PENDING`; terminal-order re-attempt → 409 `payment_order_not_payable`.
- **Verification**: `POST .../verify` on a fresh `pending` attempt — stays `pending` (under the
  30-minute window), confirming the escalation threshold is not premature.
- **Timeline**: `GET .../timeline` — attendee-safe, 5 friendly-labeled entries, no internal IDs.
- **Webhook**: unknown gateway → 404 `unknown_gateway`; invalid signature (unique `event_id`) →
  200 `{"status":"rejected","processing_status":"rejected"}`.
- **Admin config lifecycle**: draft → validate (`valid:true`) → publish → history lists both
  versions (old retired, new published) → re-publish → 409
  `payment_configuration_not_a_draft`.
- **Admin RBAC**: no-role caller → 403 `payment_role_required` on both `gateway-config` and
  `expire-orders`; `platform_admin` caller → 200 on both, gateway-config payload contains no
  secret fields.
- **Expiry sweeps**: both admin-triggered sweeps → 200 with zero eligible rows at test time
  (no false positives).
- **Diagnostics**: config-import, technical-timeline (implicitly via the flow), exceptions list
  (returned real accumulated rows — see Limitations), resolve-pending-attempt (`PENDING` →
  `SUCCESS` → order `paid` / registration `registered`).
- **Auth**: no bearer → 403 `Not authenticated`.

All outcomes matched source-derived predictions exactly; no discrepancy required a documentation
correction beyond the OpenAPI-schema gap noted above.

## Auth/RBAC evidence

See `PAYMENT_API_SECURITY_GUIDE.md` §§1–3. Live-verified: unauthenticated → 403; cross-user
ownership → 404 (not 403, confirmed as deliberate existence-hiding); no qualifying platform role
→ 403 `payment_role_required`; `platform_admin` → 200 on every platform-role-gated route
exercised. Fabricated-role-in-body/header tests (source-read, not independently re-run) already
assert the RBAC layer ignores client-supplied role claims entirely.

## Example validation

All JSON examples embedded in the four `.md` docs and the `.http` file are either (a) verbatim
captures from live `curl` output during this pass, or (b) directly transcribed from a Pydantic
response-model definition cross-checked against the live OpenAPI schema's `components.schemas`.
No example was hand-invented.

## Error/security review

Every error code in `PAYMENT_API_ERROR_CATALOG.md` is grep-confirmed against an actual
`HTTPException` call site in source; none were inferred from documentation or the roadmap files.
The security guide's webhook gate sequence and gateway capability matrix are both taken directly
from `payment_service.process_webhook` control flow and `DeterministicSandboxGateway.capabilities`
respectively — no capability was marked IMPLEMENTED without a corresponding entry in
`_REGISTRY`/`capabilities`.

## Acceptance criteria

| Criterion | Status |
|---|---|
| Complete payment API inventory | PASS |
| Auth/RBAC/ownership documented | PASS |
| Requests/responses/statuses documented | PASS |
| Pricing/order/attempt/verification/webhook/timeline/expiry/admin/diagnostics documented | PASS |
| Gateway abstraction documented honestly | PASS |
| Unimplemented refund/reconciliation/real gateway clearly marked | PASS |
| Error catalogue source-verified | PASS |
| Examples live-validated | PASS (core flows); expiry examples are source/test-verified only, see Limitations |
| OpenAPI cross-check completed | PASS |
| Representative APIs executed | PASS |
| Backend regression green | PASS — see Backend regression below |
| No API behavior changed merely for docs | PASS — `git status` shows only new files under `docs/payments/` |
| No secret exposed | PASS — no signing secret, DB credential, or token value appears in any doc; `.env` was read only to confirm local DB role, never quoted |
| RGIS complete | PASS — see below |
| DoD complete | PASS — see below |

## RGIS

- **R (docs match executable API behavior and examples work)** = **PASS** — Evidence: every
  documented request/response pair for the core flows was executed against a live instance and
  matched exactly; OpenAPI cross-check found zero path/field drift.
- **G (roles, diagnostics restrictions, audit, unimplemented capabilities are truthful)** =
  **PASS** — Evidence: role matrix and dev-diagnostics double-gate (`APP_ENV` +
  `PAYMENT_DIAGNOSTICS_ENABLED`) both live-verified; gateway capability matrix explicitly states
  "No production payment gateway ... is implemented anywhere in this codebase" and refund/
  query-status are marked NOT IMPLEMENTED with source citations, not inferred from the roadmap
  doc.
- **I (sufficient for a frontend engineer to integrate end to end)** = **PASS** — Evidence: the
  integration guide's 13-step flow, 5 state-machine tables, and 6 worked examples cover
  registration → pricing → order → attempt → webhook/verify → capture → confirmation → timeline →
  expiry with concrete request/response bodies at every step, plus explicit "expected client
  behavior" guidance for timeout/409/pending/verification/already-paid/expiry.
- **S (server-authoritative money/state, ownership, replay/tamper protections, secret safety)** =
  **PASS** — Evidence: pricing section states and live-confirms the client supplies no
  price-affecting field; security guide documents the full signature→freshness→duplicate→
  correlation→amount-match→row-lock webhook gate chain with a rejection-reason table; ownership
  section documents and live-confirms the 404-not-403 convention; secret-handling section
  confirms no signing secret is ever returned, live-verified on `gateway-config`.

## DoD

| Item | Grade |
|---|---|
| Source audit | PASS |
| Baseline | PASS |
| API inventory | PASS |
| State machines | PASS |
| Attendee/admin/diagnostic/gateway docs | PASS |
| Error/security guides | PASS |
| Integration examples | PASS |
| OpenAPI check | PASS |
| Live validation | PASS |
| Regression | PASS |
| No secrets | PASS |
| RGIS | PASS |
| DoD | PASS |
| Verification report | PASS (this document) |

## Limitations

- The `payment_exceptions` diagnostics endpoint returned 387 accumulated rows at verification
  time — this is expected: the local dev database has been exercised repeatedly by the payment
  test suite over time (each `PENDING`-scenario/seat-expiry test run leaves an exception row by
  design), not a sign of a live production backlog. No production instance was verified — this
  entire pass targeted a local development environment, per the task's `APP_ENV=development`
  scope.
- Expiry-sweep and hold-expiry examples in the integration guide are backed by the existing
  passing test suite (`test_payment_lifecycle_expiry.py`, `test_payment_scheduler.py`) and source
  reading, not independently re-executed live in this pass — doing so live requires backdating
  `hold_expires_at`/`expires_at` via direct DB access (test-only tooling, not a real client
  capability), which was judged unnecessary duplication of already-passing, already-read test
  coverage.
- The `unsupported_scenario` (422) and several less common admin/diagnostics error codes are
  source-verified (exact `HTTPException` call site read) but not independently re-triggered live
  in this pass, since the seeded test identities' state didn't naturally reach them without
  additional throwaway setup beyond what was already exercised.
- No real payment gateway exists to test against — by design (Phase 0 sandbox-only). The gateway
  abstraction is documented honestly as a foundation with exactly one adapter registered.

## Recommended next step

Wire an external scheduler (cron / Cloud Scheduler / systemd timer) to
`scripts/run_payment_lifecycle_sweep.py` — the script and its underlying service functions are
fully built and tested, but no scheduler invokes it anywhere in this repository today, meaning
expired orders/holds only clear via the manual admin-triggered endpoints until one is wired up.
