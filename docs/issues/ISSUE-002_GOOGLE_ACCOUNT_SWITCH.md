# ISSUE-002 — Google Account Chooser Missing

## Severity

P1

## Gap

On web, after a user logs out of NITKSAA and clicks "Sign in with Google" again, Google signs the same account straight back in. The account chooser is not shown.

```text
User A signs in with Google
→ User A logs out from NITKSAA
→ user clicks Sign in with Google again
→ Google silently signs User A back in
→ account chooser is not shown
```

A tester therefore cannot switch from User A to User B in one browser without signing out of Google itself. This also blocks the manual two-user verification of ISSUE-001.

## Root Cause

Findings from the code at commit `db3abfa`, before the fix:

| # | Question | Finding |
|---|---|---|
| 1 | Current Google sign-in flow | Login screen → `AuthController.signInWithGoogle()` → `FirebaseAuthService.signInWithGoogle()`. On web this calls `FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider())`. The controller then takes a fresh Firebase ID token, posts it to `POST /api/v1/auth/firebase`, validates the returned token with `GET /api/v1/auth/me`, stores the session in Hive, and sets the status to authenticated. |
| 2 | Current logout flow | `AuthController.signOut()` clears the Hive session, calls `FirebaseAuthService.signOut()`, and sets the status to unauthenticated. On web, `FirebaseAuthService.signOut()` calls only `FirebaseAuth.instance.signOut()`. |
| 3 | Which API is used on web | `GoogleAuthProvider` with Firebase's popup. The `GoogleSignIn` SDK is used only on Android and iOS. |
| 4 | Custom parameters | None were set. The provider was created with its defaults. |
| 5 | How the reference app forces selection | `nitksaa-payment/apps/payment_demo_app`, `lib/core/auth/services/firebase_auth_service.dart`: `provider.setCustomParameters({'prompt': 'select_account'})`. |
| 6 | Why the previous account is reused | Logout ends the Firebase session but, correctly, does not sign the browser out of Google. With no `prompt` parameter, Google reuses the account that is still signed in, without asking when there is only one. |
| 7 | Web-only or mobile too | Web only. On mobile, logout already calls `GoogleSignIn.instance.signOut()`, so the next sign-in does not start from a remembered account. |

The root cause is the missing `prompt=select_account` parameter on the web Google provider. Logout is not at fault.

## Expected Behavior

```text
User A login
→ Logout
→ Click Sign in with Google
→ Google account chooser appears
→ User can select User B
→ backend session belongs to User B
```

The chooser must appear on every web Google sign-in. A first login, logout, and session restore after a reload must keep working as before.

## Fix Plan

- [x] Set `prompt=select_account` on the web `GoogleAuthProvider`, as the reference app does.
- [x] Do not clear Google's cookies or sign the user out of Google.
- [x] Leave logout, the mobile sign-in path and the backend unchanged.
- [x] Leave the ISSUE-001 fix unchanged.
- [x] Add regression tests for the provider configuration, the login exchange, logout, and the account switch.
- [ ] Verify in a real browser with two Google accounts.

## Files Involved

| File | Role |
|---|---|
| `frontend/lib/features/auth/services/firebase_auth_service.dart` | The fix: the web Google provider now carries `prompt=select_account`. |
| `frontend/lib/features/auth/services/auth_controller.dart` | Adds a test-only constructor so tests can run the real controller against a fake backend. No behaviour change. |
| `frontend/test/features/auth/google_sign_in_account_chooser_test.dart` | New tests for the provider configuration. |
| `frontend/test/features/auth/google_login_flow_test.dart` | New browser tests for the account switch, the login exchange, logout and session restore. |
| `frontend/test/features/auth/support/auth_fakes.dart` | Fakes for Firebase Auth and the backend auth endpoints. |

## Verification Plan

Automated:

- The provider passed to Firebase's popup has `prompt = select_account`.
- A Google login still goes Firebase user → Firebase ID token → `POST /api/v1/auth/firebase` → `GET /api/v1/auth/me` → authenticated session.
- Logout still clears the stored session, signs out of Firebase and leaves the app unauthenticated.
- User A → logout → Google sign-in → pick User B results in B's backend session.
- The ISSUE-001 auth-isolation tests still pass.
- `flutter analyze` reports no new issues; the web build compiles.

Manual, in a real browser on the deployed build:

- Account chooser test: A logs in, logs out, clicks Google sign-in without refreshing, the chooser appears, B is selected, NITKSAA is signed in as B.
- Combined ISSUE-001 test: after switching to B, the event A viewed shows none of A's registration, badge, QR, name, email or phone.

Results are recorded in `ISSUE-002_GOOGLE_ACCOUNT_SWITCH_TEST_REPORT.md`.

## Dependencies

- ISSUE-001 code fix already exists
- ISSUE-002 is required to complete ISSUE-001 manual two-user verification

## Status

IN PROGRESS

The code fix and automated verification are complete. The manual browser verification has not been run, and the change is not committed.
