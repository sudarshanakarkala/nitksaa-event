# NITKSAA Event — Payment API Error Catalog

Source-verified 2026-08-22 — every row below is grep-confirmed against an actual
`HTTPException(status_code=..., detail=...)` call site (or, for FastAPI-native errors, the
framework's own behavior). Live-verified rows are marked ✅; source/test-verified-only rows are
marked 📄. No invented codes.

## Attendee-facing (`app/api/payments.py`, `app/services/payment_service.py`)

| HTTP | `detail` | Meaning | Recommended client action | Verified |
|---|---|---|---|---|
| 403 | *(FastAPI native)* `"Not authenticated"` | No `Authorization` header | Prompt login | ✅ |
| 401 | `invalid_or_expired_token` | Bearer token fails JWT decode/expiry | Refresh via `/api/v1/auth/firebase`, then retry | 📄 |
| 403 | `account_suspended` | Identity resolved but account is suspended | Show suspension message; do not retry | 📄 |
| 403 | `alumni_only` | `user_type != "alumni"` or missing `ref_id` (registration) | Not recoverable by retry — account type issue | 📄 |
| 403 | `alumni_not_found` / `alumni_not_active` | Alumni profile missing/inactive in `alumni_db` | Contact support | 📄 |
| 404 | `event_not_found` | `event_id` doesn't exist | Show not-found page | 📄 |
| 409 | `event_not_published` | Event not in `published` status | Hide registration CTA | 📄 |
| 409 | `registration_not_open_yet` / `registration_closed` | Outside registration window | Show window dates | 📄 |
| 409 | `payment_not_configured` | Paid event has no published pricing config | Contact organizer — not a client bug | ✅ (pricing endpoint) |
| 409 | `already_registered` | Live registration already exists for this event | Route to `GET .../my-registration` | ✅ |
| 409 | `event_full` | Capacity reached | Show waitlist/sold-out state | 📄 |
| 404 | `registration_not_found` | Registration doesn't exist, or belongs to another user (ownership-hidden) | Verify `registration_id`; do not assume it exists | 📄 |
| 409 | `idempotency_key_conflict` | Same key reused against a different registration | Generate a fresh key; this is a client bug | 📄 |
| 409 | `registration_not_payable` | Registration not in `seat_held`/`payment_pending`/`payment_failed` | Re-fetch registration status; likely already resolved | 📄 |
| 409 | `seat_hold_expired` | Hold lapsed before order/attempt creation | Restart registration flow | 📄 |
| 409 | `payment_order_creation_conflict` | Rare concurrent-create edge case, no resolvable existing order found | Re-fetch and retry once | 📄 |
| 404 | `payment_order_not_found` | Order doesn't exist, or belongs to another user | Do not assume order exists; re-derive from `latest_order_id` | ✅ |
| 422 | `unsupported_scenario` | `scenario` not supported by the active gateway | Client bug (sandbox-only field misuse) — fix request | 📄 |
| 503 | `payment_gateway_unavailable` | Server-side gateway misconfiguration (fail-closed) | Not client-recoverable — alert ops; do not retry rapidly | 📄 |
| 409 | `payment_order_not_payable` | Order not `created`/`payment_pending` (e.g. already `paid`/`expired`) | Re-fetch order; show final state | ✅ |
| 409 | `payment_order_expired` | Past `expires_at` | Restart registration flow | 📄 |
| 409 | `payment_already_completed` | `amount_paid >= final_amount` already | Re-fetch order; show paid state | 📄 |
| 409 | `payment_attempt_active` | An unresolved attempt already exists | Poll order/attempt status; do not create another attempt | 📄 |
| 409 | `payment_verification_in_progress` | Same as above, specifically while `registration_status == payment_verification` | Poll `POST .../verify`, show "do not pay again" | 📄 (message live-verified) |
| 404 | `payment_attempt_not_found` | Attempt doesn't exist, or its order belongs to another user | Do not assume attempt exists | 📄 |
| 409 | `attempt_not_verifiable` | Attempt not in `pending`/`requires_verification` | Re-fetch attempt/order; likely already resolved | 📄 |

## Webhook (`POST /payment-gateways/{gateway}/webhook`)

| HTTP | Response body | Meaning | Recommended (server-to-server) behavior | Verified |
|---|---|---|---|---|
| 404 | `{"detail":"unknown_gateway"}` | Path segment doesn't match a registered+enabled gateway | Gateway integration misconfigured — fix the webhook URL/gateway name | ✅ |
| 200 | `{"status":"rejected","processing_status":"rejected"}` | Invalid signature, unparseable body, stale/future timestamp, unknown order, or amount/currency mismatch (see security guide for the full ordered gate list) | Gateway should treat as a hard failure per its own retry policy — this codebase does not request a retry via HTTP status (always 200) | ✅ (invalid signature; timestamp cases test-verified) |
| 200 | `{"status":"ok","processing_status":"duplicate"}` | Already-recorded event, or a stale/resolved attempt | No-op — correct behavior for a replayed delivery | ✅ |
| 200 | `{"status":"ok","processing_status":"processed"}` | Successfully applied | — | ✅ |

## Admin (`app/api/admin_payments.py`)

| HTTP | `detail` | Meaning | Recommended client action | Verified |
|---|---|---|---|---|
| 403 | `payment_role_required` | Caller lacks any of the route's allowed platform roles | Request role grant from a `platform_admin` | ✅ |
| 403 | `event_admin_required` | Caller lacks `platform_admin`/`event_admin` for this event | Same | 📄 |
| 403 | `payment_read_access_required` | Caller lacks any qualifying read role for this event | Same | 📄 |
| 404 | `event_not_found` | `event_id` doesn't exist (config/admin-grant routes) | Verify event_id | 📄 |
| 422 | `{"errors": [...]}` | Configuration draft fails `validate_configuration` | Fix each listed field; same validator backs both `/validate` and the write path | 📄 |
| 404 | `payment_configuration_not_found` | Config id doesn't exist, or belongs to a different event | Re-fetch config list | 📄 |
| 409 | `payment_configuration_not_a_draft` | `/publish` called on a non-draft config | Only draft configs are publishable — check status first | ✅ |
| 409 | `payment_configuration_publish_conflict` | Concurrent publish race, loser | Re-fetch; the winning publish already applied | 📄 |
| 409 | `payment_role_already_active` | Granting a role the user already actively holds | No action needed — already granted | 📄 |
| 404 | `firebase_uid_not_found` | Target `firebase_uid` has no `event_users` row | Verify UID; user must have logged in at least once | 📄 |
| 404 | `payment_role_grant_not_found` | Revoking a `grant_id` that doesn't exist or is already revoked | Re-fetch role list | 📄 |

## Diagnostics (`app/api/dev_diagnostics.py` — dev-only, `404 not_found` for both gating checks)

| HTTP | `detail` | Meaning | Verified |
|---|---|---|---|
| 404 | `not_found` | `APP_ENV != development`, or `PAYMENT_DIAGNOSTICS_ENABLED=false` — both existence-hidden identically | 📄 (`test_resolve_pending_attempt_endpoint_requires_development_env`) |
| 404 | `event_not_found` | Config-import target event doesn't exist | 📄 |
| 404 | `payment_attempt_not_found` | Resolve target doesn't exist | 📄 |
| 409 | `attempt_not_resolvable` | Attempt not `pending`/`requires_verification` | 📄 |

## Notes on this catalog

- Every non-2xx payment-domain response in this codebase uses `{"detail": "<snake_case_code>"}`
  (FastAPI's default `HTTPException` shape) except the admin-config `422` validation response,
  which nests a list: `{"detail": {"errors": ["...", "..."]}}`.
- `error_code` strings recorded on `payment_webhook_events` rows
  (`invalid_signature`/`timestamp_stale`/etc.) are **not** returned in the webhook HTTP response
  body — they're internal/audit-only, visible via `GET /dev/diagnostics/payments/orders/{id}/technical-timeline`
  or direct DB access, never to the calling gateway.
- No `5xx` payment-domain response was found in source for expected business-logic failures — the
  one deliberate `5xx`, `503 payment_gateway_unavailable`, represents fail-closed misconfiguration,
  not an attendee-caused error.
