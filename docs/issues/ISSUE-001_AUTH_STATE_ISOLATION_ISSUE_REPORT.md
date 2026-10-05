# Task: Fix ISSUE-001 Only — Cross-User Event Data Survives Logout/Login

You are working on the NITKSAA-EVENT Flutter frontend.

Repository / app under test:

`nitksaa-rakshit/nitksaa-event/frontend`

Primary source documents:

- `NITKSAA_EVENT_FLUTTER_VERIFICATION_REPORT(1).md`
- `NITKSAA_EVENT_ISSUE_BY_ISSUE_REMEDIATION_PLAN.md`

Read both documents first, but for this task **fix ISSUE-001 only**.

Do not fix ISSUE-002 or any other issue in the same change.

---

# ISSUE-001

## Title

Logout → login as another user shows the previous user's event data.

## Severity

P0 / Critical privacy and state-isolation issue.

## Area

Authentication / Event Detail / Checkout

## Primary Root Cause Area

State management / Riverpod lifecycle

## Fix Location

NEW Flutter frontend only.

Do not modify backend behavior unless you discover that the existing report is factually wrong. The verification report states that the backend APIs are correctly scoped to the bearer token.

---

# Confirmed Problem

Current behavior:

1. User A logs in.
2. User A opens Event X.
3. User A's event-specific data is loaded:
   - eligibility
   - registration
   - badge / registration number
   - QR-related state
   - alumni profile
   - name
   - email
   - phone
4. User A logs out.
5. User B logs in in the same browser tab, without a full reload.
6. User B opens the same Event X.
7. The app can still render User A's data.

This is a P0 cross-user data exposure.

The existing analysis identifies these important causes:

- `eventDetailProvider(eventId)` is long-lived.
- It is not `autoDispose`.
- It is created/fetched once.
- `fetchEventDetails()` reads auth using `_ref.read(authControllerProvider)` rather than establishing a dependency on authenticated identity.
- Logout clears Hive/Firebase session but does not invalidate event-detail providers.
- There are no provider invalidations for this state.
- `EventDetailState.copyWith()` uses patterns such as:
  - `myRegistration ?? this.myRegistration`
  - `alumniProfile ?? this.alumniProfile`
  - `eligibilityStatus ?? this.eligibilityStatus`
- Therefore a legitimate new `null` result can fail to clear old User A state.
- Checkout may also reuse stale event-detail state and attempt to use User A's registration ID under User B's token.

The backend endpoints themselves are expected to return data scoped to the currently authenticated user:

- `GET /api/v1/events/{id}/registration-eligibility`
- `GET /api/v1/events/{id}/my-registration`
- `GET /api/v1/alumni/me`

Do not weaken backend authorization.

---

# Goal

After any authentication identity change, no user-specific event state belonging to the previous user may remain visible or actionable.

The required behavior is:

```text
User A
  ↓
View Event X
  ↓
Logout
  ↓
User-specific event state is discarded
  ↓
User B login
  ↓
Event X reloads using User B token
  ↓
Only User B eligibility / registration / profile is shown
```

A full browser refresh must NOT be required to achieve correct isolation.

---

# Scope

Fix only ISSUE-001.

Likely files to inspect include, but are not limited to:

- `lib/features/events/presentation/providers/event_detail_provider.dart`
- `lib/features/auth/.../auth_controller.dart`
- `lib/features/events/presentation/screens/event_detail_screen.dart`
- `lib/features/events/presentation/screens/checkout_screen.dart`
- related event-detail models/providers
- related tests

Inspect the actual current code before changing anything.

Do not assume the line numbers from the report are still exact.

---

# Required Analysis Before Editing

First inspect and document:

1. How `authControllerProvider` publishes authentication changes.
2. How `eventDetailProvider` is declared.
3. Whether it is currently:
   - `StateNotifierProvider.family`
   - `autoDispose`
   - watching auth
   - reading auth
4. How event-detail state is initialized and refreshed.
5. How logout changes auth state.
6. Whether any user-scoped event providers are invalidated on logout.
7. How `EventDetailState.copyWith()` handles clearing nullable fields.
8. How checkout obtains:
   - current registration
   - registration ID
   - auth token
