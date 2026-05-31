"""Event-app JWT auth helpers."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.database import get_pool

ALGORITHM = "HS256"

_bearer = HTTPBearer()
_firebase_apps: dict[str, Any] = {}


def _get_firebase_app(project_id: str) -> Any:
    try:
        import firebase_admin
        from firebase_admin import credentials
    except ImportError as exc:
        raise HTTPException(status_code=500, detail="firebase_admin_not_installed") from exc

    if project_id in _firebase_apps:
        return _firebase_apps[project_id]

    app = firebase_admin.initialize_app(
        credential=credentials.ApplicationDefault(),
        name=project_id,
        options={"projectId": project_id},
    )
    _firebase_apps[project_id] = app
    return app


def verify_firebase_token(id_token: str) -> Dict[str, Any]:
    settings = get_settings()
    try:
        from firebase_admin import auth as fb_auth
        from google.auth.exceptions import DefaultCredentialsError
    except ImportError as exc:
        raise HTTPException(status_code=500, detail="firebase_admin_not_installed") from exc

    try:
        app = _get_firebase_app(settings.firebase_project_id)
        return fb_auth.verify_id_token(id_token, app=app)
    except fb_auth.ExpiredIdTokenError as exc:
        raise HTTPException(status_code=401, detail="firebase_token_expired") from exc
    except fb_auth.RevokedIdTokenError as exc:
        raise HTTPException(status_code=401, detail="invalid_firebase_token") from exc
    except fb_auth.InvalidIdTokenError as exc:
        raise HTTPException(status_code=401, detail="invalid_firebase_token") from exc
    except fb_auth.CertificateFetchError as exc:
        raise HTTPException(status_code=401, detail="invalid_firebase_token") from exc
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="invalid_firebase_token") from exc
    except DefaultCredentialsError as exc:
        raise HTTPException(status_code=401, detail="invalid_firebase_token") from exc
    except Exception as exc:
        raise HTTPException(status_code=401, detail="invalid_firebase_token") from exc


def make_access_token(payload: Dict[str, Any]) -> str:
    try:
        from jose import jwt
    except ImportError as exc:
        raise HTTPException(status_code=500, detail="python_jose_not_installed") from exc

    settings = get_settings()
    data = {
        **payload,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes),
    }
    return jwt.encode(data, settings.secret_key, algorithm=ALGORITHM)


def decode_access_token(token: str) -> Dict[str, Any]:
    try:
        from jose import JWTError, jwt
    except ImportError as exc:
        raise HTTPException(status_code=500, detail="python_jose_not_installed") from exc

    try:
        payload = jwt.decode(
            token,
            get_settings().secret_key,
            algorithms=[ALGORITHM],
        )
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="invalid_or_expired_token") from exc

    firebase_uid = payload.get("firebase_uid")
    user_type = payload.get("user_type")
    if not firebase_uid or not user_type:
        raise HTTPException(status_code=401, detail="invalid_token")
    return payload


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> Dict[str, Any]:
    payload = decode_access_token(credentials.credentials)
    user = await _fetch_event_user(payload["firebase_uid"])
    if user:
        if user["is_suspended"]:
            raise HTTPException(status_code=403, detail="account_suspended")
        payload.update(
            {
                "email": user["email"],
                "fullname": user["fullname"],
                "user_type": user["user_type"],
                "ref_id": user["ref_id"],
                "graduation_year": user["graduation_year"],
            }
        )
    return {
        "firebase_uid": payload["firebase_uid"],
        "email": payload.get("email"),
        "fullname": payload.get("fullname"),
        "user_type": payload["user_type"],
        "ref_id": payload.get("ref_id"),
        "graduation_year": payload.get("graduation_year"),
    }


async def _fetch_event_user(firebase_uid: str) -> Optional[Dict[str, Any]]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT firebase_uid, email, fullname, user_type, ref_id,
                   graduation_year, is_suspended
            FROM event_users
            WHERE firebase_uid = $1
            """,
            firebase_uid,
        )
    return dict(row) if row else None
