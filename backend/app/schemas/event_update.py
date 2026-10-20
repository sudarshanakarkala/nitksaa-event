from decimal import Decimal
from pydantic import BaseModel, Field, model_validator
from typing import Optional
from datetime import datetime

from app.services.slug_service import SLUG_PATTERN

# An accent colour: #RRGGBB (the database checks the same).
BRAND_ACCENT_PATTERN = r"^#[0-9A-Fa-f]{6}$"


class EventUpdate(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=255)
    # The event's link (/e/<slug>). Only a never-published event may change
    # it (checked in EventsService.update_event).
    slug: Optional[str] = Field(default=None, min_length=3, max_length=60,
                                pattern=SLUG_PATTERN)
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
    # Branding, all optional: logos for light and dark backgrounds and
    # one accent colour. Empty strings clear them.
    brand_logo_url: Optional[str] = Field(default=None, max_length=2048)
    brand_logo_dark_url: Optional[str] = Field(default=None, max_length=2048)
    brand_accent: Optional[str] = Field(default=None, pattern=BRAND_ACCENT_PATTERN)
    capacity: Optional[int] = Field(default=None, gt=0)
    show_attendee_list: Optional[bool] = None
    max_guests: Optional[int] = Field(default=None, ge=0, le=4)
    registration_opens_at: Optional[datetime] = None
    registration_closes_at: Optional[datetime] = None
    is_full_day: Optional[bool] = None
    is_free: Optional[bool] = None
    ticket_price: Optional[Decimal] = Field(default=None, ge=0)

    @model_validator(mode="after")
    def validate_datetimes(self) -> "EventUpdate":
        # capacity may be left out of a PATCH, but not cleared: every event
        # has a capacity. update_event uses model_dump(exclude_unset=True), so
        # without this an explicit null would reach the database.
        if "capacity" in self.model_fields_set and self.capacity is None:
            raise ValueError("capacity cannot be empty")
        if "slug" in self.model_fields_set and self.slug is None:
            raise ValueError("slug cannot be empty")
        if self.start_datetime and self.end_datetime:
            if self.end_datetime <= self.start_datetime:
                raise ValueError("end_datetime must be after start_datetime")
        if self.is_free is True:
            self.ticket_price = None
        # Blank branding fields mean "none".
        for name in ("brand_logo_url", "brand_logo_dark_url"):
            value = getattr(self, name)
            if value is not None and not value.strip():
                setattr(self, name, None)
        return self
