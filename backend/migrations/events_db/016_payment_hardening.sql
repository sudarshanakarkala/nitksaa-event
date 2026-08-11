-- 016_payment_hardening.sql
-- Payment Phase 0 hardening: pending/verification, configuration versioning,
-- and PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY exception tracking.
--
-- Does not touch 001-015. Additive only; existing payment_orders/attempts
-- rows get sensible defaults (version=1) since every config currently in the
-- database is its own first version.

BEGIN;

-- ============================================================
-- payment_attempts: add 'requires_verification' status
-- Used when a PENDING attempt has not resolved within the configured
-- pending-verification window — distinct from 'pending' so retry-blocking
-- logic and diagnostics can tell "freshly pending" apart from "stuck".
-- ============================================================

ALTER TABLE payment_attempts DROP CONSTRAINT payment_attempts_status_check;

ALTER TABLE payment_attempts ADD CONSTRAINT payment_attempts_status_check
    CHECK (status IN (
        'initiated', 'pending', 'requires_verification',
        'captured', 'failed', 'cancelled', 'expired'
    ));

ALTER TABLE payment_attempts
    ADD COLUMN IF NOT EXISTS verification_checked_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verification_check_count INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN payment_attempts.verification_checked_at IS
    'Timestamp of the most recent POST .../verify call for this attempt. NULL if never checked.';
COMMENT ON COLUMN payment_attempts.verification_check_count IS
    'Number of verification checks performed. Used to detect a stuck pending attempt.';

-- ============================================================
-- payment_configurations: versioning
-- A configuration is now append-only. "Editing" a configuration_key retires
-- the current published row (status='retired') and inserts a NEW row with
-- version = previous_max + 1, same configuration_key. The old UNIQUE
-- constraint on configuration_key alone is replaced by (configuration_key,
-- version) so multiple versions of the same key can coexist.
-- ============================================================

ALTER TABLE payment_configurations
    ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;

ALTER TABLE payment_configurations
    DROP CONSTRAINT payment_configurations_configuration_key_key;

ALTER TABLE payment_configurations
    ADD CONSTRAINT uq_payment_configurations_key_version UNIQUE (configuration_key, version);

-- uq_payment_configurations_active_event (one published row per event) is
-- unchanged — still exactly one published version per event at a time.

-- ============================================================
-- payment_orders: store the configuration_version used at order-creation
-- time, alongside the existing immutable configuration_id/pricing_snapshot.
-- ============================================================

ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS configuration_version INT NOT NULL DEFAULT 1;

-- ============================================================
-- payment_exceptions
-- Operational exceptions that must not silently resolve themselves —
-- financial state stays exactly as captured; a human/dev-diagnostics
-- action resolves the exception explicitly.
-- ============================================================

CREATE TABLE payment_exceptions (
    id                 BIGSERIAL     PRIMARY KEY,
    exception_type     VARCHAR(50)   NOT NULL CHECK (exception_type IN (
                            'PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY',
                            'VERIFICATION_UNRESOLVED'
                        )),
    order_id           BIGINT        REFERENCES payment_orders(id),
    attempt_id         BIGINT        REFERENCES payment_attempts(id),
    registration_id    INT           REFERENCES registrations(registration_id),
    status             VARCHAR(20)   NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
    summary            TEXT          NOT NULL,
    detail             JSONB,
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    resolved_at        TIMESTAMPTZ,
    resolved_by        VARCHAR(128),
    resolution         TEXT
);

CREATE INDEX idx_payment_exceptions_status ON payment_exceptions (status, created_at DESC);
CREATE INDEX idx_payment_exceptions_order_id ON payment_exceptions (order_id);

COMMIT;
