-- 028_payment_details.sql
-- Payment lifecycle details for support, finance, Audit and NITiKa
-- (admin revamp step 10a; see PAYMENT_LIFECYCLE_RESEARCH.md).
--
-- Additive only: every new column is nullable, so existing rows and code are
-- unaffected. Provider-neutral names; each gateway adapter maps its own
-- fields into them. No personal data from the provider (no email, phone,
-- UPI id or card details).

BEGIN;

-- How a payment was made, and why it failed (current facts; the history of
-- each step stays in event_audit_log).
ALTER TABLE payment_attempts
    ADD COLUMN payment_method     VARCHAR(30),    -- upi / card / netbanking / wallet / emi ...
    ADD COLUMN payment_instrument VARCHAR(60),    -- bank or wallet code, e.g. HDFC, paytm
    ADD COLUMN is_international   BOOLEAN,
    ADD COLUMN provider_fee       NUMERIC(14,2),  -- gateway fee incl. GST, in rupees
    ADD COLUMN provider_tax       NUMERIC(14,2),  -- GST part of the fee, in rupees
    ADD COLUMN failure_source     VARCHAR(40),    -- e.g. customer / bank / gateway
    ADD COLUMN failure_step       VARCHAR(60),    -- e.g. payment_authentication
    ADD COLUMN failure_reason     VARCHAR(80),    -- e.g. incorrect_otp
    ADD COLUMN bank_reference     TEXT;           -- bank/network reference (RRN etc.)

-- The bank reference a customer quotes to trace a refund (ARN/RRN/UTR),
-- and how the refund was actually sent.
ALTER TABLE payment_refunds
    ADD COLUMN bank_reference  TEXT,
    ADD COLUMN speed_processed VARCHAR(20);       -- normal / instant

-- Refund webhooks are matched by the provider's refund id.
CREATE INDEX IF NOT EXISTS idx_payment_refunds_provider_refund_id
    ON payment_refunds (provider_refund_id);

COMMIT;
