# Razorpay Live Test Mode — End-to-End Validation Report

**Project:** NITKSAA-EVENT (backend only)
**Date:** 2026-09-07
**Public base:** `https://y5pym24pm6ze.shares.zrok.io` (zrok share → localhost:8000)
**Webhook endpoint:** `https://y5pym24pm6ze.shares.zrok.io/api/v1/payment-gateways/razorpay/webhook`
**Security:** no full Key ID / Key Secret / Webhook Secret appears in this report, any tracked file, test fixture, or log.
**Status:** local config + all automatable live verification **COMPLETE**. Browser-Checkout-dependent flows (paid capture, real payment webhook, refund) **PAUSED pending your action** — see §"Remaining Blockers".

---

## 1. Executive Summary

- `RAZORPAY_WEBHOOK_SECRET` written to local git-ignored `backend/.env` (one line, upsert, no duplicate). `RAZORPAY_MODE=test`. Key ID/Secret already present. `settings.razorpay_configured=True`, `RazorpayGateway.is_enabled()=True`, webhook secret is distinct from key secret.
- **Secret hygiene PASS** — `backend/.env` untracked & git-ignored; no real secret in any tracked file / `.env.example` / docs / test fixture.
- **zrok PASS** — local and public `/api/v1/health` return identical `{"status":"ok",...,"db":"ok"}`.
- **Public webhook reachable PASS** — internet → zrok → localhost:8000 → FastAPI route confirmed. Unsigned, bad-signature, and signed-then-tampered deliveries are all safely `rejected` (HTTP 200, `processing_status:"rejected"`), validation untouched.
- **Real webhook-secret verification PASS** — a delivery signed with the freshly-configured secret over the **public zrok path** was accepted by the running server (`payment_webhook_events.signature_valid = true`, then correctly `rejected` with `unknown_gateway_order` because the probe had no real order behind it). The running `uvicorn --reload` worker picked up the new secret after a reload nudge.
- **Regression PASS** — focused Razorpay/payment/refund suites and full `pytest -q`: **407 passed, 4 skipped** (the 4 skips are pre-existing `test_admin_rbac.py` design skips), 0 failures.
- **₹1 pilot event created & published** — `event_id = 18117` "Razorpay Payment Validation", `is_free=false`, `ticket_price=1.00`, config `id = 7138` (`gateway=razorpay`, GST off, INR). **`event_id=392` not touched.**
- **Alumni tester verified** — `TEST_ALUMNI_UID_001` / `NITK2020CS001` → auth exchange OK, profile resolves, eligibility `eligible`, `payment_required=true`, `ticket_price=1.00`.
- **FREE flow live PASS** — register → `registered` immediately, `latest_order_id=None`, 0 payment orders → cancel → `cancelled`, refund status `none`, no refund row.
- **Real Razorpay Test order created live** — `POST /payment-orders/{id}/attempts` on the pilot called Razorpay `POST /v1/orders` with Test credentials and returned a genuine `order_TZ9LcRERNO16gK` (confirmed by a direct Razorpay `GET /v1/orders/...` → `amount=100`, `amount_due=100`, `currency=INR`, `status=created`). Checkout payload: `provider_order_id`, `key_id=rzp_test_…` (public), `amount_minor=100`, `currency=INR` — **no secret**.
- **Live security PASS** — fake browser success (bad signature) → `400 checkout_signature_invalid`; cross-user verify-checkout / cancel / refund-status → `404`; tampered webhook body → `rejected`.
- **NOT yet live-verified (needs your browser + Dashboard):** completed Test payment, `verify-checkout` capture, real `payment.captured`/`order.paid` webhook, failure+retry, paid cancellation + full ₹1 refund, refund webhooks.

---

## 2. Manual Prerequisites Confirmed

| Prerequisite | State |
|---|---|
| FastAPI running on :8000 | YES (PID observed; `uvicorn app.main:app --reload`) |
| Public zrok share reachable | YES — `https://y5pym24pm6ze.shares.zrok.io` |
| Razorpay Test Key ID / Key Secret in `backend/.env` | YES (masked verification below) |
| `RAZORPAY_WEBHOOK_SECRET` in `backend/.env` | YES — configured this run |
| Running server reloaded to pick up webhook secret | YES — verified via signed probe (`signature_valid=true`) |
| Razorpay Dashboard in TEST mode + webhook active + 7 events selected | **NOT CONFIRMED — awaiting your YES/NO** (§4 below) |
| Browser available to complete a Test Checkout payment | **Required — awaiting your action** |

