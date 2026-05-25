from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..backend_models import StashEventsSyncMeta, StashGameEventRow
from ..config import Settings
from ..igdb_client import (
    IgdbClient,
    IgdbError,
    IgdbEvent,
    IgdbEventDetail,
    IgdbGame,
    igdb_event_url,
    igdb_game_url,
)
from ..schemas import (
    StashEventGameItemResponse,
    StashGameEventDetailResponse,
    StashGameEventResponse,
    StashGameEventsListResponse,
)

logger = logging.getLogger(__name__)

_SYNC_META_ID = "default"
StashEventsWindow = str  # "upcoming" | "previous"


def get_stash_game_event_detail(
    db: Session,
    settings: Settings,
    *,
    slug: str,
    offset: int = 0,
    limit: int = 36,
    igdb_client: IgdbClient | None = None,
) -> StashGameEventDetailResponse:
    safe_slug = slug.strip().strip("/")
    if not safe_slug:
        raise HTTPException(status_code=400, detail="Event slug is required.")
    if igdb_client is None:
        raise HTTPException(
            status_code=503,
            detail="IGDB is not configured. Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET on the server.",
        )

    try:
        detail = igdb_client.fetch_event_detail_resolved(safe_slug)
    except IgdbError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if detail is None:
        raise HTTPException(status_code=404, detail="Event not found.")

    legacy_row = db.get(StashGameEventRow, safe_slug)
    if legacy_row is not None and legacy_row.slug != detail.slug:
        db.delete(legacy_row)
    _upsert_cached_event(db, detail)
    games = list(detail.games)
    safe_offset = max(0, offset)
    safe_limit = max(1, min(limit, 120))
    page_games = games[safe_offset : safe_offset + safe_limit]

    serialized = [_serialize_igdb_game_item(db, game) for game in page_games]
    db.commit()

    return StashGameEventDetailResponse(
        slug=detail.slug,
        title=detail.title,
        startsAt=detail.starts_at.isoformat().replace("+00:00", "Z"),
        description=detail.description,
        imageUrl=detail.image_url,
        stashUrl=igdb_event_url(detail.slug),
        items=serialized,
    )


def list_stash_game_events_cached(
    db: Session,
    settings: Settings,
    *,
    window: str = "upcoming",
    offset: int = 0,
    limit: int = 60,
    force_refresh: bool = False,
    igdb_client: IgdbClient | None = None,
) -> StashGameEventsListResponse:
    key = window.strip().lower()
    if key not in {"upcoming", "previous"}:
        raise HTTPException(status_code=400, detail="window must be upcoming or previous.")
    safe_window = "previous" if key == "previous" else "upcoming"
    if igdb_client is None:
        raise HTTPException(
            status_code=503,
            detail="IGDB is not configured. Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET on the server.",
        )

    meta = _get_or_create_sync_meta(db)
    if force_refresh or _should_refresh_cache(db, meta, settings):
        try:
            sync_stash_events_from_remote(db, settings, igdb_client)
            db.commit()
        except IgdbError as exc:
            db.rollback()
            _record_sync_error(db, meta, str(exc))
            db.commit()
            if _count_cached_events(db) == 0:
                raise HTTPException(status_code=502, detail=str(exc)) from exc
            logger.warning("IGDB events sync failed; serving cached rows: %s", exc)

    rows = _query_cached_events(db, window=safe_window, offset=offset, limit=limit)
    return StashGameEventsListResponse(
        window=safe_window,
        items=[_row_to_response(row) for row in rows],
    )


def sync_stash_events_from_remote(
    db: Session,
    settings: Settings,
    igdb_client: IgdbClient,
) -> int:
    """Pull past and upcoming IGDB events into the shared cache."""
    page_size = settings.stash_events_sync_page_size
    max_pages = settings.stash_events_sync_max_pages
    remote: list[IgdbEvent] = []
    for window in ("previous", "upcoming"):
        remote.extend(
            igdb_client.fetch_all_events(
                window=window,
                page_size=page_size,
                max_pages=max_pages,
            ),
        )
    now = datetime.now(tz=UTC)
    seen_slugs: set[str] = set()
    for event in remote:
        if event.slug in seen_slugs:
            continue
        seen_slugs.add(event.slug)
        _upsert_cached_event(db, event, now=now)

    stale_rows = db.scalars(
        select(StashGameEventRow).where(StashGameEventRow.slug.not_in(seen_slugs)),
    ).all()
    for stale in stale_rows:
        db.delete(stale)

    meta = _get_or_create_sync_meta(db)
    meta.last_synced_at = now
    meta.last_error = None
    meta.event_count = len(seen_slugs)
    meta.updated_at = now
    db.flush()
    return len(seen_slugs)


