"""payment_refunds repository (migration 022).

The "one logical refund per order" guarantee is enforced by two database
indexes, not by the checks here:
  * uq_payment_refunds_idempotency      (idempotency_key)
  * uq_payment_refunds_active_per_order  (payment_order_id) WHERE status in
                                         ('pending','processing','processed')
Application-level lookups are a fast path; the UniqueViolationError handler in
refund_service is the real serialisation point (same pattern as
payment_orders / payment_attempts).
"""
import json
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

import asyncpg


class RefundRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def create(
        self,
        *,
        public_refund_number: str,
        registration_id: int,
        payment_order_id: int,
        payment_attempt_id: int,
        gateway: str,
        provider_payment_id: str,
        amount: Decimal,
        currency: str,
        idempotency_key: str,
        reason: str,
        requested_by: str,
        payment_mode: str = "test",
    ) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            INSERT INTO payment_refunds (
                public_refund_number, registration_id, payment_order_id,
                payment_attempt_id, gateway, provider_payment_id, amount,
                currency, idempotency_key, reason, requested_by, payment_mode, status
            ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'pending')
            RETURNING *
            """,
            public_refund_number, registration_id, payment_order_id,
            payment_attempt_id, gateway, provider_payment_id, amount,
            currency, idempotency_key, reason, requested_by, payment_mode,
        )

    async def get_by_idempotency_key(self, idempotency_key: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_refunds WHERE idempotency_key = $1", idempotency_key
        )

    async def get_active_for_order(self, payment_order_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            """
            SELECT * FROM payment_refunds
            WHERE payment_order_id = $1 AND status IN ('pending','processing','processed')
            ORDER BY requested_at DESC LIMIT 1
            """,
            payment_order_id,
        )

    async def get_by_public_number(self, public_refund_number: str) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            "SELECT * FROM payment_refunds WHERE public_refund_number = $1", public_refund_number
        )

    async def get_latest_for_registration(self, registration_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow(
            """
            SELECT * FROM payment_refunds
            WHERE registration_id = $1 ORDER BY requested_at DESC LIMIT 1
            """,
            registration_id,
        )

    async def get_by_id(self, refund_id: int) -> Optional[asyncpg.Record]:
        return await self.conn.fetchrow("SELECT * FROM payment_refunds WHERE id = $1", refund_id)

    async def mark(
        self,
        refund_id: int,
        *,
        status: str,
        provider_refund_id: Optional[str] = None,
        failure_reason: Optional[str] = None,
        finalized: bool = False,
    ) -> asyncpg.Record:
        return await self.conn.fetchrow(
            """
            UPDATE payment_refunds SET
                status = $2,
                provider_refund_id = COALESCE($3, provider_refund_id),
                failure_reason = $4,
                updated_at = now(),
                finalized_at = CASE WHEN $5 THEN now() ELSE finalized_at END
            WHERE id = $1
            RETURNING *
            """,
            refund_id, status, provider_refund_id, failure_reason, finalized,
        )

    async def list_all(self, status_filter: Optional[str] = None) -> List[asyncpg.Record]:
        if status_filter:
            return await self.conn.fetch(
                "SELECT * FROM payment_refunds WHERE status = $1 ORDER BY requested_at DESC",
                status_filter,
            )
        return await self.conn.fetch("SELECT * FROM payment_refunds ORDER BY requested_at DESC")
