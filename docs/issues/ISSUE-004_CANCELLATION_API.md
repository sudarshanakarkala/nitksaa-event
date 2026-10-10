# ISSUE-004 — Cancellation Calls a Nonexistent API

## Severity

P1 — Gate A blocker. ISSUE-005 (refund) depends on it.

## Status

CODE PASS — MANUAL E2E PENDING

The fix is on branch `fix/issue-004`, in two commits. Automated verification passes. No manual run has been made. The beta deploy is approved and follows the second commit; the live site is not deployed from this branch. See "Status" at the end.

## Gap

No registration could be cancelled from the app. "Unregister" always failed.

```text
User taps "Unregister"
→ DELETE /api/v1/events/{event_id}/my-registration
→ HTTP 405 {"detail": "Method Not Allowed"}
→ snackbar "Could not unregister."
```

Five things were wrong in that one request: the route, the HTTP method, the identifier (`event_id` where the backend wants `registration_id`), the body (no idempotency key) and the response model (parsed as a registration; the backend returns a refund status).

Because cancellation is the only way a refund starts, a paid attendee could not get a refund either.

## Root Cause

Findings from the code at commit `e7267a2`, before this fix. Line numbers refer to that commit.

### Where cancellation is triggered

There are two triggers, and both are "Unregister" buttons:

| Screen | Button | Handler |
|---|---|---|
| My Events | `_RegistrationCard`, `my_events_screen.dart:362-373` | `_confirmCancel(registration)`, `:218-253` |
| Event list, "Registered by me" card | `_buildMaterialEventCard`, `event_list_screen.dart:1805-1813` | `_confirmUnregister(event)`, `:77-102` |

Nothing else in `lib/` cancels a registration. The event page has no Unregister button; it only shows "Unregistered from this event" for a registration that is already cancelled. The list's table view and its iOS layout have no button. The event list button was added by the UI merge (PR #2), after the verification report was written.

### Call chain

Both buttons follow the same chain from the confirm dialog onwards:

```text
Unregister → confirm dialog
   ↓
MyEventsNotifier.cancelRegistration(int eventId)          my_events_provider.dart:66-80
   ↓
EventsRepository.cancelMyRegistration(eventId, token)     events_repository.dart:194-203
   ↓
_dio.delete('/api/v1/events/$eventId/my-registration')    ✗ no such route: 405
   ↓
MyEventRegistration.fromJson(response)                    never reached
```

### Identifiers

Both callers already hold the registration. My Events has the `MyEventRegistration` of the card. The event list has the `MyEventRegistration` it looked up for the event. `MyEventRegistration.registrationId` was parsed from the API and never used for cancelling; each caller passed `eventId` instead.

The event list looks its registration up in a map from event id to registration (`_registrationsByEvent`, `event_list_screen.dart:69-74`). The map kept the last row for each event. The backend lists registrations newest first, so for an event with an old cancelled registration and a current one, the map held the old one. The card then had no "Registered" badge and no Unregister button.

### Idempotency key

Cancellation sent none. Checkout builds one for the payment order, from the registration id and the time: `'reg-$registrationId-${DateTime.now().millisecondsSinceEpoch}'` (`checkout_screen.dart:301-302`). No package is used for it.

### Refresh after a change

- **My Events and the event list** both read `myEventsProvider`. After a successful cancel the notifier called `fetchMyEvents()`, so both would have refreshed, had a cancel ever succeeded.
- **The event page** reads `eventDetailProvider(eventId)`, which is `autoDispose` and bound to the session (ISSUE-001). It fetches when the page opens and is discarded when the page closes.

### Errors

A failed cancel stored `e.toString()` in `MyEventsState.errorMessage`. Each screen then read that field and showed "Could not unregister." The field is also what My Events uses for a failed load, so after a failed cancel My Events replaced the whole list with "Could not load registrations" and the raw text `DioException [bad response]: … status code of 405 …`. The attendee lost the list and saw exception text.

If there was no session token, `cancelRegistration` returned without doing anything, and the screen showed "Unregistered".

### Event page after a cancel

The event page cannot be open underneath a screen that cancels. Both Unregister buttons are on top-level pages reached with `context.go`, and the event page is pushed on top of them. So by the time a cancel happens the event page is closed and its provider is gone. Opening it again builds a new provider, which fetches `GET /events/{id}/my-registration` again. No explicit invalidation is needed. Test L confirms the second fetch.

### Event page for a cancelled registration

