# NITKSAA Event & Payment Platform
## Beta Testing, Hosting, and Day-wise Rollout Plan

**Projects**
- `nitksaa-event` — FastAPI backend, PostgreSQL, authentication, registration, payment, webhook, refund, admin APIs
- `nitksaa-payment` — Flutter frontend for Web / macOS Chrome initially, later iOS and Android
- **Beta/Test domain:** `itelematics.com`
- **Production domain:** `nitkalumni.in`

**Primary objective:** Move from local/zrok development to a stable hosted beta environment, complete real-world end-to-end validation, and then prepare a controlled production launch.

---

# 1. High-Level Plan

The rollout should happen in four controlled stages.

## Stage 1 — Stabilize TEST Mode locally
Complete all remaining Razorpay Test Mode flows locally:

- FREE event registration
- Paid ₹1 Test event
- Razorpay Checkout
- server-side `verify-checkout`
- webhook processing
- payment retry
- cancellation
- full refund
- refund status
- app/browser refresh and recovery
- TEST/LIVE UI separation
- security and regression tests

**Exit condition:** Local TEST Mode is fully stable and repeatable.

---

## Stage 2 — Host Beta Environment

Deploy:

```text
Frontend:
events-test.itelematics.com
→ Vercel
→ NITKSAA-PAYMENT Flutter Web

Backend:
api-events-test.itelematics.com
→ Railway
→ NITKSAA-EVENT FastAPI

Database:
Railway PostgreSQL
→ dedicated beta/test database

Razorpay:
TEST credentials only
→ TEST webhook
→ no real money
```

This environment is for developers, testers, invited alumni, and controlled beta users.

**Exit condition:** Beta users can complete all use cases from browser without depending on localhost, zrok, or the developer's Mac.

---

## Stage 3 — Controlled LIVE Pilot

Create a separate LIVE environment/configuration using:

```text
Production frontend:
nitkalumni.in/events

Production backend:
api-events.nitkalumni.in

Production database:
separate production PostgreSQL

Razorpay:
LIVE credentials
LIVE webhook
₹1 real-money pilot
```

Do not mix Test and Live data.

**Exit condition:** One or more controlled ₹1 real transactions and refunds complete successfully with full audit evidence.

---

## Stage 4 — Production Launch

After beta sign-off:

- production database
- production Firebase/auth configuration
- Razorpay Live keys
- production domains
- backup/restore plan
- monitoring
- admin readiness
- public user rollout
- optional native iOS/Android distribution

---

# 2. Recommended Hosting Architecture

## Beta

```text
Beta User Browser
        |
        v
https://events-test.itelematics.com
        |
        v
Vercel
NITKSAA-PAYMENT Flutter Web
        |
        | HTTPS API
        v
https://api-events-test.itelematics.com
        |
        v
Railway
NITKSAA-EVENT FastAPI
        |
        v
Railway PostgreSQL
        ^
        |
        +---- Razorpay TEST Webhooks
```

## Production

```text
Production User
        |
        v
https://nitkalumni.in/events
        |
        v
Vercel
NITKSAA-PAYMENT Flutter Web
        |
        v
https://api-events.nitkalumni.in
        |
        v
Railway
NITKSAA-EVENT FastAPI
        |
        v
Production PostgreSQL
        ^
        |
        +---- Razorpay LIVE Webhooks
```

---

# 3. Why This Hosting Model

## NITKSAA-PAYMENT → Vercel

Flutter Web produces static web assets after:

```bash
flutter build web
```

Vercel is well suited for:

- static hosting
- HTTPS
- custom domains
- preview deployments
- GitHub-based deployment
- quick rollback
- beta branch deployment

Recommended beta URL:

```text
events-test.itelematics.com
```

Recommended production URL:

```text
nitkalumni.in/events
```

---

## NITKSAA-EVENT → Railway

The FastAPI backend needs:

- persistent HTTPS API
- PostgreSQL
- environment secrets
- Razorpay webhook handling
- database migrations
- operational logs
- stable server process

Railway fits this model well.

Recommended beta API:

```text
api-events-test.itelematics.com
```

Recommended production API:

```text
api-events.nitkalumni.in
```

---

# 4. Environment Separation

Never use a single environment for both Test and Production.

## Beta/Test

```text
Domain:
itelematics.com

Frontend:
events-test.itelematics.com

Backend:
api-events-test.itelematics.com

Database:
events_beta

Razorpay:
TEST keys

Webhook:
TEST webhook secret

Payment:
No real money
```

## Production

