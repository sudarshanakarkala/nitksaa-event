"""Attendee-owned cancellation + refund endpoints.

All routes require the production Firebase-token auth dependency and enforce
ownership in the service layer (registration must belong to the caller —
cross-user calls get a 404, never someone else's data).
"""
from typing import Any, Dict

from fastapi import APIRouter, Depends

from app.middleware.auth import get_current_user
from app.schemas.payments import CancelRegistrationRequest, RefundStatusResponse
from app.services import refund_service

router = APIRouter(tags=["refunds"])


@router.post(
    "/api/v1/registrations/{registration_id}/cancel",
    response_model=RefundStatusResponse,
)
async def cancel_registration(
    registration_id: int,
    body: CancelRegistrationRequest,
    user: Dict[str, Any] = Depends(get_current_user),
) -> RefundStatusResponse:
    """Cancel the caller's own registration. For a confirmed paid
    registration this also creates one full refund with the configured
    gateway and returns its status; for a free registration it just
    cancels. Idempotent per `idempotency_key`."""
    return await refund_service.cancel_registration(registration_id, user, body.idempotency_key)


@router.get(
    "/api/v1/registrations/{registration_id}/refund",
    response_model=RefundStatusResponse,
)
async def get_refund_status(
    registration_id: int,
    user: Dict[str, Any] = Depends(get_current_user),
) -> RefundStatusResponse:
    return await refund_service.get_refund_status(registration_id, user)
