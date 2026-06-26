-- Week 5 Phase 1: Full Day Events + Free/Paid Event display
-- Adds 3 columns to events table. All have defaults — zero downtime, fully backward-compatible.

BEGIN;

ALTER TABLE events
  ADD COLUMN is_full_day  BOOLEAN      NOT NULL DEFAULT false,
  ADD COLUMN is_free      BOOLEAN      NOT NULL DEFAULT true,
  ADD COLUMN ticket_price NUMERIC(10,2);

ALTER TABLE events
  ADD CONSTRAINT chk_ticket_price_non_negative
    CHECK (ticket_price IS NULL OR ticket_price >= 0);

COMMENT ON COLUMN events.is_full_day  IS 'True for all-day or multi-day events; time fields are hidden in UI';
COMMENT ON COLUMN events.is_free      IS 'True = free entry; false = paid event (display only, no payment processing)';
COMMENT ON COLUMN events.ticket_price IS 'Price in INR; NULL when is_free=true; display only';

COMMIT;
