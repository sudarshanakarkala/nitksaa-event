# ISSUE-003 Auth Error Handling Test Report

**Date:** 2026-10-05
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `e9222d5` (branch `main`), which contains the ISSUE-001 and ISSUE-002 fixes. The ISSUE-003 fix is in the working tree and is not committed.
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, `dio` 5.9.2, `firebase_auth` 6.5.0, `hive` 2.2.3, Chrome 154 for the browser tests
**Final result:** CODE PASS — MANUAL E2E PENDING

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-003 |
| Severity | P2 |
| Area | Authentication / Error Handling |
| Status | Code fix and automated verification complete. Manual browser verification not run. Not committed. |

When the backend refused a login, the user saw "Sign in failed. Please try again." whatever the reason, and Firebase stayed signed in with no backend session.

---

## 2. Root Cause

The full analysis is in `ISSUE-003_AUTH_ERROR_HANDLING.md`.

### Backend rejection detail loss

`BackendAuthService` let Dio's `DioException` pass through unchanged. The backend's `detail` code was intact in `response.data` when it reached `AuthController`, but nothing read it.

### Friendly error mapping

`AuthController._friendlyAuthError` recognised only `FirebaseAuthException`. Every other error, including every backend and network failure, returned "Sign in failed. Please try again."

### Firebase rollback gap

By the time the backend is called, Firebase has already signed the user in. The catch block in `_runLoginFlow` cleared the stored session and never signed out of Firebase.

### Hive/backend session behaviour

This part was already correct. The backend token is saved only after `/auth/me` validates it, and a failed login cleared Hive. A failed login also deleted any session stored earlier.

---

## 3. Fix

### Files Changed

| File | Change |
|---|---|
| `frontend/lib/features/auth/services/backend_auth_exception.dart` | New. `BackendAuthException` and `BackendAuthFailure`. |
| `frontend/lib/features/auth/services/auth_error_messages.dart` | New. `friendlyAuthError` and `genericSignInError`. |
| `frontend/lib/features/auth/services/backend_auth_service.dart` | Both requests go through `_send`, which converts a `DioException`. |
| `frontend/lib/features/auth/services/auth_controller.dart` | Shared mapper; `_rollBackLogin`; private mapper removed. |
| `frontend/lib/features/auth/presentation/screens/login_screen.dart` | Fallback is the generic message, not `error.toString()`. |

### Implementation

- `BackendAuthService` catches `DioException` in one private method and rethrows a `BackendAuthException` with the original stack trace. The exception holds a classification, the backend's `detail` code and the HTTP status. It does not hold the request or the response, which contain the Firebase ID token and the bearer token.
- `friendlyAuthError` is a top-level function with no dependencies on the controller. It maps `FirebaseAuthException` codes exactly as before, maps each `BackendAuthFailure` to its own message, and returns the generic message for anything else.
- `AuthController._runLoginFlow` sets the error message, then calls `_rollBackLogin`, then sets the status to unauthenticated and rethrows the original error.
- The login screen still shows `AuthController.errorMessage`. Its fallback for a missing message used to be the raw exception text; it is now the generic message. The screen does not parse errors.

Not changed: the backend, `firebase_auth_service.dart` (including `prompt=select_account`), `event_detail_provider.dart`, session restore behaviour, logout, `pubspec.yaml` and `pubspec.lock`.

### Error Classification

| Condition | Classification |
|---|---|
| `detail` = `email_not_verified` | `emailNotVerified` |
| `detail` = `account_suspended` | `accountSuspended` |
| `detail` = `email_missing` | `emailMissing` |
| `detail` = `firebase_token_expired`, `invalid_firebase_token`, `firebase_uid_missing`, `invalid_or_expired_token`, `invalid_token` | `sessionRejected` |
| No known code, status 401 or 403 | `sessionRejected` |
| No known code, status 500 or above | `server` |
| Connection error, any timeout, bad certificate | `network` |
| Anything else | `unknown` |

Expired and invalid tokens share a classification and a message, but the exception keeps the distinct `detail` code.

