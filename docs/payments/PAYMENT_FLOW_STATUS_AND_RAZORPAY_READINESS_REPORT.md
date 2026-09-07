# Payment Flow Status & Razorpay Readiness Report

**Project:** NITKSAA-EVENT (backend only)
**Date:** 2026-09-07
**Type:** Source-verified status + readiness audit. **No Razorpay code was written.** No implementation started.
**Scope note:** NITKSAA-PAYMENT (Flutter) was not inspected or modified. Admin event-creation / unexpected-signout issue is treated as CLOSED (confirmed working by user) and was not re-opened.

---

## 1. Executive Summary

The payment backend is a **gateway-neutral deterministic-sandbox implementation ("Phase 0")** that is architecturally ready for a real provider adapter. The domain layer (`payment_service.py`) talks only to the `PaymentGateway` interface via a server-controlled `GatewayRegistry`; it never imports or branches on a concrete provider. Adding Razorpay means writing one adapter class + one registry line + config/secrets + a real webhook route body — **core payment business logic does not need to change**.

- **Backend baseline:** `339 passed, 4 skipped` (full suite, `pytest -q`, 144s, `EMAIL_MODE=send` from `.env`).
- **Focused payment regression:** `100 passed, 0 failed` across the 7 payment suites. Re-verified a 15-test high-value subset (full flow, verification, captured-after-expiry, amount/currency tampering, replay, concurrency) — all green.
- **Live local verification:** register → seat hold → pricing snapshot → order → attempt → signed HMAC webhook → capture → registration confirmation → timeline was exercised end-to-end against a **real local Postgres `events_db`** through the ASGI app (not mocked). Tampering, replay, and 5-way concurrency paths executed live and were rejected/serialized correctly.
- **Server-authoritative money:** amount, currency (INR-locked), and success state are computed/decided server-side only. The client cannot supply or influence any of them; verified by live tampering tests.
- **Gateway foundation:** `PaymentGateway` ABC, `GatewayRegistry` (fail-closed, no default fallback), `DeterministicSandboxGateway` adapter, capability model (`CREATE_PAYMENT`, `VERIFY_WEBHOOK`, `PROCESS_WEBHOOK`, plus declared-but-unsupported `VERIFY_PAYMENT`, `QUERY_PAYMENT_STATUS`, `REFUND`, `QUERY_REFUND`). Capability gaps raise `GatewayCapabilityNotSupportedError`, never a fake success.

**Blockers for a Razorpay *Test Mode* integration today:**

1. **No hosted-checkout / redirect contract** in `GatewayInitiationResult` — today an adapter must return an immediate or delayed webhook. Razorpay needs a `checkout`/`order-id` field returned to the client. **SMALL CHANGE** (add optional field; deferred by design until a provider was chosen).
2. **No raw-body webhook signature path for a real provider** — the sandbox re-canonicalizes JSON (`json.dumps(sort_keys)`); Razorpay signs the **exact received bytes**. `process_webhook` already takes `raw_body: bytes`, and the route already reads `await request.body()`, so the plumbing exists — but the sandbox adapter's `verify_webhook` must not be the template. **SMALL CHANGE.**
3. **No external/guest frontend contract.** Every attendee payment endpoint requires a Firebase-JWT-backed `event_users` identity **and** registration requires an *active alumni* profile. There is no guest ownership model, no scoped capability token, no rate limiting, and CORS allows only `localhost:5173/5200`. **BLOCKER FOR DIRECT BROWSER INTEGRATION** from an iTelematics-hosted frontend with arbitrary users. (Not a blocker if the pilot runs inside the existing Firebase-authenticated app with seeded alumni identities.)
4. **No `query_payment_status` capability** (reconciliation / late-success recovery against the provider) — the sandbox cannot support it and it was left `BLOCKED` pending a provider. **MISSING** (needed for production robustness; a Test Mode happy-path demo can proceed without it).
5. **Secrets management for a real key/secret/webhook-secret** — only a single `PAYMENT_SANDBOX_SIGNING_SECRET` exists. Need `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` / `RAZORPAY_WEBHOOK_SECRET` + test/live separation. **SMALL CHANGE.**

None of the above require rewriting `PaymentService`, `PaymentRepository`, pricing, orders, attempts, verification, retry, webhook dedupe, freshness, expiry, RBAC, or the audit timeline.

---

## 2. Baseline

Reproduced this session (not copied from history):

| Run | Command | Result |
|---|---|---|
| Full backend suite | `python -m pytest -q` | **339 passed, 4 skipped**, 5 warnings, 144.17s |
| `test_payments.py` | `pytest -q tests/test_payments.py` | 31 passed |
| `test_payment_admin_config.py` | ″ | 14 passed |
| `test_payment_gateway_foundation.py` | ″ | 16 passed |
| `test_payment_lifecycle_expiry.py` | ″ | 8 passed |
| `test_payment_rbac.py` | ″ | 12 passed |
| `test_payment_scheduler.py` | ″ | 9 passed |
| `test_payment_webhook_freshness.py` | ″ | 10 passed |
| **Payment focused total** | | **100 passed, 0 failed** |
| High-value subset re-run | `pytest tests/test_payments.py -k "diagnostics_full_flow or latest_order_id or verification_workflow or captured_after_seat_expiry or amount_tampering or currency_tampering or replay_attack or concurrent_webhook or double_click_attempt or seat_hold_expiry or configuration_versioning or client_supplied_amount or predictable_id or no_secret_leakage"` | 15 passed |
| Live diagnostics endpoint | `GET /api/v1/dev/diagnostics/payments` (TestClient, real DB) | HTTP 200, `status:"ok"`, 3 scenarios PASS |

Notes:
- `EMAIL_MODE=send` in `backend/.env` makes the suite slow (~2.5 min) because real SMTP is attempted; behavior is otherwise unchanged.
- The 4 skips are all in `test_admin_rbac.py` (parametrized cases for `create_event` / `list_all_events`, which have no `event_id` to scope — `platform_admin`-only by design). Unrelated to payments; none are error/environment skips.
- The live diagnostics endpoint's ad-hoc sub-scenarios that failed did so with `403 alumni_not_found` — the endpoint mints throwaway alumni identities not present in the **remote** `alumni_db` that `.env`'s `DB_HOST`/`ALUMNI_DB_URL` currently point at. This is an environment/seed-data mismatch (see auto-memory `feedback_local_db_env_mismatch`), **not a payment-code defect**; the pytest suite uses pre-seeded identities (`TEST_ALUMNI_UID_001` …) and passes fully.

