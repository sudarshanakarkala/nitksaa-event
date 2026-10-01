"""Firebase login exchange and internal auth verification endpoints."""
import logging
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.database import get_pool
from app.middleware.auth import get_current_user, make_access_token, verify_firebase_token
from app.services.alumni_service import find_alumni_by_email

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])
logger = logging.getLogger(__name__)


class FirebaseLoginRequest(BaseModel):
    token: str = Field(..., min_length=1)


class AuthResponse(BaseModel):
    status: str
    access_token: str
    token_type: str
    firebase_uid: str
    user_type: str
    fullname: str
    ref_id: Optional[str]
    graduation_year: Optional[int]


class CurrentUserResponse(BaseModel):
    firebase_uid: str
    email: Optional[str]
    fullname: Optional[str]
    user_type: str
    ref_id: Optional[str]
    graduation_year: Optional[int]


@router.post("/firebase", response_model=AuthResponse)
async def firebase_login(body: FirebaseLoginRequest):
    claims = verify_firebase_token(body.token)
    firebase_uid = claims.get("uid")
    email = claims.get("email")
    if not firebase_uid:
        raise HTTPException(status_code=400, detail="firebase_uid_missing")
    if not email:
        raise HTTPException(status_code=400, detail="email_missing")
    if claims.get("email_verified") is not True:
        raise HTTPException(status_code=403, detail="email_not_verified")

    fullname = claims.get("name") or claims.get("display_name") or email
    try:
        alumni = await find_alumni_by_email(email)
    except Exception:
        logger.warning(
            "Alumni lookup failed; continuing Firebase login as non-alumni user.",
            exc_info=True,
        )
        alumni = None

    if alumni:
        user_type = "alumni"
        ref_id = alumni["alumni_id"]
        graduation_year = alumni["graduationyear"]
        fullname = alumni.get("fullname") or fullname
    else:
        user_type = "other"
        ref_id = None
        graduation_year = None

    user = await _upsert_event_user(
        firebase_uid=firebase_uid,
        email=email,
        fullname=fullname,
        user_type=user_type,
        ref_id=ref_id,
        graduation_year=graduation_year,
    )
    if user["is_suspended"]:
        raise HTTPException(status_code=403, detail="account_suspended")

    token_payload = {
        "firebase_uid": user["firebase_uid"],
        "sub": user["email"],
        "email": user["email"],
        "fullname": user["fullname"],
        "user_type": user["user_type"],
        "ref_id": user["ref_id"],
        "graduation_year": user["graduation_year"],
    }
    access_token = make_access_token(token_payload)

    return {
        "status": "ok",
        "access_token": access_token,
        "token_type": "bearer",
        "firebase_uid": user["firebase_uid"],
        "user_type": user["user_type"],
        "fullname": user["fullname"],
        "ref_id": user["ref_id"],
        "graduation_year": user["graduation_year"],
    }


@router.get("/me", response_model=CurrentUserResponse)
async def read_me(user: Dict[str, Any] = Depends(get_current_user)):
    return user


async def _upsert_event_user(
    *,
    firebase_uid: str,
    email: str,
    fullname: str,
    user_type: str,
    ref_id: Optional[str],
    graduation_year: Optional[int],
) -> Dict[str, Any]:
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            INSERT INTO event_users (
                firebase_uid, email, fullname, user_type, ref_id,
                graduation_year, last_login
            )
            VALUES ($1, $2, $3, $4, $5, $6, now())
            ON CONFLICT (firebase_uid) DO UPDATE
            SET email = EXCLUDED.email,
                fullname = EXCLUDED.fullname,
                last_login = now(),
                user_type = CASE WHEN EXCLUDED.user_type = 'alumni' THEN EXCLUDED.user_type ELSE event_users.user_type END,
                ref_id = CASE WHEN EXCLUDED.user_type = 'alumni' THEN EXCLUDED.ref_id ELSE event_users.ref_id END,
                graduation_year = CASE WHEN EXCLUDED.user_type = 'alumni' THEN EXCLUDED.graduation_year ELSE event_users.graduation_year END
            RETURNING firebase_uid, email, fullname, user_type, ref_id,
                      graduation_year, is_suspended
            """,
            firebase_uid,
            email,
            fullname,
            user_type,
            ref_id,
            graduation_year,
        )
    return dict(row)