### Rollback Behaviour

`_rollBackLogin` does three things in order: sets the controller session to `null`, clears the Hive session, and calls `FirebaseAuthService.signOut()`. The last two are each wrapped so that a failure is logged and the next step still runs. The error message is set before the rollback, so a listener notified by the Firebase sign-out already finds it.

---

## 4. Automated Verification

Commands, run from `frontend/`:

```bash
flutter test
flutter test --platform chrome test/features/auth/ \
  test/features/events/checkout_auth_isolation_test.dart
```

How the tests work:

- Firebase Auth and the backend are replaced by the fakes from ISSUE-002, extended with email/password sign-in and failure injection. The backend fake can answer with a status and `detail`, answer with a non-JSON body, or fail without answering.
- `AuthController`, `FirebaseAuthService`, `BackendAuthService` and `AuthSessionStore` are the real classes. Hive is real: IndexedDB in Chrome, a temporary directory on the VM.
- The controller tests sign in with email and password, so they run on the VM as well as in Chrome. One test uses Google sign-in and runs only in Chrome.
- Every failed-login test checks all of: the thrown error's backend code, the exact message, status unauthenticated, session `null`, Hive empty, Firebase `currentUser` `null`, and one Firebase sign-out call.

| Test | Expected | Actual | Result |
|---|---|---|---|
| Valid verified user (A) | Authenticated; requests are `POST /auth/firebase` then `GET /auth/me`; session and Hive hold the backend token; Firebase stays signed in; no error message | As expected | PASS |
| Email not verified (B) | Verify-email message; `BackendAuthException` with code `email_not_verified`; fully rolled back; `/auth/me` never called | As expected | PASS |
| Suspended account (C) | Suspension message; code `account_suspended`; fully rolled back | As expected | PASS |
| Missing email (D) | Email-required message; code `email_missing`; fully rolled back | As expected | PASS |
| Invalid/expired token (E) | Session-not-verified message for `firebase_token_expired` and for `invalid_firebase_token`; each code kept on the exception; fully rolled back | As expected (2 tests) | PASS |
| Network failure (F) | Connection message, not an account message; fully rolled back | As expected | PASS |
| Timeout (G) | Connection message for a connection timeout and for a response timeout; fully rolled back | As expected (2 tests) | PASS |
| Server error (H) | Server-unavailable message for a 500 with a `detail` code and for a 503 HTML page; fully rolled back | As expected (2 tests) | PASS |
| Unclassifiable failure | Generic message for a 422 whose `detail` is a list; fully rolled back | As expected | PASS |
| `/auth/firebase` success + `/auth/me` failure (I) | Both requests made; nothing persisted; fully rolled back. Covered for a refused token, a suspended account, a 500 and a dropped connection | As expected (4 tests) | PASS |
| Retry after rejection (J) | First attempt refused and rolled back; second attempt authenticates with no stale error, token or stored session | As expected | PASS |
| Failed A → successful B (K) | A refused and rolled back; B signs in; session, Hive and Firebase are all B's | As expected | PASS |
| Failed A → successful B through Google (K, Chrome) | After A is refused the browser is still signed in to Google; the chooser is shown again with `prompt=select_account`; B signs in | As expected | PASS |
| Refused login while someone else is signed in | Nobody is left signed in | As expected | PASS |
| Firebase sign-out fails during rollback | The verify-email message is still shown; status unauthenticated; session `null`; Hive empty | As expected | PASS |
| Listener ordering | Listeners see `authenticating`, then `unauthenticated` with the message already set. Never `authenticated` | As expected | PASS |
| Wrong password | Firebase's own message; backend not called | As expected | PASS |
| Logout regression (L) | Hive cleared; Firebase signed out once; unauthenticated | As expected | PASS |
| Session restore regression (M) | Valid stored session → authenticated with one `GET /auth/me`. Rejected stored session → removed, unauthenticated. No stored session → unauthenticated, backend not called | As expected (3 tests) | PASS |
| Classification matrix | 27 tests: every backend code, status-only fallbacks, transport failures, no token in the exception text, and the real service against the fake backend | All pass | PASS |
| Message matrix | 22 tests: every `BackendAuthFailure`, nine Firebase codes, three unclassified error types | All pass | PASS |
| ISSUE-001 regression | 18 on the VM, 1 in Chrome | All pass | PASS |
| ISSUE-002 regression | 1 on the VM, 8 in Chrome | All pass | PASS |

