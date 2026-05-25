from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy.orm import Session

from ...config import Settings
from ...native_auth import NativeAuthError, NativeAuthService
from ...schemas import (
    AuthResponse,
    LoginRequest,
    MeResponse,
    RefreshRequest,
    RegisterRequest,
)
from ...serializers.auth import build_native_auth_response, native_session_expiry
from ...validation import optional_text, require_text
from ..dependencies import get_db, get_settings, token_from_auth_header

router = APIRouter()


@router.post("/auth/register", response_model=AuthResponse)
def register(
    payload: RegisterRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> AuthResponse:
    auth_service = NativeAuthService(settings, db)
    try:
        user, access_token, refresh_token = auth_service.register(
            username=require_text(payload.username, "username"),
            password=require_text(payload.password, "password"),
            display_name=optional_text(payload.displayName),
        )
    except NativeAuthError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    return build_native_auth_response(
        user,
        access_token=access_token,
        refresh_token=refresh_token,
        settings=settings,
    )


@router.post("/auth/login", response_model=AuthResponse)
def login(
    payload: LoginRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> AuthResponse:
    auth_service = NativeAuthService(settings, db)
    try:
        user, access_token, refresh_token = auth_service.login(
            username=require_text(payload.username, "username"),
            password=require_text(payload.password, "password"),
        )
    except NativeAuthError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    return build_native_auth_response(
        user,
        access_token=access_token,
        refresh_token=refresh_token,
        settings=settings,
    )


@router.post("/auth/refresh", response_model=AuthResponse)
def refresh(
    payload: RefreshRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> AuthResponse:
    native_auth_service = NativeAuthService(settings, db)
    native_refreshed = native_auth_service.refresh(payload.refreshToken)
    if native_refreshed is None:
        raise HTTPException(status_code=401, detail="Missing or expired refresh token.")
    user, access_token, refresh_token = native_refreshed
    return build_native_auth_response(
        user,
        access_token=access_token,
        refresh_token=refresh_token,
        settings=settings,
    )


@router.post("/auth/logout")
def logout(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> dict[str, bool]:
    token = token_from_auth_header(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Missing or expired session token.")
    native_auth_service = NativeAuthService(settings, db)
    if not native_auth_service.revoke_access_token(token):
        raise HTTPException(status_code=401, detail="Missing or expired session token.")
    return {"ok": True}


@router.get("/me", response_model=MeResponse)
def me(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MeResponse:
    token = token_from_auth_header(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Missing or expired session token.")
    native_auth_service = NativeAuthService(settings, db)
    native_user = native_auth_service.get_user_by_access_token(token)
    if native_user is None:
        raise HTTPException(status_code=401, detail="Missing or expired session token.")
    return MeResponse(
        username=native_user.username,
        displayName=native_user.display_name,
        sessionExpiresAt=native_session_expiry(settings),
    )
