"""POST /api/v1/nitika/chat — the attendee app's NITiKa panel.

The app can't call NITiKa itself: NITiKa is IAM-only, needs a client key
that must stay server-side, and believes whatever user and role its caller
sends. This route signs the user in the usual way, works out their admin
scope from the role tables, and forwards the message (app.services.
nitika_service). The answer, or NITiKa's error, goes back unchanged.
"""
from typing import Any, Dict, List, Literal, Optional

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app.config import get_settings
from app.middleware.auth import get_current_user
from app.services import nitika_service

router = APIRouter(prefix="/api/v1/nitika", tags=["nitika"])


class ChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    text: str


class ChatContext(BaseModel):
    page: Optional[str] = None
    event_id: Optional[int] = None


class ChatRequest(BaseModel):
    """What the app sends. Lengths are checked by NITiKa; any other field
    (a `user`, a role) is ignored, never forwarded."""

    message: str
    history: List[ChatTurn] = Field(default_factory=list)
    locale: str = "en-IN"
    context: ChatContext = Field(default_factory=ChatContext)


@router.post("/chat")
async def chat(
    body: ChatRequest,
    user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    if not get_settings().nitika_configured:
        return JSONResponse(
            status_code=404,
            content=nitika_service.error_body(
                "not_configured", "NITiKa isn't available right now."
            ),
        )

    scope = await nitika_service.resolve_admin_scope(user["firebase_uid"])
    payload = {
        "user": nitika_service.nitika_user(user, scope),
        **body.model_dump(exclude_none=True),
    }
    status, data = await nitika_service.chat(payload)
    return JSONResponse(status_code=status, content=data)
