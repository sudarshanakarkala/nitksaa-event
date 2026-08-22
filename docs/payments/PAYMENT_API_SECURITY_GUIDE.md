# NITKSAA Event — Payment API Security Guide

Source-verified 2026-08-22 against `app/middleware/{auth,admin_auth}.py`, `app/api/dev_diagnostics.py`,
`app/gateways/*.py`, `app/config.py`, and the RBAC/webhook-freshness/gateway-foundation test suites
(`tests/test_payment_rbac.py`, `tests/test_payment_webhook_freshness.py`,
`tests/test_payment_gateway_foundation.py` — 100/100 passing at verification time).

---

## 1. Attendee identity model

- **Bearer header**: `Authorization: Bearer <access_token>`, verified by `fastapi.security.
  HTTPBearer` (`app/middleware/auth.py:_bearer`).
- **Token type**: this is **not** a raw Firebase ID token. It is a backend-issued JWT
  (`app.middleware.auth.make_access_token`, HS256, signed with `settings.secret_key`), minted by
  `POST /api/v1/auth/firebase` after that endpoint verifies a real Firebase ID token
  server-side (`verify_firebase_token`). A client authenticates once against Firebase, exchanges
  the Firebase token for this backend access token, then uses the backend token for every
  subsequent call — including all payment/registration endpoints.
- **`get_current_user` dependency** (used by every attendee-facing payment/registration route):
  decodes the token, re-fetches the current `event_users` row by `firebase_uid` (so a suspended
  account is caught even with a still-valid token — `403 account_suspended`), and returns
  `{firebase_uid, email, fullname, user_type, ref_id, graduation_year}`. **Nothing about role or
  permission is read from the token payload itself** — `user_type`/`ref_id` are re-resolved from
  the DB on every request, not trusted from stale claims.
- **No Authorization header** → `403 "Not authenticated"` from FastAPI's `HTTPBearer` (live-verified,
  `GET /api/v1/events/{id}/payment-pricing` with no header). An invalid/expired token →
  `401 invalid_or_expired_token` (`decode_access_token`).

## 2. Ownership rules and the 403-vs-404 convention

**This codebase deliberately never returns 403 for cross-user payment resource access — it
returns 404**, treating "exists but isn't yours" the same as "doesn't exist" (existence-hiding, so
an attacker enumerating order/attempt IDs learns nothing about which IDs are real):

| Resource | Ownership check | Denial code |
|---|---|---|
| `payment_order` (`GET`/`POST attempts`/`GET timeline`) | `order.payer_firebase_uid == caller.firebase_uid` | `404 payment_order_not_found` |
| `payment_attempt` (`POST verify`) | via its parent order's `payer_firebase_uid` | `404 payment_attempt_not_found` |
| `registration` (`POST payment-order`) | `registration.firebase_uid == caller.firebase_uid` | `404 registration_not_found` |

Live-verified: `alumni2`'s token against `alumni1`'s order returns `404
payment_order_not_found` (not 403). Source: `test_predictable_id_enumeration_fails` and
`test_no_secret_leakage_in_responses` additionally assert no internal integer IDs or other users'
data leak through these paths. Public identifiers (`ORD-...`, `ATT-...`) are opaque
`secrets.token_urlsafe(9)`-derived strings (`payment_service._public_id`) — internal `BIGSERIAL`
IDs are never exposed in any attendee-facing response.

The one 403 in the attendee-facing surface is `account_suspended` (an authenticated-but-blocked
account), which is a genuinely different case from ownership.

## 3. Admin roles

Two independent role systems exist; **admin_payments.py and admin_events.py share the same
`app.middleware.admin_auth` module** — "manage this event" is one permission, not duplicated per
surface.

### Platform-wide roles (`payment_platform_roles` table, migration 018)

| Role | Granted via | Scope |
|---|---|---|
| `platform_admin` | Bootstrap: `PLATFORM_ADMIN_FIREBASE_UIDS` env var (the only way the very first admin exists, since no admin identity can grant the role via API yet). Every subsequent grant: `POST /admin/payment-roles`. | Global — satisfies **every** `require_platform_role(...)` check and `require_event_admin`/`require_event_payment_read_access` for **every** event, regardless of the specific roles listed. |
| `finance_operator` | `POST /admin/payment-roles` (platform_admin only) | Payment-operational: read access via `require_event_payment_read_access`; not `require_event_admin` (cannot manage general event data). |
| `auditor` | Same | Same read access as `finance_operator`, plus explicitly allowed on `GET /admin/payment-roles` (role-grant visibility) — `finance_operator`/`support` are not. |
| `support` | Same | Same read access as `finance_operator`. |

