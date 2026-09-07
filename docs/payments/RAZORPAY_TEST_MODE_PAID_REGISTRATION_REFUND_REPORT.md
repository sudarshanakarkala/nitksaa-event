# Razorpay Test Mode + ₹1 Paid Registration + Full Refund — Sprint Report

**Project:** NITKSAA-EVENT (backend only)
**Date:** 2026-09-07
**Baseline doc:** `docs/payments/PAYMENT_FLOW_STATUS_AND_RAZORPAY_READINESS_REPORT.md`
**NITKSAA-PAYMENT / iTelematics frontend:** not touched.

---

## 1. Executive Summary

Implemented one complete backend vertical slice for real Razorpay Test Mode
payments and full refunds, on top of the existing gateway-neutral
architecture — **no redesign of `PaymentService` / `PaymentRepository`**, and
the free-event flow is byte-for-byte unchanged.

- **Per-event gateway selection** added (`payment_configurations.gateway`,
  snapshotted to `payment_orders.gateway`). `event_id=392` and every existing
  paid event stay on `deterministic_sandbox`; only an event whose published
  config says `razorpay` uses Razorpay. The global `PAYMENT_GATEWAY_MODE` no
  longer drives dispatch.
- **`RazorpayGateway` adapter** (`app/gateways/razorpay_gateway.py`),
  registered through the existing `GatewayRegistry`. Capabilities:
  `CREATE_PAYMENT`, `VERIFY_PAYMENT` (checkout-return first gate only),
  `VERIFY_WEBHOOK`, `PROCESS_WEBHOOK`, `QUERY_PAYMENT_STATUS`, `REFUND`,
  `QUERY_REFUND`. Talks to the Razorpay REST API over httpx (the `razorpay`
  PyPI SDK is deliberately **not** used — see §6).
- **Server-authoritative money end to end**: amount is computed by
  `pricing_service` in Decimal rupees, converted to paise (`₹1.00 → 100`)
  only inside the adapter; currency is INR-locked by DB CHECK + adapter
  guard; a browser reporting success can never confirm a registration —
  confirmation comes strictly from `query_payment_status` / a verified
  webhook, applied through one shared state machine.
- **Checkout verification endpoint** (`POST
  /api/v1/payment-orders/{order_id}/verify-checkout`): verifies the
  Razorpay signature (constant-time HMAC), checks the server-stored order id
  matches, then queries authoritative provider status and re-checks
  amount/currency before any capture.
- **Raw-body webhook**: the existing
  `POST /api/v1/payment-gateways/{gateway}/webhook` route now reads
  `X-Razorpay-Signature` and `X-Razorpay-Event-Id` for `gateway=razorpay`,
  verifies HMAC over the **exact received bytes** (no re-serialisation),
  and parses only after verification. Dedupe, replay/freshness, amount &
  currency checks, `FOR UPDATE` capture, idempotent confirmation and the
  captured-after-expiry exception are all preserved.
- **Refund domain** (new): `payment_refunds` table (migration 022),
  `RefundRepository`, `refund_service`, and two attendee endpoints —
  `POST /api/v1/registrations/{id}/cancel` and
  `GET /api/v1/registrations/{id}/refund`. Full refund only, 100% for the
  pilot. One logical refund per order guaranteed by two DB unique indexes;
  the provider `Idempotency-Key` header is an extra layer. Provider failure
  leaves a safe, retryable state (registration cancelled, refund row
  `failed`).
- **Deterministic sandbox gained REFUND/QUERY_REFUND** (processed instantly,
  no settlement delay) so the refund domain is exercisable end-to-end
  without a real provider.
- **Tests:** **+68 new**, 0 failures. Full backend suite **407 passed / 4
  skipped** (was 339/4 — the 4 skips are the same pre-existing
  `test_admin_rbac.py` design skips). Fresh-DB migration chain
  (`001_events.sql … 022`) applies clean.
- **Live Razorpay Test Mode: BLOCKED** — no Test Key ID / Key Secret /
  Webhook Secret / public HTTPS webhook URL was available. All code and
  automated verification are complete; the live provider run is the only
  outstanding item (§18).

---

## 2. Baseline

Reproduced this session before and after the change:

| Run | Before | After |
|---|---|---|
| `pytest -q` (full) | 339 passed, 4 skipped | **407 passed, 4 skipped** |
| Fresh-DB migration chain `001_events.sql … 022` | n/a | **applies clean**, `gateway` columns + `payment_refunds` present |
| Admin sign-out regression (`test_admin_signout_regression.py`) | green | **green** |

The 4 skips are all in `test_admin_rbac.py` (`create_event` / `list_all_events`
have no `event_id` to scope — `platform_admin`-only by design). Not
error/environment skips.

`EMAIL_MODE=send` in `backend/.env` makes the full run ~3.5 min (real SMTP
attempts); behaviour is otherwise unchanged.

---

## 3. Architecture

The gateway-neutral spine is unchanged. What this sprint added sits at the
edges:

