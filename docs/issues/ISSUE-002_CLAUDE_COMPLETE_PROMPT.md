# Claude Task — Fix ISSUE-002 Only: Google Account Chooser Missing After Logout

## Repository

You are working on the NITKSAA-EVENT Flutter frontend.

Repository:

`/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-rakshit/nitksaa-event`

Frontend:

`/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-rakshit/nitksaa-event/frontend`

Issue/report directory — IMPORTANT:

`/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-rakshit/nitksaa-event/docs/issues`

Use lowercase `docs/issues`.

Before editing, review:

- `NITKSAA_EVENT_FLUTTER_VERIFICATION_REPORT(1).md`
- `NITKSAA_EVENT_ISSUE_BY_ISSUE_REMEDIATION_PLAN.md`
- the current ISSUE-001 changes already present in the working tree

Do NOT undo or modify the ISSUE-001 fix unless strictly necessary for compilation.

Fix **ISSUE-002 only**.

Do not start ISSUE-003 or any other issue.

---

# ISSUE-002

## Title

Google web sign-in does not force account selection after logout.

## Severity

P1

## Area

Authentication / Firebase Auth / Google Sign-In

## Problem

Current manual behavior:

```text
User A signs in with Google
→ User A logs out from NITKSAA
→ user clicks Sign in with Google again
→ Google silently signs User A back in
→ account chooser is not shown
```

This blocks proper User A → User B switching and also blocks the manual E2E verification of ISSUE-001.

The verification report identified that:

- Firebase sign-out is performed.
- The Google browser session remains, which is normal browser/Firebase behavior.
- The NEW Flutter app does not force Google account selection.
- The reference payment app uses `prompt: select_account`.
- Therefore the previous Google account is often silently reused.

Expected behavior:

```text
User A login
→ Logout
→ Click Sign in with Google
→ Google account chooser appears
→ User can select User B
→ backend session belongs to User B
```

---

# Required Analysis Before Editing

Inspect the current implementation first.

Focus on:

- `firebase_auth_service.dart`
- Google sign-in initialization/configuration
- web-specific auth code
- logout implementation
- Firebase Auth sign-out
- Google Sign-In behavior on web
- any current Google provider parameters
- the reference payment app implementation

Before modifying code, report:

1. Current Google sign-in flow.
2. Current logout flow.
3. Whether `GoogleAuthProvider` or `GoogleSignIn` is used on web.
4. Whether any custom parameters are configured.
5. How the reference app forces account selection.
6. Why the current app reuses the previous account.
7. Whether the required fix is web-only or affects mobile too.

Do not guess. Inspect actual code.

---

# Required Fix

Implement the smallest correct change that forces Google account selection on web.

The expected direction is equivalent to:

```text
prompt=select_account
```

Use the correct API supported by the current Firebase/Google Sign-In implementation.

Examples may include provider custom parameters such as:

```dart
provider.setCustomParameters({
  'prompt': 'select_account',
});
```

or the appropriate current API for the package/version actually used.

Do not blindly paste this if the current code uses a different auth path.

Verify the correct implementation for the current codebase.

---

# Functional Requirements

## Requirement 1 — Account Chooser Must Appear

After logout, clicking Google Sign-In must present the Google account chooser instead of silently reusing the previous account.

## Requirement 2 — User Can Switch Accounts

This must work:

```text
User A
→ logout
→ Google Sign-In
→ choose User B
→ backend auth session becomes User B
```

## Requirement 3 — Do Not Break Normal First Login

Fresh Google login should continue to work.

## Requirement 4 — Do Not Break Logout

Existing logout must still:

- clear backend/Hive session
- call Firebase sign-out
- return app to unauthenticated state

Do not add broad logout changes unless necessary.

## Requirement 5 — Preserve ISSUE-001 Fix

The current working-tree ISSUE-001 state isolation fix must remain intact.

Do not refactor the event-detail provider as part of ISSUE-002.

## Requirement 6 — Platform Safety

If the change is web-specific, ensure:

- web compiles
- non-web code is not broken
- mobile behavior is unchanged unless explicitly required

---

# Tests Required

Add focused regression tests where practical.

At minimum validate:

## Test A — Google Provider Configuration

Verify the web Google provider contains:

```text
prompt = select_account
```

or equivalent behavior.

## Test B — Existing Auth Flow Unchanged

Successful Google auth still:

```text
Google/Firebase credential
→ Firebase user
→ Firebase ID token
→ POST /api/v1/auth/firebase
→ GET /api/v1/auth/me
→ authenticated session
```

## Test C — Logout Still Clears App Session

Verify existing logout behavior is not regressed.

## Test D — ISSUE-001 Regression

Run the ISSUE-001 auth-isolation tests already present.

They must still pass.

---

# Static Verification

Run:

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-rakshit/nitksaa-event/frontend

flutter test
```

Also run:

```bash
flutter analyze
```

The repository currently has known analyzer failures related to ISSUE-016 / missing `razorpay_flutter`.

Do not fix ISSUE-016.

Report clearly:

- baseline analyzer result
- post-fix analyzer result
- whether ISSUE-002 introduced any new errors/warnings

Also run the relevant Chrome/web test if appropriate.

---

# Manual E2E Verification

This issue requires actual browser verification.

Run locally or deploy to Firebase Hosting if browser automation/environment allows it.

Recommended deployed build:

```bash
cd /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-rakshit/nitksaa-event/frontend

flutter build web --release \
  --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app

firebase deploy --only hosting:events
```

Then test:

`https://nitksaa-events.web.app`

## Manual Test 1 — Account Chooser

