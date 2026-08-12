# NITKSAA Payment Platform — Complete Feature Status, Gaps, and Roadmap

> **Repositories**
>
> - `NITKSAA-EVENT` — backend payment, registration, RBAC, audit, lifecycle, diagnostics
> - `NITKSAA-PAYMENT` — Flutter Payment Flow Lab / attendee payment experience / diagnostics
>
> **Latest verified baselines**
>
> - Backend full suite: **312 passed / 0 failed / 4 skipped**
> - Backend payment/security/scheduler subset: **84 passed / 0 failed**
> - Flutter `flutter analyze`: **clean**
> - Flutter unit/widget tests: **52 passed / 0 failed**
> - Returning attendee payment UX: **Pilot Ready**
> - Real payment gateway: **Not implemented yet**
> - Real money: **Not enabled yet**

---

# 1. Executive Summary

The NITKSAA payment platform is already beyond a basic payment POC.

The core backend lifecycle is implemented and tested:

```text
Event
→ Registration
→ Seat Hold
→ Pricing
→ Payment Order
→ Payment Attempt
→ Deterministic Sandbox
→ Signed/Timestamped Webhook
→ Payment Capture
→ Registration Confirmation
→ Attendee Timeline
```

The returning-attendee Flutter flow is also implemented:

```text
Login
→ My Registrations
→ Payment Detail
→ Continue Payment / View Payment / Check Status
→ Payment Result
→ Timeline
```

The main remaining gaps are:

```text
Real Payment Gateway
Reconciliation
Refund / Cancellation / Transfer
Receipt / GST Invoice
Notifications
Advanced Pricing / Discounts
Production Exception Resolution
Data Retention / Cleanup
Production Security Hardening
```

Immediate next sprint:

```text
NITKSAA-PAYMENT
Sprint 6 — Integration Test Reliability + Payment Recovery Live E2E Closure
```

This sprint should close fresh UI-driven evidence gaps for:

```text
Failure
Failure → Retry → Success
Pure Pending
Requires Verification
Double Tap
Expiry
Restart Recovery
Cross-User Denial
```

---

# 2. Overall Feature Status

| Feature | Backend | Frontend | Status |
|---|---|---|---|
| Registration | ✅ | ✅ | Completed |
| Paid registration | ✅ | ✅ | Completed |
| Seat hold | ✅ | ✅ | Completed |
| Pricing | ✅ | ✅ | Completed |
| GST | ✅ | ✅ | Completed |
| Convenience fee | ✅ | ✅ display | Completed foundation |
| Payment order | ✅ | ✅ | Completed |
| Payment attempt | ✅ | ✅ | Completed |
| Sandbox payment | ✅ | ✅ | Completed |
| Payment success | ✅ | ✅ | Completed |
| Payment failure | ✅ | ✅ | Implemented |
| Retry | ✅ | ✅ | Live E2E closure pending |
| Pending payment | ✅ | ✅ | Live E2E closure pending |
| Requires verification | ✅ | ✅ | Live repeatable E2E closure pending |
| Already-paid reopening | ✅ | ✅ | Completed |
| My Registrations | ✅ | ✅ | Completed |
| My Payments / Payment Detail | ✅ | ✅ | Completed |
| Attendee timeline | ✅ | ✅ | Completed |
| Payment audit | ✅ | N/A | Completed |
| Duplicate-payment protection | ✅ | UX guard | Completed |
| Concurrency protection | ✅ | N/A | Completed |
| Webhook security | ✅ | N/A | Completed |
| Cross-user isolation | ✅ | ✅ | Completed |
| Restart recovery | Backend source-of-truth | ✅ | Completed |
| Order/hold expiry | ✅ | ✅ existing handling | Isolated E2E pending |
| Payment configuration admin | ✅ | No admin UI | Backend completed |
| Lifecycle scheduler script | ✅ | N/A | Completed |
| Payment exceptions | ✅ create/read | Diagnostics only | Partial |
| Real gateway | ❌ | ❌ | Pending |
| Refunds | ❌ | ❌ | Pending |
| Cancellation | ❌ | ❌ | Pending |
| Registration transfer | ❌ | ❌ | Pending |
| Receipt | ❌ | ❌ | Pending |
| GST invoice | ❌ | ❌ | Pending |
| Coupon/discount engine | ❌ | ❌ | Pending |
| Reconciliation | ❌ | ❌ | Pending |
| Notifications | Partial/general | ❌ payment UX | Pending |
| Data retention | ❌ | N/A | Pending |
| Rate limiting | ❌ | N/A | Pending |
| Secret manager | ❌ | N/A | Pending |
| Penetration testing | ❌ | ❌ | Pending |

