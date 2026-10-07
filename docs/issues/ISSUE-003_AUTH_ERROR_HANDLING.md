# ISSUE-003 — Backend Authentication Rejections Are Masked

## Severity

P2

## Status

IN PROGRESS

The code fix and the automated verification are complete. The manual browser verification has not been run, and the change is not committed. See "Final Status".

## Gap

A login has two halves. Firebase signs the user in, and then the backend exchanges the Firebase ID token for its own session. When the backend half failed, two things went wrong:

1. **The reason was hidden.** Whatever the backend said, the user saw "Sign in failed. Please try again." An unverified email, a suspended account and a dropped connection all looked the same.
2. **The login was only half undone.** Firebase stayed signed in while the app showed the login screen with no backend session.

The first point matters most for email/password test accounts. Since 2026-10-01 the backend refuses Firebase accounts whose email is unverified (`403 email_not_verified`), which is the normal state of an account created in the Firebase console. Such a user could not log in and was given no reason.

## Before Behaviour

```text
Firebase sign-in succeeds
→ POST /api/v1/auth/firebase → 403 {"detail": "email_not_verified"}
→ login screen: "Sign in failed. Please try again."
→ Firebase user: still signed in
→ Hive session: empty
→ app status: unauthenticated
```

The same message and the same leftover Firebase user followed every other backend failure: `account_suspended`, `email_missing`, a refused token, a timeout, a 500.

## Root Cause

Findings from the code at commit `e9222d5`, before this fix.

### Authentication Flow

| # | Question | Finding |
|---|---|---|
| 1 | Authentication entry points | Three in `AuthController`: `signInWithGoogle()`, `signInWithEmail()` and `initialize()` (session restore). The debug-only developer diagnostics screen has its own sign-in code that does not go through the controller; it is not changed here. |
| 2 | What happens after Firebase succeeds | `_runLoginFlow` takes a fresh ID token, calls `loginWithFirebaseToken`, then `validateAccessToken`, then `_setAuthenticated`, which stores the session in Hive and sets the status to authenticated. |
| 3 | Where the Firebase ID token is obtained | `FirebaseAuthService.freshIdToken()`, which calls `currentUser.getIdToken(true)`. |
| 4 | Where `POST /api/v1/auth/firebase` is called | `BackendAuthService.loginWithFirebaseToken`. |
| 5 | Where `GET /api/v1/auth/me` is called | `BackendAuthService.validateAccessToken`, used by both the login flow and session restore. |
| 16 | Do Google and email/password share a flow | Yes. Both call `_runLoginFlow`, so the fix is made once. |

### Error Propagation

| # | Question | Finding |
|---|---|---|
| 6 | What the service threw | Nothing of its own. Dio's exception passed straight through: `DioException` of type `badResponse` for any 4xx or 5xx, `connectionError` for a failed connection, and `connectionTimeout`, `sendTimeout` or `receiveTimeout` for a timeout. A 200 with an unusable body threw `StateError`. |
| 7 | Did the backend's `detail` reach the controller | Yes. It was intact in `DioException.response.data`. |
| 8 | Where the `detail` was lost | In `AuthController._friendlyAuthError`. Nothing ever read `response.data`. |

### Error Mapping

| # | Question | Finding |
|---|---|---|
| 9 | What `_friendlyAuthError` received | The raw exception: a `FirebaseAuthException`, a `DioException` or a `StateError`. |
| 10 | What it did with each | It recognised only `FirebaseAuthException`, mapping eight codes. Every other type returned "Sign in failed. Please try again." That is why all backend failures looked alike. |
| 17 | Does session restore use the same mapper | Yes. The message is stored on the controller, but no screen shows it: the login screen reads `errorMessage` only after a login it started itself. |
| 20 | Reusable code elsewhere | The reference payment app has `FriendlyErrorMessages`, a table from backend codes to messages. It depends on that app's `ApiClient` and `ApiException`, which this app does not have, and its own auth controller has the same generic mapping and no rollback. The idea is reused here; the code is not. |

### Partial Firebase Session

| # | Question | Finding |
|---|---|---|
| 11 | State after Firebase succeeds and the backend refuses | Firebase: still signed in. Hive: empty. Controller: status unauthenticated, session `null`, generic error message. |
| 15 | Did an immediate retry work | Yes, because the next sign-in replaces the Firebase user. The stale Firebase user remained until then. |

The catch block in `_runLoginFlow` called `_clearStoredSession()` and nothing else. It never signed out of Firebase.

### Hive / Backend Session Behaviour

