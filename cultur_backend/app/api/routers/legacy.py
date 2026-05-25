from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ...config import Settings
from ...schemas import (
    DashboardResponse,
    HistoryResponse,
    ListsResponse,
    MediaDetailResponse,
    ProgressRequest,
    SearchResponse,
    SessionRecord,
    WatchActionRequest,
)
from ...storage import SessionStore
from ...services import upstream_session_service
from ..dependencies import get_record, get_settings, get_store

router = APIRouter()


@router.get("/dashboard", response_model=DashboardResponse)
def dashboard(
    record: SessionRecord = Depends(get_record),
    settings: Settings = Depends(get_settings),
    store: SessionStore = Depends(get_store),
) -> DashboardResponse:
    _, client, cookies, _ = upstream_session_service.ensure_upstream_session(record, settings, store)
    return DashboardResponse.model_validate(client.fetch_dashboard(cookies))


@router.get("/history", response_model=HistoryResponse)
def history(
    record: SessionRecord = Depends(get_record),
    settings: Settings = Depends(get_settings),
    store: SessionStore = Depends(get_store),
) -> HistoryResponse:
    _, client, cookies, _ = upstream_session_service.ensure_upstream_session(record, settings, store)
    return HistoryResponse.model_validate(client.fetch_history(cookies))


@router.get("/discover", response_model=DashboardResponse)
def discover(
    mediaType: str = "all",
    record: SessionRecord = Depends(get_record),
    settings: Settings = Depends(get_settings),
    store: SessionStore = Depends(get_store),
) -> DashboardResponse:
    _, client, cookies, _ = upstream_session_service.ensure_upstream_session(record, settings, store)
    return DashboardResponse.model_validate(
        client.fetch_discover(cookies, media_type=mediaType),
    )


@router.get("/search", response_model=SearchResponse)
def search(
    q: str,
    mediaType: str = "movie",
    record: SessionRecord = Depends(get_record),
    settings: Settings = Depends(get_settings),
    store: SessionStore = Depends(get_store),
) -> SearchResponse:
    if not q.strip():
        raise HTTPException(status_code=400, detail="The search query cannot be empty.")
    _, client, cookies, _ = upstream_session_service.ensure_upstream_session(record, settings, store)
    return SearchResponse.model_validate(client.search(cookies, query=q.strip(), media_type=mediaType))


@router.get("/lists", response_model=ListsResponse)
def lists(
    record: SessionRecord = Depends(get_record),
    settings: Settings = Depends(get_settings),
    store: SessionStore = Depends(get_store),
) -> ListsResponse:
    _, client, cookies, _ = upstream_session_service.ensure_upstream_session(record, settings, store)
    return ListsResponse.model_validate(client.fetch_lists(cookies))


@router.get("/media/{media_ref}", response_model=MediaDetailResponse)
def media_detail(
    media_ref: str,
    record: SessionRecord = Depends(get_record),
    settings: Settings = Depends(get_settings),
    store: SessionStore = Depends(get_store),
) -> MediaDetailResponse:
    _, client, cookies, _ = upstream_session_service.ensure_upstream_session(record, settings, store)
    return MediaDetailResponse.model_validate(
        client.fetch_media_detail(cookies, media_ref=media_ref),
    )


@router.post("/progress")
def progress(
    payload: ProgressRequest,
    record: SessionRecord = Depends(get_record),
    settings: Settings = Depends(get_settings),
    store: SessionStore = Depends(get_store),
) -> dict[str, bool]:
    return upstream_session_service.persist_progress_update(
        record=record,
        settings=settings,
        store=store,
        media_ref=payload.mediaRef,
        status=payload.status,
        progress=payload.progress,
        score=payload.score,
    )


@router.post("/watch-actions")
def watch_actions(
    payload: WatchActionRequest,
    record: SessionRecord = Depends(get_record),
    settings: Settings = Depends(get_settings),
    store: SessionStore = Depends(get_store),
) -> dict[str, bool]:
    return upstream_session_service.persist_watch_action(
        record=record,
        settings=settings,
        store=store,
        media_ref=payload.mediaRef,
        action=payload.action,
    )