---

## 3. Current Architecture

```
Registration (registration_service.register_for_event)
  └─ alumni-only gate (user_type=='alumni' + active alumni profile)          [IMPLEMENTED]
  └─ FOR UPDATE on events row → capacity check                                [IMPLEMENTED]
  └─ free event   → status='registered', confirmation email                  [IMPLEMENTED]
  └─ paid event   → status='seat_held', hold_expires_at = now + seat_hold    [IMPLEMENTED]
        │
        ▼
Pricing (pricing_service.calculate_price)                                     [IMPLEMENTED]
  └─ server-authoritative, Decimal, INR only, GST inclusive/exclusive,
     fixed/percentage convenience fee, line items
        │
        ▼
Seat Hold (registrations.hold_expires_at + registration_holds migration 014) [IMPLEMENTED]
  └─ reactive expiry on next register; explicit sweep via lifecycle service
        │
        ▼
Payment Order (payment_service.create_order → payment_orders)                 [IMPLEMENTED]
  └─ pricing_snapshot frozen into the order (JSONB) + configuration_id/version
  └─ idempotency_key (unique per payer) + one-active-order-per-registration
     (partial unique index) — DB is source of truth, app check is fast path
  └─ expires_at = now + payment_session_expiry_minutes
        │
        ▼
Payment Attempt (payment_service.create_attempt → payment_attempts)          [IMPLEMENTED]
  └─ gateway = registry.get_active_gateway(settings)  (server config only)
  └─ retry = new attempt row (failed attempts never overwritten)
  └─ blocked while an attempt is initiated/pending/requires_verification
     (partial unique index uq_payment_attempts_unresolved_per_order, mig 020)
        │
        ▼
Gateway (app/gateways/*)                                                      [IMPLEMENTED — sandbox only]
  └─ PaymentGateway ABC / GatewayRegistry / DeterministicSandboxGateway
  └─ create_payment() → SignedWebhookDelivery | DelayedWebhookDelivery
  └─ real hosted-checkout redirect field: NOT IMPLEMENTED (deferred by design)
        │
        ▼
Webhook / Verification (payment_service.process_webhook)                      [IMPLEMENTED — sandbox semantics]
  └─ registry-validated gateway (path segment) → verify_webhook (HMAC)
  └─ record_webhook_event ON CONFLICT (gateway, gateway_event_id) → dedupe   [IMPLEMENTED]
  └─ freshness gate: issued_at signed, max_age 300s / future skew 30s        [IMPLEMENTED]
  └─ amount + currency match against the attempt                             [IMPLEMENTED]
  └─ SELECT ... FOR UPDATE on order row → single captured transition         [IMPLEMENTED]
  └─ verify_attempt(): re-read + escalate stuck 'pending' → 'requires_verification' + exception  [IMPLEMENTED]
  └─ query_payment_status() against provider: NOT IMPLEMENTED (capability BLOCKED, sandbox can't)
        │
        ▼
Capture (payment_repository.mark_order_paid / update_attempt_captured)       [IMPLEMENTED]
  └─ financial state preserved unconditionally
        │
        ▼
Registration Confirmation (reg_repo.set_status 'registered' + email)         [IMPLEMENTED]
  └─ idempotent (only if not already 'registered')
  └─ captured-after-seat-expiry → PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY exception, no silent reconfirm  [IMPLEMENTED]
        │
        ▼
Timeline (payment_service.get_timeline / get_developer_timeline)             [IMPLEMENTED]
  └─ attendee-safe labelled view (security events filtered, no raw IDs)
  └─ developer/"admin" timeline = full unfiltered feed (dev-diagnostics gated;
     no distinct payment-admin timeline role exists yet)                      [PARTIAL — no dedicated admin role]
        │
        ▼
Expiry / Recovery                                                            [IMPLEMENTED]
  └─ payment_lifecycle_service.expire_stale_payment_orders / _registration_holds
  └─ idempotent + concurrency-safe (single UPDATE...WHERE...RETURNING, NOT EXISTS guard)
  └─ entry point: scripts/run_payment_lifecycle_sweep.py (cron/ops script) + admin API
  └─ no long-running scheduler daemon (by design — cron the script/endpoint)  [PARTIAL by design]
  └─ refund / reconciliation / receipt / invoice: NOT IMPLEMENTED
```

### Component status

| Component | Source | Status |
|---|---|---|
| `PaymentService` | `app/services/payment_service.py` (791 loc) | IMPLEMENTED |
| `PaymentRepository` | `app/repositories/payment_repository.py` (553 loc) | IMPLEMENTED |
| `PricingService` | `app/services/pricing_service.py` | IMPLEMENTED |
| `RegistrationService` (payment coupling) | `app/services/registration_service.py` | IMPLEMENTED |
| `PaymentLifecycleService` | `app/services/payment_lifecycle_service.py` | IMPLEMENTED |
| `PaymentConfigService` (draft→validate→publish) | `app/services/payment_config_service.py` | IMPLEMENTED |
| `PaymentGateway` interface | `app/gateways/base.py` | IMPLEMENTED |
| `GatewayRegistry` | `app/gateways/registry.py` | IMPLEMENTED |
| `DeterministicSandboxGateway` | `app/gateways/deterministic_sandbox.py` | IMPLEMENTED |
| Attendee payment router | `app/api/payments.py` | IMPLEMENTED |
| Admin payment router | `app/api/admin_payments.py` | IMPLEMENTED |
| Payment RBAC | `app/middleware/admin_auth.py` + `payment_role_repository.py` | IMPLEMENTED |
| Payment schemas | `app/schemas/payments.py`, `app/schemas/payment_admin.py` | IMPLEMENTED |
| Migrations | `events_db/015`–`018`, `020` | IMPLEMENTED |
| Diagnostics | `app/api/dev_diagnostics.py` (`/payments*`) | IMPLEMENTED (dev-gated) |
| Lifecycle scheduler entry point | `scripts/run_payment_lifecycle_sweep.py` | IMPLEMENTED (script, not daemon) |
| Real gateway adapter | — | NOT IMPLEMENTED (by design) |
| Hosted-checkout/redirect contract | `GatewayInitiationResult` | NOT IMPLEMENTED (deferred) |
| `query_payment_status` / reconciliation | interface stub only | NOT IMPLEMENTED |
| Refund / receipt / GST invoice | interface stub only | NOT IMPLEMENTED |
| Guest / external-frontend ownership | — | NOT IMPLEMENTED |
| Rate limiting | — | NOT IMPLEMENTED |