---

# 3. Backend — Completed Features

## 3.1 Registration and Seat Hold

Completed:

```text
Free Event Registration
Paid Event Registration
Temporary Seat Hold
Configurable Hold Duration
Registration Preservation on Payment Failure
Registration Confirmation after Payment
Registration Ownership
latest_order_id Lookup
```

Paid-event model:

```text
Registration
→ Seat Held
→ Payment
→ Confirmed
```

A failed payment does not destroy the attendee's registration.

## 3.2 Pricing

Completed:

```text
INR only
Base Amount
GST OFF
GST Inclusive
GST Exclusive
Convenience Fee
Configuration Versioning
Immutable Pricing Snapshot
```

Example:

```text
Base Fee          ₹100
GST 18%           ₹18
Final Amount      ₹118
```

The backend is financially authoritative. Flutter only displays returned values.

## 3.3 Payment Configuration

Completed production configuration lifecycle:

```text
Draft
→ Validate
→ Publish
→ Published
→ New Version
→ Previous Version Retired
```

Protections:

```text
Versioned Configuration
Append-Only Published History
Immutable Historical Configuration
Order Bound to Configuration Version
Immutable Pricing Snapshot
```

## 3.4 Payment Orders

Completed:

```text
Create Order
Public Order ID
Server Price Binding
Configuration Binding
Registration Ownership
Order Idempotency
Active Order Reuse
Order Expiry
Order Timeline
```

## 3.5 Payment Attempts

Completed:

```text
Attempt Creation
Multiple Attempts per Order
Success
Failure
Pending
Requires Verification
Retry
Attempt Ownership
Attempt History
```

Example:

```text
Order
 ├── Attempt 1 — Failed
 ├── Attempt 2 — Failed
 └── Attempt 3 — Captured
```

## 3.6 Deterministic Sandbox

Completed scenarios include:

```text
SUCCESS
FAILURE
PENDING
Verification
Duplicate Webhook
Invalid Signature
Amount Mismatch
Currency Mismatch
Expiry
Captured After Expiry
```

It is for development, demo, diagnostics, integration, and security testing.

It is **not real money**.

## 3.7 Successful Payment

Completed flow:

```text
Registration
→ Order
→ Attempt
→ Sandbox Success
→ Signed Webhook
→ Signature Validation
→ Timestamp Validation
→ Amount/Currency Validation
→ Order Paid
→ Registration Confirmed
→ Audit
→ Timeline
```

## 3.8 Failed Payment

Implemented:

```text
Payment Failed
→ Registration Preserved
→ Attempt History Preserved
→ Attendee Failure UX
→ Retry When Safe
```

Fresh Flutter live E2E proof is still part of Sprint 6.

## 3.9 Retry

Backend and frontend implementation exist.

Current status:

```text
Implementation             ✅
Backend tests               ✅
Widget tests                ✅
Fresh live UI E2E           🔄 Sprint 6
```

## 3.10 Pending Payment

Backend and frontend implementation exist.

Expected attendee message:

```text
Payment confirmation is pending.
If money was deducted, don't pay again yet.
```

Current status:

