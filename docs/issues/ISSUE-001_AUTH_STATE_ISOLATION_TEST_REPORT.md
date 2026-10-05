# ISSUE-001 Auth State Isolation Test Report

**Date:** 2026-10-04
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `db3abfa` (branch `main`); the fix is in the working tree and is not committed
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, `flutter_riverpod` 2.6.1, Chrome 154 for the browser test
**Final result:** CODE PASS — MANUAL E2E PENDING

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-001 |
| Title | Logout → login as another user shows the previous user's event data |
| Severity | P0 / Critical (privacy, state isolation) |
| Area | Authentication / Event Detail / Checkout |
| Fix location | NEW Flutter frontend only. No backend change. |
| Status | Code fixed and verified by automated tests. Two-user browser test not yet run. |

Before the fix, User B could see User A's eligibility verdict, registration status, badge number, QR badge, and A's name, email and phone in the registration form. This happened whenever B signed in after A in the same browser tab without a page reload and opened an event A had viewed. Checkout could also try to pay for A's registration using B's token.

---

## 2. Root Cause

All four causes named in the verification report were confirmed in the code at `db3abfa`.

### Provider lifecycle

`eventDetailProvider(eventId)` was a `StateNotifierProvider.family` without `autoDispose`. One instance per event id was created on first use and lived until the page was reloaded. It fetched once, in a `Future.microtask` at creation, and never again unless the Retry button or the post-payment refresh called it.

### Auth dependency

The provider watched only the repository. The notifier read auth with `_ref.read(authControllerProvider)` inside `fetchEventDetails()`, which does not create a dependency, so an auth change never rebuilt it. Logout cleared the Hive session and Firebase, but nothing invalidated the provider: there was no `invalidate` call anywhere in `lib/`.

### Nullable state retention

`EventDetailState.copyWith()` merged with `value ?? this.value` for `eligibilityStatus`, `eligibilityMessage`, `myRegistration` and `alumniProfile`. A `null` result could therefore never replace an earlier value. Failed calls were swallowed without touching state. So even a re-fetch as User B (404 no registration, 403 `alumni_only`) would have left A's values in place.

### Checkout impact

`CheckoutScreen._confirmRegistration()` takes the existing registration from `eventDetailProvider` state and takes the token separately from `authControllerProvider`. With a stale provider it paired A's `registration_id` with B's token. This was reproduced on the pre-fix code with the real `CheckoutScreen`: the app sent `POST /registrations/101/payment-order` for A's registration 101 with B's token, never called register for B, and showed `registration_not_found`. The backend refuses the request, so no payment could be made against A's registration, but B was blocked from registering.

The provider was checkout's only source of a stale registration. The screen keeps no registration of its own.

---

## 3. Fix

### Files changed

| File | Change |
|---|---|
| `frontend/lib/features/events/presentation/providers/event_detail_provider.dart` | The fix. The only production file changed. |
| `frontend/test/features/events/event_detail_auth_isolation_test.dart` | New. 18 regression tests. |
| `frontend/test/features/events/checkout_auth_isolation_test.dart` | New. 1 browser-only test on the real `CheckoutScreen`. |
| `frontend/test/features/events/support/auth_isolation_fakes.dart` | New. Fake auth controller and in-memory backend used by both test files. |

`auth_controller.dart`, `checkout_screen.dart`, `event_detail_screen.dart` and the backend are unchanged.

### Architecture change

1. **The provider depends on the signed-in session.** It now watches `authControllerProvider.select(...)` for the current access token (`null` when signed out). Any change of session, whether logout, login, or a switch to another user, rebuilds the provider. The old notifier is disposed and a new one starts from empty state and fetches with the new token.
2. **Each notifier is bound to one session.** `EventDetailNotifier` receives the access token in its constructor instead of reading auth at call time. A notifier can only request and hold data for the session it was created for.
3. **The provider is `autoDispose`.** State is dropped when no screen is watching the event, and fetched fresh on each entry. No user-scoped event state outlives the screen.
4. **Late responses are dropped.** Every `await` in the notifier is followed by a `mounted` check. A response for User A that arrives after the switch is discarded, and a notifier captured before the switch can no longer make requests.
5. **`null` clears.** `copyWith()` uses the sentinel pattern already used in `events_provider.dart` for the four user-scoped fields: passing `null` clears the field, omitting the argument keeps it. Each fetch result now overwrites its field outright, so "no registration", "not an alumnus" and a failed call all clear the field. The unused `clearRegistration` flag was removed.

