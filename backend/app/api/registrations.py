"""Registration endpoints — all require authentication."""
from typing import Any, Dict

from fastapi import APIRouter, Depends

from app.middleware.auth import get_current_user
from app.schemas.registrations import (
    MyRegistrationsListResponse,
    RegisterRequest,
    RegistrationEligibilityResponse,
    RegistrationResponse,
)
from app.services import registration_service

router = APIRouter(tags=["registrations"])


@router.post(
    "/api/v1/events/{event_id}/register",
    response_model=RegistrationResponse,
    status_code=201,
)
async def register_for_event(
    event_id: int,
    body: RegisterRequest,
    user: Dict[str, Any] = Depends(get_current_user),
) -> RegistrationResponse:
    return await registration_service.register_for_event(event_id, user, body)


@router.get(
    "/api/v1/events/{event_id}/my-registration",
    response_model=RegistrationResponse,
)
async def get_my_event_registration(
    event_id: int,
    user: Dict[str, Any] = Depends(get_current_user),
) -> RegistrationResponse:
    return await registration_service.get_my_event_registration(event_id, user)


@router.get(
    "/api/v1/my/registrations",
    response_model=MyRegistrationsListResponse,
)
async def list_my_registrations(
    user: Dict[str, Any] = Depends(get_current_user),
) -> MyRegistrationsListResponse:
    return await registration_service.list_my_registrations(user)


@router.get(
    "/api/v1/events/{event_id}/registration-eligibility",
    response_model=RegistrationEligibilityResponse,
)
async def get_registration_eligibility(
    event_id: int,
    user: Dict[str, Any] = Depends(get_current_user),
) -> RegistrationEligibilityResponse:
    return await registration_service.get_registration_eligibility(event_id, user)