---

## 4. Payment Flow Status Matrix

Backend = code path exists. Tests = automated coverage exists. Live Verified = executed this session end-to-end against local Postgres via the ASGI app (deterministic sandbox).

| Flow | Backend | Tests | Live Verified | Status | Notes |
|---|---|---|---|---|---|
| Free registration | ✅ | ✅ | ✅ (indirect via suite) | IMPLEMENTED | `status='registered'` + email immediately |
| Paid registration (seat hold) | ✅ | ✅ | ✅ | IMPLEMENTED | `status='seat_held'`, `hold_expires_at` set |
| Pricing snapshot | ✅ | ✅ (6 unit + integration) | ✅ | IMPLEMENTED | frozen into `payment_orders.pricing_snapshot` + `configuration_version` |
| Seat hold | ✅ | ✅ | ✅ | IMPLEMENTED | migration 014 + `hold_expires_at` |
| Payment order creation | ✅ | ✅ | ✅ | IMPLEMENTED | idempotency key + one-active-order index |
| Payment attempt creation | ✅ | ✅ | ✅ | IMPLEMENTED | new row per attempt |
| Sandbox success (capture) | ✅ | ✅ | ✅ | IMPLEMENTED | `SUCCESS` scenario → signed webhook → captured |
| Sandbox failure | ✅ | ✅ | ✅ | IMPLEMENTED | `FAILURE` → attempt `failed`, reg `payment_failed` |
| Pending | ✅ | ✅ | ✅ | IMPLEMENTED | `PENDING` → reg `payment_verification`, hold extended |
| Requires verification (escalation) | ✅ | ✅ (`verification_workflow`) | ✅ | IMPLEMENTED | stuck >30 min → `requires_verification` + `VERIFICATION_UNRESOLVED` exception |
| Retry after failure | ✅ | ✅ | ✅ | IMPLEMENTED | new attempt allowed while reg `payment_failed` |
| Retry blocked during verification | ✅ | ✅ | ✅ | IMPLEMENTED | `has_unresolved_attempt` + partial unique index |
| Duplicate registration | ✅ | ✅ (`no_hang`, `double_click`) | ✅ | IMPLEMENTED | returns promptly, no hang |
| Duplicate payment initiation (idempotency) | ✅ | ✅ | ✅ | IMPLEMENTED | same key → same order |
| Concurrent initiation | ✅ | ✅ (5-way order + 5-way attempt) | ✅ | IMPLEMENTED | DB unique indexes serialize; 409 not 500 |
| Webhook signature validation | ✅ | ✅ | ✅ | IMPLEMENTED | HMAC-SHA256; invalid → `rejected` |
| Webhook freshness / replay | ✅ | ✅ (10 tests) | ✅ | IMPLEMENTED | signed `issued_at`, stale/future/malformed/missing rejected; event-id dedupe |
| Captured confirmation | ✅ | ✅ | ✅ | IMPLEMENTED | reg → `registered`, confirmation email, idempotent |
| Captured-after-expiry | ✅ | ✅ | ✅ | IMPLEMENTED | funds preserved, `PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY`, no silent reconfirm |
| Order / hold expiry sweep | ✅ | ✅ (expiry + scheduler suites) | ✅ | IMPLEMENTED | idempotent, concurrency-safe, in-flight-attempt guard |
| Returning attendee | ✅ | ✅ | ✅ | IMPLEMENTED | `get_active_or_held_for_user`, seat re-use semantics |
| `latest_order_id` recovery | ✅ | ✅ (`latest_order_id_tracks…`) | ✅ | IMPLEMENTED | `RegistrationResponse.latest_order_id` from most recent order |
| Payment timeline (attendee) | ✅ | ✅ | ✅ | IMPLEMENTED | labelled, security events filtered |
| Admin timeline | ✅ (dev-diagnostics gated) | ✅ | ✅ | PARTIAL | no dedicated payment-admin role; = developer timeline |
| Admin payment config (draft→publish) | ✅ | ✅ (14 tests) | ✅ (via suite) | IMPLEMENTED | append-only versioning, retires prior published |
| Payment RBAC | ✅ | ✅ (12 tests) | ✅ | IMPLEMENTED | platform_admin / finance_operator / auditor / support + event_admin |
| Scheduler / lifecycle | ✅ (script) | ✅ (9 tests) | ✅ | PARTIAL | entry-point script + admin API; no daemon (design choice) |
| Payment exceptions | ✅ | ✅ | ✅ | IMPLEMENTED | `payment_exceptions` table; open/resolved; dedup guard. **No production resolution UI/API** (dev-diagnostics list only) |
| Refunds | ❌ (interface stub) | ❌ | ❌ | NOT IMPLEMENTED | `refund()` raises `GatewayCapabilityNotSupportedError` |
| Reconciliation / status refresh | ❌ (interface stub) | ❌ | ❌ | NOT IMPLEMENTED | `query_payment_status()` BLOCKED pending provider |
| Real payment gateway | ❌ | ❌ | ❌ | NOT IMPLEMENTED | by design — provider-neutral foundation only |

---

## 5. Payment API Inventory

### Attendee (require internal Firebase-JWT `event_users` identity; ownership by `payer_firebase_uid`)

| Method | Path | Auth | Ownership | Purpose | Status |
|---|---|---|---|---|---|
| GET | `/api/v1/events/{event_id}/payment-pricing` | `get_current_user` | none (event-scoped) | server-calculated pricing breakdown | IMPLEMENTED |
| POST | `/api/v1/registrations/{registration_id}/payment-order` | `get_current_user` | registration must belong to caller | create/return payment order (idempotent) | IMPLEMENTED |
| GET | `/api/v1/payment-orders/{order_id}` | `get_current_user` | `payer_firebase_uid == caller` | order status + safe message | IMPLEMENTED |
| POST | `/api/v1/payment-orders/{order_id}/attempts` | `get_current_user` | payer-owned order | create payment attempt (sandbox scenario) | IMPLEMENTED |
| GET | `/api/v1/payment-orders/{order_id}/timeline` | `get_current_user` | payer-owned order | attendee-safe labelled timeline | IMPLEMENTED |
| POST | `/api/v1/payment-attempts/{attempt_id}/verify` | `get_current_user` | payer-owned attempt | controlled status re-check / escalation | IMPLEMENTED |