`GET /events/{id}/my-registration` returns the newest registration, cancelled ones included. For a cancelled one the event page showed "Unregistered from this event" and nothing else, whatever the eligibility call said (`event_detail_screen.dart:1094-1118`). The backend counts only live registrations, so it reports a cancelled attendee as `eligible` and accepts a new registration. The page gave no way to make one.

This could not be reached from the app while cancelling never worked. Making cancel work makes it reachable, so it is closed in this issue (second commit).

### Other callers of the old path

None. `cancelMyRegistration` had one caller. The developer diagnostics screen (debug builds only) mentions `/my-registration` on seven lines: one `GET` call (`developer_diagnostics_screen.dart:3794`) and six labels, comments and endpoint descriptions, all for that `GET`. It has no DELETE and was not changed.

## Backend Contract

Read from `backend/app/api/refunds.py`, `backend/app/services/refund_service.py` and `backend/app/schemas/payments.py` at `e7267a2`, and from the live API's OpenAPI document on 2026-10-10. The backend is not changed.

```text
POST /api/v1/registrations/{registration_id}/cancel
Authorization: Bearer <backend access token>
{"idempotency_key": "<8 to 128 characters>"}

200 → RefundStatusResponse {
  refund_id, registration_id, status, amount, currency,
  requested_at, finalized_at, safe_message, payment_mode, real_money
}
status ∈ refund_pending | refund_processed | refund_failed | none
```

| Registration state | Result |
|---|---|
| `registered`, no paid order | Cancelled. Refund status `none` |
| `registered`, paid order | Cancelled. One full refund is created and sent to Razorpay |
| already `cancelled` | 200 with the current refund status |
| `seat_held`, `payment_pending`, `payment_verification`, `payment_failed` | `409 registration_not_cancellable` |
| another user's registration, or none | `404 registration_not_found` |
| paid, but nothing captured, or the gateway cannot refund, or the modes disagree | `409 no_captured_payment`, `refund_not_supported`, `refund_mode_mismatch` |

The contract matches the task description. No difference was found.

Cancelling a paid registration starts a real Razorpay refund in the payment mode the payment was captured in.

## Expected Behaviour

1. Unregister, once confirmed, sends one `POST /api/v1/registrations/{registration_id}/cancel` with the bearer token and an idempotency key.
2. The app never sends `DELETE …/my-registration`.
3. The registration cancelled is the one on the card, by its own id.
4. A retry of the same action carries the same key. A new action carries a new one.
5. On success the attendee is told the registration is cancelled, and that a refund has started if there was a payment. My Events and the event list reload. The event page shows not registered when it is next opened.
6. On failure the attendee sees a short fixed message, the list stays as it was, and the button works again.
7. After cancelling, the event page offers Register again when the backend says the attendee is eligible, and registering makes a new registration.

## Fix Strategy

1. **Endpoint.** `EventsRepository.cancelMyRegistration` is deleted. `cancelRegistration(registrationId, token, idempotencyKey:)` posts to the cancel route and returns a `RefundStatus`.
2. **Identifier.** The notifier, both screens and the "in progress" state use the registration id. The in-progress state is a set of registration ids, so two registrations of one event are told apart.
3. **Event list lookup.** `_registrationsByEvent` now prefers the active registration of an event over a cancelled one. Without this, the card of a re-registered event had no Unregister button, and test C could not pass from the event list. This is the only part of the "several registrations for one event" problem that is touched; the rest is ISSUE-011.
4. **Idempotency key.** `MyEventsNotifier` makes the key when a cancel starts, in the same form checkout uses (`cancel-<registration id>-<milliseconds>`, about 25 characters). It keeps the key until the backend gives a definite answer:

   | What came back | Key |
   |---|---|
   | 200 | Dropped. The action is finished |
   | 4xx | Dropped. The backend refused, and nothing was created |
   | No response, timeout, 5xx | Kept. The backend may have cancelled, so the retry must repeat the same key |

