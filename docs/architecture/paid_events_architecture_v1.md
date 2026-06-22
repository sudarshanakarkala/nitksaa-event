# Paid Events — Architecture v1

**Date:** 2026-06-22
**Status:** ARCHITECTURE DOCUMENT — payment must not be implemented in Week 4 or Alpha
**Depends on:** migrations 001–009 (existing), registrations table
**Related decisions:** `week4_feedback_architecture_decisions.md` Decision 11

---

## Concept

The Event App must eventually support paid events — events where an alumnus pays a registration
fee before their registration is confirmed. Examples: NITKonnect dinner (₹1,500/person),
workshops with limited capacity (₹500/seat), fundraiser galas.

For the Jun 30 Alpha and the foreseeable near-term, all events are free. Payment is explicitly
not in scope. However, the schema must be designed now so that:

1. The `events` table can distinguish free from paid events without a breaking migration later.
2. The `registrations` table can reference a payment record when payment is required.
3. Admin and Flutter UI can display a "Free" or fee label correctly.

This document defines the schema for free/paid event types and the future payment table. No
payment gateway code is defined here. No Razorpay or Stripe integration is designed here.

---

## Alpha Decision

**All Alpha events are free. `registration_fee_type = 'FREE'` is the only value in use.**

The "Free" label on the event detail screen and registration screen may be displayed using
either:
- The `registration_fee_type` field (once the schema change is applied), or
- A simple UI default ("Free" when `registration_fee_amount` is null or zero)

Both approaches work for Alpha. The schema change is additive and safe to defer.

---

## Free vs. Paid Event Concept

| | Free event | Paid event |
|---|---|---|
| Registration fee | None | Fixed amount per registrant |
| Registration flow | Register → Confirmed immediately | Register → Payment pending → Payment confirmed → Registration confirmed |
| Cancellation | Simple status change | May require refund logic |
| Admin view | Registration count | Registration count + payment status + revenue total |
| Flutter flow | Register tap → Confirmation screen | Register tap → Payment screen → Confirmation screen |

The key difference is the **registration flow**. A paid event requires an intermediate `payment_pending`
state that does not exist in the current schema.

---

## Proposed Schema Changes to `events` Table

These columns are added in a future migration (not Week 4):

```sql
ALTER TABLE events
  ADD COLUMN registration_fee_type VARCHAR(10) NOT NULL DEFAULT 'FREE'
             CHECK (registration_fee_type IN ('FREE', 'PAID')),
  ADD COLUMN registration_fee_amount NUMERIC(10, 2),
             -- NULL for FREE events; required when PAID
  ADD COLUMN registration_fee_currency VARCHAR(3) NOT NULL DEFAULT 'INR',
  ADD COLUMN payment_required BOOLEAN NOT NULL DEFAULT false,
             -- true when registration_fee_type='PAID' and payment must clear before confirmation
  ADD COLUMN payment_provider VARCHAR(30);
             -- NULL = not applicable; future values: RAZORPAY | STRIPE
```

Validation rules (enforced at the API layer, not just DB):
- When `registration_fee_type = 'PAID'`: `registration_fee_amount` must be > 0
- When `registration_fee_type = 'FREE'`: `registration_fee_amount` must be null or 0
- `payment_required` follows `registration_fee_type` — `true` only when `PAID`

---

## Proposed `event_payments` Table (future)

Created when payment gateway integration is approved. Not created in Week 4 or Alpha.

```sql
CREATE TABLE event_payments (
    payment_id           SERIAL        PRIMARY KEY,
    registration_id      INT           NOT NULL REFERENCES registrations(registration_id),
    event_id             INT           NOT NULL REFERENCES events(event_id),
    firebase_uid         VARCHAR(128)  NOT NULL,
    amount               NUMERIC(10, 2) NOT NULL,
    currency             VARCHAR(3)    NOT NULL DEFAULT 'INR',
    provider             VARCHAR(30)   NOT NULL,
                         -- RAZORPAY | STRIPE | MANUAL
    provider_payment_id  TEXT,         -- payment ID from provider (Razorpay payment_id)
    provider_order_id    TEXT,         -- order ID from provider (Razorpay order_id)
    status               VARCHAR(20)   NOT NULL
                         CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
    paid_at              TIMESTAMPTZ,  -- set when status transitions to 'completed'
    failure_reason       TEXT,         -- populated on 'failed' status
    refund_reason        TEXT,         -- populated on 'refunded' status
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ
);

CREATE INDEX idx_payments_registration_id ON event_payments(registration_id);
CREATE INDEX idx_payments_event_id        ON event_payments(event_id);
CREATE INDEX idx_payments_firebase_uid    ON event_payments(firebase_uid);
CREATE INDEX idx_payments_status          ON event_payments(status, created_at);
```

