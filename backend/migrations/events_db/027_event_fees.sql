-- Admin revamp step 5b: fee tiers on an event.
--
-- The tiers break down the ticket price (participation, accommodation, food
-- pass ...). The event form sets events.ticket_price to their total, so the
-- event page shows exactly what checkout charges. Display only: checkout
-- still charges the one ticket price.
--
-- Additive only. Safe to run more than once.

BEGIN;

CREATE TABLE IF NOT EXISTS event_fees (
    fee_id         SERIAL        PRIMARY KEY,
    event_id       INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    name           VARCHAR(120)  NOT NULL,
    fee_type       VARCHAR(30)   NOT NULL DEFAULT 'participation'
                   CHECK (fee_type IN ('participation', 'accommodation', 'contributions',
                                       'food_pass', 'merchandise', 'other')),
    amount         NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    display_order  INT           NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_event_fees_event ON event_fees (event_id, display_order);

COMMIT;
