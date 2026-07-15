from decimal import Decimal
from pydantic import BaseModel, Field, model_validator
from typing import Optional, List
from datetime import datetime


class SessionCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    speaker_name: Optional[str] = None
    start_datetime: datetime
    end_datetime: datetime


class SpeakerCreate(BaseModel):
    fullname: str = Field(..., min_length=1, max_length=255)
    title: Optional[str] = None
    organisation: Optional[str] = None
    role: str = "SPEAKER"


class SponsorCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    sponsor_type: str
    logo_url: Optional[str] = None
    website_url: Optional[str] = None
    display_order: int = 0


class EventCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    tagline: Optional[str] = None
    description: Optional[str] = None
    start_datetime: datetime
    end_datetime: datetime
    timezone: str = Field(default="Asia/Kolkata", max_length=60)
    location_text: Optional[str] = None
    location_maps_url: Optional[str] = None
    is_virtual: bool = False
    virtual_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    banner_url: Optional[str] = None
    capacity: Optional[int] = Field(default=None, gt=0)
    show_attendee_list: bool = False
    registration_opens_at: Optional[datetime] = None
    registration_closes_at: Optional[datetime] = None
    is_full_day: bool = False
    is_free: bool = True
    ticket_price: Optional[Decimal] = Field(default=None, ge=0)
    sessions: Optional[List[SessionCreate]] = []
    speakers: Optional[List[SpeakerCreate]] = []
    sponsors: Optional[List[SponsorCreate]] = []

    @model_validator(mode="after")
    def validate_event(self) -> "EventCreate":
        if self.is_full_day:
            if self.end_datetime.date() < self.start_datetime.date():
                raise ValueError("end date must be on or after start date for full-day events")
        else:
            if self.end_datetime <= self.start_datetime:
                raise ValueError("end_datetime must be after start_datetime")
        if not self.is_virtual and not self.location_text:
            raise ValueError("location_text is required for physical events")
        if self.is_virtual and not self.virtual_url:
            raise ValueError("virtual_url is required for virtual events")
        if not self.is_free and self.ticket_price is None:
            raise ValueError("ticket_price is required for paid events")
        if self.is_free:
            self.ticket_price = None
        return self