```text
Domain:
nitkalumni.in

Frontend:
nitkalumni.in/events

Backend:
api-events.nitkalumni.in

Database:
events_prod

Razorpay:
LIVE keys

Webhook:
LIVE webhook secret

Payment:
Real money
```

---

# 5. Required Backend Environment Variables

Beta Railway should contain server-only values such as:

```text
EVENTS_DB_URL
APP_ENV=beta

FIREBASE_PROJECT_ID
FIREBASE related server configuration

RAZORPAY_TEST_KEY_ID
RAZORPAY_TEST_KEY_SECRET
RAZORPAY_TEST_WEBHOOK_SECRET

CORS_ALLOWED_ORIGINS=https://events-test.itelematics.com
```

Production later:

```text
APP_ENV=production

RAZORPAY_LIVE_KEY_ID
RAZORPAY_LIVE_KEY_SECRET
RAZORPAY_LIVE_WEBHOOK_SECRET

CORS_ALLOWED_ORIGINS=https://nitkalumni.in
```

Never store Key Secret or Webhook Secret in Flutter, GitHub, Vercel public variables, logs, or documentation.

---

# 6. Razorpay Beta Configuration

For beta:

```text
Mode:
TEST

Frontend:
events-test.itelematics.com

Backend webhook:
https://api-events-test.itelematics.com/api/v1/payment-gateways/razorpay/test/webhook
```

Enable:

```text
payment.authorized
payment.captured
payment.failed
order.paid
refund.created
refund.processed
refund.failed
```

Use a dedicated TEST webhook secret.

---

# 7. Razorpay Production Configuration

Production must have a completely separate setup:

```text
Mode:
LIVE

Frontend:
nitkalumni.in/events

Backend webhook:
https://api-events.nitkalumni.in/api/v1/payment-gateways/razorpay/live/webhook
```

Use:

```text
RAZORPAY_LIVE_KEY_ID
RAZORPAY_LIVE_KEY_SECRET
RAZORPAY_LIVE_WEBHOOK_SECRET
```

The first production payment should be a controlled ₹1 real-money transaction.

---

# 8. Beta Testing Scope

Beta testing should cover all major attendee and admin journeys.

## Admin

Test:

- login
- create event
- edit event
- publish event
- free event
- paid event
- Test/Live configuration separation
- event status lifecycle
- payment configuration
- event listing
- registration list
- payment/refund visibility
- admin session stability
- role permissions

---

## Attendee — FREE Event

Test:

```text
Open event
→ Check eligibility
→ Register
→ Confirmation
→ My Registrations
→ Cancel
→ Cancelled
```

Expected:

```text
No payment order
No Razorpay Checkout
No refund
```

---

## Attendee — Paid TEST Event

Test:

```text
Open paid event
→ Register
→ seat held
→ payment review
→ Razorpay Test Checkout
→ payment success
→ verify-checkout
→ registration confirmed
→ My Registrations
```

Also test:

```text
payment failure
retry payment
browser refresh
app restart
continue payment
expired payment attempt
```

---

## Cancellation / Refund

Test:

```text
Paid registration
→ Cancel
→ confirmation dialog
→ refund requested
→ refund pending
→ refund processed
```

Verify:

- one refund only
- correct amount
- correct payment mode
- provider refund ID
- no duplicate refund
- status recovers after refresh

---

# 9. Browser / Device Matrix

For beta, start with Web.

## Mandatory

- Chrome on macOS
- Chrome on Windows
- Safari on macOS
- Chrome on Android
- Safari on iPhone

## Later

- Flutter iOS native
- Flutter Android native

No App Store / Play Store review is needed for the web beta.

---

# 10. Beta User Groups

Use phased user expansion.

## Group 1 — Internal Developers

2–5 users.

Focus:

- technical flow
- logs
- payment states
- edge cases
- diagnostics

## Group 2 — Internal Admin / Committee

5–10 users.

Focus:

- admin usability
- event creation
- event publishing
- payment visibility
- registration management

## Group 3 — Trusted Alumni Beta

10–25 users.

Focus:

- usability
- browser/device compatibility
- registration clarity
- retry
- refund UX

## Group 4 — Expanded Beta

50–100 users.

Only after Groups 1–3 are stable.

---

# 11. Beta Test Scenarios

## Critical P0

- user can login
- event list loads
- free registration works
- paid registration works
- Razorpay Checkout opens
- payment is confirmed only after backend verification
- webhook works
- registration confirmation works
- cancel works
- refund works
- duplicate payment prevented
- duplicate refund prevented

## P1

- retry after failure
- browser refresh recovery
- session expiry
- payment pending
- payment status check
- mobile browser compatibility
- admin event management