---

## 3. Local Secret Configuration

`backend/.env` (git-ignored at `.gitignore:164`, untracked):

```
RAZORPAY_KEY_ID=rzp_test_****Yuoo        (present)
RAZORPAY_KEY_SECRET=********             (present, 24 chars)
RAZORPAY_WEBHOOK_SECRET=********         (present, 15 chars)  ← added this run, exactly one line
RAZORPAY_MODE=test
```

- `settings.razorpay_configured = True`
- `RazorpayGateway.is_enabled(settings) = True`
- `webhook_secret != key_secret` → **True** (not copied)
- `git status`: only 2 modified tracked files (`tests/test_razorpay_gateway.py`, `tests/test_payment_gateway_foundation.py` — the `delenv`→`setenv("")` isolation fixes from the credential task). `backend/.env` not tracked, not staged.
- `git grep` for the real Key ID / Key Secret / Webhook Secret across the tracked tree → **not found**.
- `backend/.env.example` → placeholders only (`RAZORPAY_KEY_ID=`, `RAZORPAY_KEY_SECRET=`, `RAZORPAY_WEBHOOK_SECRET=`, `RAZORPAY_MODE=test`).

---

## 4. zrok / Public Webhook Reachability

| Probe | Result |
|---|---|
| `curl http://127.0.0.1:8000/api/v1/health` | `200 {"status":"ok","version":"0.1.0-alpha","env":"development","db":"ok"}` |
| `curl https://y5pym24pm6ze.shares.zrok.io/api/v1/health` | `200` — identical body |
| `POST …/razorpay/webhook` no signature | `200 {"status":"rejected","processing_status":"rejected"}` |
| `POST …/razorpay/webhook` `X-Razorpay-Signature: deadbeef` | `200 rejected` |
| `POST …/razorpay/webhook` signed with real secret, fresh `created_at`, bogus order | `200 rejected`; DB: `signature_valid=true`, `error_code=unknown_gateway_order` |
| `POST …/razorpay/webhook` signed then body mutated (+1 byte) | `200 rejected` |

**Proves:** internet → zrok → localhost:8000 → FastAPI webhook route; raw-body HMAC verification with the real secret succeeds; freshness accepted; unknown-order and tamper correctly rejected. Validation was **not** weakened for any probe.

---

## 5. Razorpay Dashboard Webhook Configuration

**AWAITING YOUR CONFIRMATION.** I cannot inspect the Razorpay Dashboard. Please answer:

- Webhook configured in Razorpay Dashboard (URL = `https://y5pym24pm6ze.shares.zrok.io/api/v1/payment-gateways/razorpay/webhook`, **Active**): **YES / NO**
- Events selected — `payment.authorized`, `payment.captured`, `payment.failed`, `order.paid`, `refund.created`, `refund.processed`, `refund.failed`: **YES / NO**
- Dashboard in **TEST** mode: **YES / NO**

---

## 6. Backend Restart / Settings Verification

The running `uvicorn --reload` worker was nudged to reload (a no-op `touch app/main.py`) so `get_settings()` (which is `@lru_cache`d) re-read `backend/.env`. **Verified working:** a webhook signed with the new secret is now accepted by the live server (§4). Health stayed `200` throughout — no downtime, no duplicate process, nothing killed.

