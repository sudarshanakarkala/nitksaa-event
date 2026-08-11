-- 015_payment_foundation.sql
-- Payment Phase 0 (Part 2): deterministic-sandbox payment foundation.
--
-- Scope: INR only, one attendee per registration, one order per registration.
-- No refunds, no receipts/invoices, no multi-gateway support yet — those are
-- later phases. Money columns use NUMERIC(14,2); all arithmetic in the
-- application layer must use Decimal, never float.
--
-- Internal PKs are BIGSERIAL (simple joins/FKs); external-facing identifiers
-- are opaque public_order_number / public_attempt_number strings so sequential
-- IDs are never exposed in API responses.
--
-- Audit trail reuses the existing event_audit_log table (entity_type=
-- 'payment_order' | 'payment_attempt', entity_id=<bigserial id>) rather than
-- introducing a parallel audit table.

BEGIN;

-- ============================================================
-- payment_configurations
-- One row per event that accepts payment. base_amount is captured at
-- config-creation time (normally sourced from events.ticket_price) and is
-- the immutable basis for pricing snapshots — it does not resync if
-- events.ticket_price changes later; a new configuration version is created
-- instead (status='retired' on the old row).
-- ============================================================

CREATE TABLE payment_configurations (
    id                              BIGSERIAL     PRIMARY KEY,
    configuration_key               TEXT          NOT NULL UNIQUE,
    event_id                        INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    currency                        VARCHAR(3)    NOT NULL DEFAULT 'INR' CHECK (currency = 'INR'),
    base_amount                     NUMERIC(14,2) NOT NULL CHECK (base_amount >= 0),
    gst_enabled                     BOOLEAN       NOT NULL DEFAULT false,
    gst_rate                        NUMERIC(5,2)  NOT NULL DEFAULT 0 CHECK (gst_rate >= 0 AND gst_rate <= 100),
    gst_mode                        VARCHAR(10)   NOT NULL DEFAULT 'exclusive' CHECK (gst_mode IN ('inclusive', 'exclusive')),
    convenience_fee_enabled         BOOLEAN       NOT NULL DEFAULT false,
    convenience_fee_type            VARCHAR(10)   NOT NULL DEFAULT 'fixed' CHECK (convenience_fee_type IN ('fixed', 'percentage')),
    convenience_fee_value           NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (convenience_fee_value >= 0),
    seat_hold_minutes               INT           NOT NULL DEFAULT 15 CHECK (seat_hold_minutes > 0),
    payment_session_expiry_minutes  INT           NOT NULL DEFAULT 15 CHECK (payment_session_expiry_minutes > 0),
    status                          VARCHAR(20)   NOT NULL DEFAULT 'published' CHECK (status IN ('draft', 'published', 'retired')),
    created_by                      VARCHAR(128),
    created_at                      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ
);

-- Only one published configuration may be active for a given event at a time.
CREATE UNIQUE INDEX uq_payment_configurations_active_event
    ON payment_configurations (event_id)
    WHERE status = 'published';

-- ============================================================
-- payment_orders
-- ============================================================

CREATE TABLE payment_orders (
    id                    BIGSERIAL     PRIMARY KEY,
    public_order_number   TEXT          NOT NULL UNIQUE,
    registration_id       INT           NOT NULL REFERENCES registrations(registration_id) ON DELETE CASCADE,
    event_id              INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    payer_firebase_uid    VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid),
    configuration_id      BIGINT        NOT NULL REFERENCES payment_configurations(id),
    currency              VARCHAR(3)    NOT NULL DEFAULT 'INR',
    base_amount           NUMERIC(14,2) NOT NULL CHECK (base_amount >= 0),
    tax_amount            NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    convenience_fee        NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (convenience_fee >= 0),
    final_amount           NUMERIC(14,2) NOT NULL CHECK (final_amount >= 0),
    amount_paid            NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
    pricing_snapshot       JSONB         NOT NULL,
    status                 VARCHAR(20)   NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'payment_pending', 'paid', 'expired', 'cancelled')),
    idempotency_key        TEXT,
    expires_at              TIMESTAMPTZ  NOT NULL,
    paid_at                 TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ,
    CONSTRAINT chk_payment_orders_amount_paid_le_final CHECK (amount_paid <= final_amount)
);

