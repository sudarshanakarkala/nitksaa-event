"""Keeps a published paid event's payment setup in step with the event.

The event form is the one place a creator sets the price (events.ticket_price).
Checkout charges from the event's published payment configuration, so this
makes a new configuration version whenever:
  - the event is published and has none yet;
  - the ticket price changed;
  - its Razorpay mode (test/live) differs from the server's RAZORPAY_MODE.

Configurations are append-only (PaymentRepository.create_new_config_version
retires the old row and inserts the next version), so orders already made
keep the price they were made at. GST, fee, gateway and hold times carry
over from the current version; a first version uses the plain defaults.
"""
from decimal import Decimal
from typing import Any, Dict, Optional

import asyncpg

from app.config import RAZORPAY_MODES, get_settings
from app.repositories.payment_repository import PaymentRepository


def server_payment_mode() -> str:
    mode = (get_settings().razorpay_mode or "test").strip().lower()
    return mode if mode in RAZORPAY_MODES else "test"


async def sync_event_payment_configuration(
    conn: asyncpg.Connection, event: Dict[str, Any], actor: str
) -> Optional[asyncpg.Record]:
    """Returns the new configuration when one was made, else None."""
    if event.get("status") != "published" or event.get("is_free") or not event.get("ticket_price"):
        return None

    price = Decimal(str(event["ticket_price"]))
    mode = server_payment_mode()
    repo = PaymentRepository(conn)
    current = await repo.get_published_config_for_event(event["event_id"])

    if current is not None:
        current_mode = current["payment_mode"] if "payment_mode" in current else "test"
        if Decimal(str(current["base_amount"])) == price and current_mode == mode:
            return None
        return await repo.create_new_config_version(
            configuration_key=current["configuration_key"],
            event_id=event["event_id"],
            base_amount=price,
            gst_enabled=current["gst_enabled"],
            gst_rate=current["gst_rate"],
            gst_mode=current["gst_mode"],
            convenience_fee_enabled=current["convenience_fee_enabled"],
            convenience_fee_type=current["convenience_fee_type"],
            convenience_fee_value=current["convenience_fee_value"],
            seat_hold_minutes=current["seat_hold_minutes"],
            payment_session_expiry_minutes=current["payment_session_expiry_minutes"],
            created_by=actor,
            gateway=current["gateway"] if "gateway" in current else "razorpay",
            payment_mode=mode,
        )

    return await repo.create_new_config_version(
        configuration_key=f"auto-event-{event['event_id']}",
        event_id=event["event_id"],
        base_amount=price,
        gst_enabled=False,
        gst_rate=Decimal("0"),
        gst_mode="exclusive",
        convenience_fee_enabled=False,
        convenience_fee_type="fixed",
        convenience_fee_value=Decimal("0"),
        seat_hold_minutes=15,
        payment_session_expiry_minutes=15,
        created_by=actor,
        gateway="razorpay",
        payment_mode=mode,
    )
