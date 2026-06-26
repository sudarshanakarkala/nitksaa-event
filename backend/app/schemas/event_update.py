from decimal import Decimal
from pydantic import BaseModel, Field, model_validator
from typing import Optional
from datetime import datetime


class EventUpdate(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=255)
    tagline: Optional[str] = None
    description: Optional[str] = None
    start_datetime: Optional[datetime] = None
    end_datetime: Optional[datetime] = None
    timezone: Optional[str] = None
    location_text: Optional[str] = None
    location_maps_url: Optional[str] = None
    is_virtual: Optional[bool] = None
    virtual_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    banner_url: Optional[str] = None
    capacity: Optional[int] = Field(default=None, gt=0)
    show_attendee_list: Optional[bool] = None
    registration_opens_at: Optional[datetime] = None
    registration_closes_at: Optional[datetime] = None
    is_full_day: Optional[bool] = None
    is_free: Optional[bool] = None
    ticket_price: Optional[Decimal] = Field(default=None, ge=0)

    @model_validator(mode="after")
    def validate_datetimes(self) -> "EventUpdate":
        if self.start_datetime and self.end_datetime:
            if self.end_datetime <= self.start_datetime:
                raise ValueError("end_datetime must be after start_datetime")
        if self.is_free is True:
            self.ticket_price = None
        return self