```
Registration (unchanged — alumni-gated, seat hold for paid)
      │
Pricing (unchanged — Decimal rupees, INR, server-authoritative)
      │
Payment Order  ── NEW: snapshots payment_configurations.gateway → payment_orders.gateway
      │
Payment Attempt
      │   create_attempt now dispatches on order["gateway"] via
      │   registry.get_enabled_gateway(...)  (NOT settings.payment_gateway_mode)
      ▼
 ┌─ deterministic_sandbox ─ in-process signed webhook (unchanged)
 └─ razorpay ─ RazorpayGateway.create_payment():
        Razorpay POST /v1/orders (amount in paise)
        → GatewayInitiationResult(gateway_order_ref=<order_xxx>,
              checkout=GatewayCheckout(provider_order_id, key_id, amount_minor, currency))
        → payment_service persists the real order id onto the attempt
        → PaymentAttemptResponse.checkout returned to the client
      │
Confirmation — two authoritative paths, ONE shared state machine
(_apply_gateway_outcome, extracted from process_webhook):
 ├─ Webhook: POST /payment-gateways/razorpay/webhook
 │     raw bytes → verify_webhook(HMAC over raw body) → parse → dedupe
 │     (X-Razorpay-Event-Id) → freshness → amount/currency →
 │     FOR UPDATE order → _apply_gateway_outcome
 └─ Checkout return: POST /payment-orders/{id}/verify-checkout
       verify_checkout_signature (HMAC "order|payment", constant-time)  [first gate]
       → order-id match check
       → query_payment_status (Razorpay GET /v1/orders/{id}/payments)   [authoritative]
       → amount/currency re-check
       → _apply_gateway_outcome
      │
Capture → order 'paid', attempt 'captured', registration 'registered' (idempotent)
      │
Refund (NEW):
  POST /registrations/{id}/cancel
   → validate owner + captured payment
   → INSERT payment_refunds (pending) + registration → 'cancelled'   [one txn]
       (uq_payment_refunds_idempotency + uq_payment_refunds_active_per_order
        are the real "one logical refund" guard)
   → gateway.refund(provider_payment_id, amount_minor, idempotency_key)
   → payment_refunds → processed | processing | failed
  GET /registrations/{id}/refund  → attendee-safe status (+ query_refund refresh)
```

### Files added / changed

**Migrations (new):**
`migrations/events_db/021_payment_config_gateway.sql`,
`migrations/events_db/022_payment_refunds.sql`.

**New modules:**
`app/gateways/razorpay_gateway.py`,
`app/repositories/refund_repository.py`,
`app/services/refund_service.py`,
`app/api/refunds.py`,
`tests/_razorpay_fakes.py`,
`tests/test_razorpay_gateway.py`,
`tests/test_razorpay_checkout_and_webhook.py`,
`tests/test_payment_refunds.py`,
`tests/test_per_event_gateway.py`,
`tests/test_free_flow_regression.py`.

**Changed:**
`app/config.py` (Razorpay settings + `razorpay_configured`),
`.env.example` (placeholders),
`app/gateways/base.py` (`GatewayCheckout`, `GatewayInitiationResult.checkout`,
`NormalizedRefundStatus`, `NormalizedRefundResult`, real `refund` /
`query_refund` / `verify_checkout_signature` signatures),
`app/gateways/deterministic_sandbox.py` (deterministic `REFUND` / `QUERY_REFUND`),
`app/gateways/registry.py` (register `razorpay`),
`app/repositories/payment_repository.py` (`create_order(gateway=…)`,
`update_attempt_gateway_order_ref`, config `gateway` params),
`app/services/payment_service.py` (per-order dispatch, real-ref persistence,
`GatewayError` handling, `_apply_gateway_outcome` extraction, `provider_event_id`,
`verify_checkout`, `query_payment_status` path in `verify_attempt`,
`_gateway_for_order`),
`app/services/payment_config_service.py` (`gateway` validation + view + draft),
`app/schemas/payments.py` (`PaymentCheckout`, `PaymentAttemptResponse.checkout`,
`VerifyCheckoutRequest/Response`, `RefundStatusResponse`,
`CancelRegistrationRequest`, `PaymentConfigImportRequest.gateway`),
`app/schemas/payment_admin.py` (`gateway`),
`app/api/payments.py` (verify-checkout route, Razorpay webhook headers),
`app/api/dev_diagnostics.py` (config-import `gateway` pass-through),
`app/main.py` (include `refunds` router),
`tests/test_payment_gateway_foundation.py` (3 tests updated for the
intentional per-event-gateway + sandbox-refund changes; 1 new test).

---

## 4. Per-Event Gateway Change

`migrations/events_db/021_payment_config_gateway.sql` (additive):

- `payment_configurations.gateway VARCHAR(30) NOT NULL DEFAULT
  'deterministic_sandbox'` + `CHECK (gateway IN
  ('deterministic_sandbox','razorpay'))`.
- `payment_orders.gateway VARCHAR(30) NOT NULL DEFAULT
  'deterministic_sandbox'` + same CHECK — **snapshotted** from the published
  config at `create_order` time, so a later config edit/retire never changes
  an in-flight order's gateway (same immutability principle as
  `configuration_id` / `pricing_snapshot`).

