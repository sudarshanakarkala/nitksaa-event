# NITKSAA-EVENT Flutter Frontend Verification Report 08 October 2026

**Date:** 2026-10-03
**Type:** Read-only verification (no source, config, or data was modified)
**Application under test:** `nitksaa-rakshit/nitksaa-event/frontend` (the "NEW" app)

Path abbreviations used throughout:

| Prefix | Absolute location |
|---|---|
| `NEW:` | `/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-rakshit/nitksaa-event/frontend/` |
| `BE:` | `/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/backend/` (reference backend; byte-identical to the copy inside `nitksaa-rakshit/nitksaa-event/backend/`) |
| `REF:` | `/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-payment/apps/payment_demo_app/` (reference payment/refund app) |
| `ADMIN-REF:` | `/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/admin/event_admin/` (reference React admin) |
| `API` | `https://nitksaa-events-api-246773894709.asia-south1.run.app` |
| `WEB` | `https://nitksaa-events.web.app` |

---

## Issue Summary Table

| ID | Severity | Flow | Issue | Issue type | Primary location | Fix location | Status |
|---|---|---|---|---|---|---|---|
| ISSUE-001 | **P0** | Auth / Event detail | User B sees User A's registration, badge no., QR, eligibility and profile after logout→login (stale `eventDetailProvider`) | UI/state | STATE_MANAGEMENT | NEW Flutter only | Confirmed (code, deterministic); runtime repro pending manual login |
| ISSUE-002 | P1 | Auth | Google web sign-in has no account chooser → after logout, popup silently re-signs the previous Google account | Integration | FIREBASE_AUTH | NEW Flutter only | Confirmed (code diff vs reference); runtime repro pending |
| ISSUE-003 | P2 | Auth | Backend login rejections (`email_not_verified`, `account_suspended`) shown as generic "Sign in failed"; Firebase left signed-in after backend rejection | UI | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed (code) |
| ISSUE-004 | P1 | Cancellation | "Unregister" calls `DELETE /api/v1/events/{event_id}/my-registration`, which does not exist → **HTTP 405** | API integration | API_CONTRACT_MISMATCH | NEW Flutter only | **Confirmed (runtime, production)** |
| ISSUE-005 | P1 | Refund | Refund never initiated and refund status never shown (no cancel/refund API integration at all) | API integration | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed (code + deployed bundle scan) |
| ISSUE-006 | **P0** | Pricing / Payment | "No of passes" (1–4) multiplies price in UI and button says "Confirm & Pay ₹(price×N)", but backend has no quantity: registers 1 seat and charges 1 pass | API integration (feature missing in backend) | API_CONTRACT_MISMATCH | Both (product decision) | Confirmed (code + live OpenAPI/schema); Razorpay amount runtime check pending |
| ISSUE-007 | P1 | Pricing | Fee summary uses public `ticket_price` instead of server pricing (`/payment-pricing` final amount incl. GST / convenience fee) | API integration | NEW_FLUTTER_FRONTEND | NEW Flutter only | Suspected (mismatch occurs only if GST/fee configured) |
| ISSUE-008 | P1 | Payment retry | Returning attendee with `seat_held`/`payment_pending`/`payment_failed` is told "You are registered" + QR badge and has no way to resume payment | UI + API integration | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed (code) |
| ISSUE-009 | P1 | Razorpay | Web checkout leaves Razorpay in-modal retry enabled; a success after an in-modal failure is ignored and never sent to verify-checkout | Integration | RAZORPAY_INTEGRATION | NEW Flutter only | Confirmed (code diff vs reference); runtime repro pending |
| ISSUE-010 | P2 | Payment status | No payment-status screen: no order re-read, no "check status" (`/payment-attempts/{id}/verify`), no timeline | API integration | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed (code) |
| ISSUE-011 | P2 | My Events | One card per registration row → same event appears multiple times after cancel/hold-expiry/re-register; in-flight statuses labelled "Unregistered" | UI | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed (code); runtime IDs pending |
| ISSUE-012 | P2 | Cancellation | Cancel button hidden unless event `registration_status == 'open'` — frontend-only rule not in backend | UI | NEW_FLUTTER_FRONTEND | NEW Flutter only (or backend policy) | Confirmed (code) |
| ISSUE-013 | P1 | Alumni eligibility | "Only alumni can register for events." — backend rule is login-time email match; frontend has no path to re-evaluate and can show stale verdicts | Data / backend rule / state | DATA (secondary: BACKEND_BUSINESS_LOGIC, STATE_MANAGEMENT) | Data correction + Flutter + backend logging | Rule confirmed; per-user cause needs runtime data |
| ISSUE-014 | P1 | Admin / RBAC | Admin UI gated on `user_type == 'admin'`, a value the backend never issues; backend has no role-discovery endpoint → admin features unreachable | RBAC contract | RBAC / API_CONTRACT_MISMATCH | Both | Confirmed (code) |
| ISSUE-015 | P2 | Admin | Admin contract mismatches: delete → 405; fees/sessions/speakers/sponsors/quantity limits silently dropped; paid event created without payment config; `X-Dev-User` header sent to prod | API integration | API_CONTRACT_MISMATCH | NEW Flutter (backend if features are wanted) | Confirmed (runtime 405 + schema) |
| ISSUE-016 | P1 | Build | `razorpay_flutter` imported but not declared → 6 analyzer errors; Android/iOS/desktop builds cannot compile | Build | DEPLOYMENT_CONFIG | NEW Flutter only | Confirmed (`flutter analyze`) |
| ISSUE-017 | P2 | Payment mode | TEST/LIVE ignored: no `payment_mode`/`real_money` handling, no banner, no live-payment confirmation, no key/mode guard | UI | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed (code) |
| ISSUE-018 | P2 | Errors | Raw `DioException …` strings / backend codes shown to attendees | UI | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed (code) |
| ISSUE-019 | P2 | Registration form | Editable Email/Phone are silently discarded; notes passed in the URL query and not length-validated | API integration | API_CONTRACT_MISMATCH | NEW Flutter only | Confirmed (code) |
| ISSUE-020 | P2 | Badge / check-in | QR badge encodes `registration_number` via third-party `api.qrserver.com`; backend check-in verifies `qrtoken`, which no attendee API exposes | API contract | API_CONTRACT_MISMATCH | Both | Confirmed (code) |
| ISSUE-021 | P3 | Routing | Unguarded `/my-events`, `/manage-events`, `/admin/...`; sidebar links to unregistered `/volunteer`, `/more` | UI | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed (code) |
| ISSUE-022 | P3 | Web shell / hosting | `checkout.js` loaded twice; title `event_app`; 1-hour cache on un-hashed `main.dart.js`; raw `user_type` shown as role | Config | DEPLOYMENT_CONFIG | NEW Flutter + hosting config | Confirmed |
| ISSUE-023 | P3 | Quality | Only 1 smoke test; 36 analyzer warnings; dead code | Code health | NEW_FLUTTER_FRONTEND | NEW Flutter only | Confirmed |

**Totals:** 23 issues — **P0: 2 · P1: 9 · P2: 9 · P3: 3**

---

## 1. Executive Summary

The NEW Flutter frontend implements login, event browsing, eligibility display, registration, and the **happy path** of Razorpay payment (order → attempt → checkout → verify-checkout) correctly against the backend. Everything **after** a payment, and everything that depends on knowing **who the user is across a session**, is broken or missing:

1. **Cancellation cannot work.** The app calls an endpoint that does not exist (`DELETE /api/v1/events/{id}/my-registration` → HTTP 405, verified against production). The backend expects `POST /api/v1/registrations/{registration_id}/cancel`.
2. **Refunds cannot happen from this app.** In this backend, a refund is created *by* the cancel endpoint. Because the app never reaches it, no refund is ever requested, and there is no refund-status call or UI. The deployed bundle contains no `/cancel` or `/refund` strings. The backend refund logic itself works (21/21 backend refund tests pass).
3. **Multi-pass pricing is a frontend-only invention.** The backend has no quantity concept anywhere. The UI shows "Confirm & Pay ₹(price × N)", but the backend creates one registration and Razorpay is opened for one pass. This is a financial-expectation integrity problem (P0).
4. **User switching leaks data (P0).** The event-detail state is a long-lived Riverpod family that is fetched once and never reset on logout, so User B sees User A's registration, badge number, QR, eligibility and alumni profile (name/email/phone) until a full page reload. Separately, the Google popup is not forced to show the account chooser (the reference app does this), so "log in as another user" often re-signs User A.
5. **Returning attendees cannot resume payment.** An unpaid seat hold is presented as "You are registered for this event." with a QR badge, and no Pay/Continue action exists. The reference app's "Continue Payment / Try Again / Check Payment Status" flow is absent.
6. **Admin features are unreachable.** The app shows admin UI only when `user_type == 'admin'`, but the backend only ever issues `alumni` or `other`. Real admin authorisation is role-table based, and there is no endpoint for a client to discover roles.
7. **Mobile builds are broken.** `razorpay_flutter` is imported but not declared in `pubspec.yaml`.

The deployed site is **not stale**: `WEB/main.dart.js` is byte-identical (SHA-256) to the local `frontend/build/web/main.dart.js`, which was built from the current `main` source and has the correct production backend URL baked in. Every issue above is therefore a source-code issue, not a deployment artefact.

**Verdict:** the NEW frontend does **not** yet correctly implement the backend's cancellation, refund, retry, payment-status, TEST/LIVE or admin workflows, and it has a P0 cross-user data exposure. It should not go to UAT until ISSUE-001, -004, -005, -006 and -008 are resolved.

---

## 2. Scope

**In scope:** the NEW Flutter app (static review of all of `lib/`, `web/`, `pubspec.yaml`, `firebase.json`), its deployed build, the production backend API (unauthenticated probes only), the backend source (reference), the `nitksaa-payment` reference app, and the React admin reference.

**Performed:**
- Full code inspection of the NEW app (≈20.9k lines Dart) and the payment/refund-relevant parts of the backend and reference app
- Live API probing of public and unauthenticated behaviour (status codes, OpenAPI route inventory, CORS)
- Deployed-bundle vs local-build comparison and bundle string scan
- `flutter analyze --no-pub` and `flutter test --no-pub` (no pub get, no lockfile change)
- Backend refund test suite against the **local development** database

**Not performed (requires a human sign-in — see §26):** authenticated runtime flows (login/logout/re-login with two accounts, registration, Razorpay TEST payment, cancellation, refund, admin screens). No Razorpay payment was initiated.

**Repository state at test time:** `nitksaa-rakshit/nitksaa-event` on branch `main` @ `db3abfa`, clean working tree. `frontend/lib` on `main` is identical to `rakshith-ui-master` @ `1a7d13f` (only `frontend/firebase.json` and `.firebaserc` differ). The session-start snapshot that showed `rakshith-ui-master` with local modifications was stale; those modifications are not present now.

---

## 3. Applications Reviewed

### Primary Flutter Frontend
- `NEW:` — package `event_app`, Flutter 3.44.2, Riverpod 2.6.1 (`StateNotifierProvider`/`ChangeNotifierProvider`), go_router 17, Dio 5, Hive (session storage), firebase_auth 6, google_sign_in 7.
- Auth: `AuthController` singleton (`ChangeNotifier`) + Hive box `auth_session`.
- API clients: `NEW:lib/features/auth/services/backend_auth_service.dart`, `NEW:lib/features/events/data/events_repository.dart` (no shared client, no interceptor, token passed manually per call).
- Payments: `NEW:lib/features/events/presentation/screens/checkout_screen.dart` + `services/razorpay_payment_{web,io,stub}.dart`.

### Backend Reference
- `BE:` @ `4b5f781` (FastAPI). Production instance reports `{"status":"ok","version":"0.1.0-alpha","env":"production","db":"ok"}`.
- Live OpenAPI route list matches the source exactly (52 non-diagnostic routes).

### Payment/Refund Reference App
- `REF:` @ `355c8cf` ("fix(payment status): improve cancellation and refund lifecycle"). Riverpod `autoDispose` providers, central `ApiClient`, dedicated repositories for pricing, orders, attempts, refunds, timelines; Payment Status screen with auto-refresh; My Registrations with per-status actions.

### Deployed Application
- `WEB` (Firebase Hosting target `events` → site `nitksaa-events`).
- `main.dart.js` SHA-256 `f98e34c8…291e` = local `build/web/main.dart.js` (built 2026-10-03 11:12 IST, deployed 05:43 UTC). `index.html` identical.
- Backend URL in bundle: `nitksaa-events-api-246773894709.asia-south1.run.app` (correct). The local fallback `127.0.0.1:8000` string is also present but is only used when no `--dart-define` is supplied.
- CORS preflight from `https://nitksaa-events.web.app` → `access-control-allow-origin` returned (OK).
- Service worker self-unregisters (no offline cache). `index.html` and `main.dart.js` are served with `cache-control: max-age=3600`.

---

## 4. Test Environment

| Item | Value |
|---|---|
| Host | macOS (Darwin 25.6.0), zsh |
| Flutter | 3.44.2 stable |
| Backend (prod) | Cloud Run, `env=production`, dev diagnostics disabled (verified 404) |
| Backend (local, for backend tests only) | `APP_ENV=development`, `localhost:5432/events_db`, `RAZORPAY_MODE=test` |
| Live events at test time | 8 published, all paid (₹1–₹4). Open: **#5** "EventFailTest", **#7** "Oct3New Event" (₹1.00, cap 10). Full: **#8** (cap 1). Closed: #1, #2, #3, #4, #6 |
| Browser automation | Not available in this session — authenticated UI steps require manual execution |

---

## 5. Backend API Inventory

Legend for "NEW uses": ✅ correct · ⚠️ used with contract problems · ❌ not used · 🚫 NEW calls an endpoint that does not exist.

### Attendee / auth

