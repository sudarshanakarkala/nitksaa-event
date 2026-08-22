# NITKSAA Event — Payment API Integration Guide

Source- and live-verified 2026-08-22 against the deterministic-sandbox payment flow (Phase 0).
Every request/response pair below marked "live-verified" was executed against a running local
instance (`APP_ENV=development`) during this documentation pass, using seeded test identities
`TEST_ALUMNI_UID_001`/`002`/`043` (the same identities `tests/test_payments.py` uses).

---

## 1. Step-by-step flow

```
 1. Event            admin publishes event, is_free=false
 2. Registration     POST /events/{id}/register           → status: seat_held
 3. Pricing          GET  /events/{id}/payment-pricing     → server-computed final_amount
 4. Seat hold        (implicit in step 2 — hold_expires_at = now + seat_hold_minutes)
 5. Payment order    POST /registrations/{id}/payment-order → status: created
 6. Payment attempt  POST /payment-orders/{id}/attempts     → gateway initiation
 7. Gateway/sandbox  deterministic_sandbox builds+signs a webhook payload
 8. Gateway result   sandbox delivers the payload in-process (immediate) or after 2s (delayed)
 9. Webhook/verify   POST /payment-gateways/{gw}/webhook    → signature/freshness/amount checks
10. Capture          attempt → captured; order → paid
11. Reg. confirmation registration → registered (skipped if hold already expired — see §Expiry)
12. Status/timeline  GET .../payment-orders/{id}, GET .../timeline
13. Expiry/recovery  order/hold sweeps; POST .../verify for stuck pending attempts
```

### Step 1 — Event
Prerequisite: an admin has created and published a paid event (`is_free=false`) with a
**published** `payment_configurations` row (via WP1 draft→validate→publish, or the dev-diagnostics
config-import shortcut). Registering against a paid event with no published config returns `409
payment_not_configured` at registration time already — the check happens before a seat hold is
ever created.

### Step 2 — Registration
```http
POST /api/v1/events/14760/register
Authorization: Bearer <token>
Content-Type: application/json

{"attendee_note": "optional"}
```
→ `201`, `status: "seat_held"`, `hold_expires_at` set `payment_session`-independently from
`payment_configurations.seat_hold_minutes`. Live-verified. Next state: seat is held; registration
is **not yet payable via idempotency-safe retries** until a payment order exists.
Failure/retry: a second call for the same event while a hold/registration is live → `409
already_registered` (live-verified) — the client should route the user back to their existing
registration (`GET .../my-registration`) rather than retrying blindly.

### Step 3 — Pricing
```http
GET /api/v1/events/14760/payment-pricing
Authorization: Bearer <token>
```
→ `200`, server-computed `final_amount`. Pure read; call this any time before or during checkout
to display an authoritative price — never compute it client-side. Live-verified: `100.00` base +
`18.00` GST(18% exclusive) = `118.00` final.

### Step 4 — Seat hold
No separate endpoint — this is the `hold_expires_at` set in step 2. The client's only
responsibility is to complete payment (or accept expiry) before that deadline; there is no
extend/renew endpoint for the attendee (extension only happens automatically when a payment
enters `PENDING`/verification — see step 9/13).

### Step 5 — Payment order
```http
POST /api/v1/registrations/5665/payment-order
Authorization: Bearer <token>
Content-Type: application/json

{"idempotency_key": "client-generated-uuid-or-similar"}
```
→ `201`, `status: "created"`, `expires_at` = now + `payment_session_expiry_minutes`. **Client
must generate and persist `idempotency_key` locally before this call** (e.g. `crypto.randomUUID()`
stored in local state) — if the request times out or the response is lost, retry with the *same*
key; the server returns the original order rather than creating a duplicate. Live-verified: same
key replayed → identical `order_id`/amounts, still `201`.
Next state: registration `seat_held` → `payment_pending`.
Failure: `409 registration_not_payable` if registration isn't in a payable state (e.g. already
`registered`); `409 seat_hold_expired` if the hold lapsed — the client should restart from step 2.

### Step 6 — Payment attempt
```http
POST /api/v1/payment-orders/ORD-IinxJRey-TyC/attempts
Authorization: Bearer <token>
Content-Type: application/json

{"scenario": "SUCCESS"}
```
`scenario` is **sandbox-only** — a future real-gateway integration would omit this field entirely
and instead receive a redirect/checkout URL back from `create_payment` (not yet defined on the
interface — see security guide, §Gateway abstraction). Live-verified for all four immediate
scenarios (`SUCCESS`→`captured`, `FAILURE`→`failed`, `PENDING`→`pending`,
and `CANCELLED` by source/tests) plus both delayed variants (source-verified: same outcome, ~2s
later, via `BackgroundTasks`).

