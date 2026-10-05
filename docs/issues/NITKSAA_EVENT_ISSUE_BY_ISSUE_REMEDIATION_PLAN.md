# NITKSAA-EVENT — Issue-by-Issue Remediation & Verification Plan

**Plan version:** 1.0  
**Prepared from:** `NITKSAA_EVENT_FLUTTER_VERIFICATION_REPORT(1).md` dated 2026-10-03  
**Application:** `nitksaa-rakshit/nitksaa-event/frontend` (NEW Flutter app)  
**Primary objective:** Stabilize the attendee end-to-end flow first. Fix exactly one issue at a time, verify it, generate its test report, commit it, and only then proceed to the next issue.  
**Later phase:** Review and cover all remaining APIs/capabilities available in the NITKSAA-EVENT backend, including admin/RBAC/check-in/payment-configuration flows.

---

# 1. Working Method

For every issue, follow this sequence without skipping a gate:

```text
Issue
  ↓
Gap / Reproduce
  ↓
Fix
  ↓
Verification
  ↓
Generate Test Report
  ↓
Commit
  ↓
Regression Check
  ↓
Next Issue
```

## Definition of Done for Every Issue

An issue is **DONE** only when all of the following are true:

- [ ] Gap reproduced or otherwise proven from code/API contract.
- [ ] Root cause documented.
- [ ] Fix is limited to the issue's intended scope.
- [ ] Automated tests added/updated where practical.
- [ ] `flutter analyze` has no new errors introduced by the change.
- [ ] Relevant existing tests pass.
- [ ] Manual/deployed verification is completed when the issue requires browser, Firebase, or Razorpay interaction.
- [ ] No regression in already completed flows.
- [ ] A dedicated Markdown test report is generated.
- [ ] Test report records expected vs actual results and evidence.
- [ ] Source changes and test report are reviewed.
- [ ] Commit is created only after verification passes.
- [ ] Commit hash is recorded in this plan.
- [ ] Issue status is changed from `OPEN` → `DONE`.

## Commit Rule

Prefer **one logical issue per commit**.

Recommended format:

```text
fix(<area>): <short issue description>

ISSUE-XXX
```

Do not mix unrelated cleanup, refactors, admin work, or API expansion into an attendee-flow fix unless the change is strictly required by that issue.

---

# 2. Baseline From the Verification Report

The source verification report identified **23 issues**:

| Severity | Count |
|---|---:|
| P0 | 2 |
| P1 | 9 |
| P2 | 9 |
| P3 | 3 |
| **Total** | **23** |

The verified baseline is:

- Public event listing works.
- Public event detail works.
- Authentication's basic login sequence works.
- Logout clears Hive session and Firebase auth.
- Payment order creation logic exists.
- Razorpay checkout launch exists.
- `verify-checkout` happy-path integration exists.
- Backend cancellation/refund logic is implemented and its local refund suite passed.
- Production frontend CORS/backend URL/deployed bundle were verified.
- Major gaps begin around **identity changes, pricing integrity, payment recovery, cancellation, refund, and post-payment state**.

The source report's UAT blockers are especially important:

- ISSUE-001 — cross-user stale event data.
- ISSUE-004 — cancellation endpoint mismatch.
- ISSUE-005 — refund not integrated.
- ISSUE-006 — unsupported multi-pass quantity.
- ISSUE-008 — payment cannot be resumed.

---

# 3. Scope Strategy

## Phase A — Basic End-to-End Attendee Flow

Fix and verify in this business-flow order:

1. View Dashboard / View Events
2. Sign In / Sign Out / Re-Sign In
3. View Events / My Events
4. View Event
5. Register
6. Payment Flow
7. Cancellation
8. Refund
9. Timeline

This phase is the priority. Do **not** start broad admin/API feature development until this attendee flow is stable.

## Phase B — Cross-Cutting Frontend Hardening

After the attendee E2E flow is stable:

- friendly error mapping
- routing/navigation
- hosting/web shell
- mobile dependency/build
- test coverage/code health
- QR/check-in contract preparation where needed

## Phase C — Backend API / Admin Capability Coverage

Later, plan and verify all backend capabilities, including:

- admin events
- admin registrations
- attendees/export
- check-in
- event people/sponsors/partners
- payment configuration
- RBAC/role management
- event payment-admin grants
- lifecycle expiry
- gateway configuration
- APIs not currently exposed by Flutter

---

# 4. Master Execution Queue

> **Rule:** Work top-to-bottom. Do not move to the next issue until the current issue has a PASS test report and commit.

