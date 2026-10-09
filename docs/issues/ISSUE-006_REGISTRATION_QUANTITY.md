# ISSUE-006 — Unsupported Multi-Pass Quantity

## Severity

P0 — financial expectation / registration contract integrity

## Status

DONE

The change is committed as `8e83a1e` and has been live on `https://nitksaa-events.web.app` since 2026-10-08. Automated verification passes. The manual browser verification was run on the deployed build on 2026-10-08 and reported PASS on 2026-10-09. See "Final Status".

## Product Decision

One authenticated alumni = one registration = one pass.

For the stabilization release there is no multi-pass purchase. One authenticated, eligible attendee makes one registration, which reserves one seat and carries one payment. Group or multi-pass booking would need its own product and backend design (stored quantity, pass ownership, capacity, pricing, payment, cancellation, refund, check-in, badges) and is not part of this issue.

## Gap

The app let an attendee choose 1 to 4 passes, showed the price multiplied by that number, and labelled the button "Confirm & Pay ₹(price × N)". The backend has no quantity anywhere. It made one registration, held one seat and charged for one registration.

Example, for an event with a ticket price of ₹1 and 4 passes chosen:

| | App | Backend |
|---|---|---|
| Passes | 4 | 1 registration, 1 seat |
| Amount | "Confirm & Pay ₹4" | One server-priced order, charged through Razorpay |

The attendee was promised four passes for ₹4 and received one seat.

## Root Cause

Findings from the code at commit `1684f3d`, before this fix. Line numbers refer to that commit.

### Flutter UI

- `event_detail_screen.dart:26` held the choice in `_selectedPassCount`, reset to the first option each time the form opened (`:1296`).
- `_passOptions` (`:1550-1556`) built the options from `event.registrationMinQuantity` and `event.registrationMaxQuantity`, falling back to 1 and 4. The public event API never returns those two fields, so the options were always 1, 2, 3, 4.
- `_buildPassesDropdown` (`:1559-1622`) drew the "No of passes" dropdown. It was used in both registration forms: the Cupertino sheet (`:1365`) and the Material dialog (`:1426`).
- `checkout_screen.dart:151-152` computed `grandTotal = unitPrice * widget.quantity`, where `unitPrice` is the public `ticket_price`. The fee table had a "No of passes" row (`:213-222`) and a "Grand Total" row (`:223-232`). The button label multiplied again (`:249`).
- Nothing after registration used the quantity: no badge, pass or My Events screen reads it.

### Navigation

- `_proceedToCheckout` (`event_detail_screen.dart:1683-1688`) pushed `/events/{id}/checkout?quantity=N&notes=…`.
- `app_router.dart:69-74` read `quantity` from the query string, defaulting to 1, and passed it to `CheckoutScreen`.
- `CheckoutScreen` took it as a constructor argument (`checkout_screen.dart:16`, `:21`). These were the only places that read it.

### Registration Request

- `CheckoutScreen._confirmRegistration` called `notifier.register(eventId, notes, quantity: widget.quantity)` (`:291-295`).
- `EventDetailNotifier.register` (`event_detail_provider.dart:124`) passed it on. The notifier kept no quantity state, so removing the parameter does not touch the session binding added for ISSUE-001.
- `EventsRepository.registerForEvent` (`events_repository.dart:205-220`) sent it:

```json
{ "attendee_note": "...", "quantity": N }
```

  The key was sent whenever checkout registered, including `"quantity": 1` when the attendee left the default.

### Backend Contract

The backend is unchanged by this fix. Confirmed from `backend/` at `1684f3d` and from the live API on 2026-10-08:

| Point | Finding |
|---|---|
| `RegisterRequest` | One field: `attendee_note`, optional, at most 500 characters (`app/schemas/registrations.py:9-16`). Pydantic ignores unknown keys, so `quantity` was dropped without an error. |
| Rows created | One per call, for the caller (`registration_service.py:160-176`). The `INSERT` has no quantity column (`registration_repository.py:234-239`). |
| Duplicate protection | A caller who already holds a registration for the event gets `409 already_registered`, checked under `SELECT … FOR UPDATE` on the event (`registration_service.py:109-147`). |
| Capacity | One registration counts as one seat (`:149-157`). |
| Paid event | The row is created as `seat_held` with a hold expiry (`:170-175`). |
| Free event | The row is created as `registered` (`:170`). |
| Pricing | `calculate_price(config)` takes the event's payment configuration and nothing else (`pricing_service.py:23`). |
| Payment order | `create_order(registration_id, user, idempotency_key)` prices from the configuration (`payment_service.py:198-279`). |
| Whole backend | `grep -rni quantity backend/app backend/migrations` finds nothing. |
| Live OpenAPI | `RegisterRequest` has only `attendee_note`. The word "quantity" does not occur in the document. |

