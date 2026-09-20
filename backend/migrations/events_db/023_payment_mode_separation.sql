-- 023_payment_mode_separation.sql
-- Razorpay TEST / LIVE mode separation — per-row mode snapshot.
--
-- Mirrors migration 021_payment_config_gateway.sql exactly, one level down:
-- 021 made *gateway* (deterministic_sandbox | razorpay) a per-event/per-row
-- value instead of a single global setting; this migration does the same
-- for *payment_mode* (test | live) so TEST and LIVE Razorpay traffic can
-- never be confused with each other in a config, order, attempt, refund,
-- webhook lookup, or refund.
--
-- Default is 'test' for every column, and that is the factually-correct
-- value for every existing row: no RAZORPAY_LIVE_* credential has ever been
-- configured in this project (see docs/payments/
-- RAZORPAY_LOCAL_CREDENTIAL_CONFIGURATION_REPORT.md), so nothing that
-- exists today could have been a real live-money Razorpay transaction.
-- event_id=392 (deterministic_sandbox) and event_id=18117/config 7138 (the
-- existing ₹1 Razorpay TEST pilot) are untouched beyond gaining this
-- default — see docs/payments/RAZORPAY_TEST_LIVE_MODE_SEPARATION_REPORT.md
-- for the explicit before/after diff.
--
-- payment_mode is snapshotted the same way gateway already is:
--   payment_configurations.payment_mode — the admin's choice for the event
--   payment_orders.payment_mode         — snapshotted from the config at
--                                          order-creation time
--   payment_attempts.payment_mode       — snapshotted from the order at
--                                          attempt-creation time (this is
--                                          the value RazorpayGateway calls
--                                          are made with)
--   payment_refunds.payment_mode        — snapshotted from the captured
--                                          attempt at refund-creation time
-- A later config edit/retire, or a global env change, never changes which
-- mode an in-flight order/attempt/refund belongs to — same immutability
-- principle as configuration_id / pricing_snapshot / gateway.
--
-- Additive only; does not touch 001-022.

BEGIN;

ALTER TABLE payment_configurations
    ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(10) NOT NULL DEFAULT 'test';
ALTER TABLE payment_configurations
    ADD CONSTRAINT chk_payment_configurations_payment_mode
    CHECK (payment_mode IN ('test', 'live'));

ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(10) NOT NULL DEFAULT 'test';
ALTER TABLE payment_orders
    ADD CONSTRAINT chk_payment_orders_payment_mode
    CHECK (payment_mode IN ('test', 'live'));

ALTER TABLE payment_attempts
    ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(10) NOT NULL DEFAULT 'test';
ALTER TABLE payment_attempts
    ADD CONSTRAINT chk_payment_attempts_payment_mode
    CHECK (payment_mode IN ('test', 'live'));

ALTER TABLE payment_refunds
    ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(10) NOT NULL DEFAULT 'test';
ALTER TABLE payment_refunds
    ADD CONSTRAINT chk_payment_refunds_payment_mode
    CHECK (payment_mode IN ('test', 'live'));

COMMENT ON COLUMN payment_configurations.payment_mode IS
    'TEST or LIVE Razorpay credential profile this config publishes with. '
    'Irrelevant (but still test-defaulted) for gateway=deterministic_sandbox '
    'rows. Publishing payment_mode=live requires platform_admin and valid '
    'rzp_live_-prefixed credentials — see app/services/payment_config_service.py.';
COMMENT ON COLUMN payment_orders.payment_mode IS
    'Snapshotted from the published config at order-creation time.';
COMMENT ON COLUMN payment_attempts.payment_mode IS
    'Snapshotted from the order at attempt-creation time. '
    'payment_service dispatches Razorpay calls with THIS value, never a '
    'global setting.';
COMMENT ON COLUMN payment_refunds.payment_mode IS
    'Snapshotted from the captured attempt at refund-creation time. A '
    'refund is resolved against credentials for this mode only — cross-mode '
    'refund (a live payment refunded with test credentials, or vice versa) '
    'is structurally impossible.';

COMMIT;
