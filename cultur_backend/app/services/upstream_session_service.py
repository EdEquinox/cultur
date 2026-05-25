from __future__ import annotations

import requests
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..backend_models import AppUser, MediaItem, TrackingEntry
from ..config import Settings
from ..schemas import SessionRecord
from ..storage import SessionStore
from ..yamtrack_client import YamtrackAuthExpired, YamtrackClient, YamtrackError


def ensure_upstream_session(
    record: SessionRecord,
    settings: Settings,
    store: SessionStore,
    *,
    validate_only: bool = False,
) -> SessionRecord | tuple[SessionRecord, YamtrackClient, dict[str, str], str | None]:
    client = YamtrackClient(record.yamtrackBaseUrl, settings.request_timeout_seconds)
    cookies = store.decrypt_cookies(record)
    csrf_token = store.decrypt_csrf_token(record)
    try:
        client.validate_session(cookies)
        if validate_only:
            return record
        return record, client, cookies, csrf_token
    except YamtrackAuthExpired:
        password = store.decrypt_password(record)
        if not record.rememberCredentials or not password:
            raise HTTPException(
                status_code=401,
                detail="The Yamtrack session expired and auto re-login is disabled.",
            ) from None
        try:
            login_result = client.login(record.username, password)
        except (YamtrackError, requests.RequestException) as error:
            raise HTTPException(
                status_code=401,
                detail=f"Auto re-login failed: {error}",
            ) from error
        updated = store.persist_upstream_state(
            record.sessionId,
            cookies=login_result.cookies,
            csrf_token=login_result.csrf_token,
            password=password,
            remember_credentials=True,
            relogin=True,
        )
        if validate_only:
            return updated
        return updated, client, login_result.cookies, login_result.csrf_token
    except requests.RequestException as error:
        raise HTTPException(
            status_code=502,
            detail=f"Could not reach Yamtrack: {error}",
        ) from error
    except YamtrackError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


def persist_progress_update(
    *,
    record: SessionRecord,
    settings: Settings,
    store: SessionStore,
    media_ref: str,
    status: str | None,
    progress: float | None,
    score: float | None,
) -> dict[str, bool]:
    active_record, client, cookies, csrf_token = ensure_upstream_session(record, settings, store)
    login_result = client.update_progress(
        cookies,
        csrf_token=csrf_token,
        media_ref=media_ref,
        status=status,
        progress=progress,
        score=score,
    )
    store.persist_upstream_state(
        active_record.sessionId,
        cookies=login_result.cookies,
        csrf_token=login_result.csrf_token,
    )
    return {"ok": True}


def persist_watch_action(
    *,
    record: SessionRecord,
    settings: Settings,
    store: SessionStore,
    media_ref: str,
    action: str,
) -> dict[str, bool]:
    active_record, client, cookies, csrf_token = ensure_upstream_session(record, settings, store)
    login_result = client.run_watch_action(
        cookies,
        csrf_token=csrf_token,
        media_ref=media_ref,
        action=action,
    )
    store.persist_upstream_state(
        active_record.sessionId,
        cookies=login_result.cookies,
        csrf_token=login_result.csrf_token,
    )
    return {"ok": True}
