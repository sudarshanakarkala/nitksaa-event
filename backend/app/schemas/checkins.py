"""Check-in schemas, aligned to the real check_ins table (checkin_id,
registration_id, event_id, session_id, scanned_by, scanned_at, result).

The original design assumed a separate "attendee" entity (attendee_id),
a qr_token/ref_id/firebase_uid copied onto the check-in row, and free-text
method/notes/metadata fields — none of that has a backing column.
registration_id is the attendee identity (registrations IS the attendee
record); qr_token lookup happens via registrations.qrtoken, not a copy on
check_ins. See the admin-event-schema-alignment sprint report.

CheckInAttemptResponse was removed: no check_in_attempts table exists in
the active schema — the list-attempts route returns 501, not a fabricated
empty/degraded response.
"""
from pydantic import BaseModel, ConfigDict, Field, model_validator
from typing import Optional
from datetime import datetime


class CheckInCreate(BaseModel):
    """Check someone in by their entry pass token (a scan), or by their
    registration (the admin Check-in list, e.g. someone without their QR).
    Exactly one of the two."""

    qr_token: Optional[str] = None
    registration_id: Optional[int] = None
    session_id: Optional[int] = None

    @model_validator(mode="after")
    def _one_way(self):
        if (self.qr_token is None) == (self.registration_id is None):
            raise ValueError("give either qr_token or registration_id")
        return self


class CheckInResponse(BaseModel):
    """Public field names checked_in_at/checked_in_by are kept stable via
    validation_alias, reading from the real columns scanned_at/scanned_by."""

    model_config = ConfigDict(populate_by_name=True)

    checkin_id: int
    event_id: int
    session_id: Optional[int] = None
    registration_id: int
    checked_in_at: datetime = Field(validation_alias="scanned_at")
    checked_in_by: str = Field(validation_alias="scanned_by")
    result: str


class QRVerifyResponse(BaseModel):
    valid: bool
    qr_token: str
    registration_id: Optional[int] = None
    full_name: Optional[str] = None
    email: Optional[str] = None
    ref_id: Optional[str] = None
    registration_status: Optional[str] = None
    already_checked_in: bool
    message: str
