"""Alumni profile endpoint — authenticated, alumni-only."""
from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException

from app.middleware.auth import get_current_user
from app.schemas.registrations import AlumniProfileResponse
from app.services import alumni_service

router = APIRouter(prefix="/api/v1/alumni", tags=["alumni"])


@router.get("/me", response_model=AlumniProfileResponse)
async def get_my_alumni_profile(
    user: Dict[str, Any] = Depends(get_current_user),
) -> AlumniProfileResponse:
    if user.get("user_type") not in ["alumni", "admin"]:
        raise HTTPException(status_code=403, detail="alumni_only")

    ref_id = await alumni_service.resolve_alumni_ref_id(user)
    if not ref_id:
        raise HTTPException(status_code=403, detail="alumni_only")

    profile = await alumni_service.get_alumni_profile_by_ref_id(ref_id)
    if not profile:
        raise HTTPException(status_code=404, detail="alumni_profile_not_found")

    return AlumniProfileResponse(
        ref_id=profile["alumni_id"],
        fullname=profile["fullname"],
        email=profile["email"],
        phone=profile.get("phone"),
        batch_year=profile.get("graduationyear"),
        branch=profile.get("branch"),
        is_active=alumni_service.is_alumni_active(profile.get("registrationstatus")),
    )