| Functional area | Method | API | Auth | NEW Flutter usage | Expected | Actual | Status |
|---|---|---|---|---|---|---|---|
| Login exchange | POST | `/api/v1/auth/firebase` `{token}` | Firebase ID token | `backend_auth_service.dart:38` | JWT + user_type | Same | ✅ PASS (error details discarded — ISSUE-003) |
| Current user | GET | `/api/v1/auth/me` | Bearer | `backend_auth_service.dart:52` | user | Same | ✅ PASS |
| Alumni profile | GET | `/api/v1/alumni/me` | Bearer, alumni only (403 `alumni_only`) | `events_repository.dart:222`, `event_detail_provider.dart:89` | profile | 403 silently swallowed, previous user's profile kept | ⚠️ FAIL (ISSUE-001) |
| Public events | GET | `/api/v1/events/public?period=` | none | `events_repository.dart:40` | list | 8 events | ✅ PASS (runtime) |
| Public event | GET | `/api/v1/events/public/{id}` | none | `events_repository.dart:140` (+ N+1 hydration in `getMyRegistrations`) | detail | Same | ✅ PASS (runtime) |
| Eligibility | GET | `/api/v1/events/{id}/registration-eligibility` | Bearer | `events_repository.dart:148` | verdict | Fetched once per app session per event | ⚠️ (ISSUE-001, -008, -013) |
| Register | POST | `/api/v1/events/{id}/register` `{attendee_note}` | Bearer, alumni | `events_repository.dart:205` sends `{attendee_note, quantity}` | 1 registration | `quantity` silently ignored | ⚠️ FAIL (ISSUE-006) |
| My registration (event) | GET | `/api/v1/events/{id}/my-registration` | Bearer | `events_repository.dart:156` | latest row, any status | Same; `latest_order_id` ignored | ⚠️ (ISSUE-008) |
| My registrations | GET | `/api/v1/my/registrations` | Bearer | `events_repository.dart:171` | all rows (history) | Rendered 1 card/row | ⚠️ (ISSUE-011) |
| Pricing | GET | `/api/v1/events/{id}/payment-pricing` | Bearer | — | server breakdown | Not called | ❌ (ISSUE-007) |
| Create order | POST | `/api/v1/registrations/{reg_id}/payment-order` `{idempotency_key}` | Bearer, owner | `events_repository.dart:269`, `checkout_screen.dart:323` | order (create-or-reuse) | Same | ✅ (code) |
| Get order | GET | `/api/v1/payment-orders/{order_id}` | Bearer, owner | — | order + `can_pay`/`can_retry`/`payment_mode` | Not called | ❌ (ISSUE-010) |
| Create attempt | POST | `/api/v1/payment-orders/{order_id}/attempts` `{}` | Bearer, owner | `events_repository.dart:284`, `checkout_screen.dart:331` | attempt + `checkout` | Same | ✅ (code) |
| Verify checkout | POST | `/api/v1/payment-orders/{order_id}/verify-checkout` | Bearer, owner | `events_repository.dart:299`, `checkout_screen.dart:350` | server-verified status | Same | ✅ (code) — not reached in ISSUE-009 case |
| Verify attempt (check status) | POST | `/api/v1/payment-attempts/{attempt_id}/verify` | Bearer, owner | — | provider re-query | Not called | ❌ (ISSUE-010) |
| Attendee timeline | GET | `/api/v1/payment-orders/{order_id}/timeline` | Bearer, owner | — | timeline incl. cancel/refund | Not called | ❌ |
| **Cancel (+ refund)** | **POST** | **`/api/v1/registrations/{reg_id}/cancel` `{idempotency_key}`** | Bearer, owner | — (calls 🚫 below instead) | `RefundStatusResponse` | Never called | ❌ **FAIL (ISSUE-004/-005)** |
| **Refund status** | **GET** | **`/api/v1/registrations/{reg_id}/refund`** | Bearer, owner | — | refund status (+provider refresh) | Never called | ❌ **FAIL (ISSUE-005)** |
| *(nonexistent)* | DELETE | `/api/v1/events/{event_id}/my-registration` | — | `events_repository.dart:194` | — | **HTTP 405 `Method Not Allowed`** (runtime) | 🚫 **FAIL** |
| Razorpay webhook | POST | `/api/v1/payments/webhook` | HMAC | n/a (server-to-server) | — | — | n/a |

### Admin

| Functional area | Method | API | Required role | NEW Flutter usage | Status |
|---|---|---|---|---|---|
| List events | GET | `/api/v1/events` | platform_admin | `events_repository.dart:56` (+ ignored `period`, + `X-Dev-User`) | ⚠️ |
| Create event | POST | `/api/v1/events` | platform_admin | `events_repository.dart:77` (extra fields dropped) | ⚠️ (ISSUE-015) |
| Get event (admin) | GET | `/api/v1/events/{id}` | platform_admin / event_admin | — | ❌ |
| Update event | PATCH | `/api/v1/events/{id}` | platform_admin / event_admin | `events_repository.dart:93` | ⚠️ |
| Update status | PATCH | `/api/v1/events/{id}/status` | platform_admin / event_admin | `events_repository.dart:110` | ✅ (code) |
| *(nonexistent)* delete event | DELETE | `/api/v1/events/{id}` | — | `events_repository.dart:127` | 🚫 **405 (runtime)** |
| Admin events v2 | GET/POST/PATCH | `/api/v1/admin/events`, `/{id}`, `/{id}/publish`, `/{id}/close`, `/{id}/sessions` | platform_admin / event_admin | — | ❌ |
| Attendees (registered only) | GET | `/api/v1/admin/events/{id}/attendees` | platform_admin / event_admin | `events_repository.dart:230` | ✅ (code) |
| Attendee export | GET | `/api/v1/admin/events/{id}/attendees/export` | platform_admin / event_admin | — (client-side CSV) | ❌ |
| Registrations (all statuses) | GET | `/api/v1/admin/events/{id}/registrations` | platform_admin / event_admin | — | ❌ |
| Check-in verify / create / list / attempts | GET/POST | `/api/v1/admin/events/{id}/check-ins…` | platform_admin / event_admin | — | ❌ |
| People / sponsors / partners CRUD | GET/POST/PUT/DELETE | `/api/v1/events/{id}/people|sponsors|partners` | platform_admin / event_admin | — (sent inline in create payload and dropped) | ❌ |
| Payment configurations | POST/GET + validate/publish | `/api/v1/admin/events/{id}/payment-configurations…` | event_admin (write), + finance/auditor/support (read) | — | ❌ |
| Platform roles | POST/GET + revoke | `/api/v1/admin/payment-roles…` | platform_admin (list: + auditor) | — | ❌ |
| Event payment admin grant | POST | `/api/v1/admin/events/{id}/payment-admins` | platform_admin | — | ❌ |
| Lifecycle sweeps | POST | `/api/v1/admin/payments/lifecycle/expire-orders`, `/expire-registration-holds` | platform_admin | — | ❌ |
| Gateway config (read) | GET | `/api/v1/admin/payments/gateway-config` | platform_admin/finance/auditor/support | — | ❌ |

**Not present in the backend at all:** any admin/finance refund, admin cancellation, refund approval, registration-status override, payment reconciliation, or "my roles" endpoint.

---

## 6. Flutter Feature Inventory

| Feature | Screen / file | Backend API(s) | Works? |
|---|---|---|---|
| Splash + session restore | `splash_screen.dart`, `auth_controller.dart:41-80` | `GET /auth/me` | Yes |
| Email/password login | `login_screen.dart`, `auth_controller.dart:82` | Firebase + `POST /auth/firebase` + `GET /auth/me` | Yes (errors masked) |
| Google login | `firebase_auth_service.dart:26` | same | Partially (no account chooser) |
| Logout | `app_sidebar.dart:380/426`, `event_list_screen.dart:49-61`, `home_placeholder_screen.dart` | none (client only) | Partially (state not reset) |
| Event list + filters | `event_list_screen.dart`, `events_provider.dart` | `/events/public` | Yes (runtime) |
| Event detail + eligibility + CTA | `event_detail_screen.dart`, `event_detail_provider.dart` | public event, eligibility, my-registration, alumni/me | Stale state across users |
| Registration form ("No of passes", email, phone, notes) | `event_detail_screen.dart:1291-1460` | none until checkout | Inputs mostly discarded |
| Checkout + Razorpay | `checkout_screen.dart`, `razorpay_payment_web.dart` | register, payment-order, attempts, verify-checkout | Happy path only |
| QR badge | `event_detail_screen.dart:1846-2101` | none (third-party QR) | Not check-in compatible |
| My Events + Unregister | `my_events_screen.dart`, `my_events_provider.dart` | my/registrations, 🚫 DELETE my-registration | Cancel broken |
| Manage Events (admin) | `manage_events_screen.dart` | `/api/v1/events` CRUD + status, 🚫 DELETE | Unreachable (ISSUE-014) |
| Event Registrations (admin) | `event_registrations_screen.dart` | `/api/v1/events`, `/admin/events/{id}/attendees` | Unreachable (ISSUE-014) |
| Developer diagnostics | `developer_diagnostics_screen.dart` (route only in `kDebugMode`) | dev diagnostics (404 in prod) | Debug only |

**Not found in the NEW app:** refund UI, refund status, payment status screen, payment retry entry point, payment timeline, TEST/LIVE banner, pricing breakdown, check-in, payment configuration, role management.

---

## 7. Authentication

### Login
`POST /auth/firebase` → `GET /auth/me` → session saved in Hive (IndexedDB on web). Correct sequence; identical to the reference app. **Gaps:** backend `detail` is discarded (`auth_controller.dart:177-192` returns "Sign in failed. Please try again." for every non-Firebase error), so `403 email_not_verified` (backend rule added 2026-10-01, `BE:app/api/auth.py:50-51`) and `403 account_suspended` are indistinguishable from a network failure (ISSUE-003).

### Logout
`AuthController.signOut()` (`auth_controller.dart:96-106`) **does** clear the Hive session and call `FirebaseAuth.instance.signOut()`. On web it deliberately skips `GoogleSignIn.signOut()` (`firebase_auth_service.dart:64`), so the browser's Google session survives (expected Firebase behaviour). **What is not cleared:** every `eventDetailProvider(eventId)` instance created during the session (ISSUE-001). The backend JWT is stateless and is not revoked (valid for 480 minutes, `BE:app/config.py:38`).

### Re-login
Status transitions `unauthenticated → authenticating → authenticated` are correct. `myEventsProvider` is rebuilt on auth change (it `watch`es `authControllerProvider`), so **My Events is correct** for User B. `eventDetailProvider` is **not** rebuilt, so **Event Detail and Checkout are wrong** for User B.

### User Switching
Two independent failure modes:
1. **Google popup re-selects User A** — no `prompt=select_account` (ISSUE-002).
2. **User A's per-event data shown to User B** — stale provider (ISSUE-001).

### Session Persistence

| Store | Contents | Cleared on logout? |
|---|---|---|
| Hive box `auth_session` (IndexedDB) | backend JWT, firebase_uid, email, fullname, user_type, ref_id, graduation_year | Yes (`auth_session_store.dart:30-33`) |
| Firebase Auth (IndexedDB `firebaseLocalStorageDb`) | Firebase user | Yes (`FirebaseAuth.signOut`) |
| Google account cookie (accounts.google.com) | Google browser session | No (by design; reference app solves via `select_account`) |
| Riverpod `eventDetailProvider` family (memory) | eligibility, my registration, alumni profile per event | **No** — survives until full page reload |
| Riverpod `myEventsProvider` (memory) | registrations | Yes (rebuilt) |
| `localStorage`, `sessionStorage`, `SharedPreferences` | — | Not used |

A full browser reload clears the Riverpod state, which is why the problem appears "intermittent" to testers.

---

## 8. Event Discovery

| Check | Result |
|---|---|
| `/events/public?period=upcoming` returns 8 events (filter is `end_datetime >= now`) | PASS (runtime) |
| Only `published` events are listed by backend; cancelled/draft never shown | PASS (backend `events_repository.py:209`) |
| Cancelled **registrations** shown as events in the event list | No — the event list never merges registrations (PASS) |
| Registration open/closed/full status | Backend-computed `registration_status`; UI filters use it directly (PASS) |
| Alumni-only flag per event | Not modelled — **every** registration is alumni-only in the backend (`registration_service.py:84-85`) |
| Minor backend inconsistency | Public `registered_count`/`registration_status` count only `registered`, while eligibility capacity for paid events also counts held seats → an event can show "open" in the list but "full" on eligibility (Suspected S-1) |

---

## 9. Alumni Eligibility

**Authoritative rule (backend):**
1. At **login only** (`POST /auth/firebase`, `BE:app/api/auth.py:53-69`), the Firebase token's email is matched case-insensitively against `alumni_db.alumni.email` (`BE:app/services/alumni_service.py:15-31`). Match → `event_users.user_type='alumni'`, `ref_id=alumni_id`; no match → `'other'`.
2. Alumni status is **sticky**: once `alumni`, a later login with no match does not downgrade it (`auth.py:131-133`).
3. If the alumni-DB lookup throws, login continues silently as `other` (`auth.py:54-59`).
4. At eligibility/registration time the backend additionally requires `alumni.registrationstatus ∈ {Active, Self-Verified}` (`alumni_service.py:7`).
5. Previous event registrations do **not** confer alumni status.

**What NEW Flutter does:** it does **not** duplicate the rule; it shows the backend's `eligibility_status`/`message` (`event_detail_screen.dart:1220-1235`). That is correct. The problems are around it — see ISSUE-013 and ISSUE-001.

| Scenario | Backend outcome | NEW app outcome |
|---|---|---|
| Known alumni, Firebase email = alumni email, Active | eligible | Correct (first visit in session) |
| Alumni who signs in with a different Google address | `other` → "Only alumni can register for events." | Shows that message; no hint about which email is needed |
| Alumni record added after user's last login | still `other` until next `POST /auth/firebase` | Session restore uses only `/auth/me`, so stays ineligible until explicit logout/login |
| Alumni with `registrationstatus` not Active/Self-Verified | "Alumni account is not active." | Shows message |
| Previous attendee (non-alumni) | `other` | Correct |
| User B after User A in same tab | B's real verdict | **A's verdict shown** (ISSUE-001) |

---

## 10. Registration

**Trace:** Register button → `_showRegistrationForm` (`event_detail_screen.dart:1291`) → "Proceed to Checkout" → `context.push('/events/{id}/checkout?quantity=N&notes=…')` (`:1683-1688`) → `CheckoutScreen._confirmRegistration` (`checkout_screen.dart:276`) → `EventDetailNotifier.register` (`event_detail_provider.dart:105`) → `POST /api/v1/events/{id}/register` body `{"attendee_note": "...", "quantity": N}`.

**Backend:** `RegisterRequest` accepts only `attendee_note` (≤500 chars) (`BE:app/schemas/registrations.py:9-17`); Pydantic ignores extra keys. Paid event → status `seat_held`, `hold_expires_at = now + seat_hold_minutes`. Free event → `registered`.

**Duplicate registration:** prevented by backend (`409 already_registered` under `SELECT … FOR UPDATE`). Frontend surfaces it as a raw `DioException` string (ISSUE-018). It is never converted into another registration.

**Registration-form defects (Issue 3 candidates):**

| Field / control | Frontend | Backend | Defect |
|---|---|---|---|
| No of passes | Dropdown 1..4 (hardcoded fallback; `registration_min/max_quantity` never returned by API) | No such concept | Value discarded; price multiplied in UI (ISSUE-006) |
| Badge name | Read-only from `alumniProfile` | Snapshot from alumni DB | Can show **previous user's** name (ISSUE-001) |
| Email | Editable, prefilled | Snapshot from alumni DB | Edits silently discarded (ISSUE-019); can be previous user's email (ISSUE-001) |
| Phone | Editable, prefilled | Snapshot from alumni DB | Same as Email |
| Notes | Free text, sent via URL query string | `attendee_note` ≤500 | Not length-validated → 422 shown raw; note visible in browser history |
| CTA after seat hold | "You are registered" + QR | Status `seat_held` (unpaid) | Misleading; no resume (ISSUE-008) |

---

## 11. Participant / Quantity / Pricing

### Trace across layers (event #7, `ticket_price = ₹1.00`)