| Seq | Flow | Issue | Severity | Status | Test Report | Commit |
|---:|---|---|---|---|---|---|
| 0.1 | Dashboard / Public Events | Baseline public-event smoke | Baseline | OPEN | `FLOW-00_DASHBOARD_EVENTS_BASELINE_TEST_REPORT.md` | — |
| 1 | Auth | ISSUE-001 Cross-user stale event data | **P0** | OPEN | `ISSUE-001_AUTH_STATE_ISOLATION_TEST_REPORT.md` | TBD |
| 2 | Auth | ISSUE-002 Google account chooser missing | P1 | OPEN | `ISSUE-002_GOOGLE_ACCOUNT_SWITCH_TEST_REPORT.md` | TBD |
| 3 | Auth | ISSUE-003 Backend auth errors masked | P2 | OPEN | `ISSUE-003_AUTH_ERROR_HANDLING_TEST_REPORT.md` | TBD |
| 4 | View Events / My Events | ISSUE-011 Duplicate cards / wrong status labels | P2 | OPEN | `ISSUE-011_MY_EVENTS_STATE_TEST_REPORT.md` | TBD |
| 5 | View Event | ISSUE-013 Alumni eligibility lifecycle/messaging | P1 | OPEN | `ISSUE-013_ALUMNI_ELIGIBILITY_TEST_REPORT.md` | TBD |
| 6 | Register | ISSUE-006 Unsupported multi-pass quantity | **P0** | OPEN | `ISSUE-006_REGISTRATION_QUANTITY_TEST_REPORT.md` | TBD |
| 7 | Register | ISSUE-019 Form fields discarded / notes in URL | P2 | OPEN | `ISSUE-019_REGISTRATION_FORM_TEST_REPORT.md` | TBD |
| 8 | Payment | ISSUE-007 Server pricing not used | P1 | OPEN | `ISSUE-007_SERVER_PRICING_TEST_REPORT.md` | TBD |
| 9 | Payment | ISSUE-008 Cannot resume/retry payment | P1 | OPEN | `ISSUE-008_PAYMENT_RECOVERY_TEST_REPORT.md` | TBD |
| 10 | Payment | ISSUE-009 Razorpay in-modal retry loses success | P1 | OPEN | `ISSUE-009_RAZORPAY_RETRY_TEST_REPORT.md` | TBD |
| 11 | Payment | ISSUE-010 No payment-status handling | P2 | OPEN | `ISSUE-010_PAYMENT_STATUS_TEST_REPORT.md` | TBD |
| 12 | Payment | ISSUE-017 No TEST/LIVE handling | P2/P1 before LIVE | OPEN | `ISSUE-017_PAYMENT_MODE_TEST_REPORT.md` | TBD |
| 13 | Cancellation | ISSUE-004 Wrong cancellation endpoint | P1 | OPEN | `ISSUE-004_CANCELLATION_API_TEST_REPORT.md` | TBD |
| 14 | Cancellation | ISSUE-012 Frontend-only cancellation rule | P2 | OPEN | `ISSUE-012_CANCELLATION_POLICY_TEST_REPORT.md` | TBD |
| 15 | Refund | ISSUE-005 Refund flow not integrated | P1 | OPEN | `ISSUE-005_REFUND_E2E_TEST_REPORT.md` | TBD |
| 16 | Timeline | Payment/cancel/refund timeline missing | Capability gap | OPEN | `FLOW-09_PAYMENT_TIMELINE_TEST_REPORT.md` | TBD |
| 17 | Errors | ISSUE-018 Raw technical errors | P2 | OPEN | `ISSUE-018_FRIENDLY_ERRORS_TEST_REPORT.md` | TBD |
| 18 | QR / Check-in | ISSUE-020 Badge QR incompatible with backend check-in | P2 | OPEN | `ISSUE-020_QR_CHECKIN_CONTRACT_TEST_REPORT.md` | TBD |
| 19 | Navigation | ISSUE-021 Routing/navigation gaps | P3 | OPEN | `ISSUE-021_ROUTING_TEST_REPORT.md` | TBD |
| 20 | Web/Hosting | ISSUE-022 Web shell/hosting hygiene | P3 | OPEN | `ISSUE-022_WEB_HOSTING_TEST_REPORT.md` | TBD |
| 21 | Build | ISSUE-016 `razorpay_flutter` dependency missing | P1* | OPEN | `ISSUE-016_MOBILE_BUILD_TEST_REPORT.md` | TBD |
| 22 | Quality | ISSUE-023 Test coverage/code health | P3 | OPEN | `ISSUE-023_QUALITY_TEST_REPORT.md` | TBD |
| 23 | Admin/RBAC | ISSUE-014 Admin role model mismatch | P1 | DEFER-PHASE-C | `ISSUE-014_ADMIN_RBAC_TEST_REPORT.md` | TBD |
| 24 | Admin API | ISSUE-015 Admin API contract mismatches | P2 | DEFER-PHASE-C | `ISSUE-015_ADMIN_API_CONTRACT_TEST_REPORT.md` | TBD |

---

# 5. Flow 0 — View Dashboard / Public View Events Baseline

This is a **baseline verification**, not a defect fix.

## Gap / Risk

The source report says public event discovery is currently working. Before modifying auth/state/payment code, preserve a known-good baseline so later regressions can be detected.

## Verify

- [ ] Application loads.
- [ ] Dashboard/home shell renders.
- [ ] Public event list loads.
- [ ] Upcoming/all filters load expected data.
- [ ] Only published events appear.
- [ ] Event cards show backend `registration_status`.
- [ ] Event detail can be opened from public list.
- [ ] Hard refresh on public event route works.
- [ ] No CORS error in browser console.
- [ ] No unexpected 4xx/5xx from public event APIs.
- [ ] Capture current screenshots/network evidence.

## Existing Source Evidence

The original verification reported:

- `GET /api/v1/events/public?period=...` — PASS.
- `GET /api/v1/events/public/{id}` — PASS.
- Production CORS for the deployed web app — PASS.

## Test Report

`FLOW-00_DASHBOARD_EVENTS_BASELINE_TEST_REPORT.md`

## Commit

No code commit unless this smoke test exposes a new defect. If it does, add a new issue before continuing.

---

# 6. Flow 1 — Sign In / Sign Out / Re-Sign In

---

## ISSUE-001 — Cross-User Event Data Survives Logout/Login

**Severity:** P0  
**Priority:** FIRST FIX  
**Status:** OPEN  
**Fix location:** NEW Flutter frontend  
**Root area:** Riverpod/user-scoped state lifecycle

### Gap

After User A views an event, logs out, and User B logs in within the same browser tab without a full reload, User B can be shown User A's:

- registration status
- badge number
- QR
- eligibility verdict
- alumni profile
- name
- email
- phone

`eventDetailProvider(eventId)` is long-lived, is fetched once, reads auth rather than watching identity changes, and is not invalidated on logout. Existing state-copy semantics can also retain a previous non-null value when the new API result is null.

### Fix Plan

- [ ] Make user-specific event-detail state dependent on authenticated identity.
- [ ] Prefer `autoDispose` for per-event user state or explicitly invalidate user-scoped providers on identity change.
- [ ] Ensure a logout destroys user-specific event state.
- [ ] Ensure a new login triggers a fresh eligibility/my-registration/alumni-profile read.
- [ ] Correct state mutation/copy semantics so legitimate null results clear prior values.
- [ ] Ensure checkout cannot reuse another user's stale `registration_id`.
- [ ] Add a regression test that changes Session A → logout → Session B.

### Verification

#### Automated

- [ ] Provider test: User A loads Event X.
- [ ] Provider state contains A's registration/profile.
- [ ] Auth changes to unauthenticated.
- [ ] Auth changes to User B.
- [ ] Event X is reloaded using B's token.
- [ ] A's values never render after B becomes active.
- [ ] Null/no-registration response clears prior registration.
- [ ] 403 alumni profile response clears prior alumni profile.
- [ ] Checkout never receives A's registration ID under B's session.

#### Manual / Deployed

Use two real test accounts in the **same tab**:

1. Login as User A.
2. Open Event X.
3. Record A's badge/profile/eligibility.
4. Logout.
5. Login as User B.
6. Open the same Event X.
7. Confirm only B's data appears.
8. Repeat without browser reload.
9. Repeat with browser reload.
10. Repeat B → A.

