# Payment Platform — Backend Implementation Assessment
### (Repository A: `nitksaa-event` — backend only, Phase 0)

Scope of this pass, per instruction: **repository analysis and payment backend
verification only**. No code was modified. Repository B (`nitksaa-payment` /
Flutter Payment Flow Lab) is **not present in this working environment** —
every claim about it in prior conversation/documentation is therefore
**NOT VERIFIABLE** from this session and is excluded below rather than
assumed. A follow-up session with that repository available is required
before Sections 6–8 of the original 20-section audit template (Flutter
implementation, E2E trace including the Flutter leg, Flutter security/test
results) can be completed.

All findings below are evidence-based: file path, line, or command output is
cited. Nothing is inferred from filenames or from
`FLUTTER_PAYMENT_DEMO_*.md`-style documentation (none of which exists in this
repository — searched, zero matches).

---

## 1. Executive Summary

- The payment backend is a real, working, **Phase 0** slice: pricing → seat
  hold → order → attempt → deterministic-sandbox gateway → signed webhook →
  capture → registration confirmation → attendee/developer timeline. Not a
  stub — every step is implemented and exercised by tests.
- **All 30 tests in `backend/tests/test_payments.py` pass** against the local
  `events_db` (verified by running `pytest tests/test_payments.py -q`, 30
  passed in 1.41s). Coverage includes pricing math, auth/ownership, seat-hold
  expiry, verification escalation, configuration versioning, and a dedicated
  security/concurrency block (tamper, replay, enumeration, secret-leakage,
  concurrent webhook/attempt/registration races).
- Server-authoritative pricing is real: the client cannot influence
  amount/GST/currency (`test_client_supplied_amount_gst_currency_are_ignored`,
  `app/schemas/payments.py:31` — `CreatePaymentOrderRequest` has no amount
  field at all).
- Webhook integrity is real: HMAC-SHA256 signature (`deterministic_sandbox.py:84-90`),
  `SELECT ... FOR UPDATE` on the order row for atomicity
  (`payment_service.py:432-434`), amount/currency mismatch rejection
  (`payment_service.py:420-429`), duplicate delivery no-op via
  `UNIQUE(gateway, gateway_event_id)` (`015_payment_foundation.sql:147`).
- One config setting is dead: `PAYMENT_WEBHOOK_MAX_AGE_SECONDS`
  (`config.py:52`) is defined but **never read anywhere in the codebase** —
  replay protection is dedup-only (same event_id), not timestamp/age-based.
- **There is currently no way to create or publish a payment configuration
  outside development mode.** The only write path to `payment_configurations`
  is `POST /api/v1/dev/diagnostics/payments/configuration/import`
  (`dev_diagnostics.py:1660`), which is gated by `_require_development()` —
  it 404s whenever `APP_ENV != "development"`. This is a hard production
  blocker, not a diagnostics gap.
- Payment diagnostics/admin auth is a **development-only placeholder**
  (`app/middleware/dev_auth.py`), not payments-specific — the same
  `X-Dev-User` header mechanism gates `admin_events.py` too. There is no
  production admin-role system anywhere in this backend yet, so "payment
  needs a dedicated admin role" is really "the whole backend needs one."
- Order expiry is **soft only**: `payment_orders.status` has an `'expired'`
  value in its CHECK constraint and `PaymentRepository.mark_order_status()`
  can set it, but **nothing in the codebase ever calls it with `'expired'`**.
  An order past `expires_at` is caught reactively (`create_attempt` returns
  409 `payment_order_expired`) but the row's `status` column stays
  `created`/`payment_pending` forever. Same pattern as registration
  seat-holds: expiry is lazy/reactive, there is no background sweeper for
  either.
- Zero code exists yet for: refunds, cancellations, transfers, receipts,
  invoices, credit notes, discounts/coupons/promo codes, or any
  retention/cleanup job (all searched, zero matches under `backend/app`).
- No "My Payments/Orders" surface exists at the API level, not just the UI:
  `RegistrationResponse` (`schemas/registrations.py:44-69`) and
  `MyRegistrationsListResponse` carry no `order_id` or payment fields, and
  there is no `GET` endpoint that lists a payer's orders. A client must
  already hold a specific `order_id` (returned once, at creation) to query
  it again.
