"""Payment Phase 0 schemas — deterministic sandbox gateway only.

INR only. Amounts are always Decimal server-side; the client never supplies
a final amount, only selection inputs (currently: none — pricing is derived
entirely from the event's published payment configuration).
"""
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class PricingBreakdownResponse(BaseModel):
    """Response for GET /events/{event_id}/payment-pricing — server-calculated only."""

    event_id: int
    configuration_key: str
    currency: str
    base_amount: Decimal
    gst_enabled: bool
    gst_rate: Decimal
    gst_mode: str
    tax_amount: Decimal
    convenience_fee_enabled: bool
    convenience_fee: Decimal
    final_amount: Decimal
    line_items: List[Dict[str, Any]]


class CreatePaymentOrderRequest(BaseModel):
    idempotency_key: str = Field(..., min_length=8, max_length=128)


class PaymentOrderResponse(BaseModel):
    order_id: str  # public_order_number
    registration_id: int
    event_id: int
    currency: str
    base_amount: Decimal
    tax_amount: Decimal
    convenience_fee: Decimal
    final_amount: Decimal
    amount_paid: Decimal
    outstanding_amount: Decimal
    status: str
    registration_status: str
    expires_at: datetime
    can_pay: bool
    can_retry: bool
    safe_message: str


class CreatePaymentAttemptRequest(BaseModel):
    """Dev/sandbox-only field. In a real gateway this would not exist — the
    gateway itself determines the outcome, not the caller."""

    scenario: str = Field(
        "SUCCESS",
        description="Sandbox scenario: SUCCESS | FAILURE | PENDING | CANCELLED | DELAYED_SUCCESS | DELAYED_FAILURE",
    )


class ResolvePendingAttemptRequest(BaseModel):
    """Dev-diagnostics-only. Resolves a live 'pending'/'requires_verification'
    attempt to a terminal outcome by building and processing the same signed
    webhook delivery the sandbox gateway would eventually send — the only
    HTTP-reachable way to do this, since the signing secret never leaves the
    backend and no client can construct a validly-signed delivery itself."""

    outcome: str = Field(pattern="^(SUCCESS|FAILURE)$")


class PaymentAttemptResponse(BaseModel):
    attempt_id: str  # public_attempt_number
    order_id: str
    attempt_number: int
    gateway: str
    status: str
    scenario: Optional[str] = None
    initiated_at: datetime


class TimelineEntry(BaseModel):
    event_type: str
    entity_type: str
    at: datetime
    detail: Optional[Dict[str, Any]] = None
    label: Optional[str] = None  # attendee-friendly label; None in the technical/developer view


class PaymentTimelineResponse(BaseModel):
    order_id: str
    entries: List[TimelineEntry]


class PaymentExceptionResponse(BaseModel):
    id: int
    exception_type: str
    status: str
    order_id: Optional[int] = None
    attempt_id: Optional[int] = None
    registration_id: Optional[int] = None
    summary: str
    detail: Optional[Dict[str, Any]] = None
    created_at: datetime
    resolved_at: Optional[datetime] = None
    resolved_by: Optional[str] = None
    resolution: Optional[str] = None


class WebhookAckResponse(BaseModel):
    status: str
    processing_status: str


class PaymentConfigImportRequest(BaseModel):
    """Dev-only: upsert a published payment_configurations row for an event.

    Not the full draft/approve/publish workflow from the Phase 0 spec —
    that's later work. This also flips events.is_free=false and sets
    events.ticket_price=base_amount so the existing event-display fields
    stay in sync with the new configuration.
    """

    configuration_key: str = Field(..., min_length=3, max_length=100)
    event_id: int
    base_amount: Decimal = Field(..., ge=0)
    gst_enabled: bool = False
    gst_rate: Decimal = Field(Decimal("0"), ge=0, le=100)
    gst_mode: str = Field("exclusive", pattern="^(inclusive|exclusive)$")
    convenience_fee_enabled: bool = False
    convenience_fee_type: str = Field("fixed", pattern="^(fixed|percentage)$")
    convenience_fee_value: Decimal = Field(Decimal("0"), ge=0)
    seat_hold_minutes: int = Field(15, gt=0)
    payment_session_expiry_minutes: int = Field(15, gt=0)
