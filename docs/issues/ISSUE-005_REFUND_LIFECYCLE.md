# ISSUE-005 — Refund Lifecycle Not Integrated

## Severity

P1 — Gate A blocker.

## Status

CODE PASS — MANUAL E2E PENDING

The fix is on branch `fix/issue-005`. Automated verification passes. It is not deployed to beta or to the live site, and no manual run has been made. See "Status" at the end.

## Gap

Since ISSUE-004, Unregister on a paid registration cancels it and starts a full Razorpay refund. The app then showed one message, "Your registration has been cancelled. Your refund has been initiated.", and nothing else. Once that message closed the attendee could not see:

- whether the refund was pending, processed or failed
- how much was being refunded
- the backend's message, which for a failed refund says what happens next
- any way to check again later

The backend has had the answer all along, at `GET /api/v1/registrations/{registration_id}/refund`. The app never called it.

## Root Cause

Findings from the code at commit `e68bddd`, before this fix. Line numbers refer to that commit.

### What the app did with the refund it was given

`RefundStatus` (`refund_status.dart`) already held all ten fields of the backend's `RefundStatusResponse`, added in ISSUE-004. The cancel call returned one. `CancellationOutcome.cancelled` (`cancellation_outcome.dart:19-39`) chose a message from its status and kept the object on the outcome. Both screens then read only `outcome.message` for a snackbar (`my_events_screen.dart:246`, `event_list_screen.dart:108`). The refund itself was dropped.

### No refund status call

Nothing in `lib/` requested `/refund`. `EventsRepository` had `cancelRegistration` and no way to ask about a refund afterwards.

### `latest_order_id` was not read

`GET /api/v1/my/registrations` returns `latest_order_id` on every row. It is in `RegistrationResponse` (`backend/app/schemas/registrations.py:87`), filled by a sub-select in the shared registration query (`registration_repository.py:54-56`) that `list_for_user` (`:307`) and `get_latest_for_user_event` (`:297`) both use, and passed through by `_format_registration` (`registration_service.py:71`). The live API's OpenAPI document shows the same field.

`MyEventRegistration.fromJson` (`my_event_registration.dart:47-63`) did not read it. A cancelled card therefore had nothing to tell a paid registration from a free one.

### Where a cancelled registration is visible

| Place | What it showed |
|---|---|
| My Events card | The tag "Unregistered" and the "View Details" button (`my_events_screen.dart:307, 351`). No other action |
| Event list, "Registered by me" | Nothing. A cancelled registration is not an own card (`event_list_screen.dart:1571`) and the filter leaves its event out |
| Event page | "Unregistered from this event", or the note and the Register button when the backend says the attendee is eligible (ISSUE-004) |

None of them said anything about a refund.

### Which cancelled registrations can have a refund

Without another request, `latest_order_id` is the only signal:

| `status` | `latest_order_id` | Meaning |
|---|---|---|
| `cancelled` | null | No payment order was ever made (a free event). There is certainly no refund |
| `cancelled` | set | A payment order was made. There may be a refund |

"May", because the backend also sets a seat hold that ran out to `cancelled` (`registration_repository.py:123-136`, and `payment_service.py`). Such a registration has an order that nobody paid, so it has no refund. The row does not carry the order's status, so the app cannot tell the two apart without asking. When asked, the backend answers `status: none`.

### State that must not cross users

A refund belongs to one signed-in user. ISSUE-001 was a provider that outlived its user, so the same rule applies here: the state must be `autoDispose` and must be rebuilt when the session token changes. `myEventsProvider` already rebuilds on every change of the auth controller.

### Reference app

`nitksaa-payment/apps/payment_demo_app` was read:

- `lib/features/refunds/services/refund_repository.dart:30-46` — `getRefundStatus`, and `refundStatusProvider`, a `FutureProvider.autoDispose.family` by registration id that fetches every time something subscribes.
- `lib/features/refunds/domain/refund_status.dart` — the model, with `hasRefund` and `isTerminal`.
- `lib/features/attendee_demo/presentation/payment_status_screen.dart:437-533` — `_RefundSection`: amount, status, the backend's message, and "Check refund status" only while the refund is not final.

Taken from it: a provider per registration that is thrown away when not shown, `hasRefund`, and the check button only while the refund can still change. Not taken: its `ApiClient`, its error mapper, and its payment status screen, which this app does not have (ISSUE-010).

## Backend Contract

Read from `backend/app/api/refunds.py:34-42` and `backend/app/services/refund_service.py:273-315` at `e68bddd`, and from the live API's OpenAPI document as read on 2026-10-10. The backend is not changed.

```text
GET /api/v1/registrations/{registration_id}/refund
Authorization: Bearer <backend access token>

200 → RefundStatusResponse {
  refund_id, registration_id, status, amount, currency,
  requested_at, finalized_at, safe_message, payment_mode, real_money
}
status ∈ refund_pending | refund_processed | refund_failed | none
404 registration_not_found — not the caller's registration, or none
```

