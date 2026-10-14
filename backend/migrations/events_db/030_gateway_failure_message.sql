-- 030: Razorpay's own error text for a failed payment try.
--
-- payment_attempts.sanitized_failure_message held the gateway's raw error
-- text (Razorpay's error_description), not a sanitised one. Renamed to say
-- what it is. It is kept for troubleshooting and never shown to attendees,
-- in emails or in API responses; screens use failure_reason.
--
-- NITiKa's read-only role loses access to this one column: its SELECT on
-- payment_attempts becomes a list of every other column. A column added
-- later is not readable by NITiKa until granted.
--
-- Run in Cloud SQL Studio right before merging the PR (the merge deploys the
-- code that uses the new name). Deploy NITiKa's explicit-column query first.

ALTER TABLE payment_attempts
    RENAME COLUMN sanitized_failure_message TO gateway_failure_message;

DO $$
DECLARE
    cols text;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nitika_ro_events') THEN
        SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
          INTO cols
          FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'payment_attempts'
           AND column_name <> 'gateway_failure_message';
        EXECUTE 'REVOKE SELECT ON payment_attempts FROM nitika_ro_events';
        EXECUTE format('GRANT SELECT (%s) ON payment_attempts TO nitika_ro_events', cols);
    END IF;
END $$;