### Why this approach was selected

- **It is central.** The alternative of calling `ref.invalidate` at logout would have to be repeated at every sign-out call site (there are four) and would not cover a login that replaces a session without an explicit logout. Re-fetching from each screen would leave the stale state in memory and depend on every screen remembering to do it.
- **It needs no change to checkout.** Because the provider can no longer hold another user's registration, checkout's existing read is correct. Nothing relies on catching the backend 404.
- **It matches the reference app,** which uses `autoDispose` providers for eligibility and registration.

### Behaviour changes to be aware of

- Opening an event now fetches it every time (four GET requests) and shows the loading spinner briefly. Previously the second and later visits in a session were served from memory.
- The first frame of the event screen is now the spinner. Previously it was a one-frame "Event not found" before loading began.
- If the eligibility, registration or profile call fails on a refresh, that field is now cleared instead of keeping the earlier value. The one place this is visible is the refresh after a successful payment: if that single request fails, the page shows no registration until the event is reopened.
- Public event data is refetched on a session change along with the user data. The public event list (`eventsProvider`) is untouched and stays cached.

---

## 4. Automated Verification

Commands, run from `frontend/`:

```bash
flutter test
flutter test --platform chrome test/features/events/checkout_auth_isolation_test.dart
```

Every test uses the same event id (7) for both users. User A is an alumnus with a registration (`registration_id` 101, badge `NITKSAA-A-0101`) and a profile. User B is not an alumnus and has no registration.

The last column is the result of the same test against the provider as it was at `db3abfa`, to show the tests detect the defect.

| Test | Expected | Actual | Result | On pre-fix code |
|---|---|---|---|---|
| **A** User switch clears registration | After A → logout → B, `myRegistration` is `null` | `null` | PASS | FAIL: A's registration returned |
| **B** User switch clears alumni profile (B gets 403 `alumni_only`) | `alumniProfile` is `null`; `/alumni/me` requested with B's token | `null`; requested with `token-B` | PASS | FAIL: A's profile returned |
| **C** User switch refreshes eligibility (A eligible, B ineligible) | `ineligible` with B's message | `ineligible`, B's message | PASS | FAIL: `eligible` |
| **D** Same event id is rebuilt and reloaded | A's notifier disposed; the three user requests repeated with B's token only | Disposed; `eligibility`, `my-registration`, `alumni-me` each once with `token-B` | PASS | FAIL: same notifier, no requests |
| Logout alone discards user state | All four user fields `null`; public event still loaded; no token-bearing request | As expected | PASS | FAIL: A's data kept |
| Nothing rendered after logout carries A's data | No state emitted after logout contains A's registration, profile or verdict | None | PASS | FAIL |
| Late response for A is dropped | A's `my-registration` response released after B is signed in does not reach state | State holds only B's data | PASS | FAIL |
| **E** Checkout safety (provider level) | B's state has no registration; register runs with B's token; A's notifier refuses to act | B gets a new registration id, not 101; A's notifier returns `false` and sends nothing | PASS | FAIL: state held id 101 |
| **E** Checkout safety (real `CheckoutScreen`, Chrome) | One payment order, for B's own registration, with B's token; no `registration_not_found` | Order for B's new registration with `token-B` | PASS | FAIL: order for 101 with `token-B`, 404 shown |
| **F** Restored session loads the user's own data | A's eligibility, registration and profile; requests use A's token only | As expected | PASS | PASS |
| **F** Restore finishing after the screen opened | User data loads once the session is restored | A's registration loaded | PASS | FAIL (not reachable in the app, see note) |
| Auth notification with no session change | Same notifier, no new requests, state kept | As expected | PASS | PASS |
| Same user signs back in | Own data loaded again with the new token | As expected | PASS | FAIL: no reload |
| Leaving the event drops state; reopening refetches | Notifier disposed on leave; one new `my-registration` request on reopen | As expected | PASS | FAIL |
| `copyWith(null)` clears each user field | All four `null` | All four `null` | PASS | FAIL |
| `copyWith` keeps fields it is not given | Values unchanged | Unchanged | PASS | PASS |
| Empty or failed result clears an earlier fetch | After a refresh returning failure / 404 / 403, all four fields `null` | All four `null` | PASS | Not runnable (constructor changed) |
| Real `EventDetailScreen`: A's badge disappears | "Registered Successfully" and `Badge #: NITKSAA-A-0101` gone after logout and after B signs in; B's ineligible message shown | As expected | PASS | FAIL: A's badge still shown |
| Real `EventDetailScreen`: registration form prefill | Form shows B's name and email; A's name, email and phone absent | As expected | PASS | FAIL: A's details shown |