1. Login using Google Account A.
2. Confirm account A is signed into NITKSAA.
3. Logout.
4. Do NOT refresh the browser.
5. Click Google Sign-In.
6. Confirm the Google account chooser appears.
7. Select Account B.
8. Confirm NITKSAA logs in as B.

Expected:

**Google must not silently sign A back in.**

## Manual Test 2 — ISSUE-001 Combined Regression

Because ISSUE-002 currently blocks ISSUE-001 manual verification, perform this immediately after Manual Test 1:

1. Login as User A.
2. Open Event X.
3. Record A's:
   - registration state
   - badge number if available
   - eligibility
   - alumni/profile values
4. Logout.
5. Do NOT refresh.
6. Sign in with Google.
7. Account chooser must appear.
8. Select User B.
9. Open the same Event X.
10. Confirm:
   - no A registration
   - no A badge
   - no A QR
   - no A name/email/phone
   - B's eligibility is correct
11. Repeat B → A if practical.

If this passes, record that ISSUE-001 manual E2E has now also passed.

Do not modify ISSUE-001 code unless the test exposes a real remaining ISSUE-001 defect.

---

# Required Documentation Files

Create both files in exactly this directory:

`/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-rakshit/nitksaa-event/docs/issues`

Do NOT use `docs/Issues`.

Create:

```text
docs/issues/ISSUE-002_GOOGLE_ACCOUNT_SWITCH.md
```

and:

```text
docs/issues/ISSUE-002_GOOGLE_ACCOUNT_SWITCH_TEST_REPORT.md
```

---

# ISSUE File Content

`ISSUE-002_GOOGLE_ACCOUNT_SWITCH.md` should contain:

```markdown
# ISSUE-002 — Google Account Chooser Missing

## Severity
P1

## Gap

## Root Cause

## Expected Behavior

## Fix Plan

## Files Involved

## Verification Plan

## Dependencies
- ISSUE-001 code fix already exists
- ISSUE-002 is required to complete ISSUE-001 manual two-user verification

## Status
OPEN / IN PROGRESS / DONE
```

---

# Test Report Content

Create:

`docs/issues/ISSUE-002_GOOGLE_ACCOUNT_SWITCH_TEST_REPORT.md`

with:

```markdown
# ISSUE-002 Google Account Switch Test Report

## 1. Issue
- ID
- severity
- area

## 2. Root Cause

## 3. Fix

### Files Changed

### Implementation

## 4. Automated Verification

| Test | Expected | Actual | Result |
|---|---|---|---|

## 5. Manual Verification

### Account Chooser Test

| Step | Expected | Actual | Result |
|---|---|---|---|

### User A → User B Test

| Step | Expected | Actual | Result |
|---|---|---|---|

## 6. ISSUE-001 Combined Regression

State whether ISSUE-001 manual E2E now passes.

## 7. Static Checks

- flutter test
- flutter analyze
- web build if run

## 8. Files Changed

## 9. Remaining Risks

## 10. Final Result

PASS / FAIL / CODE PASS — MANUAL E2E PENDING

## 11. Commit

Commit hash and message, or note why not committed.
```

---

# Commit Rules

Do not commit until:

- ISSUE-002 implementation is complete
- automated tests pass
- manual account-switch test passes
- ISSUE-002 test report is generated

If manual testing cannot be performed, leave:

```text
CODE PASS — MANUAL E2E PENDING
```

and do not commit unless explicitly instructed.

If manual testing succeeds, use:

```text
fix(auth): force Google account selection on web sign in

ISSUE-002
```

If ISSUE-001 manual E2E also passes after this fix, update its test report status separately.

Do NOT combine the ISSUE-001 and ISSUE-002 source changes into a misleading single issue description.

---

# Important Scope Restrictions

Do NOT fix:

- ISSUE-003 auth error messaging
- ISSUE-004 cancellation
- ISSUE-005 refund
- ISSUE-006 quantity
- ISSUE-007 pricing
- ISSUE-008 payment recovery
- ISSUE-009 Razorpay retry
- ISSUE-010 payment status
- ISSUE-011 My Events
- ISSUE-012 cancellation policy
- ISSUE-013 alumni eligibility redesign
- ISSUE-014 RBAC
- ISSUE-015 admin APIs
- ISSUE-016 mobile Razorpay dependency
- ISSUE-017 payment mode
- ISSUE-018 error mapping
- ISSUE-019 registration form
- ISSUE-020 QR
- ISSUE-021 routing
- ISSUE-022 hosting
- ISSUE-023 general cleanup

Do not perform broad refactors.

---

# Final Response Format

When done, respond with exactly:

## ISSUE-002 Result

`PASS / FAIL / CODE PASS — MANUAL E2E PENDING`

## Root Cause Confirmed

## Fix Implemented

## Files Changed

## Tests Added / Updated

## Verification Results

Include exact output summary for:

- `flutter test`
- `flutter analyze`
- web/browser test if run

## Manual E2E Result

Include whether the account chooser appeared.

## ISSUE-001 Manual Regression Result

State:

`PASS / FAIL / NOT RUN`

## Documentation Created

Confirm both:

- `docs/issues/ISSUE-002_GOOGLE_ACCOUNT_SWITCH.md`
- `docs/issues/ISSUE-002_GOOGLE_ACCOUNT_SWITCH_TEST_REPORT.md`

## Git Diff Summary

## Commit

Commit hash/message or:

`Not committed — manual E2E pending`

## Next Issue

`ISSUE-003 — Backend authentication errors are masked`

Do not start ISSUE-003.