### Steps 7–8 — Gateway / gateway result
Sandbox-internal — `deterministic_sandbox.build_signed_delivery` constructs and HMAC-signs the
payload, then either returns it for immediate in-process delivery or schedules delivery after
`DELAYED_SCENARIO_DELAY_SECONDS` (2s). A real gateway would instead redirect the user to a hosted
checkout page and later deliver an HTTP webhook to step 9's endpoint asynchronously — the client
integration shape (poll `GET .../payment-orders/{id}` and/or `GET .../timeline` after returning
from checkout) is the same regardless.

### Step 9 — Webhook / verification
For the sandbox's immediate scenarios, this happens synchronously inside the attempt-creation
call (steps 6–10 collapse into one HTTP round trip from the client's point of view) — see the
security guide's full webhook gate sequence (signature → freshness → duplicate → correlation →
amount/currency → row-locked transition).

For `PENDING` or a delayed scenario, the client instead **polls**:
```http
POST /api/v1/payment-attempts/ATT-.../verify
Authorization: Bearer <token>
```
→ re-reads current state; if a webhook already resolved it, returns the resolved status. If still
`pending` past 30 minutes, escalates to `requires_verification` and opens a
`VERIFICATION_UNRESOLVED` exception for manual/dev resolution. Live-verified: `PENDING` scenario,
immediate verify call → stays `pending` (well under 30 min), `order.safe_message`: "Your payment
confirmation is being verified. Please do not pay again." and `can_retry: false` — **the client
must not offer a retry button while `registration_status == "payment_verification"`.**

### Step 10 — Capture
Server-internal (webhook processing). Financial state (`amount_paid`, order `paid`) is recorded
unconditionally on a `PAYMENT_SUCCESS` event, independent of whether the registration can also be
auto-confirmed (see step 11 and §Expiry — captured-after-expiry).

### Step 11 — Registration confirmation
Auto-confirmed (`registered`) as part of the same webhook transaction, **unless** the seat hold
had already expired — in which case the payment is still captured (money is never discarded) but
a `PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY` exception is opened instead of auto-confirming, to avoid
silently overbooking. See §5 State machines and the operations runbook for resolution.

### Step 12 — Status/timeline
```http
GET /api/v1/payment-orders/ORD-.../    → order status, can_pay, can_retry, safe_message
GET /api/v1/payment-orders/ORD-.../timeline → attendee-safe event history with friendly labels
```
Both live-verified. Poll the order endpoint after returning from a checkout redirect (real-gateway
future) or after a `verify` call; use `timeline` for a human-readable "what happened" view in the
attendee UI.

### Step 13 — Expiry/recovery
See §6 Idempotency/concurrency/retry and §7 Expiry below.

---

## 2. State machines (source-verified — no invented statuses)

### Registration status
Source: `migrations/014_registration_holds.sql`, `registration_service.py`,
`payment_service.py`. No CHECK constraint exists on `registrations.status`; these are the only
values any code path writes.

