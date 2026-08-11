-- 014_registration_holds.sql
-- Payment Phase 0 (Part 1): seat-hold support on registrations for paid events.
--
-- Paid events already have events.is_free / events.ticket_price (migration 010),
-- previously "display only, no payment processing". This migration adds the
-- registration-side plumbing so a paid registration can hold a seat while
-- payment is in progress, without touching the free-event flow at all.
--
-- New registrations.status values used by the paid flow (no CHECK constraint
-- exists on this column, so these are additive at the application level):
--   seat_held            — registration created, no payment order yet
--   payment_pending       — payment order created, attempt in progress
--   payment_verification  — gateway returned pending/unclear result
--   payment_failed        — most recent attempt failed; seat held until hold_expires_at
-- Existing values are unchanged: registered (confirmed/paid), cancelled.
--
-- Free-event registrations continue to insert directly as 'registered' with
-- hold_expires_at = NULL, exactly as today.

BEGIN;

ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS hold_expires_at TIMESTAMPTZ;

COMMENT ON COLUMN registrations.hold_expires_at IS
    'Deadline for seat_held/payment_pending/payment_verification/payment_failed rows before the seat is released back to capacity. NULL for free events and for registered/cancelled rows.';

-- Replace the active-registration guard (migration 008) so a user cannot hold
-- multiple simultaneous in-flight-or-confirmed registrations for the same event.
DROP INDEX IF EXISTS uq_registrations_active;

CREATE UNIQUE INDEX uq_registrations_active
    ON registrations (event_id, firebase_uid)
    WHERE status IN ('registered', 'seat_held', 'payment_pending', 'payment_verification', 'payment_failed');

COMMIT;
