# ISSUE-005 Refund Lifecycle Test Report

**Date:** 2026-10-10. Updated 2026-10-11 with the beta run (section 6).
**Application:** `nitksaa-event/frontend` (NEW Flutter app)
**Base commit:** `e68bddd` (branch `main`), which contains the ISSUE-004 merge (`578ec9c`) and its docs closure.
**Fix branch:** `fix/issue-005`
**Toolchain:** Flutter 3.44.2, Dart 3.12.2, `dio` 5.9.2, `go_router` 17.2.3, `flutter_riverpod` 2.6.1, Chrome 154 for the browser tests
**Final result:** CODE PASS — beta run reported passed; review pending

---

## 1. Issue

| Field | Value |
|---|---|
| ID | ISSUE-005 |
| Severity | P1 — Gate A blocker |
| Area | Refund / My Events |
| Status | Fixed on `fix/issue-005`. On beta since 2026-10-11 05:30 IST. The manual run was reported passed (section 6). Awaiting review. Not on the live site. |

After a paid registration was cancelled, the app showed one message and nothing more. The attendee could not see the refund's status, its amount, the backend's message, or check again later.

---

## 2. Root Cause

The full analysis is in `ISSUE-005_REFUND_LIFECYCLE.md`.

### The refund was thrown away

The cancel call returns a `RefundStatus`. `CancellationOutcome` chose a message from it, and both screens showed that message in a snackbar. Nothing kept or showed the refund itself.

### No refund status call

The app never requested `GET /api/v1/registrations/{registration_id}/refund`.

### `latest_order_id` was not read

`/my/registrations` returns `latest_order_id` on every row. `MyEventRegistration` did not parse it, so a cancelled card could not tell a paid registration from a free one.

### Nowhere to see it

A cancelled registration appears on My Events as a card tagged "Unregistered" with "View Details" only.

---

## 3. Fix

### Files Changed

| File | Change |
|---|---|
| `frontend/lib/features/events/data/events_repository.dart` (+16 −0) | New `getRefundStatus(registrationId, accessToken)` |
| `frontend/lib/features/events/domain/refund_status.dart` (+3 −0) | New `hasRefund` |
| `frontend/lib/features/events/domain/my_event_registration.dart` (+12 −0) | Reads `latest_order_id`; new `mayHaveRefund` |
| `frontend/lib/features/events/presentation/providers/refund_status_provider.dart` (new, 115 lines) | `RefundStatusState`, `RefundStatusNotifier`, `refundStatusProvider`, and the refund error messages |
| `frontend/lib/features/events/presentation/widgets/refund_status_dialog.dart` (new, 246 lines) | `RefundStatusDialog`, `showRefundStatus`, `viewRefundAction` |
| `frontend/lib/features/events/presentation/screens/my_events_screen.dart` (+36 −1) | "View refund status" on a cancelled card; "View refund" on the message after a cancel |
| `frontend/lib/features/events/presentation/screens/event_list_screen.dart` (+10 −1) | "View refund" on the message after a cancel |
| `frontend/test/features/events/refund_screens_test.dart` (new, 584 lines) | 23 tests on the real My Events and event list screens |
| `frontend/test/features/events/refund_api_test.dart` (new, 480 lines) | 20 tests on the repository, the provider, the messages and the model |
| `frontend/test/features/events/support/registration_backend_fake.dart` (+112 −22) | The fake backend extended with `GET /registrations/{id}/refund` and `latest_order_id` |
| `frontend/test/features/events/cancellation_screens_test.dart` (+4 −9) | One ISSUE-004 assertion updated (section 7) |
| `docs/issues/ISSUE-005_REFUND_LIFECYCLE.md` (new) | Issue analysis |
| `docs/issues/ISSUE-005_REFUND_LIFECYCLE_TEST_REPORT.md` (new) | This report |

No backend, auth, checkout or event page file is changed. `event_detail_provider.dart`, `cancellation_outcome.dart` and `my_events_provider.dart` are not changed. No package was added. `frontend/build/web` was rebuilt; it is git-ignored.

### Request

```text
GET /api/v1/registrations/{registration_id}/refund
Authorization: Bearer <access token>
```