| # | Question | Finding |
|---|---|---|
| 12 | `/auth/firebase` succeeds, `/auth/me` fails | The new backend token was never saved, because saving happens only after validation. Hive was cleared. Firebase was not signed out. |
| 13 | An older session already in Hive | It stays during the attempt. A successful login replaces it. A failed login deletes it. |
| 14 | When storage is cleared | Only on a failed login and on logout. A successful login overwrites it. |

### Existing tests

| # | Question | Finding |
|---|---|---|
| 18 | Tests that exercise `AuthController` | `google_login_flow_test.dart` from ISSUE-002: five browser tests using the real controller. The ISSUE-001 tests use a fake controller. |
| 19 | Test infrastructure available for reuse | `AuthController.forTesting`, `FakeFirebaseAuthPlatform`, `FakeBackend` and `TestAccount`, all from ISSUE-002. They are extended here, not replaced. |

## Backend Error Contract

Read from `backend/app/api/auth.py` and `backend/app/middleware/auth.py`. The backend is not changed by this fix. Rows marked "live" were also observed on the production API with unauthenticated requests on 2026-10-05.

`POST /api/v1/auth/firebase`

| Status | `detail` | When |
|---|---|---|
| 401 | `firebase_token_expired` | The Firebase ID token has expired |
| 401 | `invalid_firebase_token` | The token is revoked or invalid, or any other error occurred while verifying it (live) |
| 400 | `firebase_uid_missing` | The token has no uid |
| 400 | `email_missing` | The Firebase account has no email |
| 403 | `email_not_verified` | The Firebase account's email is unverified |
| 403 | `account_suspended` | `event_users.is_suspended` is true |
| 422 | a list, not a string | The request body is malformed (live) |
| 500 | `firebase_admin_not_installed`, `python_jose_not_installed` | Server misconfiguration |

`GET /api/v1/auth/me`

| Status | `detail` | When |
|---|---|---|
| 403 | `Not authenticated` | No bearer token was sent (live) |
| 401 | `invalid_or_expired_token` | The backend access token does not decode or has expired (live) |
| 401 | `invalid_token` | The token lacks `firebase_uid` or `user_type` |
| 403 | `account_suspended` | `event_users.is_suspended` is true |

The live 401, 403 and 422 responses carry `access-control-allow-origin` for `https://nitksaa-events.web.app`, so browser code can read their bodies.

## Expected Behaviour

A login is either fully established or fully rolled back.

```text
Firebase sign-in succeeds
→ backend refuses, or cannot be reached
→ the user sees a message that matches the reason
→ Firebase signed out
→ Hive session empty
→ controller session null
→ app status unauthenticated
→ the next sign-in attempt starts clean
```

A valid login, logout and session restore keep working as before.

## Fix Strategy

- [x] `BackendAuthService` turns every Dio failure into a typed `BackendAuthException` that keeps the backend's `detail` code, the HTTP status and a classification.
- [x] One function, `friendlyAuthError`, maps Firebase and backend failures to user messages. The Firebase mappings are moved into it unchanged.
- [x] `_runLoginFlow` rolls back in one place, `_rollBackLogin`: clear the controller session, clear Hive, sign out of Firebase.
- [x] Cleanup steps that fail are logged and skipped, so the original reason still reaches the user.
- [x] The login screen no longer falls back to raw exception text.
- [x] The backend, the Google provider (`prompt=select_account`) and the ISSUE-001 provider are untouched.
- [x] Regression tests for classification, messages and rollback.
- [ ] Verify in a real browser on a deployed build.

`BackendAuthException` deliberately does not keep the Dio request or response. They hold the Firebase ID token and the bearer token, and the exception is logged.

## Friendly Error Mapping

| Backend / Transport Condition | User-Safe Message |
|---|---|
| `email_not_verified` | Please verify your email address before signing in. |
| `account_suspended` | Your account is currently suspended. Please contact support if you believe this is an error. |
| `email_missing` | An email address is required to sign in. Please use an account with a valid email address. |
| `firebase_token_expired`, `invalid_firebase_token`, `firebase_uid_missing`, `invalid_or_expired_token`, `invalid_token`, or any other 401 or 403 | Your sign-in session could not be verified. Please sign in again. |
| Connection error, connection / send / receive timeout, bad certificate | Unable to connect to the server. Check your internet connection and try again. |
| Any 5xx | The server is temporarily unavailable. Please try again shortly. |
| Anything else (for example 422, 404, an unusable 200 body) | Sign in failed. Please try again. |
| Firebase errors (`invalid-credential`, `wrong-password`, `too-many-requests`, `popup-blocked` and the rest) | Unchanged from before this fix |