**Totals**

| Run | Before ISSUE-003 | After ISSUE-003 |
|---|---|---|
| `flutter test` (VM) | 20 of 20 | 95 of 95 |
| Chrome | 9 of 9 | 85 of 85 |

New tests: 75 on the VM (27 classification, 22 message, 26 controller) and 76 in Chrome (the same, plus the Google test).

### The same tests against the pre-fix code

To confirm the tests detect the defect, `login_failure_rollback_test.dart` was run with `auth_controller.dart` and `backend_auth_service.dart` restored to `e9222d5`.

| Outcome on pre-fix code | Tests |
|---|---|
| FAIL (20) | All 11 refused-login cases, all 4 `/auth/me` cases, J, K, "refused login while someone else is signed in", "Firebase sign-out fails during rollback", and listener ordering |
| PASS (6) | Valid user (A), wrong password, logout (L), and the three session-restore tests (M) |

The tests that describe the defect fail, and the tests that guard existing behaviour pass.

### What the automated tests do not show

They use a fake Firebase and a fake backend. They do not show the real Firebase SDK signing out in a browser, or the login screen rendering the message. Section 7 lists what was checked against the real backend without signing in.

---

## 5. Authentication State Verification

Checked by `expectNobodySignedIn` after every failed login in `login_failure_rollback_test.dart`, on the VM and in Chrome.

| State | Expected | Actual |
|---|---|---|
| Auth status | unauthenticated | unauthenticated |
| Controller session | null | null |
| Hive backend session | absent | absent |
| Firebase currentUser | null | null |
| Previous error/state leakage | none | none: after a later successful login the error message is `null` and the session, Hive and Firebase all belong to the new user |

One exception is by design: in the test where the Firebase sign-out itself fails, Firebase `currentUser` cannot be `null`. That test checks the other four rows and that the original message survives.

---

## 6. Friendly Message Verification

| Failure | Expected Message | Actual | Result |
|---|---|---|---|
| email_not_verified | Please verify your email address before signing in. | Same | PASS |
| account_suspended | Your account is currently suspended. Please contact support if you believe this is an error. | Same | PASS |
| email_missing | An email address is required to sign in. Please use an account with a valid email address. | Same | PASS |
| invalid/expired auth | Your sign-in session could not be verified. Please sign in again. | Same | PASS |
| network | Unable to connect to the server. Check your internet connection and try again. | Same | PASS |
| 5xx | The server is temporarily unavailable. Please try again shortly. | Same | PASS |
| unknown | Sign in failed. Please try again. | Same | PASS |

Raw Dio or HTTP internals are not displayed. `friendlyAuthError` can return only its fixed strings; a test confirms a raw `DioException`, a `StateError` and a plain `Exception` all produce the generic message; and the login screen's fallback no longer uses `error.toString()`.

---

## 7. Manual Verification

**No browser sign-in test was run.** Two things are needed first, and neither was done in this session:

- **A deploy.** The live site serves the ISSUE-001/002 build (`main.dart.js` SHA-256 `3c134c42…41f0`). The ISSUE-003 build exists locally (`0ccf41e1…dcb3`) and has not been deployed. A local run cannot stand in for it: the production backend's CORS preflight answers 400 for `localhost` origins.
- **Test accounts.** In particular an email/password Firebase account with an unverified email.

### Live checks that were run, without signing in

These used the production API with deliberately invalid tokens. They change no data.