No body. The answer is parsed with the `RefundStatus` model from ISSUE-004, which does not throw on nulls or on a status it does not know.

### Paid or free

`MyEventRegistration.latestOrderId` is read from `latest_order_id`. `mayHaveRefund` is true when the registration is `cancelled` and has one. Nothing else is asked of the backend to decide this.

### State

`refundStatusProvider(registrationId)` is an `autoDispose` family. It watches the session's access token the same way `eventDetailProvider` does, so logout, login and a change of user each build a new, empty notifier. The notifier keeps the token it was made with and ignores an answer that arrives after it was replaced.

The provider fetches nothing by itself. It has two entry points:

| Call | What it does |
|---|---|
| `check()` | One GET. Ignored while another is in flight |
| `show(refund)` | Takes a refund the app already has. Sends nothing |

### View

`RefundStatusDialog` is an `AlertDialog`, opened with `showRefundStatus`.

| `status` | Headline | Shown | "Check refund status" |
|---|---|---|---|
| `refund_pending` | "Refund in progress" | Amount, "Requested on", the backend's `safe_message` | Yes |
| `refund_processed` | "Refunded" | Amount, "Refunded on", `safe_message` | No |
| `refund_failed` | "Refund could not be completed" | Amount, `safe_message` | No |
| `none` | "No refund" | "No payment was taken, so there is nothing to refund." | No |
| anything else | "Refund status unavailable" | "We could not read the refund status. Please check again in a moment." | Yes |

One addition to the table in the task: the amount is also shown for a failed refund, because that is when an attendee most needs the figure.

| Failure | Message |
|---|---|
| `404 registration_not_found` | "We couldn't find this registration. Please refresh and try again." |
| No connection, timeout | "Unable to connect to the server. Check your internet connection and try again." |
| Anything else | "Could not load the refund status. Please try again." |

After a failure the view keeps what it was showing and offers "Check refund status". The mapping is in `refund_status_provider.dart` and is used by the refund status only. All colours come from the theme and `context.palette`.

### Where it opens from

| From | Opens with | Request |
|---|---|---|
| "View refund status" on a cancelled My Events card with `mayHaveRefund` | Nothing known | One GET |
| "View refund" on the message after a paid cancel, on My Events and on the event list | The refund the cancel returned | None |

The message after a cancel has the action only when the cancel returned a refund. A free cancel has no action.

### No polling

There is no timer. One request when the view opens from a card, and one for each press of "Check refund status".

### Change of user

When the session changes the provider is rebuilt empty, and an open refund view closes itself.

---

## 4. Automated Verification

Commands, from `frontend/`:

```bash
flutter test
flutter test test/features/events/refund_screens_test.dart \
  test/features/events/refund_api_test.dart
flutter test --platform chrome test/features/auth/ test/features/events/
```

How the tests are built:

- `MyEventsScreen`, `EventListScreen`, `RefundStatusDialog`, `RefundStatusNotifier`, `MyEventsNotifier` and `EventsRepository` are the real classes. The repository uses a real Dio client whose transport is the fake backend, so each test reads the method, path, token and body that would have gone on the wire.
- The fake backend follows `refund_service.get_refund_status`: the caller's own registration only (404 otherwise), the latest refund or `none`, and a fresh answer from the payment provider while the refund is pending. A test sets what "Razorpay now says", and the next refund status call returns it.
- Every registration row from the fake carries `latest_order_id`, null when no order was made.
- User changes are made the way ISSUE-001's tests make them: logout, then login as user B, in the same running app.