## P2

- visual polish
- wording
- performance
- empty states
- minor UX improvements

---

# 12. Security Beta Checklist

Verify:

- secrets never reach Flutter
- no API Key Secret in browser
- no Webhook Secret in browser
- amount is server-authoritative
- currency is server-authoritative
- payment success is server-authoritative
- refund is server-authoritative
- IDOR prevented
- unauthorized registration access prevented
- unauthorized cancellation prevented
- invalid webhook rejected
- tampered webhook rejected
- duplicate webhook idempotent
- CORS restricted
- HTTPS only
- Test/Live separation enforced

---

# 13. Operational Checklist

Before opening beta:

- Railway health endpoint green
- PostgreSQL migrations current
- Vercel deployment green
- DNS working
- HTTPS working
- CORS working
- Firebase auth working
- Razorpay Test webhook active
- test event available
- test users available
- admin user available
- logs accessible
- rollback plan available

---

# 14. Logging and Monitoring

For beta, capture:

- API errors
- payment failures
- webhook failures
- refund failures
- authentication failures
- database errors
- unexpected 5xx
- payment reconciliation issues

Add correlation fields where possible:

```text
event_id
registration_id
order_id
attempt_id
provider_order_id
payment_mode
refund_id
```

Never log secrets.

---

# 15. Backup Plan

For beta PostgreSQL:

- automatic daily backup
- backup before migration
- restore test before production
- no local-only database dependency

Before production:

- production backup policy
- retention
- restore drill
- migration rollback procedure

---

# 16. Day-wise Implementation and Beta Progress Plan

## Day 0 — Current State

Already completed / substantially completed:

- NITKSAA-EVENT backend payment architecture
- deterministic sandbox
- Razorpay Test integration
- payment attempts
- checkout verification
- webhook signature verification
- cancellation/refund APIs
- payment recovery
- admin auth hardening
- Flutter payment integration
- Razorpay frontend integration
- My Registrations
- retry
- cancellation/refund UX
- Test/Live mode design in progress
- local zrok testing
- Razorpay website approval for `itelematics.com/events`

**Current gap:** move from local/zrok to permanent beta hosting.

---

## Day 1 — Freeze Beta Architecture

Tasks:

- confirm beta domains
- confirm production domains
- confirm Vercel for frontend
- confirm Railway for backend/database
- create beta deployment checklist
- freeze environment variable names
- freeze Test/Live separation
- confirm beta database strategy

Deliverable:

```text
Beta architecture approved
Domain plan approved
Deployment checklist ready
```

---

## Day 2 — Host NITKSAA-EVENT Backend

Tasks:

- create Railway project
- connect GitHub repo
- configure FastAPI start command
- create Railway PostgreSQL
- configure beta environment variables
- run migrations
- deploy backend
- verify `/api/v1/health`
- configure backend custom domain

Target:

```text
https://api-events-test.itelematics.com
```

Deliverable:

```text
Backend hosted
Database hosted
Health check PASS
```

---

## Day 3 — Razorpay Test Webhook Migration

Tasks:

- replace zrok webhook URL
- configure permanent beta webhook
- verify Test webhook secret
- verify all 7 events
- send signed verification
- run ₹1 Test payment
- verify `payment.captured`
- verify `order.paid`
- cancel
- verify refund webhook

Deliverable:

```text
Permanent Razorpay Test integration PASS
zrok no longer required
```

---

## Day 4 — Host NITKSAA-PAYMENT Frontend

Tasks:

- configure Vercel
- build Flutter Web
- point frontend to hosted API
- configure beta environment
- set custom domain

Target:

```text
https://events-test.itelematics.com
```

Test:

- Firebase login
- API access
- CORS
- events
- registrations
- payments

Deliverable:

```text
Public beta frontend online
```

---

## Day 5 — Internal End-to-End QA

Run full scenarios:

### FREE

```text
create
publish
register
cancel
```

### PAID

```text
register
pay
verify
webhook
confirm
cancel
refund
```

### Recovery

```text
refresh
restart
retry
pending status
```

Test:

- Chrome/macOS
- Safari/macOS
- Chrome/Windows if available

Deliverable:

```text
Internal QA report
P0 issues = 0
```

---

## Day 6 — Admin and Security Validation

Tasks:

- admin event creation
- payment configuration
- role checks
- session behavior
- CORS
- IDOR checks
- webhook tampering
- duplicate payment
- duplicate refund
- audit verification
- diagnostics

Deliverable:

```text
Security/RGIS review complete
```

---

