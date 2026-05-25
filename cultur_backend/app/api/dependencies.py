from __future__ import annotations

from collections.abc import Iterator

from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session

from ..config import Settings
from ..schemas import SessionRecord
from ..database import DatabaseManager
from ..storage import SessionStore


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_store(request: Request) -> SessionStore:
    return request.app.state.store


def get_database_manager(request: Request) -> DatabaseManager:
    return request.app.state.database


def get_db(
    database: DatabaseManager = Depends(get_database_manager),
) -> Iterator[Session]:
    session = database.session()
    try:
        yield session
    finally:
        session.close()


def token_from_auth_header(authorization: str | None) -> str | None:
    if not authorization or not authorization.startswith("Bearer "):
        return None
    token = authorization.removeprefix("Bearer ").strip()
    return token or None


def record_from_auth_header(
    authorization: str | None,
    store: SessionStore,
) -> SessionRecord | None:
    token = token_from_auth_header(authorization)
    if not token:
        return None
    return store.get_by_access_token(token)


def get_record(
    authorization: str | None = Header(default=None),
    store: SessionStore = Depends(get_store),
) -> SessionRecord:
    record = record_from_auth_header(authorization, store)
    if record is None:
        raise HTTPException(status_code=401, detail="Missing or expired session token.")
    return record


def get_optional_record(
    authorization: str | None = Header(default=None),
    store: SessionStore = Depends(get_store),
) -> SessionRecord | None:
    return record_from_auth_header(authorization, store)
