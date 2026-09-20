# Razorpay TEST / LIVE Mode Separation — Backend Report

**Project:** NITKSAA-EVENT (backend)
**Date:** 2026-09-17
**Scope:** architectural TEST/LIVE separation for the Razorpay gateway —
credentials, per-row mode snapshot, webhook routing, refunds, admin
publish RBAC, safe API exposure, pilot configs, tests.
**Status (updated 2026-09-17, later same day — see §14):** CODE VERIFIED +
TEST MODE LIVE-VERIFIED (existing 2026-09-07 E2E, re-validated against the
new mode-specific webhook route) + **LIVE MODE CONFIGURED AND WEBHOOK
LIVE-VERIFIED** (real `RAZORPAY_LIVE_*` credentials now loaded, LIVE
webhook signature verified end-to-end over a public tunnel — see §14).
Config `7772` (event `19243`) remains an unpublished **draft**. **LIVE MODE
REAL-MONEY VERIFIED: not attempted — no real payment, refund, or config
publish has been performed. Pending explicit human approval + Razorpay
Dashboard confirmation (§14).**

---

## 1. Baseline before this work

- One global Razorpay credential set (`RAZORPAY_KEY_ID/KEY_SECRET/WEBHOOK_SECRET/MODE`,
  `backend/app/config.py`), Test creds only, confirmed in
  `docs/payments/RAZORPAY_LOCAL_CREDENTIAL_CONFIGURATION_REPORT.md`.
- No `mode`/`environment` column anywhere in `payment_configurations`,
  `payment_orders`, `payment_attempts`, `payment_refunds` (checked
  migrations 015–022). Only *gateway* (`deterministic_sandbox` |
  `razorpay`) was per-row (migration 021).
- Single webhook route `/api/v1/payment-gateways/{gateway}/webhook`, no
  key-prefix validation anywhere.
- Existing TEST pilot: `event_id=18117` / config `7138`, ₹1, `gateway=razorpay`,
  live-verified per `docs/payments/RAZORPAY_LIVE_TEST_MODE_E2E_REPORT.md`.

## 2. Backend TEST config

`RAZORPAY_TEST_KEY_ID` / `RAZORPAY_TEST_KEY_SECRET` / `RAZORPAY_TEST_WEBHOOK_SECRET`
added to `app/config.py` and `.env.example`. `Settings.razorpay_credentials_for("test")`
falls back to the legacy `RAZORPAY_KEY_ID/KEY_SECRET/WEBHOOK_SECRET` vars
when the new ones are blank — the existing local `.env` (real Test creds,
confirmed `rzp_test_` prefix) keeps working unmodified. **Status: PASS.**

## 3. Backend LIVE config

`RAZORPAY_LIVE_KEY_ID` / `RAZORPAY_LIVE_KEY_SECRET` / `RAZORPAY_LIVE_WEBHOOK_SECRET`
added, fully independent — `razorpay_credentials_for("live")` never falls
back to the TEST or legacy vars. **Updated 2026-09-17:** real Live
credentials were provided and are now configured in local git-ignored
`backend/.env` (masked verification: key_id `rzp_live****daK5`, 23 chars,
`rzp_live_` prefix confirmed; key_secret and webhook_secret present,
webhook_secret distinct from both the key_secret and the TEST webhook
secret). **Status: PASS** — see §14 for the live verification.

## 4. payment_mode persistence

Migration `023_payment_mode_separation.sql` adds `payment_mode VARCHAR(10)
NOT NULL DEFAULT 'test' CHECK (payment_mode IN ('test','live'))` to all
four payment tables, mirroring the migration-021 `gateway` pattern exactly:
- `payment_configurations.payment_mode` — admin's choice at draft time
- `payment_orders.payment_mode` — snapshotted from the config at order-creation
- `payment_attempts.payment_mode` — snapshotted from the order at attempt-creation (what `RazorpayGateway` calls actually use)
- `payment_refunds.payment_mode` — snapshotted from the captured attempt at refund-creation

Applied to local `events_db`. Every existing row defaulted to `'test'` —
the only value that has ever been factually true (no Live credentials have
ever existed). **Status: PASS.**

## 5. Key-prefix / fail-closed guard

