"""Schemas for the production payment admin surface (WP1 configuration
lifecycle, WP2 RBAC role management, WP4 lifecycle-sweep triggers).

Kept separate from app/schemas/payments.py, which covers the attendee-facing
and dev-diagnostics payment surfaces.
"""
from datetime import datetime
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, Field


# ── WP1: payment configuration lifecycle ───────────────────────────────────

class PaymentConfigDraftCreateRequest(BaseModel):
    configuration_key: str = Field(..., min_length=3, max_length=100)
    base_amount: Decimal = Field(..., ge=0)
    gst_enabled: bool = False
    gst_rate: Decimal = Field(Decimal("0"), ge=0, le=100)
    gst_mode: str = Field("exclusive", pattern="^(inclusive|exclusive)$")
    convenience_fee_enabled: bool = False
    convenience_fee_type: str = Field("fixed", pattern="^(fixed|percentage)$")
    convenience_fee_value: Decimal = Field(Decimal("0"), ge=0)
    seat_hold_minutes: int = Field(15, gt=0)
    payment_session_expiry_minutes: int = Field(15, gt=0)


class PaymentConfigAdminResponse(BaseModel):
    configuration_id: int
    configuration_key: str
    event_id: int
    version: int
    status: str
    currency: str
    base_amount: Decimal
    gst_enabled: bool
    gst_rate: Decimal
    gst_mode: str
    convenience_fee_enabled: bool
    convenience_fee_type: str
    convenience_fee_value: Decimal
    seat_hold_minutes: int
    payment_session_expiry_minutes: int
    created_by: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None


class PaymentConfigListResponse(BaseModel):
    event_id: int
    configurations: List[PaymentConfigAdminResponse]


class PaymentConfigValidateResponse(BaseModel):
    configuration_id: int
    valid: bool
    errors: List[str]


# ── WP2: payment RBAC ───────────────────────────────────────────────────────

class PlatformRoleGrantRequest(BaseModel):
    firebase_uid: str = Field(..., min_length=1, max_length=128)
    role: str = Field(..., pattern="^(platform_admin|finance_operator|auditor|support)$")


class PlatformRoleResponse(BaseModel):
    id: int
    firebase_uid: str
    role: str
    granted_by: str
    granted_at: datetime
    revoked_at: Optional[datetime] = None
    revoked_by: Optional[str] = None


class PlatformRoleListResponse(BaseModel):
    roles: List[PlatformRoleResponse]


class EventPaymentAdminGrantRequest(BaseModel):
    firebase_uid: str = Field(..., min_length=1, max_length=128)


class EventPaymentAdminGrantResponse(BaseModel):
    event_id: int
    firebase_uid: str
    role: str
    status: str


# ── WP4: lifecycle sweep triggers ───────────────────────────────────────────

class ExpireOrdersResponse(BaseModel):
    expired_count: int
    expired_order_ids: List[str]


class ExpireHoldsResponse(BaseModel):
    expired_count: int
    expired_registration_ids: List[int]


# ── Gateway registry diagnostics (Sprint 7 — read-only, no secrets) ────────

class GatewayInfo(BaseModel):
    name: str
    enabled: bool
    capabilities: List[str]
    supported_scenarios: List[str]


class GatewayConfigResponse(BaseModel):
    environment: str
    configured_gateway_mode: str
    active_gateway: Optional[str] = None
    gateways: List[GatewayInfo]
