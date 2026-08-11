# Google Sign-In Fix — Chrome / macOS (Flutter Web)

**Scope:** `apps/event_app` (Flutter) + `backend` (FastAPI)
**Status:** Fixed and verified
**Related commits:** `b383174`, `94dbdcb`, `cec138d`, `149f2c1`
**Superseded doc:** `docs/reviews/old_reviews/flutter_web_auth_fix_report.txt` (initial fix only; this doc consolidates all follow-ups)

---

## Summary

Google Sign-In was completely broken when running the event app as **Flutter Web in Chrome** (typically launched on macOS via `flutter run -d chrome`). It worked fine on Android/iOS. Two independent bugs combined to break it, and a third UX issue surfaced afterward:

1. The app used the **mobile-only `google_sign_in` SDK** on every platform, including web.
2. The backend's CORS policy did not allow the Flutter Web dev origin.
3. (Follow-up) Chrome would silently reuse a cached Google session instead of showing the account picker on repeat sign-ins.

---

## Root cause

### 1. Wrong auth method on web

`FirebaseAuthService.signInWithGoogle()` called:

```dart
await GoogleSignInInitializer.ensureInitialized();
final googleUser = await GoogleSignIn.instance.authenticate();
```

`GoogleSignIn.instance.authenticate()` (from `google_sign_in` v7) depends on native platform credential infrastructure — the Android Credential Manager or the iOS system account sheet. Neither exists inside a browser, so on Flutter Web this call failed outright, making the "Continue with Google" button non-functional in Chrome.

### 2. Missing CORS origin

`backend/.env` had no `ALLOWED_ORIGINS` entry, so FastAPI's `CORSMiddleware` defaulted to allowing only `http://localhost:5173` (the React admin portal's dev port). Flutter Web runs on a different port (`5200`), so even if step 1 had succeeded, the browser would have blocked the follow-up `POST /api/v1/auth/firebase` token-exchange call at the CORS preflight stage.

Both bugs had to be fixed for web login to work end-to-end: step 1 (Firebase popup sign-in) failed on its own, and step 2 (backend session exchange) would have failed independently even if step 1 succeeded.

### 3. Stale session reuse (follow-up)

After the initial fix, Chrome would sometimes sign a user back in silently using a cached Google session instead of presenting the account chooser, which was confusing when testing with multiple accounts.

---

## Fix

### A. Platform branch in `firebase_auth_service.dart`

File: `apps/event_app/lib/features/auth/services/firebase_auth_service.dart`

Added `kIsWeb` branch that uses Firebase's own popup-based OAuth flow instead of the mobile SDK:

```dart
import 'package:flutter/foundation.dart'; // for kIsWeb

static Future<User?> signInWithGoogle() async {
  AppLogger.info('signInWithGoogle called');

  if (kIsWeb) {
    final provider = GoogleAuthProvider();
    provider.addScope('email');
    provider.addScope('profile');
    provider.setCustomParameters({'prompt': 'select_account'});
    final userCredential = await FirebaseAuth.instance.signInWithPopup(
      provider,
    );
    return userCredential.user;
  }

  // Mobile path — unchanged
  await GoogleSignInInitializer.ensureInitialized();
  final googleUser = await GoogleSignIn.instance.authenticate();
  final googleAuth = googleUser.authentication;
  final credential = GoogleAuthProvider.credential(
    idToken: googleAuth.idToken,
  );
  final userCredential = await FirebaseAuth.instance.signInWithCredential(
    credential,
  );
  return userCredential.user;
}
```

`signInWithPopup()` is provided by `firebase_auth_web` and opens a browser popup that Firebase's own JS SDK drives — no extra Google Identity Services (GIS) JS library, FedCM config, or One Tap setup is required.

`setCustomParameters({'prompt': 'select_account'})` (added in a later commit) forces Chrome to show the account picker every time rather than silently reusing a cached session — this addresses root cause #3.

`signOut()` was also guarded so the mobile-only `GoogleSignIn.instance.signOut()` isn't invoked on web (it was never initialized there and would throw):

```dart
static Future<void> signOut() async {
  AppLogger.info('signOut called');
  if (!kIsWeb) {
    try {
      await GoogleSignInInitializer.ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (error, stackTrace) {
      AppLogger.warning('Google sign-out skipped or failed: $error');
      AppLogger.debug(stackTrace.toString());
    }
  }
  await FirebaseAuth.instance.signOut();
}
```

The Android/iOS path is completely untouched. `kIsWeb` is a compile-time constant, so the mobile branch has zero runtime cost on mobile.

The same `kIsWeb` split was mirrored in the developer diagnostics screen (`apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart`) so the in-app auth diagnostic tool exercises the same code path as production.

### B. CORS origin for Flutter Web

File: `backend/.env`

```diff
- (no ALLOWED_ORIGINS key — defaulted to http://localhost:5173 only)
+ ALLOWED_ORIGINS=http://localhost:5173,http://localhost:5200
```

