"""Payment Phase 0 repository — payment_configurations / payment_orders /
payment_attempts / payment_webhook_events (migration 015).
"""
import json
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

import asyncpg


class PaymentRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    # ── Configuration ──────────────────────────────────────────────────────

    async def get_published_config_for_event(self, event_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            """
            SELECT * FROM payment_configurations
            WHERE event_id = $1 AND status = 'published'
            """,
            event_id,
        )

    async def get_config_by_id(self, configuration_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_configurations WHERE id = $1", configuration_id
        )

    async def create_new_config_version(
        self,
        configuration_key: str,
        event_id: int,
        base_amount: Decimal,
        gst_enabled: bool,
        gst_rate: Decimal,
        gst_mode: str,
        convenience_fee_enabled: bool,
        convenience_fee_type: str,
        convenience_fee_value: Decimal,
        seat_hold_minutes: int,
        payment_session_expiry_minutes: int,
        created_by: Optional[str],
        gateway: str = "deterministic_sandbox",
        payment_mode: str = "test",
    ) -> asyncpg.Record:
        """Dev-only helper (diagnostics config import). Configurations are
        append-only: retires the currently published row for the event (if
        any) and INSERTS a new row with version = previous_max_for_key + 1.
        Never updates an existing row's amounts/rates in place — orders that
        already reference an earlier configuration_id/version keep seeing the
        values that were active when they were created. Not the full
        draft/approve/publish workflow."""
        async with self.conn.transaction():
            prev_version = await self.conn.fetchval(
                "SELECT COALESCE(MAX(version), 0) FROM payment_configurations WHERE configuration_key = $1",
                configuration_key,
            )
            await self.conn.execute(
                """
                UPDATE payment_configurations
                SET status = 'retired', updated_at = now()
                WHERE event_id = $1 AND status = 'published'
                """,
                event_id,
            )
            row = await self.conn.fetchrow(
                """
                INSERT INTO payment_configurations (
                    configuration_key, event_id, version, base_amount,
                    gst_enabled, gst_rate, gst_mode,
                    convenience_fee_enabled, convenience_fee_type, convenience_fee_value,
                    seat_hold_minutes, payment_session_expiry_minutes,
                    status, created_by, gateway, payment_mode
                ) VALUES (
                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'published', $13, $14, $15
                )
                RETURNING *
                """,
                configuration_key,
                event_id,
                prev_version + 1,
                base_amount,
                gst_enabled,
                gst_rate,
                gst_mode,
                convenience_fee_enabled,
                convenience_fee_type,
                convenience_fee_value,
                seat_hold_minutes,
                payment_session_expiry_minutes,
                created_by,
                gateway,
                payment_mode,
            )
        return row

    async def create_draft_config(
        self,
        configuration_key: str,
        event_id: int,
        base_amount: Decimal,
        gst_enabled: bool,
        gst_rate: Decimal,
        gst_mode: str,
        convenience_fee_enabled: bool,
        convenience_fee_type: str,
        convenience_fee_value: Decimal,
        seat_hold_minutes: int,
        payment_session_expiry_minutes: int,
        created_by: str,
        gateway: str = "deterministic_sandbox",
        payment_mode: str = "test",
    ) -> asyncpg.Record:
        """Production config lifecycle (WP1): insert a new status='draft'
        row. Does not touch any currently-published row — unlike
        create_new_config_version (dev-diagnostics import path), nothing is
        retired until publish_draft_config runs. version = previous max for
        this configuration_key + 1, same append-only numbering."""
        prev_version = await self.conn.fetchval(
            "SELECT COALESCE(MAX(version), 0) FROM payment_configurations WHERE configuration_key = $1",
            configuration_key,
        )
        return await self.conn.fetchrow(
            """
            INSERT INTO payment_configurations (
                configuration_key, event_id, version, base_amount,
                gst_enabled, gst_rate, gst_mode,
                convenience_fee_enabled, convenience_fee_type, convenience_fee_value,
                seat_hold_minutes, payment_session_expiry_minutes,
                status, created_by, gateway, payment_mode
            ) VALUES (
                $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'draft', $13, $14, $15
            )
            RETURNING *
            """,
            configuration_key,
            event_id,
            prev_version + 1,
            base_amount,
            gst_enabled,
            gst_rate,
            gst_mode,
            convenience_fee_enabled,
            convenience_fee_type,
            convenience_fee_value,
            seat_hold_minutes,
            payment_session_expiry_minutes,
            created_by,
            gateway,
            payment_mode,
        )

    async def list_configs_for_event(self, event_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            """
            SELECT * FROM payment_configurations
            WHERE event_id = $1
            ORDER BY version DESC
            """,
            event_id,
        )

    async def publish_draft_config(self, configuration_id: int) -> asyncpg.Record:
        """Transition a status='draft' row to 'published', retiring the
        event's currently-published row (if any) in the same transaction.
        Raises asyncpg.exceptions.UniqueViolationError if a concurrent
        publish for the same event wins the race — the partial unique index
        uq_payment_configurations_active_event is the actual source of
        truth for "at most one published config per event", same pattern as
        payment_orders/payment_attempts elsewhere in this module."""
        async with self.conn.transaction():
            draft = await self.conn.fetchrow(
                "SELECT * FROM payment_configurations WHERE id = $1 AND status = 'draft'",
                configuration_id,
            )
            if not draft:
                return None
            await self.conn.execute(
                """
                UPDATE payment_configurations
                SET status = 'retired', updated_at = now()
                WHERE event_id = $1 AND status = 'published'
                """,
                draft["event_id"],
            )
            row = await self.conn.fetchrow(
                """
                UPDATE payment_configurations
                SET status = 'published', updated_at = now()
                WHERE id = $1
                RETURNING *
                """,
                configuration_id,
            )
        return row

    # ── Orders ────────────────────────────────────────────────────────────

    async def get_active_order_for_registration(
        self, registration_id: int
    ) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            """
            SELECT * FROM payment_orders
            WHERE registration_id = $1 AND status IN ('created', 'payment_pending')
            """,
            registration_id,
        )

    async def get_order_by_idempotency_key(
        self, payer_firebase_uid: str, idempotency_key: str
    ) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            """
            SELECT * FROM payment_orders
            WHERE payer_firebase_uid = $1 AND idempotency_key = $2
            """,
            payer_firebase_uid,
            idempotency_key,
        )

    async def get_order_by_public_id(self, public_order_number: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_orders WHERE public_order_number = $1",
            public_order_number,
        )

    async def get_order_by_id(self, order_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_orders WHERE id = $1", order_id
        )

    async def create_order(
        self,
        public_order_number: str,
        registration_id: int,
        event_id: int,
        payer_firebase_uid: str,
        configuration_id: int,
        configuration_version: int,
        currency: str,
        base_amount: Decimal,
        tax_amount: Decimal,
        convenience_fee: Decimal,
        final_amount: Decimal,
        pricing_snapshot: Dict[str, Any],
        idempotency_key: str,
        expires_at: datetime,
        gateway: str = "deterministic_sandbox",
        payment_mode: str = "test",
    ) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO payment_orders (
                public_order_number, registration_id, event_id, payer_firebase_uid,
                configuration_id, configuration_version, currency, base_amount, tax_amount,
                convenience_fee, final_amount, pricing_snapshot, idempotency_key, expires_at,
                gateway, payment_mode, status
            ) VALUES (
                $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::jsonb, $13, $14, $15, $16, 'created'
            )
            RETURNING *
            """,
            public_order_number,
            registration_id,
            event_id,
            payer_firebase_uid,
            configuration_id,
            configuration_version,
            currency,
            base_amount,
            tax_amount,
            convenience_fee,
            final_amount,
            json.dumps(pricing_snapshot, default=str),
            idempotency_key,
            expires_at,
            gateway,
            payment_mode,
        )

    async def mark_order_payment_pending(self, order_id: int) -> None:
        await self.conn.execute(
            "UPDATE payment_orders SET status = 'payment_pending', updated_at = now() WHERE id = $1",
            order_id,
        )

    async def mark_order_paid(self, order_id: int, amount_paid: Decimal) -> None:
        await self.conn.execute(
            """
            UPDATE payment_orders
            SET status = 'paid', amount_paid = $2, paid_at = now(), updated_at = now()
            WHERE id = $1
            """,
            order_id,
            amount_paid,
        )

    async def mark_order_status(self, order_id: int, status: str) -> None:
        await self.conn.execute(
            "UPDATE payment_orders SET status = $2, updated_at = now() WHERE id = $1",
            order_id,
            status,
        )

    # ── Attempts ──────────────────────────────────────────────────────────

    async def next_attempt_number(self, order_id: int) -> int:
        val = await self.conn.fetchval(
            "SELECT COALESCE(MAX(attempt_number), 0) + 1 FROM payment_attempts WHERE order_id = $1",
            order_id,
        )
        return int(val)

    async def create_attempt(
        self,
        public_attempt_number: str,
        order_id: int,
        attempt_number: int,
        gateway: str,
        scenario: str,
        amount: Decimal,
        currency: str,
        gateway_order_ref: str,
        payment_mode: str = "test",
    ) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO payment_attempts (
                public_attempt_number, order_id, attempt_number, gateway, scenario,
                amount, currency, gateway_order_ref, payment_mode, status
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'initiated')
            RETURNING *
            """,
            public_attempt_number,
            order_id,
            attempt_number,
            gateway,
            scenario,
            amount,
            currency,
            gateway_order_ref,
            payment_mode,
        )

    async def get_attempt_by_public_id(self, public_attempt_number: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_attempts WHERE public_attempt_number = $1",
            public_attempt_number,
        )

    async def get_attempt_by_id(self, attempt_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_attempts WHERE id = $1", attempt_id
        )

    async def get_attempt_by_gateway_ref(
        self, gateway_order_ref: str
    ) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_attempts WHERE gateway_order_ref = $1",
            gateway_order_ref,
        )

    async def update_attempt_gateway_order_ref(
        self, attempt_id: int, gateway_order_ref: str
    ) -> None:
        """Replace the placeholder gateway_order_ref with the real
        provider-minted one (Razorpay order id) once create_payment returns."""
        await self.conn.execute(
            "UPDATE payment_attempts SET gateway_order_ref = $2, updated_at = now() WHERE id = $1",
            attempt_id,
            gateway_order_ref,
        )

    async def list_attempts_for_order(self, order_id: int) -> List[asyncpg.Record]:
        return await self.conn.fetch(
            "SELECT * FROM payment_attempts WHERE order_id = $1 ORDER BY attempt_number ASC",
            order_id,
        )

    async def get_unresolved_attempt(self, order_id: int) -> Optional[asyncpg.Record]:
        """The order's in-flight attempt, if any — at most one exists
        (uq_payment_attempts_unresolved_per_order, migration 020)."""
        return await self.conn.fetchrow(
            """
            SELECT * FROM payment_attempts
            WHERE order_id = $1 AND status IN ('initiated', 'pending', 'requires_verification')
            """,
            order_id,
        )

    async def has_unresolved_attempt(self, order_id: int) -> bool:
        """True while an attempt is in flight OR stuck awaiting verification —
        retry must be blocked in both cases (see verify_attempt)."""
        val = await self.conn.fetchval(
            """
            SELECT EXISTS (
                SELECT 1 FROM payment_attempts
                WHERE order_id = $1 AND status IN ('initiated', 'pending', 'requires_verification')
            )
            """,
            order_id,
        )
        return bool(val)

    async def update_attempt_captured(
        self, attempt_id: int, gateway_payment_ref: str
    ) -> None:
        await self.conn.execute(
            """
            UPDATE payment_attempts
            SET status = 'captured', gateway_payment_ref = $2, captured_at = now(), updated_at = now()
            WHERE id = $1
            """,
            attempt_id,
            gateway_payment_ref,
        )

    async def update_attempt_failed(
        self, attempt_id: int, failure_code: str, sanitized_message: str
    ) -> None:
        await self.conn.execute(
            """
            UPDATE payment_attempts
            SET status = 'failed', failure_code = $2, sanitized_failure_message = $3,
                failed_at = now(), updated_at = now()
            WHERE id = $1
            """,
            attempt_id,
            failure_code,
            sanitized_message,
        )

    async def update_attempt_status(self, attempt_id: int, status: str) -> None:
        await self.conn.execute(
            "UPDATE payment_attempts SET status = $2, updated_at = now() WHERE id = $1",
            attempt_id,
            status,
        )

    # ── Webhook events (replay / duplicate protection) ───────────────────

    async def record_webhook_event(
        self,
        gateway: str,
        gateway_event_id: str,
        event_type: str,
        payload_hash: str,
        signature_valid: bool,
        correlated_order_id: Optional[int],
        correlated_attempt_id: Optional[int],
    ) -> Optional[asyncpg.Record]:
        """Insert the webhook event row. Returns None if this (gateway,
        gateway_event_id) was already recorded — i.e. a duplicate delivery."""
        return await self.conn.fetchrow(
            """
            INSERT INTO payment_webhook_events (
                gateway, gateway_event_id, event_type, payload_hash,
                signature_valid, correlated_order_id, correlated_attempt_id,
                processing_status
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, 'received')
            ON CONFLICT (gateway, gateway_event_id) DO NOTHING
            RETURNING *
            """,
            gateway,
            gateway_event_id,
            event_type,
            payload_hash,
            signature_valid,
            correlated_order_id,
            correlated_attempt_id,
        )

    async def mark_webhook_processed(self, webhook_id: int, status: str, error_code: Optional[str] = None) -> None:
        await self.conn.execute(
            """
            UPDATE payment_webhook_events
            SET processing_status = $2, processed_at = now(), error_code = $3
            WHERE id = $1
            """,
            webhook_id,
            status,
            error_code,
        )

    # ── Explicit lifecycle expiry (WP4) ───────────────────────────────────

    async def expire_stale_orders(self) -> List[asyncpg.Record]:
        """Explicit, idempotent, concurrency-safe stale-order sweep.

        A single UPDATE...WHERE...RETURNING: idempotent because a second
        run's WHERE matches nothing already 'expired', and concurrency-safe
        under Postgres MVCC without any explicit locking primitive — two
        concurrent callers targeting overlapping rows serialize naturally
        (the second's WHERE re-evaluates after the first commits and finds
        the rows no longer match 'created'/'payment_pending').

        The NOT EXISTS guard is deliberate and goes beyond a naive
        "past expires_at" check: an order with a payment attempt still
        in flight with the gateway (initiated/pending/requires_verification)
        must never be expired out from under it — same race this codebase
        already defends against for registrations via
        PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY, applied here to the order row.
        'paid'/'cancelled'/already-'expired' orders are excluded by the
        status filter, so captured funds are never touched.
        """
        return await self.conn.fetch(
            """
            UPDATE payment_orders
            SET status = 'expired', updated_at = now()
            WHERE status IN ('created', 'payment_pending')
              AND expires_at < now()
              AND NOT EXISTS (
                  SELECT 1 FROM payment_attempts pa
                  WHERE pa.order_id = payment_orders.id
                    AND pa.status IN ('initiated', 'pending', 'requires_verification')
              )
            RETURNING id, public_order_number, event_id, registration_id
            """
        )

    # ── Verification (pending → requires_verification) ───────────────────

    async def record_verification_check(self, attempt_id: int) -> None:
        await self.conn.execute(
            """
            UPDATE payment_attempts
            SET verification_checked_at = now(),
                verification_check_count = verification_check_count + 1,
                updated_at = now()
            WHERE id = $1
            """,
            attempt_id,
        )

    # ── Exceptions (migration 016) ────────────────────────────────────────

    async def create_exception(
        self,
        exception_type: str,
        order_id: Optional[int],
        attempt_id: Optional[int],
        registration_id: Optional[int],
        summary: str,
        detail: Optional[Dict[str, Any]] = None,
    ) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO payment_exceptions (
                exception_type, order_id, attempt_id, registration_id, summary, detail
            ) VALUES ($1, $2, $3, $4, $5, $6::jsonb)
            RETURNING *
            """,
            exception_type,
            order_id,
            attempt_id,
            registration_id,
            summary,
            json.dumps(detail, default=str) if detail is not None else None,
        )

    async def get_open_exception(
        self, exception_type: str, attempt_id: Optional[int] = None, order_id: Optional[int] = None
    ) -> Optional[asyncpg.Record]:
        """Dedup guard so a repeatedly-checked stuck attempt doesn't create a
        new exception row every time it's polled."""
        return await self.conn.fetchrow(
            """
            SELECT * FROM payment_exceptions
            WHERE exception_type = $1 AND status = 'open'
              AND (attempt_id = $2 OR ($2 IS NULL AND attempt_id IS NULL))
              AND (order_id = $3 OR $3 IS NULL)
            LIMIT 1
            """,
            exception_type,
            attempt_id,
            order_id,
        )

    async def list_exceptions(self, status_filter: Optional[str] = None) -> List[asyncpg.Record]:
        if status_filter:
            return await self.conn.fetch(
                "SELECT * FROM payment_exceptions WHERE status = $1 ORDER BY created_at DESC",
                status_filter,
            )
        return await self.conn.fetch("SELECT * FROM payment_exceptions ORDER BY created_at DESC")
