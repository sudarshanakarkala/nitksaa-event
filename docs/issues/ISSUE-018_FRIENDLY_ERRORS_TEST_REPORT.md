# ISSUE-018 Friendly Errors Test Report

**Date:** 2026-10-15
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `fbe4ede` (branch `main`, after #58)
**Fix branch:** `fix/issue-018`
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, Chrome for the browser tests
**Final result:** CODE PASS — MANUAL E2E PENDING

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-018 |
| Severity | P2 |
| Area | Errors shown to attendees |
| Status | Fixed on `fix/issue-018`. Not on beta yet. Manual run PENDING. Not on the live site. |

Attendees saw backend codes and Dio's text ("Payment could not be completed: payment_attempt_active", "DioException [connection error]: …") instead of plain words.

---

## 2. Root Cause

Full analysis in `ISSUE-018_FRIENDLY_ERRORS.md`.

- `apiErrorMessage` had no plain words for the registration-window, payment and session codes, so it fell back to `Could not <action>: <code with spaces>.`
- Checkout showed the backend's `detail` (or Dio's message, or `$e`) through its own `_apiError`.
- The event list and My Events stored `e.toString()` as their error.
- Razorpay failures were shown with Razorpay's reason code.

---

## 3. Fix

| File | Change |
|---|---|
| `lib/core/errors/api_error_message.dart` | Plain words for 26 more codes (register, pay, session) |
| `lib/features/events/presentation/screens/checkout_screen.dart` | Errors through `apiErrorMessage(e, action: 'complete the payment')`; `_apiError` removed |
| `lib/features/events/presentation/services/razorpay_payment_web.dart` | Razorpay's description only; fixed text when it cannot open |
| `lib/features/events/presentation/providers/events_provider.dart`, `my_events_provider.dart` | `apiErrorMessage` instead of `e.toString()` |
| `lib/features/events/presentation/screens/event_detail_screen.dart` | No exception text when a link fails to open |
| `test/features/events/attendee_errors_test.dart` | New, 53 tests |
| `test/features/events/checkout_errors_test.dart` | New, 5 tests, Chrome only |
| `test/features/events/support/registration_backend_fake.dart` | `failures` knob |
| `test/features/events/support/fake_razorpay_web.dart` | `failed` outcome |

Messages still go through `showNotice(…, kind: NoticeKind.error)` (checkout, event page) or the page's error state (lists), as before.

---

## 4. Automated Verification

```bash
flutter test test/features/events/attendee_errors_test.dart
flutter test --platform chrome test/features/events/checkout_errors_test.dart
flutter test
flutter test --platform chrome test/features/
```

The tests use the real `EventDetailNotifier`, `EventListScreen`, `MyEventsScreen` and `CheckoutScreen` with the fake backend as the HTTP transport. A test makes a request fail with `failures[<request pattern>] = (status, detail)`, or status 0 for no connection. Every test also checks that nothing on screen matches `DioException`, `XMLHttpRequest`, `Exception`, `HTTP <n>` or a `snake_case` code.

Checklist from `SUDARSHANA_BUG_LIST.md` item 7:

| Check | Before (`fbe4ede`) | After | Test | Result |
|---|---|---|---|---|
| Register when already registered | "Could not register: already registered." | "You're already registered for this event." | registering / already registered | PASS |
| Register for a full event | "The event is full." | Unchanged | registering / event full | PASS (already plain) |
| Register after registration closed | "Could not register: registration closed." | "Registration for this event has closed." | registering / registration closed; checkout / registration closed | PASS |
| Pay when a payment try is active | "Payment could not be completed: payment_attempt_active" | "A payment for this registration is already in progress. Please wait a few minutes and try again." | checkout / payment already in progress | PASS |
| Unregister something not cancellable | Plain (ISSUE-004) | Unchanged | `cancellation_screens_test.dart` Test H | PASS (already plain) |
| Session expired | "Could not register: invalid or expired token." / "Payment could not be completed: invalid_or_expired_token" | "Your session has expired. Please sign in again." | registering / session expired; checkout / session expired; My Events / session expired | PASS |
| No network | Event list and My Events: "DioException [connection error]: …"; checkout: Dio's message | "Could not reach the server. Check your connection and try again." | lists / no network (×2); checkout / no network; registering / no network | PASS |
| Sign-in failures | Plain (ISSUE-003) | Unchanged | `test/features/auth/` | PASS (already plain) |

