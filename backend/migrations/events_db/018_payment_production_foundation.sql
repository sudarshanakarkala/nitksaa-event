-- 018_payment_production_foundation.sql
-- Payment production foundation: platform-wide payment RBAC roles, and an
-- index to support the new explicit stale-order expiry sweep (WP4).
--
-- Does not touch 001-017. Additive only.
--
-- Event-scoped role storage deliberately reuses the existing (currently
-- unused) event_members(event_id, firebase_uid, role, status) table from
-- migration 003 with a new role value 'event_admin' — that column has no
-- CHECK constraint, so no schema change is needed there.

BEGIN;

-- ============================================================
-- payment_platform_roles
-- Platform-wide (not event-scoped) payment roles: platform_admin,
-- finance_operator, auditor, support. The very first platform_admin is
-- established out-of-band via the PLATFORM_ADMIN_FIREBASE_UIDS setting
-- (see app/config.py) — this table holds every grant made after that,
-- including ones made by a bootstrap-list admin through the role-grant API.
-- ============================================================

CREATE TABLE payment_platform_roles (
    id              BIGSERIAL     PRIMARY KEY,
    firebase_uid    VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid),
    role            VARCHAR(30)   NOT NULL CHECK (role IN (
                        'platform_admin', 'finance_operator', 'auditor', 'support'
                    )),
    granted_by      VARCHAR(128)  NOT NULL,
    granted_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    revoked_at      TIMESTAMPTZ,
    revoked_by      VARCHAR(128)
);

-- One *active* grant per (user, role); revoked rows are kept for audit
-- history rather than deleted, so a role can be re-granted after revocation
-- without violating uniqueness.
CREATE UNIQUE INDEX uq_payment_platform_roles_active
    ON payment_platform_roles (firebase_uid, role)
    WHERE revoked_at IS NULL;

CREATE INDEX idx_payment_platform_roles_uid ON payment_platform_roles (firebase_uid);

-- ============================================================
-- Expiry sweep support index (WP4)
-- expire_stale_payment_orders() filters on status IN ('created',
-- 'payment_pending') AND expires_at < now() — index the common case.
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_payment_orders_expiry_sweep
    ON payment_orders (status, expires_at)
    WHERE status IN ('created', 'payment_pending');

COMMIT;
