# ISSUE-012 — Unregister Hidden Once Registration Closes

## Severity

P2 — Cancellation

## Status

Fixed on `fix/issue-012`, from `main` at `0f3b48f` (contains PR #56, guests). Code and automated tests pass. Not yet on beta; the manual run on beta is PENDING. Touches cancellation, so it needs Padmanand's approval. Not on the live site.

---

## Gap

The app hid Unregister as soon as the event's registration window closed. Registration usually closes days before the event, so an attendee who could no longer come had no way to cancel (or get their refund) from the app, though the backend would have done both.

`frontend/lib/features/events/domain/my_event_registration.dart`, before the fix:

```dart
bool get canCancel =>
    isActive && publicEvent?.registrationStatus.toLowerCase() == 'open';
```

The rule had a second effect: an event whose window was still `open` after it started (or ended) kept offering Unregister.

---

## Root Cause

The registration window (`registration_status`, `registration_closes_at`) decides who may **register**. The app reused it to decide who may **cancel**, a rule the backend does not have.

### Where Unregister is offered (on `0f3b48f`)

| Entry point | What it cancels | Condition before the fix | After |
|---|---|---|---|
| My Events card (`my_events_screen.dart`, `_registrationCard`) | The whole registration (with its guests) | `registration.canCancel` | `registration.canCancel` (new rule) |
| Event list card, "Registered by me" or not (`event_list_screen.dart`, card grid) | The whole registration | `registered && registration!.canCancel` | Same expression, new rule |
| Event list, table view | — | No Unregister | Unchanged |
| Event page (`event_detail_screen.dart`) | — | No whole-registration Unregister | Unchanged |
| Event page, guest list ✕ (`_buildGuestsSection`, from #56) | One guest | `guest.isActive`, shown while the head registration is `registered` | Unchanged (see Scope) |

Both whole-registration entry points go through `confirmAndUnregister` (`widgets/unregister_flow.dart`), which calls `MyEventsNotifier.cancelRegistration` → `POST /api/v1/registrations/{id}/cancel`. The guest ✕ goes through `confirmAndCancelGuest` → the same endpoint with the guest's registration id.

### How the app decides "started" and "past"

- `RegisteredEventSummary.startDatetime` (the `event` object of each `GET /my/registrations` row) and `AppEvent.startDatetime` (public event) are both parsed with `DateTime.parse(...).toLocal()`. The backend columns are `TIMESTAMPTZ`, so the strings carry an offset and Dart compares them as instants; the attendee's time zone does not matter.
- "Past" elsewhere in the app: `eventEnded()` (`event_list_controls.dart`, end or start before now), `MyEventEntry.isUpcoming` (end after now; no dates counts as upcoming), and `isPastEvent` on the event page. None of them is "started".

### When the backend refuses

`CancellationOutcome` (not `apiErrorMessage`) turns a refusal into a fixed message; no exception text, status code or backend code reaches the attendee. On a refusal the list is not reloaded, so the card stays as it was.

| Backend `detail` | Message |
|---|---|
| `registration_not_cancellable` (409) | "This registration can't be cancelled while payment is in progress." |
| `registration_not_found` (404) | "We couldn't find this registration. Please refresh and try again." |
| `no_captured_payment`, `refund_not_supported`, `refund_mode_mismatch` (409) | "We couldn't cancel this registration automatically. Please contact support." |
| No connection | "Unable to connect to the server. Check your internet connection and try again." |
| Anything else | "Could not cancel your registration. Please try again." |

---

## Backend Rule

`backend/app/services/refund_service.py`, `cancel_registration`, in order:

1. The registration must be the caller's (404 `registration_not_found` otherwise).
2. `cancelled` → 200, the existing refund view (idempotent).
3. Any status other than `registered` → 409 `registration_not_cancellable` (`seat_held`, `payment_pending`, `payment_verification`, `payment_failed`).
4. No paid order on the group head's row → cancel, no refund.
5. Paid → one refund for the captured payment: the whole remaining amount for the head, one person's share for a guest.

There is **no time check**: nothing reads the event's start, end, `registration_status` or `registration_closes_at`. The only `datetime` use in the file is the refund retry window.

Guests (#56, migration `031_guests.sql`): every person has their own `registrations` row, with the head's id in `group_head_id`. Cancelling the head cancels its guests through the trigger `registrations_follow_group_head`; a guest can be cancelled alone. A lapsed seat hold ends as `cancelled`; there is no `expired` registration status.

---

## Fix

One rule, in the model, used by both whole-registration entry points without changing them:

```dart
bool get canCancel => canCancelAt(DateTime.now());

bool canCancelAt(DateTime now) {
  if (!isActive) return false;
  final start = event?.startDatetime ?? publicEvent?.startDatetime;
  // Without a start time, leave it to the backend.
  return start == null || start.isAfter(now);
}
```

- Offered: a `registered` registration whose event has not started, whether the registration window is open or closed.
- Not offered: the event has started or ended; any status other than `registered` (unchanged).
- The start comes from the registration row's `event` (always present: `list_for_user` joins `events`), with the public event as a fallback. With neither, the button is shown and the backend decides, as `MyEventEntry.isUpcoming` treats an event without dates.
- `canCancelAt` takes the time, so the rule is unit-tested with a fixed clock.
- A refusal shows the existing `CancellationOutcome` message. No new text, no restyling, no colours, no backend change.

---

## Files

| File | Change |
|---|---|
| `frontend/lib/features/events/domain/my_event_registration.dart` | `canCancel` rule replaced; `canCancelAt(now)` added |
| `frontend/test/features/events/cancellation_policy_test.dart` | New: the rule at a fixed time (17 tests) |
| `frontend/test/features/events/cancellation_policy_screens_test.dart` | New: My Events and the event list card (22 tests) |
| `frontend/test/features/events/support/registration_backend_fake.dart` | The fake event's `registration_status`, start and end can be set; defaults unchanged |
| `docs/issues/ISSUE-012_CANCELLATION_POLICY.md`, `..._TEST_REPORT.md` | New |

`my_events_screen.dart`, `event_list_screen.dart`, `unregister_flow.dart`, `cancellation_outcome.dart`, `event_detail_screen.dart` and `backend/` are unchanged.

---

## Scope

Fixed: ISSUE-012 only.

Not changed, reported here:

1. **Guest ✕ on the event page has a different rule.** It has no registration-window rule and no time rule: it is shown for every active guest while the head is `registered`, also after the event has started or ended. Per the task it was left alone. To match, the condition would become `guest.isActive && <event not started>`.
2. **The start-time cut-off is the app's, not the backend's.** The backend still accepts a cancel (with a full refund) after the event starts, e.g. from an old tab or a direct API call. If "no cancelling once it has started" is the policy, the backend should enforce it too; that is a backend change and out of scope.
3. **ISSUE-006 Test K fails in Chrome on `main`** (`checkout_single_registration_test.dart`, "the backend's refusal of a duplicate is shown"). It expects the text "Registration failed", which left the app in `3f0a221` (#37, 14 Oct). It runs only in Chrome, so `flutter test` on the VM does not show it. Unrelated to this change; it fails the same way without it. Fixed separately in `fix/test-006-k`.
4. ISSUE-010, -011, -017, -018 and -021, and the checkout page, are untouched.

---

## Status

CODE PASS — MANUAL E2E PENDING. See `ISSUE-012_CANCELLATION_POLICY_TEST_REPORT.md`.
