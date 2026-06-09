from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime


class EventResponse(BaseModel):
    event_id: int
    slug: str
    title: str
    tagline: Optional[str] = None
    description: Optional[str] = None
    status: str
    start_datetime: datetime
    end_datetime: datetime
    timezone: str
    location_text: Optional[str] = None
    location_maps_url: Optional[str] = None
    is_virtual: bool
    virtual_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    banner_url: Optional[str] = None
    capacity: Optional[int] = None
    registration_opens_at: Optional[datetime] = None
    registration_closes_at: Optional[datetime] = None
    registered_count: int = 0
    registration_status: str
    created_by_firebase_uid: str
    created_by_name: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None
    published_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None
    cancelled_reason: Optional[str] = None

    model_config = {"from_attributes": True}


class PublicEventResponse(BaseModel):
    event_id: int
    slug: str
    title: str
    tagline: Optional[str] = None
    description: Optional[str] = None
    status: str
    start_datetime: datetime
    end_datetime: datetime
    timezone: str
    location_text: Optional[str] = None
    location_maps_url: Optional[str] = None
    is_virtual: bool
    thumbnail_url: Optional[str] = None
    banner_url: Optional[str] = None
    capacity: Optional[int] = None
    registered_count: int = 0
    registration_status: str
    published_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class PublicEventDetailResponse(PublicEventResponse):
    sessions: List[Any] = []
    speakers: List[Any] = []
