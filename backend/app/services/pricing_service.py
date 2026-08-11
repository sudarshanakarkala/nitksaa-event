"""Server-authoritative pricing for Payment Phase 0.

All arithmetic uses Decimal. The client never supplies an amount — every price
shown to or charged from the attendee is calculated here, from the event's
published payment_configurations row.

Convenience-fee percentage (when convenience_fee_type='percentage') is applied
to (base_amount + tax_amount), i.e. the payable total before the fee itself —
not to base_amount alone. There is no live configuration using percentage fees
yet, so this is a documented assumption, not an exercised path.
"""
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Dict


TWO_PLACES = Decimal("0.01")


def _q(value: Decimal) -> Decimal:
    return value.quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


def calculate_price(config: Dict[str, Any]) -> Dict[str, Any]:
    """Compute the full pricing breakdown for one payment_configurations row.

    `config` keys used: base_amount, gst_enabled, gst_rate, gst_mode,
    convenience_fee_enabled, convenience_fee_type, convenience_fee_value.
    All Decimal-typed values (asyncpg returns NUMERIC columns as Decimal).
    """
    base_amount = Decimal(config["base_amount"])
    if base_amount < 0:
        raise ValueError("base_amount must not be negative")

    gst_enabled = bool(config["gst_enabled"])
    gst_rate = Decimal(config["gst_rate"])
    gst_mode = config["gst_mode"]

    line_items = [{"label": "Registration fee", "amount": str(_q(base_amount))}]

    if not gst_enabled or gst_rate == 0:
        taxable_amount = base_amount
        tax_amount = Decimal("0.00")
    elif gst_mode == "exclusive":
        taxable_amount = base_amount
        tax_amount = _q(base_amount * gst_rate / Decimal(100))
        line_items.append({"label": f"GST ({gst_rate}%)", "amount": str(tax_amount)})
    elif gst_mode == "inclusive":
        taxable_amount = _q(base_amount / (Decimal(1) + gst_rate / Decimal(100)))
        tax_amount = _q(base_amount - taxable_amount)
        line_items[0]["amount"] = str(_q(base_amount))
        line_items.append(
            {"label": f"GST ({gst_rate}%, included)", "amount": str(tax_amount)}
        )
    else:
        raise ValueError(f"unknown gst_mode: {gst_mode!r}")

    payable_before_fee = base_amount if gst_mode == "inclusive" and gst_enabled else base_amount + tax_amount

    convenience_fee_enabled = bool(config["convenience_fee_enabled"])
    if not convenience_fee_enabled:
        convenience_fee = Decimal("0.00")
    else:
        fee_type = config["convenience_fee_type"]
        fee_value = Decimal(config["convenience_fee_value"])
        if fee_type == "fixed":
            convenience_fee = _q(fee_value)
        elif fee_type == "percentage":
            convenience_fee = _q(payable_before_fee * fee_value / Decimal(100))
        else:
            raise ValueError(f"unknown convenience_fee_type: {fee_type!r}")
        if convenience_fee > 0:
            line_items.append({"label": "Convenience fee", "amount": str(convenience_fee)})

    final_amount = _q(payable_before_fee + convenience_fee)

    return {
        "currency": config.get("currency", "INR"),
        "base_amount": _q(base_amount),
        "gst_enabled": gst_enabled,
        "gst_rate": gst_rate,
        "gst_mode": gst_mode,
        "taxable_amount": _q(taxable_amount),
        "tax_amount": tax_amount,
        "convenience_fee_enabled": convenience_fee_enabled,
        "convenience_fee": convenience_fee,
        "final_amount": final_amount,
        "line_items": line_items,
    }
