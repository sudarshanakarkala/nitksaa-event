-- 031_guests.sql — guests (step 4): one registrations row per person.
--
-- A group = the leader's row plus up to 4 guest rows, all with the leader's
-- registration_id in group_head_id. Someone on their own is their own head.
-- Each row keeps its own qrtoken and registration_number, so check-in,
-- seat counts (COUNT(*) of rows) and per-person refunds work per person.
--
-- Run in Cloud SQL Studio (event_db) after a backup, before merging.
-- Safe to run twice.

BEGIN;

-- 1. Guests allowed per registration (0 = none, the default).
ALTER TABLE events
    ADD COLUMN IF NOT EXISTS max_guests INT NOT NULL DEFAULT 0;
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_max_guests_check;
ALTER TABLE events
    ADD CONSTRAINT events_max_guests_check CHECK (max_guests BETWEEN 0 AND 4);

-- 2. The group head: the leader's registration_id.
ALTER TABLE registrations
    ADD COLUMN IF NOT EXISTS group_head_id INT REFERENCES registrations(registration_id);
UPDATE registrations SET group_head_id = registration_id WHERE group_head_id IS NULL;

-- A new row without a head is its own head.
CREATE OR REPLACE FUNCTION registrations_default_group_head() RETURNS trigger AS $$
BEGIN
    IF NEW.group_head_id IS NULL THEN
        NEW.group_head_id := NEW.registration_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_registrations_default_group_head ON registrations;
CREATE TRIGGER trg_registrations_default_group_head
    BEFORE INSERT ON registrations
    FOR EACH ROW EXECUTE FUNCTION registrations_default_group_head();

ALTER TABLE registrations ALTER COLUMN group_head_id SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_registrations_group_head ON registrations (group_head_id);

-- Guests follow their leader: when the leader's status or hold changes
-- (held -> paid, hold expired, unregistered), the guests still in the group
-- change with it. A guest cancelled on their own stays cancelled.
CREATE OR REPLACE FUNCTION registrations_follow_group_head() RETURNS trigger AS $$
BEGIN
    IF NEW.registration_id = NEW.group_head_id
       AND (NEW.status IS DISTINCT FROM OLD.status
            OR NEW.hold_expires_at IS DISTINCT FROM OLD.hold_expires_at) THEN
        UPDATE registrations
           SET status = NEW.status,
               hold_expires_at = NEW.hold_expires_at,
               cancelled_at = CASE WHEN NEW.status = 'cancelled'
                                   THEN COALESCE(NEW.cancelled_at, now())
                                   ELSE cancelled_at END,
               updated_at = now()
         WHERE group_head_id = NEW.registration_id
           AND registration_id <> NEW.registration_id
           AND status <> 'cancelled';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_registrations_follow_group_head ON registrations;
CREATE TRIGGER trg_registrations_follow_group_head
    AFTER UPDATE OF status, hold_expires_at ON registrations
    FOR EACH ROW EXECUTE FUNCTION registrations_follow_group_head();

-- 3. One live registration per person per event now means one live group
--    they lead (guest rows carry the leader's sign-in).
DROP INDEX IF EXISTS uq_registrations_active;
CREATE UNIQUE INDEX uq_registrations_active
    ON registrations (event_id, firebase_uid)
    WHERE status IN ('registered', 'seat_held', 'payment_pending', 'payment_verification', 'payment_failed')
      AND registration_id = group_head_id;

-- 4. An order pays for the whole group: final_amount = one person's amount x quantity.
ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS quantity INT NOT NULL DEFAULT 1;
ALTER TABLE payment_orders DROP CONSTRAINT IF EXISTS payment_orders_quantity_check;
ALTER TABLE payment_orders
    ADD CONSTRAINT payment_orders_quantity_check CHECK (quantity BETWEEN 1 AND 5);

-- 5. Several refunds per order (one per cancelled guest, one for the rest).
--    Still at most one live refund per registrations row; the app checks that
--    refunds never add up to more than was paid.
DROP INDEX IF EXISTS uq_payment_refunds_active_per_order;
CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_refunds_active_per_registration
    ON payment_refunds (registration_id)
    WHERE status IN ('pending', 'processing', 'processed', 'delayed');

COMMIT;

-- Check (should return 0 rows):
--   SELECT registration_id FROM registrations WHERE group_head_id IS NULL;