### Registration (payment-coupled)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/v1/events/{event_id}/register` | `get_current_user` + alumni gate | seat hold (paid) or confirm (free) |
| GET | `/api/v1/events/{event_id}/my-registration` | `get_current_user` | includes `latest_order_id`, `hold_expires_at` |
| GET | `/api/v1/my/registrations` | `get_current_user` | list, includes `latest_order_id` |
| GET | `/api/v1/events/{event_id}/registration-eligibility` | `get_current_user` | `payment_required`, `ticket_price` |

### Webhook (unauthenticated by design; HMAC signature is the trust anchor)

| Method | Path | Auth | Purpose | Status |
|---|---|---|---|---|
| POST | `/api/v1/payment-gateways/{gateway}/webhook` | none — registry-validated `{gateway}` + `X-Sandbox-Signature` header + raw-body HMAC | inbound gateway callback | IMPLEMENTED (sandbox header/semantics) |

### Admin (`app/middleware/admin_auth.py`, real Firebase identity + DB/settings roles)

| Method | Path | Role | Purpose |
|---|---|---|---|
| POST | `/api/v1/admin/events/{event_id}/payment-configurations` | `require_event_admin` | create draft config |
| GET | `/api/v1/admin/events/{event_id}/payment-configurations` | `require_event_payment_read_access` | list history |
| GET | `/api/v1/admin/events/{event_id}/payment-configurations/{id}` | `require_event_payment_read_access` | get one |
| POST | `.../payment-configurations/{id}/validate` | `require_event_admin` | dry-run validation |
| POST | `.../payment-configurations/{id}/publish` | `require_event_admin` | publish (retires prior, syncs `events.ticket_price`) |
| POST | `/api/v1/admin/payment-roles` | `platform_admin` | grant platform role |
| POST | `/api/v1/admin/payment-roles/{grant_id}/revoke` | `platform_admin` | revoke |
| GET | `/api/v1/admin/payment-roles` | `platform_admin` / `auditor` | list active roles |
| POST | `/api/v1/admin/events/{event_id}/payment-admins` | `platform_admin` | grant event-scoped payment admin |
| POST | `/api/v1/admin/payments/lifecycle/expire-orders` | `platform_admin` | manual stale-order sweep |
| POST | `/api/v1/admin/payments/lifecycle/expire-registration-holds` | `platform_admin` | manual stale-hold sweep |
| GET | `/api/v1/admin/payments/gateway-config` | `platform_admin` / `finance_operator` / `auditor` / `support` | read-only registry view (no secrets) |

