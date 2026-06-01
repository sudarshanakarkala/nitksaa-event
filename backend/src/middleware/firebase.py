"""
Firebase token verification and JWT utilities.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import firebase_admin
from firebase_admin import auth as fb_auth, credentials
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from config.tenant_config import TenantConfig

TOKEN_EXPIRY_HOURS = 8
ALGORITHM = "HS256"

_firebase_apps: dict[str, firebase_admin.App] = {}
_bearer = HTTPBearer()


def _get_firebase_app(firebase_project: str) -> firebase_admin.App:
    if firebase_project in _firebase_apps:
        return _firebase_apps[firebase_project]
    app = firebase_admin.initialize_app(
        credential=credentials.ApplicationDefault(),
        name=firebase_project,
        options={"projectId": firebase_project},
    )
    _firebase_apps[firebase_project] = app
    return app


def verify_firebase_token(id_token: str, tenant: TenantConfig) -> dict:
    """Verify a Firebase ID token. Returns decoded claims or raises HTTPException."""
    app = _get_firebase_app(tenant.firebase_project)
    try:
        return fb_auth.verify_id_token(id_token, app=app)
    except fb_auth.ExpiredIdTokenError:
        raise HTTPException(status_code=401, detail="Firebase token expired")
    except fb_auth.InvalidIdTokenError:
        raise HTTPException(status_code=401, detail="Invalid Firebase token")
    except Exception as exc:
        raise HTTPException(status_code=401, detail=f"Token verification failed: {exc}")


def make_jwt(payload: dict, secret_key: str) -> str:
    """Issue a signed JWT with 8-hour expiry."""
    data = {
        **payload,
        "exp": datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRY_HOURS),
    }
    return jwt.encode(data, secret_key, algorithm=ALGORITHM)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> dict:
    """
    FastAPI dependency. Decodes our JWT on every request. No Firebase call.

    Role flags (is_admin, is_content_editor, is_innovation_reviewer) are read
    from the live DB on every request so changes take effect without re-login.

    Returns:
        {
            "firebase_uid": str,
            "email": str,
            "user_type": str,
            "ref_id": str | None,
            "is_admin": bool,
            "is_content_editor": bool,
            "is_innovation_reviewer": bool,
            "is_giving_reviewer": bool,
            "is_community_admin": bool,
        }
    """
    from config.settings import settings
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.secret_key,
            algorithms=[ALGORITHM],
        )
        firebase_uid = payload.get("firebase_uid")
        user_type = payload.get("user_type")
        if not firebase_uid or not user_type:
            raise HTTPException(status_code=401, detail="Invalid token")

        # Single DB call: suspension check + live role flags
        from services.db import get_db
        is_content_editor      = False
        is_innovation_reviewer = False
        is_giving_reviewer     = False
        is_community_admin     = False
        fullname               = None
        try:
            with get_db() as cur:
                cur.execute(
                    """
                    SELECT status, is_content_editor, is_innovation_reviewer, is_giving_reviewer,
                           is_community_admin, fullname
                    FROM website_users
                    WHERE firebase_uid = %s
                    """,
                    [firebase_uid],
                )
                row = cur.fetchone()
            if row:
                if row["status"] == "suspended":
                    raise HTTPException(status_code=403, detail="Account suspended")
                is_content_editor      = bool(row["is_content_editor"])
                is_innovation_reviewer = bool(row["is_innovation_reviewer"])
                is_giving_reviewer     = bool(row["is_giving_reviewer"])
                is_community_admin     = bool(row["is_community_admin"])
                fullname               = row["fullname"]
        except HTTPException:
            raise
        except Exception:
            pass  # DB check failed — fail open, don't lock out users over infra issues

        return {
            "firebase_uid":           firebase_uid,
            "email":                  payload.get("sub"),
            "fullname":               fullname,
            "user_type":              user_type,
            "ref_id":                 payload.get("ref_id"),
            "is_admin":               bool(payload.get("is_admin", False)),
            "is_content_editor":      is_content_editor,
            "is_innovation_reviewer": is_innovation_reviewer,
            "is_giving_reviewer":     is_giving_reviewer,
            "is_community_admin":     is_community_admin,
        }
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


def require_user_type(*allowed_types: str):
    """Dependency factory for user type enforcement."""
    async def checker(user: dict = Depends(get_current_user)) -> dict:
        if user["user_type"] not in allowed_types:
            raise HTTPException(
                status_code=403,
                detail=f"Access denied. Required: {' or '.join(allowed_types)}",
            )
        return user
    return checker


def require_alumni(user: dict) -> None:
    """Raises 403 if the user is not a verified alumni. Call inline at the top of a handler."""
    if user.get("user_type") != "alumni":
        raise HTTPException(
            status_code=403,
            detail="This action is available to verified alumni only",
        )
