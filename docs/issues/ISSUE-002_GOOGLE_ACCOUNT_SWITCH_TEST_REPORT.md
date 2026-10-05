# ISSUE-002 Google Account Switch Test Report

**Date:** 2026-10-04
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `db3abfa` (branch `main`). The ISSUE-001 and ISSUE-002 fixes are both in the working tree and neither is committed.
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, `firebase_auth` 6.5.0, `firebase_auth_web` 6.2.0, Chrome 154 for the browser tests

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-002 |
| Severity | P1 |
| Area | Authentication / Firebase Auth / Google Sign-In |
| Title | Google web sign-in does not force account selection after logout |

After logging out of NITKSAA, clicking "Sign in with Google" signed the previous Google account straight back in. The account chooser was not shown, so a tester could not switch from User A to User B.

---

## 2. Root Cause

On web, `FirebaseAuthService.signInWithGoogle()` called `FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider())` with no custom OAuth parameters.

Logout on web ends the Firebase session and clears the stored backend session, and it deliberately leaves the browser signed in to Google. That is correct: logging out of NITKSAA should not log a user out of Google. But it means Google still has an active account when the next sign-in starts, and without a `prompt` parameter Google reuses that account without asking when there is only one.

The reference payment app sets `prompt: select_account` on the provider. The NEW app did not. A bundle built before this fix contains no occurrence of `select_account`.

The defect is web-only. On Android and iOS the `GoogleSignIn` SDK is used, and logout already calls `GoogleSignIn.instance.signOut()`.

The full analysis is in `ISSUE-002_GOOGLE_ACCOUNT_SWITCH.md`.

---

## 3. Fix

### Files Changed

| File | Change |
|---|---|
| `frontend/lib/features/auth/services/firebase_auth_service.dart` | The fix. |
| `frontend/lib/features/auth/services/auth_controller.dart` | Adds `AuthController.forTesting(...)`, a test-only constructor. No behaviour change. |
| `frontend/test/features/auth/google_sign_in_account_chooser_test.dart` | New. 3 tests. |
| `frontend/test/features/auth/google_login_flow_test.dart` | New. 5 browser tests. |
| `frontend/test/features/auth/support/auth_fakes.dart` | New. Fakes for Firebase Auth and the backend auth endpoints. |

### Implementation

- The web Google provider is now built with `provider.setCustomParameters({'prompt': 'select_account'})`. This is the OAuth parameter that makes Google show the account chooser on every sign-in, and it is what the reference app uses. `firebase_auth_web` 6.2.0 copies the provider's custom parameters onto the JavaScript provider (`web_utils.dart`, lines 310–315), so the parameter reaches Google's request.
- The web branch of `signInWithGoogle()` moved into its own method, `signInWithGooglePopup()`. Its behaviour is otherwise the same. The split lets the popup call be tested under plain `flutter test`, where `kIsWeb` is false and the web branch cannot be reached.
- `AuthController` gained a constructor marked `@visibleForTesting` that exposes the backend-service and session-store parameters its private constructor already had. Tests B and C need it to run the real controller against a fake backend. The app still uses `AuthController.instance`.

Not changed: logout, the mobile sign-in path, the login screen, the backend, and the ISSUE-001 fix in `event_detail_provider.dart`.

Deliberately left alone:

- **OAuth scopes.** The reference app also adds `email` and `profile` explicitly. Sign-in already works with the provider's default scopes, and scopes are not part of this defect.
- **The developer diagnostics screen** opens its own Google popup without the parameter. Its route exists only in debug builds.

One behaviour change: every Google sign-in on web now shows the account chooser, including for a user with only one Google account. That is one extra click.

---

## 4. Automated Verification

Commands, run from `frontend/`:

```bash
flutter test
flutter test --platform chrome \
  test/features/auth/google_sign_in_account_chooser_test.dart \
  test/features/auth/google_login_flow_test.dart \
  test/features/events/checkout_auth_isolation_test.dart
```

How the tests work:

- Firebase Auth is replaced by a fake that records the provider each popup was asked to use. It also plays Google's part: a browser signed in to one Google account hands that account back without asking unless the request carries `prompt=select_account`, in which case the chooser is "shown" and the test's pick is used.
- The backend is replaced by a fake that serves `POST /api/v1/auth/firebase` and `GET /api/v1/auth/me`.
- `AuthController`, `FirebaseAuthService`, `BackendAuthService` and `AuthSessionStore` (Hive) are the real classes.
- Tests marked Chrome run only in a browser, because the web sign-in path is selected by `kIsWeb`.

| Test | Expected | Actual | Result |
|---|---|---|---|
| **A** The Google popup asks for the account chooser (VM and Chrome) | Provider passed to `signInWithPopup` is a `GoogleAuthProvider` with `{prompt: select_account}` | As expected | PASS |
| **A** `signInWithGoogle` on web opens that popup (Chrome) | The real web path passes the same provider | As expected | PASS |
| User A logs out, picks User B in the chooser, session becomes B (Chrome) | Chooser shown on both sign-ins; after the second, the session's uid, email and backend token are B's, and Hive holds B's session | Chooser shown twice; session and stored session are B's | PASS |
| A first Google login shows the chooser and signs in (Chrome) | Chooser shown once; authenticated as the picked account | As expected | PASS |
| **B** Google sign-in still exchanges the Firebase ID token for a validated backend session (Chrome) | Requests are `POST /api/v1/auth/firebase` then `GET /api/v1/auth/me`; the POST carries the Firebase ID token; status is authenticated; session and Hive hold the backend token | As expected | PASS |
| **C** Logout clears the stored session, signs out of Firebase, leaves the app signed out (Chrome) | Status unauthenticated; session `null`; Hive empty; Firebase sign-out called once | As expected | PASS |
| Web logout signs out of Firebase and nothing else (Chrome) | Firebase sign-out called once; the browser's Google account untouched | As expected | PASS |
| A reload restores the session without a Google popup (Chrome) | New controller + `initialize()`: authenticated as the same user; no popup; one `GET /api/v1/auth/me` | As expected | PASS |
| **D** ISSUE-001 auth-isolation tests (18 on VM, 1 on Chrome) | All pass | All pass | PASS |

**Totals:** `flutter test` passes 20 of 20 (18 ISSUE-001, 1 ISSUE-002, 1 pre-existing). In Chrome, 9 of 9 pass (8 ISSUE-002, 1 ISSUE-001 checkout).

### The same tests against the pre-fix sign-in service

To confirm the tests detect the defect, the browser tests were run against `firebase_auth_service.dart` as it was at `db3abfa`.

| Test | On pre-fix code |
|---|---|
| A: `signInWithGoogle` on web opens that popup | FAIL: parameters were `{}` |
| User A logs out, picks User B, session becomes B | FAIL: chooser shown once instead of twice; A was reused |
| A first Google login shows the chooser and signs in | PASS |
| B: login exchange | PASS |
| C: logout | PASS |
| Web logout signs out of Firebase and nothing else | PASS |
| Reload restores the session | PASS |
| A: the Google popup asks for the account chooser | Not runnable (the method did not exist) |

The two tests that describe the defect fail and the five that guard existing behaviour pass.

### What the automated tests do not show

They show the app asks Google for the account chooser and then uses whichever account comes back. They cannot show Google displaying the chooser. The fake's rule for when Google reuses an account is taken from the verification report, not from Google.

---

## 5. Manual Verification

**One attempt made, which failed. A retest is required; see "First attempt" below.** The two-account test has not yet been run on a browser that is known to be running the fixed build, so every row in the two tables is still pending.

### Deployment

The fix was deployed to `https://nitksaa-events.web.app` at 12:50:38 IST on 2026-10-04. The live `main.dart.js` has the same SHA-256 as the local release build (`3c134c42…41f0`) and contains `["prompt","select_account"]`.

### Live check without Google accounts

A fresh headless Chrome (empty cache, no Google session) was pointed at the live site, and "Continue with Google" was clicked. The popup made these requests:

| Request | Observed |
|---|---|
| `project-d22bed42-f302-4e23-8dc.firebaseapp.com/__/auth/handler` | `providerId=google.com`, `customParameters={"prompt":"select_account"}` |
| `accounts.google.com/o/oauth2/auth` | `prompt=select_account` |