Also covered:

| Check | Result |
|---|---|
| Each of 13 codes gives its exact message (register, pay, session, `Not authenticated`) | PASS |
| Each of 32 attendee codes: the message does not contain the code, is not the "Could not …: <code>." fallback, and has nothing technical | PASS |
| Razorpay refuses a payment: "Payment could not be completed: <Razorpay's description>", without `payment_failed`; no verify request | PASS |
| The existing `apiErrorMessage` tests (admin fallbacks: humanised unknown code, HTTP status) | PASS, unchanged |

### Totals

| | `main` (`fbe4ede`) | After ISSUE-018 |
|---|---|---|
| `flutter test` (VM) | 315 of 315 | 368 of 368 |
| Chrome, `test/features/` | 306 of 307 | 364 of 365 |
| New tests | — | 58 (53 VM and Chrome, 5 Chrome only) |

The Chrome failure is ISSUE-006 Test K, before and after (section 8).

### The same tests against the code before the fix

With `lib/` as on `fbe4ede`:

| File | Result |
|---|---|
| `attendee_errors_test.dart` | 10 pass, **43 fail**. The 10 are the codes that already had plain words (event full, not enough seats, too many guests, the form fields) and registering with no network |
| `checkout_errors_test.dart` (Chrome) | **5 of 5 fail** |

---

## 5. Contract Verification

The codes come from the backend source at `fbe4ede`: every `HTTPException(detail=…)` in `registration_service.py`, `payment_service.py` and `middleware/auth.py`, and the dynamic ones (`already_registered`, `event_full`, `not_enough_seats`, `payment_verification_in_progress`). `refund_service.py`'s codes are `CancellationOutcome`'s (ISSUE-004). No backend change.

---

## 6. Manual Verification

**PENDING.** To be run on `https://nitksaa-events-beta.web.app` (Incognito, Razorpay TEST mode).

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Register when already registered (register in a second tab, then submit the form in the first) | "You're already registered for this event." | PENDING |
| 2 | Register for a full event | "The event is full." | PENDING |
| 3 | Register after an admin closes registration (form already open) | "Registration for this event has closed." | PENDING |
| 4 | Pay while a payment try is active (two tabs, Pay in both) | "A payment for this registration is already in progress…" or Razorpay reopens the same try | PENDING |
| 5 | Unregister something not cancellable | "This registration can't be cancelled while payment is in progress." | PENDING |
| 6 | Session expired (sign out in another tab, then act) | "Your session has expired. Please sign in again." | PENDING |
| 7 | No network (DevTools → Offline): event list, My Events, register, pay | "Could not reach the server. Check your connection and try again." | PENDING |
| 8 | Sign-in failures | ISSUE-003's messages | PENDING |

---

## 7. Regression

All existing tests pass on the VM; in Chrome all but ISSUE-006 Test K, which fails on `main` too. The existing `apiErrorMessage` tests are unchanged and pass.

---

## 8. Static Checks

| Check | Result |
|---|---|
| `flutter analyze` | 25 info before and after; identical lists |
| `flutter test` | 368 of 368 |
| Chrome `test/features/` | 364 of 365. The failure: `checkout_single_registration_test.dart` Test K expects "Registration failed", removed in `3f0a221` (#37). It is fixed in `fix/test-006-k` |
| `tool/check_colors.sh` | OK |
| `flutter build web --release` (production URL) | Succeeded |

---

## 9. Remaining Risks

1. A code the backend adds later still shows as `Could not <action>: <code with spaces>.` until it is added to the table.
2. A server error with no `detail` shows the HTTP status ("(HTTP 500)"), as the admin pages want.
3. "No connection" has two wordings ("Could not reach the server…" and, for unregister and refunds, "Unable to connect to the server…").
4. Razorpay's own description is shown as Razorpay wrote it.

---

## 10. Final Result

**CODE PASS — MANUAL E2E PENDING**

---

## 11. Commit

Branch `fix/issue-018` from `main` at `fbe4ede`.

```text
fix(errors): plain words for attendee errors

ISSUE-018
```

Pull request: `fix/issue-018` → `main`, "ISSUE-018: plain words for attendee errors". Not to be merged before Padmanand's check on beta.
