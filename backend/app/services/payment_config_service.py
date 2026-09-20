"""Production payment configuration lifecycle (WP1): draft -> validate ->
publish -> published, with append-only versioning and safe retirement of
the previously-published row.

This is additive to, not a replacement of, the existing dev-diagnostics
import path (app/api/dev_diagnostics.py -> PaymentRepository.
create_new_config_version), which stays development-only and continues to
create+publish in one step for sandbox/demo convenience. This module is the
first production-safe write path to payment_configurations.
"""
from decimal import Decimal
from typing import Any, Dict, List

import asyncpg
from fastapi import HTTPException

from app.database import get_pool
from app.repositories.payment_repository import PaymentRepository
from app.services import audit_service

_VALID_GST_MODES = ("inclusive", "exclusive")
_VALID_FEE_TYPES = ("fixed", "percentage")
_VALID_GATEWAYS = ("deterministic_sandbox", "razorpay")


def validate_configuration(
    payload: Dict[str, Any], *, require_live_credentials: bool = True
) -> List[str]:
    """Pure validation — no DB access. Returns a list of error strings;
    empty list means valid. Reused by draft creation, the explicit validate
    action, and publish, so a dry-run check and the actual write path can
    never disagree on everything except live-credential presence.

    `require_live_credentials` is deliberately the one thing draft creation
    opts out of (passes False): the spec's own wording ties the Live
    credential/prefix check to *publishing* LIVE, not to preparing a LIVE
    draft ahead of time (the whole point of "prepare LIVE mode safely" is
    being able to draft a LIVE pilot config before Live credentials exist).
    validate_draft() and publish() both use the default (True) — publishing
    LIVE with no Live credentials configured must fail closed."""
    errors: List[str] = []

    currency = payload.get("currency", "INR")
    if currency != "INR":
        errors.append("currency must be INR — no other currency is supported yet")

    base_amount = payload.get("base_amount")
    if base_amount is None or Decimal(base_amount) < 0:
        errors.append("base_amount must be a non-negative amount")

    gst_enabled = bool(payload.get("gst_enabled", False))
    gst_rate = payload.get("gst_rate", Decimal("0"))
    gst_mode = payload.get("gst_mode", "exclusive")
    if gst_mode not in _VALID_GST_MODES:
        errors.append(f"gst_mode must be one of {_VALID_GST_MODES}")
    if gst_enabled and not (Decimal("0") <= Decimal(gst_rate) <= Decimal("100")):
        errors.append("gst_rate must be between 0 and 100 when gst_enabled is true")

    convenience_fee_enabled = bool(payload.get("convenience_fee_enabled", False))
    convenience_fee_type = payload.get("convenience_fee_type", "fixed")
    convenience_fee_value = payload.get("convenience_fee_value", Decimal("0"))
    if convenience_fee_type not in _VALID_FEE_TYPES:
        errors.append(f"convenience_fee_type must be one of {_VALID_FEE_TYPES}")
    if convenience_fee_enabled and Decimal(convenience_fee_value) < 0:
        errors.append("convenience_fee_value must be non-negative when convenience_fee_enabled is true")
    if convenience_fee_type == "percentage" and Decimal(convenience_fee_value) > 100:
        errors.append("convenience_fee_value must not exceed 100 when convenience_fee_type is percentage")

    seat_hold_minutes = payload.get("seat_hold_minutes")
    if seat_hold_minutes is None or int(seat_hold_minutes) <= 0:
        errors.append("seat_hold_minutes must be a positive integer")

    payment_session_expiry_minutes = payload.get("payment_session_expiry_minutes")
    if payment_session_expiry_minutes is None or int(payment_session_expiry_minutes) <= 0:
        errors.append("payment_session_expiry_minutes must be a positive integer")

    gateway = payload.get("gateway", "deterministic_sandbox")
    if gateway not in _VALID_GATEWAYS:
        errors.append(f"gateway must be one of {_VALID_GATEWAYS}")

    payment_mode = payload.get("payment_mode", "test")
    if payment_mode not in ("test", "live"):
        errors.append("payment_mode must be one of ('test', 'live')")
    elif gateway == "razorpay" and payment_mode == "live" and require_live_credentials:
        # Fail closed at draft/validate/publish time, not first-use: a live
        # config must never be publishable unless real Live credentials with
        # the correct rzp_live_ prefix already exist server-side.
        from app.config import get_settings
        from app.gateways.razorpay_gateway import _KEY_PREFIX

        settings = get_settings()
        key_id, key_secret, webhook_secret = settings.razorpay_credentials_for("live")
        if not (key_id and key_secret and webhook_secret):
            errors.append(
                "gateway=razorpay with payment_mode=live requires "
                "RAZORPAY_LIVE_KEY_ID, RAZORPAY_LIVE_KEY_SECRET and "
                "RAZORPAY_LIVE_WEBHOOK_SECRET to all be configured"
            )
        elif not key_id.startswith(_KEY_PREFIX["live"]):
            errors.append(f"RAZORPAY_LIVE_KEY_ID must start with {_KEY_PREFIX['live']!r}")

    return errors