CREATE INDEX idx_payment_orders_registration_id ON payment_orders (registration_id);
CREATE INDEX idx_payment_orders_payer ON payment_orders (payer_firebase_uid, status);

-- At most one order in flight (created/payment_pending) per registration.
CREATE UNIQUE INDEX uq_payment_orders_active_registration
    ON payment_orders (registration_id)
    WHERE status IN ('created', 'payment_pending');

-- Idempotency: same payer + same idempotency key must resolve to one order.
CREATE UNIQUE INDEX uq_payment_orders_idempotency
    ON payment_orders (payer_firebase_uid, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- ============================================================
-- payment_attempts
-- One order may have many attempts; a failed attempt is never overwritten,
-- retry always inserts a new row with the next attempt_number.
-- ============================================================

CREATE TABLE payment_attempts (
    id                          BIGSERIAL     PRIMARY KEY,
    public_attempt_number       TEXT          NOT NULL UNIQUE,
    order_id                    BIGINT        NOT NULL REFERENCES payment_orders(id) ON DELETE CASCADE,
    attempt_number               INT          NOT NULL CHECK (attempt_number > 0),
    gateway                      VARCHAR(30)  NOT NULL DEFAULT 'deterministic_sandbox',
    scenario                     VARCHAR(30),
    gateway_order_ref            TEXT,
    gateway_payment_ref          TEXT,
    amount                       NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
    currency                     VARCHAR(3)   NOT NULL,
    status                       VARCHAR(20)  NOT NULL DEFAULT 'initiated' CHECK (status IN ('initiated', 'pending', 'captured', 'failed', 'cancelled', 'expired')),
    failure_code                 TEXT,
    sanitized_failure_message    TEXT,
    initiated_at                 TIMESTAMPTZ  NOT NULL DEFAULT now(),
    captured_at                  TIMESTAMPTZ,
    failed_at                    TIMESTAMPTZ,
    cancelled_at                 TIMESTAMPTZ,
    created_at                   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at                   TIMESTAMPTZ,
    CONSTRAINT uq_payment_attempts_order_attempt_number UNIQUE (order_id, attempt_number)
);

CREATE INDEX idx_payment_attempts_order_id ON payment_attempts (order_id);

CREATE UNIQUE INDEX uq_payment_attempts_gateway_payment_ref
    ON payment_attempts (gateway_payment_ref)
    WHERE gateway_payment_ref IS NOT NULL;

-- ============================================================
-- payment_webhook_events
-- Every inbound gateway event is recorded before processing so replay /
-- duplicate delivery can be detected via the unique (gateway, gateway_event_id).
-- ============================================================

CREATE TABLE payment_webhook_events (
    id                     BIGSERIAL    PRIMARY KEY,
    gateway                VARCHAR(30)  NOT NULL,
    gateway_event_id       TEXT         NOT NULL,
    event_type             TEXT         NOT NULL,
    payload_hash            TEXT        NOT NULL,
    signature_valid          BOOLEAN    NOT NULL,
    processing_status         VARCHAR(20) NOT NULL DEFAULT 'received' CHECK (processing_status IN ('received', 'processed', 'duplicate', 'rejected')),
    correlated_order_id       BIGINT     REFERENCES payment_orders(id),
    correlated_attempt_id     BIGINT     REFERENCES payment_attempts(id),
    received_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at               TIMESTAMPTZ,
    error_code                  TEXT,
    CONSTRAINT uq_payment_webhook_events_gateway_event UNIQUE (gateway, gateway_event_id)
);

CREATE INDEX idx_payment_webhook_events_order_id ON payment_webhook_events (correlated_order_id);

COMMIT;