`app/gateways/razorpay_gateway.py`: new `_resolve_credentials(settings,
payment_mode)` is the single choke point every Razorpay call goes
through. Raises `RazorpayModeCredentialError` (fail closed, never a
silent fallback) when: `payment_mode` is missing/unrecognised, the
resolved profile has no credentials, or the key_id doesn't start with the
expected `rzp_test_`/`rzp_live_` prefix. `PaymentGateway.create_payment`,
`verify_checkout_signature`, `verify_webhook`, `query_payment_status`,
`refund`, `query_refund` all now take `payment_mode` (ignored by the
deterministic sandbox). **Status: PASS** — covered by
`tests/test_razorpay_gateway.py` (missing mode, unknown mode, missing
Live creds, wrong-prefix Live key, wrong-prefix Test key, no cross-mode
fallback even when the other mode's creds are valid).

## 6. Webhook separation

Two explicit routes (`app/api/payments.py`):
```
POST /api/v1/payment-gateways/razorpay/test/webhook   (RAZORPAY_TEST_WEBHOOK_SECRET only)
POST /api/v1/payment-gateways/razorpay/live/webhook   (RAZORPAY_LIVE_WEBHOOK_SECRET only)
```
The generic `/api/v1/payment-gateways/{gateway}/webhook` route now 404s
for `gateway=razorpay` (deterministic_sandbox unaffected). `process_webhook`
additionally rejects (`webhook_mode_mismatch`) if a delivery's route-mode
disagrees with the matched order's own snapshotted `payment_mode`, even
when the signature validates — cross-mode webhook application is rejected
independent of signature validity. **Status: PASS** — covered by
`tests/test_razorpay_checkout_and_webhook.py`
(`test_generic_webhook_route_rejects_razorpay`,
`test_live_webhook_route_rejects_test_signed_delivery`,
`test_live_signed_webhook_for_test_order_is_mode_mismatch_rejected`).

Dashboard setup (once Live credentials exist): create a **separate** Live
webhook at the `.../razorpay/live/webhook` URL with its own secret, same 7
events as TEST (`payment.authorized`, `payment.captured`, `payment.failed`,
`order.paid`, `refund.created`, `refund.processed`, `refund.failed`) — do
not reuse the TEST webhook's URL or secret.

## 7. Refund separation

`refund_service.cancel_registration` resolves gateway credentials using
the **captured attempt's** snapshotted `payment_mode` (not the order's —
asserted equal, since a mismatch would indicate a data-integrity bug, not
a legitimate state). `payment_refunds.payment_mode` is snapshotted at
refund-creation time and used for every subsequent `refund()`/`query_refund()`
call. **Status: PASS** — `tests/test_payment_refunds.py::test_cross_mode_refund_is_structurally_rejected`
forces a synthetic mode mismatch directly in the DB (impossible via the
API) and confirms the service fails closed (409 `refund_mode_mismatch`,
no refund row created, registration left untouched) rather than ever
calling a provider with mismatched credentials.

## 8. Admin configuration / RBAC

`PaymentConfigDraftCreateRequest.payment_mode` (`test`|`live`, default
`test`). A LIVE draft may be **created** by the same roles as any other
draft (event_admin/platform_admin) without Live credentials existing yet —
preparing a LIVE config ahead of time is the point of "prepare LIVE mode
safely." **Publishing** a LIVE config additionally requires:
- `platform_admin` (checked inside `payment_config_service.publish`,
  independent of the route-level `event_admin` dependency, since the
  route can't see the draft's mode before loading it), and
- `RAZORPAY_LIVE_KEY_ID/KEY_SECRET/WEBHOOK_SECRET` all present with the
  `rzp_live_` prefix — enforced by `validate_configuration(...,
  require_live_credentials=True)`.

`events_service._ensure_payment_configuration` (auto-provisioning on
event publish) explicitly passes `payment_mode="test"` — an admin
publishing an event through the portal can never silently create a
Live-charging config. **Status: PASS** — covered by
`tests/test_payment_admin_config.py` (§C: live draft creation without
creds succeeds, live publish without creds 422s, live publish by
event_admin 403s, live publish by platform_admin with valid creds 200s,
test-mode publish unaffected by the new gate).

## 9. Safe API exposure

`payment_mode` and derived `real_money` (`payment_mode == "live"`) added
to `PaymentOrderResponse`, `PaymentAttemptResponse`, `RefundStatusResponse`,
`PaymentConfigAdminResponse`, `GatewayInfo` (razorpay-only
`test_mode_configured`/`live_mode_configured`, no secrets). No Key Secret,
Webhook Secret, or credential value is exposed anywhere — unchanged from
before this work (only `key_id` was ever public, still true).
**Status: PASS.**

## 10. Pilot configurations

- **TEST pilot** (pre-existing): `event_id=18117`, config `id=7138`, ₹1,
  `gateway=razorpay`, `payment_mode=test` (explicit, matches default).
  Unchanged by this work.
