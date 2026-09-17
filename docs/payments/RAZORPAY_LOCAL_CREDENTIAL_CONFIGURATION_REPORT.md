# Razorpay Local Credential Configuration Report

**Project:** NITKSAA-EVENT (backend only)
**Date:** 2026-09-07
**Scope:** write the provided Razorpay **Test Mode** credentials into local
`backend/.env`, verify hygiene + settings load, run focused tests.
**Security:** no full Key ID or Key Secret appears anywhere in this report,
in any tracked file, in test fixtures, or in logs.

---

## Result

| Item | Value |
|---|---|
| `RAZORPAY_KEY_ID` | **configured** — masked: `rzp_test****Yuoo` (23 chars, `rzp_test_` prefix) |
| `RAZORPAY_KEY_SECRET` | **configured** — masked: `********` (24 chars, present) |
| `RAZORPAY_MODE` | `test` |
| `RAZORPAY_WEBHOOK_SECRET` | **MISSING** (not provided; intentionally left unset) |
| `backend/.env` tracked by git | **no** — git-ignored at `.gitignore:164` (`backend/.env`); `git ls-files backend/.env` → empty |
| `settings.razorpay_configured` | **true** |
| `RazorpayGateway.is_enabled(settings)` | **true** |
| tests | **125 passed / 0 failed** (focused Razorpay + payment + refund + gateway-foundation + free-flow suite) |
| restart required | **YES** — `get_settings()` is `@lru_cache`d; a running backend must be restarted to pick up the new `.env` values |

---

## 1. Existing configuration (inspected, not redesigned)

`backend/app/config.py` already defines all four fields
(`razorpay_key_id`, `razorpay_key_secret`, `razorpay_webhook_secret`,
`razorpay_mode`) plus the `razorpay_configured` property. `backend/.env.example`
already carries all four as blank placeholders (`RAZORPAY_MODE=test`).
No configuration-system changes were made.

## 2. `backend/.env` update

- `backend/.env` had **no** `RAZORPAY_*` lines before this change.
- Appended exactly three lines under a comment header:
  `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_MODE=test`.
- Idempotent upsert (replace-in-place if present, else append) — **each key
  appears exactly once**, no duplicates.
- All unrelated `.env` values preserved (DB, Firebase, email, SMTP, admin
  UIDs, allowed origins — untouched).
- `PAYMENT_GATEWAY_MODE` **not** changed — the project uses per-event gateway
  selection (`payment_configurations.gateway`), so the global mode is
  irrelevant to enabling Razorpay for the ₹1 pilot event.
- `event_id=392` not touched.
- `RAZORPAY_WEBHOOK_SECRET` **not** written (not provided; not invented; the
  Key Secret was **not** copied into it).

## 3. Webhook secret

`RAZORPAY_WEBHOOK_SECRET = MISSING`. Acceptable for now. Live webhook
signature verification stays blocked until the webhook is created in the
Razorpay Dashboard and the matching secret is added to local `backend/.env`.

## 4. Secret hygiene

| Check | Result |
|---|---|
| `git status --porcelain` | only `M backend/tests/test_payment_gateway_foundation.py`, `M backend/tests/test_razorpay_gateway.py` (test-isolation fixes, no secrets) |
| `backend/.env` tracked / staged | no / no |
| Real Key Secret in any tracked file (`git grep`) | **not found** |
| Real Key ID in any tracked file (`git grep`) | **not found** |
| `backend/.env.example` | placeholders only (`RAZORPAY_KEY_ID=`, `RAZORPAY_KEY_SECRET=`, `RAZORPAY_WEBHOOK_SECRET=`, `RAZORPAY_MODE=test`) |
| Real Key Secret in `docs/` or any report | **not found** — only in `backend/.env` (git-ignored) |
| Real Key Secret in test fixtures | **not found** — `tests/_razorpay_fakes.py` uses `secret_fake` / `whsec_fake` |

## 5. Settings load (masked)

```
RAZORPAY_KEY_ID=rzp_test****Yuoo
RAZORPAY_KEY_SECRET=********
RAZORPAY_MODE=test
RAZORPAY_WEBHOOK_SECRET present=False
razorpay_configured=True
RazorpayGateway.is_enabled(settings)=True
```

No real Razorpay API call was made — `is_enabled` and `razorpay_configured`
are pure local checks.

## 6. Tests

Focused suite run **after** the `.env` update:
`test_razorpay_gateway.py`, `test_per_event_gateway.py`,
`test_payment_gateway_foundation.py`, `test_razorpay_checkout_and_webhook.py`,
`test_payment_refunds.py`, `test_free_flow_regression.py`, `test_payments.py`,
`test_payment_webhook_freshness.py` → **125 passed, 0 failed**.

Two tests needed a one-line isolation fix because real credentials now live
in `backend/.env`: `test_is_enabled_false_without_credentials` and
`test_attempt_creation_fails_closed_when_order_gateway_is_unusable` switched
from `monkeypatch.delenv(...)` to `monkeypatch.setenv(..., "")` — an explicit
empty env var overrides the dotenv-file value in pydantic-settings, so the
fail-closed assertions hold regardless of local `.env` contents. No
functional code changed; no test weakened.

The Razorpay adapter/integration tests run entirely against the offline fake
(`tests/_razorpay_fakes.py`) and never touch the real API.

## 7. Restart

**Restart the backend** to load the new `.env` values (settings are cached):

```
cd backend
source .venv/bin/activate
python -m uvicorn app.main:app --reload
```

(No long-running server was started by this task.)

---

## RGIS

- **R = PASS** — settings resolve consistently; 125/0 focused tests green after the update.
- **G = PASS** — secrets only in local git-ignored `backend/.env`; no tracked-file / fixture / report / log leakage; `.env.example` placeholders only.
- **I = PASS** — existing `RazorpayGateway` + `Settings` recognise the provided Test credentials (`razorpay_configured=True`, `is_enabled=True`); no adapter/config redesign.
- **S = PASS** — no full Key ID/Secret printed, committed, logged, or copied into `RAZORPAY_WEBHOOK_SECRET`; masked output only.

## Definition of Done

```
credential values updated locally: PASS
test mode set:                     PASS
secret hygiene:                    PASS
settings load:                     PASS
razorpay_configured:               PASS (true)
focused tests:                     PASS (125 passed / 0 failed)
webhook secret:                    MISSING
restart required:                  YES
RGIS:                              PASS
```

## Blockers

- `RAZORPAY_WEBHOOK_SECRET` not yet configured → live webhook signature
  verification remains blocked.
- No public HTTPS URL for `POST /api/v1/payment-gateways/razorpay/webhook`.

Live payment/refund testing must not begin until both are in place.