If you prefer a clean restart instead:
```
cd backend
source .venv/bin/activate
EVENTS_DB_URL="postgresql://ananth@localhost:5432/events_db" \
  python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 7. Regression Results

| Suite | Result |
|---|---|
| `test_razorpay_gateway.py` | pass |
| `test_razorpay_checkout_and_webhook.py` | pass |
| `test_payment_refunds.py` | pass |
| `test_per_event_gateway.py` | pass |
| `test_free_flow_regression.py` | pass |
| `test_payment_gateway_foundation.py` | pass |
| `test_admin_signout_regression.py` | pass |
| **`pytest -q` (full)** | **407 passed, 4 skipped, 0 failed** |

The 4 skips are pre-existing `test_admin_rbac.py` design skips (`create_event` / `list_all_events` have no `event_id` to scope). Adapter/integration tests use the offline fake — no real API traffic during the suite.

---

## 8. Free Event Live Flow

`event_id` (throwaway free event) → publish → `TEST_ALUMNI_UID_001` registers.

| Step | Result |
|---|---|
| register | `201`, `status=registered` |
| `GET /events/{id}/my-registration` | `status=registered`, `latest_order_id=None` |
| DB `payment_orders` for this registration | `0` |
| `POST /registrations/{id}/cancel` | `200`, `status="none"`, message "No payment was collected…" |
| `GET /registrations/{id}/refund` | `200`, `status="none"` |
| DB `payment_refunds` for this registration | `0` |

**PASS.**

---

## 9. ₹1 Pilot Event

| Field | Value |
|---|---|
| pilot event ID | **18117** |
| title | Razorpay Payment Validation |
| is_free | false |
| price / currency | ₹1.00 / INR |
| GST | disabled |
| payment configuration ID | **7138** (key `razorpay-pilot-44f56fe0`, version 1) |
| gateway | **razorpay** |
| status | published |
| `event_id=392` | **untouched** |

---

## 10. Real Razorpay Order Creation

`register (event 18117)` → `seat_held`; `POST /registrations/{id}/payment-order` → order `ORD-…` (`gateway=razorpay`, `final_amount=1.00 INR`, `registration_status=payment_pending`); `POST /payment-orders/{id}/attempts` (body `{}`) → attempt `ATT-…` `status=initiated`, `gateway=razorpay`.

**Razorpay Test order created:** `order_TZ9LcRERNO16gK`
- checkout payload returned to client: `{ provider:"razorpay", provider_order_id:"order_TZ9LcRERNO16gK", key_id:"rzp_test_…", amount_minor:100, currency:"INR" }` — **no secret**
- direct `GET https://api.razorpay.com/v1/orders/order_TZ9LcRERNO16gK` (Test auth) → `200`: `amount=100`, `amount_paid=0`, `amount_due=100`, `currency=INR`, `status=created`
- DB attempt row: `gateway_order_ref=order_TZ9LcRERNO16gK`, `amount=1.00 INR`, `status=initiated`

**PASS** — ₹1.00 → exactly 100 paise, INR, genuine provider order.

> Note: the pilot order/attempt above (`ORD-sOq6UgLf9mJs` / `ATT-jHIDhXhjx9Bh` / `order_TZ9LcRERNO16gK`) has a 20-minute session/seat-hold window. If it has expired by the time you run Checkout, re-run register → payment-order → attempts on event 18117 to mint a fresh Razorpay order, then use that `provider_order_id`.

---

## 11. Checkout Verification

**NOT YET LIVE-VERIFIED — requires a completed browser Test payment.** Endpoint and server-side logic are implemented and unit/integration-tested (`test_razorpay_checkout_and_webhook.py`): signature gate → server-stored order-id match → authoritative `query_payment_status` → amount/currency re-check → capture; a browser reporting success with a bad/absent signature is rejected (`400 checkout_signature_invalid` — **verified live in §17**).

To complete: after Checkout, `POST /api/v1/payment-orders/{ORDER_ID}/verify-checkout` with `{razorpay_payment_id, razorpay_order_id, razorpay_signature}` from the Checkout handler.

---

## 12. Webhook Deliveries Observed

| Delivery | Observed |
|---|---|
| unsigned probe | `rejected` (invalid_signature) |
| bad-signature probe | `rejected` (invalid_signature) |
| real-secret-signed probe, bogus order | **`signature_valid=true`**, then `rejected` (unknown_gateway_order) |
| signed-then-tampered body | `rejected` (invalid_signature) |
| **real `payment.captured` / `order.paid` from Razorpay** | **not yet — no Test payment completed** |
| **real `refund.*` from Razorpay** | **not yet — no refund issued** |

