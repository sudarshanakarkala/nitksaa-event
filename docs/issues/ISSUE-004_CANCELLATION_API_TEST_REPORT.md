# ISSUE-004 Cancellation API Test Report

**Date:** 2026-10-10
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `e7267a2` (branch `main`), which contains the ISSUE-001, ISSUE-002, ISSUE-003 and ISSUE-006 fixes and the UI merge (PR #2).
**Fix branch:** `fix/issue-004`, two commits: the cancel API, then registering again after a cancellation
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, `dio` 5.9.2, `go_router` 17.2.3, `flutter_riverpod` 2.6.1, Chrome 154 for the browser tests
**Final result:** CODE PASS — MANUAL E2E PENDING

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-004 |
| Severity | P1 — Gate A blocker |
| Area | Cancellation / My Events / Event list |
| Status | Fixed on `fix/issue-004`. Manual verification not run. Deploy status is in section 6. |

"Unregister" sent `DELETE /api/v1/events/{event_id}/my-registration`. The backend has no such route and answered 405, so no registration could be cancelled from the app, and no refund could start.

---

## 2. Root Cause

The full analysis is in `ISSUE-004_CANCELLATION_API.md`.

### Wrong request

`EventsRepository.cancelMyRegistration` sent a `DELETE` to a path that only has a `GET`. The route, the method, the identifier, the body and the response model were all wrong. The backend's cancel call is `POST /api/v1/registrations/{registration_id}/cancel` with an `idempotency_key`, and it returns a refund status.

### Keyed on the event

The notifier, both screens and the "in progress" flag used `eventId`. Both screens already held the registration and its `registrationId`.

### Two callers

My Events and the event list "Registered by me" card both call `MyEventsNotifier.cancelRegistration`. The event page has no cancel button.

### Failure handling

A failed cancel put `e.toString()` into the field My Events uses for a failed load. My Events then replaced the list with "Could not load registrations" and the raw `DioException` text.

### Dead end after cancelling

For a cancelled registration the event page showed "Unregistered from this event" and no Register button, whatever the backend's eligibility answer was. The backend reports a cancelled attendee as `eligible` and accepts a new registration. This could not be reached while cancelling never worked; the cancel fix makes it reachable, so it is closed here.

---

## 3. Fix

### Files Changed

| File | Change |
|---|---|
| `frontend/lib/features/events/data/events_repository.dart` (+15 −7) | `cancelMyRegistration` (DELETE) removed. `cancelRegistration(registrationId, token, idempotencyKey:)` posts to the cancel route and returns `RefundStatus` |
| `frontend/lib/features/events/domain/refund_status.dart` (new, 71 lines) | `RefundStatus`: the ten fields of `RefundStatusResponse`, all tolerant of null |
| `frontend/lib/features/events/presentation/providers/cancellation_outcome.dart` (new, 97 lines) | `CancellationOutcome`: cancelled or not, and the message to show |
| `frontend/lib/features/events/presentation/providers/my_events_provider.dart` (+65 −13) | Cancels by registration id; makes and keeps the idempotency key; in-progress state is a set of registration ids; returns the outcome |
| `frontend/lib/features/events/presentation/screens/my_events_screen.dart` (+7 −12) | Passes `registrationId`; shows the outcome's message |
| `frontend/lib/features/events/presentation/screens/event_list_screen.dart` (+17 −9) | Passes `registrationId`; shows the outcome's message; the per-event lookup prefers the active registration |
| `frontend/lib/features/events/presentation/screens/event_detail_screen.dart` (+20 −1) | Second commit. Cancelled and eligible: the Register button and a one-line note |
| `frontend/test/features/events/cancellation_screens_test.dart` (new, 530 lines) | 29 tests on the real screens: 8 for each Unregister button and 13 for the event page |
| `frontend/test/features/events/cancellation_api_test.dart` (new, 499 lines) | 26 tests on the notifier, the repository, the messages and the model |
| `frontend/test/features/events/cancellation_source_test.dart` (new, 52 lines) | 3 tests on the source files, VM only |
| `frontend/test/features/events/cancellation_reregister_checkout_test.dart` (new, 138 lines) | 2 tests that register again through the real `CheckoutScreen`, browser only |
| `frontend/test/features/events/support/registration_backend_fake.dart` (+298 −18) | The ISSUE-006 fake backend extended with the cancel contract, `GET /my/registrations`, the public event list and a settable eligibility answer |
| `docs/issues/ISSUE-004_CANCELLATION_API.md` (new) | Issue analysis |
| `docs/issues/ISSUE-004_CANCELLATION_API_TEST_REPORT.md` (new) | This report |

No backend, auth, checkout or developer-diagnostics file is changed. `event_detail_provider.dart` is not changed. No package was added. `frontend/build/web` was rebuilt; it is git-ignored.

### Request

```text
POST /api/v1/registrations/{registration_id}/cancel
Authorization: Bearer <access token>
{"idempotency_key": "cancel-<registration id>-<milliseconds>"}
```

The DELETE is gone. `cancelMyRegistration` no longer exists, so no code path can send it.

### Registration, not event

`cancelRegistration` takes the registration id at every level. `MyEventsState.cancellingEventId` became `cancellingRegistrationIds`, a set, with `isCancelling(registrationId)`. Two registrations of the same event are told apart, and so are two cancels running at once.

The event list finds a card's registration in a map from event id to registration. The map used to keep the last row of each event, and the backend lists newest first, so an event with an old cancelled registration and a current one resolved to the old one. That card then had no Unregister button. The map now prefers the active row. This is the only ISSUE-011 code touched, and test C from the event list needs it: with the old map that test fails.

### Idempotency key

Made when a cancel starts, in the form checkout already uses for payment orders (`<prefix>-<registration id>-<milliseconds>`). It is about 25 characters; the backend accepts 8 to 128. The notifier keeps it by registration id until the backend answers definitely.

| What came back | Key |
|---|---|
| 200 | Dropped |
| 4xx | Dropped: the backend refused and created nothing |
| No response, timeout, 5xx | Kept, so the retry repeats the same cancellation |

### Response

Parsed as `RefundStatus`. Parsing cannot throw. Once a 200 has arrived the registration is cancelled, and a field the app cannot read must not be reported as a failed cancel.

### Messages

| Outcome | Message |
|---|---|
| Cancelled, `none` | "Your registration has been cancelled." |
| Cancelled, `refund_pending` / `refund_processed` | "Your registration has been cancelled. Your refund has been initiated." |
| Cancelled, `refund_failed` | The backend's `safe_message` |
| `registration_not_cancellable` | "This registration can't be cancelled while payment is in progress." |
| `registration_not_found` | "We couldn't find this registration. Please refresh and try again." |
| `no_captured_payment`, `refund_not_supported`, `refund_mode_mismatch` | "We couldn't cancel this registration automatically. Please contact support." |
| No connection, timeout | "Unable to connect to the server. Check your internet connection and try again." |
| Anything else | "Could not cancel your registration. Please try again." |

Two choices that differ slightly from the suggested table:

- For `refund_failed` the backend's message is shown on its own, not after "Your registration has been cancelled." It already begins "Your registration is cancelled, but the refund could not be completed automatically", and the prefix would say it twice. If the backend ever sends no message, a fixed one that starts with the cancellation is used.
- For `refund_pending` and `refund_processed` the fixed wording is used, not the backend's.

The mapping is in `cancellation_outcome.dart` and is used by cancellation only.

### Refresh

After a successful cancel the notifier reloads `myEventsProvider`, which My Events and the event list both read. The Unregister button stays disabled until the reload ends. The event page needed no change to refresh (section 4, test L).

### Register again after cancelling

Second commit, in `_buildRegistrationCTA` of `event_detail_screen.dart` only.

| Newest registration | Eligibility | Before | After |
|---|---|---|---|
| `cancelled` | `eligible` | "Unregistered from this event" | "You cancelled your earlier registration." and the normal Register button |
| `cancelled` | `full`, `closed`, `not_open_yet`, `ineligible` | "Unregistered from this event" | Same |
| `cancelled` | unknown, because the call failed | "Unregistered from this event" | Same |
| `cancelled`, past event | any | "Unregistered from this event" | Same |
| any other status | any | | Same |

The Register button is the existing one. It opens the existing form and checkout. Checkout already registers afresh when the registration it holds is not one that still owes payment, so a cancelled registration is never reused: the backend makes a new row and the cancelled one stays as history. For a paid event the payment order is made for the new registration.

When the attendee is not eligible the page is as it was. It does not show the backend's reason; that would be a wider change to this page.

---

## 4. Automated Verification

Commands, from `frontend/`:

```bash
flutter test
flutter test test/features/events/cancellation_screens_test.dart \
  test/features/events/cancellation_api_test.dart \
  test/features/events/cancellation_source_test.dart
flutter test --platform chrome test/features/auth/ test/features/events/
flutter test --platform chrome \
  test/features/events/cancellation_reregister_checkout_test.dart
```

How the tests are built:

- `MyEventsScreen`, `EventListScreen`, `EventDetailScreen`, `MyEventsNotifier` and `EventsRepository` are the real classes. The repository uses a real Dio client whose transport is replaced by the fake backend, so each test reads the method, path, token and JSON body that would have gone on the wire.
- The screen tests press the real Unregister button and the real button in the confirm dialog. Every one of them runs twice: from My Events, and from the event list opened as the account menu opens it (`/home?mine=1`, "Registered by me" on).
- The event-page tests run for the Material page and for the iOS page. On the VM the checkout step is a stand-in that registers through the page's own notifier, because `CheckoutScreen` cannot compile there (ISSUE-016). In Chrome two more tests go through the real `CheckoutScreen`, with Razorpay replaced by the ISSUE-006 fake.
- The fake backend follows `refund_service.cancel_registration` in the same order of checks: key length (422), ownership (404), already cancelled (200), not `registered` (409), then free or paid. It keeps every registration row, lists them newest first, and counts the refunds it makes. It answers the old DELETE with 405, as production does.
- A network failure is a Dio connection error raised by the transport, either before the backend sees the request or after it has carried it out.

| Test | Expected | Actual | Result |
|---|---|---|---|
| Correct request (A) | One `POST /api/v1/registrations/{registration_id}/cancel`; `Authorization: Bearer <token>`; body is exactly `{"idempotency_key": …}`, 8 to 128 characters | As expected, from both buttons | PASS |
| No DELETE (B) | No request uses `DELETE`. No request to `…/my-registration` other than `GET`. No file in `lib/` contains a `delete` call to `my-registration`, the words `DELETE … my-registration`, or `cancelMyRegistration` | As expected | PASS |
| Registration id, not event id (C) | With an old cancelled registration and a current one for the same event, the request path carries the current `registration_id`; the old one is never sent | As expected, from both buttons | PASS |
| Free event (D) | Status `none`; "Your registration has been cancelled."; `GET /my/registrations` sent again after the cancel; no active registration shown; no refund; the seat is released | As expected | PASS |
| Paid event (E) | Status `refund_pending`; "…Your refund has been initiated."; one refund; the amount, currency, dates and mode are parsed; the snackbar is the only text on screen that mentions a refund. `refund_processed` gives the same message | As expected | PASS |
| Idempotent retry (F) | First attempt fails with a network error, retry succeeds: both requests carry the same key. A later cancel of another registration, and a later cancel of the same registration after a refusal, carry a different key. When the response is lost after the backend has refunded, the retry carries the same key and there is still one refund. A 500 keeps the key | As expected | PASS |
| Already cancelled (G) | The backend's 200 is shown as "Your registration has been cancelled." and the list reloads | As expected | PASS |
| Not cancellable (H) | `409 registration_not_cancellable` for `seat_held`, `payment_pending`, `payment_verification`, `payment_failed`: "This registration can't be cancelled while payment is in progress."; the card is still there, still registered; no "Could not load registrations"; no exception text | As expected | PASS |
| Not found / wrong user (I) | `404 registration_not_found`: "We couldn't find this registration. Please refresh and try again."; the other user's registration is untouched | As expected | PASS |
| Network failure (J) | "Unable to connect to the server. Check your internet connection and try again."; the Unregister button is enabled again; the list and its error state are unchanged | As expected | PASS |
| Both UI entry points (K) | Tests A to J above pass from My Events and from the event list "Registered by me" card | 8 of 8 from each | PASS |
| Event page after cancel (L) | The page showed "Registered Successfully" and a badge number before. After the cancel it fetches `my-registration` a second time and shows neither, nor "View QR badge" | As expected. It shows the note and the Register button | PASS |
| ISSUE-001/002/003/006 regression (M) | All existing tests pass on the VM and in Chrome | 110 of 110 and 124 of 124 | PASS |
| Cancelled and eligible (N) | The note and the Register button are shown, and no "Unregistered from this event". Register, the form and checkout make one `POST /register`; the new registration has a new id and is `registered`; the cancelled one is unchanged; one seat is taken; the page shows "Registered Successfully" with the new badge number | As expected, on both page forms, and in Chrome through the real checkout | PASS |
| Cancelled and eligible, paid event (N) | Register, payment order, attempt and verification each once, in that order, and all for the new registration id | As expected, in Chrome through the real checkout | PASS |
| Cancelled and not eligible (O) | For `ineligible`, `full`, `closed` and `not_open_yet`: no Register button, no note, "Unregistered from this event" as before | As expected, on both page forms | PASS |
| Cancelled, eligibility unknown (O) | The eligibility call fails with 500: no Register button | As expected | PASS |
| Never registered | The Register button has no note about a cancellation | As expected | PASS |

Also covered, beyond the list in the task:

| Check | Result |
|---|---|
| `409 no_captured_payment`, `refund_not_supported`, `refund_mode_mismatch` each give the "contact support" message, and no refund is made | PASS |
| `refund_failed` shows the backend's `safe_message` and counts as cancelled | PASS |
| A 503, and a 409 with an unknown code, give the general message | PASS |
| For every Dio error type and for 401, 405, 409, 422, 500 and 502 responses, the message has no exception text, status code or backend code | PASS |
| While a cancel is in flight only that registration is marked; another registration of the same event is not | PASS |
| Signed out: nothing is sent | PASS |
| `RefundStatus` reads all ten fields, accepts every null of a free cancellation, and does not throw on an empty or malformed body | PASS |

### Totals

| | Before ISSUE-004 (`e7267a2`) | After ISSUE-004 |
|---|---|---|
| `flutter test` (VM) | 110 of 110 | 168 of 168 |
| Chrome, `test/features/auth/` and `test/features/events/` | 124 of 124 | 181 of 181 |

New tests: 58 on the VM and 57 in Chrome. The 55 in the screen and API files run on both; the 3 source tests are VM only and the 2 real-checkout tests are Chrome only.

After the first commit alone the totals were 156 on the VM and 167 in Chrome.

### The same tests against the code before the fix

The new tests and the extended fake were copied into an untouched checkout of `e7267a2`.

| | Fail | Pass | Could not run |
|---|---:|---:|---:|
| VM, `cancellation_screens_test.dart`, 17 tests | 17 | 0 | |
| VM, `cancellation_source_test.dart`, 3 tests | 2 | 1 | |
| VM, `cancellation_api_test.dart`, 26 tests | | | 26 |
| Chrome, `cancellation_screens_test.dart`, 17 tests | 17 | 0 | |
| Chrome, `cancellation_api_test.dart`, 26 tests | | | 26 |

`cancellation_api_test.dart` does not compile against the old code: `RefundStatus` and `CancellationOutcome` did not exist, and `cancelRegistration` returned nothing. The one source test that passes only checks that `lib/` is being read.

What the old code did when Unregister was pressed and confirmed, from both buttons:

| Observed before the fix | |
|---|---|
| Request sent | `DELETE /api/v1/events/7/my-registration`, no body |
| Cancel request | None |
| Snackbar | "Could not unregister." |
| My Events afterwards | The list replaced by "Could not load registrations" and `DioException [bad response]: … status code of 405 …` |
| Event list afterwards | Card unchanged |
| Source | `events_repository.dart` contained the `delete` call and `cancelMyRegistration` |

The table above is for the tests of the first commit. The 13 event-page tests were run on the VM against the event page as it was before the second commit:

| | Fail | Pass |
|---|---:|---:|
| VM, event-page group, 13 tests | 3 | 10 |

The three that fail are test L and "cancelled and eligible" on both page forms: the page showed "Unregistered from this event" and no Register button. The ten that pass describe behaviour the second commit does not change.

---

## 5. Contract Verification

The backend is not changed. Its cancel contract was read from `backend/` at `e7267a2`, and from the live API's OpenAPI document (`https://nitksaa-events-api-246773894709.asia-south1.run.app/openapi.json`) on 2026-10-10, without signing in.

`CancelRegistrationRequest` and `RefundStatusResponse` (`backend/app/schemas/payments.py:129-146`):

```python
class RefundStatusResponse(BaseModel):
    refund_id: Optional[str] = None
    registration_id: int
    status: str
    amount: Optional[Decimal] = None
    currency: Optional[str] = None
    requested_at: Optional[datetime] = None
    finalized_at: Optional[datetime] = None
    safe_message: str
    payment_mode: Optional[str] = None
    real_money: bool = False

class CancelRegistrationRequest(BaseModel):
    idempotency_key: str = Field(..., min_length=8, max_length=128)
```

| Where | Finding | Evidence |
|---|---|---|
| Cancel route | `POST /api/v1/registrations/{registration_id}/cancel`, bearer token required | `refunds.py:18-31`. The live OpenAPI document lists `post` only, with `HTTPBearer` |
| Old route | `/api/v1/events/{event_id}/my-registration` has `GET` only | `registrations.py:31-40`. The live OpenAPI document lists `get` only. No path there has a `delete` on `my-registration` |
| Request body | `idempotency_key`, 8 to 128 characters | Schema above. The live schema has `minLength` 8, `maxLength` 128 |
| Response | The ten fields above; `registration_id`, `status`, `safe_message` required | Same in the live schema |
| Already cancelled | 200 with the latest refund, or `none` | `refund_service.py:116-119` |
| Not `registered` | `409 registration_not_cancellable` | `refund_service.py:121-125` |
| Not found or not owned | `404 registration_not_found`, same body for both | `refund_service.py:88-95` |
| No paid order | Cancelled, `none`, no refund row | `refund_service.py:137-151` |
| Paid order | `409 no_captured_payment`, `refund_not_supported` or `refund_mode_mismatch` before anything is written; otherwise one refund row and the registration cancelled in one transaction, then the provider call | `refund_service.py:153-221` |
| Repeat | The same key, or any second cancel of the order, returns the existing refund with no second provider call | `refund_service.py:183-188, 213-221` |
| Ordering of `GET /my/registrations` | Newest first | `registration_repository.py:307-311` |
| `GET /events/{id}/my-registration` | The newest registration, cancelled ones included | `registration_repository.py:297-303` |

The contract matches the task description. The HTTP 405 for the old DELETE was observed against production on 2026-10-03 (verification report, ISSUE-004). It was not sent again for this report.

---

## 6. Manual Verification

**Result: PENDING.** No step in this section has been run.

The beta deploy was approved on 2026-10-10 and is made from this branch after the second commit. Whether it was done, and when, is recorded in the pull request description, because it happens after this report is committed. The fix is not deployed to the live site.

Manual testing is on beta only. The live site is never deployed from this branch.

```bash
cd frontend
flutter pub get
flutter test
flutter build web --release \
  --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
firebase deploy --only hosting:beta --project project-d22bed42-f302-4e23-8dc
```

Then test on `https://nitksaa-events-beta.web.app` in a private window, with DevTools → Network open. Afterwards discard the local pub-get edits: `git checkout -- pubspec.lock analysis_options.yaml linux macos windows`.

### Prerequisites

- **A signed-in, eligible alumni account**, and a second account for step 8.
- **An open free event and an open TEST-mode paid event.** Event #11 "TestOct8" closes at 23:59 IST on 2026-10-10. After that an admin has to create new ones.
- **Beta and live share one backend.** Every cancellation and TEST refund made on beta is a real backend record. Paid tests in Razorpay TEST mode only: cancelling a paid registration sends a real refund request to Razorpay in the mode the payment was captured in.

### Steps

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Register for the free event, open My Events, Unregister, confirm | One `POST /registrations/{id}/cancel`, 200, status `none`; "Your registration has been cancelled."; card shows cancelled | PENDING |
| 2 | Check the Network panel | No `DELETE …/my-registration` | PENDING |
| 3 | Open the event page | No "Registered Successfully", no badge. "You cancelled your earlier registration." and a Register button. Register again: one `POST /events/{id}/register`, a new registration id, and the page shows "Registered Successfully" | PENDING |
| 4 | With the registration from step 3, repeat step 1 from the event list "Registered by me" card | Same result as step 1, with the new `registration_id` in the path | PENDING |
| 5 | Register and pay for the TEST paid event (Razorpay Test Mode ribbon visible), then Unregister | 200, status `refund_pending` or `refund_processed`; "…Your refund has been initiated." | PENDING |
| 6 | Optional: Razorpay TEST dashboard | One refund for the captured payment, full amount | PENDING |
| 7 | Hold a seat (close Razorpay without paying), then try to cancel | No Unregister button for that status. If one is shown: `409 registration_not_cancellable` and the "payment is in progress" message | PENDING |
| 8 | With user B's token, `POST` user A's `registration_id` to `/cancel` | 404 `registration_not_found` | PENDING |

After step 3 My Events shows two cards for the event, the cancelled registration and the new one. That is ISSUE-011 and is expected here.

---

## 7. ISSUE-001/002/003/006 Regression

No existing test was edited. The only existing test file changed is the shared fake backend, which gained endpoints and kept its behaviour for the ISSUE-006 tests. Its seat count now leaves out cancelled registrations; no earlier test has one.

### ISSUE-001 — PASS (automated)

- `event_detail_auth_isolation_test.dart`: 18 of 18 on the VM and in Chrome.
- `checkout_auth_isolation_test.dart`: 1 of 1 in Chrome.
- `event_detail_provider.dart` is not changed by either commit. The session-bound token and the `autoDispose` provider are what make test L pass.

### ISSUE-002 — PASS (automated)

- `google_sign_in_account_chooser_test.dart`: 1 of 1 on the VM, 3 of 3 in Chrome.
- `google_login_flow_test.dart`: 5 of 5 in Chrome.
- `prompt=select_account` is preserved: `firebase_auth_service.dart:58` still sets it, and the release bundle contains `select_account`.

### ISSUE-003 — PASS (automated)

- `backend_auth_exception_test.dart`: 27 of 27 on the VM and in Chrome.
- `auth_error_messages_test.dart`: 22 of 22 on the VM and in Chrome.
- `login_failure_rollback_test.dart`: 26 of 26 on the VM, 27 of 27 in Chrome.
- No file under `frontend/lib/features/auth/` is changed.

### ISSUE-006 — PASS (automated)

- `registration_quantity_test.dart`: 9 of 9 on the VM and in Chrome.
- `registration_quantity_source_test.dart`: 6 of 6 on the VM.
- `checkout_single_registration_test.dart`: 12 of 12 in Chrome.
- `registerForEvent` still sends `{"attendee_note": …}` only. `checkout_screen.dart` is not changed. `event_detail_screen.dart` changed only in the branch for a cancelled registration; the registration form is as it was. The release bundle does not contain `quantity=`.

### PR #2 UI

Nothing is restyled. The confirm dialog, the buttons and the cards are as they were. Two pieces of text changed: the snackbar after Unregister, and one new line above the Register button on the event page, in the palette's secondary text colour. `bash frontend/tool/check_colors.sh` reports `check_colors: OK`.

---

## 8. Static Checks

### flutter test

```bash
flutter test
```

Result: `+168: All tests passed!` (110 before this change.)

ISSUE-004 tests alone: 58 of 58.

### Chrome tests

```bash
flutter test --platform chrome test/features/auth/ test/features/events/
```

Result: `+181: All tests passed!` (124 before this change.) This includes the 2 real-checkout tests.

### flutter analyze

Measured fresh on `e7267a2`. The count is lower than the 98 in the ISSUE-006 report because PR #2 changed the baseline.

| | Total | Errors | Warnings | Info |
|---|---:|---:|---:|---:|
| Before ISSUE-004 (`e7267a2`) | 75 | 6 | 32 | 37 |
| After ISSUE-004 | 75 | 6 | 32 | 37 |

- **Pre-existing issues:** all 75. The two lists are identical when line numbers are ignored. `flutter analyze` exits with code 1 before and after: the 6 errors are in `razorpay_payment_io.dart` and come from the missing `razorpay_flutter` package (ISSUE-016), which was left alone.
- **New ISSUE-004 issues:** none. No finding is in any new or changed file's new lines.

### Colour check

```bash
bash frontend/tool/check_colors.sh
```

Result: `check_colors: OK`.

### web build

```bash
flutter build web --release \
  --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
```

Result: succeeded (`✓ Built build/web`).

| Check on `build/web/main.dart.js` | Result |
|---|---|
| `/cancel` | Present once, as `"/api/v1/registrations/"+a+"/cancel"` |
| `idempotency_key` | Present twice: the cancel call and the payment order |
| `my-registration` | Present once, in the call that also fetches `/api/v1/my/registrations`, which is the `GET` |
| `"DELETE"` | Present once, in the admin delete-event call to `/api/v1/events/{id}`. Not near `my-registration` |
| "Could not unregister", `cancelMyRegistration` | Absent |
| "Your refund has been initiated." | Present once |
| "You cancelled your earlier registration." | Present once |
| `select_account` | Present once |
| `quantity=` | Absent |
| Production backend URL | Present |
| SHA-256 | `dd76aba1325ae8f2643deb46b8a775ab95d751d398075845987c9eaaca74e377` |
| Deployed | Not to live. Beta: see section 6 |

---

## 9. Source Search

Run from the repository root after the fix.

| Search | Matches |
|---|---|
| `grep -Rn "cancelMyRegistration" frontend/lib` | None |
| `grep -Rn "my-registration" frontend/lib/features/events` | 1: the `GET` in `getMyEventRegistration` |
| `grep -Rn "my-registration" frontend/lib/features/developer` | 7, all for the `GET`, in the debug-only diagnostics screen. Not changed |
| `grep -RnE "\.delete(<[^(]*)?\(" frontend/lib` | 2: the admin `deleteAdminEvent` (`/api/v1/events/$eventId`) and a Hive `_box?.delete` in the session store |
| `grep -Rn "/cancel" frontend/lib` | 1: the new call |
| `grep -Rn "GET /registrations\|/refund'" frontend/lib` | No refund-status call. ISSUE-005 is not started |

---

## 10. Remaining Risks

1. **A cancelled attendee who cannot register again is not told why.** The event page says "Unregistered from this event" whether the event is full, closed, or the account is not eligible. If the eligibility call fails, the page says the same and offers no Register button until it is reloaded.
2. **Manual verification has not been run.** Everything about real sign-in, the real backend and Razorpay rests on the automated tests and on reading the backend code.
3. **A paid cancel sends a real refund request to Razorpay.** In LIVE mode that is real money. The app does not warn about the mode before cancelling (ISSUE-017) and does not show the refund amount in the confirm dialog.
4. **ISSUE-005 remains pending.** After the snackbar closes, the app shows nothing about the refund. A `refund_pending` or `refund_failed` refund cannot be followed or checked in the app.
5. **ISSUE-011 remains pending.** An event that was cancelled and registered again has two cards on My Events, and registering again is now possible from the app, so this will be seen. Any status other than `registered` is labelled "Unregistered". On the event page `seat_held` and the `payment_*` statuses are as they were.
6. **ISSUE-012 remains pending.** The app hides Unregister once the registration window closes; the backend would still accept the cancel.
7. **ISSUE-018 remains pending.** If the reload after a successful cancel fails, My Events shows "Could not load registrations" with raw exception text. The cancel is still reported as cancelled.
8. **The idempotency key is kept in memory.** After a lost response followed by a page reload, the retry has a new key. The backend still cannot refund twice: the registration is already cancelled, and it returns the existing refund.
9. **The key is a timestamp, not a random value.** Two cancels of the same registration from two devices in the same millisecond would share a key. The backend treats that as one cancellation, which is the right outcome.
10. **The event list lookup changed for re-registered events.** Their card now shows the "Registered" badge and appears under "Registered by me", which it did not before. This is the intended effect of the change in section 3, but it is visible outside the cancel flow.
11. **The widget tests use the test font**, which is much wider than the app's. Each screen is tested at a window size where its layout fits. They do not check the layout at other sizes.
12. **Deploys are invisible to returning browsers for up to an hour** (ISSUE-022). Use a private window for the manual run.

---

## 11. Final Result

**CODE PASS — MANUAL E2E PENDING**

Automated verification passes (sections 4, 7 and 8). The manual run on beta has not been made (section 6).

---

## 12. Commit

Branch: `fix/issue-004`, from `main` at `e7267a2`. Nothing is committed to `main`.

Two commits, in this order:

```text
fix(cancellation): use canonical registration cancel API

ISSUE-004
```

```text
fix(cancellation): allow registering again after cancelling

ISSUE-004
```

The hashes are not written here. The branch is rebased onto `main` before merge (section 13), which changes them. The pull request shows the current hashes, and the merged ones go into the remediation plan after merge.

Pull request: `fix/issue-004` → `main`, titled "ISSUE-004: use canonical registration cancel API". It touches cancellation and refunds, so it needs Padmanand's approval. It is not to be merged before the manual run.

---

## 13. Before Merge

To be done by the maintainer, after the manual run on beta passes and the pull request is approved:

1. `git fetch origin && git rebase origin/main`
2. `git push --force-with-lease`
3. Redeploy to beta and check the cancel flow again.
4. Merge with "Create a merge commit", not squash.
5. Update `NITKSAA_EVENT_ISSUE_BY_ISSUE_REMEDIATION_PLAN.md`: ISSUE-004 status and commit hash. Record the manual results in section 6 of this report.

ISSUE-005 is branched from the updated `main` after this pull request merges. It has not been started.