### Diagnostics (dev-env gated + `payment_diagnostics_enabled`)

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/dev/diagnostics/payments/configuration/import` | upsert published config + flip `events.is_free` |
| GET | `/api/v1/dev/diagnostics/payments/orders/{order_id}/technical-timeline` | full unfiltered timeline |
| GET | `/api/v1/dev/diagnostics/payments/exceptions` | list `payment_exceptions` |
| POST | `/api/v1/dev/diagnostics/payments/attempts/{attempt_id}/resolve` | resolve a live pending/verification attempt to SUCCESS/FAILURE (builds the signed delivery server-side) |
| GET | `/api/v1/dev/diagnostics/payments` | end-to-end sandbox scenario runner |

### Endpoints iTelematics / NITKSAA-PAYMENT would call

- **Read pricing:** `GET /events/{id}/payment-pricing`
- **Start payment:** `POST /registrations/{id}/payment-order` → `POST /payment-orders/{id}/attempts`
- **Poll / recover:** `GET /payment-orders/{id}`, `POST /payment-attempts/{id}/verify`, `GET /my/registrations` (`latest_order_id`)
- **Show history:** `GET /payment-orders/{id}/timeline`
- **Razorpay callback (server-to-server):** `POST /payment-gateways/razorpay/webhook` (new adapter)

All six attendee/registration calls today require a valid internal JWT minted from a verified Firebase token for an **active alumnus**.

---

## 6. Gateway Foundation Status

| Element | Status | Evidence |
|---|---|---|
| `PaymentGateway` interface | READY | `app/gateways/base.py` — ABC with `create_gateway_order_ref`, `create_payment`, `verify_webhook`, `parse_webhook` abstract; `verify_payment`, `query_payment_status`, `refund`, `query_refund` default to raise |
| `GatewayRegistry` | READY | `app/gateways/registry.py` — `get_active_gateway(settings)` from `payment_gateway_mode` env only; `get_enabled_gateway` fail-closed; **never falls back to a default** (test-verified) |
| Current adapters | sandbox only | `DeterministicSandboxGateway` |
| Provider capability model | READY | `GatewayCapability` enum + per-adapter `capabilities` frozenset; unsupported ops raise `GatewayCapabilityNotSupportedError` (test: "unsupported capability raises cleanly, not a fake response") |
| External order/reference storage | READY | `payment_attempts.gateway_order_ref` (correlation) + `gateway_payment_ref` (unique partial index). `gateway` column per attempt. `payment_webhook_events.gateway_event_id` unique per gateway |
| Webhook dispatch model | PARTIAL | `process_webhook(gateway, raw_body: bytes, signature)` + route reads raw body. Correlation via `gateway_order_ref`. **Immediate/delayed in-process delivery is sandbox-only**; a real provider posts over HTTP to the same route — supported, but `GatewayInitiationResult` has no redirect/checkout field yet |
| Query-status support | MISSING | `query_payment_status()` raises; documented `BLOCKED` until a real provider |
| Refund capability | MISSING | `refund()` / `query_refund()` raise; explicitly out of scope |
| Fail-closed behavior | READY | Unknown/disabled gateway → 503 on initiation, 404 on webhook; sandbox disabled in `APP_ENV=production` unless `PAYMENT_SANDBOX_ALLOW_IN_PRODUCTION=true` (test-verified both ways) |

**Can Razorpay be added as a new adapter without changing core payment business logic?**
**YES**, with two small, pre-identified interface extensions:
1. Add an optional `checkout` / `redirect` field to `GatewayInitiationResult` (deferred by design — "adding it now with no consumer would be speculative", per the sprint report) and have `create_attempt` return it when `initiation.immediate_webhook`/`delayed_webhook` are both absent.
2. Provide a real `verify_webhook` that HMACs the **raw received bytes** (Razorpay: `HMAC_SHA256(webhook_secret, raw_body)` compared to `X-Razorpay-Signature`) — do **not** reuse the sandbox's re-canonicalization.

Everything else — order creation, pricing snapshot, attempts, retry, dedupe, freshness, capture, confirmation, expiry, RBAC, audit — is provider-agnostic and untouched.

---

## 7. Razorpay Readiness Gap Analysis

| Item | Rating | Notes |
|---|---|---|
| Server-side order creation | SMALL CHANGE | `create_attempt` already server-side; add a Razorpay `orders.create` call inside the adapter's `create_payment`, store returned `razorpay_order_id` in `gateway_order_ref` |
| Amount minor-unit conversion (paise) | SMALL CHANGE | pricing is `Decimal` rupees; adapter must `int(amount * 100)`. Single spot, in the adapter |
| INR enforcement | READY | `currency = 'INR'` CHECK on config + order; `validate_configuration` rejects non-INR; webhook currency-match check |
| Gateway external order ID storage | READY | `payment_attempts.gateway_order_ref` |
| Gateway payment ID storage | READY | `payment_attempts.gateway_payment_ref` (unique partial index) |
| Checkout initiation response | MISSING → SMALL CHANGE | need `GatewayInitiationResult.checkout` field + `PaymentAttemptResponse` passthrough (`razorpay_order_id`, `key_id`, amount, currency) |
| Frontend-safe public key handling | SMALL CHANGE | expose `RAZORPAY_KEY_ID` only (never secret) via the attempt response; add to settings |
| Server-side signature verification (webhook) | SMALL CHANGE | new adapter `verify_webhook` over raw bytes with `RAZORPAY_WEBHOOK_SECRET`; plumbing (`raw_body: bytes`) already present |
| Raw-body webhook verification | READY (plumbing) / SMALL CHANGE (adapter) | route already does `await request.body()`; sandbox adapter re-serializes — real adapter must not |
| Webhook event dedupe | READY | `payment_webhook_events` unique `(gateway, gateway_event_id)`; map Razorpay `x-razorpay-event-id` / payload `id` |
| Provider event ID storage | READY | same table/column |
| Query payment status | MISSING | `query_payment_status()` unimplemented; needed for reconciliation & late-success recovery (Razorpay `payments.fetch`) |
| Pending / requires_verification mapping | READY | `NormalizedStatus.PAYMENT_PENDING` → `payment_verification` + hold extension + 30-min escalation already implemented; adapter maps `payment.authorized`/`order.paid`/`payment.failed` → normalized enum |
| Late success handling | PARTIAL | webhook capture-after-expiry path exists (`PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY`); no proactive `payments.fetch` reconciliation |
| Failure / retry | READY | `NormalizedStatus.PAYMENT_FAILED` → new-attempt retry, tested |
| Reconciliation / status refresh | MISSING | no scheduled reconcile job; would build on `query_payment_status` |
| Idempotency | READY | order idempotency key (unique per payer); attempt partial unique index; webhook event-id dedupe |
| Concurrency | READY | `FOR UPDATE` on order in webhook; partial unique indexes on orders/attempts/configs; 5-way tests |
| Secret management | SMALL CHANGE | only `PAYMENT_SANDBOX_SIGNING_SECRET` today; add `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` / `RAZORPAY_WEBHOOK_SECRET` to `Settings`; keep out of all responses (`gateway-config` already excludes secrets) |
| Test / live mode separation | SMALL CHANGE | add `RAZORPAY_MODE=test|live` (or infer from key prefix `rzp_test_`); registry can register `razorpay` once, mode from settings |
| CORS / external frontend contract | MISSING → BLOCKER (for direct browser) | `ALLOWED_ORIGINS` = `localhost:5173,5200` only; `allow_credentials=True`; dev regex allows any localhost port. No production/iTelematics origin |
| Guest / external ownership contract | MISSING → BLOCKER (for non-alumni external users) | see §8 |

---

## 8. External Frontend / iTelematics Readiness

**Intended:** iTelematics frontend → NITKSAA-EVENT backend → Razorpay.

**Current external-frontend contract: NOT SAFE for direct browser integration.**

| Check | Finding |
|---|---|
| Guest / no-login payment ownership | **None.** Every attendee payment endpoint depends on `get_current_user` → internal JWT → `event_users` row. Ownership is `payer_firebase_uid`. No anonymous/guest order concept |
| Firebase attendee dependency | **Hard.** Token must be a verified Firebase ID token for the configured project; `POST /api/v1/auth/firebase` exchanges it for the internal JWT |
| Alumni dependency | **Hard.** `register_for_event` returns `403 alumni_only` / `alumni_not_found` / `alumni_not_active` unless the caller maps to an **active** alumni profile. No seat hold → no order → no payment for non-alumni |
| External client identification | **None.** No API key, client credential, or integration principal for a server-to-server caller |
| CORS allowlist | `localhost:5173`, `localhost:5200` + `^http://(localhost|127\.0\.0\.1):\d+$` in dev. No HTTPS/production origin. `allow_credentials=True` |
| Public / opaque payment capability token | **None.** No scoped, expiring, single-order token mechanism exists |
| Rate limiting | **None.** No slowapi/limiter/throttle anywhere |
| Cross-user / IDOR protections | **Present** for the authenticated model: every order/attempt load checks `payer_firebase_uid == caller`; public IDs are opaque `secrets.token_urlsafe`; enumeration test passes; "no secret leakage" test passes |

**Classification: BLOCKER FOR DIRECT BROWSER INTEGRATION.**

### Recommendation: **Option B — iTelematics server-side BFF → NITKSAA-EVENT with an integration credential** (safer given current source).

Rationale:
- Ownership, IDOR protection, and audit are all built around a single authenticated principal (`firebase_uid`). A BFF preserves that model unchanged: iTelematics authenticates its own users, then calls NITKSAA-EVENT as a known integration identity (either a dedicated service `event_users`/role, or a new integration-credential check) — no new browser-facing trust surface, no CORS widening to a public origin, no new token lifecycle to secure.
- Option A (direct browser + scoped capability token) is cleaner long-term but requires **new, security-critical infrastructure that does not exist today**: token minting/rotation/expiry, per-order scoping, replay defense, rate limiting, and a public CORS origin. That is a sprint in itself and a larger attack surface for a ₹1 pilot.
- The existing Firebase-authenticated Flutter app (NITKSAA-PAYMENT) is already a working "first-party client" path; if the pilot can run there with seeded alumni identities, **no new contract is needed at all**.

