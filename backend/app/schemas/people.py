from datetime import datetime
from typing import Optional
from pydantic import BaseModel, field_validator


VALID_ROLES = {
    "HOST", "MODERATOR", "SPEAKER", "PANELIST",
    "CHIEF_GUEST", "GUEST_OF_HONOUR", "ORGANIZER",
}


class PersonCreate(BaseModel):
    role: str
    fullname: str
    title: Optional[str] = None
    organisation: Optional[str] = None
    bio: Optional[str] = None
    photo_url: Optional[str] = None
    linkedin_url: Optional[str] = None
    display_order: int = 0
    is_visible: bool = True

    @field_validator("role")
    @classmethod
    def validate_role(cls, v: str) -> str:
        v = v.upper()
        if v not in VALID_ROLES:
            raise ValueError(f"role must be one of: {', '.join(sorted(VALID_ROLES))}")
        return v


class PersonUpdate(BaseModel):
    role: Optional[str] = None
    fullname: Optional[str] = None
    title: Optional[str] = None
    organisation: Optional[str] = None
    bio: Optional[str] = None
    photo_url: Optional[str] = None
    linkedin_url: Optional[str] = None
    display_order: Optional[int] = None
    is_visible: Optional[bool] = None

    @field_validator("role")
    @classmethod
    def validate_role(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        v = v.upper()
        if v not in VALID_ROLES:
            raise ValueError(f"role must be one of: {', '.join(sorted(VALID_ROLES))}")
        return v


class PersonResponse(BaseModel):
    person_id: int
    event_id: int
    role: str
    fullname: str
    title: Optional[str] = None
    organisation: Optional[str] = None
    bio: Optional[str] = None
    photo_url: Optional[str] = None
    linkedin_url: Optional[str] = None
    display_order: int
    is_visible: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