5. **Response.** New `RefundStatus` model with the ten fields of `RefundStatusResponse`. Parsing does not throw: once there is a response the registration is already cancelled, and a field the app cannot read must not turn that into a reported failure.
6. **Messages.** New `CancellationOutcome`, returned by `cancelRegistration`. It holds whether the registration was cancelled and the message to show. Each screen shows that message in its snackbar.

   | Outcome | Message |
   |---|---|
   | Cancelled, `none` (also an unrecognised status) | "Your registration has been cancelled." |
   | Cancelled, `refund_pending` or `refund_processed` | "Your registration has been cancelled. Your refund has been initiated." |
   | Cancelled, `refund_failed` | The backend's `safe_message`, which already says the registration is cancelled. A fixed fallback if it is empty |
   | `registration_not_cancellable` | "This registration can't be cancelled while payment is in progress." |
   | `registration_not_found` | "We couldn't find this registration. Please refresh and try again." |
   | `no_captured_payment`, `refund_not_supported`, `refund_mode_mismatch` | "We couldn't cancel this registration automatically. Please contact support." |
   | No connection, timeout | "Unable to connect to the server. Check your internet connection and try again." |
   | Anything else | "Could not cancel your registration. Please try again." |

7. **Failure no longer breaks the list.** A failed cancel is reported through the outcome only. `MyEventsState.errorMessage` is left for load errors, so My Events keeps showing the cards.
8. **Refresh.** Unchanged in design: a successful cancel reloads `myEventsProvider`, which both screens read. The Unregister button stays disabled until that reload ends.
9. **Register again (second commit).** On the event page, when the newest registration is `cancelled` and the eligibility call says `eligible`, the page shows the normal Register button with one line above it: "You cancelled your earlier registration." Registering goes through the same form and checkout as a first registration, and the backend makes a new registration row; the cancelled one stays as history.

   | Newest registration | Eligibility | Event page |
   |---|---|---|
   | `cancelled` | `eligible` | The note and the Register button (new) |
   | `cancelled` | `full`, `closed`, `not_open_yet`, `ineligible` | "Unregistered from this event", as before |
   | `cancelled` | unknown (the call failed) | "Unregistered from this event", as before |
   | `cancelled`, past event | any | "Unregistered from this event", as before |
   | any other status | any | As before |

   The button comes back only on a positive answer from the backend. Nothing else in the page's branches was reordered.

Not changed: the backend, the confirm dialog and every other piece of UI, `canCancel`, `eventDetailProvider`, checkout, auth, and the developer diagnostics screen. On the event page only the branch for a cancelled registration changed; `seat_held` and the `payment_*` statuses are as they were (ISSUE-008, ISSUE-011).

## Files Involved

| File | Change |
|---|---|
| `frontend/lib/features/events/data/events_repository.dart` | `cancelMyRegistration` (DELETE) replaced by `cancelRegistration` (POST) |
| `frontend/lib/features/events/domain/refund_status.dart` | New. `RefundStatus` |
| `frontend/lib/features/events/presentation/providers/cancellation_outcome.dart` | New. `CancellationOutcome` and the message mapping |
| `frontend/lib/features/events/presentation/providers/my_events_provider.dart` | Cancel by registration id; idempotency key; in-progress set; returns the outcome |
| `frontend/lib/features/events/presentation/screens/my_events_screen.dart` | Passes `registrationId`; shows the outcome's message |
| `frontend/lib/features/events/presentation/screens/event_list_screen.dart` | Passes `registrationId`; shows the outcome's message; lookup prefers the active registration |
| `frontend/lib/features/events/presentation/screens/event_detail_screen.dart` | Second commit. A cancelled attendee the backend calls eligible gets the Register button and a one-line note |
| `frontend/test/features/events/` | Four new test files; the fake backend extended with the cancel contract and with settable eligibility |

## Scope Boundaries

### ISSUE-005

Not implemented. There is no refund status screen, no polling, no "Check refund status" and no call to `GET /registrations/{id}/refund`. The only thing the attendee sees about a refund is the one-line message after cancelling. `RefundStatus` is the minimal model and is meant to be extended there. A refund that is `refund_pending` when the snackbar closes cannot be followed in the app.

### ISSUE-011

Not implemented, except for the lookup in "Fix Strategy", item 3, and the cancelled-and-eligible case on the event page, item 9. My Events still shows one card per registration row, so an event that was cancelled and registered again has two cards. Any status other than `registered` is still labelled "Unregistered". On the event page, `seat_held` and the `payment_*` statuses are untouched.

### ISSUE-012

Not changed. `canCancel` is still `registered` and the event's registration window `open`. The backend would accept a cancel after the window closes; the app still hides the button.

### ISSUE-018

Not implemented. The message mapping is local to cancellation. A failed load of My Events or of the event list still shows `e.toString()`.

## Adjacent Problems Found, Not Fixed