Do **not** weaken the existing authenticated attendee APIs to accommodate an external frontend.

---

## 9. Guest Ownership Assessment

- **No guest ownership model exists.** There is no code path to create or pay a `payment_order` without an authenticated, alumni-linked `event_users` identity.
- Payment ownership = `payment_orders.payer_firebase_uid` (FK to `event_users`), enforced on every read/mutation.
- Public identifiers (`public_order_number`, `public_attempt_number`) are opaque and unguessable, but they are **not** bearer capabilities — they still require the owning JWT.
- For an external pilot with arbitrary testers, this is a **blocker** unless (a) testers are seeded as active alumni, or (b) a BFF calls on their behalf, or (c) a scoped capability-token feature is built (Option A).

---

## 10. ₹1 Pilot Readiness

**Goal:** a separate "Event Registration & Payment Pilot" — ₹1.00, INR, GST off, gateway `razorpay`, mode `test` — **without touching the existing NITKSAA Business Breakfast event (`event_id=392`) or its price.**

| Aspect | Finding |
|---|---|
| Separate event | **Safe.** Config is per-event (`payment_configurations.event_id`, one published row per event). Create a brand-new event via `POST /api/v1/admin/events` (+ publish), then a new published config via the admin draft→publish flow or the dev import endpoint |
| ₹1 amount | **Safe.** `base_amount` `NUMERIC(14,2)` `CHECK >= 0`; `1.00` is valid; `final_amount >= 0` allowed |
| GST off | **Safe.** `gst_enabled=false` (default); pricing yields `tax_amount=0.00` |
| Currency INR | **Enforced.** Only INR permitted |
| Gateway `razorpay` / mode `test` | **Not yet possible** — `payment_gateway_mode` is a single global env var and only `deterministic_sandbox` is registered. Per-event gateway selection does **not** exist. Enabling Razorpay switches it **globally** for every paid event, including `event_id=392` |
| Existing event isolation | Price/config isolation is fine; **gateway selection is not isolated**. Until Razorpay is implemented and (ideally) `event_id=392` has no live paying traffic, a global switch to `razorpay` is acceptable for a controlled pilot window, but note it is global |
| Non-alumni testers | **Blocker** — see §9. Use seeded alumni identities or a BFF |

**Smallest safe path to a pilot:**
1. Implement the `razorpay` adapter + settings + checkout-response field + raw-body webhook verify (the Razorpay sprint).
2. Create a **new** pilot event + its own published `payment_configurations` row (`base_amount=1.00`, `gst_enabled=false`).
3. Run the pilot in a window where `PAYMENT_GATEWAY_MODE=razorpay` (test keys) is acceptable globally, **or** add a small `payment_configurations.gateway` column + have `create_attempt` prefer the config's gateway over the global default (a contained, additive change — recommended if `event_id=392` must stay on sandbox simultaneously).
4. Use seeded alumni test identities (or a BFF) for testers.

---

## 11. Security Readiness

| Protection | Status | Evidence |
|---|---|---|
| Client cannot control authoritative amount | ✅ | `pricing_service` server-side; `create_attempt` uses `order["final_amount"]`; test `client_supplied_amount_gst_currency_are_ignored` |
| Client cannot control currency | ✅ | INR CHECK constraints; webhook currency-match; same test |
| Client cannot mark payment success | ✅ | success only via signed webhook through `process_webhook`; `verify_payment` (client-return) deliberately unsupported |
| Gateway secrets server-only | ✅ | secrets read inside adapter methods from `Settings`; never in any response; `gateway-config` endpoint explicitly excludes them; test `exposes_no_secrets` |
| Duplicate attempt protection | ✅ | `has_unresolved_attempt` + `uq_payment_attempts_unresolved_per_order` (mig 020); 5-way concurrency test |
| Webhook replay protection | ✅ | `payment_webhook_events` unique `(gateway, gateway_event_id)`; signed `issued_at` freshness (300s / 30s skew); 10 freshness tests incl. post-signing tamper |
| Cross-user access control | ✅ | `payer_firebase_uid == caller` on every order/attempt path; IDOR/enumeration tests |
| RBAC | ✅ | `admin_auth.py` — roles from verified JWT + DB/settings only, never from body/header/query; fabricated-role tests |
| Audit timeline | ✅ | every state transition emits to `event_audit_log`; attendee-safe vs developer views |
| Concurrency safety | ✅ | `FOR UPDATE` on order in webhook; partial unique indexes; UniqueViolation → 409 not 500 |

**Gaps:**
- **No rate limiting** on any endpoint (matters once an external/guest surface exists).
- **No production exception-resolution API** — `payment_exceptions` can be opened and listed (dev-diagnostics) but resolution has no authenticated admin route.
- **Webhook route trusts `X-Sandbox-Signature` header name** — a real provider uses a different header (`X-Razorpay-Signature`); the adapter/route must read the provider-appropriate header.
- **`query_payment_status` absent** — no server-authoritative recovery if a webhook is permanently missed.

---

## 12. Live Verification

Executed this session against **local Postgres `events_db`** through the FastAPI ASGI app with the deterministic sandbox gateway (real HMAC signing, real webhook processing path, real DB writes). This is integration-level, not unit-only — but it is **local sandbox**, not a real gateway and not a manual browser run.

