-- 024_payment_attempts_gateway_order_ref_unique.sql
-- Razorpay integration Step 2: the provider order id (razorpay_order_id)
-- must be unique.
--
-- payment_attempts.gateway_order_ref holds that id — every attempt gets its
-- own Razorpay order, replacing the random rzp_pending_ placeholder once
-- create_payment returns (sandbox attempts hold a random sbx_ord_ ref).
-- Migration 015 made gateway_payment_ref unique
-- (uq_payment_attempts_gateway_payment_ref) but left gateway_order_ref
-- unconstrained and unindexed, so uniqueness rested on the provider alone
-- and the webhook correlation lookup
-- (PaymentRepository.get_attempt_by_gateway_ref) was a sequential scan that
-- would silently pick one row if a ref were ever duplicated.
--
-- Fix: the same partial-unique-index pattern as
-- uq_payment_attempts_gateway_payment_ref — NULLs stay allowed, every
-- non-NULL ref must be unique across all gateways (sandbox and Razorpay refs
-- carry distinct prefixes). The index also serves the webhook lookup. No
-- service-code change is required.
--
-- Pre-check (must return no rows, or index creation fails and the
-- transaction rolls back with nothing changed):
--   SELECT gateway_order_ref, count(*) FROM payment_attempts
--   WHERE gateway_order_ref IS NOT NULL GROUP BY 1 HAVING count(*) > 1;
--
-- Additive only; does not touch 001-023 and changes no rows.

BEGIN;

CREATE UNIQUE INDEX uq_payment_attempts_gateway_order_ref
    ON payment_attempts (gateway_order_ref)
    WHERE gateway_order_ref IS NOT NULL;

COMMIT;