```text
Backend                      ✅
Frontend                     ✅
Fresh pure-Pending live E2E  🔄 Sprint 6
```

## 3.11 Requires Verification

Completed:

```text
Pending
→ Verification Window
→ Requires Verification
→ Attendee Checks Status
```

Retry is blocked while verification is active.

## 3.12 Payment Verification

Completed attendee verification flow:

```text
Check Payment Status
→ Backend Re-check
→ Authoritative State
→ Flutter Refresh
```

Flutter does not mark payment successful locally.

## 3.13 Webhook Security

Completed:

```text
HMAC Signature
Signed Timestamp
Maximum Age
Future Clock Skew
Replay Protection
Duplicate Event Protection
Amount Validation
Currency Validation
Idempotent Processing
Concurrent Webhook Safety
```

## 3.14 Duplicate Protection

Completed layers include:

```text
Registration Uniqueness
Order Idempotency
Active Order Reuse
Unresolved Attempt Guard
DB Constraints
Webhook Idempotency
Concurrent Transaction Protection
```

## 3.15 Concurrency Protection

Verified areas include:

```text
Duplicate Registration
Concurrent Payment Initiation
Concurrent Attempt Creation
Concurrent Webhook Processing
Concurrent Event State Transition
Concurrent Check-In
```

## 3.16 Captured After Seat Expiry

Implemented exception:

```text
PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY
```

Behavior:

```text
Funds Captured
→ Preserve Financial Success
→ Do Not Silently Overbook
→ Do Not Silently Discard Payment
→ Create Exception
→ Human Resolution Required
```

## 3.17 Payment Exceptions

Current status:

```text
Create Exception      ✅
Persist Exception     ✅
List in Diagnostics   ✅
Resolve in Production ❌
Assign Owner          ❌
Close Exception       ❌
Admin Operations UI   ❌
```

## 3.18 Expiry Lifecycle

Completed:

```text
Seat Hold Expiry
Payment Order Expiry
Idempotent Sweeps
Concurrency-Safe Sweep
Manual Admin Trigger
Scheduler-Safe Script
```

## 3.19 Authentication and RBAC

Completed production roles:

```text
platform_admin
event_admin
finance_operator
auditor
support
```

Production admin/business APIs use Firebase JWT + server-side RBAC.

## 3.20 Audit Trail

Audit foundation covers:

```text
Registration
Payment
Configuration
Role Grants/Revoke
Events
Sessions
Check-In
People
Sponsors
Partners
Lifecycle Expiry
```

## 3.21 Developer Diagnostics

Completed:

```text
API Request/Response
HTTP Status
Correlation ID
Idempotency Key
Registration State
Order State
Attempt State
Technical Timeline
Scenario Runner
Payment Exceptions
Security Scenarios
```

---

# 4. Frontend — Completed Features

## 4.1 Authentication

Completed:

```text
Firebase Login
Backend Token Exchange
Bearer Token API Calls
Session Persistence
Logout
```

## 4.2 My Registrations

Completed returning-attendee list covering:

```text
seat_held
payment_pending
payment_failed
payment_verification
registered + paid
registered + free
cancelled
```

## 4.3 My Payments / Payment Detail

Current design intentionally uses:

```text
My Registrations
→ Continue Payment / View Payment / Check Status
```

No duplicate standalone My Payments list was created.

## 4.4 Already-Paid Reopen

Completed:

```text
Login
→ My Registrations
→ Paid Registration
→ View Payment
→ Success
→ Timeline
```

`latest_order_id` enables this flow.

## 4.5 Payment Review

Completed backend-sourced display:

```text
Base Fee
GST
Convenience Fee
Final Amount
```

## 4.6 Payment Status UX

Implemented:

```text
Success
Failure
Pending
Requires Verification
Paid
Registration Confirmed
```

## 4.7 Attendee Timeline

Friendly attendee events include:

```text
Seat Reserved
Payment Order Created
Payment Started
Payment Successful
Registration Confirmed
```

