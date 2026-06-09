from pydantic import BaseModel
from typing import Literal


class EventStatusUpdate(BaseModel):
    status: Literal["draft", "published", "cancelled", "completed"]
