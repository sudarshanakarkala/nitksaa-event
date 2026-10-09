# ISSUE-006 Registration Quantity Test Report

**Date:** 2026-10-08. Updated 2026-10-09 with the closure audit (section 14) and the manual verification results (section 7).
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `1684f3d` (branch `main`), which contains the ISSUE-001, ISSUE-002 and ISSUE-003 fixes.
**Fix commit:** `8e83a1e` (branch `main`)
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, `dio` 5.9.2, `go_router` 17.2.3, `flutter_riverpod` 2.6.1, Chrome 154 for the browser tests
**Final result:** PASS

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-006 |
| Severity | P0 |
| Area | Registration / Pricing / Payment |
| Status | DONE. Committed as `8e83a1e`. Deployed on 2026-10-08. Manual browser verification run on 2026-10-08 and reported PASS on 2026-10-09. |

The app let an attendee choose 1 to 4 passes and showed "Confirm & Pay ₹(price × N)". The backend made one registration, held one seat and charged for one registration.

---

## 2. Product Decision

One attendee = one registration = one pass.

One authenticated, eligible alumni makes one registration, which reserves one seat and carries one payment. Multi-pass and group booking are not part of the stabilization release.

---

## 3. Root Cause

The full analysis is in `ISSUE-006_REGISTRATION_QUANTITY.md`.

### Unsupported frontend quantity

The registration form had a "No of passes" dropdown in both its Material and Cupertino versions. Its options came from two event fields the API never returns, so they were always the hardcoded fallback, 1 to 4. The choice went to checkout in the URL (`?quantity=N`) and from there into the registration request.

### Backend registration contract

`RegisterRequest` accepts `attendee_note` only. Unknown keys are ignored, so `quantity` was dropped without an error. One call makes one registration for the caller and takes one seat.

### Misleading client price multiplication

Checkout computed `ticket_price × quantity`, showed it as "Grand Total", and put it on the button.

### Actual server payment flow

The backend prices the order from the event's payment configuration, with no quantity input. The app opens Razorpay with `checkout.amount_minor` from the payment attempt. The charge was therefore always the one-registration amount, whatever the app had displayed.

---

## 4. Fix

### Files Changed

| File | Change |
|---|---|
| `frontend/lib/features/events/presentation/screens/event_detail_screen.dart` (+3 −85) | Dropdown, option list and pass-count state removed from both forms; `quantity` removed from the checkout URL |
| `frontend/lib/features/events/presentation/screens/checkout_screen.dart` (+9 −35) | `quantity` removed from the screen; "No of passes" and "Grand Total" rows removed; button no longer shows a multiplied amount |
| `frontend/lib/routes/app_router.dart` (+1 −7) | Checkout route no longer reads `quantity` |
| `frontend/lib/features/events/data/events_repository.dart` (+5 −7) | `registerForEvent` has no `quantity` parameter and sends `attendee_note` only |
| `frontend/lib/features/events/presentation/providers/event_detail_provider.dart` (+2 −2) | `register` has no `quantity` parameter |
| `frontend/test/features/events/registration_quantity_test.dart` (new, 205 lines) | 9 tests: registration form and registration request |
| `frontend/test/features/events/checkout_single_registration_test.dart` (new, 271 lines) | 12 browser tests on the real `CheckoutScreen` |
| `frontend/test/features/events/registration_quantity_source_test.dart` (new, 38 lines) | 6 tests: no quantity wording in the attendee-flow source files |
| `frontend/test/features/events/support/registration_backend_fake.dart` (new, 310 lines) | Fake backend at the HTTP level, so request bodies can be inspected |
| `frontend/test/features/events/support/fake_razorpay_web.dart` (new, 77 lines) | Fake `window.Razorpay` that records what the app opens it with |
| `frontend/test/features/events/support/auth_isolation_fakes.dart` (+2 −3) | ISSUE-001 fake: `quantity` removed from the overridden `registerForEvent` so it still compiles |
| `frontend/test/features/events/event_detail_auth_isolation_test.dart` (+2 −2) | ISSUE-001 test: two calls no longer pass `quantity: 1` |
| `frontend/test/features/events/checkout_auth_isolation_test.dart` (+1 −1) | ISSUE-001 test: finds the checkout button by its new label |
| `docs/issues/ISSUE-006_REGISTRATION_QUANTITY.md` (new) | Issue analysis |
| `docs/issues/ISSUE-006_REGISTRATION_QUANTITY_TEST_REPORT.md` (new) | This report |