| Test | Expected | Actual | Result |
|---|---|---|---|
| Correct request (A) | One `GET /api/v1/registrations/{id}/refund`; `Authorization: Bearer <token>`; empty body; no request other than GET | As expected | PASS |
| Pending (B) | "Refund in progress", `₹123.45`, "Requested on" with a date and time, the backend's message, "Check refund status" | As expected | PASS |
| Check status transitions (C) | Pending; "Razorpay" then reports processed; press "Check refund status"; a second GET; "Refunded"; no check button left | As expected | PASS |
| Processed (D) | "Refunded", `₹499`, "Refunded on", the backend's message; no check button | As expected | PASS |
| Failed (E) | "Refund could not be completed" and the backend's message; no "Retry", "Try again" or "Check refund status" | As expected | PASS |
| None / free (F) | A cancelled free registration has no "View refund status" and causes no request. A cancelled registration with an unpaid order opens to "No refund" and "No payment was taken, so there is nothing to refund." | As expected | PASS |
| After cancel (G) | The message after a paid cancel has "View refund". Pressing it shows "Refund in progress" and the amount from the cancel response, with no refund status request, although the fake would by then answer "processed". Pressing "Check refund status" then sends one. A free cancel has no "View refund" | As expected, from My Events and from the event list | PASS |
| Lazy fetch (H) | My Events with three cancelled paid registrations sends no refund request. Opening one sends one, for that registration | As expected | PASS |
| Errors (I) | 404, no connection and 500 give the three fixed messages; no exception text, status code or backend code on screen; the check works once the connection is back; a failed check keeps the refund already shown | As expected | PASS |
| User isolation (J) | User A has the refund view open; logout; login as B: the view is gone, A's amount and message are not on screen, and no request after the switch carries A's token. An answer for A that arrives after the switch is not shown | As expected, on the screen and at the provider | PASS |
| Repeat safety (K) | Three presses of "Check refund status" send three GETs; a second check while one is in flight is ignored; no request other than GET is ever sent; no refund is created | As expected | PASS |
| Regression (L) | All existing ISSUE-001/002/003/004/006 tests pass on the VM and in Chrome | 168 of 168 and 181 of 181 | PASS |

Also covered, beyond the list in the task:

| Check | Result |
|---|---|
| No polling: a pending refund left open for five minutes is asked about once | PASS |
| Closing the view and opening it again asks again | PASS |
| A registered registration, and one whose payment failed, have no refund action | PASS |
| After a paid cancel the My Events card gains "View refund status" | PASS |
| The provider fetches nothing until asked, and its state is discarded when the view closes | PASS |
| Signed out: nothing is sent | PASS |
| For every Dio error type and for 401, 403, 404, 422, 500 and 502 responses, the message is one of the three fixed ones | PASS |
| A status the app does not know is kept and does not throw | PASS |
| `latest_order_id` reaches `MyEventRegistration` through the repository, and listing registrations sends no refund request | PASS |

### Totals

| | Before ISSUE-005 (`e68bddd`) | After ISSUE-005 |
|---|---|---|
| `flutter test` (VM) | 168 of 168 | 211 of 211 |
| Chrome, `test/features/auth/` and `test/features/events/` | 181 of 181 | 224 of 224 |

New tests: 43 on the VM and 43 in Chrome. All of them run on both.

### The same tests against the code before the fix

The new tests and the extended fake were copied into an untouched checkout of `e68bddd`.

| | Fail | Pass | Could not run |
|---|---:|---:|---:|
| VM, `refund_screens_test.dart`, 23 tests | 19 | 4 | |
| VM, `refund_api_test.dart`, 20 tests | | | 20 |
| Chrome, `refund_screens_test.dart`, 23 tests | 19 | 4 | |

`refund_api_test.dart` does not compile against the old code: `refund_status_provider.dart`, `getRefundStatus`, `hasRefund` and `latestOrderId` did not exist. It was not run in Chrome against the old code.

The four screen tests that pass before the fix are the ones that say a refund action must be absent: for a cancelled free registration, for a registered or payment-pending one, and on the message after a free cancel from each screen. The old code had no refund action anywhere, so they were true already.

What the old code did in the nineteen that fail:

| Observed before the fix | |
|---|---|
| Cancelled paid card on My Events | No "View refund status". Nothing to press |
| Message after a paid cancel | No "View refund" action |
| Refund status requests | None, in any test |

### Two changes that must make the tests fail

Each was made by hand, run, and undone.

| Change to the fix | Tests that then fail |
|---|---|
| The view always asks the backend when it opens, even with a refund in hand | Test G, from My Events and from the event list |
| The provider reads the token once and does not watch the session | All four Test J tests, on the screen and at the provider |