Flutter Web is run on a fixed port so it matches this origin:

```
flutter run -d chrome --web-port=5200
```

### C. CORS hardening (follow-up, `backend/app/main.py`)

The initial fix only widened the static `ALLOWED_ORIGINS` list. A follow-up commit made local dev more robust against Flutter's dynamic web port and `localhost` vs `127.0.0.1` mismatches, both of which had caused confusing CORS failures during Chrome testing on macOS:

```diff
 _cors_kwargs: dict = {
+    "allow_origins": settings.origins_list,
     "allow_credentials": True,
     "allow_methods": ["*"],
     "allow_headers": ["*"],
 }
 if settings.app_env == "development":
-    _cors_kwargs["allow_origin_regex"] = r"http://localhost(:\d+)?"
-else:
-    _cors_kwargs["allow_origins"] = settings.origins_list
+    _cors_kwargs["allow_origin_regex"] = (
+        r"^http://(localhost|127\.0\.0\.1):\d+$"
+    )
```

`allow_origins` is now always populated from `settings.origins_list` (parsed from the `ALLOWED_ORIGINS` CSV in `backend/app/config.py`), and in development it is additionally widened by regex to accept any `localhost`/`127.0.0.1` port.

---

## Why this only showed up on Chrome/macOS

- The bug is really "Flutter Web" vs "Flutter mobile," not Chrome-specific or macOS-specific per se — but in practice, local Flutter Web development on this project is done via `flutter run -d chrome`, which is most commonly run on the team's macOS dev machines. Any browser running the Flutter Web build would have hit the same `GoogleSignIn.instance.authenticate()` failure.
- No COOP/COEP headers, ITP third-party-cookie workarounds, or GIS `ux_mode`/`itp_support`/`use_fedcm_for_prompt` config were needed — `signInWithPopup` avoids third-party-cookie restrictions entirely (unlike an iframe/One Tap approach), which is why Firebase's built-in popup flow was chosen over hand-rolling Google Identity Services.
- A legacy `google-signin-client_id` meta tag still exists in `apps/event_app/web/index.html`. It is a vestige of the old GIS JS library approach and is not read by the `signInWithPopup` flow used today — safe to ignore/remove in a future cleanup.

---

## End-to-end web auth flow (post-fix)

1. User taps "Continue with Google" in the Flutter Web app.
2. `FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider())` opens a browser popup; the Firebase JS SDK drives the OAuth exchange internally.
3. Popup closes; Firebase returns a `UserCredential` with the authenticated `User`.
4. `FirebaseAuthService.freshIdToken()` calls `user.getIdToken(true)`.
5. `AuthController._runLoginFlow()` posts the ID token to `POST /api/v1/auth/firebase`.
6. Backend verifies the Firebase ID token (`verify_firebase_token()` in `backend/app/middleware/auth.py`, via `firebase_admin.auth.verify_id_token`), upserts `event_users`, and returns a signed backend JWT (`make_access_token`).
7. `AuthController` calls `GET /api/v1/auth/me` to validate the session.
8. The validated `AuthSession` is persisted locally via `AuthSessionStore` (Hive).
9. `LoginScreen` navigates to `AppRoutes.home`.

The Firebase ID token is used only as a server-side exchange credential — it is never rendered in the UI.

---

## Firebase Authorized Domains

`signInWithPopup` requires the page's origin to be listed under **Firebase Console → Authentication → Settings → Authorized domains**. Firebase includes `localhost` by default, so `http://localhost:5200` works for local dev with no console change. **Any production web domain must be added explicitly before this flow will work in production.**

---

## Files touched

| File | Change |
|---|---|
| `apps/event_app/lib/features/auth/services/firebase_auth_service.dart` | `kIsWeb` branch using `signInWithPopup`; web-safe `signOut()`; `prompt: select_account` |
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Mirrored `kIsWeb` branch for the diagnostics tool |
| `backend/.env` | Added `ALLOWED_ORIGINS=http://localhost:5173,http://localhost:5200` |
| `backend/app/main.py` | CORS: always set `allow_origins` from config; dev regex widened to `localhost`/`127.0.0.1` on any port |

No database schema or migration changes. No changes to the Android/iOS auth path.

---

## Verification

- `dart format` / `flutter analyze` / `flutter test`: clean.
- Manual (Chrome, macOS, `flutter run -d chrome --web-port=5200`):
  - "Continue with Google" opens the account-picker popup every time (not silently cached).
  - Backend logs `POST /api/v1/auth/firebase 200` then `GET /api/v1/auth/me 200`.
  - Home screen loads; session survives a page refresh (JWT re-validated via `/auth/me`).
  - Logout clears both the backend session and Firebase Auth state.
- Regression check (Android emulator): Google login still works via the unmodified native `GoogleSignIn` flow.
- Email/password login unaffected on both platforms.