No backend, admin, auth or payment-service file is changed. `frontend/build/web` was rebuilt; it is git-ignored.

### Quantity Removal

Deleted from `event_detail_screen.dart`: `_selectedPassCount`, `_passOptions` (the 1-to-4 fallback and the min/max logic), `_buildPassesDropdown`, and its use in both forms. Nothing replaces them. The form now has Badge name, Email, Phone and Notes.

### Registration Contract

The request body is now:

```json
{ "attendee_note": "..." }
```

There is no `quantity` key, not even `"quantity": 1`. No code path can add one, because neither `registerForEvent` nor `EventDetailNotifier.register` has a parameter for it.

### Checkout Changes

| | Before | After |
|---|---|---|
| Constructor | `CheckoutScreen(eventId, quantity, notes)` | `CheckoutScreen(eventId, notes)` |
| Fee table, paid event | Ticket Price · No of passes · Grand Total | Registration Fee |
| Fee table, free event | Free Event · No of passes · Grand Total | Free Event |
| Button, paid event | "Confirm & Pay ₹(price × N)" | "Proceed to Payment" |
| Button, free event | "Confirm Registration" | "Confirm Registration" |

The paid button no longer shows an amount. The only figure the app holds is the public `ticket_price`, which is not the charged amount when GST or a convenience fee is configured. Showing the server's amount is ISSUE-007.

### Payment Amount Integrity

The payment code is unchanged. Checkout still calls payment-order, then attempts, then opens Razorpay with `checkout.amount_minor`, then verify-checkout. No price is computed in the app for payment. Tests G and H check this with a backend amount (₹123.45) that is neither the ticket price (₹100.00) nor a multiple of it.

---

## 5. Automated Verification

Commands, from `frontend/`:

```bash
flutter test
flutter test test/features/events/registration_quantity_test.dart \
  test/features/events/registration_quantity_source_test.dart
flutter test --platform chrome \
  test/features/events/checkout_single_registration_test.dart \
  test/features/events/registration_quantity_test.dart
flutter test --platform chrome test/features/auth/ \
  test/features/events/checkout_auth_isolation_test.dart
```

How the tests are built:

- `EventDetailScreen`, `CheckoutScreen`, `EventDetailNotifier` and `EventsRepository` are the real classes. The repository uses a real Dio client whose transport is replaced by a fake backend, so each test reads the JSON that would have gone on the wire.
- The fake backend follows the real one where it matters here: it reads `attendee_note` and ignores any other key, makes one registration per attendee, refuses a second with `409 already_registered`, and sets the payable amount itself.
- The checkout tests are browser-only. `CheckoutScreen` cannot compile for the Dart VM (ISSUE-016), and Razorpay is driven through a fake `window.Razorpay` that records the options it is opened with. No call reaches Razorpay.
- Tests A and B run for both forms: the Material dialog and the Cupertino sheet.

