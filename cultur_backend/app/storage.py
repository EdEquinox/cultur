from __future__ import annotations

import hashlib
import json
import secrets
import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from cryptography.fernet import Fernet

from .config import Settings
from .schemas import SessionBundle, SessionRecord


def utc_now() -> datetime:
    return datetime.now(tz=UTC)


class SessionStore:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._path = Path(settings.session_store_path)
        self._fernet = Fernet(settings.fernet_key)
        self._lock = threading.Lock()
        self._path.parent.mkdir(parents=True, exist_ok=True)
        if not self._path.exists():
            self._path.write_text(json.dumps({"sessions": []}, indent=2), encoding="utf-8")

    def create_session(
        self,
        *,
        username: str,
        yamtrack_base_url: str,
        cookies: dict[str, str],
        csrf_token: str | None,
        password: str | None,
        remember_credentials: bool,
    ) -> SessionBundle:
        access_token = secrets.token_urlsafe(32)
        refresh_token = secrets.token_urlsafe(48)
        now = utc_now()
        record = SessionRecord(
            sessionId=secrets.token_urlsafe(16),
            username=username,
            yamtrackBaseUrl=yamtrack_base_url,
            accessTokenHash=self._hash_token(access_token),
            refreshTokenHash=self._hash_token(refresh_token),
            accessExpiresAt=self._serialize_dt(
                now + timedelta(seconds=self._settings.access_token_ttl_seconds),
            ),
            refreshExpiresAt=self._serialize_dt(
                now + timedelta(seconds=self._settings.refresh_token_ttl_seconds),
            ),
            createdAt=self._serialize_dt(now),
            updatedAt=self._serialize_dt(now),
            encryptedCookies=self._encrypt_json(cookies),
            encryptedCsrfToken=self._encrypt_text(csrf_token) if csrf_token else None,
            encryptedPassword=self._encrypt_text(password)
            if remember_credentials and password
            else None,
            rememberCredentials=remember_credentials,
            lastReloginAt=None,
        )
        with self._lock:
            payload = self._load_payload()
            self._cleanup(payload)
            payload["sessions"].append(record.model_dump())
            self._save_payload(payload)
        return SessionBundle(
            access_token=access_token,
            refresh_token=refresh_token,
            record=record,
        )

    def get_by_access_token(self, access_token: str) -> SessionRecord | None:
        return self._get_by_token(access_token, "accessTokenHash", "accessExpiresAt")

    def get_by_refresh_token(self, refresh_token: str) -> SessionRecord | None:
        return self._get_by_token(refresh_token, "refreshTokenHash", "refreshExpiresAt")

    def rotate_tokens(self, session_id: str) -> tuple[SessionRecord, str, str]:
        access_token = secrets.token_urlsafe(32)
        refresh_token = secrets.token_urlsafe(48)
        with self._lock:
            payload = self._load_payload()
            self._cleanup(payload)
            sessions = payload["sessions"]
            for index, raw in enumerate(sessions):
                if raw["sessionId"] != session_id:
                    continue
                updated = SessionRecord.model_validate(raw).model_copy(
                    update={
                        "accessTokenHash": self._hash_token(access_token),
                        "refreshTokenHash": self._hash_token(refresh_token),
                        "accessExpiresAt": self._serialize_dt(
                            utc_now()
                            + timedelta(seconds=self._settings.access_token_ttl_seconds),
                        ),
                        "refreshExpiresAt": self._serialize_dt(
                            utc_now()
                            + timedelta(seconds=self._settings.refresh_token_ttl_seconds),
                        ),
                        "updatedAt": self._serialize_dt(utc_now()),
                    },
                )
                sessions[index] = updated.model_dump()
                self._save_payload(payload)
                return updated, access_token, refresh_token
        raise KeyError(f"Session {session_id} not found.")

    def persist_upstream_state(
        self,
        session_id: str,
        *,
        cookies: dict[str, str],
        csrf_token: str | None,
        password: str | None = None,
        remember_credentials: bool | None = None,
        relogin: bool = False,
    ) -> SessionRecord:
        with self._lock:
            payload = self._load_payload()
            self._cleanup(payload)
            sessions = payload["sessions"]
            for index, raw in enumerate(sessions):
                if raw["sessionId"] != session_id:
                    continue
                existing = SessionRecord.model_validate(raw)
                update_map: dict[str, Any] = {
                    "encryptedCookies": self._encrypt_json(cookies),
                    "encryptedCsrfToken": self._encrypt_text(csrf_token)
                    if csrf_token
                    else None,
                    "updatedAt": self._serialize_dt(utc_now()),
                }
                if remember_credentials is not None:
                    update_map["rememberCredentials"] = remember_credentials
                if password is not None:
                    update_map["encryptedPassword"] = self._encrypt_text(password)
                elif remember_credentials is False:
                    update_map["encryptedPassword"] = None
                if relogin:
                    update_map["lastReloginAt"] = self._serialize_dt(utc_now())
                updated = existing.model_copy(update=update_map)
                sessions[index] = updated.model_dump()
                self._save_payload(payload)
                return updated
        raise KeyError(f"Session {session_id} not found.")

    def revoke(self, session_id: str) -> None:
        with self._lock:
            payload = self._load_payload()
            before = len(payload["sessions"])
            payload["sessions"] = [
                session for session in payload["sessions"] if session["sessionId"] != session_id
            ]
            if len(payload["sessions"]) != before:
                self._save_payload(payload)

    def decrypt_cookies(self, record: SessionRecord) -> dict[str, str]:
        return json.loads(self._decrypt_text(record.encryptedCookies))

    def decrypt_csrf_token(self, record: SessionRecord) -> str | None:
        if not record.encryptedCsrfToken:
            return None
        return self._decrypt_text(record.encryptedCsrfToken)

    def decrypt_password(self, record: SessionRecord) -> str | None:
        if not record.encryptedPassword:
            return None
        return self._decrypt_text(record.encryptedPassword)

    def _get_by_token(
        self,
        token: str,
        hash_field: str,
        expires_field: str,
    ) -> SessionRecord | None:
        hashed = self._hash_token(token)
        with self._lock:
            payload = self._load_payload()
            changed = self._cleanup(payload)
            if changed:
                self._save_payload(payload)
            for raw in payload["sessions"]:
                if raw[hash_field] != hashed:
                    continue
                record = SessionRecord.model_validate(raw)
                expiry = self._parse_dt(getattr(record, expires_field))
                if expiry <= utc_now():
                    return None
                return record
        return None

    def _load_payload(self) -> dict[str, list[dict[str, Any]]]:
        raw = self._path.read_text(encoding="utf-8")
        payload = json.loads(raw)
        payload.setdefault("sessions", [])
        return payload

    def _save_payload(self, payload: dict[str, Any]) -> None:
        self._path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    def _cleanup(self, payload: dict[str, Any]) -> bool:
        now = utc_now()
        original = len(payload["sessions"])
        payload["sessions"] = [
            session
            for session in payload["sessions"]
            if self._parse_dt(session["refreshExpiresAt"]) > now
        ]
        return len(payload["sessions"]) != original

    def _hash_token(self, token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    def _encrypt_text(self, value: str) -> str:
        return self._fernet.encrypt(value.encode("utf-8")).decode("utf-8")

    def _encrypt_json(self, value: dict[str, Any]) -> str:
        return self._encrypt_text(json.dumps(value))

    def _decrypt_text(self, value: str) -> str:
        return self._fernet.decrypt(value.encode("utf-8")).decode("utf-8")

    def _serialize_dt(self, value: datetime) -> str:
        return value.astimezone(UTC).isoformat()

    def _parse_dt(self, value: str) -> datetime:
        return datetime.fromisoformat(value)