| Behaviour | Where |
|---|---|
| Only the caller's own registration; anything else is 404 with the same body | `_load_owned_registration`, `refund_service.py:88-95` |
| The latest refund of the registration, or `status: none` with no refund | `get_refund_status`, `:304-315` |
| While the refund is `pending` or `processing` internally, the backend asks Razorpay again before answering and stores a change | `_refresh_and_view`, `:273-301` |
| Internal `pending` and `processing` both reach the client as `refund_pending` | `_ATTENDEE_STATUS`, `:44-49` |
| No request body. No state is changed by the caller | Route has no body; the live OpenAPI document shows none |

The contract matches the task description. No difference was found.

## Expected Behaviour

1. A cancelled registration that had a payment order has a "View refund status" action on its My Events card.
2. Opening it sends one `GET /api/v1/registrations/{id}/refund` and shows the status, the amount and the backend's message.
3. While the refund is pending, "Check refund status" asks again. There is no polling.
4. Right after a paid cancel, the message offers "View refund", which opens the same view with the answer the cancel already gave. No request is sent for that first view.
5. Loading My Events sends no refund request, however many cancelled registrations it lists.
6. A free cancelled registration has no refund action.
7. A failure to load shows a short fixed message, never exception text.
8. After a change of user, nothing of the previous user's refund is shown or requested.

## Fix Strategy

1. **Request.** `EventsRepository.getRefundStatus(registrationId, accessToken)` sends the GET and returns the existing `RefundStatus`. No second model was made. `RefundStatus` gained `hasRefund`.
2. **Paid or free.** `MyEventRegistration` reads `latest_order_id`. `mayHaveRefund` is true for a `cancelled` registration that has one.
3. **State.** New `refundStatusProvider(registrationId)`: an `autoDispose` family that watches the session's access token, exactly as `eventDetailProvider` does. Its notifier keeps the token it was made with and drops any answer that arrives after it was replaced. The state is the last refund, a loading flag and an error message.

   The provider fetches nothing by itself. Whoever shows a refund calls `check()` (one GET) or `show(refund)` (no request). That is what lets the view open from a cancel response without a request, and it is why listing registrations cannot cause one.
4. **View.** New `RefundStatusDialog`, an `AlertDialog` like the app's other confirmations. `showRefundStatus(context, ref, registrationId:, known:)` opens it.

   | `status` | Headline | Shown | "Check refund status" |
   |---|---|---|---|
   | `refund_pending` | "Refund in progress" | Amount, "Requested on", the backend's message | Yes |
   | `refund_processed` | "Refunded" | Amount, "Refunded on", the backend's message | No |
   | `refund_failed` | "Refund could not be completed" | Amount, the backend's message | No. The backend has no retry |
   | `none` | "No refund" | "No payment was taken, so there is nothing to refund." | No |
   | anything else | "Refund status unavailable" | "We could not read the refund status. Please check again in a moment." | Yes |

   The amount is the backend's figure, written the way checkout writes money: `₹1`, `₹123.45`.

   | Failure | Message |
   |---|---|
   | `404 registration_not_found` | "We couldn't find this registration. Please refresh and try again." |
   | No connection, timeout | "Unable to connect to the server. Check your internet connection and try again." |
   | Anything else | "Could not load the refund status. Please try again." |

   After a failure the view keeps what it was already showing and offers "Check refund status" to try again.
5. **My Events card.** A cancelled registration with `mayHaveRefund` gets a "View refund status" button, in the place where Unregister sits for an active one. The two never appear together.
6. **After a cancel.** On My Events and on the event list, the message after a cancellation has a "View refund" action when the cancel returned a refund. It opens the view with that refund.
7. **No polling.** One request when the view opens from a card, one per press of the button. No timer exists.
8. **User change.** When the session changes, the provider is rebuilt empty and an open refund view closes.

Not changed: the backend, the cancel request and its idempotency key, `CancellationOutcome` and its messages, the event page, `eventDetailProvider`, checkout, auth, and all other UI.

## Files Involved

| File | Change |
|---|---|
| `frontend/lib/features/events/data/events_repository.dart` | New `getRefundStatus` |
| `frontend/lib/features/events/domain/refund_status.dart` | New `hasRefund` |
| `frontend/lib/features/events/domain/my_event_registration.dart` | Reads `latest_order_id`; new `mayHaveRefund` |
| `frontend/lib/features/events/presentation/providers/refund_status_provider.dart` | New. State, notifier, provider, and the refund error messages |
| `frontend/lib/features/events/presentation/widgets/refund_status_dialog.dart` | New. The refund view, `showRefundStatus`, and the "View refund" action |
| `frontend/lib/features/events/presentation/screens/my_events_screen.dart` | "View refund status" on the card; "View refund" on the message after a cancel |
| `frontend/lib/features/events/presentation/screens/event_list_screen.dart` | "View refund" on the message after a cancel |
| `frontend/test/features/events/` | Two new test files; the fake backend extended with the refund status contract; one ISSUE-004 assertion updated |