### Pass Criteria

**ZERO data belonging to the previous authenticated user may remain visible or actionable after identity change.**

### Generate Test Report

`ISSUE-001_AUTH_STATE_ISOLATION_TEST_REPORT.md`

Report must include:

- files changed
- root cause
- before behavior
- after behavior
- automated tests
- manual two-user evidence
- screenshots/network evidence
- regression results
- final PASS/FAIL

### Commit

Recommended:

```text
fix(auth): isolate event state across user sessions

ISSUE-001
```

**Commit hash:** `TBD`

---

## ISSUE-002 — Google Sign-In Does Not Force Account Selection

**Severity:** P1  
**Status:** OPEN  
**Fix location:** NEW Flutter frontend

### Gap

After logout, Google browser session can remain active. The NEW app does not force account selection, so clicking Google Sign In can silently sign the user back into the previous Google account.

### Fix Plan

- [ ] Match the working reference behavior.
- [ ] Configure Google web sign-in to request account selection (`select_account` behavior).
- [ ] Do not rely on clearing the Google browser cookie as the normal solution.
- [ ] Keep Firebase/backend logout behavior intact.

### Verification

- [ ] Login as Google Account A.
- [ ] Logout.
- [ ] Click Google Sign In.
- [ ] Account chooser appears.
- [ ] Select Account B.
- [ ] `/auth/me` reflects B.
- [ ] Sidebar/profile reflects B.
- [ ] Event detail reflects B.
- [ ] Repeat B → A.
- [ ] Verify session restore still works after a normal reload.

### Test Report

`ISSUE-002_GOOGLE_ACCOUNT_SWITCH_TEST_REPORT.md`

### Commit

```text
fix(auth): force Google account selection on web sign in

ISSUE-002
```

**Commit hash:** `TBD`

---

## ISSUE-003 — Backend Authentication Rejections Are Masked

**Severity:** P2  
**Status:** OPEN

### Gap

Backend errors such as:

- `email_not_verified`
- `account_suspended`

are reduced to a generic "Sign in failed" message. Firebase auth may also remain signed in after backend exchange failure.

### Fix Plan

- [ ] Preserve backend error code/detail.
- [ ] Add user-safe friendly auth messages.
- [ ] Explicitly sign out Firebase when backend authentication fails.
- [ ] Ensure Hive/backend session is absent after failed login.
- [ ] Distinguish backend rejection from connectivity failure.

### Verification

Test:

- [ ] Verified valid user.
- [ ] Unverified email/password Firebase user.
- [ ] Suspended backend user.
- [ ] Invalid/expired token.
- [ ] Network failure.
- [ ] Retry after failed backend exchange.

### Test Report

`ISSUE-003_AUTH_ERROR_HANDLING_TEST_REPORT.md`

### Commit

```text
fix(auth): surface backend login errors safely

ISSUE-003
```

**Commit hash:** `TBD`

---

# 7. Flow 2 — View Events / My Events

## ISSUE-011 — Duplicate Event Cards and Incorrect Status Labels

**Severity:** P2  
**Status:** OPEN

### Gap

Backend returns registration history as registration rows. NEW Flutter maps rows one-to-one into My Events cards. After expired holds, cancellation through another client, or re-registration, multiple cards for the same event can appear. Non-`registered` statuses can also be labelled "Unregistered" even when payment is pending.

### Fix Plan

- [ ] Define a current-state presentation rule for My Events.
- [ ] Preserve history separately if history is required.
- [ ] Group/resolve registration rows by `event_id` for the main current-state view.
- [ ] Use stable keys.
- [ ] Render explicit statuses:
  - registered
  - seat held
  - payment pending
  - payment verification
  - payment failed
  - cancelled
  - expired
- [ ] Integrate `latest_order_id` where payment actions require it.

### Verification

Test state sequences:

- [ ] registered only
- [ ] seat-held only
- [ ] seat-held → expired → re-register
- [ ] payment failed → retry
- [ ] cancelled → re-register
- [ ] paid/registered
- [ ] no duplicate current event card unless product explicitly chooses history view

### Test Report

`ISSUE-011_MY_EVENTS_STATE_TEST_REPORT.md`

### Commit

```text
fix(events): render current registration state correctly

ISSUE-011
```

**Commit hash:** `TBD`

---

# 8. Flow 3 — View Event

## ISSUE-013 — Alumni Eligibility Lifecycle and Messaging

**Severity:** P1  
**Status:** OPEN  
**Root area:** data + backend login-time classification + frontend state/messaging

### Gap

The backend determines `alumni` primarily from login-time email matching against alumni data. The frontend can additionally show a stale verdict if ISSUE-001 exists. Users who consider themselves alumni may still be classified as `other` when:

- Firebase/Google email differs from alumni DB email.
- Alumni lookup failed during login.
- Alumni data was corrected after the user's previous login.
- Alumni record status is not `Active` or `Self-Verified`.

### Dependency

**Do not diagnose ISSUE-013 before ISSUE-001 is fixed.** Otherwise stale state can produce false conclusions.

### Fix Plan

- [ ] Verify eligibility source remains backend-authoritative.
- [ ] Improve ineligible messaging without duplicating authorization rules in Flutter.
- [ ] Document how a user should resolve an email mismatch.
- [ ] Consider backend logging/observability for alumni lookup failures.
- [ ] Decide whether a controlled re-evaluation path is required after alumni data changes.
- [ ] Do not infer alumni eligibility from previous event attendance.

### Verification

- [ ] Known alumni + exact email + Active.
- [ ] Known alumni + case variation in email.
- [ ] Alumni using a different Google email.
- [ ] Inactive alumni.
- [ ] `Self-Verified` alumni.
- [ ] Non-alumni.
- [ ] Alumni record corrected after prior login.
- [ ] User A → User B in same browser.
- [ ] Verify backend result equals displayed result.

### Test Report

`ISSUE-013_ALUMNI_ELIGIBILITY_TEST_REPORT.md`

### Commit

```text
fix(eligibility): make alumni eligibility state and messaging consistent

ISSUE-013
```

**Commit hash:** `TBD`

---

# 9. Flow 4 — Register

## ISSUE-006 — Unsupported Multi-Pass Quantity

**Severity:** P0  
**Status:** OPEN  
**Root area:** frontend/backend contract mismatch