```text
Flutter display (checkout_screen.dart:151-152, 249)
   unitPrice = event.ticketPrice (public) ; grandTotal = unitPrice × quantity
        ↓
Registration request (events_repository.dart:211-216)
   {"attendee_note": "...", "quantity": N}
        ↓
Backend register (registration_service.py:75)  ← quantity silently dropped (no field)
   creates ONE registration (seat_held)
        ↓
Backend order (payment_service.py:198 create_order)
   final_amount = calculate_price(published config) — one pass, no quantity input
        ↓
Razorpay (payment_service.py create_attempt → checkout.amount_minor = final_amount × 100)
   NEW opens checkout with amount_minor from backend (checkout_screen.dart:343)
```

| Qty | Flutter display ("Confirm & Pay") | Backend order amount | Razorpay amount | Expected (current backend contract) |
|---:|---:|---:|---:|---:|
| 1 | ₹1 | F (= ₹1.00 if no GST/fee) | F × 100 paise | F |
| 2 | **₹2** | F | F × 100 paise | F — only one seat exists |
| 3 | **₹3** | F | F × 100 paise | F |
| 4 | **₹4** | F | F × 100 paise | F |

`F` = `final_amount` of the event's published payment configuration (base + GST + convenience fee). Reading `F` for event #7 needs an authenticated `GET /api/v1/events/7/payment-pricing`; not yet run.

**First incorrect layer:** the NEW Flutter registration screen, which offers a quantity the backend contract does not have. From the backend's point of view its amount is internally consistent; from the attendee's point of view they were promised N passes for ₹(N × price) and receive one seat for ₹F.

**Reference app:** has no quantity selector; registers with `attendee_note` only (`REF:lib/features/registrations/services/registration_repository.dart:11-17`) and shows `pricing.finalAmount` from `/payment-pricing` (`REF:…/payment_review_screen.dart:70,186`).

---

## 12. Razorpay Payment

### Order Creation
`POST /registrations/{id}/payment-order` with a new idempotency key per click (`checkout_screen.dart:326-327`). Backend reuses the active order for the registration, so a new key per click is harmless. ✅

### Checkout
Options: `key`, `amount`, `currency`, `order_id`, `name`, `description` from backend `checkout` object (`checkout_screen.dart:338-348`). Key is never hardcoded (good). Missing vs reference: `prefill`, `retry: {enabled:false}` (ISSUE-009), key-prefix/mode guard and LIVE confirmation (ISSUE-017). `checkout.js` is included twice in `web/index.html:37,40` (ISSUE-022).

### Payment Verification
On the Razorpay `handler` callback the app calls `verify-checkout` with our `ORD-…` id and Razorpay's `{payment_id, order_id, signature}` (`checkout_screen.dart:350-356`) — field names and id types match the backend (`BE:app/schemas/payments.py VerifyCheckoutRequest`). ✅ Confirmation is taken from `payment_confirmed` in the response, not the SDK callback. ✅

### Payment Retry
`checkout_screen.dart:286-289` *can* reuse a registration in `seat_held/payment_pending/payment_failed`, and the backend reuses an `initiated` attempt (`payment_service.py:479 _reusable_hosted_checkout`). But the event-detail CTA hides every path to the checkout for those statuses (ISSUE-008), and `latest_order_id` is never used. Effective retry support: **No**.

### Payment Status
No `GET /payment-orders/{id}`, no `POST /payment-attempts/{id}/verify`, no timeline. If verify-checkout returns "pending" or fails with 502, the user sees a snackbar and nothing else (ISSUE-010).

### Payment mode
Production Razorpay mode is not visible without an authenticated order response (`payment_mode`). The NEW app does not read `payment_mode` or `real_money` anywhere (bundle scan: 0 occurrences). **Testers cannot tell from the NEW UI whether a ₹1 event is TEST or LIVE**; use the Razorpay modal's "Test Mode" ribbon.

---

## 13. Cancellation

**Backend state machine** (`BE:app/services/refund_service.py:105-270`):

```text
registered + no paid order  ──cancel──▶ cancelled                       (refund status "none")
registered + paid order     ──cancel──▶ cancelled  + payment_refunds row ─▶ provider refund call
                                         refund: pending → processing → processed | failed
cancelled                   ──cancel──▶ (idempotent) current refund view
seat_held / payment_pending / payment_verification / payment_failed ──cancel──▶ 409 registration_not_cancellable
                                         (these expire via hold expiry instead)
```

**NEW app:** `MyEventsNotifier.cancelRegistration(eventId)` (`my_events_provider.dart:66-80`) → `EventsRepository.cancelMyRegistration` (`events_repository.dart:194-203`) → `DELETE /api/v1/events/{eventId}/my-registration` → **405**. Snackbar "Could not unregister." No cancellation is possible for any status. Cancel is also only offered when the event's registration window is open (ISSUE-012).

| Case | Backend expected | NEW app actual |
|---|---|---|
| Registered unpaid (free) | cancelled, status `none` | 405 |
| Registered paid | cancelled + refund | 405 |
| Seat held (unpaid paid-event) | 409 `registration_not_cancellable` | No cancel button for this status (it is labelled "Unregistered") |
| Already cancelled | idempotent 200 | No cancel button |
| Refunded | idempotent 200 with refund view | No cancel button |

---

## 14. Refund

### Refund Initiation
Only through `POST /api/v1/registrations/{registration_id}/cancel` (attendee). Refund amount = paid order's `final_amount`; provider payment id = captured attempt's `gateway_payment_ref`; refund `payment_mode` = captured attempt's mode (cross-mode refund refused). One active refund per order (DB unique index) + idempotency key.

### Authorization

| Operation | Attendee (owner) | event_admin | platform_admin | finance_operator | auditor | support |
|---|---|---|---|---|---|---|
| Cancel own registration + create refund | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Read refund status (own) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Cross-user cancel/status | 404 (no existence leak) | — | — | — | — | — |
| Admin/finance refund, approval, retry | *No endpoint exists* | | | | | |

### Razorpay Refund
Synchronous provider call after commit; provider error → refund `failed` with "Our team will follow up" (no backend retry/admin path exists — Suspected S-4).

### Refund Status
`GET /registrations/{id}/refund` returns `refund_pending | refund_processed | refund_failed | none` and refreshes from the provider when non-terminal.

### UI Status
**NEW app: none.** No call, no model, no UI. Reference app: `_RefundSection` (`REF:…/payment_status_screen.dart:437-533`) with amount, status label, safe message, "Check refund status".

### Refund step table (Issue 2)

| Refund step | Backend supports | Reference app | NEW app | Gap |
|---|---:|---:|---:|---|
| Identify paid registration | Yes (`latest_order_id`, order status) | Yes (`my_registrations_screen.dart:101-155`) | No (`latest_order_id` not parsed in `my_event_registration.dart`) | FRONTEND |
| Request cancellation | Yes (`POST /registrations/{id}/cancel`) | Yes (`refund_repository.dart:20`, `payment_status_screen.dart:258-298`) | **Wrong endpoint → 405** | API CONTRACT |
| Create refund | Yes (inside cancel) | Yes (implicit) | No (cancel never succeeds) | FRONTEND |
| Capture refund ID | Yes (`refund_id` in response) | Yes (`RefundStatus.refundId`) | No | FRONTEND |
| Refresh refund status | Yes (`GET /registrations/{id}/refund`) | Yes (`refundStatusProvider`, "Check refund status") | No | FRONTEND |
| Update UI | — | Yes (`_RefundSection`, invalidates My Registrations) | No | FRONTEND |

**Traceability (Issue 2):**

```text
User taps "Unregister" (My Events)                        my_events_screen.dart:197 → _confirmCancel :222-255
   ↓
MyEventsNotifier.cancelRegistration(eventId)               my_events_provider.dart:66
   ↓
EventsRepository.cancelMyRegistration(eventId, token)      events_repository.dart:194
   ↓
DELETE /api/v1/events/{event_id}/my-registration           ✗ DIVERGES HERE — route does not exist (HTTP 405)
   ↓  (expected)
POST /api/v1/registrations/{registration_id}/cancel        BE:app/api/refunds.py:18
   ↓
refund_service.cancel_registration                         BE:app/services/refund_service.py:105
   ↓
registration → cancelled; payment_refunds row; Razorpay refund
   ↓
Actual: nothing changes in DB; snackbar "Could not unregister."
```

---

## 15. Admin Features

Inventory of admin functionality found in the NEW app:

| Feature | Frontend screen | Backend API | Required role | Status | Issue |
|---|---|---|---|---|---|
| Admin role detection | `app_sidebar.dart:103-117`, `app_bottom_nav.dart:28`, `manage_events_screen.dart:35-37,301` | none (uses `user_type`) | — | FAIL | ISSUE-014 |
| List events (published/draft tabs) | `manage_events_screen.dart:98` | `GET /api/v1/events` | platform_admin | Unreachable | ISSUE-014 |
| Create event | `manage_events_screen.dart:2801-2857` | `POST /api/v1/events` | platform_admin | Unreachable; fees/sessions/speakers/sponsors/qty dropped | ISSUE-015 |
| Edit event | `manage_events_screen.dart:2859` | `PATCH /api/v1/events/{id}` | platform_admin / event_admin | Unreachable; same drops | ISSUE-015 |
| Publish / unpublish | `manage_events_screen.dart:135,187` | `PATCH /api/v1/events/{id}/status` | platform_admin / event_admin | Unreachable | ISSUE-014 |
| Delete event | `manage_events_screen.dart:260` | 🚫 `DELETE /api/v1/events/{id}` | — | **405 (runtime)** | ISSUE-015 |
| Registrations/attendees list + search + batch filter | `event_registrations_screen.dart:85,120` | `GET /api/v1/events` + `GET /admin/events/{id}/attendees` | platform_admin (list) / event_admin (attendees) | Unreachable; event_admin cannot load list (platform-only) | ISSUE-014/-015 |
| CSV export | `event_registrations_screen.dart:279-292` | none (client-side) | — | Unreachable | — |
| Payment views / refund views / cancellation approval / reconciliation / check-in | — | partly exist (see §5) | — | Not implemented | §18 |

The reference admin (`ADMIN-REF:src/api/*.js`) uses the same `/api/v1/events` + `/admin/events/{id}/attendees|registrations` endpoints, never calls a DELETE, and does not send `X-Dev-User`.

---

## 16. RBAC

**Backend roles (actual):** platform roles `platform_admin`, `finance_operator`, `auditor`, `support` (`payment_platform_roles` table + `PLATFORM_ADMIN_FIREBASE_UIDS` env bootstrap); event-scoped `event_admin` (`event_members`). `user_type` (`alumni`/`other`) is **not** an authorisation role. (`BE:app/middleware/admin_auth.py`)

**Flutter:** derives admin from `session.userType == 'admin'`; caches it in the session; the backend never returns `admin` (`BE:app/api/auth.py:61-69`). Consequences:
- Authorised admins never see admin UI (hides authorised actions).
- Unauthorised users never see admin UI either (no exposure) — and any admin URL they open directly is rejected by the backend (403), which is correct.
- Admin A → logout → regular User B: no admin UI can persist, because none is ever shown; `user_type` comes from B's fresh session.
- Setting `event_users.user_type='admin'` in the DB to "unlock" the UI would make that user fail `alumni_only` on registration and still fail admin APIs unless roles are also granted.
- `X-Dev-User: admin` sent by the NEW app is inert in production (verified: `GET /auth/me` with only that header → 403). Not a security hole, but a dev-only assumption leaking into production code.

---

## 17. NEW Frontend vs Reference Payment App

| Capability | Reference App (`REF:`) | NEW App (`NEW:`) | Backend requirement | Gap |
|---|---|---|---|---|
| Create order | Yes — `payment_order_repository.dart:16`, `payment_review_screen.dart:47` | Yes — `events_repository.dart:269`, `checkout_screen.dart:323` | `{idempotency_key}` | None |
| Server pricing before pay | Yes — `pricing_repository.dart:11`, `payment_review_screen.dart:70,186` | No — `ticket_price × qty` | `GET /payment-pricing` | FRONTEND (ISSUE-007) |
| Create attempt | Yes — `payment_attempt_repository.dart:21` | Yes — `events_repository.dart:284` | `{}` for Razorpay | None |
| Payment callback | Success/cancel/fail/external-wallet; `retry.enabled=false` — `razorpay_checkout_web.dart:52-82` | Success/dismiss/fail; retry left enabled — `razorpay_payment_web.dart:61-127` | — | RAZORPAY (ISSUE-009) |
| Prefill name/email | Yes | No | — | Minor |
| Verification | Yes → Payment Status screen — `razorpay_checkout_screen.dart:225` | Yes → snackbar — `checkout_screen.dart:350-370` | verify-checkout | Partial (ISSUE-010) |
| Check status / verify attempt | Yes — `payment_status_screen.dart:237` | No | `POST /payment-attempts/{id}/verify` | FRONTEND |
| Order status + auto-refresh | Yes — `payment_status_screen.dart:148-215` | No | `GET /payment-orders/{id}` | FRONTEND |
| Retry / returning attendee | Yes — `my_registrations_screen.dart:101-155` ("Continue Payment", "Try Again", "Check Payment Status") | No entry point (ISSUE-008) | `latest_order_id`, `can_retry` | FRONTEND |
| Cancellation | Yes — `refund_repository.dart:20` `POST /registrations/{id}/cancel` | Wrong — `events_repository.dart:194` `DELETE /events/{id}/my-registration` | POST cancel | API CONTRACT (ISSUE-004) |
| Refund | Yes (via cancel) | No | via cancel | FRONTEND (ISSUE-005) |
| Refund status | Yes — `refund_repository.dart:30`, `payment_status_screen.dart:437` | No | `GET /registrations/{id}/refund` | FRONTEND (ISSUE-005) |
| Timeline | Yes — `timeline_repository.dart:13` | No | `GET /payment-orders/{id}/timeline` | FRONTEND |
| TEST/LIVE separation | Yes — `payment_mode_banner.dart`, LIVE confirm + key-prefix guard `razorpay_checkout_screen.dart:109-160` | No | `payment_mode`, `real_money` | FRONTEND (ISSUE-017) |
| Friendly error mapping | Yes — `core/errors/friendly_error_message.dart` | No | `detail` codes | FRONTEND (ISSUE-018) |
| Google account chooser | Yes — `firebase_auth_service.dart:32` `prompt: select_account` | No | — | AUTH (ISSUE-002) |
| Provider lifecycle | `autoDispose` everywhere, invalidation after cancel/pay | Non-`autoDispose` family, fetched once | — | STATE (ISSUE-001) |
| Mobile Razorpay dependency | `razorpay_flutter: ^1.4.6` in pubspec | Imported, not declared | — | BUILD (ISSUE-016) |

## Features Present in Reference App but Missing from NEW Flutter