9. Whether My Events already rebuilds correctly on auth changes.
10. Whether there are any other user-scoped providers with the same stale-state risk directly involved in Event Detail / Checkout.

Before editing, give a short root-cause summary.

---

# Fix Requirements

Implement a robust state-isolation solution.

## Requirement 1 — Event-detail state must depend on identity

Use an approach that guarantees event-specific user data is recreated or refreshed when the authenticated user changes.

Preferred direction:

- use `autoDispose` for per-event user-scoped provider state, and/or
- make the provider react to authenticated identity, and/or
- explicitly invalidate the correct providers when identity changes.

Choose the cleanest solution for the current architecture.

Do not add fragile manual hacks to individual screens if provider lifecycle can solve this centrally.

---

## Requirement 2 — Logout must eliminate prior user's state

After logout, these values must not remain available from the previous user:

- `myRegistration`
- `alumniProfile`
- `eligibilityStatus`
- eligibility message
- badge number
- QR-derived state
- attendee/profile data
- registration ID used by checkout
- any other user-specific event state

Public event information may remain cached if safe, but user-specific data must not.

---

## Requirement 3 — Null must be able to clear stale state

Fix the state-update semantics.

For example:

If User A has:

```text
myRegistration = Registration(...)
```

and User B's API returns:

```text
404 / no registration
```

the state must become:

```text
myRegistration = null
```

It must NOT retain User A's registration.

The same requirement applies to:

- alumni profile
- eligibility state/message
- any other nullable user-specific field

Do this cleanly.

Possible techniques include explicit sentinel/copy semantics or replacing the full user-specific portion of state rather than relying on `value ?? previousValue`.

Use the design that is most maintainable in this codebase.

---

## Requirement 4 — Checkout must never use stale registration

Before checkout/payment logic acts on an existing registration:

- it must belong to the current authenticated user/state
- it must be freshly resolved through the current provider/session
- stale registration ID from a previous user must not be reusable

Do not attempt to solve this by catching the backend 404 after the fact.

Prevent stale state from reaching checkout.

---

## Requirement 5 — No regression in public event data

Do not break:

- public event listing
- public event detail
- eligibility fetching
- registration fetching
- My Events
- checkout happy path
- session restore

---

# Tests Required

Add meaningful regression tests for ISSUE-001.

Do not stop at code changes.

At minimum, create tests covering:

## Test A — User switch clears registration

```text
User A authenticated
→ Event X loaded
→ A has registration
→ logout
→ User B authenticated
→ Event X loaded
→ B has no registration
→ state.myRegistration == null
```

Pass condition:

No User A registration survives.

---

## Test B — User switch clears alumni profile

```text
User A has alumni profile
→ logout
→ User B has no alumni profile / receives alumni-only failure
```

Pass condition:

A's profile is not retained.

---

## Test C — User switch refreshes eligibility

```text
A eligible
→ logout
→ B ineligible
```

Pass condition:

B's eligibility is shown.

A's eligibility must not remain.

---

## Test D — Same event ID

The regression test must use the same event ID for A and B.

The original bug is specifically about an already-created `eventDetailProvider(eventId)` instance surviving identity changes.

---

## Test E — Checkout safety

Simulate:

```text
A registration ID exists
→ logout
→ B login
→ B opens checkout/event flow
```

Pass condition:

A registration ID is never reused.

---

## Test F — Session restore regression

Confirm that normal same-user session restore still works.

---

# Static Verification

Run the appropriate project checks.

At minimum:

```bash
flutter analyze
flutter test
```

If the repository has targeted tests or scripts, run them too.

If `flutter analyze` already has unrelated known warnings/errors from the baseline, distinguish:

- pre-existing
- newly introduced

The ISSUE-001 fix must introduce no new analyzer errors.

---

# Manual Verification Plan

Do not claim runtime verification if you cannot actually perform authenticated two-user browser testing.

Prepare the exact manual test steps:

### Manual Two-User Test

1. Open deployed/local web app.
2. Login as User A.
3. Open Event X.
4. Capture:
   - eligibility
   - registration status
   - badge number if present
   - name/email/phone