**Totals:** 18 of 18 pass under `flutter test`, and 1 of 1 passes in Chrome. Against the pre-fix provider, 15 of these fail, 3 pass, and 1 cannot compile.

Notes on what these tests do and do not cover:

- The two `EventDetailScreen` tests and the `CheckoutScreen` test use the real screens and the real provider, with the screen left mounted across the user switch. That is a harsher case than the app, where the route guard removes `/events/*` screens at logout.
- `AuthController` itself is replaced by a fake. The real one calls Firebase and Hive directly and has no test seam. The fake publishes changes the same way the real one does (listeners are notified only on a status change, after the session has been set or cleared), but the real sign-in, sign-out and session-restore code did not run in any automated test.
- The `CheckoutScreen` test is browser-only and is skipped by plain `flutter test`. The screen imports `razorpay_payment.dart`, whose `dart:io` variant needs the `razorpay_flutter` package that is missing from `pubspec.yaml` (ISSUE-016), so it cannot compile for the Dart VM. The test stops before the Razorpay modal opens.
- "Restore finishing after the screen opened" cannot occur in the app today, because `AuthController.initialize()` completes before `runApp`. The test shows the provider would handle it.

---

## 5. Manual / Runtime Verification

**Not run.** No authenticated two-user browser session was available in the environment where the fix was made: there was no browser automation and no test account credentials. Every row below is pending.

Until ISSUE-002 is fixed, Google sign-in on web may silently reuse account A. For this test either use two email/password accounts with verified emails, or sign account A out of Google in another tab between steps. Do not reload the app tab.

Keep the browser's network panel open and note the `Authorization` token on the three user requests (`/registration-eligibility`, `/my-registration`, `/alumni/me`).

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. Open the web app | App loads, public events listed | Not run | PENDING |
| 2. Log in as User A (alumnus registered for Event X) | Lands on the event list as A | Not run | PENDING |
| 3. Open Event X | A's eligibility, "Registered Successfully", badge number | Not run | PENDING |
| 4. Capture A's eligibility, registration status, badge number, name / email / phone | Recorded for comparison | Not run | PENDING |
| 5. Logout from the sidebar | Redirected to login | Not run | PENDING |
| 6. Do **not** refresh the page | — | Not run | PENDING |
| 7. Log in as User B | Lands on the event list as B | Not run | PENDING |
| 8. Open the same Event X | Spinner, then B's view. The three user requests carry B's token | Not run | PENDING |
| 9. Check the event page and the Register form | No A registration, badge, QR, alumni profile, email or phone. B's eligibility is correct | Not run | PENDING |
| 10. Open another event, then return to Event X | Still only B's data | Not run | PENDING |
| 11. Repeat in reverse: B → logout → A, same tab | A sees A's own data, nothing of B's | Not run | PENDING |
| 12. Repeat once with a browser refresh after login | Session restored; the signed-in user's own data shown | Not run | PENDING |
| 13. As B on a paid event A holds an unpaid seat for: Register → Proceed to Checkout → Confirm & Pay | Order is created for B's own registration. No `registration_not_found` | Not run | PENDING |

---

## 6. Regression

Only the event-detail provider changed. The table states what evidence exists for each flow; "Manual pending" means it was not exercised at runtime.