`X-Razorpay-Event-Id` handling, dedupe/idempotency, freshness, and order/payment correlation are covered by `test_razorpay_checkout_and_webhook.py`; live confirmation of the real captured/refund events is pending the browser step + Dashboard config.

---

## 13. Failure + Retry

**NOT LIVE-VERIFIED.** Razorpay Test Mode has no server-side "simulate a failed payment" for standard Checkout; it requires selecting a failure instrument in the browser (e.g. a failing test card / `failure@razorpay` UPI). Covered by automated tests (`payment.failed` webhook → attempt `failed`, registration `payment_failed`; retry → new attempt → success). Mark **PARTIAL / NOT LIVE VERIFIED** until run in the browser.

---

## 14. Cancellation

**NOT YET LIVE-VERIFIED for the paid path** (needs a captured payment first). Free-path cancellation verified live (§8). Paid-path logic (owner check, captured-payment lookup, one refund row, ₹1.00 amount, provider refund called once, provider refund id persisted, registration → cancelled) is covered by `test_payment_refunds.py` including 5-way concurrency and provider-failure safety.

---

## 15. Full Refund

**NOT YET LIVE-VERIFIED** — depends on a live captured ₹1 payment. On a confirmed paid pilot registration: `POST /api/v1/registrations/{id}/cancel` → creates exactly one `payment_refunds` row (amount ₹1.00), calls Razorpay `POST /v1/payments/{id}/refund` once with an `Idempotency-Key`, persists `provider_refund_id`, sets registration `cancelled`.

---

## 16. Refund Status / Webhooks

**NOT YET LIVE-VERIFIED.** `GET /api/v1/registrations/{id}/refund` returns a provider-backed status (`refund_pending|refund_processed|refund_failed`), refreshing via `query_refund` while non-terminal, and never reports "processed" until the provider says so. Real `refund.processed` / `refund.failed` webhook verification pending.

---

## 17. Security Verification (live, against :8000 / public URL)

| Check | Result |
|---|---|
| unsigned webhook rejected | PASS (`rejected` / invalid_signature) |
| bad-signature webhook rejected | PASS |
| tampered webhook body rejected | PASS |
| real-secret-signed webhook accepted at signature layer | PASS (`signature_valid=true`) |
| fake browser payment success rejected | PASS (`400 checkout_signature_invalid`, no capture) |
| cross-user `verify-checkout` denied | PASS (`404 payment_order_not_found`) |
| cross-user `cancel` denied | PASS (`404 registration_not_found`) |
| cross-user refund-status denied | PASS (`404 registration_not_found`) |
| no secret leakage (checkout payload / responses / tracked files / logs) | PASS |
| duplicate cancel/refund → one logical refund | PASS (automated — `test_payment_refunds.py`); live pending a captured payment |

---

## 18. Acceptance Criteria

| Criterion | Grade |
|---|---|
| webhook secret safely configured | PASS |
| backend settings load webhook secret | PASS |
| no secret leakage | PASS |
| zrok health works | PASS |
| public webhook reachable | PASS |
| unsigned webhook rejected | PASS |
| Dashboard webhook active | **BLOCKED — awaiting your YES/NO** |
| required events selected | **BLOCKED — awaiting your YES/NO** |
| backend restarted with settings | PASS (reload nudge; signed-probe verified) |
| focused regression green | PASS |
| full regression green | PASS (407/4) |
| free flow verified | PASS |
| free cancellation verified | PASS |
| ₹1 Razorpay event published | PASS (event 18117 / config 7138) |
| active alumni tester verified | PASS |
| real Razorpay Test order created | PASS (`order_TZ9LcRERNO16gK`) |
| checkout payload = 100 paise | PASS |
| checkout success verified server-side | NOT TESTED — needs browser payment |
| authoritative captured/paid confirmed | NOT TESTED — needs browser payment |
| registration confirmed (paid) | NOT TESTED — needs browser payment |
| real webhook received | NOT TESTED — needs browser payment + Dashboard |
| raw-body signature verification passed | PASS (real-secret-signed probe) |
| webhook dedupe/idempotency passed | PASS (automated); live pending real event |
| failure/retry live-tested | PARTIAL / NOT LIVE VERIFIED |
| paid cancellation works | NOT TESTED live (automated PASS) |
| full ₹1 refund created | NOT TESTED live (automated PASS) |
| provider refund ID persisted | NOT TESTED live (automated PASS) |
| refund status query works | NOT TESTED live (automated PASS) |
| refund webhook verified if delivered | NOT TESTED |
| duplicate refund remains one logical refund | PASS (automated); live pending |
| RGIS completed | PASS (below) |
| DoD completed | PASS (below) |
| report created | PASS (this document) |

