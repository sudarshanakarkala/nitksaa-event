"""
Dev-only auth placeholder. Only active when APP_ENV=development.
In production this will be replaced with Firebase JWT verification.

Header usage:
  X-Dev-User: admin     → is_admin=True, full permissions
  X-Dev-User: attendee  → is_admin=False, event:register only
"""
from typing import Optional, Dict, Any
from fastapi import HTTPException, Header
from app.config import get_settings

_DEV_USERS: Dict[str, Dict[str, Any]] = {
    "admin": {
        "firebase_uid": "dev-admin-firebase-uid",
        "ref_id": "ALUMNI-DEV-ADMIN",
        "email": "admin@example.com",
        "user_type": "alumni",
        "is_admin": True,
        "permissions": ["event:create", "event:update", "event:checkin", "event:export"],
    },
    "attendee": {
        "firebase_uid": "dev-attendee-firebase-uid",
        "ref_id": "ALUMNI-DEV-001",
        "email": "attendee@example.com",
        "user_type": "alumni",
        "is_admin": False,
        "permissions": ["event:register"],
    },
}


def _assert_dev_mode() -> None:
    if get_settings().app_env != "development":
        raise HTTPException(
            status_code=500,
            detail="dev_auth_not_available_in_production",
        )


async def get_current_user(
    x_dev_user: Optional[str] = Header(default=None),
) -> Dict[str, Any]:
    _assert_dev_mode()
    if not x_dev_user or x_dev_user.lower() not in _DEV_USERS:
        raise HTTPException(
            status_code=401,
            detail="missing_or_invalid_x_dev_user_header",
        )
    return _DEV_USERS[x_dev_user.lower()]


async def get_admin_user(
    x_dev_user: Optional[str] = Header(default=None),
) -> Dict[str, Any]:
    user = await get_current_user(x_dev_user)
    if not user.get("is_admin"):
        raise HTTPException(status_code=403, detail="admin_required")
    return user


async def get_optional_user(
    x_dev_user: Optional[str] = Header(default=None),
) -> Optional[Dict[str, Any]]:
    """Returns user if header present, None otherwise (for public endpoints)."""
    if not x_dev_user:
        return None
    _assert_dev_mode()
    return _DEV_USERS.get(x_dev_user.lower())