---

## 5. Contract Verification

The backend is not changed. The refund status contract was read from `backend/` at `e68bddd`, and from the live API's OpenAPI document (`https://nitksaa-events-api-246773894709.asia-south1.run.app/openapi.json`) as read on 2026-10-10, without signing in.

| Where | Finding | Evidence |
|---|---|---|
| Route | `GET /api/v1/registrations/{registration_id}/refund`, bearer token required, no request body | `refunds.py:34-42`. The live OpenAPI document lists `get` only, with `HTTPBearer` and no request body |
| Response | `RefundStatusResponse`, the same ten fields the cancel call returns | `payments.py:129-142` |
| Ownership | Not found and not owned give the same `404 registration_not_found` | `refund_service.py:88-95` |
| No refund | `status: none`, with the "nothing to refund" message | `refund_service.py:304-312`, `:67-71` |
| Refresh | For an internal `pending` or `processing` refund the backend asks the gateway and stores a change before answering. A gateway error is swallowed and the stored refund is returned | `refund_service.py:273-301` |
| Client status | Internal `pending` and `processing` are both `refund_pending` | `refund_service.py:44-49` |
| `latest_order_id` | On every row of `GET /my/registrations` and on `GET /events/{id}/my-registration`: the newest order's public number, whatever its status, or null | `registrations.py:56-66, 87`; `registration_repository.py:54-56`; `registration_service.py:71`. In the live schema, `MyRegistrationsListResponse.registrations` is a list of `RegistrationResponse`, which has the field |
| Expired holds | A seat hold that ran out is set to `cancelled` | `registration_repository.py:123-136` |

The contract matches the task description. One thing the task does not mention is the last row: a `cancelled` registration with an order is not always a paid one. It is handled, and described in section 10.

---

## 6. Manual Verification

**Result: passed, as reported by the tester.** The report was the one word "passed", with one screenshot and no result for each step. The table of steps below therefore gives what is on record for each one: the screenshot, and the backend's request log for the same minutes. A step with nothing on record is marked NOT REPORTED, and a step the record shows could not have been run is marked NOT RUN.

| Field | Value |
|---|---|
| Site | `https://nitksaa-events-beta.web.app`, in an Incognito window |
| Build tested | `f9da077`, deployed to beta on 2026-10-11 at 05:30 IST with `firebase deploy --only hosting:beta` |
| Before the deploy | `flutter pub get`, then `flutter test`: 211 of 211 |
| Beta bundle | After the deploy, beta served `main.dart.js` with SHA-256 `b7f8557d77127f19613bc58e8e643a61c1c43d2383c40c8e8ebf648133b423eb`, the same as the local build of `f9da077` (section 8) |
| Run | 2026-10-11, about 05:33 to 05:36 IST |
| Reported | 2026-10-11: "passed", and one screenshot taken at about 05:34 IST |
| Live site | Not deployed from this branch. Its `main.dart.js` had the same SHA-256 before and after the beta deploy (`dd76aba1…e377`) |

Beta and live share one backend, so the cancellation in this run is a real backend record.

### What the screenshot shows

- The beta site at `/#/my-events`, with DevTools → Network filtered by "refund": 1 request of 86.
- That request: `GET …/api/v1/registrations/52/refund`, status 200, answered at 05:34:32 IST.
- The refund view: "Refunded", "Amount: ₹1", "Refunded on: 11 Oct 2026, 5:34 AM", "Your cancellation is confirmed and the refund has been processed by the payment provider.", and "Close". No "Check refund status".
- Behind it, My Events cards for "TestOct8" tagged "Unregistered".
- At the bottom of the page, the message "Your registration is cancelled, but the refund could not be completed automatically. Our team will follow up." with the action "View refund".

### What the backend's request log shows

All requests to `/api/v1/registrations/…` between 05:25 and 05:38 IST:

| Time (IST) | Request | Status | Note |
|---|---|---|---|
| 05:33:35 | `POST /registrations/8/cancel` | 200 | The backend's own log one second later: the refund call to Razorpay failed with `BAD_REQUEST_ERROR`. The registration is cancelled and its refund is recorded as failed |
| 05:34:32 | `GET /registrations/52/refund` | 200 | The request in the screenshot |
| 05:36:00, 05:36:05, 05:36:10 | `GET /registrations/52/refund` | 200 | Three more, each one opening of the view |

The message at the bottom of the screenshot belongs to the cancel of registration 8. The refund view belongs to registration 52. They are two registrations.

### Steps

| # | Step | Expected | On record | Result |
|---|---|---|---|---|
| 1 | Incognito → beta → sign in → Network, filter "refund" | | The screenshot shows exactly this | Done |
| 2 | My Events, without opening anything | No `/refund` request | The Network panel holds one `/refund` request, the one of step 3. The backend log has none before it | PASS |
| 3 | TestOct8 (cancelled, paid) → "View refund status" | One `GET /registrations/14/refund`, 200; "Refund in progress" or "Refunded", ₹1 | Run on registration 52, not 14: one GET, 200, "Refunded", ₹1. Registration 14 was not asked about | PASS, on registration 52 |
| 4 | If pending: "Check refund status" | One more GET | Registration 52 answered "Refunded" at once, so the button was never offered. The three later GETs are the view being opened again | NOT RUN |
| 5 | Unregister a paid TEST registration → "View refund" on the message opens the view with no extra GET | | Registration 8 was cancelled. The message with "View refund" is in the screenshot. Its refund failed at Razorpay, so the view would have shown "Refund could not be completed". Whether "View refund" was pressed is not on record; the backend log has no refund request for registration 8, which is what pressing it should cause | Cancel and message: shown. Pressing "View refund": NOT REPORTED |
| 6 | A free cancelled registration shows no "View refund status" | | Nothing on record | NOT REPORTED |

Not covered by this run: a pending refund and "Check refund status" (step 4), the view opened from the message after a cancel (step 5), a free cancelled registration (step 6), a change of user, and the wrong-user request. They rest on the automated tests.

### Found in this run

1. **The message after a paid cancel does not go away by itself.** It was still on screen about a minute after the cancel. In this Flutter version a snackbar that has an action stays until the action is pressed or the bar is swiped away (`SnackBar.persist` defaults to true when there is an action). ISSUE-004's message had no action and closed after four seconds; adding "View refund" in this issue changed that. It is a defect of this change. A fix (`persist: false`, a set duration, and a test) is proposed and not yet made; making it means a new build on beta and a re-check of step 5.
2. **The refund of registration 8 failed at Razorpay** with `BAD_REQUEST_ERROR`. The log holds the code and not Razorpay's reason. The app showed the backend's message for a failed refund, as designed. The message says "Our team will follow up", and the backend has no way to retry a failed refund, so this one needs a person.
3. **"Refunded on" is the time the backend learned of the refund.** For registration 52 it equals the time of the first status request, to the minute. The backend sets `finalized_at` when it marks a refund processed, and for a pending refund that happens when a status request makes it ask Razorpay. An attendee who first looks days later would see that later date. The app shows the backend's value as it is.

---

## 7. ISSUE-001/002/003/004/006 Regression

### One ISSUE-004 assertion was changed

`cancellation_screens_test.dart`, Test E, which runs once for each Unregister button. In ISSUE-004 it ended by checking that the message was the only text on screen mentioning a refund, with the comment "The refund status page is ISSUE-005". This issue adds that page, so the check is now that the message offers "View refund". The rest of the test is as it was: the refund message, the cancelled registration, one refund made, and no active registration left on screen. The test's title lost the words "with no other refund UI".

No other existing test was edited. The shared fake backend gained the refund status route and `latest_order_id`; its cancel behaviour is the same.

### ISSUE-001 — PASS (automated)

- `event_detail_auth_isolation_test.dart`: 18 of 18 on the VM and in Chrome.
- `checkout_auth_isolation_test.dart`: 1 of 1 in Chrome.
- `event_detail_provider.dart` is not changed. The new provider is built on the same pattern, and Test J checks it.

### ISSUE-002 — PASS (automated)

