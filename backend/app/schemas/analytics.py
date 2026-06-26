from datetime import datetime
from typing import Any, Dict, Optional
from pydantic import BaseModel


VALID_ACTION_TYPES = {
    "EVENT_VIEWED", "EVENT_DETAIL_OPENED",
    "REGISTER_CLICKED", "REGISTRATION_COMPLETED", "REGISTRATION_FAILED",
    "JOIN_LINK_CLICKED", "MAP_CLICKED", "CALENDAR_CLICKED",
    "EMAIL_SENT", "EMAIL_FAILED", "EVENT_SHARED",
}

VALID_SOURCE_APPS = {"FLUTTER", "ADMIN", "BACKEND", "EMAIL", "SYSTEM"}


class ActivityLogResponse(BaseModel):
    activity_id: int
    event_id: Optional[int] = None
    firebase_uid: Optional[str] = None
    action_type: str
    source_app: str
    metadata: Dict[str, Any]
    created_at: datetime

    class Config:
        from_attributes = True
