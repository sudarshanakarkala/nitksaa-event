# ISSUE-021 Routing Test Report

**Date:** 2026-10-15
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `fbe4ede` (branch `main`, after #58)
**Fix branch:** `fix/issue-021`
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, go_router 17.2.3, Chrome for the browser tests
**Final result:** CODE PASS — MANUAL E2E PENDING (beta run 1 found 021-8; fixed, re-check pending)

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-021 |
| Severity | P3 |
| Area | Routing / navigation |
| Status | Fixed on `fix/issue-021`. On beta in `test/evening-batch` since 2026-10-15 16:44 IST. Beta run 1 found one defect (021-8, section 5a), fixed in a second commit and redeployed; its re-check and the remaining steps are PENDING. Not on the live site. |

---

## 2. Root Cause

Full analysis in `ISSUE-021_ROUTING.md`. In short: `/my-events` was not guarded; sign-in was asked for without remembering the page; a refresh lost the page at the splash; non-admins were sent to Events silently; the login screen and the header's Sign out navigated on their own; there was no not-found page.

---

## 3. Fix

| File | Change |
|---|---|
| `lib/routes/route_guards.dart` | Guard pages that need sign-in and remember them; remember the page opened during the sign-in check (`afterSplash`); non-admins → `/no-access`; logic in `redirectFor(auth, uri)` |
| `lib/routes/return_after_sign_in.dart` | In-memory copy besides Hive |
| `lib/routes/route_pages.dart` | New: `NotFoundPage`, `NotAdminPage` |
| `lib/routes/app_routes.dart`, `app_router.dart` | `/no-access` route; `errorBuilder` |
| `lib/features/auth/presentation/screens/splash_screen.dart` | `RouteGuards.afterSplash(auth)` |
| `lib/features/auth/presentation/screens/login_screen.dart` | No own `go(home)` after sign-in |
| `lib/shared/widgets/site_header.dart` | Sign out → Events |
| `test/routes/routing_test.dart` | New, 34 tests (VM and Chrome) |
| `test/routes/routing_after_sign_in_test.dart` | New (second commit), 3 tests: the beta finding 021-8 (section 5a) |
| `test/routes/routing_source_test.dart` | New, 3 source checks (VM) |

---

## 4. Automated Verification

```bash
flutter test test/routes/
flutter test
flutter test --platform chrome test/features/ test/routes/
```

`routing_test.dart` uses the real `RouteGuards`, `ReturnAfterSignIn`, `NotFoundPage`, `NotAdminPage` and `SiteHeader`, in a router built like `AppRouter` (guard, `refreshListenable`, `errorBuilder`, the shell with the header) around the fake sign-in used by the ISSUE-001 tests. `AppRouter`, the splash and the login screen use the app's single `AuthController`, which cannot run under `flutter test`; `routing_source_test.dart` checks their source instead.

Checklist from `SUDARSHANA_BUG_LIST.md` item 8:

| Check | Test | Result |
|---|---|---|
| Signed out, `/my-events` → sign-in, then back to My Events | "/my-events: sign-in, then back to My Events"; "…to sign-in, and remembered" | PASS |
| Signed out, `/admin` → sign-in; an admin comes back, a non-admin gets "Not an admin" | "/admin: sign-in, then an admin lands on Admin"; "…a non-admin is told plainly"; `/admin`, `/admin/payments`, `/admin/registrations?event=7` remembered | PASS |
| Signed out, a check-in link → stays on its page (which asks to sign in and comes back, #40) | "a check-in link stays on its page, signed out or checking" | PASS |
| Refresh on an event page, My Events, an admin tab → same page | "refresh …: the splash comes back to it" (×3, query kept); signed out after the check → sign-in | PASS |
| Sign out from each page → Events | "signing out from …" for My Events, an event, an admin tab, a policy page; nothing remembered afterwards | PASS |
| An unknown URL → a friendly page | `/volunteer`, `/more`, `/events`, `/nope/at/all`: "Page not found", no `GoException`, Go to Events works | PASS |
| Public pages stay public | `/home`, `/home?mine=1`, the four policies, `/feedback`: no redirect, nothing remembered | PASS |
| `/events/{id}/checkout` stays | Guarded and remembered like the event page; route present in `AppRouter` | PASS |
| Wiring in `AppRouter`, splash, login screen | `routing_source_test.dart` | PASS |

### Totals

| | `main` (`fbe4ede`) | After ISSUE-021 |
|---|---|---|
| `flutter test` (VM) | 315 of 315 | 355 of 355 |
| Chrome, `test/features/` + `test/routes/` | 306 of 307 | 343 of 344 |
| New tests | — | 40 (37 VM and Chrome, 3 VM only) |

The Chrome failure is ISSUE-006 Test K, before and after.

### The same tests against the code before the fix

`routing_test.dart` does not compile on `fbe4ede` (`redirectFor`, `afterSplash`, the two pages and `AppRoutes.notAdmin` are new). It was run with a temporary shim that exposes `fbe4ede`'s own guard as `redirectFor` and its splash rule as `afterSplash`, and with the two new pages present:

- **24 of 37 fail:** every "to sign-in and remembered" and "back after sign-in" case, the non-admin page, all refresh cases, all four sign-out cases and the three source checks.
- **13 pass:** the public pages, the check-in link, signed-in access to the protected pages (behaviour `fbe4ede` already had right), and the four not-found screens. These pass only because the test router supplies the new page; `fbe4ede`'s `AppRouter` has no `errorBuilder`, which the source check catches.
- Two of the 24 ("signed in at sign-in: back to the remembered page", "opened at the root: a remembered page") also depend on the new in-memory copy: on `fbe4ede` `ReturnAfterSignIn` works only with the Hive box open, which the tests do not open.

---

## 5. Manual Verification

Beta run 1, reported by the tester on 2026-10-15: `https://nitksaa-events-beta.web.app`, `test/evening-batch` @ `39a0c23`, `main.dart.js` SHA-256 `e903f592…088b`, Incognito. Steps not reported are PENDING.

| # | Checklist | Step | Expected | Result |
|---|---|---|---|---|
| 1 | 021-1 | Signed out, open `/#/my-events` | Sign-in page; after signing in, My Events | PASS |
| 2 | 021-2 | Signed out, open `/#/admin` | Sign-in; an admin then lands in Admin, a non-admin sees "Not an admin" | PENDING |
| 3 | 021-3 | Signed out, open a check-in link | The check-in page asks to sign in, and comes back to it afterwards | PENDING |
| 4 | 021-4 | Refresh on an event page, My Events, an admin tab | The same page | PENDING |
| 5 | 021-5 | Sign out from Events, an event page, My Events, an admin tab | Events | PENDING |
| 6 | 021-6 | Open `/#/volunteer` and a mistyped address | "Page not found" with Go to Events | PASS |
| 7 | 021-7 | Signed out: Events, policies, feedback | Open without sign-in | PASS |
| 8 | 021-8 | Signed out, click an event card on Events | Sign-in, then back to that event | **FAIL** on `e903f592…`; fixed (section 5a), re-check PENDING |

---

## 5a. Beta finding 021-8 and fix

**Symptom.** Signed out, an event card on Events opened the "Sign In" page with a back arrow; the address bar still showed `#/home`. After "Continue with Google" the page said "Signed in." and stayed there.

**Reproduced** in `routing_after_sign_in_test.dart` with the real Events screen: on the first commit (`9cc3573`) the event-card test fails (the sign-in page is still shown after signing in).

**Root cause.** The event card *pushes* `/events/{id}`. The guard turns that push into sign-in, so the sign-in page is pushed on top of `/home` (the router's configuration is `/home` with matches `[/home, /login]`, which is why the address bar showed `#/home`). When the session changes, go_router re-runs the guard for `/home`, the page underneath, not for `/login`, so "just signed in at sign-in → back to the remembered page" never ran. Before this change the login screen's own `go(home)` hid this by always opening Events; the first commit removed that (it raced the guard and overrode the return), which left the pushed sign-in page with nothing to move it.

**Fix (second commit).** `route_guards.dart`: when signed in and a page is waiting in `ReturnAfterSignIn`, the guard sends it from whichever page the router re-checks, once. `ReturnAfterSignIn.isPending` checks without touching storage, so ordinary navigation costs nothing. Traced: after sign-in the guard sees `/home` and returns `/events/7`; the configuration becomes `/events/7`.

**Tests added** (`routing_after_sign_in_test.dart`): event card → sign-in → back to that event (real Events screen); the guard sends a waiting page once and not when already there; `/my-events` → sign-in → My Events lists the registration without a reload.

**Also reported: My Events sometimes empty right after sign-in.** Not caused by ISSUE-021, and not changed here:

- The `/my-events` → sign-in → My Events flow loads the list (the third test above passes, before and after the fix).
- The mechanism that does empty it is on `main` (`fbe4ede`) too. `myEventsProvider` watches `authControllerProvider`, so it is rebuilt empty on every notification of the auth controller, and My Events and Events fetch only when they open. One notification that does not change the user (e.g. `refreshSession()`, which the Admin pages call) leaves My Events at "No registrations yet" until a reload. Shown by a probe on `main`'s code: the list is there, one `notifyListeners()` without a change, and the page says "No registrations yet".
- Which notification happened on beta right after sign-in was not found in the code.
- A possible fix, for a separate change: rebuild `myEventsProvider` only when the session token changes (`ref.watch(authControllerProvider.select((a) => a.session?.accessToken))`), which keeps ISSUE-001's reset on a change of user.

---

## 6. Regression

All existing tests pass on the VM; in Chrome all but ISSUE-006 Test K, which fails on `main` too. The ISSUE-001/002/003 tests (sign-in, sign-out, account switch) pass.

---

## 7. Static Checks

| Check | Result |
|---|---|
| `flutter analyze` | 25 info before and after; identical lists |
| `flutter test` | 355 of 355 |
| Chrome | 343 of 344 (Test K, pre-existing; fixed by #62) |
| `tool/check_colors.sh` | OK |
| `flutter build web --release` (production URL) | Succeeded |

---

## 8. Remaining Risks

1. The event page still needs sign-in (see `ISSUE-021_ROUTING.md`, Scope 1).
2. The page opened during the sign-in check is kept in memory for that page load only, which is all a refresh needs.
3. A page remembered for sign-in is kept for 30 minutes (as for check-in links); if the person does not sign in then, a later sign-in within that time still returns there.
4. The login screen's own navigation was removed; it relies on the router noticing the session change, as the rest of the app already does. A sign-in page pushed over another page is handled by the guard's waiting-page rule (section 5a).
5. My Events can empty itself after an auth notification that does not change the user (section 5a). Pre-existing on `main`; not changed here.

---

## 9. Final Result

**CODE PASS — MANUAL E2E PENDING**

---

## 10. Commit

Branch `fix/issue-021` from `main` at `fbe4ede`.

| Commit | Message |
|---|---|
| `9cc3573` | `fix(routing): sign-in and back for protected pages, friendly not-found` |
| (second) | `fix(routing): back to the page after a pushed sign-in` (021-8) |

Both carry `ISSUE-021` in the body.

Pull request: `fix/issue-021` → `main`, "ISSUE-021: consistent signed-out routing and navigation". Not to be merged before Padmanand's check on beta.