| Feature | Reference file | NEW equivalent | Status | Impact |
|---|---|---|---|---|
| Cancel registration (correct API) | `REF:lib/features/refunds/services/refund_repository.dart:20` | `events_repository.dart:194` (wrong endpoint) | Broken | P1 |
| Refund status + refresh | `REF:…/refund_repository.dart:30`, `payment_status_screen.dart:437` | — | Missing | P1 |
| Payment retry / continue payment | `REF:…/my_registrations_screen.dart:101-155` | Reuse logic only in `checkout_screen.dart:286` (unreachable) | Missing | P1 |
| `latest_order_id` recovery | `REF:lib/features/registrations/domain/registration.dart:40` | Not parsed | Missing | P1 |
| Payment status screen + auto-refresh | `REF:…/payment_status_screen.dart:117-330` | — | Missing | P2 |
| Check status (`verifyAttempt`) | `REF:…/payment_attempt_repository.dart:29` | — | Missing | P2 |
| Server pricing breakdown | `REF:lib/features/pricing/services/pricing_repository.dart:11` | — | Missing | P1 |
| Attendee timeline | `REF:lib/features/timelines/…` | — | Missing | P3 |
| TEST/LIVE banner, LIVE confirm, key guard | `REF:lib/core/widgets/payment_mode_banner.dart`, `razorpay_checkout_screen.dart:109-160` | — | Missing | P2 (P1 before LIVE) |
| Razorpay `retry.enabled=false` | `REF:…/razorpay_checkout_web.dart:71` | — | Missing | P1 |
| Friendly error messages | `REF:lib/core/errors/friendly_error_message.dart` | — | Missing | P2 |
| Google `select_account` | `REF:lib/core/auth/services/firebase_auth_service.dart:32` | — | Missing | P1 |
| Central API client (token read at call time, normalised errors) | `REF:lib/core/network/api_client.dart`, `api_client_provider.dart` | Token passed per call; raw Dio errors | Missing | P2 |
| Policy acceptance before pay | `REF:…/payment_review_screen.dart:140` | — | Missing | P3 |

---

## 18. API Integration Gaps

## Backend APIs Not Used by NEW Flutter Frontend

| API | Purpose | Reference app uses it? | NEW Flutter uses it? | Impact |
|---|---|---:|---:|---|
| `POST /api/v1/registrations/{id}/cancel` | Cancel + full refund | Yes | **No** (calls nonexistent DELETE) | Cancellation and refund impossible |
| `GET /api/v1/registrations/{id}/refund` | Refund status | Yes | **No** | Refund state invisible |
| `GET /api/v1/events/{id}/payment-pricing` | Server price breakdown | Yes | **No** | UI amount may differ from charge |
| `GET /api/v1/payment-orders/{id}` | Order status, `can_pay`, `can_retry`, `payment_mode` | Yes | **No** | No status/retry/mode awareness |
| `POST /api/v1/payment-attempts/{id}/verify` | Provider re-query ("Check status") | Yes | **No** | Pending payments can't be resolved by attendee |
| `GET /api/v1/payment-orders/{id}/timeline` | Attendee timeline incl. cancel/refund | Yes | **No** | No history |
| `GET /api/v1/events/{id}` (admin) | Admin event read | n/a | No | Minor |
| `/api/v1/admin/events` family (list/create/patch/publish/close/sessions) | Admin events v2 | ADMIN-REF no | No | Optional |
| `GET /api/v1/admin/events/{id}/registrations` | All-status audit list | ADMIN-REF yes | **No** | Admin can't see cancelled/in-flight |
| `GET /api/v1/admin/events/{id}/attendees/export` | Server CSV | ADMIN-REF yes | No (client CSV) | Minor |
| `/api/v1/admin/events/{id}/check-ins…` (4 routes) | QR check-in | No | **No** | No check-in UI |
| `/api/v1/events/{id}/people|sponsors|partners` CRUD | Event enrichment | ADMIN-REF yes | **No** (inline fields dropped) | Admin edits lost |
| `/api/v1/admin/events/{id}/payment-configurations…` (5 routes) | Paid-event setup | No | **No** | Admin-created paid events → `payment_not_configured` |
| `/api/v1/admin/payment-roles…`, `/payment-admins` | Role management | No | No | Roles DB-only |
| `/api/v1/admin/payments/lifecycle/*` | Expiry sweeps | No | No | Holds expire lazily |
| `/api/v1/admin/payments/gateway-config` | Gateway diagnostics | No | No | Minor |

## Backend Capabilities Not Exposed in NEW Flutter UI

| Capability (exists in backend) | Who may use it | Exposed in NEW UI? |
|---|---|---|
| Attendee cancellation with automatic full refund | Attendee | No (broken call) |
| Refund status with provider refresh | Attendee | No |
| Payment retry / continue payment (`can_retry`, attempt reuse) | Attendee | No |
| Payment status check (provider re-query) | Attendee | No |
| Payment/cancel/refund timeline | Attendee | No |
| TEST/LIVE mode indicator (`payment_mode`, `real_money`) | Attendee | No |
| Server pricing breakdown (GST, convenience fee) | Attendee | No |
| All-status registration audit | event_admin / platform_admin | No |
| Check-in (verify QR token, record, attempts log) | event_admin / platform_admin | No |
| Payment configuration draft → validate → publish | event_admin / platform_admin | No |
| Platform role grant/revoke/list; event payment-admin grant | platform_admin (list: + auditor) | No |
| Order / hold expiry sweeps | platform_admin | No |
| Gateway configuration view | platform_admin / finance / auditor / support | No |

*Not in backend (so not a frontend gap):* admin refund, finance refund approval, refund retry, admin cancellation, registration-status override, reconciliation.

---

## 19. iTelematics References

Search terms: `iTelematics`, `itelematics`, `ITELEMATICS`, `iTelematics Software`, `itelematics.com`, `EV.ENGINEER`, `EV Society`, `Thasmai`, `Sudarshana`, `ananth`, `CAR Software Systems` (case-insensitive), over `NEW:` excluding `build/`, `.dart_tool/`, `.git/`; plus the deployed `main.dart.js`.

| File | Line | Exact string | Visible to end users | Affects functionality | Nature | Recommendation |
|---|---|---|---|---|---|---|
| `ios/Flutter/flutter_export_environment.sh` | 4–5 | `/Users/ananth/iTelematics/NITK_Project/…/frontend` (local path) | No | No | Generated, **git-ignored** (`ios/.gitignore:26`) | KEEP (not committed) |
| `ios/Flutter/Generated.xcconfig` | 3–4 | same local path | No | No | Generated, git-ignored (`ios/.gitignore:21`) | KEEP |
| `ios/Flutter/ephemeral/flutter_native_integration.env` | 2–3 | same local path | No | No | Generated, git-ignored (`ios/.gitignore:22`) | KEEP |
| `lib/features/developer/presentation/developer_diagnostics_screen.dart` | 923 | `hintText: 'e.g. sudarshana'` | Debug builds only (route registered only under `kDebugMode`) | No | Dev placeholder text | REVIEW (replace with neutral example) |
| Deployed `main.dart.js` | — | none found | — | — | — | — |

**No iTelematics, EV.ENGINEER, EV Society, Thasmai or CAR Software Systems strings exist in tracked source or in the deployed bundle.**

---

## 20. Hardcoded Configuration

| Item | Location | Value (masked) | Assessment |
|---|---|---|---|
| Backend URL fallback | `backend_auth_service.dart:33,35`, `events_repository.dart:35,37` | `http://10.0.2.2:8000`, `http://127.0.0.1:8000` | Used only if no `--dart-define`; prod build correct. Duplicated in two Dio factories — REVIEW |
| Firebase options | `lib/firebase_options.dart:44-83` | apiKey `AIzaSyDhDv****`, `AIzaSyBUkg****`, `AIzaSyCXm4****`; project `project-d22bed42-…` | Public client config by design — KEEP |
| Google client id | `web/index.html:22` | `246773894709-44td…apps.googleusercontent.com` | Public — KEEP |
| Android appId mismatch | `firebase.json` | `…android:51f0e5…` (platforms) vs `…android:45059a…` (dart config) | REVIEW (ISSUE-022) |
| Razorpay keys | — | none hardcoded (come from backend) | Good |
| Razorpay SDK | `web/index.html:37,40` | `checkout.razorpay.com/v1/checkout.js` ×2 | Remove duplicate |
| Third-party QR service | `event_detail_screen.dart:2052` | `api.qrserver.com` | Sends registration number to third party — REVIEW (ISSUE-020) |
| Dev header | `events_repository.dart:71,86,103,119,135,257` | `X-Dev-User: admin` | Inert in prod; REMOVE |
| Pass-count defaults | `event_detail_screen.dart:1551-1552` | min 1 / max 4 | Feature not backed by API (ISSUE-006) |
| Placeholder routes | `app_sidebar.dart` | `/volunteer`, `/more` | Unregistered routes (ISSUE-021) |
| Test accounts, event IDs, registration IDs, tokens, secrets | — | none found | Good |
| PII in logs | `firebase_auth_service.dart:12` | logs email on sign-in | `logger` default filter is debug-only; REVIEW (reference deliberately avoids it) |

---

## 21. Security Observations

| # | Observation | Severity | Evidence |
|---|---|---|---|
| SEC-1 | **User A's registration status, badge number, QR, eligibility, name, email and phone shown to User B in the same tab** | **P0 / Critical (privacy)** | ISSUE-001 |
| SEC-2 | Payment amount is server-authoritative; client quantity cannot change what is charged | Good | `payment_service.py create_order`; schema ignores `quantity` |
| SEC-3 | Eligibility enforced server-side on register (not only in UI) | Good | `registration_service.py:84-95` |
| SEC-4 | Refund/cancel callable only by owner; cross-user → 404 | Good | `refund_service.py:88-95`; backend tests `test_cross_user_cancel_denied`, `test_cross_user_refund_status_denied` passed |
| SEC-5 | No admin action is exposed to non-admins in UI; backend enforces RBAC | Good | ISSUE-014 analysis |
| SEC-6 | `X-Dev-User` header ignored in production; dev diagnostics return 404 | Good (runtime) | §25 API-006/007 |
| SEC-7 | Backend JWT not revoked on logout (stateless, 480 min) | P3 | `BE:app/config.py:38`; no logout endpoint |
| SEC-8 | Registration number sent to third-party QR generator | P3 | ISSUE-020 |
| SEC-9 | Attendee note carried in URL query string (browser history, logs) | P3 | ISSUE-019 |
| SEC-10 | Hive stores JWT + PII in IndexedDB unencrypted | P3 (accepted for web) | `auth_session_store.dart` |
| SEC-11 | No secrets in source or bundle | Good | §20 |

---

## 22. Confirmed Issues

---

## ISSUE-001 — Logout → login as another user shows the previous user's event data

**Severity:** P0
**Area:** Authentication / Event detail / Checkout
**Primary Location:** STATE_MANAGEMENT (secondary: NEW_FLUTTER_FRONTEND)
**Root Cause Area:** STATE MANAGEMENT
**Fix Location:** NEW Flutter frontend only
**Status:** Confirmed (code-level, deterministic). Runtime reproduction pending manual login (§26, MAN-1).

### User Symptom
After User A logs out and User B logs in (same tab, no reload), opening an event User A had viewed shows User A's "Registered Successfully / Badge #NITKSAA-…", A's QR badge, A's eligibility verdict, and the registration form prefilled with A's name/email/phone. It also explains "I logged in as someone else but it still looks like the first user."

### Preconditions
User A viewed event X while logged in. No full page reload between A's logout and B's login.