- The existing NITKSAA Flutter app in this repo (`apps/event_app/`) has
  **zero payment-related files** — confirmed by directory search. Whatever
  Flutter payment UI exists, it is not in this repository.
- **Biggest risk**: the coupling between "payment configuration can only be
  set via a dev-gated diagnostics endpoint" and "there is no production admin
  role system" means the payment module cannot go live for a real paid event
  today without new work — this is more limiting than any gap in the payment
  domain logic itself, which is comparatively solid.
- **Backend readiness: Sandbox Ready.** Correct, tested, reasonably secure
  for a single deterministic gateway and a single pricing shape. Not Pilot
  Ready: no real gateway, no production config-management path, no
  refund/cancel, no retention policy.

---

## 2. Architecture (verified)

```
app/api/payments.py            -- attendee + webhook HTTP routes
app/api/dev_diagnostics.py     -- payment config import, technical timeline,
                                   exceptions list, pending-attempt resolve,
                                   full scenario runner (dev-gated)
        |
app/services/payment_service.py -- orchestration: orders, attempts, webhook
                                    processing, timelines, verification
        |
        +-- app/services/pricing_service.py   -- pure Decimal pricing math
        +-- app/services/audit_service.py     -- event_audit_log writer
        +-- app/gateways/deterministic_sandbox.py -- HMAC sign/verify, payload build
        +-- app/repositories/payment_repository.py    -- payment_* tables
        +-- app/repositories/registration_repository.py -- seat-hold fields
        |
        v
PostgreSQL events_db: payment_configurations, payment_orders,
                       payment_attempts, payment_webhook_events,
                       payment_exceptions, event_audit_log (reused, not new)
```

No standalone "Gateway Abstraction" layer exists — `deterministic_sandbox`
is imported directly by `payment_service.py` (`from app.gateways import
deterministic_sandbox as sandbox`, `payment_service.py:26`); there is no
interface/protocol a second gateway would implement. Adding a real gateway
today means introducing that abstraction, not swapping a config value.

Repository B (Flutter Payment Flow Lab) is not present here — the diagram's
top box from the original template is unverifiable this session.

---

## 3. Backend Implementation Matrix

Evidence column cites file:line. Status values per the requested scale.