- `google_sign_in_account_chooser_test.dart`: 1 of 1 on the VM, 3 of 3 in Chrome.
- `google_login_flow_test.dart`: 5 of 5 in Chrome.
- `prompt=select_account` is preserved: `firebase_auth_service.dart:58` still sets it, and the release bundle contains `select_account`.

### ISSUE-003 — PASS (automated)

- `backend_auth_exception_test.dart`: 27 of 27 on the VM and in Chrome.
- `auth_error_messages_test.dart`: 22 of 22 on the VM and in Chrome.
- `login_failure_rollback_test.dart`: 26 of 26 on the VM, 27 of 27 in Chrome.
- No file under `frontend/lib/features/auth/` is changed.

### ISSUE-004 — PASS (automated)

- `cancellation_api_test.dart`: 26 of 26 on the VM and in Chrome.
- `cancellation_screens_test.dart`: 29 of 29 on the VM and in Chrome, with the one assertion above changed.
- `cancellation_source_test.dart`: 3 of 3 on the VM.
- `cancellation_reregister_checkout_test.dart`: 2 of 2 in Chrome.
- The cancel request, the idempotency key and `CancellationOutcome` are not changed: `my_events_provider.dart` and `cancellation_outcome.dart` have no diff. The re-register branch of `event_detail_screen.dart` has no diff. The release bundle still contains `/cancel` and "You cancelled your earlier registration.".

### ISSUE-006 — PASS (automated)

- `registration_quantity_test.dart`: 9 of 9 on the VM and in Chrome.
- `registration_quantity_source_test.dart`: 6 of 6 on the VM.
- `checkout_single_registration_test.dart`: 12 of 12 in Chrome.
- `registerForEvent` still sends `{"attendee_note": …}` only. The release bundle does not contain `quantity=`.

### PR #2 UI

Nothing is restyled. One button was added to the cancelled card, in the row and style of the existing Unregister button. The message after a cancel gained an action. `bash frontend/tool/check_colors.sh` reports `check_colors: OK`.

---

## 8. Static Checks

### flutter test

```bash
flutter test
```

Result: 211 of 211. (168 before this change.)

ISSUE-005 tests alone: 43 of 43.

### Chrome tests

```bash
flutter test --platform chrome test/features/auth/ test/features/events/
```

Result: 224 of 224. (181 before this change.)

### flutter analyze

Measured fresh on `e68bddd`.

| | Total | Errors | Warnings | Info |
|---|---:|---:|---:|---:|
| Before ISSUE-005 (`e68bddd`) | 75 | 6 | 32 | 37 |
| After ISSUE-005 | 75 | 6 | 32 | 37 |

- **Pre-existing issues:** all 75. The two lists are identical when line numbers are ignored. `flutter analyze` exits with code 1 before and after: the 6 errors are in `razorpay_payment_io.dart` and come from the missing `razorpay_flutter` package (ISSUE-016), which was left alone.
- **New ISSUE-005 issues:** none. No finding is in any new file.

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
| `/refund` | Present five times: once as `"/api/v1/registrations/"+a+"/refund"`, the new call, and four times as the route of the existing Refund Policy page |
| `/cancel` | Present once |
| `select_account` | Present once |
| `idempotency_key` | Present twice |
| `latest_order_id` | Present once |
| "View refund status", "Check refund status", "Refund in progress" | Each present once |
| `my-registration` | Present once, the `GET` |
| `"DELETE"` | Present once, the admin delete-event call |
| "You cancelled your earlier registration." | Present once |
| `quantity=` | Absent |
| Production backend URL | Present |
| SHA-256 | `b7f8557d77127f19613bc58e8e643a61c1c43d2383c40c8e8ebf648133b423eb` |
| Deployed | No |

---

## 9. Source Search

Run from the repository root after the fix.