| From | Action | To | Endpoint/Event | Idempotent? |
|---|---|---|---|---|
| (none) | Register, paid event | `seat_held` | `POST /events/{id}/register` | No — 2nd call → 409 |
| (none) | Register, free event | `registered` | `POST /events/{id}/register` | No |
| `seat_held` | Create payment order | `payment_pending` | `POST .../payment-order` | Yes (idempotency key) |
| `payment_pending`/`seat_held`/`payment_verification` | Webhook: `PAYMENT_SUCCESS`, hold not expired | `registered` | webhook | Yes (guarded by `already_confirmed` check) |
| `payment_pending`/`seat_held`/`payment_verification` | Webhook: `PAYMENT_SUCCESS`, hold **expired** | *(unchanged)* + `PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY` exception | webhook | Yes (dedup'd exception) |
| `seat_held`/`payment_pending`/`payment_verification` | Webhook: `PAYMENT_FAILED` or `PAYMENT_CANCELLED` | `payment_failed` | webhook | Yes |
| `seat_held`/`payment_pending` | Webhook: `PAYMENT_PENDING` | `payment_verification` (+ hold extended 30 min) | webhook | Yes |
| `seat_held`/`payment_pending`/`payment_verification`/`payment_failed` | Hold expires (`hold_expires_at < now`) | `cancelled` | lazy check (per-event, on next registration) or explicit sweep (`POST .../expire-registration-holds`) | Yes |
| any non-`registered` in-flight status | Order/attempt lookup finds hold expired | `cancelled` | inline check in `create_order`/`create_attempt` | Yes |

`registered`/`cancelled` are terminal for this state machine (a cancelled registration is not
reused — the attendee registers again from scratch).

### Payment order status
Source: `migrations/015_payment_foundation.sql` CHECK constraint: `created`, `payment_pending`,
`paid`, `expired`, `cancelled`.

| From | Action | To | Endpoint/Event | Idempotent? |
|---|---|---|---|---|
| (none) | `create_order` | `created` | `POST .../payment-order` | Yes |
| `created` | First attempt created | `payment_pending` | `POST .../attempts` | Yes (only fires once, `if order.status == "created"`) |
| `created`/`payment_pending` | Webhook `PAYMENT_SUCCESS`, `amount_paid < final_amount` | `paid` | webhook | Yes (`if` guard prevents re-marking) |
| `created`/`payment_pending` | Past `expires_at`, no in-flight attempt | `expired` | `POST /admin/.../expire-orders` (explicit) or rejected inline on next attempt (no DB write on the inline path) | Yes (`UPDATE...WHERE...RETURNING`, safe under MVCC) |
| — | *(no `cancelled`-producing code path found in the payment order lifecycle beyond the CHECK constraint listing it as a valid value)* | `cancelled` | *(not exercised in current source — reserved value)* | — |

`paid` and `expired` are terminal (an `expired` order is never resurrected — the client must
create a new registration/order). `cancelled` exists in the schema but no current code path
transitions an order into it — do not document a cancel-order endpoint as existing.

### Payment attempt status
Source: `015_payment_foundation.sql` + `016_payment_hardening.sql` (added
`requires_verification`) + `017_widen_attempt_status.sql` (column-width fix only, no new values).
Valid set: `initiated`, `pending`, `requires_verification`, `captured`, `failed`, `cancelled`,
`expired`.

| From | Action | To | Endpoint/Event | Idempotent? |
|---|---|---|---|---|
| (none) | `create_attempt` | `initiated` | `POST .../attempts` | No — blocked by unresolved-attempt guard while another is live |
| `initiated`/`pending` | Webhook `PAYMENT_SUCCESS` | `captured` | webhook | Yes (stale-attempt no-op guard) |
| `initiated`/`pending` | Webhook `PAYMENT_FAILED` | `failed` | webhook | Yes |
| `initiated`/`pending` | Webhook `PAYMENT_PENDING` | `pending` | webhook | Yes |
| `initiated`/`pending` | Webhook `PAYMENT_CANCELLED` | `cancelled` | webhook | Yes |
| `pending` | `verify()` called, ≥30 min elapsed since `initiated_at` | `requires_verification` (+ exception opened) | `POST .../verify` | Yes (dedup'd exception) |
| `pending`/`requires_verification` | Dev resolve to SUCCESS/FAILURE | `captured`/`failed` | `POST /dev/diagnostics/.../resolve` (dev-only) | Yes — builds the same signed webhook, goes through the same idempotent pipeline |

`captured`, `failed`, `cancelled` are terminal for a given attempt (a *new* attempt, not a status
change on the same row, is how retry works — see `attempt_number`). `expired` is a valid CHECK
value with no attempt-level code path found that sets it in current source (order-level expiry
does not currently cascade a status write to in-flight attempts, since an order with a live
attempt is explicitly excluded from the expiry sweep — see §7).

### Payment configuration status
Source: `payment_config_service.py`. Values: `draft`, `published`, `retired`.

| From | Action | To | Endpoint | Idempotent? |
|---|---|---|---|---|
| (none) | `create_draft` (WP1) or dev-diagnostics import (creates+publishes in one step) | `draft` (WP1) or `published` (dev import) | `POST .../payment-configurations` or `POST /dev/diagnostics/.../import` | No |
| `draft` | `publish` | `published` (previous published row → `retired` in the same transaction) | `POST .../publish` | No — 2nd call → `409 payment_configuration_not_a_draft` |

Append-only: publishing never edits an existing row's amounts — a new version is always inserted.
Orders reference a fixed `configuration_id`/`configuration_version` and a frozen
`pricing_snapshot`, so republishing never changes the price of an order already in flight
(live/test-verified: `test_existing_order_retains_old_configuration_after_republish`).

### Payment exception status
Source: `016_payment_hardening.sql`. Values: `open`, `resolved`. Types:
`PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY`, `VERIFICATION_UNRESOLVED`. **No API transitions `open` →
`resolved`** — see security guide §7, Known Gaps. `resolved_by`/`resolution`/`resolved_at` columns
exist on the table but are only ever written by direct DB access today.

---

## 3. Pricing

- **Currency**: INR only, enforced at the DB CHECK-constraint level
  (`payment_configurations.currency = 'INR'`) and re-validated in
  `payment_config_service.validate_configuration`.
- **`base_amount`**: immutable per configuration version — set at draft-creation time, does not
  resync if `events.ticket_price` changes later (a new version is required instead).
- **GST**: `gst_enabled` (bool) + `gst_rate` (0–100) + `gst_mode` (`exclusive` | `inclusive`).
  - `exclusive`: `tax_amount = round(base_amount * gst_rate / 100)`; `final = base + tax (+ fee)`.
  - `inclusive`: `base_amount` already contains tax; `taxable_amount = round(base_amount / (1 +
    gst_rate/100))`, `tax_amount = base_amount - taxable_amount`; `final = base_amount (+ fee)`
    (tax is not added again).
  - Rounding: `Decimal.quantize(Decimal("0.01"), ROUND_HALF_UP)` throughout — never float
    arithmetic.
- **Convenience fee**: `convenience_fee_enabled` + `convenience_fee_type` (`fixed` | `percentage`)
  + `convenience_fee_value`. Percentage fee is applied to `(base_amount + tax_amount)` — the
  payable total *before* the fee itself, not to `base_amount` alone. Source docstring notes this
  is "a documented assumption, not an exercised path" — no live configuration in this codebase
  currently uses a percentage fee.
- **`payment_configurations.version`**: append-only integer, unique per `(configuration_key,
  version)`. Exactly one row per event may be `status='published'` at a time
  (`uq_payment_configurations_active_event`).
- **Pricing snapshot**: every order stores the full computed breakdown as `pricing_snapshot`
  JSONB at creation time — immutable regardless of later configuration changes.
- **Server-authoritative amount**: the client supplies nothing that affects price. Confirmed
  live (§1 Step 3) and by source (`create_order`/`get_pricing` always recompute from the DB
  config row) and test (`test_client_supplied_amount_gst_currency_are_ignored`).
- **Discounts/coupons/promo codes: NOT IMPLEMENTED.** No schema column, request field, or service
  logic for any discount mechanism exists anywhere in the payment source.

---

## 4. Idempotency / concurrency / retry

| Concern | Mechanism | Evidence |
|---|---|---|
| Order idempotency | Client-supplied `idempotency_key`; DB-unique `(payer_firebase_uid, idempotency_key)` | Live-verified repeat call → same order |
| Duplicate registration | `uq_registrations_active` partial unique index across in-flight-or-confirmed statuses | `test_concurrent_double_click_registration_only_one_succeeds` |
| Concurrent order creation (double-click) | `uq_payment_orders_active_registration` + `UniqueViolationError` fallback re-read | `test_five_concurrent_order_creation_requests_produce_one_order` (5 concurrent → 1 order) |
| Unresolved-attempt guard | Partial unique index `uq_payment_attempts_unresolved_per_order` (migration 020) | `test_five_concurrent_attempt_creation_requests_only_one_succeeds` — closed a real 2-of-5 race found while adding this test |
| Webhook dedupe/replay | `uq_payment_webhook_events_gateway_event` + freshness window | §Webhook security in the security guide |
| Concurrent webhook delivery of the same payload | `SELECT ... FOR UPDATE` on the order row | `test_concurrent_webhook_delivery_of_identical_payload_captures_once` |
| Concurrent config publish | `uq_payment_configurations_active_event` + `UniqueViolationError` → `409` | `test_concurrent_publish_exactly_one_winner` |
| Concurrent expiry sweep | Plain `UPDATE ... WHERE ... RETURNING`, safe under Postgres MVCC, no explicit lock needed | `test_concurrent_expiry_calls_no_double_processing`, `test_concurrent_script_invocations_are_safe` |

**Expected client behavior**:
- **Timeout**: retry the *same* request with the *same* idempotency key (order creation) — safe.
  For attempt creation, do **not** blindly retry; check `GET .../payment-orders/{id}` first —
  `has_unresolved_attempt` will reject a second attempt with `409 payment_attempt_active` if the
  first one is still in flight, which is the correct signal to poll rather than retry.
- **409 responses**: never silently retried by the client — each 409 detail string maps to a
  specific recovery action (see error catalog).
- **Pending**: poll `POST .../verify`, not `POST .../attempts` again.
- **Verification**: same — poll, don't retry payment.
- **Already-paid** (`409 payment_already_completed` / `409 payment_order_not_payable`): stop:
  fetch the order and show the confirmed state; never re-attempt.
- **Expiry**: restart the registration flow from step 2 — an expired order/hold has no "resume"
  path.

---

## 5. Integration examples (live-verified 2026-08-22)

### 5.1 Happy path
Register → pricing → order → attempt(SUCCESS) → order shows `paid`/`registered` → timeline shows
5 friendly-labeled entries. Full request/response bodies are in `PAYMENT_API_REFERENCE.md` §1–§4
and `PAYMENT_API_EXAMPLES.http`.

### 5.2 Failure → retry → success
```
POST .../attempts {"scenario":"FAILURE"}  → 201 attempt_number=1, status=failed
GET  .../payment-orders/{id}              → status=payment_pending, registration_status=payment_failed,
                                             can_retry=true, safe_message="Payment was not completed..."
POST .../attempts {"scenario":"SUCCESS"}  → 201 attempt_number=2, status=captured
GET  .../payment-orders/{id}              → status=paid, registration_status=registered
POST .../attempts {"scenario":"SUCCESS"}  → 409 payment_order_not_payable  (terminal order rejects further attempts)
```
Live-verified exactly as above, including the terminal-order rejection.

### 5.3 Pending → verification
```
POST .../attempts {"scenario":"PENDING"}     → 201 status=pending
GET  .../payment-orders/{id}                 → registration_status=payment_verification, can_retry=false,
                                                safe_message="Your payment confirmation is being verified.
                                                Please do not pay again."
POST .../payment-attempts/{id}/verify        → 200 status=pending  (checked promptly — under 30 min)
POST /dev/diagnostics/.../resolve {"outcome":"SUCCESS"}  (dev-only path to resolve a stuck sandbox pending)
                                              → order_status=paid, registration_status=registered
```
Live-verified exactly as above.

### 5.4 Returning attendee using `latest_order_id`
`GET /api/v1/events/{id}/my-registration` and `GET /api/v1/my/registrations` both include
`latest_order_id` on the registration payload — the correct field for a client to resume an
in-progress payment after closing and reopening the app, rather than re-deriving it from a
locally-cached order ID (which could be stale after a retry created a second order under a
different idempotency key... though in practice `uq_payment_orders_active_registration` prevents
more than one active order existing at once, so `latest_order_id` and the client's own cached ID
should always agree while an order is active). Live-verified: `latest_order_id: null` immediately
after registration, `"ORD-IinxJRey-TyC"` after order creation, unchanged through capture.

### 5.5 Expiry
See §7 below — exercised via `tests/test_payment_lifecycle_expiry.py` (8/8 passing) and
`tests/test_payment_scheduler.py` (9/9 passing); not independently re-run live in this pass
because it requires backdating `hold_expires_at`/`expires_at` via direct DB access (the same
approach the test suite itself uses — see `_force_hold_expired`/`_force_attempt_stale` in
`tests/test_payments.py`), which is test-only tooling, not something a real client can do.

### 5.6 Cross-user denial
`GET /api/v1/payment-orders/{alumni1's order}` with `alumni2`'s bearer token → `404
payment_order_not_found`. Live-verified (§2 in the security guide).

---

## 6. Expiry and recovery

Two independent sweeps, both idempotent and concurrency-safe (plain `UPDATE ... WHERE ...
RETURNING`, no explicit locking needed under Postgres MVCC):

- **Order expiry**: `created`/`payment_pending` orders past `expires_at` **with no in-flight
  attempt** (`initiated`/`pending`/`requires_verification`) → `expired`. An order with a live
  attempt is protected even past its nominal expiry — the in-flight payment must resolve first.
  `paid`/`cancelled`/already-`expired` orders are never touched (captured funds are never at
  risk from this sweep).
- **Registration hold expiry**: `seat_held`/`payment_pending`/`payment_verification`/
  `payment_failed` rows past `hold_expires_at` → `cancelled`. `registered` rows are never matched.

Two invocation paths, both calling the identical `payment_lifecycle_service` functions (no
duplicated logic): `POST /admin/payments/lifecycle/expire-{orders,registration-holds}`
(`platform_admin`-only, manual/on-demand — live-verified `200 {"expired_count":0,...}` with no
eligible rows at verification time) and `scripts/run_payment_lifecycle_sweep.py` (intended for an
external cron/scheduler — **no scheduler is wired up in this repository**; ops must provide one).

**Captured-after-expiry**: if a `PAYMENT_SUCCESS` webhook lands after a seat hold expired,
financial state is preserved unconditionally (`amount_paid`/order `paid` still happen) but
registration auto-confirmation is skipped in favor of opening a
`PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY` exception — money is never silently discarded, and a seat is
never silently re-granted past expiry (possible overbooking). Resolution today requires the
runbook's manual process (§Payment exceptions).