1. **A cancelled attendee who cannot register again is not told why.** The page says "Unregistered from this event" whether the event is full, closed or the account is not eligible. The backend's reason is not shown. Unchanged.
2. **Two cards after registering again.** My Events shows the cancelled registration and the new one as separate cards. ISSUE-011.
3. **Raw exception text on a failed load.** After a successful cancel the list is reloaded. If that reload fails, My Events shows "Could not load registrations" with `e.toString()`. The cancel itself is still reported as cancelled. ISSUE-018.
4. **The idempotency key lives in memory.** If the response is lost and the attendee reloads the page before retrying, the retry has a new key. The backend still cannot refund twice: the registration is already `cancelled`, so the second call returns the existing refund.
5. **`fetchMyEvents` writes state without checking `mounted`.** If the attendee signs out while the list is loading, the notifier is replaced and the write lands on a disposed notifier. Present before this change.

## Verification Plan

Automated, all in `frontend/test/features/events/`:

| Test | File | Runs on |
|---|---|---|
| A — one `POST /registrations/{id}/cancel`, bearer token, key of valid length | `cancellation_screens_test.dart`, `cancellation_source_test.dart` | VM, Chrome; VM |
| B — no DELETE on the wire; no DELETE to `my-registration` in `lib/` | `cancellation_screens_test.dart`, `cancellation_source_test.dart` | VM, Chrome; VM |
| C — old cancelled + current registered: the current id is cancelled | `cancellation_screens_test.dart` | VM, Chrome |
| D — free event | `cancellation_screens_test.dart`, `cancellation_api_test.dart` | VM, Chrome |
| E — paid event | both | VM, Chrome |
| F — same key on retry, new key for a new action | both | VM, Chrome |
| G — already cancelled | both | VM, Chrome |
| H — not cancellable | both | VM, Chrome |
| I — not found, wrong user | both | VM, Chrome |
| J — network failure | both | VM, Chrome |
| K — both Unregister buttons | `cancellation_screens_test.dart` (each Unregister test runs for both) | VM, Chrome |
| L — event page after a cancel | `cancellation_screens_test.dart` | VM, Chrome |
| M — ISSUE-001, -002, -003, -006 | their existing tests | VM, Chrome |
| N — cancelled and eligible: Register shown, registering again works | `cancellation_screens_test.dart`; `cancellation_reregister_checkout_test.dart` with the real checkout | VM, Chrome; Chrome |
| O — cancelled and not eligible, or eligibility unknown: no Register button | `cancellation_screens_test.dart` | VM, Chrome |

Manual, on beta only (`https://nitksaa-events-beta.web.app`), in a private window, with DevTools → Network open. The live site is not deployed from this branch; it only ever gets `main`.

Beta and live share one backend. A cancellation or a TEST refund made on beta is a real backend record. Paid events in Razorpay TEST mode only.

| # | Step | Expected |
|---|---|---|
| 1 | Register for a free event, open My Events, Unregister, confirm | One `POST /registrations/{id}/cancel`, 200, status `none`; "Your registration has been cancelled."; card shows cancelled |
| 2 | Check the Network panel | No `DELETE …/my-registration` |
| 3 | Open the event page | Not registered: "You cancelled your earlier registration." and a Register button. Register again: a new registration is made and the page shows "Registered Successfully" |
| 4 | With the registration from step 3, repeat step 1 from the event list "Registered by me" card | Same result as step 1 |
| 5 | Register and pay for a TEST paid event, then Unregister | 200, status `refund_pending` or `refund_processed`; refund message |
| 6 | Optional: Razorpay TEST dashboard | One refund for the captured payment, full amount |
| 7 | Hold a seat (close Razorpay without paying), then try to cancel | No Unregister button for that status; if one is shown, `409` and the "payment is in progress" message |
| 8 | With user B's token, `POST` user A's `registration_id` to `/cancel` | 404 `registration_not_found` |

## Status

**CODE PASS — MANUAL E2E PENDING**

Done: the fix in two commits, 58 new tests on the VM and 57 in Chrome, the regression suites for ISSUE-001, -002, -003 and -006, the analyzer comparison, the release web build and the bundle check. Results are in `ISSUE-004_CANCELLATION_API_TEST_REPORT.md`.

Not done: the eight manual steps above. They need the beta deploy (approved on 2026-10-10; the pull request description records whether it was made), a real sign-in, an open free event and an open TEST-mode paid event. Event #11 "TestOct8" closes at 23:59 IST on 2026-10-10.

The pull request must not be merged before the manual run, and it needs Padmanand's approval because it touches cancellation and refunds. The steps before merge are in section 13 of the test report.