## 4.8 Restart Recovery

Completed:

```text
App Restart
→ Session Restored
→ Registrations Refetched
→ Backend State Reconstructed
```

## 4.9 Cross-User Security

Verified:

```text
User B cannot read User A order
User B cannot read User A timeline
User B cannot verify User A attempt
User B cannot access User A registration
```

## 4.10 Financial Tampering Resistance

Forged values do not override backend state:

```text
final_amount
base_amount
gst_rate
gst_amount
amount_paid
currency
status
registration_status
configuration_id
configuration_version
```

---

# 5. In Progress / Next — Sprint 6

## Project

```text
NITKSAA-PAYMENT
```

## Goal

```text
Integration Test Reliability
+
Payment Recovery Live E2E Closure
```

## Work

```text
Repair auth_flow_test.dart
Repair attendee_success_flow_test.dart
Root-Cause Diagnostics Timeout
Deterministic Test Data
Scenario Isolation
Failure
Failure → Retry → Success
Pure Pending
Requires Verification
Rapid Double Tap
Explicit Expiry
Restart Recovery
Cross-User Denial
Repeatable E2E Runs
```

Target:

```text
No mandatory PARTIAL E2E acceptance criteria
```

---

# 6. Major Pending Backend Features

## 6.1 Real Payment Gateway

Pending:

```text
Gateway Selection
Gateway Interface / Adapter
Production Gateway Order
Checkout Session
Payment Verification API
Production Webhook
Real Status Query
Gateway Error Mapping
Timeout Handling
Retry Handling
Gateway Credentials
Secret Rotation
Sandbox/Production Separation
```

Potential gateway: CCAvenue, subject to final decision.

## 6.2 Reconciliation

Pending:

```text
Internal Order ↔ Gateway Matching
Gateway Transaction Import
Missing Webhook Detection
Orphan Payment Detection
Paid at Gateway / Pending in Portal
Amount Mismatch Detection
Duplicate Payment Detection
Settlement Matching
Daily Reconciliation
Finance Exception Queue
Resolution Audit
```

## 6.3 Cancellation

Pending:

```text
Attendee Cancellation
Admin Cancellation
Deadline
Policy
Reason
Approval/Rejection
Seat Release
Breakfast Count Adjustment
Audit
Notification
```

## 6.4 Registration Transfer

Pending:

```text
Transfer Eligibility
Transfer Deadline
Recipient Identity
Recipient Verification
Approval if Required
Ownership Change
Payment Relationship
Breakfast Count
Audit
Notification
```

Transfer should be first-class, not an afterthought.

## 6.5 Refund

Pending:

```text
Refund Request
Full Refund
Partial Refund
Approval
Rejection
Finance Operator
Finance Approver
Gateway Refund
Refund Status
Refund Retry
Refund Webhook
Refund Timeline
Refund Reconciliation
Refund Receipt
Credit Note
Seat Release Relationship
```

## 6.6 Manual / Offline Payment

Decision pending on support for:

```text
Bank Transfer
Manual UPI
Cash
Manual Reference
Payment Proof
Finance Verification
Manual Confirmation
```

If supported, it must not bypass audit or duplicate protection.

## 6.7 Receipts

Pending:

```text
Receipt Number
Payment Date
Attendee
Event
Amount
Tax Breakdown
Payment Reference
PDF
Email
History
```

## 6.8 GST Invoice

Pending:

```text
Invoice Request
Billing Address
GST Details
Invoice Number
Tax Breakdown
GSTIN where applicable
PDF
Email
Download
```

Billing address should be collected only when required.

## 6.9 Credit Note

Pending:

```text
Credit Note Number
Invoice Reference
Refund Reference
Tax Adjustment
PDF
Email
Audit
```

---

# 7. Advanced Pricing — Pending

Current pricing foundation exists, but business-rule pricing is pending.

Need support for:

