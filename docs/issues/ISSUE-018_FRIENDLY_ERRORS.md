# ISSUE-018 — Technical Errors Shown to Attendees

## Severity

P2 — Errors

## Status

Fixed on `fix/issue-018`, from `main` at `fbe4ede`. Code and automated tests pass. Manual run on beta PENDING. Not on the live site.

---

## Gap

On several attendee paths the app showed the backend's code or Dio's own text instead of plain words:

| Path | Shown on `fbe4ede` |
|---|---|
| Register, already registered (another tab) | "Could not register: already registered." |
| Register after registration closed | "Could not register: registration closed." |
| Pay while a payment try is active | "Payment could not be completed: payment_attempt_active" |
| Session expired (register) | "Could not register: invalid or expired token." |
| Session expired (pay) | "Payment could not be completed: invalid_or_expired_token" |
| No network (pay) | "Payment could not be completed: " + Dio's message ("The connection errored: …") |
| No network (event list, My Events) | "DioException [connection error]: …" |
| Payment refused by Razorpay | "Payment could not be completed: <Razorpay's words> (payment_failed)" |

Already plain on `fbe4ede`, unchanged: event full and not enough seats (#56), unregister not cancellable (`CancellationOutcome`, ISSUE-004), refund status (ISSUE-005), sign-in failures (`friendlyAuthError`, ISSUE-003), no network when registering and loading the event page.

---

## Root Cause

1. **Missing codes.** `apiErrorMessage` (`core/errors/api_error_message.dart`) has a table of codes with plain words, then falls back to `Could not <action>: <code with spaces>.` The table had the form and seat codes from #56, but none of the registration-window, payment or session codes.
2. **Checkout built its own text.** `checkout_screen.dart` had a private `_apiError` that returned the backend's `detail` as is, or Dio's `e.message`; a non-Dio error was shown with `$e`.
3. **Lists used `e.toString()`.** `EventsNotifier.fetchEvents` and `MyEventsNotifier.fetchMyEvents` stored the exception's text as the error message, which the two pages show.
4. **Razorpay's reason code.** `razorpay_payment_web.dart` showed `"<description> (<reason>)"`; the reason is a code such as `payment_failed`. Opening Razorpay could also fail with `'Unable to open Razorpay checkout: $e'`.

## Backend codes on the attendee paths

| Endpoint (service) | Codes |
|---|---|
| `POST /events/{id}/register` (`registration_service.py`) | `already_registered`, `event_full`, `not_enough_seats`, `registration_closed`, `registration_not_open_yet`, `event_not_published`, `event_not_found`, `payment_not_configured`, `too_many_guests`, `name_required`, `phone_required`, `phone_invalid`, `guest_name_required` |
| Payment order, attempt, verify-checkout (`payment_service.py`) | `registration_not_found`, `registration_not_payable`, `seat_hold_expired`, `payment_not_configured`, `payment_order_creation_conflict`, `payment_order_not_payable`, `payment_order_expired`, `payment_already_completed`, `payment_attempt_active`, `payment_verification_in_progress`, `payment_gateway_error`, `payment_gateway_unavailable`, `checkout_order_mismatch`, `checkout_signature_invalid`, `checkout_amount_mismatch` |
| Any signed-in call (`middleware/auth.py`) | 401 `invalid_or_expired_token`, `invalid_token`, `firebase_token_expired`, `invalid_firebase_token`; 403 `account_suspended`; FastAPI's 403 `Not authenticated` without a token |
| `POST /registrations/{id}/cancel` | Handled by `CancellationOutcome` (ISSUE-004) |

---

## Fix

- `api_error_message.dart`: plain words for every code above that had none. One table, so every screen that uses `apiErrorMessage` (event page, checkout, the lists, admin) gets them. Its fallbacks are unchanged: an unknown code still reads `Could not <action>: <code with spaces>.`, and a reply with no `detail` still gives the HTTP status, as the admin pages expect (`api_error_message_test.dart`).
- `checkout_screen.dart`: `_apiError` removed. Any error from register → order → attempt → verify goes through `apiErrorMessage(e, action: 'complete the payment')`, shown with `showNotice(…, kind: NoticeKind.error)` as before.
- `events_provider.dart`, `my_events_provider.dart`: `apiErrorMessage(e, action: 'load events' / 'load your registrations')` instead of `e.toString()`.
- `razorpay_payment_web.dart`: shows Razorpay's description only; the reason code is still used to tell a cancellation from a failure, as before. "Razorpay could not be opened. Please try again." instead of the exception text.
- `event_detail_screen.dart`: a link that throws when opened says "Could not launch <url>", as when it does not open, instead of the exception text.

No backend change. No restyling or colours. The checkout page stays (paid events use it).

---

## Files

| File | Change |
|---|---|
| `frontend/lib/core/errors/api_error_message.dart` | Codes added to the plain-words table |
| `frontend/lib/features/events/presentation/screens/checkout_screen.dart` | Errors through `apiErrorMessage`; `_apiError` and the `dio` import removed |
| `frontend/lib/features/events/presentation/services/razorpay_payment_web.dart` | No reason code or exception text in the message |
| `frontend/lib/features/events/presentation/providers/events_provider.dart` | `apiErrorMessage` for a failed load |
| `frontend/lib/features/events/presentation/providers/my_events_provider.dart` | Same |
| `frontend/lib/features/events/presentation/screens/event_detail_screen.dart` | No exception text when a link fails |
| `frontend/test/features/events/attendee_errors_test.dart` | New, 53 tests (VM and Chrome) |
| `frontend/test/features/events/checkout_errors_test.dart` | New, 5 tests (Chrome) |
| `frontend/test/features/events/support/registration_backend_fake.dart` | `failures`: a test can make any request answer a status and `detail`, or not arrive |
| `frontend/test/features/events/support/fake_razorpay_web.dart` | A `failed` outcome (Razorpay reports a failure, then the window is closed) |

---

## Scope

Fixed: ISSUE-018 only.

Not changed, reported:

1. **The fallbacks of `apiErrorMessage`.** A code that is not in the table still shows as `Could not <action>: <code with spaces>.`, and a server error with no `detail` as `Could not <action> (HTTP 500). Please try again.`. Both are what the admin pages rely on (and its tests pin). An attendee sees them only for a code the backend adds later, or a 5xx.
2. **Three wordings for "no connection".** `apiErrorMessage` says "Could not reach the server…", `CancellationOutcome` and the refund view "Unable to connect to the server…". All plain; left as they are.
3. **ISSUE-006 Test K** still fails in Chrome on this branch, as on `main` (it expects text removed by #56). It is fixed in `fix/test-006-k`, written so that it passes with or without this change.

---

## Status

CODE PASS — MANUAL E2E PENDING. See `ISSUE-018_FRIENDLY_ERRORS_TEST_REPORT.md`.