def _config_view(row: asyncpg.Record) -> Dict[str, Any]:
    return {
        "configuration_id": row["id"],
        "configuration_key": row["configuration_key"],
        "event_id": row["event_id"],
        "version": row["version"],
        "status": row["status"],
        "currency": row["currency"],
        "base_amount": row["base_amount"],
        "gst_enabled": row["gst_enabled"],
        "gst_rate": row["gst_rate"],
        "gst_mode": row["gst_mode"],
        "convenience_fee_enabled": row["convenience_fee_enabled"],
        "convenience_fee_type": row["convenience_fee_type"],
        "convenience_fee_value": row["convenience_fee_value"],
        "seat_hold_minutes": row["seat_hold_minutes"],
        "payment_session_expiry_minutes": row["payment_session_expiry_minutes"],
        "gateway": row["gateway"] if "gateway" in row else "deterministic_sandbox",
        "payment_mode": row["payment_mode"] if "payment_mode" in row else "test",
        "real_money": (row["payment_mode"] if "payment_mode" in row else "test") == "live",
        "created_by": row["created_by"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


async def create_draft(event_id: int, payload: Dict[str, Any], user: Dict[str, Any]) -> Dict[str, Any]:
    errors = validate_configuration(payload, require_live_credentials=False)
    if errors:
        raise HTTPException(status_code=422, detail={"errors": errors})

    pool = await get_pool()
    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)
        row = await pay_repo.create_draft_config(
            configuration_key=payload["configuration_key"],
            event_id=event_id,
            base_amount=Decimal(payload["base_amount"]),
            gst_enabled=bool(payload.get("gst_enabled", False)),
            gst_rate=Decimal(payload.get("gst_rate", "0")),
            gst_mode=payload.get("gst_mode", "exclusive"),
            convenience_fee_enabled=bool(payload.get("convenience_fee_enabled", False)),
            convenience_fee_type=payload.get("convenience_fee_type", "fixed"),
            convenience_fee_value=Decimal(payload.get("convenience_fee_value", "0")),
            seat_hold_minutes=int(payload.get("seat_hold_minutes", 15)),
            payment_session_expiry_minutes=int(payload.get("payment_session_expiry_minutes", 15)),
            created_by=user["firebase_uid"],
            gateway=payload.get("gateway", "deterministic_sandbox"),
            payment_mode=payload.get("payment_mode", "test"),
        )

    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="payment_configuration_draft_created",
        entity_type="payment_configuration",
        entity_id=row["id"],
        context={"event_id": event_id, "configuration_key": row["configuration_key"], "version": row["version"]},
    )
    return _config_view(row)


async def validate_draft(configuration_id: int, user: Dict[str, Any]) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await PaymentRepository(conn).get_config_by_id(configuration_id)
    if not row:
        raise HTTPException(status_code=404, detail="payment_configuration_not_found")
    errors = validate_configuration(dict(row))
    return {"configuration_id": configuration_id, "valid": not errors, "errors": errors}


async def publish(event_id: int, configuration_id: int, user: Dict[str, Any]) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        pay_repo = PaymentRepository(conn)
        row = await pay_repo.get_config_by_id(configuration_id)
        if not row or row["event_id"] != event_id:
            raise HTTPException(status_code=404, detail="payment_configuration_not_found")
        if row["status"] != "draft":
            raise HTTPException(status_code=409, detail="payment_configuration_not_a_draft")

        row_payment_mode = row["payment_mode"] if "payment_mode" in row else "test"
        if row_payment_mode == "live":
            # LIVE publish is restricted to the highest-trust role regardless
            # of who created the draft — event_admin alone is not enough.
            # The route-level Depends can't see the row's mode before this
            # point, so the gate lives here.
            from app.middleware.admin_auth import _resolve_platform_roles

            roles = await _resolve_platform_roles(user["firebase_uid"])
            if "platform_admin" not in roles:
                raise HTTPException(status_code=403, detail="live_publish_requires_platform_admin")

        errors = validate_configuration(dict(row))
        if errors:
            raise HTTPException(status_code=422, detail={"errors": errors})

        try:
            published = await pay_repo.publish_draft_config(configuration_id)
        except asyncpg.exceptions.UniqueViolationError:
            # Another draft for the same event won the publish race between
            # our SELECT above and our UPDATE — same defensive pattern as
            # payment_service.create_order's UniqueViolationError handling.
            raise HTTPException(status_code=409, detail="payment_configuration_publish_conflict")

        if published is None:
            # Row stopped being a draft between our check and the update
            # (e.g. published by a concurrent call that also passed our
            # first check) — report the same conflict, not a 500.
            raise HTTPException(status_code=409, detail="payment_configuration_publish_conflict")

        await conn.execute(
            "UPDATE events SET is_free = false, ticket_price = $2 WHERE event_id = $1",
            event_id,
            published["base_amount"],
        )

    await audit_service.emit(
        actor_uid=user["firebase_uid"],
        event_type="payment_configuration_published",
        entity_type="payment_configuration",
        entity_id=published["id"],
        context={"event_id": event_id, "configuration_key": published["configuration_key"], "version": published["version"]},
    )
    return _config_view(published)


async def list_history(event_id: int) -> List[Dict[str, Any]]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await PaymentRepository(conn).list_configs_for_event(event_id)
    return [_config_view(r) for r in rows]


async def get_one(event_id: int, configuration_id: int) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await PaymentRepository(conn).get_config_by_id(configuration_id)
    if not row or row["event_id"] != event_id:
        raise HTTPException(status_code=404, detail="payment_configuration_not_found")
    return _config_view(row)
