from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ...backend_models import AppUser, MediaItem, TrackingEntry
from ..dependencies import get_database_manager, get_db
from ...database import DatabaseManager
from ...schemas import BackendHealthResponse

router = APIRouter()


@router.get("/health")
def health(
    database: DatabaseManager = Depends(get_database_manager),
) -> dict[str, object]:
    return {
        "service": "cultur_api",
        "status": "ok",
        "databaseDialect": database.dialect,
    }


@router.get("/backend/health", response_model=BackendHealthResponse)
def backend_health(
    database: DatabaseManager = Depends(get_database_manager),
    db: Session = Depends(get_db),
) -> BackendHealthResponse:
    return BackendHealthResponse(
        service="cultur_api",
        status="ok",
        databaseDialect=database.dialect,
        users=db.scalar(select(func.count(AppUser.id))) or 0,
        mediaItems=db.scalar(select(func.count(MediaItem.id))) or 0,
        trackingEntries=db.scalar(select(func.count(TrackingEntry.id))) or 0,
    )