def _upsert_cached_event(
    db: Session,
    event: IgdbEvent | IgdbEventDetail,
    *,
    now: datetime | None = None,
) -> StashGameEventRow:
    stamp = now or datetime.now(tz=UTC)
    row = db.get(StashGameEventRow, event.slug)
    if row is None:
        row = StashGameEventRow(
            slug=event.slug,
            title=event.title,
            description=event.description,
            starts_at=event.starts_at,
            image_url=event.image_url,
            stash_url=igdb_event_url(event.slug),
        )
        db.add(row)
    else:
        row.title = event.title
        row.description = event.description
        row.starts_at = event.starts_at
        row.image_url = event.image_url
        row.stash_url = igdb_event_url(event.slug)
        row.updated_at = stamp
    db.flush()
    return row


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _should_refresh_cache(db: Session, meta: StashEventsSyncMeta, settings: Settings) -> bool:
    if meta.last_synced_at is None:
        return True
    if _count_cached_events(db) == 0:
        return True
    if _count_cached_events_missing_description(db) > 0:
        return True
    ttl = max(60, settings.stash_events_cache_ttl_seconds)
    age = datetime.now(tz=UTC) - _as_utc(meta.last_synced_at)
    return age > timedelta(seconds=ttl)


def _count_cached_events_missing_description(db: Session) -> int:
    return int(
        db.scalar(
            select(func.count())
            .select_from(StashGameEventRow)
            .where(
                (StashGameEventRow.description.is_(None))
                | (StashGameEventRow.description == ""),
            ),
        )
        or 0,
    )


def _count_cached_events(db: Session) -> int:
    return int(db.scalar(select(func.count()).select_from(StashGameEventRow)) or 0)


def _get_or_create_sync_meta(db: Session) -> StashEventsSyncMeta:
    meta = db.get(StashEventsSyncMeta, _SYNC_META_ID)
    if meta is None:
        meta = StashEventsSyncMeta(id=_SYNC_META_ID)
        db.add(meta)
        db.flush()
    return meta


def _record_sync_error(db: Session, meta: StashEventsSyncMeta, message: str) -> None:
    meta.last_error = message[:2000]
    meta.updated_at = datetime.now(tz=UTC)
    db.flush()


def _query_cached_events(
    db: Session,
    *,
    window: str,
    offset: int,
    limit: int,
) -> list[StashGameEventRow]:
    now = datetime.now(tz=UTC)
    stmt = select(StashGameEventRow)
    if window == "upcoming":
        stmt = stmt.where(StashGameEventRow.starts_at >= now).order_by(StashGameEventRow.starts_at.asc())
    else:
        stmt = stmt.where(StashGameEventRow.starts_at < now).order_by(StashGameEventRow.starts_at.desc())
    stmt = stmt.offset(max(0, offset)).limit(max(1, min(limit, 120)))
    return list(db.scalars(stmt).all())


def _row_to_response(row: StashGameEventRow) -> StashGameEventResponse:
    return StashGameEventResponse(
        slug=row.slug,
        title=row.title,
        startsAt=row.starts_at.isoformat().replace("+00:00", "Z"),
        description=row.description,
        imageUrl=row.image_url,
        stashUrl=row.stash_url,
    )


def _serialize_igdb_game_item(db: Session, game: IgdbGame) -> StashEventGameItemResponse:
    from .catalog_service import upsert_igdb_game

    media = upsert_igdb_game(db, game)
    slug = str((game.metadata or {}).get("slug") or game.external_id)
    release_label = _release_label_from_metadata(game.metadata)
    return StashEventGameItemResponse(
        slug=slug,
        title=game.title,
        imageUrl=game.image_url,
        releaseLabel=release_label,
        stashUrl=igdb_game_url(slug) if slug else igdb_game_url(game.external_id),
        mediaId=str(media.id),
    )


def _release_label_from_metadata(metadata: dict[str, object]) -> str | None:
    unix = metadata.get("firstReleaseDateUnix")
    if isinstance(unix, (int, float)) and unix > 0:
        dt = datetime.fromtimestamp(int(unix), tz=UTC)
        return dt.strftime("%d %b %Y")
    year = metadata.get("firstReleaseDate")
    if isinstance(year, str) and year.strip():
        return year.strip()
    return None
