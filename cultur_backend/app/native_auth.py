from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .backend_models import AppUser, NativeSession
from .config import Settings

_PBKDF2_ITERATIONS = 600_000


def utc_now() -> datetime:
    return datetime.now(tz=UTC)


class NativeAuthError(RuntimeError):
    pass


class NativeAuthService:
    def __init__(self, settings: Settings, db: Session) -> None:
        self._settings = settings
        self._db = db

    def register(
        self,
        *,
        username: str,
        password: str,
        display_name: str | None = None,
    ) -> tuple[AppUser, str, str]:
        self._cleanup_expired_sessions()
        user = self._db.scalar(select(AppUser).where(AppUser.username == username))
        if user is not None and user.password_hash:
            raise NativeAuthError("That username is already in use.")

        if user is None:
            user = AppUser(
                username=username,
                display_name=display_name,
                password_hash=_hash_password(password),
            )
            self._db.add(user)
            self._db.flush()
        else:
            user.display_name = display_name or user.display_name
            user.password_hash = _hash_password(password)
            self._db.flush()

        access_token, refresh_token = self._create_session(user)
        self._db.commit()
        self._db.refresh(user)
        return user, access_token, refresh_token

    def login(self, *, username: str, password: str) -> tuple[AppUser, str, str]:
        self._cleanup_expired_sessions()
        user = self._db.scalar(select(AppUser).where(AppUser.username == username))
        if user is None or not user.password_hash:
            raise NativeAuthError("Invalid username or password.")
        if not _verify_password(password, user.password_hash):
            raise NativeAuthError("Invalid username or password.")

        access_token, refresh_token = self._create_session(user)
        self._db.commit()
        self._db.refresh(user)
        return user, access_token, refresh_token

    def refresh(self, refresh_token: str) -> tuple[AppUser, str, str] | None:
        self._cleanup_expired_sessions()
        token_hash = _hash_token(refresh_token)
        session = self._db.scalar(
            select(NativeSession).where(NativeSession.refresh_token_hash == token_hash),
        )
        if session is None or _normalize_dt(session.refresh_expires_at) <= utc_now():
            return None

        access_token = secrets.token_urlsafe(32)
        new_refresh_token = secrets.token_urlsafe(48)
        session.access_token_hash = _hash_token(access_token)
        session.refresh_token_hash = _hash_token(new_refresh_token)
        session.access_expires_at = utc_now() + timedelta(
            seconds=self._settings.access_token_ttl_seconds,
        )
        session.refresh_expires_at = utc_now() + timedelta(
            seconds=self._settings.refresh_token_ttl_seconds,
        )
        self._db.commit()
        self._db.refresh(session)
        self._db.refresh(session.user)
        return session.user, access_token, new_refresh_token

    def revoke_access_token(self, access_token: str) -> bool:
        self._cleanup_expired_sessions()
        token_hash = _hash_token(access_token)
        session = self._db.scalar(
            select(NativeSession).where(NativeSession.access_token_hash == token_hash),
        )
        if session is None:
            return False
        self._db.delete(session)
        self._db.commit()
        return True

    def get_user_by_access_token(self, access_token: str) -> AppUser | None:
        self._cleanup_expired_sessions()
        token_hash = _hash_token(access_token)
        session = self._db.scalar(
            select(NativeSession).where(NativeSession.access_token_hash == token_hash),
        )
        if session is None or _normalize_dt(session.access_expires_at) <= utc_now():
            return None
        self._db.refresh(session.user)
        return session.user

    def _create_session(self, user: AppUser) -> tuple[str, str]:
        access_token = secrets.token_urlsafe(32)
        refresh_token = secrets.token_urlsafe(48)
        session = NativeSession(
            user_id=user.id,
            access_token_hash=_hash_token(access_token),
            refresh_token_hash=_hash_token(refresh_token),
            access_expires_at=utc_now()
            + timedelta(seconds=self._settings.access_token_ttl_seconds),
            refresh_expires_at=utc_now()
            + timedelta(seconds=self._settings.refresh_token_ttl_seconds),
        )
        self._db.add(session)
        self._db.flush()
        return access_token, refresh_token

    def _cleanup_expired_sessions(self) -> None:
        self._db.execute(
            delete(NativeSession).where(NativeSession.refresh_expires_at <= utc_now()),
        )
        self._db.flush()


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    derived = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        _PBKDF2_ITERATIONS,
    )
    return "pbkdf2_sha256${iterations}${salt}${hash}".format(
        iterations=_PBKDF2_ITERATIONS,
        salt=base64.urlsafe_b64encode(salt).decode("utf-8"),
        hash=base64.urlsafe_b64encode(derived).decode("utf-8"),
    )


def _verify_password(password: str, password_hash: str) -> bool:
    try:
        algorithm, iterations_text, salt_b64, hash_b64 = password_hash.split("$", 3)
    except ValueError as exc:
        raise NativeAuthError("Stored password hash has an invalid format.") from exc

    if algorithm != "pbkdf2_sha256":
        raise NativeAuthError("Unsupported password hashing algorithm.")

    expected = base64.urlsafe_b64decode(hash_b64.encode("utf-8"))
    salt = base64.urlsafe_b64decode(salt_b64.encode("utf-8"))
    derived = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        int(iterations_text),
    )
    return hmac.compare_digest(derived, expected)


def _normalize_dt(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)