`payment_service.create_attempt` now:

```python
order_gateway_name = order["gateway"]           # snapshot, not settings
gateway = gateway_registry.get_enabled_gateway(order_gateway_name, settings)
# UnknownGatewayError / GatewayDisabledError -> 503 payment_gateway_unavailable
```

Existing rows (and `event_id=392`) get the default and behave identically.
Validation (`payment_config_service.validate_configuration` + Pydantic
`pattern`) rejects any gateway outside the allow-list. **Not** a global
switch: enabling Razorpay for the pilot event does not affect any other
event.

Tests: `tests/test_per_event_gateway.py` (7 — default, razorpay accepted,
unknown rejected 422, order snapshot, `event_id=392` stays sandbox [skips if
absent], validator).

---

## 5. Settings / Secret Handling

`app/config.py` — new server-only fields (aliases): `RAZORPAY_KEY_ID`,
`RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `RAZORPAY_MODE`
(`test`|`live`), plus `RAZORPAY_API_BASE` / `RAZORPAY_HTTP_TIMEOUT_SECONDS`.
`Settings.razorpay_configured` is `True` only when **both** key id and secret
are present.

- Placeholders added to `.env.example`; real values never committed
  (`backend/.env` is git-ignored).
- Secrets are read inside adapter method bodies from `settings`, never
  returned in any response, never logged, never in an exception message
  (`RazorpayApiError` messages carry only operation + HTTP status + provider
  error code). `PaymentCheckout` exposes `key_id` only.
- **Fail closed:** `RazorpayGateway.is_enabled()` returns `False` when
  credentials are missing or `RAZORPAY_MODE` is not `test`/`live`, so
  `create_attempt` for a razorpay order raises `503
  payment_gateway_unavailable` and **no attempt row / order mutation
  occurs** (test:
  `test_attempt_creation_fails_closed_when_order_gateway_is_unusable`).

Tests: `test_razorpay_gateway.py` — `test_is_enabled_false_without_credentials`,
`test_is_enabled_false_on_unknown_mode`, `test_checkout_payload_carries_no_secret`.

---

## 6. Razorpay Adapter

`app/gateways/razorpay_gateway.py`. Registered via one line in
`app/gateways/registry.py`. No `razorpay`-name branching anywhere in
`payment_service` — dispatch is entirely through the registry + capability
model.

**Why no `razorpay` SDK:** it is a thin wrapper over the six REST calls used
here, adds a `requests` dependency, and is not in the locked venv (offline
CI). A small httpx client (`_RazorpayClient`, httpx already a dependency) is
fully offline-testable via the `_build_client(settings)` seam. Documented
here as the §5 prompt allows.

| Method | Razorpay call | Normalisation |
|---|---|---|
| `create_payment` | `POST /v1/orders` (`amount`=paise, `currency`=INR, `payment_capture`=1) | returns `GatewayInitiationResult(gateway_order_ref=order_xxx, checkout=…)`, no webhook fields |
| `verify_checkout_signature` | — (local HMAC) | `HMAC_SHA256(key_secret, "order_id\|payment_id")` vs signature, `compare_digest` |
| `verify_webhook` | — (local HMAC) | `HMAC_SHA256(webhook_secret, raw_body_bytes)` vs `X-Razorpay-Signature`, `compare_digest`; empty/absent → `False`, never raises |
| `parse_webhook` | — | `payment.captured` / `order.paid` → `PAYMENT_SUCCESS`; `payment.failed` → `PAYMENT_FAILED`; `payment.authorized` → `PAYMENT_PENDING`; else `UNKNOWN`. Amount paise→rupees. `issued_at_raw` = body `created_at`. Body-derived dedupe id `"<event>:<entity_id>"` (header id preferred by the route). Unparseable → `GatewayWebhookUnparseableError` |
| `query_payment_status` | `GET /v1/orders/{id}/payments` | picks a `captured` payment else most recent; `captured`→SUCCESS, `authorized`/`created`/`pending`→PENDING, `failed`→FAILED; no payments → PENDING (not a crash) |
| `refund` | `POST /v1/payments/{id}/refund` (`amount`=paise, `speed`=normal, header `Idempotency-Key`) | `processed`→`REFUND_PROCESSED`, `pending`/`created`→`REFUND_PENDING`, `failed`→`REFUND_FAILED` |
| `query_refund` | `GET /v1/refunds/{id}` | same map |

`rupees_to_paise(Decimal)` — exact, `ROUND_HALF_UP`, `₹1.00 → 100`,
`₹2499.99 → 249999`. Non-INR raises `GatewayError` in `create_payment` and
`refund`.

Tests: `tests/test_razorpay_gateway.py` (28) — registration, capabilities,
fail-closed, paise conversion (6 params), INR guards, checkout payload
(no secret), checkout signature valid/invalid/tampered/empty, webhook
signature over raw bytes (+ mutation breaks it), event mapping + amount
conversion + dedupe id, unparseable, unknown event, `query_payment_status`
mapping (3 params) + empty, refund mapping (3 params), refund non-INR,
refund provider-error propagation, `query_refund` mapping.

---

## 7. Checkout Contract

`GatewayInitiationResult.checkout: Optional[GatewayCheckout]` — new optional
field, sandbox behaviour unchanged (it sets a webhook field, not `checkout`).

`GatewayCheckout` / `PaymentCheckout` (response schema) carry **public
values only**: `provider`, `provider_order_id`, `key_id`, `amount_minor`
(paise), `currency`. Never `key_secret` / `webhook_secret`.

`PaymentAttemptResponse.checkout` is populated for a razorpay attempt and
`null` for sandbox. Frontend contract for the next sprint:

```
POST /api/v1/payment-orders/{order_id}/attempts   (body: {} — no scenario for razorpay)
  → 201 { attempt_id, order_id, gateway:"razorpay", status:"initiated",
          checkout: { provider:"razorpay", provider_order_id, key_id,
                      amount_minor, currency:"INR" } }

