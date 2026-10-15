# ISSUE-021 Routing Test Report

**Date:** 2026-10-15
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `fbe4ede` (branch `main`, after #58)
**Fix branch:** `fix/issue-021`
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, go_router 17.2.3, Chrome for the browser tests
**Final result:** CODE PASS — MANUAL E2E PENDING

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-021 |
| Severity | P3 |
| Area | Routing / navigation |
| Status | Fixed on `fix/issue-021`. Not on beta yet. Manual run PENDING. Not on the live site. |

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
| `flutter test` (VM) | 315 of 315 | 352 of 352 |
| Chrome, `test/features/` + `test/routes/` | 306 of 307 | 340 of 341 |
| New tests | — | 37 (34 VM and Chrome, 3 VM only) |

The Chrome failure is ISSUE-006 Test K, before and after.

### The same tests against the code before the fix

`routing_test.dart` does not compile on `fbe4ede` (`redirectFor`, `afterSplash`, the two pages and `AppRoutes.notAdmin` are new). It was run with a temporary shim that exposes `fbe4ede`'s own guard as `redirectFor` and its splash rule as `afterSplash`, and with the two new pages present:

- **24 of 37 fail:** every "to sign-in and remembered" and "back after sign-in" case, the non-admin page, all refresh cases, all four sign-out cases and the three source checks.
- **13 pass:** the public pages, the check-in link, signed-in access to the protected pages (behaviour `fbe4ede` already had right), and the four not-found screens. These pass only because the test router supplies the new page; `fbe4ede`'s `AppRouter` has no `errorBuilder`, which the source check catches.
- Two of the 24 ("signed in at sign-in: back to the remembered page", "opened at the root: a remembered page") also depend on the new in-memory copy: on `fbe4ede` `ReturnAfterSignIn` works only with the Hive box open, which the tests do not open.

---

## 5. Manual Verification

**PENDING.** To be run on `https://nitksaa-events-beta.web.app` in an Incognito window.

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Signed out, open `/#/my-events` | Sign-in page; after signing in (Google, email and password, and an emailed link), My Events | PENDING |
| 2 | Signed out, open `/#/admin` | Sign-in; an admin then lands in Admin, a non-admin sees "Not an admin" | PENDING |
| 3 | Signed out, open a check-in link | The check-in page asks to sign in, and comes back to it afterwards | PENDING |
| 4 | Refresh on an event page, My Events, an admin tab | The same page | PENDING |
| 5 | Sign out from Events, an event page, My Events, an admin tab | Events | PENDING |
| 6 | Open `/#/volunteer` and a mistyped address | "Page not found" with Go to Events | PENDING |
| 7 | Signed out: Events, policies, feedback | Open without sign-in | PENDING |

---

## 6. Regression

All existing tests pass on the VM; in Chrome all but ISSUE-006 Test K, which fails on `main` too. The ISSUE-001/002/003 tests (sign-in, sign-out, account switch) pass.

---

## 7. Static Checks

| Check | Result |
|---|---|
| `flutter analyze` | 25 info before and after; identical lists |
| `flutter test` | 352 of 352 |
| Chrome | 340 of 341 (Test K, pre-existing) |
| `tool/check_colors.sh` | OK |
| `flutter build web --release` (production URL) | Succeeded |

---

## 8. Remaining Risks

1. The event page still needs sign-in (see `ISSUE-021_ROUTING.md`, Scope 1).
2. The page opened during the sign-in check is kept in memory for that page load only, which is all a refresh needs.
3. A page remembered for sign-in is kept for 30 minutes (as for check-in links); if the person does not sign in then, a later sign-in within that time still returns there.
4. The login screen's own navigation was removed; it relies on the router noticing the session change, as the rest of the app already does.

---

## 9. Final Result

**CODE PASS — MANUAL E2E PENDING**

---

## 10. Commit

Branch `fix/issue-021` from `main` at `fbe4ede`.

```text
fix(routing): sign-in and back for protected pages, friendly not-found

ISSUE-021
```

Pull request: `fix/issue-021` → `main`, "ISSUE-021: consistent signed-out routing and navigation". Not to be merged before Padmanand's check on beta.