So the deployed app does ask Google for the account chooser. With no Google account signed in, Google showed its sign-in page rather than the chooser, so this check does not replace the two-account test.

### First attempt

At about 12:53 IST, roughly three minutes after the deploy, the test was tried by hand and reported as failing: after logout, Google sign-in went straight back into the same account and a different account could not be chosen.

The most likely cause is that the browser was still running the previous build from its cache. Firebase Hosting serves every file of this site, including `index.html` and `main.dart.js`, with `cache-control: max-age=3600`. Measured in Chrome against the live site, with a profile that had already loaded it:

| How the site is reopened | `main.dart.js` |
|---|---|
| Normal reload (Cmd+R / F5) | Memory cache. Server not contacted. |
| New tab | Disk cache. Server not contacted. |
| Browser closed and reopened | Disk cache. Server not contacted. |
| Hard reload (Cmd+Shift+R) | Downloaded from the server. |

A browser that loaded the site in the hour before a deploy therefore keeps running the old code unless it is hard-reloaded. This has not been confirmed on the browser used for the first attempt.

**Before retesting:** hard-reload the app tab (Cmd+Shift+R on macOS, Ctrl+Shift+R on Windows), or use a new Incognito window. If the chooser still does not appear after that, the fix has failed and this report must be changed to FAIL.

### Account Chooser Test

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. Login using Google Account A | Google popup shows the account chooser; A is selected | Not run | PENDING |
| 2. Confirm Account A is signed in to NITKSAA | Sidebar shows A | Not run | PENDING |
| 3. Logout | Redirected to login | Not run | PENDING |
| 4. Do NOT refresh the browser | — | Not run | PENDING |
| 5. Click Google Sign-In | Google popup opens | Not run | PENDING |
| 6. Confirm the Google account chooser appears | Chooser shown. A is **not** signed back in silently | Not run | PENDING |
| 7. Select Account B | Popup closes | Not run | PENDING |
| 8. Confirm NITKSAA logs in as B | Sidebar shows B; `GET /api/v1/auth/me` returns B | Not run | PENDING |

### User A → User B Test

| Step | Expected | Actual | Result |
|---|---|---|---|
| 1. Login as User A | Signed in as A | Not run | PENDING |
| 2. Open Event X | Event page loads with A's data | Not run | PENDING |
| 3. Record A's registration state, badge number, eligibility, and alumni / profile values | Recorded for comparison | Not run | PENDING |
| 4. Logout | Redirected to login | Not run | PENDING |
| 5. Do NOT refresh | — | Not run | PENDING |
| 6. Sign in with Google | Popup opens | Not run | PENDING |
| 7. Account chooser must appear | Chooser shown | Not run | PENDING |
| 8. Select User B | Signed in as B | Not run | PENDING |
| 9. Open the same Event X | Spinner, then B's view | Not run | PENDING |
| 10. Confirm no A registration, badge, QR, name / email / phone; B's eligibility is correct | Only B's data | Not run | PENDING |
| 11. Repeat B → A | Chooser shown; A sees A's own data | Not run | PENDING |

---

## 6. ISSUE-001 Combined Regression

**ISSUE-001 manual E2E: NOT RUN.**

The ISSUE-001 code is unchanged by this fix, and its automated tests still pass (18 on the VM, plus the Chrome checkout test). Its manual two-user test was blocked by this issue. The "User A → User B Test" above is that test; it needs the same hard reload first, because the ISSUE-001 fix is also only in the newly deployed build. The ISSUE-001 test report has not been updated and should be updated separately once the test has been run.

---

## 7. Static Checks

### flutter test

| Run | Result |
|---|---|
| Before ISSUE-002 (with the ISSUE-001 fix) | `+19: All tests passed!` |
| After ISSUE-002 | `+20: All tests passed!` |
| Chrome, three browser test files | `+9: All tests passed!` |

### flutter analyze

| | Total | Errors | Warnings | Info |
|---|---:|---:|---:|---:|
| Baseline (`db3abfa`, and again after ISSUE-001) | 98 | 6 | 36 | 56 |
| After ISSUE-002 | 98 | 6 | 36 | 56 |