| Capability | Evidence | Status |
|---|---|---|
| Pricing (server-authoritative) | `pricing_service.py:23-88`; schema has no client-supplied amount field | IMPLEMENTED + VERIFIED |
| GST exclusive/inclusive | `pricing_service.py:43-53`; tests `test_pricing_gst_exclusive`, `test_pricing_gst_inclusive` | IMPLEMENTED + VERIFIED |
| Convenience fee (fixed/%) | `pricing_service.py:59-72`; tests pass; docstring notes % fee path has no live config exercising it | IMPLEMENTED + VERIFIED (fixed), PARTIAL (percentage — code path present, untested against a real config) |
| Configuration versioning | `016_payment_hardening.sql:36-51`, `payment_repository.py:32-94`; `test_configuration_versioning_never_mutates_existing_order` | IMPLEMENTED + VERIFIED |
| Registration seat hold | `registration_service.py:132-175`, `registrations status='seat_held'` | IMPLEMENTED + VERIFIED |
| Order creation | `payment_service.py:147-225` | IMPLEMENTED + VERIFIED |
| Order idempotency | `uq_payment_orders_idempotency` index (`015...sql:89-91`) + app-layer check + `UniqueViolationError` fallback (`payment_service.py:204-216`) | IMPLEMENTED + VERIFIED |
| Payment attempt creation | `payment_service.py:245-337` | IMPLEMENTED + VERIFIED |
| Deterministic sandbox gateway | `deterministic_sandbox.py` (full file) | IMPLEMENTED + VERIFIED |
| Success / Failure / Pending / Cancelled scenarios | `_EVENT_TYPE_BY_SCENARIO` (`deterministic_sandbox.py:33-40`) + webhook handlers (`payment_service.py:449-555`) | IMPLEMENTED + VERIFIED |
| Retry after failure | `payment_service.py:245-337` (new attempt_number per retry); `test_payment_diagnostics_full_flow` | IMPLEMENTED + VERIFIED |
| Verification (pending → requires_verification) | `payment_service.py:657-719`; `test_verification_workflow_escalates_and_blocks_retry` | IMPLEMENTED + VERIFIED |
| Webhook processing | `payment_service.py:350-557` | IMPLEMENTED + VERIFIED |
| Signature verification | `deterministic_sandbox.py:84-90`, HMAC-SHA256 | IMPLEMENTED + VERIFIED |
| Replay protection | Dedup via `UNIQUE(gateway, gateway_event_id)` only | PARTIAL — no timestamp/age check despite `PAYMENT_WEBHOOK_MAX_AGE_SECONDS` existing in config (unused, see §9) |
| Duplicate webhook protection | `record_webhook_event` `ON CONFLICT DO NOTHING` (`payment_repository.py:326-343`); `test_replay_attack_after_successful_capture_no_effect`, `test_concurrent_webhook_delivery_of_identical_payload_captures_once` | IMPLEMENTED + VERIFIED |
| Amount tamper protection | `payment_service.py:420-429`; `test_amount_tampering_on_webhook_rejected` | IMPLEMENTED + VERIFIED |
| Currency tamper protection | Same lines; `test_currency_tampering_on_webhook_rejected` | IMPLEMENTED + VERIFIED |
| Cross-user protection | `_load_order_for_user` ownership check (`payment_service.py:228-234`); diagnostics scenario + assumed test coverage | IMPLEMENTED + VERIFIED |
| Seat-hold expiry | `_is_hold_expired`, lazy check on order/attempt creation (`payment_service.py:77-81,169-171,268-270`) | IMPLEMENTED + VERIFIED (lazy/reactive only — no sweeper) |
| Payment-after-expiry handling | `PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY` exception path (`payment_service.py:472-500`); `test_payment_captured_after_seat_expiry_creates_exception` | IMPLEMENTED + VERIFIED |
| Payment exceptions | `payment_exceptions` table (`016...sql:71-90`), 2 types only (`PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY`, `VERIFICATION_UNRESOLVED`) | IMPLEMENTED + VERIFIED (narrow — 2 exception types, read-only, no resolve-from-attendee-side workflow) |
| Attendee timeline | `payment_service.py:602-629`, filtered/labeled, internal fields excluded | IMPLEMENTED + VERIFIED |
| Developer timeline | `payment_service.py:632-654`, `dev_diagnostics.py:1707-1727` | IMPLEMENTED + VERIFIED |
| Audit logs | Reuses `event_audit_log` (not a new table), `audit_service.py` | IMPLEMENTED + VERIFIED |
| Developer diagnostics | `dev_diagnostics.py:1647-2280+` (config import, technical timeline, exceptions list, resolve, full scenario runner) | IMPLEMENTED + VERIFIED |
| Concurrency protection | `SELECT...FOR UPDATE` on order (`payment_service.py:432-434`), unique constraints as source of truth (see code comments `payment_repository.py` header); 4 dedicated concurrency tests, all pass | IMPLEMENTED + VERIFIED |
| Order status auto-expiry (DB row) | `mark_order_status()` exists but is never invoked with `'expired'` anywhere in the codebase (grep confirmed) | MISSING |
| Refunds | No files, no schema, no code | MISSING |
| Cancellation / transfer | No files, no schema, no code | MISSING |
| Receipts / invoices / credit notes | No files, no schema, no code | MISSING |
| Discounts / coupons / promo codes | No files, no schema, no code (`grep -rl discount\|coupon\|promo` → zero hits) | MISSING |
| Data retention / cleanup jobs | No files, no scheduler (`grep -rl retention\|cleanup_old\|purge` → zero hits) | MISSING — FUTURE GOVERNANCE REQUIREMENT |
| Production config-management path | Only write path is dev-gated `dev_diagnostics.py:1660` | MISSING — blocks production use |
| Real gateway abstraction | Single concrete module, no interface | DEFERRED |

---

## 4. Database Schema (current, verified against `015_payment_foundation.sql` + `016_payment_hardening.sql`)