### Gap

Flutter offers a quantity selector (1–4) and displays `price × quantity`, but the backend registration schema has no quantity field. One backend registration/seat is created and backend payment pricing is for one registration.

This is a financial-expectation integrity issue.

### Product Decision for Stabilization

For the current attendee-flow stabilization phase:

**Recommended decision: one authenticated alumni = one registration = one pass. Remove the quantity selector.**

Do not add multi-pass backend semantics during this fix unless the product owner explicitly changes the product requirement.

### Fix Plan

- [ ] Remove/hide "No of passes".
- [ ] Remove hardcoded min/max quantity.
- [ ] Stop sending unsupported `quantity`.
- [ ] Remove `ticket_price × quantity` calculations.
- [ ] Make checkout amount server-authoritative.
- [ ] Keep backend capacity/registration semantics unchanged.

### Verification

- [ ] Registration request contains supported fields only.
- [ ] Exactly one registration is created.
- [ ] Exactly one seat is reserved.
- [ ] No quantity selector is visible.
- [ ] Checkout text does not promise multiple passes.
- [ ] Displayed payment equals authoritative pricing.
- [ ] Razorpay amount equals order amount.

### Test Report

`ISSUE-006_REGISTRATION_QUANTITY_TEST_REPORT.md`

### Commit

```text
fix(registration): remove unsupported pass quantity

ISSUE-006
```

**Commit hash:** `TBD`

---

## ISSUE-019 — Registration Form Fields Are Misleading / Notes in URL

**Severity:** P2  
**Status:** OPEN

### Gap

Email and phone are editable in Flutter but are not accepted by the registration API; edits are silently discarded. Attendee notes are passed through a URL query and have no frontend 500-character validation.

### Fix Plan

- [ ] Display authoritative alumni profile fields as read-only unless a supported profile-update API exists.
- [ ] Explain where profile data comes from.
- [ ] Carry notes in application state/request body, not URL query parameters.
- [ ] Enforce ≤500 characters before API call.
- [ ] Keep backend `attendee_note` as the only supported registration input unless contract changes.

### Verification

- [ ] Email cannot appear editable if changes are discarded.
- [ ] Phone cannot appear editable if changes are discarded.
- [ ] Notes are absent from browser URL/history.
- [ ] 500 chars accepted.
- [ ] >500 chars blocked with friendly message.
- [ ] Request body matches backend schema.

### Test Report

`ISSUE-019_REGISTRATION_FORM_TEST_REPORT.md`

### Commit

```text
fix(registration): align attendee form with API contract

ISSUE-019
```

**Commit hash:** `TBD`

---

# 10. Flow 5 — Payment

## ISSUE-007 — Checkout Does Not Use Server Pricing

**Severity:** P1  
**Status:** OPEN / source report calls mismatch conditional on configured GST/fees

### Gap

NEW Flutter displays public `ticket_price`, while backend has a dedicated server pricing endpoint that can include GST and convenience fee.

### Fix Plan

- [ ] Call `GET /api/v1/events/{id}/payment-pricing`.
- [ ] Render server line items.
- [ ] Render `final_amount`.
- [ ] Do not calculate authoritative payment totals in Flutter.
- [ ] Confirm amount equality across pricing → order → Razorpay minor amount.

### Verification

For an event with fees:

```text
payment-pricing.final_amount
    ==
payment-order.final_amount
    ==
attempt.checkout.amount_minor / 100
    ==
Razorpay displayed amount
```

- [ ] base amount
- [ ] GST
- [ ] convenience fee
- [ ] currency
- [ ] rounding

### Test Report

`ISSUE-007_SERVER_PRICING_TEST_REPORT.md`

### Commit

```text
fix(payment): use server-authoritative event pricing

ISSUE-007
```

**Commit hash:** `TBD`

---

## ISSUE-008 — Returning Attendee Cannot Resume Payment

**Severity:** P1  
**Status:** OPEN

### Gap

`seat_held`, `payment_pending`, and `payment_failed` states do not lead to a usable recovery action. Event detail can incorrectly say "You are registered" and offer a QR even though payment is incomplete.

### Fix Plan

Map backend states to attendee actions:

| Registration / Payment State | UI |
|---|---|
| `seat_held` | Payment pending / Continue Payment |
| `payment_pending` | Continue Payment / Check Status |
| `payment_failed` | Try Again |
| `payment_verification` | Check Payment Status |
| `registered` | Registered / badge when valid |
| expired/cancelled | Register again if eligible |

Additional work:

- [ ] Parse and store `latest_order_id`.
- [ ] Reuse backend order/attempt semantics.
- [ ] Never show QR/badge for unpaid hold.
- [ ] Display hold expiry when available.
- [ ] Refresh event detail/My Events after state transition.

### Verification

- [ ] Open Razorpay then close it.
- [ ] Return to event page.
- [ ] Continue Payment exists.
- [ ] Retry failed payment.
- [ ] Check verification state.
- [ ] Hold expiration has correct UI.
- [ ] Successful recovery ends in `registered`.

### Test Report

`ISSUE-008_PAYMENT_RECOVERY_TEST_REPORT.md`

### Commit

```text
fix(payment): support attendee payment recovery

ISSUE-008
```

**Commit hash:** `TBD`

---

## ISSUE-009 — Razorpay In-Modal Retry Can Lose Later Success

**Severity:** P1  
**Status:** OPEN

### Gap

The failure callback completes the Dart completer, but Razorpay may keep its modal open for retry. A later success can then be ignored by the application and never reach `verify-checkout`.

### Fix Plan

Recommended for deterministic state management:

- [ ] Disable Razorpay's internal retry.
- [ ] Let the application own retry.
- [ ] Ensure success callback can result in `verify-checkout` exactly once.
- [ ] Treat dismiss/failure as recoverable application states.
- [ ] Verify webhook remains a safety net, not the primary recovery design.

### Verification

TEST MODE ONLY:

- [ ] Trigger a failed test payment.
- [ ] Confirm application receives failure.
- [ ] Retry through application.
- [ ] Succeed.
- [ ] Verify `/verify-checkout` called exactly once for successful payment.
- [ ] Confirm registration becomes `registered`.

### Test Report

`ISSUE-009_RAZORPAY_RETRY_TEST_REPORT.md`

### Commit

```text
fix(payment): make Razorpay retry lifecycle deterministic

ISSUE-009
```