```text
Individual
Couple
Family
Alumni Family
Both Spouses Alumni
Parent + Child Alumni
Group
Early Bird
Promotion
Sponsor Funded
Complimentary
Physical Attendance
Virtual Attendance
Coupon
Manual Committee Discount
```

Rules must be configurable, not hard-coded.

## 7.1 Discount Engine

Pending:

```text
Eligibility
Start / End Date
Usage Limit
Per-User Limit
Percentage / Fixed Amount
Maximum Discount
Stacking
Priority
Audit
```

## 7.2 Coupon Codes

Pending:

```text
Code
Validity
Usage Limits
Event Scope
User Scope
Amount / Percentage
Stackable?
Active / Disabled
Audit
```

## 7.3 Complimentary / Sponsor-Funded

Pending:

```text
Sponsor Code
Complimentary Registration
Approval
Sponsor Attribution
Zero Payable Amount
Audit
Financial Reporting
```

---

# 8. Notifications — Pending

Potential payment notifications:

```text
Payment Started
Payment Successful
Payment Failed
Payment Pending
Verification Required
Retry Reminder
Seat Hold Expiring
Payment Link Expiring
Registration Confirmed
Cancellation
Transfer
Refund Started
Refund Completed
Refund Failed
```

Channels:

```text
Email
WhatsApp
```

---

# 9. Admin / Finance Portal — Pending

Need:

```text
Payments Dashboard
Transaction Search
Attendee Search
Registration Search
Gateway Reference Search
Status Filters
Event/Date Filters
Payment Detail
Finance Timeline
Exception Viewer
Exception Resolution
Refund View
Reconciliation View
Export
Audit Viewer
```

---

# 10. Payment Exception Resolution — Pending

Suggested lifecycle:

```text
OPEN
→ UNDER_REVIEW
→ ASSIGNED
→ RESOLVED
→ CLOSED
```

Suggested fields:

```text
owner
severity
priority
resolution
comments
resolved_by
resolved_at
timeline
```

---

# 11. Metrics and Analytics — Pending

Operational metrics:

```text
Success Rate
Failure Rate
Retry Rate
Pending Rate
Verification Rate
Average Payment Time
Gateway Latency
Duplicate Prevention Count
Refund Rate
Reconciliation Exception Count
```

Product funnel analytics:

```text
Registration Started
Payment Started
Payment Completed
Payment Failed
Payment Abandoned
Retry Used
Recovered Payment
Conversion Rate
Drop-Off Point
```

This directly addresses the original pain point where many users started payment but only a smaller subset completed successfully on the first attempt.

---

# 12. Data Retention / Cleanup — Pending

Need explicit policy for:

```text
Payment Orders
Payment Attempts
Webhook Events
Payment Exceptions
Audit Logs
Failed Registrations
Expired Holds
Billing Addresses
Invoices
Refunds
Diagnostic Data
```

Need decisions for:

```text
Retention Period
Archive
Anonymization
Deletion
Legal Hold
Cleanup Schedule
Audit Preservation
```

---

# 13. Production Security — Pending Before Real Money

Required:

```text
Real Gateway Threat Model
Rate Limiting
WAF/API Abuse Protection
Secret Manager
Key Rotation
Production Firebase/RBAC Review
SAST
SCA
Dependency Scan
DAST/API Security Test
Penetration Test
Fraud/Abuse Tests
Load Test
Monitoring
Alerts
Incident Runbook
Privacy/Logging Review
```

The target is not “unhackable”.

The target is:

```text
Defense in Depth
Least Privilege
Server-Authoritative Financial State
Immutable Financial History
Replay Resistance
Tamper Resistance
Auditability
Monitoring
Recovery
```

---

# 14. Backup / Disaster Recovery — Pending

Need deployment-level decisions for:

```text
PostgreSQL Backup
Point-in-Time Recovery
Restore Testing
RPO
RTO
Payment Recovery
Audit Recovery
Gateway Reconciliation after Restore
```

---

# 15. Production Deployment — Pending

