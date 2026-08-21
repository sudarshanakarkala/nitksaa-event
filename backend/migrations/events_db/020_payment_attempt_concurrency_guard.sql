-- 020_payment_attempt_concurrency_guard.sql
-- Real Payment Gateway Foundation sprint: closes a genuine pre-existing
-- concurrency gap found while adding the sprint's mandatory 5-concurrent-
-- request test coverage (create_attempt, not just the pre-existing 2-way
-- double-click tests).
--
-- payment_service.create_attempt's has_unresolved_attempt() check is a
-- read-then-insert race: it runs BEFORE the row is inserted, on a separate
-- statement from the insert. Two concurrent requests can each pass the
-- check before either commits, and — unlike the order-creation race, which
-- is genuinely blocked by uq_payment_orders_active_registration — nothing
-- stopped both from inserting distinct, non-conflicting attempt_number
-- values (the existing uq_payment_attempts_order_attempt_number constraint
-- only rejects two attempts claiming the SAME attempt_number). Observed
-- directly: 5 concurrent POST .../attempts calls against one order
-- produced 2 successful 'pending' attempts, not 1 — see
-- tests/test_payment_gateway_foundation.py::
-- test_five_concurrent_attempt_creation_requests_only_one_succeeds.
--
-- Fix: the same pattern already used for payment_orders
-- (uq_payment_orders_active_registration) and payment_configurations
-- (uq_payment_configurations_active_event) — a partial unique index makes
-- the invariant "at most one unresolved attempt per order" a real database
-- guarantee, not just an application-level fast path. No service-code
-- change is required: create_attempt's existing
-- `except asyncpg.exceptions.UniqueViolationError: raise HTTPException(409,
-- "payment_attempt_active")` already handles this — it was written for the
-- attempt_number race and applies unchanged to this one.

BEGIN;

CREATE UNIQUE INDEX uq_payment_attempts_unresolved_per_order
    ON payment_attempts (order_id)
    WHERE status IN ('initiated', 'pending', 'requires_verification');

COMMIT;