## Scope Boundaries

### ISSUE-010

Not implemented. There is no payment status screen and no order status. The refund view is about the refund only.

### ISSUE-011

Not changed. My Events still shows one card per registration row, and a cancelled registration is still labelled "Unregistered". An event that was cancelled and registered again has two cards; the cancelled one carries the refund action.

### ISSUE-012

Not changed. `canCancel` is as it was.

### ISSUE-017

Not implemented. The view does not show a TEST or LIVE banner. `payment_mode` and `real_money` are parsed and not shown.

### ISSUE-018

Not implemented. The error mapping is local to the refund status. It repeats the connection wording used for sign-in and for cancellation on purpose, until the central mapper exists.

### FLOW-09

Not implemented. There is no timeline.

### Also not included

- **The event page.** It shows nothing about a refund. The requirement lists My Events and the message after a cancel as the minimum; the event page was left alone to keep `eventDetailProvider` and the ISSUE-004 re-register branch untouched.
- **Admin refunds, retry and approval.** The backend has no such APIs.

## Adjacent Problems Found, Not Fixed

1. **A seat hold that ran out looks like a cancelled paid registration.** Both are `cancelled` with a `latest_order_id`. Its card shows "View refund status", and the view says "No refund. No payment was taken, so there is nothing to refund." That is true, but the action should not be offered. Telling them apart needs the order's status, which the row does not carry. This belongs with ISSUE-011 (status labels) or needs a backend field.
2. **The refund action exists only on My Events.** After a cancel from the event list, the "View refund" action on the message is the only way to the refund from that screen.
3. **An attendee who cancelled before this fix** sees the refund only from the My Events card, which is the intended route.
4. **Raw exception text on a failed load of My Events** is unchanged (ISSUE-018).

## Verification Plan

Automated, all in `frontend/test/features/events/`:

| Test | File | Runs on |
|---|---|---|
| A — `GET /registrations/{id}/refund`, bearer token, no body | `refund_screens_test.dart`, `refund_api_test.dart` | VM, Chrome |
| B — pending | both | VM, Chrome |
| C — "Check refund status": pending, second GET, "Refunded" | both | VM, Chrome |
| D — processed | `refund_screens_test.dart` | VM, Chrome |
| E — failed, no retry | both | VM, Chrome |
| F — free: no refund action; `none`: "No refund" | both | VM, Chrome |
| G — after a cancel: "View refund" shows the cancel response with no GET | both | VM, Chrome |
| H — listing sends no refund request | both | VM, Chrome |
| I — 404, no connection, 500 | both | VM, Chrome |
| J — user isolation | both | VM, Chrome |
| K — one GET per press, never a POST | both | VM, Chrome |
| L — ISSUE-001, -002, -003, -004, -006 | their existing tests | VM, Chrome |

Manual, on beta only (`https://nitksaa-events-beta.web.app`), in a private window, with DevTools → Network open. The live site is never deployed from a branch. Beta and live share one backend; TEST mode only.

Registration 14 on event #11 "TestOct8" was paid in TEST mode and cancelled on 2026-10-10 in the ISSUE-004 beta run, so it should already have a refund.

| # | Step | Expected |
|---|---|---|
| 1 | My Events → cancelled TestOct8 card → "View refund status" | One `GET /registrations/14/refund`, 200; "Refund in progress" or "Refunded", ₹1 |
| 2 | If pending, press "Check refund status" | Another GET; the status changes once Razorpay has processed it |
| 3 | Optional: Razorpay TEST dashboard | The refund for the payment has the amount and status shown |
| 4 | Open My Events without opening any refund view | No `/refund` request in the Network panel |
| 5 | Pay for a new TEST paid event, Unregister, press "View refund" on the message | The view opens at once with the cancel response; no GET for the first view |
| 6 | Cancel a free registration, if a free event exists | No refund action |
| 7 | Sign out, sign in as another user, open My Events | None of the first user's refunds appear |
| 8 | With user B's token, `GET` user A's `/registrations/{id}/refund` | 404 `registration_not_found` |

## Status

**CODE PASS — MANUAL E2E PENDING**

Done: the fix, 43 new tests on the VM and 43 in Chrome, the regression suites for ISSUE-001, -002, -003, -004 and -006, the analyzer comparison, the colour check, the release web build and the bundle check. Results are in `ISSUE-005_REFUND_LIFECYCLE_TEST_REPORT.md`.

Not done: the beta deploy, which needs approval, and the eight manual steps above.

The pull request must not be merged before the manual run. It touches refunds, so it needs Padmanand's approval. The steps before merge are in section 13 of the test report.