**Commit hash:** `TBD`

---

## ISSUE-010 — Missing Payment Status / Check Status

**Severity:** P2  
**Status:** OPEN

### Gap

After pending/ambiguous payment verification, the attendee has no status page, no order refresh and no provider re-query.

### Required Backend APIs

- `GET /api/v1/payment-orders/{order_id}`
- `POST /api/v1/payment-attempts/{attempt_id}/verify`
- timeline API later in Flow 9

### Fix Plan

- [ ] Add Payment Status screen/view.
- [ ] Persist/navigation-pass order and attempt identifiers.
- [ ] Re-read backend order state.
- [ ] Auto-refresh only while appropriate.
- [ ] Add explicit "Check Payment Status".
- [ ] Map status to safe messages/actions.
- [ ] Refresh registration state on confirmation.

### Verification

- [ ] success
- [ ] pending
- [ ] verification pending
- [ ] verify-checkout 502/ambiguous
- [ ] payment failure
- [ ] page refresh
- [ ] returning later
- [ ] repeated Check Status is safe/idempotent

### Test Report

`ISSUE-010_PAYMENT_STATUS_TEST_REPORT.md`

### Commit

```text
feat(payment): add attendee payment status recovery

ISSUE-010
```

**Commit hash:** `TBD`

---

## ISSUE-017 — No TEST/LIVE Payment-Mode Protection

**Severity:** P2, treat as P1 before any LIVE use  
**Status:** OPEN

### Gap

NEW Flutter does not use `payment_mode` or `real_money`, has no TEST/LIVE indication, no LIVE real-money confirmation, and no Razorpay key/mode guard.

### Fix Plan

- [ ] Show payment mode from backend data.
- [ ] Prominent TEST banner in test mode.
- [ ] Explicit real-money confirmation for LIVE.
- [ ] Validate Razorpay key prefix against backend payment mode.
- [ ] Block mismatch.
- [ ] Do not infer mode from environment alone; backend response is authoritative.

### Verification

- [ ] TEST order + test key → allowed.
- [ ] TEST order + live key → blocked.
- [ ] LIVE order + live key → explicit real-money confirmation.
- [ ] LIVE order + test key → blocked.
- [ ] Payment status/refund view retains mode context.

### Test Report

`ISSUE-017_PAYMENT_MODE_TEST_REPORT.md`

### Commit

```text
fix(payment): enforce test and live payment modes

ISSUE-017
```

**Commit hash:** `TBD`

---

# 11. Flow 6 — Cancellation

## ISSUE-004 — Cancellation Calls a Nonexistent API

**Severity:** P1  
**Status:** OPEN  
**Confirmed against production:** current DELETE returns HTTP 405

### Gap

Current Flutter path:

```text
DELETE /api/v1/events/{event_id}/my-registration
```

does not exist.

Backend expects:

```text
POST /api/v1/registrations/{registration_id}/cancel
{
  "idempotency_key": "..."
}
```

### Fix Plan

- [ ] Cancel by `registration_id`, not `event_id`.
- [ ] Use the canonical POST endpoint.
- [ ] Send valid idempotency key.
- [ ] Parse `RefundStatusResponse`.
- [ ] Refresh My Events.
- [ ] Refresh event detail.
- [ ] Refresh payment/refund status.
- [ ] Friendly-map `registration_not_cancellable` and other backend errors.

### Verification

- [ ] Cancel free registered event.
- [ ] Cancel TEST-paid registered event.
- [ ] Cancel already cancelled registration (idempotent behavior).
- [ ] Attempt cancellation as wrong user.
- [ ] Attempt cancellation for seat-held/payment-pending state.
- [ ] Confirm current obsolete DELETE is no longer called.

### Test Report

`ISSUE-004_CANCELLATION_API_TEST_REPORT.md`

### Commit

```text
fix(cancellation): use canonical registration cancel API

ISSUE-004
```

**Commit hash:** `TBD`

---

## ISSUE-012 — Cancellation Availability Uses Frontend-Only Rule

**Severity:** P2  
**Status:** OPEN

### Gap

The UI hides cancel unless the public event's registration status is `open`. Backend cancellation currently checks registration state, not the registration-window state.

### Product Decision

Choose one:

**A. Current backend semantics:** registered attendees can cancel regardless of registration window.

**B. New business cancellation cutoff:** implement/enforce cutoff in backend and expose the policy to clients.

Do not keep a frontend-only rule.

### Fix Plan

- [ ] Confirm product cancellation policy.
- [ ] Remove unsupported UI-only condition OR add backend policy.
- [ ] UI renders cancellation availability from authoritative state/policy.

### Verification

- [ ] Registered attendee while registration window open.
- [ ] Registered attendee after registration closes.
- [ ] Unsupported payment states.
- [ ] Cancelled registration.
- [ ] Refunded registration.

### Test Report

`ISSUE-012_CANCELLATION_POLICY_TEST_REPORT.md`

### Commit

```text
fix(cancellation): align cancel availability with backend policy

ISSUE-012
```

**Commit hash:** `TBD`

---

# 12. Flow 7 — Refund

## ISSUE-005 — Refund Lifecycle Not Integrated

**Severity:** P1  
**Status:** OPEN  
**Dependency:** ISSUE-004 must be fixed first.

### Backend Behavior to Preserve

For a paid `registered` registration:

```text
Cancel
  → registration becomes cancelled
  → refund row created
  → provider refund initiated
  → refund_pending / refund_processing
  → refund_processed OR refund_failed
```

Refund status endpoint:

```text
GET /api/v1/registrations/{registration_id}/refund
```

### Gap

NEW Flutter currently has:

- no correct cancel/refund initiation path
- no refund model
- no refund ID capture
- no refund amount display
- no refund status view
- no "Check refund status"
- no post-cancel refund lifecycle

### Fix Plan

- [ ] Parse cancellation response.
- [ ] Add refund status model.
- [ ] Call refund status endpoint.
- [ ] Display amount/status/safe message.
- [ ] Allow user to manually refresh non-terminal refund.
- [ ] Keep cancelled registration accessible for refund status.
- [ ] Refresh My Events/event detail.
- [ ] Handle `refund_failed` clearly.
- [ ] Do not invent admin refund approval/retry UI—the source backend does not provide those APIs.

### Verification

TEST MODE / controlled environment:

- [ ] successful paid registration
- [ ] cancel paid registration
- [ ] refund record returned
- [ ] pending/processing rendered
- [ ] processed rendered
- [ ] repeated status query safe
- [ ] refund amount equals captured order amount
- [ ] cancel idempotency
- [ ] wrong-user refund lookup denied
- [ ] failure state message tested if safely reproducible

### Test Report

`ISSUE-005_REFUND_E2E_TEST_REPORT.md`

### Commit

```text
feat(refund): add attendee refund lifecycle

ISSUE-005
```

**Commit hash:** `TBD`

---

# 13. Flow 8 — Timeline

## FLOW-09 — Attendee Payment / Cancellation / Refund Timeline

**Status:** OPEN  
**Type:** Missing backend capability integration in NEW Flutter

### Gap

Backend supports:

```text
GET /api/v1/payment-orders/{order_id}/timeline
```

NEW Flutter does not expose the lifecycle.

### Dependency

Implement after:

- payment recovery
- payment status
- cancellation
- refund

### Fix Plan

- [ ] Add timeline repository/API integration.
- [ ] Display events chronologically.
- [ ] Use server state as authoritative.
- [ ] Connect timeline from payment/refund status view.
- [ ] Avoid exposing internal/unsafe provider details directly.

### Verification

Expected lifecycle examples:

```text
Registration created
→ Payment order created
→ Attempt initiated
→ Payment confirmed
→ Registration confirmed
→ Cancellation requested
→ Refund initiated
→ Refund processed
```

Also verify partial flows:

- [ ] abandoned payment
- [ ] failed attempt
- [ ] retry
- [ ] pending verification
- [ ] free event where timeline may not apply

### Test Report

`FLOW-09_PAYMENT_TIMELINE_TEST_REPORT.md`

### Commit

```text
feat(payment): add attendee transaction timeline
```

**Commit hash:** `TBD`

---

# 14. Cross-Cutting Issues After Core E2E

## ISSUE-018 — Friendly Error Mapping

**Severity:** P2  
**Status:** OPEN

### Gap

Raw `DioException` text/backend codes can be shown directly.

### Fix

- [ ] Centralize API error parsing.
- [ ] Map known backend `detail` codes to safe user messages.
- [ ] Preserve raw technical details only in appropriate diagnostics/logging.
- [ ] Reuse the same error strategy for auth, registration, payment, cancellation and refund.

### Verification

- [ ] already registered
- [ ] event full
- [ ] payment not configured
- [ ] active payment attempt
- [ ] not cancellable
- [ ] invalid/expired session
- [ ] generic network failure

### Test Report

`ISSUE-018_FRIENDLY_ERRORS_TEST_REPORT.md`

### Commit

```text
fix(errors): centralize attendee-safe API messages

ISSUE-018
```

---

## ISSUE-020 — QR Badge / Check-In Contract Mismatch

**Severity:** P2  
**Status:** OPEN  
**Fix location:** backend + Flutter

### Gap

Flutter QR currently encodes `registration_number` through a third-party QR service. Backend check-in expects a `qrtoken`, and no attendee API currently exposes that token.

### Fix Plan

- [ ] Define safe attendee check-in token contract.
- [ ] Expose token only for valid registered attendee where appropriate.
- [ ] Render QR locally in Flutter.
- [ ] Stop sending registration identifier to third-party QR generation.
- [ ] Never show valid check-in QR for unpaid hold.

### Verification

- [ ] registered paid attendee QR verifies through backend check-in verify endpoint.
- [ ] another user's token cannot be accessed.
- [ ] unpaid/cancelled registration has no valid badge.
- [ ] token is not sent to third-party QR service.

### Test Report

`ISSUE-020_QR_CHECKIN_CONTRACT_TEST_REPORT.md`

### Commit

```text
fix(checkin): align attendee QR with backend token contract

ISSUE-020
```

---

## ISSUE-021 — Routing / Navigation

**Severity:** P3  
**Status:** OPEN

### Fix Plan

- [ ] Protect authenticated routes consistently.
- [ ] Protect admin routes consistently.
- [ ] Remove or implement `/volunteer`.
- [ ] Remove or implement `/more`.
- [ ] Normalize logout navigation.
- [ ] Verify deep-link hard refresh.

### Test Report

`ISSUE-021_ROUTING_TEST_REPORT.md`

### Commit

```text
fix(routing): normalize protected routes and navigation

ISSUE-021
```

---

## ISSUE-022 — Web Shell / Hosting Hygiene

**Severity:** P3  
**Status:** OPEN

### Fix Plan

- [ ] Remove duplicate Razorpay `checkout.js`.
- [ ] Set proper browser title.
- [ ] Set proper meta description.
- [ ] Set proper manifest identity.
- [ ] Review cache strategy for `index.html` / un-hashed `main.dart.js`.
- [ ] Resolve Firebase Android app ID mismatch.
- [ ] Do not show raw `user_type` as a polished role label.

### Test Report

`ISSUE-022_WEB_HOSTING_TEST_REPORT.md`

### Commit

```text
fix(web): clean hosting shell and client metadata

ISSUE-022
```

---

## ISSUE-016 — Mobile Razorpay Dependency Missing

**Severity:** P1 if mobile is in release scope  
**Status:** OPEN

### Gap

`razorpay_flutter` is imported for IO platforms but not declared, causing analyzer/build errors.

### Decision

- If mobile is shipping: add and configure the dependency correctly.
- If mobile is intentionally out of scope: remove/stub unsupported mobile integration so build intent is explicit.

### Verification

- [ ] `flutter analyze`
- [ ] Android build
- [ ] iOS build
- [ ] web build unchanged
- [ ] platform-specific payment initialization

### Test Report

`ISSUE-016_MOBILE_BUILD_TEST_REPORT.md`

### Commit

```text
fix(build): restore supported Razorpay platform dependency

ISSUE-016
```

---

## ISSUE-023 — Test Coverage / Code Health

**Severity:** P3  
**Status:** OPEN

### Gap

Source report found only one Flutter smoke test plus analyzer warnings and dead code.

### Fix Plan

Do this progressively as each issue is fixed, then close ISSUE-023 at the end.

Minimum permanent regression coverage should include:

- [ ] auth state isolation
- [ ] Google account chooser config
- [ ] registration request contract
- [ ] single-pass behavior
- [ ] server pricing
- [ ] payment verification
- [ ] payment recovery
- [ ] cancellation endpoint contract
- [ ] refund state
- [ ] My Events status rendering
- [ ] friendly error mapping
- [ ] route protection

