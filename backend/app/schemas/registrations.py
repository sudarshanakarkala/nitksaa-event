"""Week 3 registration request and response schemas."""
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class RegisterRequest(BaseModel):
    """Body for POST /events/{event_id}/register.

    All profile data is fetched from alumni_db — the only client-supplied field
    is the optional attendee note, which is stored in registrations.notes.
    """

    attendee_note: Optional[str] = Field(None, max_length=500)


class AlumniProfileResponse(BaseModel):
    """Response for GET /alumni/me."""

    ref_id: str
    fullname: str
    email: str
    phone: Optional[str] = None
    batch_year: Optional[int] = None
    branch: Optional[str] = None
    is_active: bool


class EventSummary(BaseModel):
    """Embedded event summary included in registration responses."""

    event_id: int
    title: str
    start_datetime: datetime
    end_datetime: datetime
    timezone: str
    is_virtual: bool
    location_text: Optional[str] = None
    location_maps_url: Optional[str] = None


class RegistrationResponse(BaseModel):
    """Full registration detail — used in POST /register, GET /my-registration, GET /my/registrations.

    Field notes:
      email_snapshot   — maps from registrations.email (alumni email at registration time)
      phone_snapshot   — maps from registrations.phone
      attendee_note    — maps from registrations.notes
      join_url         — only present when user is registered for a published virtual event;
                         never present in public event APIs
      hold_expires_at  — only meaningful while status is a hold-bearing state
                         (seat_held/payment_pending/payment_verification/payment_failed);
                         None once registered/cancelled
    """

    registration_id: int
    registration_number: Optional[str] = None
    event_id: int
    firebase_uid: str
    ref_id: Optional[str] = None
    status: str
    fullname_snapshot: Optional[str] = None
    email_snapshot: Optional[str] = None
    phone_snapshot: Optional[str] = None
    batch_year_snapshot: Optional[int] = None
    branch_snapshot: Optional[str] = None
    attendee_note: Optional[str] = None
    registered_at: datetime
    cancelled_at: Optional[datetime] = None
    confirmation_email_status: Optional[str] = None
    confirmation_email_sent_at: Optional[datetime] = None
    hold_expires_at: Optional[datetime] = None
    join_url: Optional[str] = None
    event: Optional[EventSummary] = None
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class RegistrationEligibilityResponse(BaseModel):
    """Response for GET /events/{event_id}/registration-eligibility."""

    event_id: int
    firebase_uid: str
    eligibility_status: str
    message: str
    registered_count: Optional[int] = None
    capacity: Optional[int] = None
    payment_required: bool = False
    ticket_price: Optional[Decimal] = None


class MyRegistrationsListResponse(BaseModel):
    registrations: List[RegistrationResponse]
    total: int


# ── Admin: attendee management schemas ────────────────────────────────────────

class AdminAttendeeItem(BaseModel):
    """One row in the admin attendee list (status='registered' only)."""

    registration_id: int
    registration_number: Optional[str] = None
    fullname_snapshot: Optional[str] = None
    email_snapshot: Optional[str] = None
    phone_snapshot: Optional[str] = None
    batch_year_snapshot: Optional[int] = None
    branch_snapshot: Optional[str] = None
    registered_at: datetime
    status: str
    confirmation_email_status: Optional[str] = None

    model_config = {"from_attributes": True}


class AdminAttendeeListResponse(BaseModel):
    attendees: List[AdminAttendeeItem]
    total: int
    page: int
    per_page: int


class AdminRegistrationItem(BaseModel):
    """One row in the admin registrations audit view (all statuses)."""

    registration_id: int
    registration_number: Optional[str] = None
    fullname_snapshot: Optional[str] = None
    email_snapshot: Optional[str] = None
    status: str
    registered_at: datetime
    cancelled_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class AdminRegistrationListResponse(BaseModel):
    registrations: List[AdminRegistrationItem]
    total: int
    page: int
    per_page: int
