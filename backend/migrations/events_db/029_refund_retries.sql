-- 029_refund_retries.sql
-- Refund reliability (admin revamp step 10c).
--
-- A refund the provider refuses for a temporary reason (e.g. the Razorpay
-- balance is too low) is now 'delayed' and retried automatically, instead
-- of 'failed' with nobody told. 'failed' now means "a person must act".
--
-- 'delayed' counts as an active refund, so the one-refund-per-order index
-- includes it: a delayed refund still blocks a second refund for the order.
-- Otherwise additive: new columns are nullable or defaulted.

BEGIN;

ALTER TABLE payment_refunds DROP CONSTRAINT payment_refunds_status_check;
ALTER TABLE payment_refunds ADD CONSTRAINT payment_refunds_status_check
    CHECK (status IN ('pending', 'processing', 'processed', 'failed', 'delayed'));

DROP INDEX uq_payment_refunds_active_per_order;
CREATE UNIQUE INDEX uq_payment_refunds_active_per_order
    ON payment_refunds (payment_order_id)
    WHERE status IN ('pending', 'processing', 'processed', 'delayed');

ALTER TABLE payment_refunds
    ADD COLUMN attempt_count               INT NOT NULL DEFAULT 1,  -- refund calls made to the provider
    ADD COLUMN last_attempt_at             TIMESTAMPTZ,
    ADD COLUMN attendee_notified_delay_at  TIMESTAMPTZ,             -- each email is sent once
    ADD COLUMN attendee_notified_result_at TIMESTAMPTZ,
    ADD COLUMN admins_notified_at          TIMESTAMPTZ;

-- Existing finished refunds count as already notified, so the first
-- retry doesn't email anyone about old refunds.
UPDATE payment_refunds
   SET attendee_notified_result_at = COALESCE(finalized_at, updated_at, requested_at)
 WHERE status IN ('processed', 'failed');
UPDATE payment_refunds SET admins_notified_at = now() WHERE status = 'failed';

COMMIT;