`_resolve_platform_roles` unions the bootstrap-list check with live `payment_platform_roles` rows
— a caller can hold a role from either source simultaneously; `platform_admin` from either source
always satisfies any `require_platform_role(...)` check (`"platform_admin" in roles` short-circuits
the allowed-set check in `require_platform_role`).

### Event-scoped role (`event_members` table, reused from migration 003)

| Role | Granted via | Scope |
|---|---|---|
| `event_admin` | `POST /events/{event_id}/payment-admins` (platform_admin only) | This event only — satisfies `require_event_admin` and `require_event_payment_read_access` for that `event_id`, nothing else. |

### Route → dependency map (source-verified)

| Dependency | Used by | Who passes |
|---|---|---|
| `require_platform_role("platform_admin")` | grant/revoke role, grant event admin, both expire-* sweep triggers | `platform_admin` only |
| `require_platform_role("platform_admin", "auditor")` | `GET /admin/payment-roles` | `platform_admin` or `auditor` |
| `require_platform_role("platform_admin","finance_operator","auditor","support")` | `GET /admin/payments/gateway-config` | any of the four |
| `require_event_admin` | create/validate/publish payment-configuration | `platform_admin`, or `event_admin` for that event |
| `require_event_payment_read_access` | list/get payment-configuration | `platform_admin`/`finance_operator`/`auditor`/`support` (any event), or `event_admin` for that event |

**Nothing here ever reads a role from the request body, query string, or header** — confirmed by
source (`admin_auth.py` docstring) and live/test evidence
(`test_fabricated_role_in_request_body_has_no_effect`,
`test_fabricated_role_header_has_no_effect`). Roles are resolved exclusively from the verified JWT
identity plus server-side DB/settings state. Denial for any of the above without a qualifying
role: `403 payment_role_required` (platform-wide checks) or `403 event_admin_required` / `403
payment_read_access_required` (event-scoped checks). Live-verified: an authenticated alumni token
with no roles → `403 payment_role_required` on `gateway-config` and `expire-orders`.

## 4. Webhook security (deep dive)

`POST /api/v1/payment-gateways/{gateway}/webhook` is intentionally unauthenticated at the HTTP
layer — see `app/services/payment_service.process_webhook` for the full gate sequence, applied
**in this exact order**, each step short-circuiting the rest:

1. **Gateway existence/enablement** — `{gateway}` path segment resolved through
   `gateway_registry.get_enabled_gateway`. Unknown or disabled → `404 unknown_gateway` at the HTTP
   layer *before* `process_webhook` is even called (defense in depth: `process_webhook` re-checks
   independently, since it's also called directly from delayed-webhook delivery and dev
   diagnostics, which don't go through the HTTP route's pre-check).
2. **Signature verification** (`gateway_obj.verify_webhook`) — HMAC-SHA256 over the exact raw
   body bytes (`hmac.compare_digest`, constant-time). Invalid → webhook event row still recorded
   (for the audit trail) but marked `rejected`/`invalid_signature`; response is `200
   {"status":"rejected","processing_status":"rejected"}` (never a 4xx — gateways expect a 2xx ack
   regardless of business outcome). Live-verified.
3. **Parseability** — malformed body → `rejected`/(no specific error code recorded at this stage
   in the audit row, since parsing happens before signature-dependent business logic can run);
   response is the same rejected-200 shape.
4. **Duplicate detection** — `INSERT ... ON CONFLICT (gateway, gateway_event_id) DO NOTHING`. A
   second delivery of the same `(gateway, event_id)` returns `RETURNING` nothing →
   `processing_status: "duplicate"`, response `200`, **zero additional mutation** — checked
   *before* freshness, so a replay of an old-but-already-seen event is caught here regardless of
   its timestamp (`test_old_duplicate_replay_causes_zero_additional_mutation`).