- **LIVE pilot** (new): `event_id=19243` ("Razorpay LIVE Payment
  Validation"), config `id=7772`, ₹1.00, `gateway=razorpay`,
  `payment_mode=live`, **status=draft** — deliberately left unpublished:
  publishing requires real Live credentials + `platform_admin`, neither
  exercised here. `event_id=392` and `event_id=18117` verified untouched
  (before/after `SELECT ... FROM payment_configurations WHERE event_id IN
  (392, 18117, 19243)` — see §12).

## 11. Tests

24 new backend tests added across `test_razorpay_gateway.py` (12),
`test_razorpay_checkout_and_webhook.py` (4), `test_payment_admin_config.py`
(6), `test_payment_refunds.py` (2). Full suite:

```
432 passed, 4 skipped (pre-existing, unrelated test_admin_rbac.py design skips), 0 failed
```
(baseline before this work: 407 passed / 4 skipped, per the 2026-09-07 report.)

**Isolation fix (2026-09-17, after real Live credentials were configured):**
five tests (`test_is_enabled_false_without_credentials`,
`test_live_mode_without_live_credentials_fails_closed`,
`test_live_mode_never_falls_back_to_test_credentials`,
`test_resolve_credentials_fails_closed_without_payment_mode`,
`test_attempt_creation_fails_closed_when_order_gateway_is_unusable`)
previously simulated "no Live credentials configured" by relying on the
absence of `RAZORPAY_LIVE_*` in the environment. Once real Live
credentials were added to local `.env`, those tests started failing —
correctly, since their premise ("no live creds exist") had become false,
not because the fail-closed behaviour broke. Fixed by having them
explicitly blank `RAZORPAY_LIVE_KEY_ID/SECRET/WEBHOOK_SECRET` via
`monkeypatch.setenv(..., "")` (env source outranks dotenv in
pydantic-settings — same pattern already used for the TEST vars per the
2026-09-07 credential report). No functional code changed; no test
weakened. Full suite re-confirmed **432 passed, 4 skipped, 0 failed**
after the fix.

## 12. Migration / audit integrity

```sql
-- before (2026-09-07 baseline) and after this migration, identical rows:
SELECT id, event_id, gateway, payment_mode, status
FROM payment_configurations WHERE event_id IN (392, 18117);
--   5 |    392 | deterministic_sandbox | test | published   (unchanged)
-- 7138 |  18117 | razorpay              | test | published   (unchanged)
```
`payment_mode` default (`'test'`) is the only value that could ever be
factually correct for pre-existing rows, since no Live credential has
existed at any point in this project's history. **Status: PASS.**

## 13. Security verification

- No Test or Live secret in any tracked file, test fixture, or this
  report (`git grep` clean, same as the 2026-09-07 credential report).
- No client-supplied `payment_mode` anywhere — it is always read from the
  server-side config/order/attempt/refund snapshot, never a request body
  field the payer or the checkout client can set.
- No cross-mode webhook verification (§6), no cross-mode refund (§7), no
  cross-mode credential fallback (§5).
- LIVE publish requires an explicit authenticated `platform_admin` action;
  nothing publishes or auto-provisions a LIVE config.

## RGIS

- **R = PASS** — TEST and LIVE cannot contaminate each other's orders,
  webhooks, or refunds (structurally, via the mode snapshot + fail-closed
  credential resolution + mode-mismatch webhook/refund guards).
- **G = PASS** — LIVE is explicit (opt-in draft field), restricted
  (platform_admin + valid credentials to publish), auditable (existing
  `audit_service` events cover config publish/refund/webhook rejection),
  backend-authoritative (mode is never client-supplied).
- **I = PASS** — TEST and LIVE operate as two deliberate, independently
  configured Razorpay environments through the same `RazorpayGateway`
  adapter, no per-provider branching added to `payment_service`.
- **S = PASS** — secrets server-only, no mode spoofing possible (mode
  comes from the DB row, not the request), no silent fallback in either
  credential resolution or webhook/refund dispatch, no automated
  real-money action anywhere in this work.

## 14. LIVE credential configuration + live verification (2026-09-17, same day)

Real Live credentials were provided and configured. This section documents
what was actually verified — superseding §3/§10/Blockers above, which
described the pre-credential state.

**Credentials (masked only):**

| Var | State |
|---|---|
| `RAZORPAY_LIVE_KEY_ID` | present, `rzp_live****daK5` (23 chars), `rzp_live_` prefix confirmed |
| `RAZORPAY_LIVE_KEY_SECRET` | present (24 chars) |
| `RAZORPAY_LIVE_WEBHOOK_SECRET` | present (23 chars), distinct from both `RAZORPAY_LIVE_KEY_SECRET` and the TEST webhook secret |
| `backend/.env` tracked by git | no — `git check-ignore -v backend/.env` → `.gitignore:164` |
| Real Live Key ID/Secret/Webhook Secret in any tracked file | not found (`git grep` clean) |

**Backend loaded them (not just present in `.env`):** the running FastAPI
process was restarted after the `.env` write (`get_settings()` is
`@lru_cache`d and does not pick up `.env` changes on its own); confirmed
fresh via `settings.razorpay_credentials_for("live")` in-process and via
the live webhook probe below.

**Public HTTPS endpoint:** existing zrok tunnel `https://82qv31ibkxli.shares.zrok.io`
→ `http://127.0.0.1:8000` (already running, unrelated to this task).
`/api/v1/health` returns `{"status":"ok",...,"db":"ok"}` both locally and
through the public URL.

**LIVE webhook route (`POST /api/v1/payment-gateways/razorpay/live/webhook`), verified over the public URL:**
- Unsigned/malformed request → safely rejected, no 500, no state mutation.
- Bad-signature request → `signature_valid=false`, `processing_status=rejected`, `error_code=invalid_signature`.
- Delivery signed with the real `RAZORPAY_LIVE_WEBHOOK_SECRET` →
  **`signature_valid=true`** in `payment_webhook_events`, correctly
  `rejected` with `error_code=unknown_gateway_order` (the probe referenced
  no real order — this is the expected, safe outcome, not a failure).

**Regression after the credential change:** full suite re-run —
**432 passed, 4 skipped, 0 failed** (5 tests needed the isolation fix in
§11; no functional code changed).

**Pilot state (re-verified against the DB, unchanged from §10):**
`event_id=392` and `event_id=18117`/config `7138` byte-for-byte identical
to before this work. Config `7772` (event `19243`, ₹1.00, INR,
`gateway=razorpay`, `payment_mode=live`, GST off) is still `status=draft`
— **not published**, per the explicit stop condition.

**Platform admin available to publish:** `PLATFORM_ADMIN_FIREBASE_UIDS`
bootstrap UID `adW99tFFnDPp10cTd2vUMfEGCxS2` (env-based; the only
non-test-fixture platform_admin identity) plus two test-fixture rows in
`payment_platform_roles`. No decision has been made about which identity
actually performs the publish action.

**Known separate gap (not a LIVE-pilot blocker at the API level, but
affects the Flutter demo app):** the public event list/detail API
(`app/schemas/event_response.py`, `app/api/events.py`) does not expose
`payment_mode`/`real_money` at all — confirmed by `grep`, matches what the
Flutter TEST/LIVE UI report already documented as a known limitation.
Event-level TEST/LIVE filtering in the Flutter app is a no-op until this
is added. Not fixed here — out of scope for a backend-only audit task and
not required for a raw API-level LIVE transaction test.

**Still NOT done — and will not be done without your explicit approval:**
- Config `7772` has not been published.
- No real payment, verify-checkout, refund, or LIVE Dashboard-originated
  webhook has occurred.
- Razorpay Dashboard state (Live mode active, the Live webhook Active at
  exactly this URL, the 7 events selected) has **not** been confirmed —
  Claude Code cannot inspect the Dashboard directly; this requires your
  answer.

## Definition of Done

```
backend TEST config:          PASS
backend LIVE config:          PASS (real credentials configured + live-verified, §14)
payment_mode persistence:     PASS
webhook separation:           PASS
refund separation:            PASS
admin config / RBAC:          PASS
event auto-provision default: PASS (test)
pilot configs:                PASS (TEST published 18117/7138; LIVE draft 19243/7772, unpublished)
event 392 / 18117 untouched:  PASS
backend tests:                PASS (432 passed, 4 pre-existing skips, 0 failed)
LIVE webhook signature:       PASS (live-verified over public tunnel, §14)
Dashboard LIVE webhook Active: NOT CONFIRMED — awaiting your answer
config 7772 published:        NO (deliberately unpublished)
security:                     PASS
RGIS:                         R=PASS G=PASS I=PARTIAL (pre-real-payment) S=PASS
LIVE real-money E2E:          BLOCKED PENDING HUMAN APPROVAL — Dashboard not confirmed, no publish/charge performed
```

## What is needed from you before LIVE can go further

1. Confirm in the Razorpay Dashboard: Live mode active, a Live webhook
   Active at exactly `https://82qv31ibkxli.shares.zrok.io/api/v1/payment-gateways/razorpay/live/webhook`
   (or whatever the current tunnel URL is if it has since changed), with
   the 7 events from §6 selected.
2. Decide which identity should hold `platform_admin` to publish config
   `7772` (currently only the bootstrap UID does).
3. Explicit approval to publish config `7772` and perform the ₹1
   real-money pilot transaction — nothing in this repo does either without
   that approval.