A known `detail` code takes priority over the status. Without one, the status decides.

## Rollback Semantics

- The rollback runs for any failure inside `_runLoginFlow`, including a failure of the Firebase step itself. In that case there is usually no Firebase user and the sign-out does nothing.
- The error message is set before the rollback starts. Signing out of Firebase can notify the controller's listeners, and they must already find the reason.
- Listeners see `authenticating` and then `unauthenticated`. They never see `authenticated` for a login that failed.
- If someone was already signed in when a new login is refused, that person is signed out as well. The stored session was already being deleted in this case before the fix; Firebase is now signed out to match.
- On web, the rollback signs out of Firebase only. The browser stays signed in to Google, and the account chooser from ISSUE-002 still appears on the next attempt.
- **Session restore is not changed.** A stored session that fails validation is deleted and the app starts signed out, as before. The message is recorded and not shown. Firebase is not signed out on this path; see Remaining Risks in the test report.

## Files Involved

| File | Role |
|---|---|
| `frontend/lib/features/auth/services/backend_auth_exception.dart` | New. The typed error and its classification. |
| `frontend/lib/features/auth/services/auth_error_messages.dart` | New. `friendlyAuthError` and the generic fallback message. |
| `frontend/lib/features/auth/services/backend_auth_service.dart` | Wraps both requests so Dio failures become `BackendAuthException`. |
| `frontend/lib/features/auth/services/auth_controller.dart` | Uses the shared mapper; adds `_rollBackLogin`; drops its private mapper. |
| `frontend/lib/features/auth/presentation/screens/login_screen.dart` | Fallback message is the generic one, not `error.toString()`. |
| `frontend/test/features/auth/support/auth_fakes.dart` | Fakes gain email/password sign-in, failure injection and VM session storage. |
| `frontend/test/features/auth/backend_auth_exception_test.dart` | New. Classification tests. |
| `frontend/test/features/auth/auth_error_messages_test.dart` | New. Message tests. |
| `frontend/test/features/auth/login_failure_rollback_test.dart` | New. Controller tests for messages, rollback, retry, logout and restore. |

## Tests Required

All are implemented. Results are in `ISSUE-003_AUTH_ERROR_HANDLING_TEST_REPORT.md`.

| Test | Covers |
|---|---|
| A | A verified, active user signs in |
| B | `email_not_verified` |
| C | `account_suspended` |
| D | `email_missing` |
| E | Expired and invalid Firebase token |
| F | Network failure during the exchange |
| G | Connection and response timeouts |
| H | Server 500 and a gateway error page |
| I | `/auth/firebase` succeeds, `/auth/me` fails |
| J | Retry after a rejection |
| K | Refused user A, then user B succeeds (email, and Google in Chrome) |
| L | Logout |
| M | Session restore: valid, rejected and absent stored session |
| Mapper matrix | Every failure kind and every Firebase code |

## Manual Verification Plan

A deploy is needed first. The live site still serves the ISSUE-001/002 build, and the production backend's CORS refuses `localhost` origins, so a local run cannot reach it. After deploying, hard-reload the tab (Cmd+Shift+R) or use a new Incognito window: every file is served with a one-hour cache.

1. **Valid user.** Sign in, confirm the profile, reload, confirm the session restores.
2. **Unverified email/password user.** Sign in. Expect "Please verify your email address before signing in." and no session.
3. **Suspended user.** Only if an authorised test account already exists with `is_suspended` set. Expect the suspension message.
4. **Network failure.** In DevTools, block requests to the API host, sign in, expect the connection message. Unblock, sign in again, expect success.
5. **ISSUE-002 regression.** A → logout → Google sign-in → chooser appears → B.
6. **ISSUE-001 regression.** As B, open the event A viewed. Nothing of A's appears.

For tests 2 to 4, also check DevTools → Application → IndexedDB: `auth_session` has no `backend_session`, and `firebaseLocalStorageDb` has no signed-in user.

## Dependencies

- ISSUE-001 completed
- ISSUE-002 completed

## Scope Restrictions

Not changed: the backend, alumni eligibility, payments, event screens, routing, the Google provider configuration, `event_detail_provider.dart`, and error messages outside sign-in (ISSUE-018). No verification-email feature is added. Unrelated analyzer findings are left alone.

## Final Status

**CODE PASS — MANUAL E2E PENDING. Not committed.**

Automated tests, the analyzer comparison and the web build pass. Live unauthenticated checks confirm the backend's error bodies and CORS headers. No browser sign-in test has been run, because that needs a deploy and test accounts.
