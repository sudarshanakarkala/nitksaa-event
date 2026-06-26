from datetime import datetime
from typing import Optional
from pydantic import BaseModel, field_validator


VALID_SPONSOR_TYPES = {
    "TITLE_SPONSOR", "GOLD_SPONSOR", "SILVER_SPONSOR",
    "BRONZE_SPONSOR", "ASSOCIATE_SPONSOR",
}

VALID_PARTNER_TYPES = {
    "COMMUNITY_PARTNER", "KNOWLEDGE_PARTNER", "MEDIA_PARTNER",
    "VENUE_PARTNER", "TECHNOLOGY_PARTNER",
    "ECOSYSTEM_PARTNER", "HIRING_PARTNER",
}


class SponsorCreate(BaseModel):
    sponsor_type: str
    name: str
    logo_url: Optional[str] = None
    website_url: Optional[str] = None
    description: Optional[str] = None
    display_order: int = 0
    is_visible: bool = True

    @field_validator("sponsor_type")
    @classmethod
    def validate_type(cls, v: str) -> str:
        v = v.upper()
        if v not in VALID_SPONSOR_TYPES:
            raise ValueError(f"sponsor_type must be one of: {', '.join(sorted(VALID_SPONSOR_TYPES))}")
        return v


class SponsorUpdate(BaseModel):
    sponsor_type: Optional[str] = None
    name: Optional[str] = None
    logo_url: Optional[str] = None
    website_url: Optional[str] = None
    description: Optional[str] = None
    display_order: Optional[int] = None
    is_visible: Optional[bool] = None

    @field_validator("sponsor_type")
    @classmethod
    def validate_type(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        v = v.upper()
        if v not in VALID_SPONSOR_TYPES:
            raise ValueError(f"sponsor_type must be one of: {', '.join(sorted(VALID_SPONSOR_TYPES))}")
        return v


class SponsorResponse(BaseModel):
    sponsor_id: int
    event_id: int
    sponsor_type: str
    name: str
    logo_url: Optional[str] = None
    website_url: Optional[str] = None
    description: Optional[str] = None
    display_order: int
    is_visible: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class PartnerCreate(BaseModel):
    partner_type: str
    name: str
    logo_url: Optional[str] = None
    website_url: Optional[str] = None
    description: Optional[str] = None
    display_order: int = 0
    is_visible: bool = True

    @field_validator("partner_type")
    @classmethod
    def validate_type(cls, v: str) -> str:
        v = v.upper()
        if v not in VALID_PARTNER_TYPES:
            raise ValueError(f"partner_type must be one of: {', '.join(sorted(VALID_PARTNER_TYPES))}")
        return v


class PartnerUpdate(BaseModel):
    partner_type: Optional[str] = None
    name: Optional[str] = None
    logo_url: Optional[str] = None
    website_url: Optional[str] = None
    description: Optional[str] = None
    display_order: Optional[int] = None
    is_visible: Optional[bool] = None

    @field_validator("partner_type")
    @classmethod
    def validate_type(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        v = v.upper()
        if v not in VALID_PARTNER_TYPES:
            raise ValueError(f"partner_type must be one of: {', '.join(sorted(VALID_PARTNER_TYPES))}")
        return v


class PartnerResponse(BaseModel):
    partner_id: int
    event_id: int
    partner_type: str
    name: str
    logo_url: Optional[str] = None
    website_url: Optional[str] = None
    description: Optional[str] = None
    display_order: int
    is_visible: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


