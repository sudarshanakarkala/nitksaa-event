# NITKSAA Events Validation Run

> **IN PROGRESS** — started Sat 3 Oct 2026, 16:10 IST. Rows marked PENDING are waiting on a human step. This line is removed when the run is complete.

## Smoke test — Admin App

| Check | Result | Notes | Screenshot |
|---|---|---|---|
| Loads | PASS | `https://nitksaa-events-admin.web.app` returns 200 and redirects to `/login`. Login card shows "Backend online" (`GET /api/v1/health` → 200, `env: production`, `db: ok`). Deployed bundle points at the production API URL. | `s7-screenshots/admin-01-loads.png` |
| Google sign-in works | PENDING | Needs Sudarshana to sign in. | |
| Platform admin sees events | PENDING | Needs sign-in. | |
| No CORS errors | PENDING | Before sign-in: 0 console errors, 0 failed requests. API preflight for origin `https://nitksaa-events-admin.web.app` returns 200 with matching `access-control-allow-origin`. Signed-in console still to be checked. | |

## Smoke test — Flutter Frontend

| Check | Result | Notes | Screenshot |
|---|---|---|---|
| Page loads | PASS | `https://nitksaa-events.web.app` returns 200 and lands on `/#/home`. Console shows one Flutter error on load, `Bad state: RenderBox was not laid out`; the page still renders. | `s7-screenshots/attendee-01-loads.png` |
| Deep-link hard refresh works | PASS | Opened `/#/my-events` directly, then reloaded: app loads and stays on `/#/my-events`, showing "Log in to view My Events" (signed out). | `s7-screenshots/attendee-02-deeplink-refresh.png` |
| Google sign-in works | PENDING | Needs Sudarshana to sign in. | |
| Events list loads | PASS (signed out) | `GET /api/v1/events/public?page=1&per_page=100&period=upcoming` → 200; 8 events shown. To be re-checked signed in. | `s7-screenshots/attendee-01-loads.png` |
| No CORS errors | PENDING | Before sign-in: no CORS errors. Two requests to `https://checkout-static-next.razorpay.com/build/undefined` fail with `ERR_BLOCKED_BY_ORB` (seen in headless Chromium; to be confirmed in a normal browser). `index.html` loads Razorpay `checkout.js` twice (once in `<head>`, once in `<body>`). Signed-in console still to be checked. | |
| My Events loads | PENDING | Needs sign-in. | |

## ₹1 Deployed Attendee Test

| Check | Result | Notes | Screenshot |
|---|---|---|---|
| ₹1 payment succeeds | PENDING | | |
| Registration shows paid | PENDING | | |
| Badge issued | PENDING | | |
| Appears in association Razorpay Test dashboard | PENDING | | |
| Checkout shows association name | PENDING | | |
| Payment webhook POST 200 | PENDING | Log access confirmed from Sudarshana's gcloud account (read-only query from the plan). Baseline before this test: latest webhook rows are 3 × POST 200 at 05:21:25–27 UTC (10:51 IST) and 3 × POST 200 at 02:17:13–14 UTC (07:47 IST). | |

## Section 7a — Dashboard Refund Fallback

| Check | Result | Notes | Screenshot |
|---|---|---|---|
| Razorpay dashboard refund succeeds | PENDING | | |
| `refund.processed` received | PENDING | | |
| Webhook POST 200 | PENDING | | |
| Registration updated to refunded | PENDING | | |

## S7 — Validation Run

| # | Test | How | Expected | Result | Notes | Screenshot |
|---|---|---|---|---|---|---|
| V1 | Successful payment | Register for a paid event, pay `success@razorpay` | Registered; badge issued | PENDING | | |
| V2 | Failed payment | Pay `failure@razorpay` | Clear failure message; no badge; retry possible | PENDING | | |
| V3 | Cancelled checkout | Open checkout, close the popup | "Payment cancelled"; seat held; retry possible | PENDING | | |
| V4 | Retry reuses registration | Retry after V2/V3, pay successfully | Same registration reused; exactly one paid order in Razorpay | PENDING | | |
| V5 | Webhook-only confirmation | Pay, close the tab immediately after success | Webhook confirms; shows paid on reload | PENDING | | |
| V6 | Multiple seats | Quantity > 1 | Correct total; correct number of seats/badges | PENDING | | |
| V7 | Free event | Register for a free event | Confirms without Razorpay | PENDING | As of 16:12 IST no published event is free (all 8 have `is_free: false`). | |
| V8 | Seat-hold expiry | Start checkout, don't pay, wait past hold time | Hold released; seat available again | PENDING | | |
| V9 | Full refund | Per the section 7 decision/admin fallback | Refunded in Razorpay; registration updated | PENDING | | |
| V10 | Partial refund (if supported) | Refund part of a multi-seat order | Correct amount; status correct | PENDING | | |
| V11 | Event full / closed | Capacity reached or registration closed | Clear message; no payment taken | PENDING | Suitable events already exist: "Oct 4NEW" (id 8) is full (capacity 1, 1 registered); ids 1, 2, 3, 4, 6 are closed. | |
| V12 | Android Chrome | Sign in, pay via UPI app, return to browser | Works end to end | PENDING | | |
| V13 | iPhone Safari | Google sign-in, pay, return | Works | PENDING | | |
| V14 | Laptop Chrome + Safari | Full flow | Works | PENDING | | |
| V15 | Eligibility / pricing | Non-alumni vs alumni | Correct eligibility and price each way | PENDING | | |
| V16 | Foreign webhook | Unknown/external Razorpay order | Ignored; returns 200; no registration touched | PENDING | | |
| V17 | Unregister | Free event and paid event | Free: cancelled + seat released. Paid: refund or blocked with message | PENDING | | |

## Items Requiring P

- [ ] A free test event is needed for V7 and for the free half of V17. None is published as of 16:12 IST on 3 Oct. Please confirm whether P or the admin will create one.

## Section 7 Decision Status

```text
7a result:
PENDING

7b:
Product decision required with P.
No implementation performed.
```

## Summary

```text
Admin smoke test: PENDING
Attendee smoke test: PENDING
₹1 deployed test: PENDING
Dashboard refund fallback: PENDING

S7:
PASS:
FAIL:
BLOCKED:
NOT SUPPORTED:
```

## Confirmation

```text
NO SOURCE CODE WAS MODIFIED.
NO DEPLOYMENT WAS PERFORMED.
NO DATABASE CHANGES WERE PERFORMED.
S6 — RETIRE iTELEMATICS WAS NOT PERFORMED BY CLAUDE.
```
