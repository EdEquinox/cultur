from __future__ import annotations

from datetime import timedelta

from ..backend_models import AppUser
from ..config import Settings
from ..native_auth import utc_now as native_utc_now
from ..schemas import AuthResponse


def native_session_expiry(settings: Settings) -> str:
    return (
        native_utc_now() + timedelta(seconds=settings.access_token_ttl_seconds)
    ).replace(microsecond=0).isoformat()


def build_native_auth_response(
    user: AppUser,
    *,
    access_token: str,
    refresh_token: str,
    settings: Settings,
) -> AuthResponse:
    return AuthResponse(
        sessionToken=access_token,
        refreshToken=refresh_token,
        username=user.username,
        displayName=user.display_name,
        sessionExpiresAt=native_session_expiry(settings),
    )
