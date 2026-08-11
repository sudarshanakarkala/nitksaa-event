"""Session schemas for the admin event-management surface.

EventCreate/EventUpdate/EventResponse used to live here too, targeting
columns from a superseded schema migration (001_create_events_alpha_schema.sql)
that don't exist on the real `events` table. They were retired in the
admin-event-schema-alignment sprint — app/api/admin_events.py now uses
app.schemas.event_create.EventCreate / event_update.EventUpdate /
event_response.EventResponse, the same already-correct schemas
app/api/events.py has always used.

Session* below is fixed in place rather than retired: the `sessions`
table (migration 002) has no equivalent elsewhere. Public field names
(location, track_name, starts_at, ends_at) are kept stable for API
compatibility; app/repositories/events_repository.py maps them to the
real columns (location_text, track, start_datetime, end_datetime).
capacity/status were dropped — sessions has no such columns, and no
current requirement justifies adding them.
"""
from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from datetime import datetime


class SessionCreate(BaseModel):
    title: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = None
    speaker_name: Optional[str] = None
    location: Optional[str] = None
    track_name: Optional[str] = None
    starts_at: datetime
    ends_at: datetime
    sort_order: int = 0


class SessionResponse(BaseModel):
    """Public field names (location/track_name/starts_at/ends_at) are kept
    stable via validation_alias, reading directly from the real sessions
    columns (location_text/track/start_datetime/end_datetime) the
    repository layer returns — JSON output still uses the public names
    (FastAPI serializes by field name, not alias, by default)."""

    model_config = ConfigDict(populate_by_name=True)

    session_id: int
    event_id: int
    title: str
    description: Optional[str] = None
    speaker_name: Optional[str] = None
    location: Optional[str] = Field(default=None, validation_alias="location_text")
    track_name: Optional[str] = Field(default=None, validation_alias="track")
    starts_at: datetime = Field(validation_alias="start_datetime")
    ends_at: datetime = Field(validation_alias="end_datetime")
    sort_order: int
    created_at: datetime