| Search | Matches |
|---|---|
| `grep -Rn "getRefundStatus" frontend/lib` | 2: its definition in `events_repository.dart` and its one call, in `RefundStatusNotifier.check` |
| `grep -Rn "showRefundStatus(\|viewRefundAction(" frontend/lib` | The two definitions, one call from the My Events card, and one `viewRefundAction` call in each of the two screens |
| `grep -nE "Timer\|periodic\|Future.delayed"` in the two new files | None |
| `grep -n "Color(0x"` in the two new files | None |
| `grep -n "paymentMode\|realMoney"` in `refund_status_dialog.dart` | None. No TEST or LIVE wording is shown |
| `git diff --stat` for `backend/`, `lib/features/auth/`, `event_detail_provider.dart`, `event_detail_screen.dart`, `checkout_screen.dart`, `cancellation_outcome.dart`, `my_events_provider.dart` | No change |

---

## 10. Remaining Risks

1. **A seat hold that ran out gets a refund action it does not need.** The backend marks an expired hold `cancelled`, and it has a `latest_order_id` because the attendee reached payment. Its My Events card shows "View refund status"; the view says "No refund. No payment was taken, so there is nothing to refund." The answer is right, but the action should not be there. The app cannot tell this case from a paid cancellation without the order's status, which the row does not carry. A fix needs ISSUE-011's status labels or a backend field.
2. **The manual run covered part of the plan.** One refund view, of a processed refund, and one paid cancel were seen on beta. A pending refund, the view opened from the message, a free registration, a change of user and the wrong-user request were not (section 6).
3. **The refund status of registration 14 is not known.** It was cancelled on 2026-10-10 and was not asked about in the run. Registration 8's refund failed at Razorpay and needs a person to follow up.
4. **The message after a paid cancel stays on screen until it is pressed or swiped away.** Found in the beta run (section 6). It was meant to close by itself after a few seconds, and it is not fixed yet. Once it is gone, the route to the refund is the cancelled card on My Events; from the event list that means going to My Events.
5. **A failed refund has no next step in the app.** The view shows the backend's message, "Our team will follow up." There is no retry and no contact link, because the backend has no retry API.
6. **No TEST or LIVE indication** (ISSUE-017). A refund of real money and a TEST refund look the same.
7. **The event page says nothing about a refund.** It was left out to keep this change away from `eventDetailProvider`.
8. **ISSUE-011 remains pending.** A cancelled registration is still labelled "Unregistered", and an event that was cancelled and registered again has two cards.
9. **ISSUE-018 remains pending.** The refund messages are a third local copy of the connection wording.
10. **The refund view closes on any change of the session token.** If the app ever renews the token of the same user while the view is open, it will close and can be opened again.
11. **The widget tests use the test font.** They do not check the layout of the card's new button at phone width. The label is in a `FittedBox`, so that it shrinks to stay on one line where the card is narrow; how that looks on a small phone has not been seen.
12. **Deploys are invisible to returning browsers for up to an hour** (ISSUE-022). Use a private window for the manual run.

---

## 11. Final Result

**CODE PASS — beta run reported passed; review pending**

Automated verification passes (sections 4, 7 and 8). A manual run on beta was made on 2026-10-11 and reported passed; it covered part of the plan and found one defect that is still open (section 6). The pull request awaits review.

---

## 12. Commit

Branch: `fix/issue-005`, from `main` at `e68bddd`. Nothing is committed to `main`.

Commit message:

```text
feat(refund): add attendee refund lifecycle

ISSUE-005
```

The hash is not written here, because a rebase before merge (section 13) would change it. The pull request shows the current hash, and the merged hash goes into the remediation plan after merge.

Pull request: `fix/issue-005` → `main`, titled "ISSUE-005: add attendee refund lifecycle". It touches refunds, so it needs Padmanand's approval. It is not to be merged before the manual run.

---

## 13. Before Merge

To be done by the maintainer, after the manual run on beta passes and the pull request is approved:

1. `git fetch origin && git rebase origin/main`
2. `git push --force-with-lease`
3. Redeploy to beta and check the refund view again.
4. Merge with "Create a merge commit", not squash.
5. In a small docs-only pull request: record the manual results in section 6 of this report, and mark ISSUE-005 DONE with the merge commit hash in `NITKSAA_EVENT_ISSUE_BY_ISSUE_REMEDIATION_PLAN.md`.

Steps 1 to 3 are needed only if `main` has moved since `e68bddd`.

The next issue is ISSUE-008. It has not been started.