Then:

- [ ] remove dead code
- [ ] resolve analyzer warnings
- [ ] avoid unrelated large refactor during functional fixes
- [ ] consider central API client/contract generation as a separate controlled refactor

### Test Report

`ISSUE-023_QUALITY_TEST_REPORT.md`

### Commit

```text
test(frontend): complete attendee flow regression coverage

ISSUE-023
```

---

# 15. Suspected Issues — Track, Do Not Mix Into Confirmed Fixes

These were not all fully reproduced in the source verification. Keep them visible, but do not silently treat them as confirmed.

| ID | Suspected Issue | Confirmation Test | Status |
|---|---|---|---|
| S-1 | Public list can say open while eligibility says full because held seats are counted differently | Create/observe active paid holds and compare public list vs eligibility | OPEN |
| S-2 | Alumni DB lookup failure at first login silently stores `other` | Inspect backend logs / force controlled lookup failure | OPEN |
| S-3 | Failed refund has no operational retry path | Controlled provider-failure test + backend capability review | OPEN |
| S-4 | Expired seat holds can remain until lazy expiry trigger | Abandon checkout, wait past hold, reload/query | OPEN |
| S-5 | Stale User A registration could be used by User B checkout | Covered by ISSUE-001 two-user test | OPEN |
| S-6 | Razorpay webhook deployment/config may be missing or incorrect | Verify Razorpay dashboard + backend webhook path/mode | OPEN |

If any is reproduced, convert it into a numbered tracked defect before fixing it.

---

# 16. Manual E2E Test Pack

All payment tests must use **TEST mode** unless an explicit LIVE test is separately approved.

## MAN-A — Two-User Auth Isolation

Covers ISSUE-001/-002:

```text
User A login
→ open event
→ logout
→ Google sign in
→ choose User B
→ open same event
→ verify no User A information
```

Capture:

- account chooser
- event page
- registration form
- My Events
- `/auth/me`
- eligibility request
- my-registration request

## MAN-B — Alumni Eligibility

Covers ISSUE-013:

- signed-in email
- alumni DB matching email (masked in report)
- alumni `registrationstatus`
- backend eligibility response
- displayed UI message

## MAN-C — Registration + Price

Covers ISSUE-006/-007/-019:

```text
Register
→ checkout
→ compare registration payload
→ payment-pricing
→ payment-order
→ attempt.checkout.amount_minor
→ Razorpay TEST modal amount
```

## MAN-D — Payment Failure / Recovery

Covers ISSUE-008/-009/-010:

```text
Start payment
→ dismiss/fail
→ revisit event
→ Continue / Try Again
→ Check Status
→ successful TEST payment
→ verify registered state
```

## MAN-E — Cancellation + Refund

Covers ISSUE-004/-005/-012:

```text
Confirmed TEST payment
→ Cancel
→ POST /registrations/{id}/cancel
→ registration cancelled
→ refund state returned
→ GET /registrations/{id}/refund
→ terminal refund state
```

## MAN-F — Timeline

Covers Flow 9:

Compare timeline events with the actual transaction sequence captured in network logs.

---

# 17. Test Report Template for Every Issue

Copy this template into the issue's dedicated report.

```markdown
# ISSUE-XXX Test Report

**Issue:**  
**Severity:**  
**Date:**  
**Branch:**  
**Pre-fix commit:**  
**Post-fix commit:**  
**Environment:**  
**Frontend URL:**  
**Backend URL:**  
**Payment mode:** N/A / TEST / LIVE

## 1. Gap

### Expected
...

### Actual Before Fix
...

### Root Cause
...

## 2. Fix

### Files Changed
- ...

### Implementation
...

### Out of Scope
- ...

## 3. Verification

### Automated Tests

| Test | Expected | Actual | Result |
|---|---|---|---|
| ... | ... | ... | PASS/FAIL |

### Manual / Runtime Tests

| Step | Expected | Actual | Result |
|---|---|---|---|
| ... | ... | ... | PASS/FAIL |

### API / Network Evidence
...

### Screenshots / Evidence
...

## 4. Regression

- [ ] Dashboard
- [ ] Sign in
- [ ] Sign out
- [ ] Re-sign in
- [ ] View Events
- [ ] View Event
- [ ] Register
- [ ] Payment
- [ ] My Events
- [ ] Cancellation
- [ ] Refund
- [ ] Timeline

Mark N/A where the downstream feature has not yet been implemented.

## 5. Static Checks

- [ ] flutter analyze
- [ ] flutter test
- [ ] web build
- [ ] relevant backend tests
- [ ] no new console/CORS errors

## 6. Final Result

**PASS / FAIL**

Open observations:
- ...

## 7. Commit

`<hash> <commit message>`
```

---

# 18. Per-Issue Fix Session Template

At the beginning of each issue, create a small working section:

```markdown
## ISSUE-XXX Work Log

### Gap
- Reproduction:
- Root cause:
- API contract:
- Files involved:

### Fix
- Planned change:
- Files to modify:
- Explicit non-goals:

### Verification
- Unit/provider tests:
- Integration/contract tests:
- Manual deployed tests:
- Regression tests:

### Generate Test Report
- File:
- Result:

### Commit
- Message:
- Hash:

### Status
OPEN / IN PROGRESS / BLOCKED / DONE
```

---

# 19. Phase C — Later Backend/API Coverage Plan

Only start this after the basic attendee E2E flow is stable.

## ISSUE-014 — Admin / RBAC Role Discovery

The backend's authorization roles are distinct from attendee `user_type`. NEW Flutter currently gates admin UI on `user_type == 'admin'`, which the backend does not issue.

### Future Work

- [ ] Define a backend role-discovery API/contract.
- [ ] Represent platform roles:
  - platform_admin
  - finance_operator
  - auditor
  - support
- [ ] Represent event-scoped `event_admin`.
- [ ] Drive Flutter admin visibility from authoritative role data.
- [ ] Keep backend authorization enforcement authoritative.

---

## ISSUE-015 — Admin API Contract Alignment

Future admin remediation must review:

- [ ] list events
- [ ] create event
- [ ] get event
- [ ] update event
- [ ] status changes
- [ ] remove unsupported delete action unless backend adds it
- [ ] admin event v2 family
- [ ] registrations
- [ ] attendees
- [ ] export
- [ ] sessions
- [ ] people
- [ ] sponsors
- [ ] partners
- [ ] payment configuration

