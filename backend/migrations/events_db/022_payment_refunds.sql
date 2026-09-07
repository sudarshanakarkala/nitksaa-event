-- 022_payment_refunds.sql
-- Durable refund model for attendee-initiated paid-registration cancellation.
--
-- Scope (this sprint): full refund only, one logical refund per paid order,
-- INR only. No partial refunds, no policy engine, no receipts. Refund state is
-- tracked HERE — never inferred from the Razorpay dashboard alone.
--
-- Additive only; does not touch 001-021. payment_orders.status is deliberately
-- NOT widened with a 'refunded' value in this sprint: the order genuinely was
-- paid, and the authoritative post-cancellation state lives in this table plus
-- registrations.status='cancelled'. Revisit if a reporting need appears.
--
-- Concurrency / idempotency (the "one logical refund" guarantee):
--   * uq_payment_refunds_idempotency  — same logical request key -> one row.
--   * uq_payment_refunds_active_per_order — at most one non-failed refund per
--     order. Both are partial/plain UNIQUE indexes, i.e. real DB guarantees,
--     exactly the pattern already used for payment_orders /
--     payment_attempts / payment_configurations. The provider's own
--     Idempotency-Key header is an ADDITIONAL safeguard, not the primary one.

BEGIN;

CREATE TABLE payment_refunds (
    id                    BIGSERIAL     PRIMARY KEY,
    public_refund_number  TEXT          NOT NULL UNIQUE,
    registration_id       INT           NOT NULL REFERENCES registrations(registration_id) ON DELETE CASCADE,
    payment_order_id      BIGINT        NOT NULL REFERENCES payment_orders(id) ON DELETE CASCADE,
    payment_attempt_id    BIGINT        NOT NULL REFERENCES payment_attempts(id),
    gateway               VARCHAR(30)   NOT NULL,
    provider_payment_id   TEXT          NOT NULL,
    provider_refund_id    TEXT,
    amount                NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
    currency              VARCHAR(3)    NOT NULL DEFAULT 'INR' CHECK (currency = 'INR'),
    -- pending    : internal row created, provider call not yet confirmed
    -- processing : provider accepted, not yet settled ('speed=optimum'/async)
    -- processed  : provider reports the refund as processed/settled
    -- failed     : provider rejected, or provider call errored — retryable
    status                VARCHAR(20)   NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'processing', 'processed', 'failed')),
    reason                VARCHAR(40)   NOT NULL DEFAULT 'attendee_cancellation',
    idempotency_key       TEXT          NOT NULL,
    failure_reason        TEXT,
    requested_by          VARCHAR(128)  NOT NULL,
    requested_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ,
    finalized_at          TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_payment_refunds_idempotency
    ON payment_refunds (idempotency_key);

-- At most one refund per order that is not in a terminal-failed state.
CREATE UNIQUE INDEX uq_payment_refunds_active_per_order
    ON payment_refunds (payment_order_id)
    WHERE status IN ('pending', 'processing', 'processed');

CREATE INDEX idx_payment_refunds_registration ON payment_refunds (registration_id);
CREATE INDEX idx_payment_refunds_status ON payment_refunds (status, requested_at DESC);

COMMIT;