5. **Freshness** (WP3) — only reached for a genuinely first-seen `event_id`, and only *after*
   signature is confirmed valid (an unsigned/forged stale timestamp never reaches this check).
   `issued_at` is part of the signed payload itself (`canonicalize()` sorts keys and signs the
   whole body), so it cannot be altered post-signing without invalidating the signature.
   - `age_seconds = now - issued_at`; rejected as `timestamp_stale` if `age_seconds >
     PAYMENT_WEBHOOK_MAX_AGE_SECONDS` (default 300s / 5 min).
   - Rejected as `timestamp_future_skew` if `age_seconds < -PAYMENT_WEBHOOK_MAX_FUTURE_SKEW_SECONDS`
     (default 30s).
   - `timestamp_missing` / `timestamp_malformed` for absent/non-numeric `issued_at`.
   - All four live/test-verified (`tests/test_payment_webhook_freshness.py`, 13/13 passing).
6. **Correlation** — `gateway_order_ref` must match a known `payment_attempts` row → else
   `rejected`/`unknown_gateway_order`.
7. **Amount/currency verification** — the webhook's `amount`/`currency` must exactly equal the
   stored attempt's `amount`/`currency` (`Decimal` comparison) → else
   `rejected`/`amount_or_currency_mismatch`. This is the server-side integrity check that makes a
   tampered webhook payload harmless even if it were somehow signed
   (`test_amount_tampering_on_webhook_rejected`, `test_currency_tampering_on_webhook_rejected`).
8. **Row lock + business transition** — `SELECT ... FROM payment_orders ... FOR UPDATE` on the
   order row, so two webhook deliveries for the same order can never both apply a captured
   transition concurrently (`test_concurrent_webhook_delivery_of_identical_payload_captures_once`).
   A stale attempt (already `captured`/`failed`/etc., not `initiated`/`pending`) is a no-op —
   `duplicate`, not an error.

**Rejection-reason → outcome table** (all return HTTP `200`, `status: "rejected"`,
`processing_status: "rejected"`, except duplicate which is `processing_status: "duplicate"`):

| `error_code` recorded | Cause |
|---|---|
| *(none — HTTP 404 instead)* | Unknown/disabled gateway path segment |
| *(none — parse failure)* | Malformed JSON body |
| `invalid_signature` | HMAC mismatch |
| `timestamp_missing` / `timestamp_malformed` / `timestamp_stale` / `timestamp_future_skew` | Freshness gate |
| `unknown_gateway_order` | `gateway_order_ref` doesn't match any attempt |
| `amount_or_currency_mismatch` | Payload amount/currency ≠ stored attempt |
| `unknown_event_type` | Recognized gateway/signature/order but an event type this codebase doesn't normalize |
| *(processing_status: duplicate, no error_code)* | Already-recorded `(gateway, event_id)`, or a stale/already-resolved attempt |

**Replay/tamper protection summary**: signature (integrity + authenticity) → freshness (replay
window) → duplicate-event-id (exact replay) → amount/currency match (tamper-after-forge-attempt
harmlessness) → row lock (concurrent-delivery race). All five are independent layers; none is a
substitute for another.

## 5. Gateway abstraction

`app/gateways/base.py` defines the gateway-neutral contract (`PaymentGateway` ABC). The payment
domain (`payment_service`) talks to this interface only — **no module outside `app/gateways/`
imports a concrete gateway class**; selection always goes through `app.gateways.registry`.

- **`GatewayCapability`** enum: `create_payment`, `verify_payment`, `query_payment_status`,
  `process_webhook`, `verify_webhook`, `refund`, `query_refund`. A gateway that doesn't declare a
  capability raises `GatewayCapabilityNotSupportedError` on that call — the domain layer never
  special-cases provider names to decide what's supported.
- **Registry** (`app/gateways/registry.py`): gateway selection is `settings.payment_gateway_mode`
  only (server-side env var) — **no request path accepts a client-supplied gateway name for
  payment initiation.** The webhook route's `{gateway}` path segment identifies who is delivering
  the callback, not who the attendee is charged through, and is validated against this same
  registry. `get_active_gateway` never falls back to a default on error — misconfiguration fails
  closed (`503 payment_gateway_unavailable`), confirmed live and by
  `test_registry_never_falls_back_to_a_default_gateway`.
- **Fail-closed sandbox-in-production guard**: `DeterministicSandboxGateway.is_enabled` returns
  `False` whenever `settings.app_env == "production"` unless
  `PAYMENT_SANDBOX_ALLOW_IN_PRODUCTION` is explicitly set — a no-real-money gateway must never be
  silently reachable in a real deployment (`test_sandbox_disabled_in_production_by_default`,
  `test_sandbox_enabled_in_production_with_explicit_opt_in`).