| Check | Observed |
|---|---|
| `POST /api/v1/auth/firebase` with an invalid token, sent with the web origin | `401 {"detail":"invalid_firebase_token"}`, with `access-control-allow-origin: https://nitksaa-events.web.app` |
| `GET /api/v1/auth/me` with an invalid bearer token | `401 {"detail":"invalid_or_expired_token"}`, with the same CORS header |
| `GET /api/v1/auth/me` with no bearer token | `403 {"detail":"Not authenticated"}`, with the same CORS header |
| `POST /api/v1/auth/firebase` with an empty body | `422`, `detail` is a list |
| The real `BackendAuthService` over real HTTP, against both endpoints with invalid tokens | `BackendAuthException(sessionRejected, …)` with the codes above, mapped to the session-not-verified message |
| The real `BackendAuthService` against a closed port, an unreachable address with a 300 ms timeout, and an unknown host | `BackendAuthException(network)` in all three, mapped to the connection message |

The CORS header matters. Without it a browser hides the response from the app, and the app could only report a connection failure.

### Valid User

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. Sign in as a verified, active user | Lands on the home screen | Not run | NOT RUN — build not deployed |
| 2. Confirm the expected user appears | Sidebar shows the user | Not run | NOT RUN |
| 3. Reload | Session restores | Not run | NOT RUN |

### Unverified User

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. Sign in with an unverified email/password account | "Please verify your email address before signing in." | Not run | NOT RUN — build not deployed; no test account supplied |
| 2. Check the app | Still on the login screen | Not run | NOT RUN |
| 3. Check IndexedDB | `auth_session` has no `backend_session`; `firebaseLocalStorageDb` has no user | Not run | NOT RUN |

### Suspended User

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. Sign in as a suspended user | The suspension message | Not run | NOT RUN — no authorized test account available |

Creating one needs `event_users.is_suspended` set in the production database. That was not done.

### Network Failure / Retry

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. Block the API host in DevTools, then sign in | The connection message | Not run | NOT RUN — build not deployed |
| 2. Unblock and sign in again | Signs in normally | Not run | NOT RUN |

### Google account switch and event isolation

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. A → logout → Google sign-in | Account chooser appears; B can be selected | Not run | NOT RUN — build not deployed |
| 2. As B, open the event A viewed | Nothing of A's appears | Not run | NOT RUN |

---

## 8. ISSUE-001 Regression

**PASS (automated). Manual not run.**

Evidence:

- `event_detail_auth_isolation_test.dart`: 18 of 18 on the VM.
- `checkout_auth_isolation_test.dart`: 1 of 1 in Chrome.
- `event_detail_provider.dart` has no diff against `e9222d5`.

---

## 9. ISSUE-002 Regression

**PASS (automated). Manual not run.**

Evidence:

- `google_sign_in_account_chooser_test.dart`: 1 of 1 on the VM, 3 of 3 in Chrome.
- `google_login_flow_test.dart`: 5 of 5 in Chrome.
- `firebase_auth_service.dart` has no diff against `e9222d5` and still calls `provider.setCustomParameters({'prompt': 'select_account'})`.
- The release bundle contains `select_account` once.
- A new Chrome test confirms the chooser is requested again after a login is refused.

---

## 10. Static Checks

### flutter test

Command:

```bash
flutter test
```

Result: `+95: All tests passed!`

### Chrome Tests

```bash
flutter test --platform chrome test/features/auth/ \
  test/features/events/checkout_auth_isolation_test.dart
```

Result: `+85: All tests passed!`

### flutter analyze

| | Total | Errors | Warnings | Info |
|---|---:|---:|---:|---:|
| Before ISSUE-003 (`e9222d5`) | 98 | 6 | 36 | 56 |
| After ISSUE-003 | 98 | 6 | 36 | 56 |

- **Pre-existing issues:** all 98. The two lists are identical when line numbers are ignored. `flutter analyze` exits with code 1 before and after: the 6 errors are in `razorpay_payment_io.dart` and come from the missing `razorpay_flutter` package (ISSUE-016).
- **ISSUE-003 introduced issues:** none. No finding is in any file this change adds or modifies.

### Web Build

```bash
flutter build web --release \
  --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
```

