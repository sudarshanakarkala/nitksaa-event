"""Payment Phase 0 endpoints — deterministic sandbox gateway only.

Attendee endpoints require authentication and enforce ownership (a payment
order/attempt is only visible to the payer who created it). The webhook
endpoint is unauthenticated by design (gateways cannot present a bearer
token) and instead relies on HMAC signature verification.
"""
from typing import Any, Dict

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException, Request

from app.config import get_settings
from app.gateways import registry as gateway_registry
from app.gateways.registry import GatewayDisabledError, UnknownGatewayError
from app.middleware.auth import get_current_user
from app.schemas.payments import (
    CreatePaymentAttemptRequest,
    CreatePaymentOrderRequest,
    PaymentAttemptResponse,
    PaymentOrderResponse,
    PaymentTimelineResponse,
    PricingBreakdownResponse,
    VerifyCheckoutRequest,
    VerifyCheckoutResponse,
    WebhookAckResponse,
)
from app.services import payment_service

router = APIRouter(tags=["payments"])


@router.get(
    "/api/v1/events/{event_id}/payment-pricing",
    response_model=PricingBreakdownResponse,
)
async def get_payment_pricing(
    event_id: int,
    user: Dict[str, Any] = Depends(get_current_user),
) -> PricingBreakdownResponse:
    return await payment_service.get_pricing(event_id)


@router.post(
    "/api/v1/registrations/{registration_id}/payment-order",
    response_model=PaymentOrderResponse,
    status_code=201,
)
async def create_payment_order(
    registration_id: int,
    body: CreatePaymentOrderRequest,
    user: Dict[str, Any] = Depends(get_current_user),
) -> PaymentOrderResponse:
    return await payment_service.create_order(registration_id, user, body.idempotency_key)


@router.get(
    "/api/v1/payment-orders/{order_id}",
    response_model=PaymentOrderResponse,
)
async def get_payment_order(
    order_id: str,
    user: Dict[str, Any] = Depends(get_current_user),
) -> PaymentOrderResponse:
    return await payment_service.get_order(order_id, user)


@router.post(
    "/api/v1/payment-orders/{order_id}/attempts",
    response_model=PaymentAttemptResponse,
    status_code=201,
)
async def create_payment_attempt(
    order_id: str,
    body: CreatePaymentAttemptRequest,
    background_tasks: BackgroundTasks,
    user: Dict[str, Any] = Depends(get_current_user),
) -> PaymentAttemptResponse:
    return await payment_service.create_attempt(order_id, user, body, background_tasks)


@router.get(
    "/api/v1/payment-orders/{order_id}/timeline",
    response_model=PaymentTimelineResponse,
)
async def get_payment_timeline(
    order_id: str,
    user: Dict[str, Any] = Depends(get_current_user),
) -> PaymentTimelineResponse:
    return await payment_service.get_timeline(order_id, user)


@router.post(
    "/api/v1/payment-attempts/{attempt_id}/verify",
    response_model=PaymentAttemptResponse,
)
async def verify_payment_attempt(
    attempt_id: str,
    user: Dict[str, Any] = Depends(get_current_user),
) -> PaymentAttemptResponse:
    return await payment_service.verify_attempt(attempt_id, user)


@router.post(
    "/api/v1/payment-orders/{order_id}/verify-checkout",
    response_model=VerifyCheckoutResponse,
)
async def verify_payment_checkout(
    order_id: str,
    body: VerifyCheckoutRequest,
    user: Dict[str, Any] = Depends(get_current_user),
) -> VerifyCheckoutResponse:
    """Backend verification of a Razorpay Checkout return. The client-supplied
    signature is only a first gate — the server independently queries
    authoritative provider status before confirming the registration."""
    return await payment_service.verify_checkout(order_id, user, body)


@router.post(
    "/api/v1/payment-gateways/{gateway}/webhook",
    response_model=WebhookAckResponse,
)
async def receive_payment_webhook(
    gateway: str,
    request: Request,
    x_sandbox_signature: str = Header(default=""),
    x_razorpay_signature: str = Header(default=""),
    x_razorpay_event_id: str = Header(default=""),
) -> WebhookAckResponse:
    # Registry-backed, not a hardcoded name check: an unregistered or
    # environment-disabled gateway is rejected the same way a genuinely
    # unknown one is (existence-hiding — both return the same 404/detail).
    try:
        gateway_registry.get_enabled_gateway(gateway, get_settings())
    except (UnknownGatewayError, GatewayDisabledError):
        raise HTTPException(status_code=404, detail="unknown_gateway")
    # Raw body bytes are passed through untouched — signature verification
    # (sandbox HMAC and Razorpay HMAC alike) is over the exact received bytes,
    # never a re-serialised copy.
    raw_body = await request.body()
    if gateway == "razorpay":
        signature = x_razorpay_signature
        provider_event_id = x_razorpay_event_id or None
    else:
        signature = x_sandbox_signature
        provider_event_id = None
    return await payment_service.process_webhook(gateway, raw_body, signature, provider_event_id)
