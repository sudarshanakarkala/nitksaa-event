import json
from pydantic import BaseModel, field_validator
from typing import Optional, Dict, Any
from datetime import datetime


def _parse_jsonb(v: Any) -> Any:
    if isinstance(v, str):
        return json.loads(v)
    return v


class CheckInCreate(BaseModel):
    qr_token: str
    session_id: Optional[int] = None
    notes: Optional[str] = None


class CheckInResponse(BaseModel):
    check_in_id: int
    event_id: int
    session_id: Optional[int]
    registration_id: Optional[int]
    attendee_id: Optional[int]
    ref_id: Optional[str]
    firebase_uid: Optional[str]
    qr_token: Optional[str]
    checked_in_at: datetime
    checked_in_by: Optional[str]
    method: str
    notes: Optional[str]
    metadata: Optional[Dict[str, Any]]

    @field_validator("metadata", mode="before")
    @classmethod
    def parse_metadata(cls, v: Any) -> Any:
        return _parse_jsonb(v)


class CheckInAttemptResponse(BaseModel):
    attempt_id: int
    event_id: Optional[int]
    qr_token: Optional[str]
    registration_id: Optional[int]
    attendee_id: Optional[int]
    attempt_status: str
    attempted_by: Optional[str]
    attempted_at: datetime
    notes: Optional[str]


class QRVerifyResponse(BaseModel):
    valid: bool
    qr_token: str
    registration_id: Optional[int]
    attendee_id: Optional[int]
    full_name: Optional[str]
    email: Optional[str]
    ref_id: Optional[str]
    registration_status: Optional[str]
    already_checked_in: bool
    message: str
