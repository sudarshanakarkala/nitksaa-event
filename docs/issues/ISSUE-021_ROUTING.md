# ISSUE-021 — Routing and Navigation

## Severity

P3 — Routing

## Status

Fixed on `fix/issue-021`, from `main` at `fbe4ede`. Code and automated tests pass. Manual run on beta PENDING. Not on the live site.

---

## Gap

Signed-out access and navigation were inconsistent. From the code on `fbe4ede`:

| Check (`SUDARSHANA_BUG_LIST.md` item 8) | On `fbe4ede` |
|---|---|
| Signed out, open `/my-events` | My Events opens and shows its own "Sign in to see My Events" box. After signing in from there: Events |
| Signed out, open `/admin` | Sign-in, but the page is not remembered: after signing in, Events |
| Signed in, not an admin, open `/admin` | Sent to Events, with no message |
| Signed out, open a check-in link | Stays on the page, which asks to sign in and comes back afterwards (#40). Correct |
| Refresh on an event page, My Events or an admin tab | While sign-in is checked every page goes to the splash, and the splash then opens Events: the page is lost |
| Sign out | The header's Sign out opens the login page |
| An unknown URL (`/volunteer`, `/more`, a typo) | go_router's default error page: "Page Not Found" and `GoException: no routes for location: …` |

Also: an event page opened signed out goes to sign-in without remembering the event; and after an in-page sign-in (email and password, Google, emailed link) the login screen itself opened Events, overriding any return.

---

## Root Cause

`lib/routes/route_guards.dart`:

1. Only paths starting with `/events/` needed sign-in; `/my-events` was left to the page.
2. Sign-in was asked for without remembering the page. `ReturnAfterSignIn` existed (for check-in links) but only the check-in page used it.
3. While sign-in was being checked (every page load and refresh), every page except the public and check-in pages was sent to the splash, which then went to a remembered check-in page or Events. Nothing kept the page that was opened.
4. A non-admin at `/admin…` was sent to Events.

Elsewhere:

5. `LoginScreen._runLogin` called `context.go(AppRoutes.home)` after a successful sign-in, racing the guard's own redirect.
6. `SiteHeader`'s Sign out went to `AppRoutes.login`.
7. `AppRouter` had no `errorBuilder`.

---

## Fix

| File | Change |
|---|---|
| `lib/routes/route_guards.dart` | `/my-events` also needs sign-in. A signed-out person at a page that needs it (`/my-events`, `/events/…`, `/admin…`) is sent to sign-in and the page is remembered (`ReturnAfterSignIn`). A page opened while sign-in is being checked is remembered, and `afterSplash` returns it. A non-admin at `/admin…` goes to `/no-access`. The logic is in `redirectFor(auth, uri)` so it can be tested |
| `lib/routes/return_after_sign_in.dart` | Also keeps the page in memory, for when the Hive box is not open |
| `lib/routes/route_pages.dart` (new) | `NotFoundPage` ("Page not found", Go to Events) and `NotAdminPage` ("Not an admin", Go to Events), on the shared `StateMessage` |
| `lib/routes/app_routes.dart`, `app_router.dart` | `AppRoutes.notAdmin` (`/no-access`) inside the shell; `errorBuilder` → `NotFoundPage` |
| `lib/features/auth/presentation/screens/splash_screen.dart` | Goes to `RouteGuards.afterSplash(auth)`: the page opened, else the remembered one, else Events |
| `lib/features/auth/presentation/screens/login_screen.dart` | No `go(home)` after signing in: the guard moves on (remembered page, else Events). Status text "Signed in." |
| `lib/shared/widgets/site_header.dart` | Sign out: to Events first, then sign out, so the page left is not remembered |

Unchanged on purpose: the event list, policies and feedback stay public; check-in links stay on their page and come back after sign-in; `/events/{id}/checkout` stays (paid events use it); NITiKa's "sign in again" still opens the login page.

No backend change. No restyling; theme colours only (the shared `StateMessage`).

---

## Scope

Fixed: ISSUE-021 only.

Reported, not changed:

1. **The event page is not public.** The bug list says to leave the event page public, but it has needed sign-in since the app was first imported (`507537c`), and the page has no signed-out view (its Register button assumes a session). It stays sign-in only; now it comes back to the event after sign-in. Making it public means a signed-out Register (e.g. "Sign in to register") on the event page, which is for Padmanand to decide.
2. **NITiKa's "sign in again"** (after its session ends) signs out and opens the login page, as before; it is not the header's Sign out.
3. **ISSUE-006 Test K** fails in Chrome on `main` and on this branch; fixed in `fix/test-006-k`.

---

## Status

CODE PASS — MANUAL E2E PENDING. See `ISSUE-021_ROUTING_TEST_REPORT.md`.