| Flow | Result |
|---|---|
| Paid registration → seat hold | **VERIFIED** |
| Pricing snapshot frozen into order | **VERIFIED** |
| Order creation + idempotency (same key → same order) | **VERIFIED** |
| Attempt creation | **VERIFIED** |
| Sandbox success → capture → registration confirmed | **VERIFIED** |
| Sandbox failure → attempt failed, reg `payment_failed` | **VERIFIED** |
| Retry after failure | **VERIFIED** |
| Pending → `payment_verification` + hold extension | **VERIFIED** |
| `verify` escalation → `requires_verification` + `VERIFICATION_UNRESOLVED` exception | **VERIFIED** (`test_verification_workflow_escalates_and_blocks_retry`) |
| Retry blocked during verification | **VERIFIED** |
| Duplicate initiation | **VERIFIED** |
| Concurrent initiation (5-way order, 5-way attempt) | **VERIFIED** |
| Webhook signature invalid → rejected | **VERIFIED** |
| Webhook freshness: stale / future / malformed / missing → rejected | **VERIFIED** |
| Webhook amount / currency tamper → rejected | **VERIFIED** |
| Replay after successful capture → no effect | **VERIFIED** |
| Captured-after-seat-expiry → exception, no silent reconfirm | **VERIFIED** |
| Order / hold expiry sweep (idempotent, concurrency-safe, in-flight guard) | **VERIFIED** |
| Returning attendee + `latest_order_id` recovery | **VERIFIED** (`test_latest_order_id_tracks_registration_through_payment_lifecycle`) |
| Attendee timeline + developer timeline | **VERIFIED** |
| Lifecycle scheduler script (`run_payment_lifecycle_sweep.py`) end-to-end | **VERIFIED** (subprocess tests) |

**NOT LIVE VERIFIED:**
- Any real gateway (no Razorpay/PG code exists).
- Hosted-checkout redirect / client SDK handoff.
- `query_payment_status` / reconciliation.
- Refunds.
- External / guest / BFF frontend contract.
- Manual browser-driven attendee run.
- The dev diagnostics scenario runner's ad-hoc identities (env/seed-data mismatch against the remote `alumni_db`; core flows still verified via seeded identities).

---

## 13. Required Status Summary

| Area | Status | Evidence | Razorpay Impact |
|---|---|---|---|
| Payment Core | READY | `payment_service.py`; 100 payment tests; live-verified | No change to core |
| Pricing | READY | `pricing_service.py`; 6 unit + integration; Decimal/INR | Adapter converts rupees→paise |
| Registration coupling | READY (alumni-gated) | `registration_service.py`; seat-hold live-verified | Alumni gate is an external-user blocker |
| Orders | READY | `payment_orders` + partial unique indexes; idempotency test | Store `razorpay_order_id` in `gateway_order_ref` |
| Attempts | READY | `payment_attempts` + mig 020 guard; 5-way test | Store `razorpay_payment_id` in `gateway_payment_ref` |
| Verification | READY | `verify_attempt` escalation; exception; live-verified | Map `payment.pending`→`PAYMENT_PENDING` |
| Retry | READY | new-attempt-per-retry; blocked-during-verification test | Unchanged |
| Webhook security | READY (sandbox) / SMALL CHANGE (real) | HMAC + freshness + dedupe; 10 tests | Real `verify_webhook` over raw bytes; provider header |
| Lifecycle / expiry | READY | `payment_lifecycle_service` + script; 17 tests | Unchanged; add reconcile later |
| Returning attendee | READY | `latest_order_id`; live-verified | Unchanged |
| Timeline | READY (attendee) / PARTIAL (admin) | `get_timeline` / `get_developer_timeline` | Unchanged |
| RBAC | READY | `admin_auth.py`; 12 tests; fabricated-role tests | Unchanged |
| Admin config | READY | `payment_config_service.py`; 14 tests; append-only versioning | Add optional per-event `gateway` column (recommended) |
| Gateway abstraction | READY | `base.py` / `registry.py` / adapter; 16 tests | Add adapter + registry line + checkout field |
| Real gateway | MISSING | none — by design | The sprint itself |
| External frontend | MISSING → BLOCKER | CORS localhost-only; no integration principal | Choose BFF (Option B) |
| Guest ownership | MISSING → BLOCKER | ownership = `payer_firebase_uid`; alumni gate | BFF or scoped token |
| Reconciliation | MISSING | `query_payment_status` raises | Build on Razorpay `payments.fetch` post-pilot |
| Refunds | MISSING | `refund()` raises | Out of scope for pilot |
| Diagnostics | READY (dev-gated) | `dev_diagnostics.py` `/payments*` | Add a Razorpay sandbox scenario runner |

---

## 14. Verification Acceptance Criteria

| Criterion | Result |
|---|---|
| Full backend baseline executed | ✅ 339 passed / 4 skipped |
| Focused payment regression executed | ✅ 100 passed (7 suites) + 15-test subset re-run |
| Current payment architecture mapped | ✅ §3 |
| Payment flow matrix completed | ✅ §4 (30 rows) |
| Active payment API inventory completed | ✅ §5 |
| Gateway foundation audited | ✅ §6 |
| Razorpay adapter readiness assessed | ✅ §6 / §7 |
| External frontend / guest ownership assessed | ✅ §8 / §9 |
| ₹1 pilot readiness assessed | ✅ §10 |
| Security readiness assessed | ✅ §11 |
| Representative flows live-tested where possible | ✅ §12 (local sandbox) |
| Missing / partial flows clearly identified | ✅ §4 / §15 |
| No implementation started | ✅ report only |
| RGIS completed | ✅ §16 |
| DoD completed | ✅ §17 |
| Verification / status report created | ✅ this document |

---

## 15. Missing / Partial Features

**Missing:**
- Real payment gateway adapter (Razorpay or any provider).
- Hosted-checkout / redirect field in `GatewayInitiationResult`.
- `query_payment_status` capability + reconciliation job.
- Refunds / cancellation / receipts / GST invoices.
- Guest / external-frontend ownership contract (capability token or integration principal).
- Rate limiting.
- Production (authenticated) payment-exception resolution API.
- Per-event gateway selection (`payment_gateway_mode` is global).
- Notifications beyond the single confirmation email.

**Partial:**
- Admin timeline = developer timeline (no dedicated payment-admin role scoping).
- Lifecycle "scheduler" is a cron-invokable script + admin endpoints, not a daemon (design choice).
- Late-success handling: capture-after-expiry exception exists, but no proactive provider reconcile.

---

## 16. RGIS

**R — Reliability = PASS**
339/4 full suite; 100/0 payment subset; 15-test high-value subset re-run green; live end-to-end sandbox flow (register→capture→confirm→timeline→expiry) verified against real Postgres; concurrency (5-way order + 5-way attempt) and replay/freshness paths verified. Suites reproduced consistently.

**G — Governance = PASS**
RBAC identity comes only from a verified JWT; roles only from DB/settings; fabricated-role body/header tests pass. Admin config lifecycle is append-only and versioned; published-config swap is race-safe. Audit log covers every transition. Attendee vs developer timeline separation enforced. Minor: no authenticated exception-resolution route yet (operational, not a boundary breach).