| Test | Expected | Actual | Result |
|---|---|---|---|
| Quantity selector absent (A) | No "No of passes", no passes or quantity wording, no dropdown in either form; "Proceed to Checkout" opens checkout | As expected | PASS |
| Checkout route no quantity (B) | Location is `/events/7/checkout?notes=Vegetarian%20meal`; no `quantity`; notes unchanged | As expected | PASS |
| Register body no quantity (C) | Body is exactly `{"attendee_note": "Vegetarian meal"}`; raw body does not contain `quantity`; an empty note is sent as `{"attendee_note": ""}` | As expected, at the notifier and from the real checkout screen | PASS |
| One registration request (D) | One `POST /events/7/register`, one registration, one seat | As expected | PASS |
| No price × quantity (E) | Paid event at ₹100: "Registration Fee" and ₹100 appear once; no ₹200, ₹300, ₹400; no "Grand Total"; no "Confirm & Pay"; the six attendee-flow source files contain no quantity wording | As expected | PASS |
| One payment order (F) | One `POST /registrations/{id}/payment-order`, for the registration just made; one attempt | As expected | PASS |
| Razorpay uses backend amount_minor (G) | Razorpay opened once with `amount` 12345, not 10000 | 12345 | PASS |
| Order and attempt amount integrity (H) | Order `final_amount` 123.45; attempt `amount_minor` 12345; Razorpay `amount`, `currency`, `order_id` and `key` equal the attempt's values | As expected | PASS |
| Free event (I) | One register request with `attendee_note` only; registration is `registered`; no payment order, no attempt, Razorpay not opened | As expected | PASS |
| Paid event (J) | Register, payment-order, attempts, Razorpay, verify-checkout, each once and in that order; registration ends `registered`; checkout closes. Closing Razorpay instead: one registration, one order, no verification, "Payment cancelled" shown | As expected | PASS |
| Existing registration (K) | A held seat is paid for with no new register request. A duplicate refused by the backend is shown as a failure, with one request, one seat and no payment | As expected | PASS |
| ISSUE-001 regression (L) | 18 on the VM, 1 in Chrome | All pass | PASS |
| ISSUE-002 regression (M) | 1 on the VM, 8 in Chrome | All pass | PASS |
| ISSUE-003 regression (N) | 75 on the VM, 76 in Chrome | All pass | PASS |

### Totals

| | Before ISSUE-006 | After ISSUE-006 |
|---|---|---|
| `flutter test` (VM) | 95 of 95 | 110 of 110 |
| Chrome | 85 of 85 | 106 of 106 |

New tests: 15 on the VM and 21 in Chrome. The 9 tests in `registration_quantity_test.dart` run on both.

### The same tests against the code before the fix

The new tests were run against an untouched checkout of `1684f3d`.

| | Fail | Pass |
|---|---:|---:|
| VM, 15 tests | 9 | 6 |
| Chrome, 21 tests | 8 | 13 |

What failed, and what it showed:

| Test | Observed before the fix |
|---|---|
| A, both forms | "No of passes" found on the form |
| B, both forms | Location was `/events/7/checkout?quantity=1&notes=Vegetarian%20meal` |
| C, from checkout | Body was `{"attendee_note": "Vegetarian meal", "quantity": 1}` |
| I, from checkout | Body was `{"attendee_note": "Wheelchair access", "quantity": 1}` |
| E, paid and free checkout | "No of passes" row present; no "Registration Fee" |
| E, source files | Quantity wording in 5 of the 6 files |

The tests that passed before the fix are the ones about behaviour that was already correct: one registration per request, and Razorpay opened with the backend's amount.

---

## 6. Contract Verification

The backend is not changed. Its registration contract was read from `backend/` at `1684f3d` and from the live API (`https://nitksaa-events-api-246773894709.asia-south1.run.app`) on 2026-10-08, without signing in.

Current `RegisterRequest` (`backend/app/schemas/registrations.py:9-16`):

```python
class RegisterRequest(BaseModel):
    attendee_note: Optional[str] = Field(None, max_length=500)
```

