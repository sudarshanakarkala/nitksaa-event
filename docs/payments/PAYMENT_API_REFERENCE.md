# NITKSAA Event — Payment API Reference

Source-verified against `backend/app/api/payments.py`, `admin_payments.py`, `dev_diagnostics.py`
(payment routes), `app/services/{payment_service,payment_lifecycle_service,pricing_service,
payment_config_service}.py`, `app/repositories/{payment_repository,registration_repository,
payment_role_repository}.py`, `app/gateways/{base,registry,deterministic_sandbox}.py`,
`app/middleware/admin_auth.py`, `app/config.py`, `app/schemas/{payments,payment_admin}.py`, and
migrations `014_registration_holds.sql` … `020_payment_attempt_concurrency_guard.sql`. Cross-checked
against the live OpenAPI schema (`GET /openapi.json`) on 2026-08-22 — zero drift (see the
verification report for the diff table).

All endpoints are mounted with no additional path prefix beyond what's shown — `app/main.py`
registers `payments.router`, `admin_payments.router`, `dev_diagnostics.router` with no extra
`prefix=` argument at the `include_router` call (the prefixes below are already baked into each
router's own `APIRouter(prefix=...)`).

Currency is INR only, everywhere. Every money amount is a `Decimal`-backed `NUMERIC(14,2)` on
the wire as a JSON string (e.g. `"118.00"`), never a float.

---

## 1. Attendee / registration APIs

These sit in `app/api/registrations.py` and are documented here because payment status
(`latest_order_id`, `hold_expires_at`) flows through the registration response.

### `POST /api/v1/events/{event_id}/register`
- **Source**: `app/api/registrations.py` → `registration_service.register_for_event`
- **Purpose/audience**: attendee-facing. Creates a registration. For a paid event this creates a
  `seat_held` row and starts the seat-hold clock; for a free event it creates a `registered` row
  directly and sends the confirmation email inline.
- **Auth**: `get_current_user` (Firebase-derived bearer access token, see §Auth documentation).
- **Ownership**: none to check yet (creates the caller's own row); scope is `firebase_uid` from
  the token.
- **Headers**: `Authorization: Bearer <token>`.
- **Path params**: `event_id: int`.
- **Request body** (`RegisterRequest`): `{"attendee_note"?: string}`.
- **Response 201** (`RegistrationResponse`, paid event):
  ```json
  {
    "registration_id": 5665, "registration_number": "NITKSAA-2026-005665",
    "event_id": 14760, "firebase_uid": "TEST_ALUMNI_UID_001", "ref_id": "NITK2020CS001",
    "status": "seat_held", "fullname_snapshot": "Ravi Shankar Test",
    "email_snapshot": "ravi.test@nitksaa.dev", "phone_snapshot": "+91-9876543210",
    "batch_year_snapshot": 2020, "branch_snapshot": "Computer Science",
    "attendee_note": "doc verification", "registered_at": "2026-08-22T15:13:49.458051Z",
    "cancelled_at": null, "confirmation_email_status": "pending",
    "confirmation_email_sent_at": null, "hold_expires_at": "2026-08-22T15:28:49.458734Z",
    "join_url": null, "event": {"event_id": 14760, "title": "...", "...": "..."},
    "updated_at": null, "latest_order_id": null
  }
  ```
  Live-verified 2026-08-22 (exact payload above, redacted event fields).
- **Errors**: `403 alumni_only` / `403 alumni_not_found` / `403 alumni_not_active` (not an active
  alumni identity) · `404 event_not_found` · `409 event_not_published` · `409
  registration_not_open_yet` / `409 registration_closed` · `409 payment_not_configured` (paid
  event with no published `payment_configurations` row) · `409 already_registered` · `409
  event_full`.
- **Idempotency**: none — a second call while a live registration exists returns `409
  already_registered` (live-verified). Concurrency: `SELECT ... FOR UPDATE` on the `events` row
  serializes concurrent registration attempts for the same event
  (`test_concurrent_double_click_registration_only_one_succeeds`).
- **Audit**: `registration_seat_held` (paid) or `registration_created` (free), plus
  `EMAIL_SENT`/`EMAIL_FAILED` analytics rows for the free path.
- **State transition**: (none) → `seat_held` (paid) or (none) → `registered` (free).
- **Security notes**: capacity/uniqueness enforced under a row lock, not just an application
  check; alumni identity is verified against `alumni_db` by `ref_id`, not trusted from the token
  body's display fields.

### `GET /api/v1/events/{event_id}/my-registration`
Returns the caller's latest registration row for the event (any status), including
`latest_order_id`. 404 `registration_not_found` if none exists. Auth: `get_current_user`.
Live-verified: returns `status: "registered"`, `latest_order_id: "ORD-..."` after payment capture.

### `GET /api/v1/my/registrations`
Returns all of the caller's registrations across all events (`MyRegistrationsListResponse`).
Auth: `get_current_user`.

### `GET /api/v1/events/{event_id}/registration-eligibility`
Pre-flight check (`eligible` / `already_registered` / `full` / `not_open_yet` / `closed` /
`ineligible`) that never mutates state. Includes `payment_required` and `ticket_price`. Auth:
`get_current_user`.

---

## 2. Pricing

### `GET /api/v1/events/{event_id}/payment-pricing`
- **Source**: `app/api/payments.py` → `payment_service.get_pricing` → `pricing_service.calculate_price`.
- **Purpose**: attendee-facing, server-authoritative price preview before registering/paying.
- **Auth**: `get_current_user`. No ownership check (pricing is public to any authenticated user,
  event-scoped only).
- **Response 200** (`PricingBreakdownResponse`), live-verified:
  ```json
  {
    "event_id": 14760, "configuration_key": "doc-DOC1787411618", "currency": "INR",
    "base_amount": "100.00", "gst_enabled": true, "gst_rate": "18.00", "gst_mode": "exclusive",
    "tax_amount": "18.00", "convenience_fee_enabled": false, "convenience_fee": "0.00",
    "final_amount": "118.00",
    "line_items": [
      {"label": "Registration fee", "amount": "100.00"},
      {"label": "GST (18.00%)", "amount": "18.00"}
    ]
  }
  ```
- **Errors**: `409 payment_not_configured` — no `payment_configurations` row with
  `status='published'` for this event. Live-verified via `test_pricing_for_unconfigured_event_returns_409`.
- **Idempotency**: pure read, always safe to repeat; never mutates state.
- **Security notes**: the client supplies nothing that influences price — `base_amount`,
  `gst_rate`, `gst_mode`, `convenience_fee_*` all come from the published DB row. Client-supplied
  amount/GST/currency fields are ignored end-to-end
  (`test_client_supplied_amount_gst_currency_are_ignored`).

---

## 3. Payment orders

### `POST /api/v1/registrations/{registration_id}/payment-order`
- **Source**: `app/api/payments.py` → `payment_service.create_order`.
- **Purpose**: attendee-facing. Creates (or idempotently returns) the payment order for one
  registration.
- **Auth**: `get_current_user`. **Ownership**: `registration.firebase_uid == caller` — else `404
  registration_not_found` (existence-hiding: a registration owned by someone else 404s exactly
  like one that doesn't exist).
- **Request body** (`CreatePaymentOrderRequest`): `{"idempotency_key": string (8–128 chars)}` —
  client-generated, e.g. a UUID.
- **Response 201** (`PaymentOrderResponse`), live-verified:
  ```json
  {
    "order_id": "ORD-IinxJRey-TyC", "registration_id": 5665, "event_id": 14760,
    "currency": "INR", "base_amount": "100.00", "tax_amount": "18.00",
    "convenience_fee": "0.00", "final_amount": "118.00", "amount_paid": "0.00",
    "outstanding_amount": "118.00", "status": "created", "registration_status": "payment_pending",
    "expires_at": "2026-08-22T15:29:04.156142Z", "can_pay": true, "can_retry": true,
    "safe_message": "Complete payment to confirm your registration."
  }
  ```
- **Errors**: `404 registration_not_found` · `409 idempotency_key_conflict` (same key reused for
  a different registration) · `409 registration_not_payable` (registration not in
  `seat_held`/`payment_pending`/`payment_failed`) · `409 seat_hold_expired` (also cancels the
  registration) · `409 payment_not_configured` · `409 payment_order_creation_conflict` (rare
  losing-race fallback — see Concurrency below).
- **Idempotency**: two mechanisms, both DB-enforced (not just application checks):
  1. Same `(payer_firebase_uid, idempotency_key)` → same order returned, `201` both times
     (live-verified: identical body on repeat call). Enforced by
     `uq_payment_orders_idempotency`.
  2. An already-active order (`created`/`payment_pending`) for the same registration is returned
     as-is even with a *different* idempotency key. Enforced by
     `uq_payment_orders_active_registration`.
- **Concurrency**: two concurrent calls with the same key can both pass the pre-insert idempotency
  check before either commits; the loser catches `UniqueViolationError` and re-reads instead of
  raising a 500 (`test_five_concurrent_order_creation_requests_produce_one_order` — 5 concurrent
  calls, exactly 1 order).
- **Audit**: `payment_order_created`.
- **State transition**: registration `seat_held` → `payment_pending`; order (none) → `created`.

### `GET /api/v1/payment-orders/{order_id}`
- **Source**: `payment_service.get_order`. **Ownership**: `order.payer_firebase_uid == caller`,
  else `404 payment_order_not_found`. Live-verified cross-user denial (§Integration examples).
- **Response 200**: same `PaymentOrderResponse` shape as above; `can_pay`/`can_retry`/
  `safe_message` are derived server-side from `status` + `registration_status` (see
  `payment_service._order_view`) — never compute these client-side.
- **`safe_message` by state** (source-verified, `_order_view`): `paid` → "Payment complete. Your
  registration is confirmed."; `expired` → "This payment session expired. Please register
  again."; `cancelled` → "This order was cancelled."; `registration_status ==
  payment_verification` → "Your payment confirmation is being verified. Please do not pay
  again."; `registration_status == payment_failed` → "Payment was not completed. Your
  registration details are saved — you may retry."; else → "Complete payment to confirm your
  registration."

---

## 4. Payment attempts

### `POST /api/v1/payment-orders/{order_id}/attempts`
- **Source**: `payment_service.create_attempt`.
- **Purpose**: attendee-facing. Starts a payment attempt against the active gateway
  (`app.gateways.registry.get_active_gateway`, server-selected — never client-selected).
- **Auth + ownership**: same as `GET .../payment-orders/{order_id}`.
- **Request body** (`CreatePaymentAttemptRequest`): `{"scenario"?: string}` — **dev/sandbox-only
  field**; a real gateway would not accept this (see §Gateway abstraction). Default `"SUCCESS"`.
  One of `SUCCESS | FAILURE | PENDING | CANCELLED | DELAYED_SUCCESS | DELAYED_FAILURE`.
- **Response 201** (`PaymentAttemptResponse`) — for an immediate scenario (`SUCCESS`, `FAILURE`,
  `PENDING`, `CANCELLED`) the response already reflects the post-webhook outcome, because the
  sandbox's webhook is processed synchronously before the HTTP response is built:
  ```json
  {
    "attempt_id": "ATT-sMWzjpgVOm6t", "order_id": "ORD-IinxJRey-TyC", "attempt_number": 1,
    "gateway": "deterministic_sandbox", "status": "captured", "scenario": "SUCCESS",
    "initiated_at": "2026-08-22T15:14:04.252047Z"
  }
  ```
  Live-verified (`SUCCESS`), and `FAILURE` → `status: "failed"`, `PENDING` → `status: "pending"`
  (all live-verified 2026-08-22). `DELAYED_*` scenarios return `status: "initiated"` immediately;
  the webhook fires ~2s later via `BackgroundTasks` (see `DELAYED_SCENARIO_DELAY_SECONDS`).
- **Errors**: `422 unsupported_scenario` (scenario not in the active gateway's
  `supported_scenarios`; source-verified, `payment_service.py:267`) · `503
  payment_gateway_unavailable` (misconfigured/disabled gateway — fail-closed, never falls back to
  another gateway; `test_attempt_creation_fails_closed_when_gateway_mode_is_misconfigured`) ·
  `404 payment_order_not_found` · `409 payment_order_not_payable` (live-verified: attempting on a
  `paid` order) · `409 payment_order_expired` · `409 payment_already_completed` · `409
  seat_hold_expired` (also cancels the registration) · `409 payment_attempt_active` /
  `409 payment_verification_in_progress` (an unresolved attempt already exists — see Retry
  blocking below).
- **Retry blocking**: `has_unresolved_attempt()` blocks a new attempt while any prior attempt on
  the order is `initiated`/`pending`/`requires_verification`. Enforced at the DB level by the
  partial unique index `uq_payment_attempts_unresolved_per_order` (migration 020) — the
  application check is a fast path, the index is the real guard (closes a genuine 2-of-5
  concurrent-request race found during that sprint's testing;
  `test_five_concurrent_attempt_creation_requests_only_one_succeeds`).
- **Audit**: `payment_attempt_initiated`, then whatever the synchronously-processed webhook emits
  (`payment_captured` / `payment_failed` / `payment_pending` / `payment_cancelled`).
- **State transition**: order `created` → `payment_pending` (first attempt only); attempt (none)
  → `initiated` → (webhook-driven) `captured`/`failed`/`pending`/`cancelled`.

### `POST /api/v1/payment-attempts/{attempt_id}/verify`
- **Source**: `payment_service.verify_attempt`.
- **Purpose**: attendee-facing controlled status re-check for a `pending`/`requires_verification`
  attempt. In Phase 0 there is no real external gateway to query — this re-reads current DB state
  (a webhook may have already resolved it) and, if `pending` for
  ≥`PENDING_VERIFICATION_WINDOW_MINUTES` (30 min), escalates to `requires_verification` and opens
  a `VERIFICATION_UNRESOLVED` exception.
- **Auth + ownership**: `order.payer_firebase_uid == caller`, else `404
  payment_attempt_not_found`.
- **Errors**: `404 payment_attempt_not_found` · `409 attempt_not_verifiable` (attempt is not
  `pending`/`requires_verification`).
- **Response 200**: `PaymentAttemptResponse`, live-verified (`PENDING` scenario, checked
  immediately — status stays `pending` since <30 min elapsed).
- **Side effect**: `record_verification_check` always bumps `verification_check_count` and
  `verification_checked_at`, regardless of outcome.
- **Idempotency**: safe to call repeatedly; each call is a fresh read plus (conditionally) one
  escalation, which itself is idempotent (`get_open_exception` dedups the exception row).

---

## 5. Webhooks

### `POST /api/v1/payment-gateways/{gateway}/webhook`
- **Source**: `app/api/payments.py::receive_payment_webhook` → `payment_service.process_webhook`.
- **Purpose**: gateway-facing (server-to-server). **Unauthenticated by design** — no bearer token
  (a real gateway cannot present one); the raw body is `bytes`, integrity/authenticity comes
  entirely from `X-Sandbox-Signature` HMAC verification, not from any session/cookie/JWT.
- **Path param**: `gateway` — validated against `app.gateways.registry` (not a hardcoded string
  match); an unregistered or environment-disabled gateway both return `404 unknown_gateway`
  (existence-hiding — the response can't be used to enumerate which gateway names are registered
  vs merely disabled). Live-verified.
- **Headers**: `X-Sandbox-Signature: <hex hmac-sha256>` (sandbox-specific header name; a future
  real-gateway adapter would define its own signature header inside its own `verify_webhook`).
- **Body**: raw JSON, canonicalized as `json.dumps(payload, sort_keys=True,
  separators=(",",":"))` before signing — see §Webhooks (deep dive) below.
- **Response 200** always (never a 4xx/5xx for a well-formed-but-rejected delivery — gateways
  expect a 2xx ack regardless of business outcome, and 404 is reserved for the gateway-name
  segment only): `WebhookAckResponse {status, processing_status}` where `processing_status` ∈
  `processed | duplicate | rejected`.
- **See §Webhooks below** for the full signature/freshness/replay/amount-verification pipeline
  and the rejection-reason table.

---

## 6. Timelines

### `GET /api/v1/payment-orders/{order_id}/timeline`
- **Source**: `payment_service.get_timeline`. **Attendee-safe view**: friendly `label` strings
  only (from `_ATTENDEE_TIMELINE_LABELS`); internal/security events (invalid-signature,
  amount-mismatch, stale-attempt no-ops, unknown-order rejections) are excluded entirely, and
  `detail.order_id` is stripped even when present. Live-verified — see §1 example. Auth +
  ownership: same as `GET .../payment-orders/{order_id}`.

### `GET /api/v1/dev/diagnostics/payments/orders/{order_id}/technical-timeline` (developer/admin)
- **Source**: `dev_diagnostics.py::get_payment_technical_timeline` → `payment_service.
  get_developer_timeline`. Full unfiltered audit feed, every row, raw `context` JSON intact,
  `label: null`. **No ownership check** — gated by dev-diagnostics access only (see §10). Doubles
  as the admin timeline in Phase 0: "no distinct admin role model exists yet for payments, so
  both use this same dev-diagnostics-gated view" (source docstring) — there is no
  platform-role-gated production timeline endpoint.

---

## 7. Admin payment/configuration (`app/api/admin_payments.py`, prefix `/api/v1/admin`)

### WP1 — configuration lifecycle (draft → validate → publish)

| Method/Path | Role | Purpose |
|---|---|---|
| `POST /events/{event_id}/payment-configurations` | `require_event_admin` | Create a `draft` config row (422 with `{"errors":[...]}` on validation failure, from `payment_config_service.validate_configuration`). |
| `GET /events/{event_id}/payment-configurations` | `require_event_payment_read_access` | Full append-only version history, newest first. |
| `GET /events/{event_id}/payment-configurations/{configuration_id}` | `require_event_payment_read_access` | One config row. `404` if wrong event_id. |
| `POST /events/{event_id}/payment-configurations/{configuration_id}/validate` | `require_event_admin` | Dry-run validation of a draft — same `validate_configuration()` function the write path uses, so a dry run can never disagree with the real publish check. |
| `POST /events/{event_id}/payment-configurations/{configuration_id}/publish` | `require_event_admin` | Draft → published; retires the event's previously-published row in the same transaction; flips `events.is_free=false`/`ticket_price`. `409 payment_configuration_not_a_draft` if not currently a draft. `409 payment_configuration_publish_conflict` on a losing concurrent-publish race (DB-enforced via `uq_payment_configurations_active_event`; `test_concurrent_publish_exactly_one_winner` — exactly one of N concurrent publishes wins). |

All live-verified end-to-end 2026-08-22 (draft → validate → publish → history-shows-both-versions
→ re-publish rejected with 409).

### WP2 — payment RBAC role management

| Method/Path | Role | Purpose |
|---|---|---|
| `POST /admin/payment-roles` | `platform_admin` only | Grant a platform-wide role (`platform_admin`\|`finance_operator`\|`auditor`\|`support`). `409 payment_role_already_active` if already granted. `404 firebase_uid_not_found` if no `event_users` row. |
| `POST /admin/payment-roles/{grant_id}/revoke` | `platform_admin` only | Soft-revoke (sets `revoked_at`/`revoked_by`; row kept for audit history, re-grantable after). `404 payment_role_grant_not_found`. |
| `GET /admin/payment-roles` | `platform_admin` or `auditor` | List all currently-active platform role grants. |
| `POST /events/{event_id}/payment-admins` | `platform_admin` only | Grant event-scoped `event_admin` (upsert into `event_members`). `404 event_not_found`. |

Live-verified: non-admin caller → `403 payment_role_required` on both `gateway-config` and
`expire-orders` (representative of every `require_platform_role` route).

### WP4 — explicit expiry-sweep triggers

| Method/Path | Role | Purpose |
|---|---|---|
| `POST /admin/payments/lifecycle/expire-orders` | `platform_admin` only | Manually trigger `payment_lifecycle_service.expire_stale_payment_orders`. Returns `{expired_count, expired_order_ids}`. Live-verified: `200 {"expired_count":0,"expired_order_ids":[]}` (no eligible rows at test time). |
| `POST /admin/payments/lifecycle/expire-registration-holds` | `platform_admin` only | Same, for stale seat holds. Returns `{expired_count, expired_registration_ids}`. Live-verified. |

Same underlying service functions the operational sweep script
(`scripts/run_payment_lifecycle_sweep.py`) calls in-process — see §Expiry.

### Gateway registry diagnostics (read-only)

### `GET /api/v1/admin/payments/gateway-config`
- **Role**: `platform_admin`, `finance_operator`, `auditor`, or `support`.
- **Response 200**, live-verified:
  ```json
  {
    "environment": "development", "configured_gateway_mode": "deterministic_sandbox",
    "active_gateway": "deterministic_sandbox",
    "gateways": [{
      "name": "deterministic_sandbox", "enabled": true,
      "capabilities": ["create_payment", "process_webhook", "verify_webhook"],
      "supported_scenarios": ["CANCELLED", "DELAYED_FAILURE", "DELAYED_SUCCESS", "FAILURE", "PENDING", "SUCCESS"]
    }]
  }
  ```
- **Security**: no secrets in the payload — `payment_sandbox_signing_secret` is read inside
  adapter methods only, never surfaced here (`test_gateway_config_diagnostics_exposes_no_secrets`,
  and live-verified above — no `secret` key present).

---

## 8. Payment exceptions (developer-gated read; no production resolve action)

### `GET /api/v1/dev/diagnostics/payments/exceptions`
- **Source**: `dev_diagnostics.py::list_payment_exceptions`. Optional `?status=open|resolved`
  query filter. Returns every `payment_exceptions` row (`PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY`,
  `VERIFICATION_UNRESOLVED`). Live-verified (returned 387 accumulated rows in the local dev DB at
  verification time — see the verification report for why that count is large and expected).
- **No resolve endpoint exists anywhere in the API.** Source docstring: "No resolve action here
  yet — an admin finance portal is explicitly out of scope for Phase 0; this is the read-only
  visibility half of 'admin-visible exception'." **Production resolution of `payment_exceptions`
  rows is NOT IMPLEMENTED** — today this requires a direct DB update (`status='resolved'`,
  `resolved_by`, `resolution`) by an operator with DB access; see the runbook.

---

## 9. Developer diagnostics (`app/api/dev_diagnostics.py`, prefix `/api/v1/dev/diagnostics`)

**DEVELOPER ONLY — every route in this section is gated by two independent checks**, both of
which fail closed to `404 not_found` (not 403 — existence-hiding: production deployments should
not be able to distinguish "wrong role" from "this route doesn't exist"):
1. `_require_development()` — `settings.app_env == "development"` (`APP_ENV` env var).
2. `_require_payment_diagnostics_enabled()` — `settings.payment_diagnostics_enabled` (default
   `True`, env var `PAYMENT_DIAGNOSTICS_ENABLED`) — an independent kill switch even inside a dev
   environment.

Auth within this gate is `_get_dev_user`: either `X-Dev-User: admin` (a fixed, hardcoded dev
identity — **not a real credential check**) or a real access token decoded the normal way. This
is a development convenience, never a production authorization mechanism — do not confuse it with
`app.middleware.admin_auth`, which is the real Firebase-JWT-backed RBAC used by
`admin_payments.py`/`admin_events.py`.

| Method/Path | Purpose |
|---|---|
| `POST .../payments/configuration/import` | Upsert a `published` payment configuration for an event in one call (bypasses the WP1 draft/validate/publish workflow — dev/demo convenience only). Flips `events.is_free`/`ticket_price` to match. Live-verified. |
| `GET .../payments/orders/{order_id}/technical-timeline` | See §6 above. |
| `GET .../payments/exceptions` | See §8 above. |
| `POST .../payments/attempts/{attempt_id}/resolve` | Resolves a live `pending`/`requires_verification` attempt to `SUCCESS`/`FAILURE` by building and processing the exact signed webhook delivery the sandbox gateway would eventually send — the only way to do this over HTTP, since the signing secret never leaves the backend. `409 attempt_not_resolvable` if not currently pending/requires_verification. Live-verified end-to-end (`PENDING` → `resolve SUCCESS` → order `paid`, registration `registered`). |
| `GET .../payments` | **Scenario runner.** Creates and cleans up its own throwaway paid event, then runs: pricing check, seat-held registration, order creation + idempotency, failed payment, retry success (2nd attempt), duplicate-webhook-is-a-no-op, cross-user access denial. Returns a structured pass/fail report per step (`{status, category, total, passed, failed, results[]}`). This is the "scenario runner" referenced elsewhere in this doc set — it exercises the real services end-to-end, not a re-implementation. |

**Security warning**: `import_payment_configuration` and `resolve_pending_payment_attempt` are
real, unauthenticated-in-practice (`X-Dev-User: admin` requires no proof of identity) write paths
into financial state. They must never be reachable outside `APP_ENV=development`. This is
enforced today only by the two checks above — there is no additional network-layer restriction
documented in this codebase (see §Security guide, Known Gaps).

---

## 10. Auth documentation

See `PAYMENT_API_SECURITY_GUIDE.md` for the full attendee identity model, bearer header format,
ownership/403/404 conventions, and the complete admin role matrix.

---

## 11. Gateway foundation

See `PAYMENT_API_SECURITY_GUIDE.md` §Gateway abstraction for `PaymentGateway`, the registry,
the sandbox adapter, and the IMPLEMENTED/NOT IMPLEMENTED/FUTURE capability matrix.
