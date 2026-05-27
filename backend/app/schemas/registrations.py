import json
from pydantic import BaseModel, Field, EmailStr, field_validator
from typing import Optional, Dict, Any
from datetime import datetime


def _parse_jsonb(v: Any) -> Any:
    """asyncpg returns JSONB columns as raw strings; parse them to Python dicts."""
    if isinstance(v, str):
        return json.loads(v)
    return v


class RegistrationCreate(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=255)
    email: EmailStr
    firebase_uid: Optional[str] = None
    ref_id: Optional[str] = None
    phone: Optional[str] = None
    badge_name: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = {}


class RegistrationResponse(BaseModel):
    registration_id: int
    event_id: int
    firebase_uid: Optional[str]
    ref_id: Optional[str]
    email: Optional[str]
    full_name: str
    status: str
    registration_source: str
    qr_token: Optional[str]
    registered_at: datetime
    cancelled_at: Optional[datetime]
    cancel_reason: Optional[str]
    metadata: Optional[Dict[str, Any]]
    created_at: datetime

    @field_validator("metadata", mode="before")
    @classmethod
    def parse_metadata(cls, v: Any) -> Any:
        return _parse_jsonb(v)


class AttendeeResponse(BaseModel):
    attendee_id: int
    registration_id: int
    event_id: int
    ref_id: Optional[str]
    firebase_uid: Optional[str]
    attendee_type: str
    display_name: str
    email: Optional[str]
    phone: Optional[str]
    badge_name: Optional[str]
    created_at: datetime
