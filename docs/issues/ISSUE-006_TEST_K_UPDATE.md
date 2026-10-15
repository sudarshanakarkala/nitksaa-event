# ISSUE-006 Test K — Stale Assertion (tests only)

**Date:** 2026-10-15
**Base commit:** `fbe4ede` (branch `main`)
**Branch:** `fix/test-006-k`
**Result:** PASS — tests only, no app change

## Gap

`checkout_single_registration_test.dart`, "ISSUE-006: paid registration Test K: the backend's refusal of a duplicate is shown, and nothing more is requested", failed in Chrome on `main`. It runs only in Chrome (it drives the real `CheckoutScreen`), so `flutter test` on the VM never showed it.

## Root Cause

The test expected the text "Registration failed". That wording left the app in `3f0a221` ("Registration form for everyone: name, email, phone, note", PR #37, 14 Oct); since then a refused registration shows `apiErrorMessage`'s text. The test was not updated. (Earlier ISSUE-012 notes put this down to #56; it was #37.)

The app's behaviour is right: one register request, no payment order, Razorpay not opened, and the refusal shown.

## Fix

The assertion now looks for "already registered", in words, and no raw `already_registered`:

- on `main`: "Could not register: already registered."
- with ISSUE-018 (PR #60): "You're already registered for this event."

So it passes with or without ISSUE-018, and the two pull requests do not touch the same lines.

## Verification

| Check | Result |
|---|---|
| `flutter test --platform chrome test/features/events/checkout_single_registration_test.dart` on `fbe4ede` | 12 of 12 (11 of 12 before) |
| Same, with ISSUE-018's `api_error_message.dart`, `checkout_screen.dart` and `razorpay_payment_web.dart` | 12 of 12 |
| `flutter test --platform chrome test/features/` | 307 of 307 (306 of 307 before) |
| `flutter test` (VM) | 315 of 315 (unchanged; the test is Chrome-only) |
| `flutter analyze` | 25 info, unchanged |
| `tool/check_colors.sh` | OK |

## Commit

```text
test(checkout): ISSUE-006 Test K checks the refusal in words

ISSUE-006
```