---

## Registration Status for Paid Events

The current `registrations.status` values are: `registered`, `cancelled`.

For paid events, two new statuses are required:

| Status | Meaning |
|---|---|
| `payment_pending` | Registration created, awaiting payment confirmation |
| `registered` | (existing) — payment confirmed or free event |
| `cancelled` | (existing) — cancelled by user or admin |
| `payment_failed` | Payment attempt was made and failed; registration not confirmed |

These status values are additive — existing `registered` and `cancelled` rows are unaffected.

---

## Registration Flow for Paid Events (future)

```
POST /api/v1/events/{id}/register
    │
    ├── FREE event:
    │   INSERT registration (status='registered')
    │   → send confirmation email
    │   → return RegistrationResponse
    │
    └── PAID event:
        INSERT registration (status='payment_pending')
        INSERT event_payments (status='pending', provider_order_id=<razorpay_order>)
        → return RegistrationResponse + PaymentInitiateResponse
            │
            ▼
        Flutter: opens payment sheet (Razorpay SDK)
            │
            ├── Payment success:
            │   POST /api/v1/events/{id}/registrations/{id}/payment/confirm
            │   → verify with provider
            │   UPDATE event_payments (status='completed', paid_at=now())
            │   UPDATE registrations (status='registered')
            │   → send confirmation email
            │
            └── Payment failure:
                POST /api/v1/events/{id}/registrations/{id}/payment/fail
                UPDATE event_payments (status='failed', failure_reason=...)
                UPDATE registrations (status='payment_failed')
                → show retry option
```

---

## Public API Impact

When `registration_fee_type` is added to the events schema, the public event detail API
response includes:

```json
{
  "event_id": 3,
  "registration_fee_type": "FREE",
  "registration_fee_amount": null,
  "registration_fee_currency": "INR"
}
```

For free events: `registration_fee_type: "FREE"`, `registration_fee_amount: null`.
For paid events: `registration_fee_type: "PAID"`, `registration_fee_amount: 500.00`.

The Flutter event detail screen displays:
- Free event: "Free" badge or no fee label
- Paid event: "₹500" badge next to the register CTA

---

## Admin UI Impact

When implemented, the admin event creation form (`EventFormPage.jsx`) adds:
- Fee type toggle: "Free" / "Paid"
- Fee amount field (shown only when "Paid" selected)
- Currency field (default INR; dropdown for future currencies)
- Payment provider selection (shown only when "Paid")

The admin attendee list (`AttendeesPage.jsx`) adds:
- Payment status column for paid events
- Revenue total in the event summary card

---

## What Must Not Be Implemented

- **Payment gateway (Razorpay, Stripe, PayU)** — not in Week 4, not in Alpha
- **Payment webhook handlers** — requires production credentials, compliance review
- **Refund logic** — requires payment gateway + compliance + product approval
- **Payment confirmation emails** — a different email template from registration confirmation
- **GST/invoice generation** — requires product and legal review

---

## Implementation Recommendation

**Do not implement in Week 4. Do not implement in Alpha.**

The schema change to `events` (adding `registration_fee_type` and related columns) is low-risk
and can be applied independently of payment gateway integration. This can be done in a Week 5
or later migration without any code change to the payment flow.

The `event_payments` table and the paid registration flow should not be created until:
1. A payment gateway is selected and credentials are obtained
2. The registration flow for paid events is reviewed and approved
3. Refund and failure handling policies are defined

Write this document. Confirm the schema design. Implement when the first paid event is
scheduled — no earlier.
