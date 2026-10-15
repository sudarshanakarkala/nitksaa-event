# ISSUE-012 Cancellation Policy Test Report

**Date:** 2026-10-15
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `0f3b48f` (branch `main`), which contains PR #56 (guests).
**Fix branch:** `fix/issue-012`
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, Chrome for the browser tests
**Final result:** CODE PASS — MANUAL E2E PENDING

**Rebased 2026-10-15** onto `fbe4ede` (PR #58), with no conflicts and no code change. Re-run there: `flutter test` 354 of 354, Chrome `test/features/` 345 of 346 (the same ISSUE-006 Test K failure as on `main`, section 8), `flutter analyze` 25 info, unchanged. The figures below are from the first run, on `0f3b48f`.

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-012 |
| Severity | P2 |
| Area | Cancellation / My Events / event list |
| Status | Fixed on `fix/issue-012`. Not on beta yet. Manual run PENDING. Needs Padmanand's approval (touches cancellation). Not on the live site. |

Unregister disappeared as soon as the event's registration window closed, though the backend cancels (and refunds in full) any `registered` registration.

---

## 2. Root Cause

The full analysis is in `ISSUE-012_CANCELLATION_POLICY.md`.

### An app-only rule

`MyEventRegistration.canCancel` was `isActive && publicEvent?.registrationStatus == 'open'`. The window decides who may register; the backend's cancel has no window check and no time check (`refund_service.cancel_registration`: owned, then `cancelled` → idempotent, then anything but `registered` → 409).

### Two callers

My Events and the event list card both used `canCancel`. Neither page had its own rule.

### The other direction

An event still `open` after it started kept showing Unregister.

---

## 3. Fix

### Files Changed

| File | Change |
|---|---|
| `frontend/lib/features/events/domain/my_event_registration.dart` | `canCancel` → `canCancelAt(DateTime.now())`; `canCancelAt(now)`: `registered` and the event's start is after `now` |
| `frontend/test/features/events/cancellation_policy_test.dart` | New, 17 tests |
| `frontend/test/features/events/cancellation_policy_screens_test.dart` | New, 22 tests |
| `frontend/test/features/events/support/registration_backend_fake.dart` | `registrationStatus`, `startDatetime`, `endDatetime` can be set; defaults as before (`open`, 2099) |

### Rule

Unregister is offered on a `registered` registration until the event's start time, open or closed window. Not at or after the start; never for `cancelled`, `seat_held`, `payment_pending`, `payment_verification` or `payment_failed`.

### Start time

From the registration row's `event.start_datetime`, else the public event's. Both are `TIMESTAMPTZ` strings with an offset, compared as instants. With neither known, the button is shown and the backend decides.

### Messages

Unchanged. A refusal goes through `CancellationOutcome`; 409 `registration_not_cancellable` shows "This registration can't be cancelled while payment is in progress." and the card stays as it was.

---

## 4. Automated Verification

Commands, from `frontend/`:

```bash
flutter test test/features/events/cancellation_policy_test.dart \
  test/features/events/cancellation_policy_screens_test.dart
flutter test
flutter test --platform chrome test/features/
```

How the tests are built:

- **Rule (H):** `canCancelAt` at a fixed time (`2026-10-15T06:30Z`); no `DateTime.now()`.
- **Screens:** the real `MyEventsScreen` and `EventListScreen` (`/home?mine=1`, "Registered by me"), the real notifier and repository, with the fake backend as the HTTP transport, as in the ISSUE-004 tests. Event times are hours or days from the real clock, so a slow run cannot cross them. Each screen test runs on both screens (F).

| Test | Expected | Actual | Result |
|---|---|---|---|
| A — open, future | Unregister shown; one `POST /api/v1/registrations/{id}/cancel`; "Your registration has been cancelled." | As expected, both screens; rule test too | PASS |
| B — closed, future | Unregister shown and works | As expected, both screens; rule test too | PASS |
| B — closed, paid | One cancel; "…Your refund has been initiated."; "View refund"; refund `refund_pending` | As expected, both screens | PASS |
| C — started (start −1 h, end +2 h) | No Unregister, window open or closed; card still "Registered"; no cancel request | As expected, both screens; rule test too | PASS |
| D — ended (3 days ago) | No Unregister, window open or closed (event list: under Past) | As expected, both screens; rule test too | PASS |
| E — `cancelled` / `seat_held` / `payment_failed` | No Unregister | As expected, both screens; rule test also covers `payment_pending`, `payment_verification` | PASS |
| F — every entry point | Same rule on My Events and the event list card | Both use `canCancel`; every screen test runs on both | PASS |
| G — 409 `registration_not_cancellable`, window closed | The fixed message; no backend code, "409" or "Exception" on screen; Unregister still enabled; card still "Registered" | As expected, both screens | PASS |
| H — rule with a fixed clock | See below | 17 of 17 | PASS |
| I — regression | All existing tests pass on the VM and in Chrome | VM 312 of 312 still pass. Chrome: all pass except one that already fails on `main` (section 8) | PASS (with the pre-existing Chrome failure noted) |

Also covered by the rule tests:

| Check | Result |
|---|---|
| Offered one minute before the start, not at the start | PASS |
| Start `12:30+05:30` is 07:00 UTC: offered at 06:30 UTC, not at 07:00 UTC | PASS |
| The registration row's start is used; the public event's is the fallback | PASS |
| No start known: offered (backend decides) | PASS |
| `canCancel` is `canCancelAt(now)` (2099 → offered, 2000 → not); it ignores a closed window | PASS |

### Totals

| | Before ISSUE-012 (`0f3b48f`) | After ISSUE-012 |
|---|---|---|
| `flutter test` (VM) | 312 of 312 | 351 of 351 |
| Chrome, `test/features/` | 303 of 304 | 342 of 343 |
| New tests | — | 39 (17 rule, 22 screens), all on both |

The one Chrome failure is the same test before and after (section 8).

### The same tests against the code before the fix

The new tests were run with `my_event_registration.dart` as on `main`.

| File | Result on `main`'s rule |
|---|---|
| `cancellation_policy_screens_test.dart` | 12 pass, **10 fail**: B (free and paid), C with an open window, D with an open window and G — each on both screens |
| `cancellation_policy_test.dart` | Does not compile (`canCancelAt` does not exist). With a temporary `canCancelAt(now) => canCancel` mapped to the old rule: 8 pass, **9 fail**: B, C (open), D (open), "until the start", "time zone", "start source", "no start known" and both `canCancel` tests |

The tests that pass before the fix are the ones the old rule also got right: A, C/D with a closed window, and E.

---

## 5. Contract Verification

| Backend (`refund_service.cancel_registration`) | App after the fix |
|---|---|
| Owned registration, else 404 | Unchanged (only own registrations are listed) |
| `cancelled` → 200, idempotent | Not offered |
| Not `registered` → 409 `registration_not_cancellable` | Not offered; if the status changed under the screen, the fixed message (G) |
| No time or window check | No window check. The app adds "not after the start" (see section 10, risk 1) |
| Head cancel takes its guests (trigger `registrations_follow_group_head`) | Unchanged; the dialog says "you and your N guests" |

---

## 6. Manual Verification

**PENDING.** Not run yet. To be run on `https://nitksaa-events-beta.web.app` in an Incognito window, with Razorpay in TEST mode (`success@razorpay`), after "beta = fix/issue-012" has been posted in WhatsApp.

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Event with registration **open**: register, then My Events and the event list ("Registered by me") | Unregister shown; pressing it cancels | PENDING |
| 2 | Event with registration **closed** but not started (an admin closes registration on a test event) | Unregister shown on both; cancels; for a paid registration the refund view shows pending or processed | PENDING |
| 3 | Past event with a registration | No Unregister | PENDING |
| 4 | DevTools → Network during 1 and 2 | Only `POST /api/v1/registrations/{id}/cancel` | PENDING |

Beta and live share one backend: cancellations and TEST refunds made on beta are real records.

| Field | Value |
|---|---|
| Local build | `main.dart.js` SHA-256 `a7f2ac96653d27d01c5b8b60ca049079cc5134e13bd0d3c87bd2ae725521abaf` |
| Beta | Not deployed yet. Beta's SHA-256 to be recorded after the deploy |

---

## 7. ISSUE-001/002/003/004/005/006 Regression

All their tests pass on the VM: included in 351 of 351. In Chrome all pass except ISSUE-006 Test K, which fails on `main` too (section 8). The ISSUE-004 cancellation screen tests and the ISSUE-005 refund tests use the fake's defaults (`open`, 2099) and are unchanged. The guests tests from #56 pass.

---

## 8. Static Checks

### flutter test

Result: 351 of 351 (312 before). ISSUE-012 tests alone: 39 of 39.

### Chrome tests

```bash
flutter test --platform chrome test/features/
```

Result: 342 of 343 (303 of 304 before). The ISSUE-012 tests pass in Chrome.

The failure, before and after: `checkout_single_registration_test.dart`, "ISSUE-006: paid registration Test K: the backend's refusal of a duplicate is shown, and nothing more is requested". It expects the text "Registration failed", which no longer exists in `lib/` since `3f0a221` (#37, 14 Oct). It runs only in Chrome. It was confirmed failing with this change removed, and was not changed (out of scope).

### flutter analyze

Measured fresh on `0f3b48f` and after the change.

| | Total | Errors | Warnings | Info |
|---|---:|---:|---:|---:|
| Before (`0f3b48f`) | 25 | 0 | 0 | 25 |
| After | 25 | 0 | 0 | 25 |

The two lists are identical when line numbers are ignored. No finding is in a changed or new file. (`flutter analyze` exits 1 on infos.)

### Colour check

`bash tool/check_colors.sh` → `check_colors: OK`.

### web build

```bash
flutter build web --release \
  --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
```

Result: `✓ Built build/web`.

| Check on `build/web/main.dart.js` | Result |
|---|---|
| `/cancel` | Present once |
| `idempotency_key` | Present twice |
| "This registration can't be cancelled while payment is in progress." | Present once |
| Production backend URL | Present |
| SHA-256 | `a7f2ac96653d27d01c5b8b60ca049079cc5134e13bd0d3c87bd2ae725521abaf` |

---

## 9. Source Search

| Search | Matches |
|---|---|
| `canCancel` in `frontend/lib` | The getter and `canCancelAt` in `my_event_registration.dart`; one use each in `my_events_screen.dart` and `event_list_screen.dart` |
| `registrationStatus` in `my_event_registration.dart` | None |
| `git diff --stat` for `backend/`, `my_events_screen.dart`, `event_list_screen.dart`, `unregister_flow.dart`, `cancellation_outcome.dart`, `event_detail_screen.dart` | No change |

---

## 10. Remaining Risks

1. **The start-time cut-off is the app's only.** The backend accepts a cancel, with a full refund, after the start (old tab, direct API call). If that is the policy, the backend should enforce it too.
2. **Guest ✕ on the event page has no time rule.** It is shown for an active guest after the event has started or ended. Left alone per the task.
3. **The device clock decides near the start.** A wrong device clock can show or hide Unregister around the start time. The backend still decides the cancel itself.
4. **A screen open across the start time keeps its button** until it rebuilds; pressing it then still cancels, as the backend allows.
5. **The 409 message mentions payment.** `registration_not_cancellable` only happens for a status other than `registered`, which is a payment state, so the wording fits; it is not about time.
6. **ISSUE-006 Test K fails in Chrome on `main`** (section 8).

---

## 11. Final Result

**CODE PASS — MANUAL E2E PENDING**

Automated checks pass (sections 4, 7, 8), apart from one Chrome test that fails on `main` already. The manual run on beta has not been made.

---

## 12. Commit

Branch: `fix/issue-012`, from `main` at `0f3b48f`. Nothing committed to `main`.

Message:

```text
fix(cancellation): offer unregister until the event starts

ISSUE-012
```

Pull request: `fix/issue-012` → `main`, "ISSUE-012: offer unregister until the event starts". Touches cancellation and refunds: Padmanand checks it on beta and merges. Not to be merged before then.