Do not send unsupported inline fields and assume they persisted.

---

# 20. Backend API Coverage Matrix for Phase C

The later API plan should explicitly test every supported route family, not just what Flutter currently calls.

## Attendee / Auth

- [ ] `POST /api/v1/auth/firebase`
- [ ] `GET /api/v1/auth/me`
- [ ] `GET /api/v1/alumni/me`
- [ ] `GET /api/v1/events/public`
- [ ] `GET /api/v1/events/public/{id}`
- [ ] `GET /api/v1/events/{id}/registration-eligibility`
- [ ] `POST /api/v1/events/{id}/register`
- [ ] `GET /api/v1/events/{id}/my-registration`
- [ ] `GET /api/v1/my/registrations`
- [ ] `GET /api/v1/events/{id}/payment-pricing`
- [ ] `POST /api/v1/registrations/{id}/payment-order`
- [ ] `GET /api/v1/payment-orders/{id}`
- [ ] `POST /api/v1/payment-orders/{id}/attempts`
- [ ] `POST /api/v1/payment-orders/{id}/verify-checkout`
- [ ] `POST /api/v1/payment-attempts/{id}/verify`
- [ ] `GET /api/v1/payment-orders/{id}/timeline`
- [ ] `POST /api/v1/registrations/{id}/cancel`
- [ ] `GET /api/v1/registrations/{id}/refund`
- [ ] Razorpay webhook integration

## Admin / Events

- [ ] `GET /api/v1/events`
- [ ] `POST /api/v1/events`
- [ ] `GET /api/v1/events/{id}`
- [ ] `PATCH /api/v1/events/{id}`
- [ ] `PATCH /api/v1/events/{id}/status`
- [ ] `/api/v1/admin/events` family
- [ ] admin publish/close
- [ ] sessions

## Registrations / Attendees / Check-In

- [ ] admin attendees
- [ ] attendee export
- [ ] all-status registrations
- [ ] check-in verify
- [ ] check-in create
- [ ] check-in list
- [ ] check-in attempts

## Event Enrichment

- [ ] people CRUD
- [ ] sponsors CRUD
- [ ] partners CRUD

## Payment Administration

- [ ] payment configuration create/read
- [ ] payment configuration validate
- [ ] payment configuration publish
- [ ] payment role grant/list/revoke
- [ ] event payment-admin grant
- [ ] expire orders
- [ ] expire registration holds
- [ ] gateway configuration read

## Explicitly Not in Current Backend

Do not plan a frontend around these unless backend scope changes:

- admin refund
- finance refund approval
- refund retry
- admin cancellation
- registration-status override
- payment reconciliation
- generic "my roles" endpoint

---

# 21. CI / Regression Target State

By the time Phase A+B is complete, CI should fail if any of these regress:

1. Cross-user data isolation.
2. Google account switching.
3. Registration request contract.
4. Single-pass behavior.
5. Server-authoritative price.
6. Payment order/attempt/verify sequence.
7. Payment retry/recovery.
8. Payment status verification.
9. Cancellation contract.
10. Refund lifecycle.
11. My Events state rendering.
12. TEST/LIVE key/mode safety.
13. Route guards.
14. Flutter analyzer/build.

Strong future improvement:

- Add contract tests against the backend OpenAPI so Flutter cannot accidentally call nonexistent routes such as the old cancellation DELETE.
- Consider generating typed API clients once functional stabilization is complete.

---

# 22. Release Gates

## Gate A — Ready for Next Internal Test Round

Must pass:

- [ ] ISSUE-001
- [ ] ISSUE-002
- [ ] ISSUE-004
- [ ] ISSUE-005
- [ ] ISSUE-006
- [ ] ISSUE-008
- [ ] no new P0/P1 regression

## Gate B — Ready for UAT

Must pass:

- [ ] all Gate A items
- [ ] ISSUE-007
- [ ] ISSUE-009
- [ ] ISSUE-010
- [ ] ISSUE-011
- [ ] ISSUE-012
- [ ] ISSUE-013
- [ ] ISSUE-018
- [ ] ISSUE-019
- [ ] stable attendee timeline where required
- [ ] full attendee regression report

## Gate C — Ready for LIVE Payments / Production

Must additionally pass:

- [ ] ISSUE-017 TEST/LIVE protection
- [ ] production webhook configuration verified
- [ ] payment/refund TEST evidence complete
- [ ] LIVE safeguards reviewed
- [ ] ISSUE-016 if mobile is a production target
- [ ] ISSUE-020 if check-in/badge is a launch requirement
- [ ] hosting/cache configuration reviewed
- [ ] no unresolved P0/P1 production blocker

---

# 23. Progress Dashboard

Update this section after every issue.

| Metric | Current |
|---|---:|
| Confirmed source issues | 23 |
| Issues completed in this remediation cycle | 0 |
| Issues in progress | 0 |
| Issues blocked | 0 |
| Phase A attendee flow | NOT STARTED |
| Phase B hardening | NOT STARTED |
| Phase C backend/admin coverage | DEFERRED |
| UAT readiness | NOT READY |
| LIVE payment readiness | NOT READY |

## Current Issue

**ISSUE-001 — Cross-user event data survives logout/login**

### Current Gate

- [ ] Gap reconfirmed
- [ ] Fix complete
- [ ] Verification complete
- [ ] Test report generated
- [ ] Commit complete

---

# 24. First Action

Start only with:

## ISSUE-001 — Auth State Isolation

Do not make unrelated changes.

When ISSUE-001 is completed:

1. Generate `ISSUE-001_AUTH_STATE_ISOLATION_TEST_REPORT.md`.
2. Run regression for dashboard, login, logout, re-login, event list and event detail.
3. Commit ISSUE-001.
4. Record the commit hash in this document.
5. Change ISSUE-001 status to `DONE`.
6. Move to ISSUE-002.

This pattern repeats for every subsequent issue.

---

# 25. Final Principle

The goal is not merely to make the UI appear correct.

For every flow, these four layers must agree:

```text
Flutter UI state
        ↓
Flutter API request/response model
        ↓
NITKSAA-EVENT backend state machine / API contract
        ↓
Runtime result (Firebase / PostgreSQL / Razorpay)
```

An issue is closed only when the behavior is correct across all applicable layers and is protected by repeatable verification.