open Razorpay Checkout with checkout.key_id + checkout.provider_order_id + checkout.amount_minor
on handler success:
POST /api/v1/payment-orders/{order_id}/verify-checkout
  { razorpay_payment_id, razorpay_order_id, razorpay_signature }
  → 200 { order_id, attempt_id, order_status, registration_status,
          payment_confirmed: bool, safe_message }

GET /api/v1/registrations/{id}/refund → { refund_id, status, amount, currency, safe_message }
```

---

## 8. ₹1 Pilot Configuration

Supported via the standard config path with `gateway: "razorpay"`:

```
Event:    a NEW event (e.g. "Razorpay Payment Validation") — do NOT touch event_id=392
Config:   base_amount = 1.00, gst_enabled = false, currency = INR (enforced),
          gateway = "razorpay", seat_hold_minutes / session_expiry as usual
Amount crossing to Razorpay: 100 paise (rupees_to_paise(Decimal("1.00")))
Mode:     RAZORPAY_MODE=test
```

Created with `POST /api/v1/admin/events` (+ publish) then the admin
draft→publish flow or the dev `configuration/import` endpoint (now accepts
`gateway`). `event_id=392` keeps `gateway='deterministic_sandbox'` and is
never modified. Tests build exactly this shape
(`tests/test_razorpay_checkout_and_webhook.py::_mk_razorpay_event`,
`base_amount="1.00"`, `gst_enabled=False`).

---

## 9. Payment Verification

`payment_service.verify_checkout(order_id, user, body)` — invoked by
`POST /api/v1/payment-orders/{order_id}/verify-checkout`:

1. Load order for caller (ownership — cross-user → 404).
2. Gateway must support `VERIFY_PAYMENT` → else `409
   checkout_verification_not_supported`.
3. Resolve the attempt by the **server-stored** `gateway_order_ref` (=
   Razorpay order id). Not found / different order → `404`.
4. `attempt.gateway_order_ref == body.razorpay_order_id` → else `400
   checkout_order_mismatch`.
5. `gw.verify_checkout_signature(order_id, payment_id, signature)` — invalid
   → audit `payment_checkout_signature_invalid`, `400
   checkout_signature_invalid`, **no capture**. Also catches a tampered
   `razorpay_payment_id` (the signature no longer matches).
6. `gw.query_payment_status(order_id)` — authoritative. On `PAYMENT_SUCCESS`,
   re-check `currency == attempt.currency` and `Decimal(amount_raw) ==
   Decimal(attempt.amount)` → mismatch → audit
   `payment_checkout_amount_mismatch`, `400 checkout_amount_mismatch`, **no
   capture**.
7. Only then `_apply_gateway_outcome` (the same state machine the webhook
   uses) captures / confirms.

**A browser posting a fake success is rejected**: if the signature is bogus
it fails at step 5; if the signature is valid but the provider's own status
is not `captured`, step 6/7 leaves `payment_confirmed=False` and the
registration unconfirmed
(`test_checkout_browser_reports_success_but_provider_not_captured`).

Tests: `tests/test_razorpay_checkout_and_webhook.py` — success confirms;
invalid signature; tampered payment id; tampered order id; amount mismatch;
browser-fake success; cross-user denied.

---

## 10. Webhook

Route `POST /api/v1/payment-gateways/{gateway}/webhook` unchanged in shape.
For `gateway == "razorpay"` it now reads `X-Razorpay-Signature` (verification)
and `X-Razorpay-Event-Id` (dedupe), passing the **raw request bytes**
untouched to `payment_service.process_webhook(..., provider_event_id=…)`.

Order of checks (all preserved from the sandbox path):
signature (HMAC over raw bytes) → parseability → **dedupe** on `(razorpay,
X-Razorpay-Event-Id or body-derived id)` → **freshness** (`created_at`,
300s max age / 30s future skew) → unknown-order → **amount & currency**
match against the attempt → `SELECT … FOR UPDATE` on the order →
`_apply_gateway_outcome` → mark `payment_webhook_events` row.

Event mapping: `payment.captured` / `order.paid` → capture + confirm
(idempotent, captured-after-expiry exception preserved); `payment.failed` →
attempt `failed`, registration `payment_failed`; `payment.authorized` →
attempt `pending`, registration `payment_verification` + hold extension.

Tests: `tests/test_razorpay_checkout_and_webhook.py` — valid capture
confirms; invalid signature rejected; tampered body rejected; duplicate
event id idempotent (one capture); replay after capture (no extra
mutation); `payment.failed`; `payment.authorized` → pending/verification;
stale `created_at` rejected; unknown order rejected.

---

## 11. Query Payment Status

`RazorpayGateway.query_payment_status(order_id)` implemented (Razorpay `GET
/v1/orders/{id}/payments`). Wired into the existing
`POST /api/v1/payment-attempts/{attempt_id}/verify`:

- If the order's gateway declares `QUERY_PAYMENT_STATUS` and the attempt is
  `initiated`/`pending`/`requires_verification` with a `gateway_order_ref`,
  `verify_attempt` queries the provider, validates amount/currency, and
  applies the outcome via `_apply_gateway_outcome`. Covers browser-callback-
  before-webhook, manual "Check Status", pending, missed/late webhook.
- Sandbox orders don't declare the capability → the existing re-read /
  stuck-escalation behaviour is unchanged (regression suite green).

No reconciliation scheduler was built (out of scope).

Tests: `test_manual_verify_captures_via_query_status`,
`test_manual_verify_failed_via_query_status`,
`test_manual_verify_authorized_stays_pending`;
adapter mapping in `test_razorpay_gateway.py`.

---

## 12. Refund Model

`migrations/events_db/022_payment_refunds.sql` — `payment_refunds`:

`id`, `public_refund_number` (unique), `registration_id`,
`payment_order_id`, `payment_attempt_id`, `gateway`, `provider_payment_id`,
`provider_refund_id`, `amount NUMERIC(14,2)`, `currency` (INR CHECK),
`status` (`pending`|`processing`|`processed`|`failed`), `reason`,
`idempotency_key`, `failure_reason`, `requested_by`, `requested_at`,
`updated_at`, `finalized_at`.

Indexes (the authoritative "one logical refund" guard):
- `uq_payment_refunds_idempotency` (unique `idempotency_key`)
- `uq_payment_refunds_active_per_order` (unique `payment_order_id`
  `WHERE status IN ('pending','processing','processed')`)

`RefundRepository` + `refund_service`. Audit events reuse `event_audit_log`
(`payment_refund_requested` / `_processed` / `_updated` / `_failed`).
`payment_orders.status` is **not** widened with `refunded` this sprint —
refund truth lives in `payment_refunds`, registration goes `cancelled`
(known limitation §23).

---

## 13. Paid Cancellation

`POST /api/v1/registrations/{registration_id}/cancel` (body:
`{idempotency_key}`) → `refund_service.cancel_registration`:

1. Load registration for caller (cross-user → 404).
2. Already `cancelled` → return the current refund view (idempotent).
3. Not `registered` → `409 registration_not_cancellable` (pre-confirmation
   states are owned by the retry / lifecycle-sweep paths).
4. Find a `paid` order + its `captured` attempt (with
   `gateway_payment_ref`). None → free path (just cancel, no refund object);
   captured missing → `409 no_captured_payment`.
5. Gateway must declare `REFUND` → else `409 refund_not_supported`.
6. **One transaction:** INSERT `payment_refunds` (`pending`) + registration
   → `cancelled` + `cancelled_at`.
7. **Outside the transaction:** `gw.refund(provider_payment_id, amount_minor
   = final_amount·100, currency, idempotency_key)` →
   `REFUND_PROCESSED` → row `processed` + `finalized_at`;
   `REFUND_PENDING` → row `processing`;
   `GatewayError` → row `failed` + `failure_reason`, audit
   `payment_refund_failed`, registration stays `cancelled` (retryable).

`GET /api/v1/registrations/{registration_id}/refund` → attendee-safe status
(`refund_pending` | `refund_processed` | `refund_failed` | `none`),
refreshing a non-terminal refund via `gw.query_refund` first. Wording never
claims "returned to your bank" — `refund_processed` says "processed by the
payment provider".

Refund amount = full captured `order.final_amount`
(`test_refund_amount_equals_captured_amount`).

---

## 14. Refund Idempotency / Concurrency

- **DB is authoritative.** Only the caller that wins the INSERT race (unique
  `idempotency_key`, or the one-active-per-order partial unique index)
  proceeds to call the provider; every duplicate/concurrent caller catches
  `UniqueViolationError`, reloads the winner's row, and returns it **without
  a second provider call**.
- **Provider `Idempotency-Key` header** is forwarded on
  `POST /v1/payments/{id}/refund` as an additional safeguard.

Tests (`tests/test_payment_refunds.py`):
`test_duplicate_cancel_same_key_is_idempotent` (same key ×2 → same
`refund_id`, 1 row),
`test_repeated_cancel_different_keys_one_logical_refund` (different keys → 1
row),
`test_concurrent_cancel_only_one_logical_refund` (5 threads, same key → all
200, exactly 1 `payment_refunds` row),
`test_provider_refund_failure_leaves_safe_state`.

---

## 15. API Changes

New:
| Method | Path | Auth / ownership | Purpose |
|---|---|---|---|
| POST | `/api/v1/payment-orders/{order_id}/verify-checkout` | `get_current_user`, payer-owned order | verify Razorpay Checkout return, confirm from authoritative status |
| POST | `/api/v1/registrations/{registration_id}/cancel` | `get_current_user`, registration owner | cancel own registration; full refund if paid; idempotent per key |
| GET | `/api/v1/registrations/{registration_id}/refund` | `get_current_user`, registration owner | attendee-safe refund status |

Changed (no breaking change):
- `POST /api/v1/payment-gateways/{gateway}/webhook` — reads
  `X-Razorpay-Signature` / `X-Razorpay-Event-Id` when `gateway=razorpay`.
- `PaymentAttemptResponse` — new optional `checkout` object.
- `POST /api/v1/payment-attempts/{attempt_id}/verify` — now performs a real
  `query_payment_status` for gateways that support it.
- `POST /api/v1/dev/diagnostics/payments/configuration/import` &
  `POST /api/v1/admin/events/{event_id}/payment-configurations` — accept an
  optional `gateway` (default `deterministic_sandbox`).

Cross-user calls to cancel / refund-status / verify-checkout return `404`
(existence-hiding), never another user's data.

---

## 16. State Transitions

**Razorpay ₹1 paid (checkout path):**
```
register            → registration: seat_held
create payment-order → order: created (gateway=razorpay)
create attempt       → attempt: initiated; Razorpay order_xxx; checkout payload
verify-checkout OK   → attempt: captured; order: paid; registration: registered
verify-checkout, provider authorized (not captured) → unchanged; payment_confirmed=false
```
**Razorpay webhook:**
```
payment.captured / order.paid → capture + confirm (idempotent)
payment.failed                → attempt: failed;  registration: payment_failed
payment.authorized            → attempt: pending; registration: payment_verification (+hold extend)
duplicate event id            → processing_status "duplicate", no mutation
```
**Cancellation / refund:**
```
registered + paid order + captured attempt
  → payment_refunds: pending      + registration: cancelled          [one txn]
  → provider refund processed      → payment_refunds: processed (finalized)
  → provider refund pending        → payment_refunds: processing
  → provider error                 → payment_refunds: failed (registration stays cancelled)