## Day 7 — Small Closed Beta

Invite:

```text
5–10 trusted users
```

Ask them to test:

- login
- event discovery
- free registration
- paid Test registration
- retry
- cancellation
- refund
- My Registrations

Capture:

```text
Device
Browser
Scenario
Expected
Actual
Severity
Screenshot
Comment
```

Deliverable:

```text
Closed Beta Round 1 report
```

---

## Day 8 — Fix Beta Findings

Prioritize:

```text
P0 = blocker
P1 = important
P2 = polish
```

Fix all P0.

Prefer fixing P1 before larger beta.

Re-run:

```text
backend tests
flutter tests
web build
smoke E2E
```

Deliverable:

```text
Beta Release Candidate 2
```

---

## Day 9 — Expanded Beta

Invite:

```text
20–50 users
```

Test across:

- macOS
- Windows
- Android browser
- iPhone browser

Measure:

- registration success rate
- payment success rate
- retry rate
- refund success
- API errors
- webhook failures

Deliverable:

```text
Expanded Beta Report
```

---

## Day 10 — Production Readiness Review

Review:

- all P0 closed
- P1 acceptable
- Test/Live separation
- production domains
- production DB
- backup
- monitoring
- Razorpay Live credentials
- Live webhook
- access control
- admin readiness

Deliverable:

```text
GO / NO-GO decision
```

---

## Day 11 — Production Infrastructure Setup

Set up:

```text
nitkalumni.in/events
api-events.nitkalumni.in
Production Railway PostgreSQL
Production FastAPI
Production Vercel deployment
```

Do not enable broad user access yet.

Deliverable:

```text
Production infrastructure ready
```

---

## Day 12 — Controlled LIVE ₹1 Pilot

Use one authorized tester.

Flow:

```text
LIVE ₹1 event
→ register
→ real ₹1 payment
→ verify-checkout
→ real payment webhook
→ confirm registration
→ cancel
→ real ₹1 refund
→ refund webhook/status
```

Verify:

```text
R = PASS
G = PASS
I = PASS
S = PASS
```

Deliverable:

```text
Live payment validation report
```

---

## Day 13 — Production Smoke Test

Test:

- free event
- paid event
- authentication
- registration
- payment
- refund
- admin
- email/confirmation
- audit
- monitoring

Deliverable:

```text
Production smoke test PASS
```

---

## Day 14 — Controlled Production Launch

Start with limited users.

Monitor:

- payments
- refunds
- errors
- webhook failures
- database health
- authentication
- user feedback

Increase exposure gradually.

---

# 17. Beta Exit Criteria

Beta is considered successful when:

```text
P0 defects = 0
critical P1 = 0
FREE registration PASS
Paid Test payment PASS
Retry PASS
Webhook PASS
Cancellation PASS
Refund PASS
Browser recovery PASS
Admin PASS
Security PASS
Test/Live isolation PASS
Backup PASS
Monitoring PASS
```

---

# 18. Production Go-Live Criteria

Before production:

```text
nitkalumni.in configured
production DB separate
production secrets separate
Razorpay Live keys configured
Live webhook configured
₹1 real-money pilot PASS
real refund PASS
all secrets protected
production CORS locked
production backup enabled
admin access verified
monitoring enabled
rollback plan documented
```

---

# 19. Native App Plan

Native apps are not required for the initial beta.

Start with:

```text
Flutter Web
→ Chrome/Safari
→ no Apple/Google review
```

After web beta is stable:

```text
iOS
→ TestFlight
→ selected testers

Android
→ Google Play Internal Testing
→ selected testers
```

Public App Store / Play Store submission should happen only after the web/payment flows are stable.

---

# 20. Recommended Final Environment Matrix

| Environment | Frontend | Backend | DB | Razorpay | Money |
|---|---|---|---|---|---|
| Local Dev | localhost | localhost | local PostgreSQL | Test | No |
| Beta | `events-test.itelematics.com` | `api-events-test.itelematics.com` | Beta PostgreSQL | Test | No |
| Production | `nitkalumni.in/events` | `api-events.nitkalumni.in` | Production PostgreSQL | Live | Yes |

---

# 21. Recommended Immediate Next Step

The next task should be:

```text
Host NITKSAA-EVENT on Railway
+ create beta PostgreSQL
+ expose api-events-test.itelematics.com
+ migrate Razorpay Test webhook from zrok to the permanent beta API
```

After backend hosting is stable:

```text
Deploy NITKSAA-PAYMENT Flutter Web to Vercel
→ events-test.itelematics.com
```

Then begin closed beta testing.
