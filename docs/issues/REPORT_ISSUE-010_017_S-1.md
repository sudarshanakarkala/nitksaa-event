# Report: ISSUE-010, ISSUE-017 and S-1 (findings only)

**Author:** Sudarshana Karkala
**Date:** 2026-10-15
**Code read:** `main` @ `fbe4ede`. PRs #59 to #62 do not change these areas, except that #60 (ISSUE-018) rewords checkout's error messages.
**Type:** REPORT ONLY (`SUDARSHANA_BUG_LIST.md` items 9 to 11). No code was changed for this report.

**Manual reproduction: NOT RUN** for all three. The steps in the bug list were not run on beta in the 15 Oct session. Everything below is read from the code. Each section ends with the beta steps still to run and the points for Padmanand to decide.

---

## ISSUE-010 — Payment left pending

### What the code does

**Registration states.** For a paid event a registration is `seat_held` → `payment_pending` → `registered`. When the provider reports the payment as pending (webhook or verify), the backend moves it to `payment_verification` (`payment_service.py`). If the payment then fails or is cancelled, it goes back to a payable state.

**Checkout, after Razorpay returns.**
- `POST /payment-orders/{id}/verify-checkout`. If `payment_confirmed` is false, checkout shows the backend's `safe_message`, or "Payment received - confirmation is in progress.", and stays on checkout.
- If the call fails, checkout shows an error notice: before #60 the raw code; with #60, e.g. "We couldn't confirm this payment. Please check the event page in a few minutes before paying again." or "The payment service isn't responding…".

**Event page.**

| Registration status | What it shows |
|---|---|
| `seat_held`, `payment_pending` | "Your payment isn't complete yet, so you aren't registered yet." + **Complete payment** (#29) |
| `payment_failed` | "Your payment didn't go through, so you aren't registered yet." + **Complete payment** |
| `payment_verification` | Not in the app's "payment due" set. The backend's eligibility counts held seats, so it answers `already_registered`, and the page shows **"You are registered for this event."** with the QR badge section, although the payment is not confirmed yet |
| `registered` | "Registered Successfully", badge number, QR |

**My Events.** The card shows **Registered** only for `registered`. Every other status (`seat_held`, `payment_pending`, `payment_verification`, `payment_failed`) shows **Unregistered**, the label for a cancelled registration.

**Not in the app.** No attendee "check payment status" (`POST /api/v1/payment-attempts/{id}/verify`), no re-read of the order (`GET /api/v1/payment-orders/{id}`), and no payment timeline (`GET /api/v1/payment-orders/{id}/timeline`). After leaving checkout, the attendee's only way to see a payment settle is to reload the event page.

### Findings

1. **A payment being verified looks confirmed on the event page.** "You are registered for this event." while the provider has not confirmed. The opposite of the original ISSUE-010 worry: not stuck, but told too early.
2. **On My Events every unfinished payment says "Unregistered".** An attendee who has paid and is waiting for confirmation sees "Unregistered" there.
3. **Money taken, not yet confirmed:** the event page does not offer Complete payment for `payment_verification`, so a second payment is not invited from the page. Not checked: whether checkout can be opened again for it (from a saved address).
4. **Not checked in the code read:** what happens if the provider never confirms. `payment_verification` extends the seat hold, but whether an expired hold is cancelled while money was taken was not traced.

### Beta steps still to run (bug list item 9)

1. Pay (TEST) and close the tab as soon as Razorpay says paid, before the app confirms.
2. Reopen the event page and My Events after 10 seconds and after 2 minutes.
3. Record what the attendee sees, and the order in Admin → Payments.

### For Padmanand

- Should `payment_verification` read "Payment received, confirming…" on the event page instead of "You are registered"?
- Should My Events say something other than "Unregistered" for unfinished payments (e.g. "Payment due" / "Confirming payment")?
- Is a "Check payment status" action wanted, or is reloading the event page enough for go-live?

---

## ISSUE-017 — TEST vs LIVE mode

### What the code does

- The attendee app does not read `payment_mode` or `real_money` on the payment order, the payment attempt or the checkout response. It reads them only in the refund status model (`refund_status.dart`) and does not show them there (ISSUE-005 left the wording out on purpose).
- No TEST-mode banner, no "this is a real payment" confirmation.
- Checkout opens Razorpay with the `key_id` the backend returns in `checkout`, with no check that a `rzp_test_` key goes with a TEST order or a `rzp_live_` key with a LIVE one.
- Admin → Payments shows the mode (`payments_api.dart`, `admin_payments_tab.dart`).

### Findings

1. Today (TEST until 30 Oct) attendees are not told that payments are test payments; the Razorpay window itself shows "Test Mode".
2. After the switch the app has no client-side guard against a mismatched key and mode. It relies on the backend's configuration being right.

### For the switch to LIVE (30 Oct)

- Confirm one new order's `payment_mode` is `live` (Admin → Payments), and that the key in its checkout starts `rzp_live_`.
- Nothing to build now, per the bug list: after 30 Oct the app runs live only.

---

## S-1 — "Open" in the list but "Full" on the event page

### What the code does

| Where | What it counts |
|---|---|
| Public `registered_count`: Events list, the event page's seat bar (`events_repository.py`) | `status = 'registered'` only |
| Eligibility and registration on a **paid** event (`registration_service.py`, `count_active_or_held`) | `registered`, `seat_held`, `payment_pending`, `payment_verification`, `payment_failed` |
| Eligibility and registration on a **free** event | `registered` only (no holds) |

### Finding

On a paid event, while payments are in progress, the list and the seat bar can show seats left while the event page says "Event is at full capacity." (eligibility `full`) and registering is refused with `event_full`. Free events are not affected. With guests (#56) a hold takes one row per person, so a group in checkout holds several seats.

### Beta steps still to run (bug list item 11)

A paid TEST event with capacity 2. Two attendees start paying and neither finishes. Record what the Events list, the seat bar and the event page each show, for a third attendee.

### For Padmanand

Counting held seats in the public count is a change to two queries in `events_repository.py`, but it also changes what the Dashboard and NITiKa show. To be agreed before changing (bug list).