### Steps to Reproduce
1. Log in as User A (alumni, registered for event #7). Open `/events/7`.
2. Log out via the sidebar.
3. Log in as User B (any account). Open `/events/7`.

### Expected
Event #7 shows B's eligibility and registration (or none). Form shows B's profile.

### Actual (from code)
`eventDetailProvider(7)` already exists and is returned as-is; its `fetchEventDetails` is never re-run. A's state is rendered.

### Expected Flow
New identity → every user-scoped provider discarded or re-fetched with the new token.

### Actual Flow
`AuthController` notifies → `myEventsProvider` rebuilds (watches auth) ✅ → `eventDetailProvider` family does **not** rebuild (uses `_ref.read`, not `watch`; not `autoDispose`) ❌.

### NEW Flutter Implementation
- File: `NEW:lib/features/events/presentation/providers/event_detail_provider.dart`
- `eventDetailProvider` (`:132-138`): `StateNotifierProvider.family`, **not** `autoDispose`, triggers `fetchEventDetails` once via `Future.microtask` at creation only.
- `fetchEventDetails` (`:57-103`): reads auth with `_ref.read(authControllerProvider)` (`:64`) — no dependency on identity.
- `EventDetailState.copyWith` (`:27-48`): `myRegistration ?? this.myRegistration`, `alumniProfile ?? this.alumniProfile`, `eligibilityStatus ?? this.eligibilityStatus` — a `null` result (404 "no registration", 403 `alumni_only`, or a failed call) can **never clear** a previous value; errors are swallowed (`:75-93`).
- `EventDetailScreen` has no `initState` re-fetch (`event_detail_screen.dart`, only `ref.watch` at `:58`).
- Logout (`auth_controller.dart:96-106`) clears Hive + Firebase but no provider is invalidated anywhere (`grep invalidate` → 0 hits in `lib/`).
- Checkout reuses this stale state: `checkout_screen.dart:286-289` may try to pay **User A's** `registration_id` with **User B's** token (backend returns 404 — safe, but B is blocked).

### Reference Frontend Implementation
- File: `REF:lib/features/registrations/services/registration_repository.dart:42-53` — `registrationEligibilityProvider` and `myEventRegistrationProvider` are `FutureProvider.autoDispose.family`, re-fetched on every subscribe.
- `REF:lib/core/network/api_client_provider.dart` — token read lazily from auth state at call time.
- Behaviour: no cross-user carry-over.

### Backend Implementation
- `GET /api/v1/events/{id}/registration-eligibility`, `GET /api/v1/events/{id}/my-registration`, `GET /api/v1/alumni/me` — all scoped to the bearer token's `firebase_uid`. Backend is correct.

### Three-layer gap

| Layer | Expected / Reference | NEW Flutter App | Gap |
|---|---|---|---|
| Backend API | Per-token data; 404/403 when B has no registration/profile | — | — |
| Reference app | `autoDispose` providers, token read at call time | — | Working reference |
| NEW Flutter app | — | Long-lived family; `read` not `watch`; `??` merge; no invalidation on logout | STATE_MANAGEMENT GAP |

### Traceability

```text
User B opens /events/7 after A logged out
   ↓
EventDetailScreen.build → ref.watch(eventDetailProvider(7))     event_detail_screen.dart:58
   ↓
Existing provider instance (created during A's session) returned  ✗ DIVERGES HERE
   ↓  (expected: new instance → fetchEventDetails with B's token)
GET /registration-eligibility, /my-registration, /alumni/me (B)
   ↓
Actual: no request; A's cached eligibility/registration/profile rendered
```

### First Point of Failure
Riverpod provider lifecycle in `event_detail_provider.dart:132`.

### Evidence
Code as cited; `grep -rn "invalidate\|autoDispose" lib/` → no matches (outside the dev screen). Runtime capture pending (MAN-1).

### Recommended Fix Direction
Make user-scoped providers depend on identity (watch the session/uid, or `autoDispose`), re-fetch on screen entry, invalidate user-scoped providers on logout/login, and make `copyWith` able to clear fields. Do not reuse cached registration ids in checkout without re-reading them.

---

## ISSUE-002 — Google sign-in cannot switch accounts after logout (web)

**Severity:** P1
**Area:** Authentication
**Primary Location:** FIREBASE_AUTH (secondary: REFERENCE_FRONTEND_DIFFERENCE)
**Root Cause Area:** AUTH/FIREBASE
**Fix Location:** NEW Flutter frontend only
**Status:** Confirmed (code difference vs working reference). Runtime confirmation pending (MAN-1).

### User Symptom
Login → Logout → "Sign in with Google" signs straight back into the first Google account without offering the account chooser, so testers cannot log in as a different user.

### Expected Flow
Popup shows the Google account chooser every time.

### Actual Flow
`signInWithPopup(GoogleAuthProvider())` with no custom parameters; on web, logout intentionally does not end the Google browser session (`firebase_auth_service.dart:64`). Google therefore re-uses the active account (silently when only one Google account is signed in to the browser).

### NEW Flutter Implementation
File: `NEW:lib/features/auth/services/firebase_auth_service.dart` · Function: `signInWithGoogle` (`:26-35`) · Behaviour: no `prompt` parameter.

### Reference Frontend Implementation
File: `REF:lib/core/auth/services/firebase_auth_service.dart` · Function: `signInWithGoogle` (`:28-34`) · Behaviour: `provider.setCustomParameters({'prompt': 'select_account'})` plus `email`/`profile` scopes.

### Backend Implementation
Not involved (`POST /api/v1/auth/firebase` simply trusts the resulting Firebase token).

| Layer | Expected / Reference | NEW Flutter App | Gap |
|---|---|---|---|
| Firebase/Google | Account chooser needs `prompt=select_account` after logout | — | — |
| Reference app | Sets it (`firebase_auth_service.dart:32`) | — | Working reference |
| NEW Flutter app | — | Not set | AUTH GAP |

### First Point of Failure
`firebase_auth_service.dart:31-33`.

### Evidence
Code diff; deployed bundle contains 0 occurrences of `select_account`.

### Recommended Fix Direction
Force the account chooser for the Google provider on web (as the reference does). Optionally show the signed-in email after login so testers can see which account is active.

---

## ISSUE-003 — Backend login rejections are shown as a generic error

**Severity:** P2 · **Area:** Authentication · **Primary Location:** NEW_FLUTTER_FRONTEND (secondary: BACKEND_BUSINESS_LOGIC — rule is intentional) · **Root Cause Area:** FRONTEND · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed (code)

### User Symptom
"Sign in failed. Please try again." for every backend refusal. Since 2026-10-01 (`dadeba0 fix(auth): reject unverified Firebase emails`) the backend returns `403 email_not_verified` for email/password Firebase accounts whose email is unverified — typical for test accounts created in the Firebase console. A second **email/password** test user can therefore be unable to log in, which presents as part of the "can't log in as another user" report.

### Expected Flow
Show the backend reason (unverified email, suspended account, network error) and sign out of Firebase when the backend exchange fails.

### Actual Flow
`_runLoginFlow` catches everything, clears Hive, sets `unauthenticated`, but leaves the Firebase user signed in; `_friendlyAuthError` maps every non-Firebase error to one string.

### NEW Flutter Implementation
`NEW:lib/features/auth/services/auth_controller.dart` · `_runLoginFlow` (`:108-134`), `_friendlyAuthError` (`:177-192`); `login_screen.dart:78-81`.

### Reference Frontend Implementation
`REF:lib/core/auth/auth_controller.dart:99-120` — same generic mapping (reference has the same weakness; not a regression), but `REF:lib/core/errors/friendly_error_message.dart` maps backend codes elsewhere.

### Backend Implementation
`POST /api/v1/auth/firebase` → 403 `email_not_verified` (`BE:app/api/auth.py:50-51`), 403 `account_suspended` (`:79-80`), 400 `email_missing`.

### Exact Gap / First Point of Failure
`auth_controller.dart:191` discards `DioException.response.data.detail`.

### Evidence
Code. Runtime: requires an unverified email/password account (MAN-1b).

### Recommended Fix Direction
Map backend `detail` codes to messages; sign out of Firebase when the backend exchange fails; for unverified email, offer "resend verification".

---

## ISSUE-004 — Cancellation calls a nonexistent endpoint (HTTP 405)

**Severity:** P1
**Area:** Cancellation
**Primary Location:** API_CONTRACT_MISMATCH
**Root Cause Area:** API CONTRACT (FRONTEND)
**Fix Location:** NEW Flutter frontend only
**Status:** **Confirmed (runtime against production)**

### User Symptom
"Unregister" in My Events always fails with "Could not unregister."

### Expected Flow
`POST /api/v1/registrations/{registration_id}/cancel` with `{"idempotency_key": "<8–128 chars>"}` → `RefundStatusResponse`; reload registration, refund status and My Events.

### Actual Flow
`DELETE /api/v1/events/{event_id}/my-registration` (wrong method, wrong path, wrong identifier, no idempotency key) → `405 {"detail":"Method Not Allowed"}`.

### NEW Flutter Implementation
- File: `NEW:lib/features/events/data/events_repository.dart` · Function: `cancelMyRegistration` (`:194-203`)
- Caller: `NEW:lib/features/events/presentation/providers/my_events_provider.dart` · `cancelRegistration(int eventId)` (`:66-80`)
- UI: `NEW:lib/features/events/presentation/screens/my_events_screen.dart:197, 222-255`
- Response is parsed as a registration (`MyEventRegistration.fromJson`), not as a refund status.

### Reference Frontend Implementation
- File: `REF:lib/features/refunds/services/refund_repository.dart` · `cancelRegistration(int registrationId)` (`:20-28`) → `POST /api/v1/registrations/$registrationId/cancel` with `idempotency_key`.
- UI: `REF:lib/features/attendee_demo/presentation/payment_status_screen.dart` · `_cancelRegistration` (`:258-298`) — confirm dialog showing refund amount, double-tap guard, invalidates My Registrations / my-registration / order / refund providers.

### Backend Implementation
- Route: `BE:app/api/refunds.py:18-31` `POST /api/v1/registrations/{registration_id}/cancel`
- Service: `BE:app/services/refund_service.py:105 cancel_registration`
- Request: `CancelRegistrationRequest {idempotency_key: str(8..128)}` (`BE:app/schemas/payments.py:145`)
- Response: `RefundStatusResponse {refund_id, registration_id, status: refund_pending|refund_processed|refund_failed|none, amount, currency, requested_at, finalized_at, safe_message, payment_mode, real_money}`

### Three-layer gap

| Layer | Expected / Reference | NEW Flutter App | Gap |
|---|---|---|---|
| Backend API | `POST /registrations/{registration_id}/cancel` + `idempotency_key` | — | — |
| Reference app | `refund_repository.dart:20` | — | Working reference |
| NEW Flutter app | — | `DELETE /events/{event_id}/my-registration` (`events_repository.dart:198`) | API CONTRACT GAP (method, path, id type, body, response model) |

### Traceability
See §14 (identical chain). Diverges at `events_repository.dart:198`.

### First Point of Failure
HTTP routing: the backend has no DELETE handler for that path.

### Evidence
```text
DELETE https://nitksaa-events-api-…run.app/api/v1/events/7/my-registration
HTTP 405
{"detail":"Method Not Allowed"}
```
Live OpenAPI lists only `GET /api/v1/events/{event_id}/my-registration`.

### Recommended Fix Direction
Cancel by `registration_id` via the POST endpoint with a stable idempotency key per user action; treat the response as a refund status; refresh My Events, event detail and refund status afterwards.

---

## ISSUE-005 — Refund flow is not integrated

**Severity:** P1
**Area:** Refund
**Primary Location:** NEW_FLUTTER_FRONTEND (secondary: API_CONTRACT_MISMATCH via ISSUE-004)
**Root Cause Area:** FRONTEND
**Fix Location:** NEW Flutter frontend only
**Status:** Confirmed (code + deployed bundle contains no `/cancel` or `/refund` path)

### User Symptom
Paid attendees cannot get a refund; there is no refund status anywhere.

### Expected Flow
Paid `registered` registration → Cancel → backend cancels + creates full refund + calls Razorpay → app shows `refund_pending`/`refund_processed`/`refund_failed` with amount → "Check refund status" polls `GET /registrations/{id}/refund` until terminal. Cancelled paid registrations keep a "View refund status" entry (via `latest_order_id`).

### Actual Flow
The only cancel call is the 405 in ISSUE-004. No refund model, endpoint, or UI exists.

### NEW Flutter Implementation
None. `grep -rn "refund" lib/` → no matches outside comments.

### Reference Frontend Implementation
`REF:lib/features/refunds/services/refund_repository.dart:20-46` (`cancelRegistration`, `getRefundStatus`, `refundStatusProvider` autoDispose); `REF:lib/features/refunds/domain/refund_status.dart` (status values, `isTerminal`, `payment_mode`, `real_money`); `REF:…/payment_status_screen.dart:437-533` `_RefundSection`; `REF:…/my_registrations_screen.dart:142-154` "View Refund Status".

### Backend Implementation
Routes `BE:app/api/refunds.py`; service `BE:app/services/refund_service.py:105-315`. Backend tests: **21/21 passed** locally (§25 BE-001), including `test_full_refund_of_captured_payment`, `test_refund_amount_equals_captured_amount`, `test_duplicate_cancel_same_key_is_idempotent`, `test_concurrent_cancel_only_one_logical_refund`, `test_provider_refund_failure_leaves_safe_state`, `test_cross_mode_refund_is_structurally_rejected`.

### Exact Gap
Frontend never calls cancel (correctly) nor refund status; never parses `latest_order_id`; never shows refund state.

### First Point of Failure
`events_repository.dart:194` (wrong cancel), then absence of any refund-status integration.

### Evidence
Deployed bundle string scan: `/cancel` 0, `/refund` 0, `payment_mode` 0.

### Recommended Fix Direction
Port the reference refund repository/model/section; fix cancel per ISSUE-004; add "View refund status" for cancelled paid registrations.

---

## ISSUE-006 — Multi-pass quantity is shown and charged inconsistently (frontend-only feature)

**Severity:** P0
**Area:** Registration / Pricing / Payment
**Primary Location:** API_CONTRACT_MISMATCH (secondary: NEW_FLUTTER_FRONTEND)
**Root Cause Area:** API CONTRACT
**Fix Location:** Both frontend and backend — product decision required (either remove quantity from the NEW app, or implement quantity end-to-end in the backend)
**Status:** Confirmed (code + live OpenAPI/schema). Razorpay modal amount for qty>1 pending manual (MAN-3).

### User Symptom
Selecting 2–4 passes shows "Grand Total ₹(price×N)" and "Confirm & Pay ₹(price×N)", but only one registration exists afterwards and Razorpay charges for one pass.

### Expected Flow
Either: (a) no quantity selector (current backend contract: one registration = one person = one price), or (b) quantity persisted, priced, capacity-checked and charged by the backend.

### Actual Flow
See §11 trace. `quantity` is sent but dropped; the backend has no quantity in `RegisterRequest`, events, pricing, orders, capacity or migrations (`grep -rn quantity BE:app BE:migrations` → none).

### NEW Flutter Implementation
- `NEW:lib/features/events/presentation/screens/event_detail_screen.dart` · `_passOptions` (`:1550-1556`, default 1..4 because `registration_min/max_quantity` never arrive), `_buildPassesDropdown` (`:1559`), `_proceedToCheckout` (`:1683-1688`)
- `NEW:lib/features/events/presentation/screens/checkout_screen.dart` · `_buildFeeSummarySection` (`:150-241`, `grandTotal = unitPrice * widget.quantity`), `_buildSubmitButton` label (`:249`)
- `NEW:lib/features/events/data/events_repository.dart` · `registerForEvent` (`:205-220`, `'quantity': ?quantity`)
- Admin side also sends `registration_min_quantity`/`registration_max_quantity` that are dropped (`manage_events_screen.dart:2817-2818`).

### Reference Frontend Implementation
No quantity; `REF:lib/features/registrations/services/registration_repository.dart:11-17` sends only `attendee_note`; amount shown is `pricing.finalAmount` (`REF:…/payment_review_screen.dart:186`).

### Backend Implementation
`RegisterRequest {attendee_note}` (`BE:app/schemas/registrations.py:9-17`); `create_order` prices from config only (`BE:app/services/payment_service.py:198-279`); `calculate_price(config)` has no quantity input (`BE:app/services/pricing_service.py:23`).

### Three-layer gap

| Layer | Expected / Reference | NEW Flutter App | Gap |
|---|---|---|---|
| Backend API | One registration, one server price; no quantity | — | Feature absent |
| Reference app | No quantity; server price | — | Consistent with backend |
| NEW Flutter app | — | Quantity 1–4, price × N displayed, `quantity` sent | API CONTRACT GAP |

### First Point of Failure
`event_detail_screen.dart:1365/1426` (offering a quantity the API cannot accept) → first value divergence at `checkout_screen.dart:152`.

### Evidence
Live `GET /api/v1/events/public/7` keys: no `registration_min_quantity`/`registration_max_quantity`; live OpenAPI has no quantity field; deployed bundle contains `quantity` (10×).

### Recommended Fix Direction
Decide product scope. Until the backend supports quantity, remove the selector and show the server `final_amount`. If multi-pass is required, design it in the backend first (persisted quantity or per-guest records, capacity accounting, pricing × quantity, refund rules), then bind the UI to server-computed totals.

---

## ISSUE-007 — Fee summary ignores server pricing (GST / convenience fee)

**Severity:** P1 · **Area:** Pricing · **Primary Location:** NEW_FLUTTER_FRONTEND · **Fix Location:** NEW Flutter frontend only · **Status:** Suspected (code confirmed; mismatch occurs only when the event's published config has GST or a convenience fee)

### User Symptom
Amount on the app's checkout can be lower than the Razorpay modal amount.

### Expected / Actual Flow
Expected: `GET /events/{id}/payment-pricing` → show `line_items` + `final_amount`. Actual: uses public `ticket_price` (= config `base_amount`) × quantity (`checkout_screen.dart:151`).

### NEW Flutter Implementation
`checkout_screen.dart:150-152, 249`; no pricing call.

### Reference Frontend Implementation
`REF:lib/features/pricing/services/pricing_repository.dart:11`, `REF:…/payment_review_screen.dart:70,186`.

### Backend Implementation
`GET /api/v1/events/{id}/payment-pricing` → `PricingBreakdownResponse` (`BE:app/services/payment_service.py:128`). Charge = `final_amount` (`pricing_service.py:23-88`).

### Exact Gap / First Point of Failure
`checkout_screen.dart:151`.

### Evidence
Code. Needs authenticated pricing call per open event (MAN-3).

### Recommended Fix Direction
Display only server-computed pricing; show the order's `final_amount` before opening Razorpay.

---

## ISSUE-008 — Returning attendee cannot resume/retry payment; unpaid hold shown as "registered"

**Severity:** P1
**Area:** Payment retry / Event detail / My Events
**Primary Location:** NEW_FLUTTER_FRONTEND
**Fix Location:** NEW Flutter frontend only
**Status:** Confirmed (code)

### User Symptom
User closes Razorpay (or payment fails), returns later: event page says "You are registered for this event." with a "View QR badge" button, and no Pay button. My Events labels the registration "Unregistered" with no action. The seat hold then expires silently.

### Expected Flow
Status `seat_held`/`payment_pending` → "Payment pending — Continue Payment"; `payment_failed` → "Try Again"; `payment_verification` → "Check Payment Status" (via `latest_order_id`); hold expiry visible.

### Actual Flow
Backend eligibility returns `already_registered` for any in-flight status (`registration_service.py` `get_active_or_held_for_user`). The NEW CTA logic treats only `status == 'registered'` as registered and otherwise falls through to `eligibilityStatus == 'already_registered'` → "You are registered for this event." + QR (`event_detail_screen.dart:1080-1173`). `MyEventRegistration.isActive` is `status == 'registered'` and the tag shows "Unregistered" for everything else (`my_event_registration.dart:28`, `my_events_screen.dart:314`). `latest_order_id` is not parsed.

### NEW Flutter Implementation
`event_detail_screen.dart:1080-1173`; `my_event_registration.dart:28-30, 47-63`; reuse logic `checkout_screen.dart:270-289` exists but is unreachable from the UI (only by typing `/events/{id}/checkout` manually).

### Reference Frontend Implementation
`REF:…/my_registrations_screen.dart:101-155` `_presentationFor` — per-status label + action; `REF:…/razorpay_checkout_screen.dart:65-107` re-enters checkout for the same order; backend attempt reuse honoured.

### Backend Implementation
`POST /registrations/{id}/payment-order` create-or-reuse (`payment_service.py:198`), `can_retry` in `PaymentOrderResponse`, attempt reuse `payment_service.py:479`, `latest_order_id` in `RegistrationResponse`.

### Three-layer gap

| Layer | Expected / Reference | NEW Flutter App | Gap |
|---|---|---|---|
| Backend API | `latest_order_id`, `can_retry`, attempt reuse | — | — |
| Reference app | Continue Payment / Try Again / Check Status | — | Working reference |
| NEW Flutter app | — | "You are registered" + QR; "Unregistered" tag; no action | FRONTEND GAP |

### First Point of Failure
`event_detail_screen.dart:1153` (status mapping).

### Evidence
Code.

### Recommended Fix Direction
Map every backend registration status explicitly; add continue/retry/check-status actions keyed on `latest_order_id`; never show a QR badge for a non-`registered` status.

---

## ISSUE-009 — Razorpay in-modal retry can lose a successful payment confirmation

**Severity:** P1 · **Area:** Razorpay checkout (web) · **Primary Location:** RAZORPAY_INTEGRATION · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed (code diff vs reference); runtime repro pending (MAN-4)

### User Symptom
Card declined first, attendee retries inside the same Razorpay modal and succeeds — the app already said "Payment could not be completed", never verifies, and the registration stays unconfirmed until the webhook (if configured) arrives.

### Expected Flow
Either disable in-modal retry (reference) or keep listening for the success handler after a failure.

### Actual Flow
`payment.failed` completes the Dart `Completer` with an error (`razorpay_payment_web.dart:97-127`); Razorpay's default keeps the modal open for retry; the later `handler` call hits `if (completer.isCompleted) return;` (`:62`) and is dropped; `verify-checkout` is never called.

### NEW Flutter Implementation
`NEW:lib/features/events/presentation/services/razorpay_payment_web.dart` — no `retry` option.

### Reference Frontend Implementation
`REF:lib/features/payment_attempts/services/razorpay_checkout_web.dart:71` — `retry: {enabled: false}`.

### Backend Implementation
Webhook `POST /api/v1/payments/webhook` would still capture the payment; `POST /payment-attempts/{id}/verify` can recover it — but the NEW app calls neither.

### First Point of Failure
`razorpay_payment_web.dart` option construction (`:27-57`).

### Recommended Fix Direction
Disable in-modal retry (as the reference does) and route every non-success outcome to a status check against the backend.

---

## ISSUE-010 — No payment status handling after checkout

**Severity:** P2 · **Area:** Payment status · **Primary Location:** NEW_FLUTTER_FRONTEND · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed (code)

**User Symptom:** After a pending verification or a 502 from verify-checkout, the user only sees a snackbar; there is nowhere to check status later.
**Expected Flow:** Land on a status view that re-reads `GET /payment-orders/{id}`, auto-refreshes while pending, offers "Check payment status" (`POST /payment-attempts/{id}/verify`), shows timeline.
**Actual Flow:** `checkout_screen.dart:350-370` shows `safe_message` in a snackbar; no stored order/attempt id.
**NEW Flutter Implementation:** `checkout_screen.dart:276-382`.
**Reference Frontend Implementation:** `REF:…/payment_status_screen.dart:117-330` (auto-refresh `:148-215`, `_checkStatus :226-256`).
**Backend Implementation:** `GET /payment-orders/{id}` (`payment_service.py:301`), `POST /payment-attempts/{id}/verify` (`:1144`), timeline (`:1081`).
**Exact Gap / First Point of Failure:** No integration after `verify-checkout`.
**Evidence:** Code; bundle has 0 `/timeline`.
**Recommended Fix Direction:** Add a payment status view driven by backend order state.

---

## ISSUE-011 — Duplicate event cards in My Events; wrong status labels

**Severity:** P2
**Area:** My Events
**Primary Location:** NEW_FLUTTER_FRONTEND
**Fix Location:** NEW Flutter frontend only
**Status:** Confirmed (code). Runtime IDs pending (MAN-5).

### User Symptom
The same event appears twice (one "Unregistered", one "Registered") after a cancellation or an abandoned payment.

### Root cause
**Backend does not return duplicate records.** `GET /api/v1/my/registrations` returns one row per `registration_id`, all statuses, newest first (`BE:app/repositories/registration_repository.py:307 list_for_user`), by design (history). Each cancellation, expired seat hold, or failed paid attempt followed by re-registration creates a **new `registration_id` for the same `event_id`**. The NEW app maps rows 1:1 to cards with no grouping by `event_id` and no status filtering (`my_events_screen.dart:184-200`). The list key is the index (no stable key).

Because the NEW app cannot cancel (ISSUE-004), duplicates in practice come from **expired paid seat holds** (abandon Razorpay → hold expires → lazily set `cancelled` → register again) or cancellations made through another client (e.g., the reference app) against the same backend.

### Expected illustration (to be confirmed with real IDs in MAN-5)
```text
Backend response:  registration_id=R2 event_id=7 status=registered
                   registration_id=R1 event_id=7 status=cancelled
Flutter state:     2 cards for event_id=7
Conclusion:        NEW Flutter list/presentation bug (backend returns history by design)
```

### NEW Flutter Implementation
`events_repository.dart:171-192` (also N+1 `GET /events/public/{id}` per row, including duplicates), `my_events_provider.dart:42-64`, `my_events_screen.dart:184-200, 314-320`.

### Reference Frontend Implementation
`REF:…/my_registrations_screen.dart` — also one card per registration, but each card states its status ("Cancelled", "Payment Pending", "Confirmed — Paid") with a relevant action, so history is intelligible.

### Backend Implementation
`GET /api/v1/my/registrations` (`registration_service.py:267`).

### Recommended Fix Direction
Group by `event_id` (show the latest registration as the event's state, older ones as history) or label each row by real status; use stable keys; avoid per-row public-event fetches.

---

## ISSUE-012 — Cancel availability depends on a frontend-only rule

**Severity:** P2 · **Area:** Cancellation · **Primary Location:** NEW_FLUTTER_FRONTEND · **Fix Location:** NEW Flutter frontend only (or backend, if a cancellation cut-off is a real policy) · **Status:** Confirmed (code)

**User Symptom:** Once registration closes (often well before the event), the Unregister button disappears.
**Expected Flow:** Backend allows cancelling any `registered` registration; no cut-off exists in the backend.
**Actual Flow:** `canCancel => isActive && publicEvent?.registrationStatus == 'open'` (`my_event_registration.dart:29-30`).
**Reference:** No such rule; cancel offered on any successful (registered + paid) order (`payment_status_screen.dart:394-405`).
**Backend:** `refund_service.py:121-127` only requires `status == 'registered'`.
**Recommended Fix Direction:** Agree a cancellation policy; if it exists, enforce it in the backend and expose it to clients rather than inventing it in the UI.

---

## ISSUE-013 — "Only alumni can register" for users who consider themselves alumni

**Severity:** P1
**Area:** Alumni eligibility
**Primary Location:** DATA (secondary: BACKEND_BUSINESS_LOGIC, STATE_MANAGEMENT)
**Fix Location:** Data correction + backend logging/observability + NEW Flutter frontend (messaging and stale state)
**Status:** Rule confirmed from code; the cause for any specific user requires their login email and alumni record (MAN-2).

### User Symptom
"Only alumni can register for events." (backend wording; reported as "Only Alumni can register for this event").

### Expected Flow
Verified alumni are eligible.

### Actual Flow / Causes (in likelihood order)
1. **Email mismatch (DATA):** the Google/Firebase email differs from `alumni_db.alumni.email` → `user_type='other'` at login (`BE:app/api/auth.py:53-69`, `alumni_service.py:15-31`).
2. **Alumni lookup error at first login (BACKEND):** exception swallowed, user stored as `other` (`auth.py:54-59`), only visible in server logs.
3. **No re-evaluation (FRONTEND/BACKEND):** alumni match runs only at `POST /auth/firebase`. The NEW app restores sessions with `GET /auth/me` only (`auth_controller.dart:58-79`), so a user fixed in the alumni DB stays ineligible until explicit logout/login.
4. **Stale verdict (STATE):** previous user's `ineligible` verdict displayed (ISSUE-001); verdict fetched once per app session per event.
5. Prior event registrations **do not** grant alumni status (by design).

### NEW Flutter Implementation
Displays backend verdict (`event_detail_screen.dart:1220-1235`) — **does not duplicate eligibility logic** (correct). Stale caching per ISSUE-001.

### Reference Frontend Implementation
Displays backend verdict via autoDispose `registrationEligibilityProvider` (`REF:…/registration_repository.dart:42-45`); friendly text for `alumni_only` (`friendly_error_message.dart:10-11`).

### Backend Implementation
`GET /events/{id}/registration-eligibility` (`registration_service.py:275`); enforced again in `register_for_event` (`:84-95`).

### Three-layer gap

| Layer | Expected / Reference | NEW Flutter App | Gap |
|---|---|---|---|
| Backend | Email match at login; Active/Self-Verified at registration | — | Single-email match; silent failure path |
| Reference app | Shows verdict; re-fetches | — | — |
| NEW Flutter app | — | Shows verdict; caches across users | STATE GAP |

### Recommended Fix Direction
Correct alumni emails (data); log/alert on alumni lookup failures; consider re-evaluating alumni status on session restore; show the signed-in email with guidance in the ineligible message; fix ISSUE-001.

---

## ISSUE-014 — Admin features are unreachable (role model mismatch)

**Severity:** P1
**Area:** Admin / RBAC
**Primary Location:** RBAC (secondary: API_CONTRACT_MISMATCH)
**Fix Location:** Both frontend and backend
**Status:** Confirmed (code)

### User Symptom
No admin (Manage Events, Registrations) menu for any real admin.

### Expected Flow
Client learns the caller's roles (`platform_admin`, `event_admin` for event X, finance/auditor/support) from the backend and shows matching UI; backend enforces.

### Actual Flow
UI gated on `session.userType == 'admin'` (`app_sidebar.dart:103-117`, `app_bottom_nav.dart:28`, `manage_events_screen.dart:35-37, 301-303`, `event_registrations_screen.dart:302-304`, `event_list_screen.dart:484,1397`, `event_detail_screen.dart:60`). Backend issues only `alumni`/`other` (`auth.py:61-69`). No endpoint returns roles.

### Reference Implementation
`ADMIN-REF:` relies on backend 403s per call (no client role model). `REF:` has no admin.

### Backend Implementation
`BE:app/middleware/admin_auth.py` (`require_platform_role`, `require_event_admin`, `require_event_payment_read_access`). No `/me/roles`.

### First Point of Failure
`app_sidebar.dart:104`.

### Recommended Fix Direction
Backend: expose the caller's platform roles and administered event ids (e.g., on `/auth/me` or a dedicated endpoint). Frontend: derive admin UI from those roles, refresh on login/logout, and handle 403 gracefully.

---

## ISSUE-015 — Admin API contract mismatches

**Severity:** P2 · **Area:** Admin · **Primary Location:** API_CONTRACT_MISMATCH · **Fix Location:** NEW Flutter frontend (backend only if the dropped features are wanted) · **Status:** Confirmed (runtime 405 for delete; schema for dropped fields)

| Sub-issue | NEW code | Backend reality | Effect |
|---|---|---|---|
| Delete event | `events_repository.dart:127-138` `DELETE /api/v1/events/{id}` | No route → **405** (runtime) | Delete always fails |
| Create/edit payload fields `registration_min_quantity`, `registration_max_quantity`, `fees`, `sponsors`, `speakers`, `sessions` | `manage_events_screen.dart:2801-2849` | Not in `EventCreate`/`EventUpdate` (`BE:app/schemas/event_create.py`); Pydantic ignores extras | Admin input silently lost (enrichment needs `/events/{id}/people|sponsors|partners`, sessions need `/admin/events/{id}/sessions`) |
| Paid event setup | `is_free=false`, `ticket_price` only | Payment requires a **published payment configuration** (`registration_service.py:120-125`) | Attendees get `409 payment_not_configured` |
| List events | `GET /api/v1/events?period=` (platform_admin only) | `period` not a parameter | event_admin cannot use Registrations screen (`event_registrations_screen.dart:85`) |
| Registrations view | `/admin/events/{id}/attendees` (registered only) | `/admin/events/{id}/registrations` gives all statuses | Cancelled/in-flight invisible to admin |
| `X-Dev-User: admin` header | `events_repository.dart:71,86,103,119,135,257` | Ignored in production | Dev assumption in prod code |

**Reference:** `ADMIN-REF:src/api/eventsApi.js`, `attendeesApi.js`, `enrichmentApi.js` use the correct endpoints and no delete.
**Recommended Fix Direction:** Align with the backend contract and the React admin; remove unsupported fields or add backend support; integrate payment-configuration endpoints for paid events.

---

## ISSUE-016 — Mobile builds fail: `razorpay_flutter` not declared

**Severity:** P1 (P2 if mobile is out of scope) · **Area:** Build · **Primary Location:** DEPLOYMENT_CONFIG · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed (`flutter analyze --no-pub`)

**Evidence:**
```text
error • Target of URI doesn't exist: 'package:razorpay_flutter/razorpay_flutter.dart'
        • lib/features/events/presentation/services/razorpay_payment_io.dart:10:8
… 5 further errors in the same file (Razorpay, PaymentSuccessResponse, PaymentFailureResponse undefined)
98 issues found (6 errors, 36 warnings, rest info)
```
`razorpay_flutter` is in neither `pubspec.yaml` nor `pubspec.lock`. The conditional import selects `razorpay_payment_io.dart` on every `dart.library.io` platform (Android, iOS, macOS, Windows, Linux), so those builds cannot compile. Web is unaffected.
**Reference:** `REF:pubspec.yaml:27` declares `razorpay_flutter: ^1.4.6`.
**Recommended Fix Direction:** Declare the dependency (and native setup) or stub mobile until supported.

---

## ISSUE-017 — No TEST/LIVE payment-mode handling

**Severity:** P2 (P1 before LIVE go-live) · **Area:** Payment mode · **Primary Location:** NEW_FLUTTER_FRONTEND · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed (code)

**Expected (reference):** TEST/LIVE banner from order `payment_mode`/`gateway`; LIVE confirmation dialog with amount; block `rzp_live_` key on a test order and vice-versa (`REF:…/razorpay_checkout_screen.dart:109-160`, `core/widgets/payment_mode_banner.dart`).
**Actual:** none; `payment_mode`/`real_money` never read (bundle: 0 occurrences).
**Backend:** `payment_mode`, `real_money`, `gateway` on order, attempt and refund responses (`BE:app/schemas/payments.py`).
**Recommended Fix Direction:** Port the reference banner, LIVE confirmation and key/mode guard.

---

## ISSUE-018 — Raw technical errors shown to attendees

**Severity:** P2 · **Area:** Registration / Payment / Cancellation · **Primary Location:** NEW_FLUTTER_FRONTEND · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed (code)

`EventDetailNotifier.register` stores `e.toString()` (`event_detail_provider.dart:122-126`), producing "Registration failed: DioException [bad response]: …" instead of e.g. "You are already registered" / "Event full" / "Payment not configured". Checkout shows raw `detail` codes (`checkout_screen.dart:389-401`, e.g. `payment_attempt_active`). Reference: `REF:lib/core/errors/friendly_error_message.dart` maps ~40 backend codes.
**Recommended Fix Direction:** Central error mapping from backend `detail` codes.

---

## ISSUE-019 — Registration form inputs silently discarded / notes in URL

**Severity:** P2 · **Area:** Registration form (Issue 3) · **Primary Location:** API_CONTRACT_MISMATCH · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed (code)

| Field | Frontend | Backend | Defect |
|---|---|---|---|
| Email, Phone | Editable (`event_detail_screen.dart:1366-1367, 1427-1428`) | Snapshotted from alumni DB; not accepted in request | Edits discarded with no notice |
| Notes | Sent as URL query `?notes=` (`:1684-1686`), read back in router (`app_router.dart:71`) | `attendee_note` ≤500 | No length check → 422 shown raw; note in browser history |
| Passes | see ISSUE-006 | — | — |

**Reference:** No editable profile fields; only optional `attendee_note` in the body.
**Recommended Fix Direction:** Show profile fields read-only (explain where to update them) and pass notes in app state, validated to 500 chars.

---

## ISSUE-020 — QR badge is not check-in compatible and uses a third-party service

**Severity:** P2 · **Area:** Badge / Check-in · **Primary Location:** API_CONTRACT_MISMATCH · **Fix Location:** Both · **Status:** Confirmed (code)

The badge QR encodes `registration_number` (or `"Event-<id>"` when none) via `https://api.qrserver.com/…` (`event_detail_screen.dart:2052`). The backend check-in looks up `registrations.qrtoken` (`BE:app/repositories/registration_repository.py get_by_qrtoken`, used by `/admin/events/{id}/check-ins/verify`), and **no attendee API returns `qrtoken`**. The badge is also offered for unpaid holds (ISSUE-008).
**Recommended Fix Direction:** Backend exposes the attendee's own check-in token for `registered` rows; Flutter renders the QR locally.

---

## ISSUE-021 — Routing and navigation gaps

**Severity:** P3 · **Primary Location:** NEW_FLUTTER_FRONTEND · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed (code)

- Route guard protects only paths starting with `/events/` (`route_guards.dart:17`); `/my-events`, `/manage-events`, `/admin/events/:id/registrations` render their own "please log in"/"not admin" states instead of redirecting.
- Sidebar links `/volunteer` and `/more` are not registered routes (`app_sidebar.dart` menu items) → go_router error page.
- Logout from the event list does not navigate (`event_list_screen.dart:49-61`); from the sidebar it does.

---

## ISSUE-022 — Web shell and hosting hygiene

**Severity:** P3 · **Primary Location:** DEPLOYMENT_CONFIG · **Fix Location:** NEW Flutter frontend + hosting config · **Status:** Confirmed

- `checkout.js` included twice (`web/index.html:37` and `:40`).
- Browser title `event_app`, meta description "A new Flutter project." (`web/index.html:21,33`), manifest name `event_app`.
- `main.dart.js` (not content-hashed) and `index.html` served with `cache-control: max-age=3600` → users can run the previous build for up to an hour after a redeploy.
- `firebase.json` Android appId differs between `platforms.android` and `dart` config.
- Sidebar shows raw `user_type` (`other`/`alumni`) as the user's role label (`app_sidebar.dart:333`).

---

## ISSUE-023 — Test coverage and code health

**Severity:** P3 · **Primary Location:** NEW_FLUTTER_FRONTEND · **Fix Location:** NEW Flutter frontend only · **Status:** Confirmed

- `flutter test`: 1 test (foundation screen smoke test) — passes; zero coverage of auth, registration, payment, cancellation.
- `flutter analyze`: 36 warnings (19 `invalid_null_aware_operator`, 10 `unused_element` incl. dead `_submitRegistration` in `event_detail_screen.dart:1691`, 5 unused imports, 2 unused locals).
- No shared API client; base-URL logic duplicated in two classes.

---

## 23. Suspected Issues

| ID | Description | Layer | Why suspected / what would confirm it |
|---|---|---|---|
| S-1 | Public list shows "open" while eligibility says "full" for paid events (public count = `registered` only; eligibility counts held seats) | BACKEND | Compare `/events/public` vs eligibility on a paid event with active holds |
| S-2 | Alumni lookup failure at first login silently stores `user_type='other'` | BACKEND | Cloud Run logs for "Alumni lookup failed" |
| S-3 | Refund `failed` has no operational retry path (no admin/finance refund API) | BACKEND | By inspection; needs a provider-failure case in prod |
| S-4 | Expired seat holds stay `seat_held` until someone triggers lazy expiry (no scheduler); NEW app shows them as "You are registered" | BACKEND + FRONTEND | Abandon a paid checkout, wait > hold minutes, reload |
| S-5 | Checkout for User B may target User A's `registration_id` (ISSUE-001) → 404 `registration_not_found` | FRONTEND | MAN-1 |
| S-6 | Razorpay webhook configured for production? If not, ISSUE-009 losses are never auto-recovered | CONFIG | Razorpay dashboard webhook settings |

---

## 24. Test Cases Passed

| Test ID | Test | Method | Result |
|---|---|---|---|
| DEP-001 | Deployed bundle equals local build of current source | SHA-256 compare | PASS |
| DEP-002 | Deployed bundle uses production backend URL | Bundle string scan | PASS |
| DEP-003 | CORS allows `https://nitksaa-events.web.app` | Preflight | PASS |
| API-001 | Production health | `GET /api/v1/health` | PASS (`env=production`, `db=ok`) |
| API-002 | Public event list | `GET /events/public?period=upcoming|all` | PASS (8 events) |
| API-003 | Public event detail schema | `GET /events/public/7` | PASS (no quantity fields — confirms ISSUE-006) |
| API-006 | Dev diagnostics disabled in prod | `GET /api/v1/dev/diagnostics/events` | PASS (404) |
| API-007 | `X-Dev-User` not honoured in prod | `GET /auth/me` with header only | PASS (403) |
| API-008 | Protected endpoints require auth | my-registration, cancel, refund, `/events`, `/admin/events` | PASS (403) |
| API-009 | Invalid bearer rejected | `GET /auth/me` | PASS (401 `invalid_or_expired_token`) |
| BE-001 | Backend refund/cancel suite | `pytest tests/test_payment_refunds.py` on local dev DB | PASS (21/21) |
| UT-001 | Existing Flutter tests | `flutter test --no-pub` | PASS (1/1) |
| SEC-11 | No secrets in source/bundle | grep | PASS |
| ITM-001 | No iTelematics strings in tracked source / bundle | grep | PASS |

## 25. Test Cases Failed

| Test ID | Test | Result | Issue |
|---|---|---|---|
| API-004 | Cancellation endpoint used by NEW app exists | **FAIL** — 405 | ISSUE-004 |
| API-005 | Admin delete endpoint used by NEW app exists | **FAIL** — 405 | ISSUE-015 |
| BUILD-001 | Static analysis clean of errors | **FAIL** — 6 errors | ISSUE-016 |
| BUNDLE-001 | Deployed app contains refund/cancel/pricing/payment-mode integration | **FAIL** — 0 occurrences | ISSUE-005, -007, -017 |
| CODE-AUTH-003 | User-scoped state reset on user switch | **FAIL** (code) | ISSUE-001 |
| CODE-AUTH-004 | Google account chooser forced | **FAIL** (code) | ISSUE-002 |
| CODE-REG-002 | Quantity honoured end-to-end | **FAIL** (code + schema) | ISSUE-006 |
| CODE-PAY-005 | Retry reachable for held/failed registrations | **FAIL** (code) | ISSUE-008 |
| CODE-ADM-001 | Admin UI reachable for real admins | **FAIL** (code) | ISSUE-014 |

### Full test case table

| Test ID | Test | Result | Issue |
|---|---|---|---|
| AUTH-001 | Fresh login (Google/email) | NOT RUN — manual (MAN-1) | — |
| AUTH-002 | Logout clears Hive + Firebase | PASS (code) | — |
| AUTH-003 | Login as different user (Google) | FAIL (code) — runtime pending | ISSUE-002 |
| AUTH-004 | User B sees no User A data | FAIL (code) — runtime pending | ISSUE-001 |
| AUTH-005 | Unverified email user gets clear message | FAIL (code) | ISSUE-003 |
| AUTH-006 | Session restore after reload | PASS (code) | — |
| EVT-001 | Event listing | PASS (runtime) | — |
| EVT-002 | Event detail fields match API | PASS (code/runtime) | — |
| EVT-003 | Cancelled registrations not shown as events in list | PASS (code) | — |
| REG-001 | Alumni registration (paid event) | NOT RUN — manual (MAN-3) | — |
| REG-002 | Two-pass registration | FAIL (code) | ISSUE-006 |
| REG-003 | Non-alumni blocked with clear message | PARTIAL (backend message shown; stale risk) | ISSUE-013 |
| REG-004 | Duplicate registration | PASS backend (409) / FAIL UI message | ISSUE-018 |
| REG-005 | Email/phone edits persisted | FAIL (code) | ISSUE-019 |
| PAY-001 | Order creation | PASS (code) — runtime pending | — |
| PAY-002 | Payment verification via verify-checkout | PASS (code) — runtime pending | — |
| PAY-003 | Displayed amount = order amount | FAIL for qty>1 (code); Suspected for GST/fee | ISSUE-006, -007 |
| PAY-004 | Close Razorpay then pay again | FAIL (code — no entry point) | ISSUE-008 |
| PAY-005 | Fail then succeed in same modal | FAIL (code) | ISSUE-009 |
| PAY-006 | Payment status check | FAIL (missing) | ISSUE-010 |
| PAY-007 | TEST/LIVE indicated | FAIL (missing) | ISSUE-017 |
| CAN-001 | Cancel unpaid (free) registration | FAIL (405) | ISSUE-004 |
| CAN-002 | Cancel paid registration | FAIL (405) | ISSUE-004 |
| CAN-003 | Cancel twice | NOT REACHABLE | ISSUE-004 |
| REF-001 | Refund initiation | FAIL (never called) | ISSUE-005 |
| REF-002 | Refund status display | FAIL (missing) | ISSUE-005 |
| REF-003 | Refund amount = captured amount | PASS (backend test) | — |
| REF-004 | Refund idempotency | PASS (backend tests) | — |
| MYE-001 | One card per event after cancel/re-register | FAIL (code) | ISSUE-011 |
| ADM-001 | Admin registration view reachable | FAIL (code) | ISSUE-014 |
| ADM-002 | Admin delete event | FAIL (405) | ISSUE-015 |
| ADM-003 | Admin event create persists fees/sessions/speakers | FAIL (schema) | ISSUE-015 |
| RBAC-001 | Admin A → logout → User B: no admin UI | PASS (no admin UI ever shown) | ISSUE-014 |
| BUILD-002 | Android/iOS compile | FAIL (analyzer) | ISSUE-016 |

---

## 26. Tests Not Completed

All of these need a human sign-in or a Razorpay interaction. No browser automation was available in this session. **Use TEST mode only.** Because the NEW app does not show the payment mode, check the Razorpay modal for its "Test Mode" ribbon before paying; if it is absent, **stop** (LIVE).

| ID | What to do | What to capture |
|---|---|---|
| **MAN-1** (ISSUE-001/-002) | In one tab on `WEB`: log in with Google as **User A** (alumni registered for an event) → open that event → logout (sidebar) → "Sign in with Google" → try to pick **User B** → open the same event. Then repeat once with a full page reload between logout and login. | Was the account chooser shown? Which name/badge/email appeared on the event page and in the Register form? Screenshot. |
| MAN-1b (ISSUE-003) | Log in with an email/password Firebase account whose email is unverified | Message shown; DevTools → Network → `POST /api/v1/auth/firebase` status + `detail` |
| **MAN-2** (ISSUE-013) | For a user who sees "Only alumni can register": note the signed-in email (sidebar/Google) and compare with that person's email in the alumni DB | Emails (mask locally), alumni `registrationstatus` |
| **MAN-3** (ISSUE-006/-007) | On event #7 (₹1, open): Register → choose **2 passes** → Checkout → note "Confirm & Pay" amount → press it → note the Razorpay modal amount → **close the modal without paying** | Both amounts; DevTools → Network: `/register` request body + response (`registration_id`, `status`), `/payment-order` response (`order_id`, `final_amount`, `payment_mode`), `/attempts` response (`checkout.amount_minor`) |
| MAN-4 (ISSUE-009, TEST mode only) | Pay with a Razorpay test card that fails, then retry in the same modal with a succeeding test card | Whether `/verify-checkout` was called; app message; registration status afterwards |
| **MAN-5** (ISSUE-011/-008) | After MAN-3, revisit event #7 and My Events; wait past the seat hold (default 15 min), register again | Event page CTA text; number of My Events cards; DevTools: `GET /api/v1/my/registrations` response (`registration_id`, `event_id`, `status`, `latest_order_id`) |
| MAN-6 (ISSUE-004/-005) | With a **confirmed TEST-paid** registration: My Events → Unregister | Network: `DELETE …/my-registration` → 405 (expected); no refund created |
| MAN-7 (ISSUE-014) | Log in with a known platform_admin account | Whether "Manage Events" appears |

**Faster alternative:** after signing in on `WEB`, copy the backend JWT (DevTools → Application → IndexedDB → `auth_session` → key `backend_session` → `access_token`; valid ~8 h) into a local file and tell me its path. I can then run the authenticated read-only checks (`/auth/me`, `/my/registrations`, eligibility, `/payment-pricing` for #5/#7) and a controlled TEST registration with curl, without printing the token.

---

## 27. Recommended Fix Priority

### Before next testing round
1. ISSUE-001 — reset user-scoped state on identity change (P0 privacy).
2. ISSUE-004 / ISSUE-005 — correct cancel endpoint and add refund status (port from reference).
3. ISSUE-006 — remove the quantity selector (or block qty>1) until the backend supports it; show server price.
4. ISSUE-002 — force Google account chooser.
5. ISSUE-008 — status-aware CTA with Continue Payment / Try Again.

### Before UAT
6. ISSUE-009 — disable Razorpay in-modal retry; route outcomes to backend status.
7. ISSUE-010 — payment status view with check-status.
8. ISSUE-007 — server pricing breakdown.
9. ISSUE-011 / ISSUE-012 — My Events grouping/labels; cancellation policy alignment.
10. ISSUE-013 — alumni email data clean-up + clear ineligible messaging.
11. ISSUE-018 / ISSUE-019 / ISSUE-003 — friendly errors, form honesty, login reasons.
12. ISSUE-014 — backend role-discovery endpoint + role-based admin UI.

### Before production
13. ISSUE-017 — TEST/LIVE banner, LIVE confirmation, key/mode guard.
14. ISSUE-015 — admin contract alignment (or hide admin until aligned); payment-config workflow for paid events.
15. ISSUE-016 — mobile dependency (if mobile ships).
16. ISSUE-020 — check-in-compatible QR.
17. Verify Razorpay webhook is registered for the production mode (S-6).

### Post-launch improvement
18. ISSUE-021, ISSUE-022, ISSUE-023; backend S-1…S-4 (count consistency, lookup-failure alerting, refund retry tooling, hold-expiry scheduler).

---

## 28. Suggested Regression Test Suite

| Area | Test (automated) | Layer |
|---|---|---|
| Login/logout/relogin | Widget/provider test: session A → logout → session B; assert every user-scoped provider re-fetches with B's token and never renders A's fields | Flutter |
| Google chooser | Unit test that the web Google provider carries `prompt=select_account` | Flutter |
| Role switching | Admin session → logout → non-admin session; admin nav absent; admin routes show 403 handling | Flutter + backend |
| Registration | Mocked API: register paid → `seat_held` → checkout; free → `registered` | Flutter |
| Alumni eligibility | Backend: email match, case-insensitivity, inactive status, lookup failure path; Flutter: each `eligibility_status` renders correct CTA | Both |
| Duplicate prevention | Backend: double register → 409; Flutter: friendly message | Both |
| Participant count | If quantity remains unsupported: assert no quantity UI and request body has only `attendee_note` | Flutter |
| Price calculation | Displayed total == `/payment-pricing.final_amount` == order `final_amount` == `amount_minor/100` | Flutter + contract |
| Razorpay order creation | Order reuse with different idempotency keys; key/mode guard | Flutter + backend |
| Payment verification | Success callback → verify-checkout called exactly once; failure then success (retry disabled) | Flutter |
| Payment retry | `seat_held`/`payment_failed` → Continue Payment reaches attempt reuse | Flutter + backend |
| Cancellation | Contract test: client calls `POST /registrations/{id}/cancel` with stable idempotency key; UI refresh | Flutter |
| Refund | Status polling until terminal; failed-refund messaging | Flutter |
| Refund idempotency | Existing backend tests (keep in CI) | Backend |
| Admin RBAC | Role endpoint drives UI; event_admin sees only own events | Both |
| API contract | Generate the Dart client (or a contract test) from the live OpenAPI so nonexistent endpoints (405s) fail CI | Contract |

---

## 29. Final Assessment

The NEW Flutter frontend is a capable attendee shell (login, event browsing, eligibility display, first-time Razorpay payment), but it is **not functionally complete** against the backend and has a **P0 privacy defect**:

- **Authentication:** core login/logout calls are correct; user switching fails because of stale per-event state (P0) and the missing Google account chooser.
- **Registration:** works for a single person; the multi-pass feature has no backend and causes a P0 price/expectation mismatch.
- **Payment:** happy path correct and server-verified; retry, status, TEST/LIVE and the fail-then-succeed case are missing.
- **Cancellation:** broken (wrong endpoint, HTTP 405 in production).
- **Refund:** absent from the app; the backend refund implementation itself works.
- **Admin:** present in code but unreachable (role-model mismatch), and partially mis-wired to nonexistent or field-dropping endpoints.

The reference `nitksaa-payment` app already contains working implementations for almost every missing payment/cancellation/refund capability; porting its repositories, provider lifecycle and status screens closes most gaps.

---

## Where Are the Problems?

✅ = verified contributing layer · ◐ = contributing, not runtime-verified · blank = not involved

| Issue | Frontend | Backend | API Contract | Auth | Razorpay | Config/Data | Fix Location |
|---|:-:|:-:|:-:|:-:|:-:|:-:|---|
| ISSUE-001 User-switch data leak | ✅ | | | ◐ | | | NEW Flutter only |
| ISSUE-002 Google account chooser | ✅ | | | ✅ | | | NEW Flutter only |
| ISSUE-003 Login errors masked | ✅ | ◐ (new rule) | | ✅ | | | NEW Flutter only |
| ISSUE-004 Cancellation 405 | ✅ | | ✅ | | | | NEW Flutter only |
| ISSUE-005 Refund missing | ✅ | | ✅ | | | | NEW Flutter only |
| ISSUE-006 Multi-pass pricing | ✅ | ✅ (feature absent) | ✅ | | ◐ | | Both (product decision) |
| ISSUE-007 Price from ticket_price | ✅ | | ◐ | | | ◐ | NEW Flutter only |
| ISSUE-008 Retry/resume | ✅ | | | | | | NEW Flutter only |
| ISSUE-009 Razorpay retry | ✅ | | | | ✅ | | NEW Flutter only |
| ISSUE-010 Payment status | ✅ | | | | | | NEW Flutter only |
| ISSUE-011 Duplicate cards | ✅ | | | | | | NEW Flutter only |
| ISSUE-012 Cancel gating | ✅ | ◐ (no policy) | | | | | NEW Flutter (or backend policy) |
| ISSUE-013 Alumni eligibility | ◐ | ◐ | | ◐ | | ◐ (data) | Data + backend logging + Flutter |
| ISSUE-014 Admin unreachable | ✅ | ✅ (no roles API) | ✅ | | | | Both |
| ISSUE-015 Admin contract | ✅ | | ✅ | | | | NEW Flutter (backend if features wanted) |
| ISSUE-016 Mobile build | ✅ | | | | ✅ | ✅ | NEW Flutter only |
| ISSUE-017 TEST/LIVE | ✅ | | | | ✅ | | NEW Flutter only |
| ISSUE-018 Raw errors | ✅ | | | | | | NEW Flutter only |
| ISSUE-019 Form fields | ✅ | | ✅ | | | | NEW Flutter only |
| ISSUE-020 QR/check-in | ✅ | ✅ (token not exposed) | ✅ | | | | Both |
| ISSUE-021 Routing | ✅ | | | | | | NEW Flutter only |
| ISSUE-022 Web shell/hosting | ✅ | | | | | ✅ | NEW Flutter + hosting |
| ISSUE-023 Tests/code health | ✅ | | | | | | NEW Flutter only |

---

## Answers to the Required Questions

**Q1 — Why does Login → Logout → Login fail when switching user?**
Two code defects in the NEW app, plus one backend rule that the app hides. (a) On web, `signInWithGoogle` (`firebase_auth_service.dart:31-33`) does not set `prompt: select_account`, and logout correctly leaves the Google browser session alive, so the popup re-signs the previous Google account. The reference app sets this parameter. (b) Even when User B does sign in, `eventDetailProvider` (`event_detail_provider.dart:132`) is a long-lived family fetched once and never invalidated, so User A's registration, badge, eligibility and profile are shown until a page reload. (c) For email/password accounts, the backend has rejected unverified emails since 2026-10-01 (`403 email_not_verified`), and the app shows only "Sign in failed". Firebase sign-out and token clearing are executed correctly; localStorage, sessionStorage and SharedPreferences are not used. Hive and Firebase IndexedDB stores are cleared.

**Q2 — Is the refund backend API functional?**
Yes, by code and by test. `POST /registrations/{id}/cancel` performs cancellation plus a full refund for a confirmed paid registration, and `GET /registrations/{id}/refund` returns and refreshes status. 21/21 backend refund tests pass (local dev DB, sandbox/mocked provider). It has not been exercised end-to-end against production Razorpay (needs MAN-6 in TEST mode).

**Q3 — Does the NEW app call the correct refund API?**
No. It calls neither cancel nor refund status. Its only cancel call is `DELETE /events/{event_id}/my-registration`, which returns 405.

**Q4 — Attendee-driven or admin/finance-driven?**
Attendee-driven only. Only the registration owner can cancel and get a refund. There are no admin or finance refund endpoints. Finance, auditor and support roles only have read access to payment configuration and gateway configuration.

**Q5 — Does cancellation automatically trigger a refund?**
Yes, for a `registered` registration with a `paid` order. It is atomic with cancellation, and the provider is called synchronously. A free registration is just cancelled (`status: none`). In-flight payment states return `409 registration_not_cancellable`.

**Q6 — Intended cancellation → refund sequence?**
`POST /registrations/{registration_id}/cancel {idempotency_key}` → response `RefundStatusResponse` → poll `GET /registrations/{registration_id}/refund` until `refund_processed` or `refund_failed`. The registration stays `cancelled` and the order stays `paid`. History is available from `GET /payment-orders/{latest_order_id}/timeline`.

**Q7 — Why "Only alumni can register" for self-identified alumni?**
The verdict comes from the backend. `user_type` is `alumni` only if the Firebase login email matched `alumni_db.alumni.email` at the user's last `POST /auth/firebase`. Likely causes: a different Google email, a silent alumni-lookup failure at first login, or an alumni record fixed after the last login (session restore does not re-match). In the NEW app, a stale verdict from a previous user can also be shown (ISSUE-001). Previous registrations never confer alumni status.

**Q8 — Authoritative source of alumni status?**
The `alumni_db.alumni` table, matched by email at login and stored in `event_users.user_type`/`ref_id`. `registrationstatus` (Active or Self-Verified) is checked at registration time. The Flutter app does not compute eligibility; it displays the backend verdict.

**Q9 — Why duplicate events after cancellation?**
The backend returns registration history: one row per `registration_id`, including cancelled and expired rows. The NEW My Events renders one card per row without grouping by `event_id`. The backend does not duplicate any single registration.

**Q10 — Why does cancellation fail?**
Wrong method, path, identifier and body: `DELETE /events/{event_id}/my-registration` returns 405. The backend expects `POST /registrations/{registration_id}/cancel` with an `idempotency_key`. In addition, the button is hidden whenever the event's registration window is closed.

**Q11 — Why is multi-member pricing incorrect?**
The backend has no quantity concept. The app multiplies `ticket_price × quantity` for display only and sends a `quantity` field that the backend ignores.

**Q12 — Backend amount correct and only display wrong, or both?**
The backend amount is internally consistent for its contract (one registration, priced from the published config). The Flutter display is wrong relative to it. If multi-pass is a product requirement, the backend is missing the feature, not miscalculating it.

**Q13 — Does Razorpay receive the correct amount?**
Razorpay receives the backend order amount (`final_amount × 100` paise, one pass), whatever quantity was chosen. It matches the backend but not the app's "Confirm & Pay" figure when the quantity is greater than 1. Runtime confirmation is pending (MAN-3).

**Q14 — Does refund use the original captured amount?**
Yes: the paid order's `final_amount`, refunded against the captured attempt's provider payment id under the captured attempt's `payment_mode` (`refund_service.py:200-215`). This is verified by `test_refund_amount_equals_captured_amount` (passed).

**Q15 — Payment/refund features in reference but missing in NEW?**
Correct cancel, refund status, Continue Payment / Try Again, `latest_order_id` recovery, payment status screen with auto-refresh, check status (`verifyAttempt`), server pricing, timeline, TEST/LIVE banner, LIVE confirmation, key/mode guard, `retry.enabled=false`, friendly errors, Google `select_account`, `autoDispose` provider lifecycle, and the mobile Razorpay dependency (§17).

**Q16 — Backend APIs not integrated?**
Cancel, refund status, pricing, get order, verify attempt, timeline, admin event read, admin events v2, all-status registrations, export, check-ins, people/sponsors/partners, payment configurations, roles, lifecycle sweeps and gateway config (§18).

**Q17 — Admin features implemented in the NEW app?**
Event list (published/draft), create, edit, publish/unpublish, delete (405), and the attendee list with search, filters and client-side CSV export. All of them are unreachable for real admins (ISSUE-014).

**Q18 — Admin APIs with no Flutter UI?**
`/admin/events` v2 (publish, close, sessions), all-status registrations, attendee export, check-ins (verify, create, list, attempts), people/sponsors/partners CRUD, payment configurations (draft, list, get, validate, publish), platform roles (grant, revoke, list), event payment-admin grant, lifecycle sweeps, gateway config.

**Q19 — iTelematics references?**
None in tracked source or the deployed bundle. The only matches are local filesystem paths (`/Users/ananth/iTelematics/…`) inside three git-ignored, generated iOS files, plus a debug-only hint `'e.g. sudarshana'` in the developer diagnostics screen.

**Q20 — Security/privacy risk from stale user state?**
Yes, P0. User B can see User A's registration status, registration/badge number, QR, eligibility, and name/email/phone in the registration form within the same browser tab (ISSUE-001). The backend correctly blocks any cross-user action, so the exposure is display-only, but it is personal data.

---

## Financial Integrity Check (§42)

| Reconciliation step | Status |
|---|---|
| Expected registration amount (server pricing) | Not read — needs auth (MAN-3) |
| = Backend order amount | Code: `create_order` uses `calculate_price(config)` ✅ |
| = Razorpay checkout amount | Code: `amount_minor` derived from order; webhook/verify reject amount mismatch ✅ |
| = Captured amount = payment record | Code: `verify_checkout`/webhook compare provider amount to attempt amount ✅ |
| **≠ Flutter displayed amount when qty > 1 or GST/fee configured** | ❌ ISSUE-006 (P0), ISSUE-007 (P1) |
| Refund: eligible = request = provider = record | Code + backend tests ✅ (unreachable from NEW app) |

---

*Report generated by read-only analysis. No application source, configuration, environment, or production data was modified. Side effects of the verification: Flutter tool caches under the git-ignored `frontend/.dart_tool`/`build` from `flutter analyze`/`flutter test`; test fixture rows written to the **local development** `events_db` by the backend refund test run; downloaded copies of the deployed bundle in the session scratchpad.*
