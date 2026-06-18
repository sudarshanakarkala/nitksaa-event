from pydantic import BaseModel, Field, model_validator
from typing import Optional
from datetime import datetime


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

    @model_validator(mode="after")
    def validate_event(self) -> "EventCreate":
        if self.end_datetime <= self.start_datetime:
            raise ValueError("end_datetime must be after start_datetime")
        if not self.is_virtual and not self.location_text:
            raise ValueError("location_text is required for physical events")
        if self.is_virtual and not self.virtual_url:
            raise ValueError("virtual_url is required for virtual events")
        return self