### Capability matrix (source-verified against `DeterministicSandboxGateway.capabilities`)

| Capability | `deterministic_sandbox` | Real gateway (Razorpay/CCAvenue/etc.) |
|---|---|---|
| `create_payment` | **IMPLEMENTED** | NOT IMPLEMENTED |
| `process_webhook` | **IMPLEMENTED** | NOT IMPLEMENTED |
| `verify_webhook` | **IMPLEMENTED** | NOT IMPLEMENTED |
| `verify_payment` (client-return-based) | NOT IMPLEMENTED — deliberately, on every adapter: "this architecture never treats a browser/app redirect or client-supplied reference as authoritative" (`base.py` docstring) | NOT IMPLEMENTED (by design — see left) |
| `query_payment_status` | NOT IMPLEMENTED — "BLOCKED until a real gateway is selected" (source comment) | FUTURE |
| `refund` | NOT IMPLEMENTED — "Out of scope for this sprint by explicit instruction" | FUTURE |
| `query_refund` | NOT IMPLEMENTED | FUTURE |

**No production payment gateway (Razorpay, CCAvenue, Stripe, or any other) is implemented
anywhere in this codebase.** `app/gateways/_REGISTRY` contains exactly one entry:
`deterministic_sandbox`. Any documentation or roadmap file claiming otherwise is describing a
future plan, not current behavior — do not treat it as implemented.

### Deterministic sandbox — how it differs from a real gateway

The sandbox "behaves like a gateway rather than a direct DB status switch": it produces a signed
webhook payload and that payload is run through the exact same signature-verification +
processing path a real gateway's HTTP webhook would use. The only shortcut is transport — the
payload is delivered via an in-process function call (or a short `asyncio.sleep` for `DELAYED_*`
scenarios) instead of an outbound HTTP request, since there's no real gateway on the other end.
`scenario` (`SUCCESS`/`FAILURE`/`PENDING`/`CANCELLED`/`DELAYED_SUCCESS`/`DELAYED_FAILURE`) is a
**sandbox-only testing concept** — the request field that selects it
(`CreatePaymentAttemptRequest.scenario`) has no equivalent in a real-gateway integration, where the
gateway itself determines the outcome and the caller cannot select it.

## 6. Secret handling

- `payment_sandbox_signing_secret` (env `PAYMENT_SANDBOX_SIGNING_SECRET`) is read only inside
  `DeterministicSandboxGateway` methods (`create_payment`, `verify_webhook`) — never returned in
  any API response. `GET /admin/payments/gateway-config` is explicitly documented and tested to
  exclude it (`test_gateway_config_diagnostics_exposes_no_secrets`, and confirmed live — no such
  key in the response body).
- `app/config.py Settings.Config.extra = "ignore"` — unrecognized `.env` keys never crash startup
  (a defensive posture, not a payment-specific one).
- `audit_service.emit` docstring: "never pass firebase_uid, email, phone, join URLs, or tokens
  into context" — the audit trail is deliberately scrubbed of PII/secrets at the call site, not
  redacted after the fact.
- `scripts/run_payment_lifecycle_sweep.py`: "Never logs tokens, secrets, DB credentials, or full
  order/registration records — only counts, IDs, and error messages."

## 7. Known gaps (honest, source-verified)

- Dev-diagnostics routes (`/api/v1/dev/diagnostics/payments/*`) are gated only by `APP_ENV` and
  `PAYMENT_DIAGNOSTICS_ENABLED` application-level checks — there is no additional network-layer
  restriction (e.g. IP allowlist) documented anywhere in this codebase. Misconfiguring
  `APP_ENV` in a reachable deployment would expose real write paths (`import_payment_configuration`,
  `resolve_pending_payment_attempt`) gated by nothing stronger than a spoofable `X-Dev-User:
  admin` header.
- `payment_exceptions` has no production resolve endpoint — resolution requires direct DB access
  (§Payment exceptions in the API reference).
- No scheduler is wired up anywhere in this repository for the expiry sweep — it must be invoked
  externally (cron, Cloud Scheduler, etc.) via `scripts/run_payment_lifecycle_sweep.py` or the
  manual admin-triggered endpoints. See the operations runbook for recommended cadence.
