-- 021_payment_config_gateway.sql
-- Per-event payment gateway selection.
--
-- The readiness audit (docs/payments/PAYMENT_FLOW_STATUS_AND_RAZORPAY_READINESS_REPORT.md)
-- found gateway selection was global (settings.payment_gateway_mode only). This
-- migration makes the gateway a per-event configuration value so the new ₹1
-- Razorpay pilot event can use 'razorpay' while every existing paid event
-- (notably event_id=392) stays on 'deterministic_sandbox' with no behaviour
-- change.
--
-- Additive only; does not touch 001-020. Existing payment_configurations and
-- payment_orders rows get the default 'deterministic_sandbox', which is exactly
-- what they were already using via the global setting.
--
--   payment_configurations.gateway  — the admin's choice for the event
--   payment_orders.gateway          — snapshotted at order-creation time, so a
--                                     later config edit/retire never changes
--                                     which gateway an in-flight order belongs
--                                     to (same immutability principle as
--                                     configuration_id / pricing_snapshot).

BEGIN;

ALTER TABLE payment_configurations
    ADD COLUMN IF NOT EXISTS gateway VARCHAR(30) NOT NULL DEFAULT 'deterministic_sandbox';

ALTER TABLE payment_configurations
    ADD CONSTRAINT chk_payment_configurations_gateway
    CHECK (gateway IN ('deterministic_sandbox', 'razorpay'));

ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS gateway VARCHAR(30) NOT NULL DEFAULT 'deterministic_sandbox';

ALTER TABLE payment_orders
    ADD CONSTRAINT chk_payment_orders_gateway
    CHECK (gateway IN ('deterministic_sandbox', 'razorpay'));

COMMENT ON COLUMN payment_configurations.gateway IS
    'Payment gateway this event uses. Default deterministic_sandbox. The new '
    'razorpay pilot event sets this to razorpay; existing events are unchanged.';
COMMENT ON COLUMN payment_orders.gateway IS
    'Gateway snapshotted from the published config at order-creation time. '
    'payment_service.create_attempt dispatches on THIS value, not the global '
    'settings.payment_gateway_mode.';

COMMIT;