Need:

```text
Production APP_ENV
Production DB
Production Firebase
Gateway Credentials
Secret Manager
HTTPS
Rate Limiting
Monitoring
Alerts
Scheduler
Backups
Rollback
Runbook
Incident Response
```

---

# 16. Recommended Roadmap

| Sprint | Project | Objective |
|---|---|---|
| Sprint 6 | NITKSAA-PAYMENT | E2E Reliability + Payment Recovery Closure |
| Sprint 7 | NITKSAA-EVENT | Real Payment Gateway Foundation |
| Sprint 8 | Both | Real Gateway Checkout + Recovery |
| Sprint 9 | Backend/Admin | Reconciliation + Exception Operations |
| Sprint 10 | Both | Cancellation + Transfer + Refund |
| Sprint 11 | Both | Receipt + GST Invoice + Credit Note |
| Sprint 12 | Backend/Integration | Email + WhatsApp Notifications |
| Sprint 13 | Both | Advanced Pricing + Coupons + Offers |
| Sprint 14 | Backend | Retention + Cleanup + Archival |
| Sprint 15 | Both | Production Security + Load Test + Pen Test + Go-Live |

---

# 17. Recommended Critical Path for the Breakfast Meeting

Do not wait for every advanced feature before the first controlled real-money pilot.

Recommended path:

```text
Sprint 6
E2E Verification Closure
        ↓
Real Gateway
        ↓
Real Gateway Verification
        ↓
Reconciliation
        ↓
Payment Exception Operations
        ↓
Monitoring / Rate Limiting / Secrets
        ↓
Security Testing
        ↓
Limited Real-Money Pilot
```

Then add:

```text
Transfer
Cancellation
Refund
Receipt
Invoice
Notifications
Advanced Pricing
Coupons
```

---

# 18. Minimum Before Accepting Real Money

Recommended minimum:

```text
Real Gateway
Server-Side Gateway Verification
Webhook Security
Duplicate Protection
Pending Handling
Payment Recovery
Reconciliation
Admin Transaction View
Production Secrets
Rate Limiting
Monitoring
Alerts
Audit
Backups
Operational Runbook
Security Review
Limited Pilot
```

---

# 19. Attendee UX Principle

Keep the user experience:

```text
My Registrations
      ↓
Breakfast Meeting
      ↓
₹118 — Payment Pending
      ↓
Pay Now
      ↓
Payment Successful
      ↓
Registration Confirmed
```

The attendee should not need to understand:

```text
Orders
Attempts
Webhook Signatures
Idempotency
Replay
Configuration Versions
Verification Windows
Database Locks
Exception Types
```

---

# 20. Final Current-State Classification

## Backend

```text
Payment Sandbox/Foundation        ✅ Completed
Payment Security Foundation       ✅ Completed
Admin RBAC                        ✅ Completed
Operational Lifecycle             ✅ Completed
Real Gateway                      ❌ Pending
Reconciliation                    ❌ Pending
Refund Operations                 ❌ Pending
Production Financial Operations   ❌ Pending
```

## Frontend

```text
Payment Flow Lab                  ✅ Completed
Attendee Payment UX               ✅ Completed
My Registrations                  ✅ Completed
Returning Attendee Recovery       ✅ Completed
Paid/Pending/Verification UX      ✅ Completed
Failure/Retry UX                  ✅ Implemented
E2E Reliability Closure           🔄 Next / In Progress
Real Gateway Checkout             ❌ Pending
Refund/Cancellation/Transfer      ❌ Pending
Invoice/Receipt                   ❌ Pending
```

## Overall

```text
Current:
Pilot Ready for deterministic sandbox payment and returning-attendee experience.

Not Yet:
Production Ready for real money.

Immediate Next:
NITKSAA-PAYMENT — Sprint 6
Integration Test Reliability + Payment Recovery Live E2E Closure.

Then:
Real Payment Gateway Foundation.
```