| Where | Quantity present? | Evidence |
|---|---|---|
| `RegisterRequest` | No | One field, `attendee_note`. The live OpenAPI schema is the same. |
| Registration persistence | No | The `INSERT INTO registrations` column list has no quantity (`registration_repository.py:234-239`). `grep -rni quantity backend/app backend/migrations` finds nothing. |
| Capacity accounting | No | Capacity is compared with a count of registration rows (`registration_service.py:149-157`). One row is one seat. |
| Pricing | No | `calculate_price(config)` takes the payment configuration only (`pricing_service.py:23`). |
| Payment order | No | `create_order(registration_id, user, idempotency_key)`; the request body is `idempotency_key` only (`payment_service.py:198`). |
| Payment attempt | No | `amount_minor = rupees_to_paise(order.final_amount)` (`razorpay_gateway.py:228`). |
| Live OpenAPI document | No | The word "quantity" occurs 0 times. |
| Live public event | No | `GET /api/v1/events/public/7` has no `registration_min_quantity` or `registration_max_quantity`. |

Other behaviour confirmed and relied on: a second registration by the same attendee is refused with `409 already_registered`; a paid event's registration starts as `seat_held`; a free event's starts as `registered`.

---

## 7. Manual Verification

**Result: PASS.** One manual run was made on the deployed build, on 2026-10-08 between 06:01 and 06:05 IST. The tester reported its results on 2026-10-09, as PASS or FAIL for each check. No values, screenshots or saved network log were supplied, so the IDs, times and request counts below come from the server logs.

| Field | Value |
|---|---|
| Build tested | `8e83a1e`, live on `https://nitksaa-events.web.app` since 2026-10-08 05:59 IST |
| Run | 2026-10-08, 06:01 to 06:05 IST |
| Results reported | 2026-10-09 |
| Event | #11, "TestOct8": paid, ₹1, capacity 4 |
| Payment mode | `test`, as reported by the tester |
| Registration ID | 14 (server log) |
| Order ID | `ORD-hH78c5dB7fAY` (server log) |
| Outcome | Paid. One `verify-checkout`, and the registration is confirmed (server log, public API) |
| Screenshots, network log | None supplied |

### Prerequisites

- **A deploy.** The live site serves `main.dart.js` with SHA-256 `cc569eb8…c298`, last modified 2026-10-08 00:29:12 GMT (05:59 IST). It is byte-for-byte the build of `8e83a1e`, and contains none of "No of passes", "Grand Total", "Confirm & Pay" or `quantity=`. Before that deploy the site served the ISSUE-003 build (`0ccf41e1…dcb3`), which had the selector. A local run cannot stand in for the deployed site, because the production backend's CORS refuses `localhost` origins.
- **An event to register for.** #11, "TestOct8", was published on 2026-10-08 at 06:03 IST. It is paid (₹1), has a capacity of 4, and is open for registration. There is no free event, so the free-event check was not run by hand.
- **A signed-in eligible alumni account.** One account was used. Which one is not on record.

### Server-side record of the run

Read on 2026-10-09 from the Cloud Run request logs of `nitksaa-events-api` (a read-only query) and from the public event API. Times are IST on 2026-10-08.

| Time | Request | Status |
|---|---|---|
| 06:01:38 | `POST /api/v1/auth/firebase` (sign-in) | 200 |
| 06:04:03 | `GET /api/v1/events/11/my-registration` (event page opened) | 404, no registration yet |
| 06:04:42 | `POST /api/v1/events/11/register` | 201 |
| 06:04:42 | `POST /api/v1/registrations/14/payment-order` | 201 |
| 06:04:42 | `POST /api/v1/payment-orders/ORD-hH78c5dB7fAY/attempts` | 201 |
| 06:04:54 to 06:04:55 | `POST /api/v1/payments/webhook`, three times | 200 |
| 06:05:07 | `POST /api/v1/payment-orders/ORD-hH78c5dB7fAY/verify-checkout` | 200 |
| 06:05:08 | `GET /api/v1/events/11/my-registration` | 200 |

What this shows:

- One register request, one payment order, one attempt and one verification, in that order.
- The registration is confirmed. The public API reports `registered_count` 1 for #11, and that figure counts rows in status `registered` only (`backend/app/repositories/events_repository.py:11`).
- This is the only browser session on the deployed build. Between the deploy and 06:10 IST on 2026-10-09 the attendee site made 47 API requests, preflights excluded. All of them fall between 06:01:19 and 06:05:08 IST on 2026-10-08, and they include one sign-in. The tester's results therefore refer to this run.