### Payment Amount Flow

```text
POST /events/{id}/register                 → one registration (seat_held)
POST /registrations/{id}/payment-order     → final_amount = calculate_price(config)
POST /payment-orders/{ORD}/attempts        → checkout.amount_minor = final_amount in paise
Razorpay                                   ← amount = checkout.amount_minor
POST /payment-orders/{ORD}/verify-checkout → backend confirms
```

The app has always opened Razorpay with `checkout.amount_minor` from the attempt (`checkout_screen.dart:343`), never with its own total. So the amount charged was correct for one registration. What was wrong was everything the app said before that point.

## Before Behaviour

```text
Register
→ registration form with "No of passes" [1 ▼]  (options 1 to 4)
→ /events/7/checkout?quantity=4&notes=…
→ fee table: Ticket Price ₹1 · No of passes 4 · Grand Total ₹4
→ button: "Confirm & Pay ₹4"
→ POST /register {"attendee_note": "…", "quantity": 4}
→ backend: one registration, one seat
→ Razorpay opens for the backend's one-registration amount
```

## Expected Behaviour

```text
Register
→ registration form with no pass count
→ /events/7/checkout?notes=…
→ fee table: Registration Fee ₹1
→ button: "Proceed to Payment"
→ POST /register {"attendee_note": "…"}
→ backend: one registration, one seat
→ one payment order, one attempt
→ Razorpay opens for checkout.amount_minor
```

A free event is the same without the payment steps, and its button reads "Confirm Registration".

## Fix Strategy

The quantity is removed, not hidden or pinned to 1.

1. **Form.** The dropdown, its option list, its state and both uses are deleted.
2. **Route.** The checkout URL no longer has `quantity`. The router no longer reads it. An old link that still has `?quantity=4` opens checkout for one registration, because nothing reads the parameter.
3. **Checkout.** `CheckoutScreen` has no quantity. The fee table has one row, "Registration Fee", showing the public event fee. The "No of passes" and "Grand Total" rows are gone.
4. **Button.** "Confirm & Pay ₹X" became "Proceed to Payment", with no amount. The only figure the app has is the public `ticket_price`, which is not the charged amount when GST or a convenience fee is configured. ISSUE-007 will put the server's amount on this screen.
5. **Request.** `registerForEvent` and `EventDetailNotifier.register` have no quantity parameter. The body is `{"attendee_note": …}`.
6. **Payment.** Unchanged. Razorpay still receives `checkout.amount_minor` from the backend. No price formula was added to the app.

Not changed: the backend, the order, attempt and verification calls, the reuse of a registration that still owes payment, the notes in the URL, and the email and phone fields.

## Files Involved

| File | Change |
|---|---|
| `frontend/lib/features/events/presentation/screens/event_detail_screen.dart` | Dropdown, options, state and `quantity` in the route removed |
| `frontend/lib/features/events/presentation/screens/checkout_screen.dart` | `quantity` removed; one fee row; button without an amount |
| `frontend/lib/routes/app_router.dart` | Checkout route no longer reads `quantity` |
| `frontend/lib/features/events/data/events_repository.dart` | `registerForEvent` sends `attendee_note` only |
| `frontend/lib/features/events/presentation/providers/event_detail_provider.dart` | `register` has no `quantity` parameter |
| `frontend/test/features/events/` | New ISSUE-006 tests; three ISSUE-001 test files updated for the removed parameter and the new button label |

Left in place, and why:

| File | What remains | Reason |
|---|---|---|
| `frontend/lib/features/events/domain/event.dart` | `registrationMinQuantity`, `registrationMaxQuantity` | Now read only by the admin event form. Removing them would force changes to that form. |
| `frontend/lib/features/events/presentation/screens/manage_events_screen.dart` | "Min/Max quantity" fields, sent as `registration_min_quantity` / `registration_max_quantity` | Admin-only. The backend drops both. This is ISSUE-015. |