ISSUE-002 introduced no new errors, warnings or infos. The set of issues is identical to the baseline, compared with line numbers ignored, and none is in `firebase_auth_service.dart`, `auth_controller.dart` or the new tests. `flutter analyze` exits with code 1 before and after: all 6 errors are in `razorpay_payment_io.dart` and come from the missing `razorpay_flutter` package (ISSUE-016, not fixed here).

The auth fakes file carries one `ignore_for_file: depend_on_referenced_packages`, because it imports two Firebase platform-interface packages that are transitive dependencies.

### Web build

```bash
flutter build web --release \
  --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
```

Succeeded (`✓ Built build/web`, 24.1 s compile).

| Check on `build/web/main.dart.js` | Result |
|---|---|
| Occurrences of `select_account` | 1, as `["prompt","select_account"]` |
| Same check on the previous build (12:15, before this fix) | 0 |
| Production backend URL present | Yes |
| SHA-256 | `3c134c4213d94cba8cc583fa1cc9457f752a6ab24e3821c9af16aa0f9cd441f0` |

This build was deployed at 12:50:38 IST. The live `main.dart.js` has the same SHA-256.

---

## 8. Files Changed

For ISSUE-002:

```text
M  frontend/lib/features/auth/services/firebase_auth_service.dart   (+16 −5)
M  frontend/lib/features/auth/services/auth_controller.dart         (+11)
A  frontend/test/features/auth/google_sign_in_account_chooser_test.dart
A  frontend/test/features/auth/google_login_flow_test.dart
A  frontend/test/features/auth/support/auth_fakes.dart
A  docs/issues/ISSUE-002_GOOGLE_ACCOUNT_SWITCH.md
A  docs/issues/ISSUE-002_GOOGLE_ACCOUNT_SWITCH_TEST_REPORT.md
```

`pubspec.yaml` and `pubspec.lock` are unchanged.

Also in the working tree, from ISSUE-001 and not part of this change:

```text
M  frontend/lib/features/events/presentation/providers/event_detail_provider.dart
A  frontend/test/features/events/   (three files)
A  docs/issues/ISSUE-001_AUTH_STATE_ISOLATION_TEST_REPORT.md
```

The folder `docs/Issues` was renamed to lowercase `docs/issues`.

---

## 9. Remaining Risks

1. **The browser test with two Google accounts has not passed.** One attempt failed, most likely on a cached copy of the old build. Only a real session on the fixed build proves Google shows the chooser.
2. **Deploys are invisible to returning browsers for up to an hour.** Every file is served with `cache-control: max-age=3600`, so a normal reload keeps the old `main.dart.js`. This affects the verification of every later fix as well, and it is part of ISSUE-022, which is not fixed here.
3. **The chooser does not sign anyone out of Google.** On a shared computer the previous user's Google account stays signed in to the browser and is listed in the chooser. The plan intends this, but the next person can still select it if Google does not ask for the password again.
4. **Eight of the nine new tests need a browser** and are not run by plain `flutter test`.
5. **The tests rely on Firebase's own test helpers** (`firebase_core_platform_interface/test.dart`, `FirebaseAuthPlatform`). A major Firebase upgrade may need the fakes adjusted.
6. **`auth_controller.dart` was touched** to add the test-only constructor. It changes no behaviour, but it is a second production file in this change.
7. **The debug-only developer diagnostics screen** still opens a Google popup without the chooser.

---

## 10. Final Result

**CODE PASS — MANUAL E2E PENDING**

---

## 11. Commit

**Not committed — manual E2E pending.**

When it is committed, ISSUE-001 and ISSUE-002 should be two separate commits, since both sets of changes are in the working tree:

| Commit | Files |
|---|---|
| `fix(auth): isolate event state across user sessions` / `ISSUE-001` | `event_detail_provider.dart`, `frontend/test/features/events/` |
| `fix(auth): force Google account selection on web sign in` / `ISSUE-002` | `firebase_auth_service.dart`, `auth_controller.dart`, `frontend/test/features/auth/` |