What it does not show: the request body, the payment mode, `final_amount`, `checkout.amount_minor`, the amount in the Razorpay modal, anything on screen, or which account was used. The request logs hold none of these. Those points rest on the tester's report.

### Live checks that were run, without signing in

These are read-only and change no data.

| Check | Observed |
|---|---|
| Live OpenAPI, `RegisterRequest` | `attendee_note` only |
| Live OpenAPI, "quantity" | 0 occurrences |
| Live OpenAPI, `PaymentCheckout` | `provider`, `provider_order_id`, `key_id`, `amount_minor`, `currency` |
| `GET /api/v1/events/public/7` | No quantity fields; `ticket_price` "1.00" |
| Live `main.dart.js` | On 2026-10-08, before the deploy: the ISSUE-003 build, with the pass selector. On 2026-10-09: the ISSUE-006 build, `cc569eb8…c298` |

### Registration UI

In the tables below, "Tester" is the result the tester reported on 2026-10-09.

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. Sign in as an eligible alumni and open an open, upcoming paid event (#11) | Event page with "Register" | Server log: sign-in 200 at 06:01:38; event #11 opened at 06:04:03 with no registration | PASS |
| 2. Press Register | Form with Badge name, Email, Phone, Notes. No "No of passes" and no dropdown | Tester: "No of passes" absent. The dropdown was that control; it was not reported separately | PASS |
| 3. Enter a note and press "Proceed to Checkout" | URL is `/events/{id}/checkout?notes=…`, with no `quantity` | Tester: the URL has no `quantity` | PASS |
| 4. Read the checkout page | One row, "Registration Fee". No quantity, passes or "Grand Total". Button reads "Proceed to Payment" | Not reported. The deployed bundle has "Proceed to Payment" once and none of "No of passes", "Grand Total" or "Confirm & Pay"; tests E cover the page | NOT REPORTED |

### Registration API

| Step | Expected | Actual | Result |
|---|---|---|---|
| 5. Press "Proceed to Payment" | One `POST /api/v1/events/{id}/register` | Tester: exactly one. Server log: one request, 201 | PASS |
| 6. Read its request body | `{"attendee_note": "…"}` and no `quantity` | Tester: `attendee_note` only, and no `quantity` key | PASS |
| 7. Read its response | One `registration_id`; `status` is `seat_held` | Not reported. Server log: registration 14, and a payment order followed | NOT REPORTED |
| 8. Open My Events | One registration for the event | Not reported. Public API: `registered_count` 1 for #11 | NOT REPORTED |

### Payment Integrity

TEST payment mode only.

| Step | Expected | Actual | Result |
|---|---|---|---|
| 9. Read the `/payment-order` response | One request, for the `registration_id` from step 7; note `final_amount`; `payment_mode` is `test` | Tester: exactly one request; `payment_mode` is `test`. `final_amount` not reported. Server log: one request, for registration 14, 201 | PASS |
| 10. Read the `/attempts` response | One request. Note `checkout.amount_minor`, `checkout.currency` and `checkout.provider_order_id`. `amount_minor` equals `final_amount × 100` | Values not reported. Server log: one request, 201 | NOT REPORTED |
| 11. Read the amount in the Razorpay modal | Equals `checkout.amount_minor / 100`; the modal shows its Test Mode ribbon | Tester: the amount equals `checkout.amount_minor / 100`. The figure and the ribbon were not reported | PASS |
| 12. Pay with a Razorpay test method, or close the modal | Paid: one `verify-checkout`, "Payment successful", and the registration is confirmed. Closed: "Payment cancelled", with one registration and one order | Not reported by the tester. Server log: paid. Three webhook calls, one `verify-checkout` (200), registration confirmed | PASS |
| 13. Compare the fee on the checkout page with the Razorpay amount | Equal unless the event has GST or a convenience fee. If they differ, record "ISSUE-006 PASS; ISSUE-007 server pricing gap observed". It is not an ISSUE-006 failure | Not reported | NOT REPORTED |

### Regression (manual)

| Step | Expected | Actual | Result |
|---|---|---|---|
| 14. ISSUE-001: as user A open event X, sign out, sign in as user B, open event X | Nothing of A's appears: no registration, badge name, email or phone | Tester: PASS. Not on the server record: the logs show one attendee sign-in since the deploy, so no second account signed in on this build. The sign-ins before it are from 2026-10-06, on the earlier build | REPORTED PASS |
| 15. ISSUE-002: as user A sign out, then press Google sign-in | The Google account chooser appears and user B can be selected | Tester: PASS. The chooser is drawn by the browser and reaches the server only when the second sign-in completes; none is on record since the deploy | REPORTED PASS |
| 16. ISSUE-003: sign in with a valid account | Sign-in succeeds, with no error message | Tester: PASS. Server log: one sign-in, 200 | PASS |

### Basis for the result

Every ISSUE-006 check the tester reported is PASS, and each agrees with the server logs where the logs can see it: one registration, one payment order, one attempt, one verification.

Steps 4, 7, 8, 10 and 13 were not reported. Steps 4, 7, 8 and 10 are covered by the automated tests on the same bundle, by the bundle's contents or by the server log. Step 13 is the ISSUE-007 observation, and it was not made: the fee shown at checkout was not compared with the Razorpay amount.

Steps 14 and 15 rest on the tester's report and on the automated ISSUE-001 and ISSUE-002 tests (section 8). The server logs do not show a second account on this build.

No access token, `Authorization` header, Firebase token or Razorpay key is recorded in this report.

---

## 8. ISSUE-001/002/003 Regression

### ISSUE-001 — PASS (automated)

- `event_detail_auth_isolation_test.dart`: 18 of 18 on the VM.
- `checkout_auth_isolation_test.dart`: 1 of 1 in Chrome.
- `event_detail_provider.dart` changed in two lines, both in `register`: the `quantity` parameter and its use. The session-bound token, the `autoDispose` provider, the `mounted` checks and the state clearing are untouched.
- Three ISSUE-001 test files were edited so that they compile and find the button: `quantity` removed from one fake and two calls, and one finder changed from "Confirm & Pay" to "Proceed to Payment". No assertion changed.

### ISSUE-002 — PASS (automated)

- `google_sign_in_account_chooser_test.dart`: 1 of 1 on the VM, 3 of 3 in Chrome.
- `google_login_flow_test.dart`: 5 of 5 in Chrome.
- `prompt=select_account` is preserved: `firebase_auth_service.dart:58` still sets it, and the release bundle contains `select_account`.
- No file under `frontend/lib/features/auth/` is changed.

### ISSUE-003 — PASS (automated)

- `backend_auth_exception_test.dart`: 27 of 27 on the VM and in Chrome.
- `auth_error_messages_test.dart`: 22 of 22 on the VM and in Chrome.
- `login_failure_rollback_test.dart`: 26 of 26 on the VM, 27 of 27 in Chrome.
- No auth file is changed.

---

## 9. Static Checks

### flutter test

```bash
flutter test
```

Result: `+110: All tests passed!` (95 before this change.)

ISSUE-006 tests alone:

```bash
flutter test test/features/events/registration_quantity_test.dart \
  test/features/events/registration_quantity_source_test.dart
```

Result: `+15: All tests passed!`

### Chrome tests

```bash
flutter test --platform chrome \
  test/features/events/checkout_single_registration_test.dart \
  test/features/events/registration_quantity_test.dart
```

Result: `+21: All tests passed!`

```bash
flutter test --platform chrome test/features/auth/ \
  test/features/events/checkout_auth_isolation_test.dart
```

Result: `+85: All tests passed!`

### flutter analyze

| | Total | Errors | Warnings | Info |
|---|---:|---:|---:|---:|
| Before ISSUE-006 (`1684f3d`) | 98 | 6 | 36 | 56 |
| After ISSUE-006 | 98 | 6 | 36 | 56 |

- **Pre-existing issues:** all 98. The two lists are identical when line numbers are ignored. `flutter analyze` exits with code 1 before and after: the 6 errors are in `razorpay_payment_io.dart` and come from the missing `razorpay_flutter` package (ISSUE-016).
- **New ISSUE-006 issues:** none. No finding is in any new test file.

One pre-existing warning is close to this change: `_submitRegistration` in `event_detail_screen.dart` is unused. It was unused before, and it was left in place; only its `quantity` argument was removed.

### web build

```bash
flutter build web --release \
  --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
```

Result: succeeded (`✓ Built build/web`, 23.2 s compile).

| Check on `build/web/main.dart.js` | Result |
|---|---|
| "No of passes", "Select number of passes", "per pass" | Absent |
| "Grand Total", "Confirm & Pay", `quantity=` | Absent |
| "Proceed to Payment" | Present once |
| `attendee_note` | Present |
| `select_account` | Present once |
| Production backend URL | Present |
| SHA-256 | `cc569eb8024bbd808cc816d74f293e11840a5b350487396332332684cbabc298` |
| Deployed | Yes, on 2026-10-08 at 05:59 IST. The live file has this SHA-256 |

---

## 10. Source Search

Run from the repository root after the fix.

| Search | Matches |
|---|---|
| `grep -Rni "No of passes" frontend/lib` | None |
| `grep -Rni "No of passes" frontend/test` | 4, all in the new ISSUE-006 tests, which check that the text is absent |
| `grep -Rni "ticketPrice.*quantity" frontend/lib` | None |
| `grep -Rni "grandTotal" frontend/lib/features/events` | None |
| `grep -Rni "quantity\|passes\|per pass" frontend/lib`, outside the two files below | None |
| `grep -Rni "quantity" frontend/lib/features/events` | 24, in the two files below |

The remaining matches:

| File | Matches | Class | Explanation |
|---|---:|---|---|
| `lib/features/events/domain/event.dart` | 6 | Admin-only | `registrationMinQuantity` and `registrationMaxQuantity`, parsed from `registration_min_quantity` / `registration_max_quantity`. The attendee flow no longer reads them. They prefill the admin event form. The API never returns them. |
| `lib/features/events/presentation/screens/manage_events_screen.dart` | 18 | Admin-only | The "Min/Max quantity" fields of the admin event form, their validation, and the two keys in the create/update payload. The backend drops both keys. This is ISSUE-015. |
| `test/features/events/*` | — | Test | The ISSUE-006 tests name `quantity` to assert that it is absent. |

There is no remaining attendee multi-pass flow. The admin fields were not touched, as instructed. They are harmless to attendees now, but an admin who fills them in may believe a pass limit is set.

---

## 11. Remaining Risks

1. **The defect is no longer live.** This build was deployed on 2026-10-08, and the deployed site no longer offers "No of passes".
2. **The manual result is recorded as PASS or FAIL only.** No amounts, screenshots or network log were kept. The wording of the checkout page (step 4) was not reported; it rests on the automated tests and on the contents of the deployed bundle.
3. **ISSUE-007 server pricing remains pending.** Checkout shows the public `ticket_price` as the fee. With GST or a convenience fee configured, Razorpay will charge more than the fee shown. The paid button no longer states an amount, so the app does not promise a wrong total, but it does not show the right one either.
4. **ISSUE-008 recovery remains pending.** Closing Razorpay leaves a held seat that the event page shows as registered, with no way back to payment.
5. **ISSUE-019 form contract remains pending.** Email and phone are still editable and discarded. Notes are still in the URL and not limited to 500 characters; a longer note is refused by the backend with a raw error.
6. **The admin event form still has quantity limits** that do nothing (ISSUE-015).
7. **Old links.** A bookmarked or cached `/checkout?quantity=4` link still opens checkout. The parameter is ignored and checkout is for one registration.
8. **A registration made under the old build** with more than one pass chosen is one registration in the backend. An attendee who did this before the deploy may still expect several passes. Whether any exist can be read from the registration and payment records; the app cannot tell.
9. **Manual testing needs a usable event.** #11, "TestOct8", is usable until it ends at 23:59 IST on 2026-10-10. After that a new TEST event is needed. Creating one is an admin action.
10. **Deploys are invisible to returning browsers for up to an hour** (ISSUE-022). Hard-reload before any manual test.
11. **The ISSUE-001 and ISSUE-002 manual checks are not on the server record for this build.** They were reported PASS, but the logs show one attendee sign-in since the deploy. Their own reports still read CODE PASS — MANUAL E2E PENDING.

---

## 12. Final Result

**PASS**

Automated verification passes (sections 5, 9 and 14). The manual verification on the deployed build passes (section 7): run on 2026-10-08 on event #11 in TEST payment mode, registration 14, order `ORD-hH78c5dB7fAY`, reported on 2026-10-09.

---

## 13. Commit

Commit hash: `8e83a1e`, on `main`, 2026-10-08 06:07 IST. The manual results were recorded afterwards, in a documentation-only follow-up commit.

Commit message, as committed:

```text
fix(payment) ISSUE-006 — Unsupported Multi-Pass Quantity
```

---

## 14. Closure Audit, 2026-10-09

A re-check of the committed fix, run from a clean checkout of `main` at `8e83a1e`. No source file was changed.

### Commit scope

`8e83a1e` changes 16 files: 5 under `frontend/lib/`, 8 under `frontend/test/` and 3 under `docs/issues/`. They are the files listed in section 4, plus a one-line change to the title of `NITKSAA_EVENT_FLUTTER_VERIFICATION_REPORT.md`. Nothing under `backend/` is changed; `git diff 1684f3d 8e83a1e -- backend` is empty.

### Automated results

| Run | Result |
|---|---|
| `flutter test` (VM, all) | 110 of 110 |
| ISSUE-006 tests, VM | 15 of 15 |
| ISSUE-006 tests, Chrome | 21 of 21 |
| Auth tests and checkout isolation, Chrome | 85 of 85 |
| Chrome, total | 106 of 106 |
| ISSUE-001, VM / Chrome | 18 of 18 / 1 of 1 |
| ISSUE-002, VM / Chrome | 1 of 1 / 8 of 8 |
| ISSUE-003, VM / Chrome | 75 of 75 / 76 of 76 |
| `flutter analyze` | 98 findings: 6 errors, 36 warnings, 56 info |
| `flutter build web --release` | Succeeded |

No test was skipped. The analyzer was also run on clean exports of `1684f3d` and of `8e83a1e`: 98 findings each, and the two lists are identical when line numbers are ignored. No finding is in an ISSUE-006 test file. The 6 errors are the missing `razorpay_flutter` package (ISSUE-016).

### Build and deploy

The release build of `8e83a1e` has SHA-256 `cc569eb8024bbd808cc816d74f293e11840a5b350487396332332684cbabc298`, the same as the build recorded in section 9. The file served by `https://nitksaa-events.web.app/main.dart.js` is byte-for-byte the same file. The deployed attendee site is therefore the committed fix.

### Source search

The searches of section 10 give the same results. The remaining `quantity` matches under `frontend/lib` are the 6 in `domain/event.dart` and the 18 in `manage_events_screen.dart`, all admin-only.

### Closure

The audit left one thing open: the browser-side checks of section 7. The tester supplied them later on 2026-10-09, and they are recorded there. The final result is PASS, and the remediation plan's ISSUE-006 entry is DONE with commit `8e83a1e`.