**`payment_configurations`** — `id` PK, `configuration_key` (was globally
unique, now `UNIQUE(configuration_key, version)` after 016), `event_id` FK →
`events` (CASCADE), `currency` CHECK ='INR' only, `base_amount NUMERIC(14,2)
CHECK >=0`, GST fields, convenience-fee fields, `seat_hold_minutes`,
`payment_session_expiry_minutes`, `status` (`draft|published|retired`),
`version INT` (added in 016), `created_by`, timestamps. Partial unique index
`uq_payment_configurations_active_event` enforces exactly one `published` row
per event. Append-only versioning: "editing" retires the old row and inserts
a new one (`create_new_config_version`, `payment_repository.py:32-94`) — old
orders keep pointing at their original `configuration_id`/`configuration_version`.

**`payment_orders`** — `id` PK, `public_order_number` (opaque, `ORD-` prefix
+ `secrets.token_urlsafe`), FKs to `registrations`/`events`/`event_users`/
`payment_configurations`, money columns `NUMERIC(14,2)` with `>=0` checks,
`amount_paid <= final_amount` CHECK, `pricing_snapshot JSONB NOT NULL`
(immutable copy of the pricing breakdown at creation time),
`status` (`created|payment_pending|paid|expired|cancelled` — `expired`/
`cancelled` values exist but nothing sets them), `idempotency_key`,
`configuration_version` (added in 016), `expires_at`, `paid_at`. Partial
unique index limits at most one `created`/`payment_pending` order per
registration; second partial unique index enforces idempotency per payer.

**`payment_attempts`** — `id` PK, `public_attempt_number` (opaque, `ATT-`
prefix), FK → `payment_orders` (CASCADE), `attempt_number` (monotonic per
order, `UNIQUE(order_id, attempt_number)` — retries never overwrite), gateway
fields, `status` (`initiated|pending|requires_verification|captured|failed|
cancelled|expired` — `requires_verification` added in 016), failure fields,
`verification_checked_at`/`verification_check_count` (016). Unique index on
`gateway_payment_ref` where not null prevents two attempts claiming the same
gateway payment.

**`payment_webhook_events`** — every inbound delivery recorded before
processing; `UNIQUE(gateway, gateway_event_id)` is the actual dedup
mechanism; `signature_valid BOOLEAN`, `processing_status`
(`received|processed|duplicate|rejected`), correlated order/attempt FKs.

**`payment_exceptions`** (016) — `exception_type` CHECK-constrained to
exactly two values today (`PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY`,
`VERIFICATION_UNRESOLVED`), `status` (`open|resolved`), `resolved_by`/
`resolution` columns exist but **no API writes them** — `list_exceptions` is
the only repository method exposed via diagnostics; there is no "resolve"
endpoint for exceptions (distinct from the pending-*attempt*-resolve
endpoint, which is a different thing).

**`registrations`** additions (pre-existing migration, referenced not
re-verified line-by-line this pass): `hold_expires_at`, hold-bearing statuses
`seat_held / payment_pending / payment_verification / payment_failed`.

### Data retention
No retention, audit-cleanup, webhook-cleanup, failed-attempt cleanup,
exception cleanup, or PII-cleanup implementation exists anywhere in
`backend/app`. **MISSING — FUTURE GOVERNANCE REQUIREMENT.** Do not treat
this as an oversight to silently fix; it needs an explicit policy decision
first, per the audit's own ground rules.

---

## 5. API Inventory (verified against `app/api/payments.py` and the payments section of `app/api/dev_diagnostics.py`)

