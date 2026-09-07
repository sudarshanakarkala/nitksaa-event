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


class PaymentCheckout(BaseModel):
    """Frontend-safe hosted-checkout payload (Razorpay Checkout). Public
    values only — never key_secret / webhook_secret. amount_minor is paise
    for INR; the server re-validates it against the order on verify-checkout."""

    provider: str
    provider_order_id: str
    key_id: str
    amount_minor: int
    currency: str


class PaymentAttemptResponse(BaseModel):
    attempt_id: str  # public_attempt_number
    order_id: str
    attempt_number: int
    gateway: str
    status: str
    scenario: Optional[str] = None
    initiated_at: datetime
    # Present only for hosted-checkout gateways (Razorpay). None for the
    # deterministic sandbox, which resolves in-process.
    checkout: Optional[PaymentCheckout] = None


class VerifyCheckoutRequest(BaseModel):
    """Client-returned Razorpay Checkout identifiers. The signature is a first
    gate only — the server independently queries authoritative provider
    status before confirming anything."""

    razorpay_payment_id: str = Field(..., min_length=1, max_length=64)
    razorpay_order_id: str = Field(..., min_length=1, max_length=64)
    razorpay_signature: str = Field(..., min_length=1, max_length=256)


class VerifyCheckoutResponse(BaseModel):
    order_id: str
    attempt_id: str
    order_status: str
    registration_status: str
    payment_confirmed: bool
    safe_message: str


class RefundStatusResponse(BaseModel):
    """Attendee-safe refund view. `status` is one of:
    refund_pending | refund_processed | refund_failed | none."""

    refund_id: Optional[str] = None
    registration_id: int
    status: str
    amount: Optional[Decimal] = None
    currency: Optional[str] = None
    requested_at: Optional[datetime] = None
    finalized_at: Optional[datetime] = None
    safe_message: str


class CancelRegistrationRequest(BaseModel):
    idempotency_key: str = Field(..., min_length=8, max_length=128)


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
    gateway: str = Field("deterministic_sandbox", pattern="^(deterministic_sandbox|razorpay)$")