5. Logout.
6. Do NOT refresh the page.
7. Login as User B.
8. Open the exact same Event X.
9. Verify:
   - no A registration
   - no A badge
   - no A QR
   - no A alumni profile
   - no A email
   - no A phone
   - B eligibility correct
10. Navigate to another event and back.
11. Repeat B → logout → A.
12. Repeat once with browser refresh to confirm normal state restoration.

If browser automation is available, run it.

If not, clearly mark manual runtime verification as pending and do not fabricate results.

---

# Test Report

Create:

`ISSUE-001_AUTH_STATE_ISOLATION_TEST_REPORT.md`

The report must contain:

```markdown
# ISSUE-001 Auth State Isolation Test Report

## 1. Issue
- ID
- severity
- area
- status

## 2. Root Cause
- provider lifecycle
- auth dependency
- nullable state retention
- checkout impact

## 3. Fix
- files changed
- architecture change
- why this approach was selected

## 4. Automated Verification

| Test | Expected | Actual | Result |
|---|---|---|---|

## 5. Manual / Runtime Verification

| Step | Expected | Actual | Result |
|---|---|---|---|

If manual verification is pending, say so explicitly.

## 6. Regression

- Dashboard
- Sign in
- Sign out
- Re-sign in
- View Events
- View Event
- My Events
- Register
- Checkout

## 7. Static Checks
- flutter analyze
- flutter test

## 8. Files Changed

## 9. Remaining Risks

## 10. Final Result

PASS / FAIL / CODE PASS — MANUAL E2E PENDING
```

---

# Commit Rules

Do not commit until:

- implementation is complete
- automated tests pass
- test report is generated
- diff is reviewed

Recommended commit message:

```text
fix(auth): isolate event state across user sessions

ISSUE-001
```

If manual E2E requires a human and cannot be executed in the current environment, do NOT falsely mark full E2E PASS.

In that case:

1. complete the code fix
2. complete automated verification
3. generate the test report
4. state `CODE PASS — MANUAL E2E PENDING`
5. show me the changes
6. do not commit unless I explicitly tell you to commit despite pending manual verification

If full runtime verification is possible and passes, then commit.

---

# Important Constraints

Do NOT fix any of these in this task:

- ISSUE-002 Google account chooser
- ISSUE-003 auth error messages
- ISSUE-004 cancellation
- ISSUE-005 refund
- ISSUE-006 quantity
- ISSUE-007 pricing
- ISSUE-008 payment retry
- ISSUE-009 Razorpay retry
- ISSUE-010 payment status
- ISSUE-011 My Events duplicate rendering
- ISSUE-012 cancellation policy
- ISSUE-013 alumni policy redesign
- ISSUE-014 admin RBAC
- ISSUE-015 admin APIs
- ISSUE-016 Razorpay mobile dependency
- ISSUE-017 TEST/LIVE handling
- ISSUE-018 friendly errors
- ISSUE-019 registration form
- ISSUE-020 QR/check-in
- ISSUE-021 routing
- ISSUE-022 web shell
- ISSUE-023 general cleanup

You may mention an adjacent issue if you encounter it, but do not fix it.

Avoid broad refactoring.

Do not modify backend schema or payment behavior for ISSUE-001.

Do not change unrelated UI.

Do not remove existing functionality.

---

# Final Response Format

When finished, respond with exactly these sections:

## ISSUE-001 Result

`PASS / FAIL / CODE PASS — MANUAL E2E PENDING`

## Root Cause Confirmed

Concise explanation.

## Fix Implemented

Files changed and what changed.

## Tests Added / Updated

List tests.

## Verification Results

Include exact `flutter analyze` and `flutter test` results.

## Manual E2E Status

State what was actually run.

## Test Report

Path to:

`ISSUE-001_AUTH_STATE_ISOLATION_TEST_REPORT.md`

## Git Diff Summary

Files changed and line-level intent.

## Commit

Commit hash + message, or explicitly say:

`Not committed — manual E2E pending`

## Next Issue

`ISSUE-002 — Google account chooser missing`

Do not start ISSUE-002.