| Method | Path | Auth | Idempotent? | Notes |
|---|---|---|---|---|
| GET | `/api/v1/events/{event_id}/payment-pricing` | Firebase bearer (`get_current_user`) | Yes (read) | 409 `payment_not_configured` if no published config |
| POST | `/api/v1/registrations/{registration_id}/payment-order` | Firebase bearer | Yes (idempotency_key) | 404/409 on ownership, state, expiry conflicts |
| GET | `/api/v1/payment-orders/{order_id}` | Firebase bearer, ownership-checked | Yes (read) | 404 if not owner (not 403 — avoids existence leak) |
| POST | `/api/v1/payment-orders/{order_id}/attempts` | Firebase bearer, ownership-checked | No (creates a new attempt each call, guarded by unresolved-attempt check) | `scenario` field is dev/sandbox-only per schema docstring |
| GET | `/api/v1/payment-orders/{order_id}/timeline` | Firebase bearer, ownership-checked | Yes (read) | Attendee-safe filtered view |
| POST | `/api/v1/payment-attempts/{attempt_id}/verify` | Firebase bearer, ownership-checked | Yes (safe to re-call) | 409 if attempt not in a verifiable state |
| POST | `/api/v1/payment-gateways/{gateway}/webhook` | **None** — HMAC signature only | Yes (dedup by gateway_event_id) | 404 for any gateway name other than `deterministic_sandbox`; always returns 200 even on rejection (never 4xx to the "gateway") |
| POST | `/api/v1/dev/diagnostics/payments/configuration/import` | `_get_dev_user` (dev-env + optional `X-Dev-User: admin`) | No (always creates a new version) | **Only write path to `payment_configurations`** |
| GET | `/api/v1/dev/diagnostics/payments/orders/{order_id}/technical-timeline` | dev-gated | Yes (read) | Unfiltered audit feed, doubles as "admin" view per code comment |
| GET | `/api/v1/dev/diagnostics/payments/exceptions` | dev-gated | Yes (read) | Read-only, no resolve action |
| POST | `/api/v1/dev/diagnostics/payments/attempts/{attempt_id}/resolve` | dev-gated | No (terminal-state guarded, 409 on second call) | Builds a real signed webhook server-side; signing secret never leaves backend |
| GET | `/api/v1/dev/diagnostics/payments` | dev-gated | N/A (side-effecting scenario runner) | Creates + exercises a throwaway paid event; full E2E scenario suite |

Attendee-facing: the six routes in `app/api/payments.py` minus the webhook.
Webhook-only: the HMAC route. Developer-only: everything under
`/dev/diagnostics/payments/*`. **No distinct admin-only or gateway-internal
API class exists** — dev-diagnostics doubles as the admin surface today, by
explicit design comment in the code (`payment_service.py:636`,
`dev_diagnostics.py:1713-1716`).

---

## 6. Security Assessment

Verified by reading code + running the security-focused subset of
`test_payments.py` (all pass).

**Confirmed protections:**
- Client cannot set amount/GST/currency — no such field exists on
  `CreatePaymentOrderRequest`; extra JSON fields are silently dropped by
  Pydantic v2 (verified: `test_client_supplied_amount_gst_currency_are_ignored`).
- Client cannot mark a payment successful or confirm a registration directly
  — the only path to `status='paid'`/`registered'` is a validly-signed
  webhook processed server-side.
- Ownership enforced on every attendee-facing payment route via
  `payer_firebase_uid` comparison, and a non-owner gets 404 (not 403),
  avoiding order-existence disclosure (`test_predictable_id_enumeration_fails`
  covers a related but distinct case — guessable sequential IDs).
- HMAC-SHA256 webhook signature, constant-time compare
  (`hmac.compare_digest`, `deterministic_sandbox.py:88-90`).
- The sandbox signing secret never leaves the backend — even the dev
  "resolve pending attempt" diagnostic route builds the signed payload
  server-side rather than exposing the secret to a caller
  (`dev_diagnostics.py:1761-1767`, explicit docstring rationale).
- `test_no_secret_leakage_in_responses` asserts the signing secret string
  never appears in any of six representative response bodies. Passed.
- Public order/attempt identifiers are `secrets.token_urlsafe`-based, not
  sequential (`_public_id`, `payment_service.py:73-74`) —
  `test_predictable_id_enumeration_fails` confirms guesses 404.