Result: succeeded (`✓ Built build/web`, 23.8 s compile).

| Check on `build/web/main.dart.js` | Result |
|---|---|
| Each of the six new messages | Present once |
| `select_account` | Present once |
| Production backend URL | Present |
| SHA-256 | `0ccf41e11e17956c65e090ba59a24266f7081b8bb8caa55863e287730643dcb3` |
| Deployed | No |

---

## 11. Files Changed

| File | Purpose |
|---|---|
| `frontend/lib/features/auth/services/backend_auth_exception.dart` (new, 105 lines) | Typed backend auth error and its classification |
| `frontend/lib/features/auth/services/auth_error_messages.dart` (new, 47 lines) | The one place that turns a sign-in failure into a user message |
| `frontend/lib/features/auth/services/backend_auth_service.dart` (+30 −6) | Converts Dio failures to `BackendAuthException` |
| `frontend/lib/features/auth/services/auth_controller.dart` (+35 −21) | Rollback on failed login; uses the shared mapper |
| `frontend/lib/features/auth/presentation/screens/login_screen.dart` (+3 −10) | Removes the raw-exception fallback |
| `frontend/test/features/auth/support/auth_fakes.dart` (+104 −2) | Email/password sign-in, failure injection, VM session storage; the backend fake's default 401 codes now match the real backend |
| `frontend/test/features/auth/backend_auth_exception_test.dart` (new) | 27 classification tests |
| `frontend/test/features/auth/auth_error_messages_test.dart` (new) | 22 message tests |
| `frontend/test/features/auth/login_failure_rollback_test.dart` (new) | 27 controller tests (26 on the VM) |
| `docs/issues/ISSUE-003_AUTH_ERROR_HANDLING.md` (new) | Issue analysis |
| `docs/issues/ISSUE-003_AUTH_ERROR_HANDLING_TEST_REPORT.md` (new) | This report |

`frontend/build/web` was rebuilt. It is git-ignored.

---

## 12. Remaining Risks

1. **No browser sign-in test has been run.** The real Firebase sign-out and the on-screen message are covered only by fakes until the build is deployed and tested.
2. **The verify-email message has no next step in the app.** The app cannot send a verification email and has no sign-up flow, and a refused user is now signed out. A user told to verify their email has to do it somewhere else. Adding a resend action is a feature, and was left out as instructed.
3. **In a browser, some server failures will read as connection failures.** A 5xx that arrives without CORS headers, such as an unhandled backend exception or a Cloud Run error page, is hidden from web code, so the user sees the connection message. Errors the backend raises itself carry the headers and are classified correctly. On mobile both cases show the server message.
4. **Session restore still leaves Firebase signed in when a stored session is rejected,** and still deletes the stored session when `/auth/me` fails for any reason, including a network failure at startup. Both behaviours predate this fix and are outside the login flow, so they were left alone. Calling the rollback from the restore path would be a one-line change.
5. **The backend reports its own verification problems as a bad token.** `verify_firebase_token` turns every unexpected error, including a failed certificate fetch, into `401 invalid_firebase_token`. A user would be told their session could not be verified when the fault is the server's. That is backend behaviour and is not changed.
6. **Unlisted Firebase errors keep their old generic message.** Closing the Google popup still shows "Sign in failed. Please try again or use Google Sign-In." The Firebase mappings were moved, not edited.
7. **A refused login signs out whoever was signed in before.** The router redirects a signed-in user away from the login screen, so this should not be reachable through normal navigation. The stored session was already deleted in that case; Firebase is now signed out as well.
8. **The debug-only developer diagnostics screen** has its own sign-in code and is unchanged.
9. **Deploys are invisible to returning browsers for up to an hour** (ISSUE-022). Hard-reload before any manual test.

---

## 13. Final Result

**CODE PASS — MANUAL E2E PENDING**

---

## 14. Commit

Commit hash: none. **Not committed — manual verification pending.**

Commit message, when it is committed:

```text
fix(auth): surface backend login errors safely

ISSUE-003
```