| Flow | Touched by the fix? | Evidence | Status |
|---|---|---|---|
| Dashboard | No | No code change | Manual pending |
| Sign in | No. `auth_controller.dart` unchanged | Fake-controller tests only | Manual pending |
| Sign out | No | Fake-controller tests only | Manual pending |
| Re-sign in | No | "Same user signs back in" test (fake controller) | Automated PASS; manual pending |
| View Events (public list) | No. `eventsProvider` unchanged | No code change | Manual pending |
| View Event | Yes | Real `EventDetailScreen` widget tests; public event loads signed in, signed out and after a switch | Automated PASS; manual pending |
| My Events | No. `myEventsProvider` unchanged; it already rebuilt on auth changes | No code change | Manual pending |
| Register | Yes (`register()` now uses the bound token) | Test E at provider level and in the Chrome `CheckoutScreen` test | Automated PASS; manual pending |
| Checkout | Screen unchanged; its data source changed | Chrome `CheckoutScreen` test up to the payment attempt. Razorpay modal and verify step not exercised | Automated PASS (partial); manual pending |
| Session restore | No | Test F (fake controller) | Automated PASS; manual pending |

The pre-existing widget test (`test/widget_test.dart`) still passes.

---

## 7. Static Checks

### flutter analyze

| | Total | Errors | Warnings | Info |
|---|---:|---:|---:|---:|
| Before the fix (`db3abfa`) | 98 | 6 | 36 | 56 |
| After the fix | 98 | 6 | 36 | 56 |

The set of issues is identical before and after, compared with line numbers ignored. No issue is reported in the changed provider or in any new test file. `flutter analyze` exits with code 1 both before and after: all 6 errors are in `lib/features/events/presentation/services/razorpay_payment_io.dart` and come from the missing `razorpay_flutter` package (ISSUE-016, not part of this fix).

```text
98 issues found. (ran in 1.5s)
```

### flutter test

| | Result |
|---|---|
| Before the fix | `00:00 +1: All tests passed!` |
| After the fix | `00:00 +19: All tests passed!` |
| Chrome, `checkout_auth_isolation_test.dart` | `00:00 +1: All tests passed!` |

---

## 8. Files Changed

```text
M  frontend/lib/features/events/presentation/providers/event_detail_provider.dart   (+58 −30)
A  frontend/test/features/events/event_detail_auth_isolation_test.dart
A  frontend/test/features/events/checkout_auth_isolation_test.dart
A  frontend/test/features/events/support/auth_isolation_fakes.dart
A  docs/issues/ISSUE-001_AUTH_STATE_ISOLATION_TEST_REPORT.md
```

`pubspec.yaml` and `pubspec.lock` are unchanged. No dependency was added.

---

## 9. Remaining Risks

1. **Manual two-user test not run.** The real Firebase sign-in, sign-out and Hive session restore were not exercised. This is the reason the result is not a full PASS.
2. **The fix relies on `AuthController` notifying on every session change.** It notifies only when `status` changes. Every path that changes the session today also changes the status, so this holds. A future change that replaces the session while the status stays `authenticated` (a token refresh, for example) would not rebuild the provider. `AuthController` was left unchanged to keep this fix to one file; whoever adds such a path must make it notify.
3. **The checkout test is not part of plain `flutter test`.** It must be run with `--platform chrome` until ISSUE-016 adds the missing package.
4. **A failed refresh clears the field** (see Behaviour changes in section 3). After a successful payment, a failed registration refresh leaves the event page without the registration until it is reopened. ISSUE-008 and ISSUE-010 rework this area.
5. **During logout, A's data stays on A's screen for the moment between the tap and the logout completing** (the Hive and Firebase calls). It is removed as soon as logout completes, and it is not visible to another user.

Adjacent observations, not fixed here:

- `MyEventsScreen` fetches only when it is first shown. If the session changes while it is on screen, it shows an empty list until reopened. It does not show another user's data.
- The route guard protects only paths starting with `/events/`. `/my-events`, `/manage-events` and `/admin/events/:id/registrations` are not guarded (ISSUE-014 / ISSUE-021).
- ISSUE-002 (Google account chooser) can prevent picking User B during the manual test; see section 5.

---

## 10. Final Result

**CODE PASS — MANUAL E2E PENDING**

The code fix is complete and all automated checks pass. The change is not committed. ISSUE-001 should stay `OPEN` in the remediation plan until the manual two-user test in section 5 passes.