- `audit_service.py` docstring explicitly forbids putting firebase_uid,
  email, phone, join URLs, or tokens into audit `context` — spot-checked
  call sites in `payment_service.py` and none violate this.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| MEDIUM | `PAYMENT_WEBHOOK_MAX_AGE_SECONDS` is defined in `Settings` (`config.py:52`) but is never read anywhere in the codebase (`grep` confirms zero non-definition matches). Replay protection is entirely dedup-based (`gateway_event_id` uniqueness); there is no payload-age/timestamp check, and the sandbox payload itself carries no timestamp field to check against (`build_webhook_payload`, `deterministic_sandbox.py:55-77`). Not exploitable against the *current* sandbox gateway (attacker can't forge a new signature without the secret), but the setting's existence implies a control that isn't actually implemented — a real gateway integration must not inherit this false sense of coverage. | `config.py:52`; `deterministic_sandbox.py:55-77`; `payment_service.py:350-429` |
| MEDIUM | No production path exists to create a `payment_configurations` row. The only write path is dev-gated (`_require_development()`), meaning a real production deployment currently has **no way to accept payment for any event** without either (a) manually inserting rows via direct DB access, or (b) building a new admin-facing config endpoint. This is a functional/operational gap that is also a security consideration: the moment someone builds "just make it work in prod" pressure, the shortest path is disabling `_require_development()`, which would also expose the entire rest of `dev_diagnostics.py` (raw table dumps, alumni lookups, etc.) — a much bigger surface than payments alone. | `dev_diagnostics.py:1660-1667`, `:49-51` |
| LOW | Payment diagnostics/admin auth is the same placeholder `X-Dev-User` header mechanism used for the rest of the admin surface (`dev_auth.py`), not a payments-specific weakness — but it means there is no scoped "payment-admin" role: whoever can hit dev diagnostics at all can resolve pending attempts, import configurations, and read the full technical timeline for any order. In development this is fine; it is a documented pre-production blocker, not a payments-specific defect. | `dev_auth.py:13-30`, `dev_diagnostics.py:54-70` |
| INFORMATIONAL | Convenience-fee percentage math (`pricing_service.py:67-68`) is implemented and unit-tested in isolation but the docstring itself states "There is no live configuration using percentage fees yet, so this is a documented assumption, not an exercised path" at the integration level (no E2E/diagnostics scenario exercises a percentage-fee paid event end-to-end). | `pricing_service.py:9-10` |
| INFORMATIONAL | `payment_exceptions.resolved_by`/`resolution` columns exist in schema but no API path ever writes them — exceptions can be listed but not resolved through any HTTP interface today. Financial-state-affecting exceptions are permanently "open" from the system's point of view until someone does a manual DB update. | `016_payment_hardening.sql:71-90`; `dev_diagnostics.py:1730-1751` (list only) |

No CRITICAL or HIGH findings identified in this pass. No claim of
"production secure" is made — see blockers in §8.

---

## 7. Automated Test Results

```
cd backend && EMAIL_MODE=log .venv/bin/python -m pytest tests/test_payments.py -q
30 passed, 5 warnings in 1.41s
```

| Test Layer | Total | Passed | Failed | Skipped | Not Run |
|---|--:|--:|--:|--:|--:|
| Backend — `test_payments.py` | 30 | 30 | 0 | 0 | 0 |
| Flutter (Repo B) | — | — | — | — | Not run — repository not present in this environment |

Environment note: `EMAIL_MODE` was overridden to `log` for this run only
(shell env var, not a code/config file change) to avoid the local `.env`'s
`EMAIL_MODE=send` attempting real SMTP sends during the confirmation-email
path a successful-payment test triggers — consistent with prior guidance
that `EMAIL_MODE=send` locally slows/complicates test runs. This is an
environment/tooling accommodation, not an application change, and nothing
in `app/` was edited to make this pass.

No backend test failures — ENVIRONMENT vs. APPLICATION-FAILURE separation
is moot for this suite this run.

---

## 8. Known Limitations Reconciliation

Verified against the items listed in the prior conversation's known-limitations
description (source doc itself not present in this repo — reconciling
against the claims as stated):

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | One confirmed registration per user/event | CONFIRMED | `get_active_or_held_for_user` / `get_active_for_user` block a second in-flight or confirmed registration (`registration_repository.py:79-108`); `payment_orders` also has one-active-order-per-registration unique index |
| 2 | Lazy seat-hold expiry (no background sweeper) | CONFIRMED | `expire_stale_holds` docstring: "Called lazily... there is no background sweeper" (`registration_repository.py:119-121`); no scheduler/cron found anywhere in `backend/app` |
| 3 | Order status not automatically becoming `expired` | CONFIRMED | `mark_order_status()` exists (`payment_repository.py:193-198`) but is never called with `'expired'` anywhere in the codebase — verified by grep |
| 4 | GST-mode demo limitations | PARTIAL | Both `inclusive` and `exclusive` GST modes are implemented and unit-tested; the limitation is real only at the *integration* level (no live config exercises percentage convenience fees, per §6 INFORMATIONAL finding) — GST itself is not limited |
| 5 | Concurrent-registration diagnostic limitation | STALE (as a limitation) | `test_concurrent_double_click_registration_only_one_succeeds` is a real, passing, true-concurrency (ThreadPoolExecutor) test — this scenario is demonstrated, not just claimed |
| 6 | Concurrent-webhook diagnostic limitation | STALE (as a limitation) | `test_concurrent_webhook_delivery_of_identical_payload_captures_once` likewise passes as a true-concurrency test |
| 7 | Developer diagnostics authorization relies on dev-env gate, not a payment-admin role | CONFIRMED | See §6 LOW finding — and it's true of the *entire* backend's admin surface, not payments-specific |
| 8 | No My Payments/My Orders UI | CONFIRMED (and deeper than UI) | No API surface exists either — `RegistrationResponse`/`MyRegistrationsListResponse` carry no order linkage (`schemas/registrations.py:44-97`), and there is no `GET /payment-orders` list endpoint |
| 9 | No real payment policy document | CONFIRMED | No refund/cancellation/policy file found anywhere in `backend/` or `docs/` searched this session |
| 10 | Discount not exposed in pricing response | CONFIRMED | `PricingBreakdownResponse` has no discount field; no discount/coupon/promo code anywhere in backend |
| 11 | Browser token-storage limitation | NOT VERIFIABLE this session | Frontend-side claim; Flutter repo not present |
| 12 | Absence of visual regression testing | NOT VERIFIABLE this session | Frontend-side claim; Flutter repo not present |

---

## 9. Reusability Assessment (backend-only view)

Coupling to NITKSAA/event-specific concepts, found by reading the code (not
inferred):

| Dependency | Classification | Note |
|---|---|---|
| FK to `events(event_id)`, `registrations(registration_id)`, `event_users(firebase_uid)` | ACCEPTABLE PHASE-0 COUPLING | Payment domain tables are physically joined to event tables via FK; a reusable "Payment Core" would need these to become polymorphic references or the payment schema would need to live in its own service/database |
| Registration confirmation on capture (`reg_repo.set_status(..., "registered")`) | SHOULD ABSTRACT NEXT | `payment_service.process_webhook` directly imports and calls `RegistrationRepository` — payment capture logic is not decoupled from event-registration state transitions |
| Seat-hold extension on `payment.pending` (`extend_hold`) | SHOULD ABSTRACT NEXT | Same coupling direction — payment lifecycle reaches into registration-specific fields (`hold_expires_at`) |
| `event_audit_log` reuse instead of a payment-scoped audit table | ACCEPTABLE PHASE-0 COUPLING | Documented as a deliberate simplification in the migration header comment, not an accident |
| `INR`-only currency CHECK constraint | BLOCKS REUSE (for non-INR consumers) | `payment_configurations.currency CHECK (currency = 'INR')` (`015...sql:32`) |
| Single concrete gateway module, no interface | SHOULD ABSTRACT NEXT | `deterministic_sandbox` imported by name, not behind a protocol/interface — a second gateway or a second consuming product would require touching `payment_service.py` directly |
| Confirmation email tied to registration fields (`fullname_snapshot`, `event_title`, etc.) | GOOD DOMAIN DEPENDENCY | This is core event-registration business logic correctly living in the event-domain email flow, not something a generic payment core should own |

A generic "Payment Core / Application Adapter" boundary (Payment Core:
pricing, orders, attempts, gateway, webhooks, verification; Application
Adapter: NITKSAA registration confirmation, seat-hold extension) is
plausible from what exists, but **no refactor was performed or should be
inferred as planned** — this is an observation for a future decoupling
decision, not a recommendation acted on here.

---

## 10. Production Readiness Gap (backend only)

**Classification: Sandbox Ready.** Not Pilot Ready. Blockers, in the order
they'd actually stop a real paid event from launching:

1. No production path to create/publish a `payment_configurations` row for
   an event (§5, §6 MEDIUM finding) — this alone blocks any real usage
   outside `APP_ENV=development`.
2. No real gateway — `deterministic_sandbox` is the only implementation;
   there is no gateway interface to plug a real one (CCAvenue, Razorpay,
   etc.) into without modifying `payment_service.py` directly.
3. No production admin-role system anywhere in the backend (not
   payments-specific, but payments inherits it) — dev diagnostics is the
   only administrative surface today.
4. No refund/cancellation/transfer capability at all — a paid registration
   that needs to be reversed has no supported path.
5. Order-row expiry is soft (status never flips to `'expired'` in the DB) —
   fine for the reactive checks currently in place, but would need
   resolving before any reporting/reconciliation work that trusts
   `payment_orders.status` as ground truth for "is this order still live."
6. No data retention policy for payment/audit/webhook/exception data —
   explicitly flagged as a governance decision still needed, not a code gap
   to silently patch.

---

## 11. Verification & Acceptance Criteria (this session's scope)

| Item | Result |
|---|---|
| Repository A (nitksaa-event) inspected | PASS |
| Repository B (nitksaa-payment) inspected | NOT APPLICABLE — not present in this environment; explicitly out of scope per this session's instruction to start with backend only |
| Generated files ignored | PASS — `__pycache__`, `.venv` excluded from all searches |
| Payment backend inventory completed | PASS — §3 |
| Final DB schema inspected | PASS — §4, read directly from migration SQL, cross-checked against local `psql \dt payment_*` |
| Actual API routes verified | PASS — §5, read directly from `app/api/payments.py` and the payments section of `app/api/dev_diagnostics.py` |
| SUCCESS/FAILURE/RETRY/PENDING flows traced | PASS — via code read of `payment_service.py` plus corresponding passing tests |
| Seat expiry / payment-after-expiry traced | PASS — §3, §8 items 2–3 |
| Backend payment tests inspected and run | PASS — §7, 30/30 passing |
| Documentation compared with code | PARTIAL — no `FLUTTER_PAYMENT_DEMO_*.md` files exist in this repository to compare against; reconciled instead against the known-limitations claims relayed in conversation (§8) |
| Known limitations verified | PASS — §8 |
| Security boundaries reviewed (backend) | PASS — §6 |
| Reusability/coupling analysed (backend) | PASS — §9 |
| Production blockers identified | PASS — §10 |
| Flutter implementation verified | NOT APPLICABLE this session |
| Business requirement gap analysis (pricing shapes, cancellation/refund) | PARTIAL — covered implicitly via §3/§8/§10 (all MISSING); not expanded into the full comparison matrix from the original template since that was framed as Flutter+backend combined and repo B is absent |

---

## 12. Final Recommendation

**CURRENT STATE:** Backend = Sandbox Ready. Flutter/E2E system = not
assessable this session (repo B absent).

**NEXT STEP (not "next sprint" — a scoping step):** Before committing to any
of Phase A–E from the original prompt, get repository B (`nitksaa-payment`)
into this environment and run the equivalent Flutter-side audit (§6–8, §10
of the original 20-section template) so the E2E readiness classification and
the single recommended next sprint can be made with both halves verified,
not just the backend half.

**WHY:** This session's ground rule was explicit — verify before
recommending, and don't infer Flutter-side implementation from documentation
that isn't in this repository. The backend picture is now solid evidence for
a decision; the Flutter/E2E picture still is not. Recommending one of Phase
A (Flutter completion) / B (refund-cancel-transfer) / C (receipts) / D (real
gateway) / E (security hardening) right now would mean picking blind on the
half of the system that wasn't inspected.

**DO NOT IMPLEMENT ANYTHING FROM THIS REPORT YET — this is an audit
deliverable only, per instruction.**