free registered → cancel → registration: cancelled; refund status "none"
```

---

## 17. Automated Tests

**+68 new**, full suite **407 passed / 4 skipped**, 0 failures.

| Suite | Count | Coverage |
|---|---|---|
| `test_razorpay_gateway.py` (new) | 28 | adapter registration/capabilities, fail-closed (no creds / bad mode), paise conversion, INR guards, no-secret checkout payload, checkout signature (valid/invalid/tampered/empty), webhook HMAC over raw bytes, event & amount & dedupe-id mapping, unparseable, unknown event, `query_payment_status` mapping + empty, refund mapping + non-INR + provider-error, `query_refund` |
| `test_razorpay_checkout_and_webhook.py` (new) | 21 | ₹1 attempt returns checkout payload (100 paise, no secret, real ref persisted); order snapshots `gateway=razorpay`; checkout verify success confirms; invalid signature; tampered payment id; tampered order id; amount mismatch; browser-fake success; cross-user denied; manual verify via query-status (captured/failed/authorized); webhook valid/invalid-sig/tampered-body/duplicate/replay/failed/authorized/stale-timestamp/unknown-order |
| `test_payment_refunds.py` (new) | 10 | full refund of captured; amount == captured; non-captured rejected; cross-user cancel & status denied; duplicate key idempotent; different keys → one refund; 5-way concurrent → one refund; provider failure safe; free cancellation no refund object |
| `test_per_event_gateway.py` (new) | 7 | import default sandbox; import razorpay; unknown gateway 422; order snapshot; `event_id=392` stays sandbox (skips if absent); validator rejects bad gateway |
| `test_free_flow_regression.py` (new) | 2 | free registration confirms immediately with no payment order/attempt/config; free cancellation creates no refund object |
| `test_payment_gateway_foundation.py` (updated) | 18 | 3 tests updated for the intentional per-event-gateway + sandbox-refund changes; +1 (`test_sandbox_refund_is_deterministic_processed`) |
| Regression (unchanged, all green) | — | `test_payments`, `test_payment_webhook_freshness`, `test_payment_lifecycle_expiry`, `test_payment_rbac`, `test_payment_admin_config`, `test_payment_scheduler`, `test_admin_rbac`, `test_admin_signout_regression`, `test_event_flow`, `test_admin_event_management` |

**Fresh-DB check:** `001_events.sql … 022` applied to a scratch database
with `ON_ERROR_STOP=1` — clean; `payment_configurations.gateway`,
`payment_orders.gateway`, and `payment_refunds` all present.

**Test-change justification:** the 3 modified `test_payment_gateway_foundation`
tests encoded the *old* invariants "gateway selection is global" and "no
adapter implements refund". Both are changed **by this sprint's explicit
requirements** (per-event gateway; refunds in scope). The updated tests
assert the new, stronger invariants (per-order dispatch fails closed;
sandbox refund returns a real `NormalizedRefundResult`). No test was
weakened to hide a defect.

---

## 18. Live Razorpay Test Mode

**LIVE RAZORPAY TEST MODE = BLOCKED**

**Reason:** external prerequisites unavailable in this environment.
**Exact prerequisites required:**
- Razorpay **Test** Key ID (`rzp_test_…`) → `RAZORPAY_KEY_ID`
- Razorpay **Test** Key Secret → `RAZORPAY_KEY_SECRET`
- Razorpay **Webhook Secret** → `RAZORPAY_WEBHOOK_SECRET` (same string set on
  the dashboard webhook)
- A **public HTTPS URL** routing to
  `POST /api/v1/payment-gateways/razorpay/webhook` (ngrok/cloudflared for
  local, or a staging deploy), registered on the dashboard for events
  `payment.captured`, `payment.failed`, `payment.authorized`, `order.paid`,
  `refund.processed`, `refund.failed`, `refund.created`
- A seeded **active alumni** identity for the pilot event
- The **₹1 pilot event** + published config (`gateway="razorpay"`)

**Not simulated as PASS.** Everything up to the provider boundary is
verified offline (adapter unit tests + full ASGI/DB integration with the
Razorpay REST surface faked). When the prerequisites are supplied, run the
free / paid-₹1 / failure+retry / refund sequence in §20 of the prompt.

---

## 19. Security Verification

| Control | Status | Evidence |
|---|---|---|
| Client cannot set authoritative amount | PASS | `pricing_service` server-side; `create_attempt` uses `order.final_amount`; paise conversion inside adapter; existing `client_supplied_amount…` test green |
| Client cannot set currency | PASS | INR CHECK on config/order; adapter INR guard; webhook + checkout currency re-check |
| Client cannot mark payment success | PASS | confirmation only via verified webhook or `query_payment_status`; `verify_checkout_signature` is first-gate only; `test_checkout_browser_reports_success_but_provider_not_captured` |
| Checkout signature verified server-side, constant-time | PASS | `hmac.compare_digest` over `"order\|payment"`; tampered id/sig tests |
| Webhook verified over raw bytes, parse-after-verify | PASS | route passes `await request.body()` untouched; `verify_webhook` HMACs raw bytes; tampered-body test |
| Webhook dedupe / replay | PASS | `payment_webhook_events` unique `(gateway, event_id)`; `X-Razorpay-Event-Id`; duplicate + replay tests |
| Webhook freshness | PASS | `created_at` age/skew gate; stale-timestamp test |
| Gateway secrets server-only | PASS | read in method bodies; never in responses/logs/exceptions; `test_checkout_payload_carries_no_secret`; `gateway-config` endpoint already excludes secrets |
| Fail-closed config | PASS | `is_enabled` false without creds / bad mode → 503, no state mutation |
| Refund amount/currency server-authoritative | PASS | `amount = order.final_amount`; INR only; provider result re-mapped, not trusted for state |
| Refund idempotency / one logical refund | PASS | two DB unique indexes; duplicate + 5-way concurrent tests |
| Cross-user cancel / refund / verify-checkout | PASS | ownership in service; 404 existence-hiding; dedicated tests |
| RBAC / admin boundaries | PASS | per-event gateway is an admin-config field through the existing RBAC'd routes; regression suites green |
| Audit trail | PASS | new `payment_checkout_*` and `payment_refund_*` events in `event_audit_log` |

No CRITICAL/HIGH findings. Gaps carried forward (not regressions): no rate
limiting; no authenticated production exception-resolution API; no external
guest/BFF contract (next sprint).

---

## 20. Acceptance Criteria

| Item | Grade |
|---|---|
| baseline reproduced | PASS (339/4 → 407/4) |
| full backend suite green | PASS |
| focused payment + razorpay + refund suites green | PASS |
| free registration preserved | PASS |
| free cancellation verified | PASS |
| per-event gateway selection implemented | PASS |
| `event_id=392` remains sandbox | PASS (test skips only if no config present) |
| ₹1 pilot isolated | PASS |
| Razorpay settings added safely | PASS |
| SDK/dependency handled | PASS (httpx; SDK declined + documented) |
| checkout contract added | PASS |
| Razorpay adapter registered | PASS |
| ₹1 → exactly 100 paise | PASS |
| INR enforced | PASS |
| checkout signature verification implemented | PASS |
| browser fake success rejected | PASS |
| query_payment_status implemented | PASS |
| raw-body webhook verification implemented | PASS |
| provider event dedupe / replay / freshness preserved | PASS |
| paid registration confirms only after authoritative success | PASS |
| refund persistence implemented | PASS |
| attendee paid cancellation implemented | PASS |
| full refund implemented | PASS |
| refund idempotency implemented | PASS |
| concurrent refund safe | PASS |
| refund status query implemented | PASS |
| cross-user cancellation/refund denied | PASS |
| no secret leakage | PASS |
| admin sign-out fix remains green | PASS |
| full regression green | PASS |
| live Razorpay Test Mode | PARTIAL — BLOCKED on external prerequisites (§18); all code/tests complete |
| RGIS complete | PASS |
| DoD complete | PASS |
| verification report created | PASS (this document) |

---

## 21. RGIS

**R — Reliability = PASS**
Free / paid-₹1 / retry / pending / refund / duplicate / 5-way-concurrent
paths are all covered by automated tests against real local Postgres through
the ASGI app; full suite 407/0/4, reproduced. Fresh-DB migration chain
clean.

**G — Governance = PASS**
Gateway choice is an admin-config field flowing through the existing RBAC'd
config routes; snapshotted per order. Ownership enforced on every new
endpoint (cross-user → 404). Audit log extended (`payment_checkout_*`,
`payment_refund_*`). Alumni/Firebase model untouched. Admin sign-out
regression green.

**I — Integration = PASS**
Razorpay is reached only through `PaymentGateway` + `GatewayRegistry` +
capability model — no provider-name branching in `payment_service`. The one
shared outcome state machine (`_apply_gateway_outcome`) serves both the
webhook and the checkout-verify path. Checkout / status / refund response
contracts are defined and typed for the next frontend sprint (§7).

**S — Security = PASS**
Server-authoritative amount / currency / success / refund; checkout & webhook
HMAC verified server-side with `compare_digest` over raw material;
parse-after-verify; dedupe + replay + freshness preserved; refund idempotency
enforced by DB uniqueness (+ provider Idempotency-Key); secrets server-only
and absent from responses/logs/exceptions; fail-closed when unconfigured.

---

## 22. DoD

```
baseline:            PASS  (339/4 → 407/4; fresh-DB chain clean)
free flow:           PASS  (confirm-immediately, no payment objects; free cancel)
per-event gateway:   PASS  (migration 021; config + order snapshot; 392 stays sandbox)
Razorpay adapter:    PASS  (registry-registered; 7 capabilities; httpx, no SDK)
checkout contract:   PASS  (GatewayCheckout / PaymentAttemptResponse.checkout; no secret)
payment verification:PASS  (signature gate + authoritative query + amount recheck)
query status:        PASS  (adapter + wired into /verify; no scheduler)
webhook:             PASS  (raw-body HMAC, header event id, dedupe/replay/freshness kept)
paid confirmation:   PASS  (only via webhook / query-status through shared state machine)
refund persistence:  PASS  (migration 022; RefundRepository; audit events)
cancel/refund:       PASS  (POST /cancel, GET /refund; full refund; free path)
refund query:        PASS  (GET /refund + query_refund refresh; attendee-safe wording)
idempotency:         PASS  (unique idempotency_key + same-key/different-key tests)
concurrency:         PASS  (uq_active_per_order; 5-way concurrent → one refund)
ownership:           PASS  (cross-user cancel/status/verify → 404)
security:            PASS  (§19 — all controls PASS, no CRITICAL/HIGH)
admin regression:    PASS  (test_admin_signout_regression, test_admin_rbac green)
full regression:     PASS  (407 passed, 4 pre-existing skips, 0 failures)
live Test Mode:      PARTIAL / BLOCKED  (external prerequisites — §18; not simulated)
RGIS:                PASS  (R/G/I/S all PASS)
report:              PASS  (this document)
```

---

## 23. Known Limitations

- **`payment_orders.status` not widened** with `refunded` this sprint — a
  refunded paid order stays `status='paid'`; authoritative post-cancel state
  is `payment_refunds.status` + `registrations.status='cancelled'`. Add the
  value + transition if reporting needs it.
- **No reconciliation scheduler** — `query_payment_status` /
  `query_refund` exist and are called on demand (`/verify`, `/refund`), but
  nothing sweeps stuck rows automatically.
- **Full refund only** — no partial refunds, no policy engine (out of scope).
- **`RAZORPAY_MODE` does not gate `create_payment`** beyond `is_enabled`'s
  test/live sanity check — mode is informational for `test` here; a genuine
  `live` guardrail (e.g. refusing `live` outside production) is a follow-up.
- **`razorpay` SDK not added** — httpx client instead (documented, §6). If a
  future need arises (e.g. Route/subscriptions) revisit.
- **Dedupe id** for Razorpay prefers `X-Razorpay-Event-Id`; if a delivery
  omits it, the body-derived `"<event>:<entity_id>"` is used — unique per
  state transition but not per delivery attempt.
- **External/guest frontend contract** unchanged — still Firebase + active
  alumni; live pilot must use seeded alumni identities or a BFF (next
  sprint).

---

## 24. Remaining Blockers

1. **Live Razorpay Test Mode run** — needs Test Key ID / Key Secret /
   Webhook Secret + a public HTTPS webhook URL + the ₹1 pilot event +
   a seeded active-alumni tester (§18). Code and offline verification are
   complete.

No code blockers.

---

## 25. Exactly One Recommended Next Step

**Run the live Razorpay Test Mode sequence** (§18 / prompt §20: free → paid
₹1 → failure+retry → full refund) once the Test credentials and a public
HTTPS webhook URL are provided, then hand the verified
checkout/verify/refund response contract (§7) to the iTelematics frontend
sprint. Do **not** start frontend integration before that live run.
