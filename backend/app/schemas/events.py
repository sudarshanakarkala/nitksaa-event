from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class EventCreate(BaseModel):
    slug: str = Field(..., min_length=3, max_length=100)
    title: str = Field(..., min_length=3, max_length=255)
    description: Optional[str] = None
    event_type: str = "event"
    venue_name: Optional[str] = None
    venue_address: Optional[str] = None
    city: Optional[str] = None
    country: str = "India"
    is_virtual: bool = False
    virtual_url: Optional[str] = None
    starts_at: datetime
    ends_at: Optional[datetime] = None
    timezone: str = "Asia/Kolkata"
    capacity: Optional[int] = None
    registration_opens_at: Optional[datetime] = None
    registration_closes_at: Optional[datetime] = None


class EventUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    event_type: Optional[str] = None
    venue_name: Optional[str] = None
    venue_address: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    is_virtual: Optional[bool] = None
    virtual_url: Optional[str] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    timezone: Optional[str] = None
    capacity: Optional[int] = None
    registration_opens_at: Optional[datetime] = None
    registration_closes_at: Optional[datetime] = None


class EventResponse(BaseModel):
    event_id: int
    slug: str
    title: str
    description: Optional[str]
    event_type: str
    venue_name: Optional[str]
    venue_address: Optional[str]
    city: Optional[str]
    country: str
    is_virtual: bool
    virtual_url: Optional[str]
    starts_at: datetime
    ends_at: Optional[datetime]
    timezone: str
    capacity: Optional[int]
    registration_opens_at: Optional[datetime]
    registration_closes_at: Optional[datetime]
    status: str
    created_by: Optional[str]
    created_at: datetime
    updated_at: datetime


class SessionCreate(BaseModel):
    title: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = None
    speaker_name: Optional[str] = None
    location: Optional[str] = None
    track_name: Optional[str] = None
    starts_at: datetime
    ends_at: Optional[datetime] = None
    capacity: Optional[int] = None
    sort_order: int = 0


class SessionResponse(BaseModel):
    session_id: int
    event_id: int
    title: str
    description: Optional[str]
    speaker_name: Optional[str]
    location: Optional[str]
    track_name: Optional[str]
    starts_at: datetime
    ends_at: Optional[datetime]
    capacity: Optional[int]
    status: str
    sort_order: int
    created_at: datetime