## Scope Boundaries

### ISSUE-007

Not implemented. The app does not call `GET /api/v1/events/{id}/payment-pricing`, and checkout still shows the public `ticket_price` as the fee. If an event's payment configuration adds GST or a convenience fee, the Razorpay amount will be higher than the fee shown. That gap is **remaining P1 ISSUE-007**. It was not observed at runtime in this work, because reading the server price needs a signed-in session.

### ISSUE-019

Not implemented. Email and phone are still editable and still discarded. The notes still travel in the URL and are still not limited to 500 characters.

### ISSUE-008

Not implemented. A held seat is still shown as registered on the event page, there is still no "Continue Payment", and closing Razorpay still leaves the attendee without a way back to checkout.

## Verification Plan

Automated, all in `frontend/test/features/events/`:

| Test | File | Runs on |
|---|---|---|
| A — no pass count on either form | `registration_quantity_test.dart` | VM, Chrome |
| B — checkout route has no `quantity`, notes kept | `registration_quantity_test.dart` | VM, Chrome |
| C — request body is `attendee_note` only | `registration_quantity_test.dart`, `checkout_single_registration_test.dart` | VM, Chrome |
| D — one request, one registration, one seat | both | VM, Chrome |
| E — one fee, no multiplied total; no quantity in the source | `checkout_single_registration_test.dart`, `registration_quantity_source_test.dart` | Chrome; VM |
| F — one payment order for that registration | `checkout_single_registration_test.dart` | Chrome |
| G — Razorpay receives the backend's `amount_minor` | `checkout_single_registration_test.dart` | Chrome |
| H — order, attempt and Razorpay amounts agree | `checkout_single_registration_test.dart` | Chrome |
| I — free event | both | VM, Chrome |
| J — paid event, paid and dismissed | `checkout_single_registration_test.dart` | Chrome |
| K — existing registration | both | VM, Chrome |
| L, M, N — ISSUE-001, -002, -003 | their existing tests | VM, Chrome |

Manual, on the deployed site, in TEST payment mode only:

1. Open an eligible paid event and its registration form. Confirm there is no "No of passes".
2. Proceed to checkout. Confirm there is no quantity or passes wording, and that the URL has no `quantity`.
3. In DevTools → Network, confirm the `/register` body has no `quantity`.
4. Confirm one registration, one payment order, and that the Razorpay amount equals `checkout.amount_minor / 100`.
5. Complete with a Razorpay test method, or close the modal.

## Final Status

**PASS. Committed as `8e83a1e`. Deployed on 2026-10-08.**

Automated tests, the analyzer comparison and the web build pass, and were run again on 2026-10-09 against `8e83a1e` with the same results. The live backend's contract was checked without signing in. The live site serves a bundle that is byte-for-byte the build of `8e83a1e`, so the "No of passes" selector is no longer live.

Manual verification, on the deployed build:

| Field | Value |
|---|---|
| Run | 2026-10-08, 06:01 to 06:05 IST. Results reported on 2026-10-09 |
| Event | #11, "TestOct8": paid, ₹1 |
| Payment mode | `test` |
| Registration ID | 14 |
| Order ID | `ORD-hH78c5dB7fAY` |

| Check | Result |
|---|---|
| "No of passes" absent from the registration form | PASS |
| Checkout URL has no `quantity` | PASS |
| `/register` body contains `attendee_note` only, with no `quantity` | PASS |
| Exactly one registration request | PASS |
| Exactly one payment order request | PASS |
| `payment_mode` is `test` | PASS |
| Razorpay amount equals `checkout.amount_minor / 100` | PASS |

The results were reported as PASS or FAIL, without amounts or screenshots. The IDs and the request counts are confirmed by the server logs, which show one register request, one payment order, one attempt, one verification, and a confirmed registration.

Two limits on this record. The fee shown at checkout was not compared with the Razorpay amount, so ISSUE-007 remains not observed. The manual regression checks for ISSUE-001 and ISSUE-002 were reported PASS, but the server logs show one sign-in on this build, not two accounts. Details are in `ISSUE-006_REGISTRATION_QUANTITY_TEST_REPORT.md`, sections 7 and 14.