---

## 19. RGIS

- **R = PARTIAL** — free / order-creation / webhook-signature / security paths are repeatable and green live; paid-capture / retry / refund are proven by the automated suite (407/4) but not yet exercised against a live completed Test payment.
- **G = PASS** — Firebase/alumni ownership enforced (cross-user calls 404 live); per-event gateway config used (pilot = razorpay, event 392 untouched); admin RBAC + audit intact; regression green.
- **I = PARTIAL** — real Razorpay Test Mode order creation works through `PaymentGateway`/`GatewayRegistry`, and the zrok webhook path + real-secret signature verification are confirmed live. Full capture/refund round-trip pending the browser Checkout step.
- **S = PASS** — secrets server-only and absent from responses/logs/tracked files; raw-body HMAC verified with `compare_digest`; unsigned/bad/tampered webhooks and fake browser success all rejected live; amount/currency server-authoritative; cross-user IDOR denied live.

---

## 20. DoD

```
webhook secret config:     PASS
zrok reachability:         PASS
dashboard webhook:         BLOCKED (awaiting your YES/NO)
settings load:             PASS
free flow:                 PASS
₹1 event:                  PASS (event 18117, config 7138)
real Razorpay order:       PASS (order_TZ9LcRERNO16gK)
checkout verification:     NOT TESTED (needs browser payment)
real webhook:              NOT TESTED (needs browser payment + dashboard)
failure/retry:             PARTIAL / NOT LIVE VERIFIED
cancel:                    NOT TESTED live (automated PASS)
refund:                    NOT TESTED live (automated PASS)
refund status:             NOT TESTED live (automated PASS)
security:                  PASS (live IDOR + signature + tamper checks)
focused regression:        PASS
full regression:           PASS (407 passed / 4 skipped)
RGIS:                      PASS (R/I PARTIAL pending live capture)
report:                    PASS
```

---

## 21. Known Limitations

- Razorpay standard Checkout has no server-side "complete/fail a test payment" API — the paid capture, real webhook, and refund flows require a human browser interaction on Razorpay's hosted Checkout.
- The zrok share URL is ephemeral; if the share is recreated the Dashboard webhook URL must be updated.
- `RAZORPAY_MODE` is informational beyond `is_enabled`'s test/live sanity check — no hard guard yet against `live` outside a production deploy (carried from the prior sprint).
- Live pilot order `order_TZ9LcRERNO16gK` expires ~20 min after creation; re-mint if stale.

---

## 22. Remaining Blockers

1. **Razorpay Dashboard confirmation** — is the webhook (`…/api/v1/payment-gateways/razorpay/webhook`) Active in **Test** mode with the 7 events selected? (YES/NO ×3 — §5).
2. **Browser Test Checkout** — open Razorpay Checkout for a razorpay pilot order (`order_TZ9LcRERNO16gK`, or a freshly minted one on event 18117) and pay with a Test instrument:
   - success: card `4111 1111 1111 1111`, any future expiry, any CVV, any name — **or** UPI `success@razorpay`
   - failure (for §13): UPI `failure@razorpay` or a failing test card
   Then send me the `razorpay_payment_id` + `razorpay_signature` from the handler (or just confirm the payment completed and the webhook fired), and I will run `verify-checkout` + observe the webhook + drive the cancellation/refund flows.

---

## 23. Exactly One Recommended Next Step

**Confirm the Razorpay Dashboard webhook (Test mode, Active, 7 events) and complete one ₹1 Test Checkout payment in the browser for a razorpay pilot order**; then this session resumes at `verify-checkout` and runs the paid-capture → webhook → cancellation → full-refund → refund-webhook sequence to close out live verification. Do not start frontend integration before that.