**I — Integration = PASS (backend abstraction) / PARTIAL (external frontend)**
Razorpay can be added as a registry adapter without changing payment core — confirmed against source. Two small, pre-identified interface extensions needed (checkout-response field; raw-body webhook verify). **External frontend contract is NOT safe for direct browser use** (no guest ownership, no integration principal, CORS localhost-only, no rate limiting) — BFF recommended.

**S — Security = PASS**
Server-authoritative price/currency/success; idempotency at order/attempt/webhook layers; replay + freshness enforced on signed bodies; ownership checks on every path; concurrency via `FOR UPDATE` + partial unique indexes; secrets never leave the server. Gaps (rate limiting, `query_payment_status`, provider webhook header) are additive and do not weaken current guarantees.

---

## 17. Definition of Done

| Item | Grade |
|---|---|
| baseline | PASS |
| payment regressions | PASS |
| architecture inventory | PASS |
| flow status matrix | PASS |
| API inventory | PASS |
| gateway readiness | PASS |
| Razorpay gap analysis | PASS |
| external frontend readiness | PARTIAL (blocker identified; BFF recommended) |
| guest ownership readiness | FAIL (no model exists — expected; documented) |
| ₹1 pilot readiness | PARTIAL (event/price isolation ready; gateway selection global; needs Razorpay adapter) |
| security readiness | PASS (gaps noted, none regressive) |
| live verification | PASS (local sandbox); real gateway / external frontend NOT TESTED (no code) |
| RGIS | PASS (I partial on external frontend) |
| status report | PASS (this document) |

---

## 18. Exact Recommended Razorpay Sprint Scope

**Sprint: "Razorpay Test Mode — Gateway Adapter + Server Order + Webhook (no real money movement beyond ₹1 pilot)"**

**In scope:**
1. **Settings:** add `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `RAZORPAY_MODE` (`test`/`live`) to `app/config.py` (`extra="ignore"` already safe). No secret ever returned in a response.
2. **Interface extension (minimal):** add `checkout: Optional[GatewayCheckout]` to `GatewayInitiationResult` (fields: `provider_order_id`, `key_id`, `amount_minor`, `currency`). No change to existing webhook fields.
3. **Adapter `app/gateways/razorpay_gateway.py`:**
   - `capabilities = {CREATE_PAYMENT, VERIFY_WEBHOOK, PROCESS_WEBHOOK, QUERY_PAYMENT_STATUS}`.
   - `create_payment()` → call Razorpay `orders.create` (amount in paise = `int(final_amount*100)`, `currency="INR"`), return `GatewayInitiationResult(gateway_order_ref=<razorpay_order_id>, checkout=...)`, **no** immediate/delayed webhook.
   - `verify_webhook(raw_body, signature)` → `hmac_sha256(RAZORPAY_WEBHOOK_SECRET, raw_body)` vs `X-Razorpay-Signature` (raw bytes, `compare_digest`).
   - `parse_webhook(raw_body)` → map `payment.captured`/`order.paid` → `PAYMENT_SUCCESS`, `payment.failed` → `PAYMENT_FAILED`, `payment.authorized`/pending → `PAYMENT_PENDING`; `event_id` from payload; `issued_at_raw` from `created_at`.
   - `query_payment_status()` → Razorpay `payments.fetch` (enables reconciliation; wire a follow-up job later).
4. **Registry:** one line — `_register(RazorpayGateway())`.
5. **Route:** `app/api/payments.py` webhook handler reads `X-Razorpay-Signature` when `gateway == "razorpay"` (keep `X-Sandbox-Signature` for sandbox). Still `await request.body()` — no re-serialization.
6. **Attempt response:** pass `checkout` through `PaymentAttemptResponse` so the client can open Razorpay Checkout.
7. **Per-event gateway (recommended, contained):** add `payment_configurations.gateway VARCHAR(30) DEFAULT 'deterministic_sandbox'`; `create_attempt` uses the order's config gateway, falling back to `payment_gateway_mode`. Lets the ₹1 pilot event use `razorpay` while `event_id=392` stays on sandbox.
8. **₹1 pilot event:** new event + new published config (`base_amount=1.00`, `gst_enabled=false`, `gateway='razorpay'`). **Do not modify `event_id=392`.**
9. **Tests:** adapter conformance; raw-body signature (valid/invalid/tampered); paise conversion; INR enforcement; webhook dedupe with Razorpay event id; pending→verification mapping; capture→confirm; freshness with Razorpay `created_at`; fail-closed when keys absent.
10. **Frontend contract:** implement **Option B (BFF)** — iTelematics calls NITKSAA-EVENT as an integration principal; no CORS widening to a public browser origin; no guest ownership change.

**Explicitly OUT of scope:** refunds, receipts/GST invoices, scheduled reconciliation job (design only), Option A capability-token browser flow, changes to NITKSAA-PAYMENT, changes to `event_id=392`, any `live` mode traffic beyond the controlled ₹1 test.

**Prerequisites the team must have (no values here):** Razorpay Test Key ID, Test Key Secret, Test Webhook Secret; a public HTTPS URL for `POST /api/v1/payment-gateways/razorpay/webhook`; a return/callback URL if using redirect checkout; the allowed frontend origin / BFF host; a configured test event + amount.

---

## Appendix — Razorpay Test Mode Prerequisites Checklist

- [ ] Razorpay **Test** Key ID (`rzp_test_…`)
- [ ] Razorpay **Test** Key Secret (server-only; never in a response or client)
- [ ] Razorpay **Webhook Secret** (server-only)
- [ ] Public HTTPS webhook URL reachable by Razorpay → `POST /api/v1/payment-gateways/razorpay/webhook`
- [ ] Return/callback URL (only if hosted-redirect checkout is used)
- [ ] Allowed frontend origin (BFF host, or the eventual browser origin if Option A is later chosen)
- [ ] Test event created + published + its own published `payment_configurations` row (₹1.00, GST off, gateway `razorpay`)
- [ ] Test attendee identities (seeded active alumni) or BFF integration principal
- [ ] Decision recorded: global `PAYMENT_GATEWAY_MODE=razorpay` window **vs** per-event `gateway` column

**STOP — no Razorpay code implemented in this prompt. This report is the input to the Razorpay Test Mode integration sprint.**
