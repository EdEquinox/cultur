from __future__ import annotations

from datetime import UTC, date, datetime

import requests
from fastapi import HTTPException
from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.orm import Session

from ..backend_models import (
    AppUser,
    MediaItem,
    TrackingEntry,
    TvEpisodeUserState,
    TvEpisodeWatch,
    TvSeasonUserState,
    UserFollow,
)
from ..schemas import (
    BackendBootstrapRequest,
    BackendBootstrapResponse,
    BackendMediaListResponse,
    BackendMediaResponse,
    BackendMediaUpsertRequest,
    BackendPurgeLibraryRequest,
    BackendPurgeLibraryResponse,
    BackendTrackingListResponse,
    BackendTrackingResponse,
    BackendTrackingUpsertRequest,
    TvEpisodeWatchListResponse,
    TvEpisodeWatchClearSeasonRequest,
    TvEpisodeWatchClearSeasonResponse,
    TvEpisodeWatchMarkThroughRequest,
    TvEpisodeWatchMarkThroughResponse,
    TvEpisodeWatchPutRequest,
    TvEpisodeWatchPutResponse,
    WatchedEpisodeResponse,
    WatchedTvEpisodeLibraryItem,
    WatchedTvEpisodeLibraryListResponse,
)
from ..serializers.backend import serialize_media_item, serialize_tracking_entry, serialize_user
from ..tmdb_client import TmdbClient, TmdbError, TmdbTvSeasonSummary
from ..validation import require_text
from .tracking_library import (
    flags_from_notes,
    load_tracking_flags,
    replace_tracking_flags,
    sync_tracking_structured_fields,
    tv_library_watched_requested,
)


def _parse_completed_at(value: object) -> datetime | None:
    if value is None:
        return None
    if not isinstance(value, str):
        return None
    text = value.strip()
    if not text:
        return None
    normalized = text.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def bootstrap_user(
    db: Session,
    *,
    database_dialect: str,
    payload: BackendBootstrapRequest,
) -> BackendBootstrapResponse:
    username = require_text(payload.username, "username")
    display_name = payload.displayName.strip() if payload.displayName else None
    user = db.scalar(select(AppUser).where(AppUser.username == username))
    if user is None:
        user = AppUser(username=username, display_name=display_name)
        db.add(user)
        db.commit()
        db.refresh(user)
    elif display_name is not None and user.display_name != display_name:
        user.display_name = display_name
        db.commit()
        db.refresh(user)

    return BackendBootstrapResponse(
        status="ok",
        databaseDialect=database_dialect,
        user=serialize_user(user),
    )


def upsert_media_item(
    db: Session,
    payload: BackendMediaUpsertRequest,
) -> BackendMediaResponse:
    source = require_text(payload.source, "source").lower()
    external_id = require_text(payload.externalId, "externalId")
    media_type = require_text(payload.mediaType, "mediaType").lower()
    title = require_text(payload.title, "title")

    item = db.scalar(
        select(MediaItem).where(
            MediaItem.source == source,
            MediaItem.media_type == media_type,
            MediaItem.external_id == external_id,
        ),
    )
    if item is None:
        item = MediaItem(
            source=source,
            external_id=external_id,
            media_type=media_type,
            title=title,
            subtitle=payload.subtitle,
            description=payload.description,
            image_url=payload.imageUrl,
            provider_payload=payload.metadata,
        )
        db.add(item)
    else:
        item.title = title
        item.subtitle = payload.subtitle
        item.description = payload.description
        item.image_url = payload.imageUrl
        item.provider_payload = payload.metadata

    db.commit()
    db.refresh(item)
    return serialize_media_item(item)


def list_media_items(
    db: Session,
    *,
    media_type: str | None,
    limit: int,
) -> BackendMediaListResponse:
    safe_limit = max(1, min(limit, 200))
    query = select(MediaItem).order_by(MediaItem.updated_at.desc()).limit(safe_limit)
    if media_type:
        query = query.where(MediaItem.media_type == media_type.strip().lower())
    items = db.scalars(query).all()
    return BackendMediaListResponse(items=[serialize_media_item(item) for item in items])


def upsert_tracking_entry(
    db: Session,
    payload: BackendTrackingUpsertRequest,
    *,
    tmdb_client: TmdbClient | None = None,
) -> BackendTrackingResponse:
    username = require_text(payload.username, "username")
    media_id = require_text(payload.mediaId, "mediaId")

    user = db.scalar(select(AppUser).where(AppUser.username == username))
    if user is None:
        raise HTTPException(status_code=404, detail="Backend user not found.")

    media_item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if media_item is None:
        raise HTTPException(status_code=404, detail="Backend media item not found.")

    entry = db.scalar(
        select(TrackingEntry).where(
            TrackingEntry.user_id == user.id,
            TrackingEntry.media_item_id == media_item.id,
        ),
    )
    incoming = payload.model_dump(exclude_unset=True)

    was_watched = entry is not None and tv_library_watched_requested(
        status=entry.status,
        notes=entry.notes,
        flags=load_tracking_flags(db, entry) if entry is not None else None,
    )
    will_be_watched = tv_library_watched_requested(
        status=payload.status,
        notes=payload.notes,
    )
    if (
        media_item.media_type == "tv"
        and will_be_watched
        and not was_watched
    ):
        _assert_tv_all_aired_episodes_watched(
            db,
            tmdb_client,
            user_id=user.id,
            media_item=media_item,
            entry=entry,
        )

    if entry is None:
        entry = TrackingEntry(
            user_id=user.id,
            media_item_id=media_item.id,
            status=payload.status,
            progress=payload.progress,
            score=payload.score,
            notes=payload.notes,
            started_at=_parse_completed_at(incoming.get("startedAt")),
            completed_at=_parse_completed_at(incoming.get("completedAt")),
            dropped_at=_parse_completed_at(incoming.get("droppedAt")),
            collected_at=_parse_completed_at(incoming.get("collectedAt")),
        )
        db.add(entry)
    else:
        entry.status = payload.status
        if "progress" in incoming:
            entry.progress = payload.progress
        if "score" in incoming:
            entry.score = payload.score
        entry.notes = payload.notes
        if "startedAt" in incoming:
            entry.started_at = _parse_completed_at(incoming.get("startedAt"))
        if "completedAt" in incoming:
            entry.completed_at = _parse_completed_at(incoming.get("completedAt"))
        if "droppedAt" in incoming:
            entry.dropped_at = _parse_completed_at(incoming.get("droppedAt"))
        if "collectedAt" in incoming:
            entry.collected_at = _parse_completed_at(incoming.get("collectedAt"))

    db.flush()
    sync_tracking_structured_fields(db, entry)
    db.commit()
    db.refresh(entry)
    db.refresh(user)
    db.refresh(media_item)
    if media_item.media_type == "music" and "score" in incoming:
        from .music_catalog_service import invalidate_music_home_cache

        invalidate_music_home_cache(username)
    ec = (
        count_tv_episode_watches_for_user_media(db, user_id=user.id, media_item_id=media_item.id)
        if media_item.media_type == "tv"
        else 0
    )
    return serialize_tracking_entry(entry, user, media_item, episode_watched_count=ec)


def ensure_tv_tracking_row_for_episode_progress(
    db: Session,
    *,
    user_id: str,
    media_item: MediaItem,
) -> None:
    if media_item.media_type != "tv":
        return
    exists = db.scalar(
        select(TrackingEntry.id).where(
            TrackingEntry.user_id == user_id,
            TrackingEntry.media_item_id == media_item.id,
        ),
    )
    if exists is None:
        db.add(
            TrackingEntry(
                user_id=user_id,
                media_item_id=media_item.id,
                status="In progress",
            ),
        )
        db.flush()
        return

    entry = db.scalar(
        select(TrackingEntry).where(
            TrackingEntry.user_id == user_id,
            TrackingEntry.media_item_id == media_item.id,
        ),
    )
    if entry is None:
        return
    entry.updated_at = datetime.now(tz=UTC)
    if entry.status.strip().lower() == "planning":
        entry.status = "In progress"


def count_tv_episode_watches_for_user_media(db: Session, *, user_id: str, media_item_id: str) -> int:
    n = db.scalar(
        select(func.count())
        .select_from(TvEpisodeWatch)
        .where(
            TvEpisodeWatch.user_id == user_id,
            TvEpisodeWatch.media_item_id == media_item_id,
        ),
    )
    return int(n or 0)


def _backfill_tv_tracking_for_episode_watches(db: Session, *, user_id: str) -> None:
    watched_mids = db.scalars(
        select(TvEpisodeWatch.media_item_id)
        .where(TvEpisodeWatch.user_id == user_id)
        .distinct(),
    ).all()
    for mid in watched_mids:
        if (
            db.scalar(
                select(TrackingEntry.id).where(
                    TrackingEntry.user_id == user_id,
                    TrackingEntry.media_item_id == mid,
                ),
            )
            is None
        ):
            db.add(
                TrackingEntry(
                    user_id=user_id,
                    media_item_id=mid,
                    status="In progress",
                ),
            )
    db.flush()


def list_tracking_entries(
    db: Session,
    *,
    username: str,
    media_type: str | None,
    limit: int,
) -> BackendTrackingListResponse:
    safe_limit = max(1, min(limit, 2000))
    normalized_username = require_text(username, "username")

    user = db.scalar(select(AppUser).where(AppUser.username == normalized_username))
    if user is not None and media_type and media_type.strip().lower() == "tv":
        _backfill_tv_tracking_for_episode_watches(db, user_id=user.id)
        db.flush()

    query = (
        select(TrackingEntry, AppUser, MediaItem)
        .join(AppUser, TrackingEntry.user_id == AppUser.id)
        .join(MediaItem, TrackingEntry.media_item_id == MediaItem.id)
        .where(AppUser.username == normalized_username)
        .order_by(TrackingEntry.updated_at.desc())
        .limit(safe_limit)
    )
    if media_type:
        query = query.where(MediaItem.media_type == media_type.strip().lower())

    rows = db.execute(query).all()

    tv_ids = [m.id for _, _, m in rows if m.media_type == "tv"]
    watch_counts: dict[str, int] = {}
    if tv_ids and rows:
        uid = rows[0][1].id
        count_rows = db.execute(
            select(TvEpisodeWatch.media_item_id, func.count())
            .where(
                TvEpisodeWatch.user_id == uid,
                TvEpisodeWatch.media_item_id.in_(tv_ids),
            )
            .group_by(TvEpisodeWatch.media_item_id),
        ).all()
        watch_counts = {str(mid): int(c) for mid, c in count_rows}

    return BackendTrackingListResponse(
        items=[
            serialize_tracking_entry(
                entry,
                user,
                media_item,
                episode_watched_count=watch_counts.get(media_item.id, 0)
                if media_item.media_type == "tv"
                else 0,
            )
            for entry, user, media_item in rows
        ],
    )


def _iso_z(dt: datetime) -> str:
    return dt.isoformat().replace("+00:00", "Z")


def _iso_z_optional(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return _iso_z(dt)


def _parse_iso_date(value: str | None) -> date | None:
    if not value:
        return None
    raw = value.strip()[:10]
    if len(raw) < 10:
        return None
    try:
        return date.fromisoformat(raw)
    except ValueError:
        return None


def _episode_released_for_watch(*, air_date: str | None, today: date) -> bool:
    """Episodes without an air date are treated as already available (legacy / special cases)."""
    if not air_date or not str(air_date).strip():
        return True
    d = _parse_iso_date(str(air_date).strip())
    if d is None:
        return True
    return d <= today


def _season_numbers_in_watch_order(summaries: list[TmdbTvSeasonSummary]) -> list[int]:
    nums = [s.season_number for s in summaries if getattr(s, "episode_count", 0) > 0]
    if not nums:
        nums = [s.season_number for s in summaries]
    positive = sorted({n for n in nums if n > 0})
    ordered = list(positive)
    if 0 in nums and 0 not in ordered:
        ordered.append(0)
    return ordered


def collect_aired_tv_episode_keys(
    client: TmdbClient,
    *,
    tv_external_id: str,
    today: date | None = None,
    max_seasons_to_scan: int = 32,
) -> set[tuple[int, int]]:
    """All season/episode keys that have aired on or before [today]."""
    stamp = today or datetime.now(tz=UTC).date()
    try:
        bundle = client.fetch_tv_show_seasons_bundle(tv_id=tv_external_id)
    except (TmdbError, Exception):
        return set()
    keys: set[tuple[int, int]] = set()
    scanned = 0
    for sn in _season_numbers_in_watch_order(list(bundle.seasons)):
        if scanned >= max_seasons_to_scan:
            break
        try:
            detail = client.fetch_tv_season_detail(
                tv_id=tv_external_id,
                season_number=sn,
                include_credits=False,
            )
        except (TmdbError, Exception):
            scanned += 1
            continue
        scanned += 1
        for ep in sorted(detail.episodes, key=lambda e: e.episode_number):
            if _episode_released_for_watch(air_date=ep.air_date, today=stamp):
                keys.add((sn, ep.episode_number))
    return keys


def _clear_stale_watched_library_state(db: Session, entry: TrackingEntry) -> None:
    """Drop library-watched flag when more aired episodes remain (e.g. new season)."""
    flags = load_tracking_flags(db, entry)
    if "watched" not in flags:
        return
    flags.discard("watched")
    replace_tracking_flags(db, entry, flags)
    if entry.status.strip().lower() == "completed":
        entry.status = "In progress"


def _apply_watched_library_state(db: Session, entry: TrackingEntry) -> None:
    """Set library Finished state when every aired episode is watched."""
    flags = load_tracking_flags(db, entry)
    flags.discard("watchlist")
    flags.discard("doing")
    flags.discard("dropped")
    flags.add("watched")
    replace_tracking_flags(db, entry, flags)
    entry.status = "Completed"
    if entry.completed_at is None:
        entry.completed_at = datetime.now(tz=UTC)
    entry.dropped_at = None


def _assert_tv_all_aired_episodes_watched(
    db: Session,
    tmdb_client: TmdbClient | None,
    *,
    user_id: str,
    media_item: MediaItem,
    entry: TrackingEntry | None,
) -> None:
    """TV shows may only be marked Finished when every aired episode is watched."""
    watched_keys = _watched_episode_keys_for_media(
        db,
        user_id=user_id,
        media_item_id=media_item.id,
    )
    ext = (media_item.external_id or "").strip()
    aired_keys: set[tuple[int, int]] = set()
    if tmdb_client is not None and ext and media_item.source == "tmdb":
        aired_keys = collect_aired_tv_episode_keys(tmdb_client, tv_external_id=ext)
    if aired_keys:
        if not aired_keys.issubset(watched_keys):
            missing = len(aired_keys - watched_keys)
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Mark all aired episodes as watched first ({missing} remaining) "
                    "before marking this series as finished."
                ),
            )
        return
    if entry is not None and entry.tv_fully_watched:
        return
    raise HTTPException(
        status_code=400,
        detail="Mark every aired episode as watched before marking this series as finished.",
    )


def _watched_episode_keys_for_media(
    db: Session,
    *,
    user_id: str,
    media_item_id: str,
) -> set[tuple[int, int]]:
    rows = db.execute(
        select(TvEpisodeWatch.season_number, TvEpisodeWatch.episode_number).where(
            TvEpisodeWatch.user_id == user_id,
            TvEpisodeWatch.media_item_id == media_item_id,
        ),
    ).all()
    return {(int(sn), int(en)) for sn, en in rows}


def refresh_tv_series_watch_state(
    db: Session,
    tmdb_client: TmdbClient | None,
    *,
    user_id: str,
    media_item: MediaItem,
) -> TrackingEntry | None:
    """Persist TV progress (0–100) and fully-watched flag on the tracking row."""
    if media_item.media_type != "tv":
        return None

    ensure_tv_tracking_row_for_episode_progress(
        db,
        user_id=user_id,
        media_item=media_item,
    )
    entry = db.scalar(
        select(TrackingEntry).where(
            TrackingEntry.user_id == user_id,
            TrackingEntry.media_item_id == media_item.id,
        ),
    )
    if entry is None:
        return None

    watched_keys = _watched_episode_keys_for_media(
        db,
        user_id=user_id,
        media_item_id=media_item.id,
    )
    aired_keys: set[tuple[int, int]] = set()
    ext = (media_item.external_id or "").strip()
    if tmdb_client is not None and ext and media_item.source == "tmdb":
        aired_keys = collect_aired_tv_episode_keys(
            tmdb_client,
            tv_external_id=ext,
        )

    if aired_keys:
        matched = len(watched_keys & aired_keys)
        entry.progress = min(100, round(100 * matched / len(aired_keys)))
        entry.tv_fully_watched = aired_keys.issubset(watched_keys)
        entry.tv_aired_episode_total = len(aired_keys)
    else:
        entry.progress = None
        entry.tv_fully_watched = False
        entry.tv_aired_episode_total = None

    if entry.tv_fully_watched:
        _apply_watched_library_state(db, entry)
    else:
        _clear_stale_watched_library_state(db, entry)

    entry.updated_at = datetime.now(tz=UTC)
    db.flush()
    return entry


def recompute_tv_series_watch_states_for_user(
    db: Session,
    tmdb_client: TmdbClient,
    *,
    username: str,
    limit: int = 200,
) -> int:
    """Recompute cached TV progress for all shows the user has episode marks on."""
    user = db.scalar(select(AppUser).where(AppUser.username == require_text(username, "username")))
    if user is None:
        return 0

    media_ids = db.scalars(
        select(TvEpisodeWatch.media_item_id)
        .where(TvEpisodeWatch.user_id == user.id)
        .distinct()
        .limit(max(1, min(limit, 500))),
    ).all()

    updated = 0
    for media_id in media_ids:
        media_item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
        if media_item is None or media_item.media_type != "tv":
            continue
        if refresh_tv_series_watch_state(
            db,
            tmdb_client,
            user_id=user.id,
            media_item=media_item,
        ) is not None:
            updated += 1
    db.commit()
    return updated


def mark_tv_episodes_watched_through(
    db: Session,
    tmdb_client: TmdbClient,
    payload: TvEpisodeWatchMarkThroughRequest,
) -> TvEpisodeWatchMarkThroughResponse:
    username = require_text(payload.username, "username")
    media_id = require_text(payload.mediaId, "mediaId")
    through_s = payload.throughSeasonNumber
    through_e = payload.throughEpisodeNumber
    only_season = payload.onlySeasonNumber
    if through_s < 0 or through_e < 0:
        raise HTTPException(status_code=400, detail="Season and episode numbers must be non-negative.")
    if only_season is not None and only_season != through_s:
        raise HTTPException(
            status_code=400,
            detail="throughSeasonNumber must match onlySeasonNumber when onlySeasonNumber is set.",
        )

    user = db.scalar(select(AppUser).where(AppUser.username == username))
    if user is None:
        raise HTTPException(status_code=404, detail="Backend user not found.")

    media_item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if media_item is None:
        raise HTTPException(status_code=404, detail="Backend media item not found.")
    if media_item.media_type != "tv":
        raise HTTPException(status_code=400, detail="Episode watches are only supported for TV media.")
    if media_item.source != "tmdb":
        raise HTTPException(status_code=400, detail="Only TMDB-backed TV shows are supported for this action.")

    today = date.today()
    try:
        if only_season is None:
            keys = _collect_aired_episode_keys_through(
                tmdb_client,
                tv_external_id=media_item.external_id,
                through_season=through_s,
                through_episode=through_e,
                today=today,
            )
        else:
            keys = _collect_aired_episode_keys_in_season_through(
                tmdb_client,
                tv_external_id=media_item.external_id,
                season_number=only_season,
                through_episode=through_e,
                today=today,
            )
    except TmdbError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    if (through_s, through_e) not in keys:
        raise HTTPException(
            status_code=400,
            detail="That episode is not available yet or does not exist for this show.",
        )

    if only_season is None:
        db.execute(
            delete(TvEpisodeWatch).where(
                TvEpisodeWatch.user_id == user.id,
                TvEpisodeWatch.media_item_id == media_item.id,
                or_(
                    TvEpisodeWatch.season_number > through_s,
                    and_(
                        TvEpisodeWatch.season_number == through_s,
                        TvEpisodeWatch.episode_number > through_e,
                    ),
                ),
            ),
        )
    else:
        db.execute(
            delete(TvEpisodeWatch).where(
                TvEpisodeWatch.user_id == user.id,
                TvEpisodeWatch.media_item_id == media_item.id,
                TvEpisodeWatch.season_number == only_season,
                TvEpisodeWatch.episode_number > through_e,
            ),
        )

    raw_at = payload.watchedAt
    stamp: datetime = datetime.now(tz=UTC)
    if raw_at is not None and str(raw_at).strip():
        parsed = _parse_completed_at(str(raw_at).strip())
        if parsed is None:
            raise HTTPException(status_code=400, detail="Invalid watchedAt datetime.")
        stamp = parsed

    for season_number, episode_number in sorted(keys):
        row = db.scalar(
            select(TvEpisodeWatch).where(
                TvEpisodeWatch.user_id == user.id,
                TvEpisodeWatch.media_item_id == media_item.id,
                TvEpisodeWatch.season_number == season_number,
                TvEpisodeWatch.episode_number == episode_number,
            ),
        )
        if row is None:
            db.add(
                TvEpisodeWatch(
                    user_id=user.id,
                    media_item_id=media_item.id,
                    season_number=season_number,
                    episode_number=episode_number,
                    watched_at=stamp,
                ),
            )
        else:
            row.watched_at = stamp

    if keys:
        ensure_tv_tracking_row_for_episode_progress(db, user_id=user.id, media_item=media_item)
        refresh_tv_series_watch_state(
            db,
            tmdb_client,
            user_id=user.id,
            media_item=media_item,
        )

    db.commit()
    return TvEpisodeWatchMarkThroughResponse(
        markedCount=len(keys),
        throughSeasonNumber=through_s,
        throughEpisodeNumber=through_e,
    )


def clear_tv_season_episode_watches(
    db: Session,
    payload: TvEpisodeWatchClearSeasonRequest,
    *,
    tmdb_client: TmdbClient | None = None,
) -> TvEpisodeWatchClearSeasonResponse:
    username = require_text(payload.username, "username")
    media_id = require_text(payload.mediaId, "mediaId")
    season_number = payload.seasonNumber
    if season_number < 0:
        raise HTTPException(status_code=400, detail="Season number must be non-negative.")

    user = db.scalar(select(AppUser).where(AppUser.username == username))
    if user is None:
        raise HTTPException(status_code=404, detail="Backend user not found.")

    media_item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if media_item is None:
        raise HTTPException(status_code=404, detail="Backend media item not found.")
    if media_item.media_type != "tv":
        raise HTTPException(status_code=400, detail="Episode watches are only supported for TV media.")

    to_delete = db.scalars(
        select(TvEpisodeWatch).where(
            TvEpisodeWatch.user_id == user.id,
            TvEpisodeWatch.media_item_id == media_item.id,
            TvEpisodeWatch.season_number == season_number,
        ),
    ).all()
    removed = len(to_delete)
    for row in to_delete:
        db.delete(row)
    db.execute(
        delete(TvEpisodeUserState).where(
            TvEpisodeUserState.user_id == user.id,
            TvEpisodeUserState.media_item_id == media_item.id,
            TvEpisodeUserState.season_number == season_number,
        ),
    )
    db.execute(
        delete(TvSeasonUserState).where(
            TvSeasonUserState.user_id == user.id,
            TvSeasonUserState.media_item_id == media_item.id,
            TvSeasonUserState.season_number == season_number,
        ),
    )
    refresh_tv_series_watch_state(
        db,
        tmdb_client,
        user_id=user.id,
        media_item=media_item,
    )
    db.commit()
    return TvEpisodeWatchClearSeasonResponse(removedCount=removed)


def apply_tv_episode_user_state_from_backup(
    db: Session,
    *,
    user_id: str,
    media_item_id: str,
    season_number: int,
    episode_number: int,
    rating: float | None,
    set_rating: bool,
    rating_rated_at: datetime | None,
    watchlist: bool,
    set_watchlist: bool,
    watchlisted_at: datetime | None,
) -> None:
    row = db.scalar(
        select(TvEpisodeUserState).where(
            TvEpisodeUserState.user_id == user_id,
            TvEpisodeUserState.media_item_id == media_item_id,
            TvEpisodeUserState.season_number == season_number,
            TvEpisodeUserState.episode_number == episode_number,
        ),
    )
    if row is None:
        row = TvEpisodeUserState(
            user_id=user_id,
            media_item_id=media_item_id,
            season_number=season_number,
            episode_number=episode_number,
        )
        db.add(row)
    if set_rating:
        row.rating = rating
        row.rating_rated_at = rating_rated_at if rating is not None else None
    if set_watchlist:
        row.watchlist = watchlist
        row.watchlisted_at = watchlisted_at if watchlist else None


def apply_tv_season_user_state_from_backup(
    db: Session,
    *,
    user_id: str,
    media_item_id: str,
    season_number: int,
    rating: float | None,
    set_rating: bool,
    rating_rated_at: datetime | None,
    watchlist: bool,
    set_watchlist: bool,
    watchlisted_at: datetime | None,
) -> None:
    row = db.scalar(
        select(TvSeasonUserState).where(
            TvSeasonUserState.user_id == user_id,
            TvSeasonUserState.media_item_id == media_item_id,
            TvSeasonUserState.season_number == season_number,
        ),
    )
    if row is None:
        row = TvSeasonUserState(
            user_id=user_id,
            media_item_id=media_item_id,
            season_number=season_number,
        )
        db.add(row)
    if set_rating:
        row.rating = rating
        row.rating_rated_at = rating_rated_at if rating is not None else None
    if set_watchlist:
        row.watchlist = watchlist
        row.watchlisted_at = watchlisted_at if watchlist else None


def merge_tv_episode_user_state_from_put(
    db: Session,
    *,
    user: AppUser,
    media_item: MediaItem,
    payload: TvEpisodeWatchPutRequest,
) -> None:
    incoming = payload.model_dump(exclude_unset=True)
    if not any(
        k in incoming
        for k in ("userRating", "userRatingRatedAt", "userWatchlist", "userWatchlistedAt")
    ):
        return
    row = db.scalar(
        select(TvEpisodeUserState).where(
            TvEpisodeUserState.user_id == user.id,
            TvEpisodeUserState.media_item_id == media_item.id,
            TvEpisodeUserState.season_number == payload.seasonNumber,
            TvEpisodeUserState.episode_number == payload.episodeNumber,
        ),
    )
    if row is None:
        row = TvEpisodeUserState(
            user_id=user.id,
            media_item_id=media_item.id,
            season_number=payload.seasonNumber,
            episode_number=payload.episodeNumber,
        )
        db.add(row)
    if "userRating" in incoming:
        row.rating = payload.userRating
        if payload.userRating is not None:
            if payload.userRatingRatedAt and str(payload.userRatingRatedAt).strip():
                parsed = _parse_completed_at(str(payload.userRatingRatedAt).strip())
                row.rating_rated_at = parsed if parsed is not None else datetime.now(tz=UTC)
            else:
                row.rating_rated_at = datetime.now(tz=UTC)
        else:
            row.rating_rated_at = None
    elif "userRatingRatedAt" in incoming and row.rating is not None:
        parsed = (
            _parse_completed_at(str(payload.userRatingRatedAt).strip())
            if payload.userRatingRatedAt and str(payload.userRatingRatedAt).strip()
            else None
        )
        if parsed is not None:
            row.rating_rated_at = parsed
    if "userWatchlist" in incoming:
        row.watchlist = bool(payload.userWatchlist)
        if row.watchlist:
            if payload.userWatchlistedAt and str(payload.userWatchlistedAt).strip():
                parsed = _parse_completed_at(str(payload.userWatchlistedAt).strip())
                row.watchlisted_at = parsed if parsed is not None else datetime.now(tz=UTC)
            else:
                row.watchlisted_at = datetime.now(tz=UTC)
        else:
            row.watchlisted_at = None


def _collect_aired_episode_keys_through(
    client: TmdbClient,
    *,
    tv_external_id: str,
    through_season: int,
    through_episode: int,
    today: date,
) -> set[tuple[int, int]]:
    bundle = client.fetch_tv_show_seasons_bundle(tv_id=tv_external_id)
    keys: set[tuple[int, int]] = set()
    for summary in bundle.seasons:
        sn = summary.season_number
        if sn > through_season:
            break
        detail = client.fetch_tv_season_detail(tv_id=tv_external_id, season_number=sn)
        for ep in sorted(detail.episodes, key=lambda x: x.episode_number):
            if sn > through_season:
                break
            if sn == through_season and ep.episode_number > through_episode:
                continue
            if not _episode_released_for_watch(air_date=ep.air_date, today=today):
                continue
            keys.add((sn, ep.episode_number))
    return keys


def _collect_aired_episode_keys_in_season_through(
    client: TmdbClient,
    *,
    tv_external_id: str,
    season_number: int,
    through_episode: int,
    today: date,
) -> set[tuple[int, int]]:
    detail = client.fetch_tv_season_detail(tv_id=tv_external_id, season_number=season_number)
    keys: set[tuple[int, int]] = set()
    for ep in sorted(detail.episodes, key=lambda x: x.episode_number):
        if ep.episode_number > through_episode:
            break
        if not _episode_released_for_watch(air_date=ep.air_date, today=today):
            continue
        keys.add((season_number, ep.episode_number))
    return keys


def list_tv_episode_watches(
    db: Session,
    *,
    username: str,
    media_id: str,
) -> TvEpisodeWatchListResponse:
    user = db.scalar(select(AppUser).where(AppUser.username == require_text(username, "username")))
    if user is None:
        return TvEpisodeWatchListResponse(items=[])
    media_item = db.scalar(select(MediaItem).where(MediaItem.id == require_text(media_id, "mediaId")))
    if media_item is None or media_item.media_type != "tv":
        return TvEpisodeWatchListResponse(items=[])
    watches = db.scalars(
        select(TvEpisodeWatch)
        .where(
            TvEpisodeWatch.user_id == user.id,
            TvEpisodeWatch.media_item_id == media_item.id,
        )
        .order_by(TvEpisodeWatch.season_number, TvEpisodeWatch.episode_number),
    ).all()
    states = db.scalars(
        select(TvEpisodeUserState)
        .where(
            TvEpisodeUserState.user_id == user.id,
            TvEpisodeUserState.media_item_id == media_item.id,
        )
        .order_by(TvEpisodeUserState.season_number, TvEpisodeUserState.episode_number),
    ).all()
    watch_by_key = {(w.season_number, w.episode_number): w for w in watches}
    state_by_key = {(s.season_number, s.episode_number): s for s in states}
    keys_sorted = sorted(set(watch_by_key) | set(state_by_key))
    merged: list[WatchedEpisodeResponse] = []
    for key in keys_sorted:
        wrow = watch_by_key.get(key)
        st = state_by_key.get(key)
        merged.append(
            WatchedEpisodeResponse(
                seasonNumber=key[0],
                episodeNumber=key[1],
                watchedAt=_iso_z(wrow.watched_at) if wrow is not None else None,
                userRating=st.rating if st is not None else None,
                userRatingRatedAt=_iso_z_optional(st.rating_rated_at) if st is not None else None,
                userWatchlist=st.watchlist if st is not None else None,
                userWatchlistedAt=_iso_z_optional(st.watchlisted_at) if st is not None else None,
            ),
        )
    return TvEpisodeWatchListResponse(items=merged)


def list_tv_watched_episodes_library(
    db: Session,
    *,
    username: str,
    limit: int = 200,
    offset: int = 0,
) -> WatchedTvEpisodeLibraryListResponse:
    user = db.scalar(select(AppUser).where(AppUser.username == require_text(username, "username")))
    if user is None:
        return WatchedTvEpisodeLibraryListResponse(items=[])

    safe_limit = max(1, min(limit, 500))
    safe_offset = max(0, offset)

    rows = db.execute(
        select(TvEpisodeWatch, MediaItem)
        .join(MediaItem, MediaItem.id == TvEpisodeWatch.media_item_id)
        .where(
            TvEpisodeWatch.user_id == user.id,
            MediaItem.media_type == "tv",
        )
        .order_by(TvEpisodeWatch.watched_at.desc())
        .limit(safe_limit)
        .offset(safe_offset),
    ).all()

    return WatchedTvEpisodeLibraryListResponse(
        items=[
            WatchedTvEpisodeLibraryItem(
                media=serialize_media_item(media_item),
                seasonNumber=watch.season_number,
                episodeNumber=watch.episode_number,
                watchedAt=_iso_z(watch.watched_at),
            )
            for watch, media_item in rows
        ],
    )


def list_tv_fully_watched_series_library(
    db: Session,
    *,
    username: str,
    limit: int = 500,
) -> BackendTrackingListResponse:
    """TV shows fully watched — reads cached [tv_fully_watched] on tracking rows."""
    normalized_username = require_text(username, "username")
    user = db.scalar(select(AppUser).where(AppUser.username == normalized_username))
    if user is None:
        return BackendTrackingListResponse(items=[])

    safe_limit = max(1, min(limit, 2000))
    rows = db.execute(
        select(TrackingEntry, MediaItem)
        .join(MediaItem, MediaItem.id == TrackingEntry.media_item_id)
        .where(
            TrackingEntry.user_id == user.id,
            TrackingEntry.tv_fully_watched.is_(True),
            MediaItem.media_type == "tv",
        )
        .order_by(TrackingEntry.updated_at.desc())
        .limit(safe_limit),
    ).all()

    out: list[BackendTrackingResponse] = []
    for entry, media_item in rows:
        ec = count_tv_episode_watches_for_user_media(
            db,
            user_id=user.id,
            media_item_id=media_item.id,
        )
        out.append(
            serialize_tracking_entry(
                entry,
                user,
                media_item,
                episode_watched_count=ec,
            ),
        )
    return BackendTrackingListResponse(items=out)


def put_tv_episode_watch(
    db: Session,
    payload: TvEpisodeWatchPutRequest,
    *,
    commit: bool = True,
) -> TvEpisodeWatchPutResponse:
    username = require_text(payload.username, "username")
    media_id = require_text(payload.mediaId, "mediaId")
    if payload.seasonNumber < 0 or payload.episodeNumber < 0:
        raise HTTPException(status_code=400, detail="Season and episode numbers must be non-negative.")

    user = db.scalar(select(AppUser).where(AppUser.username == username))
    if user is None:
        raise HTTPException(status_code=404, detail="Backend user not found.")

    media_item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if media_item is None:
        raise HTTPException(status_code=404, detail="Backend media item not found.")
    if media_item.media_type != "tv":
        raise HTTPException(status_code=400, detail="Episode watches are only supported for TV media.")

    if not payload.watched:
        db.execute(
            delete(TvEpisodeWatch).where(
                TvEpisodeWatch.user_id == user.id,
                TvEpisodeWatch.media_item_id == media_item.id,
                TvEpisodeWatch.season_number == payload.seasonNumber,
                TvEpisodeWatch.episode_number == payload.episodeNumber,
            ),
        )
        merge_tv_episode_user_state_from_put(db, user=user, media_item=media_item, payload=payload)
        if commit:
            db.commit()
        else:
            db.flush()
        return TvEpisodeWatchPutResponse(
            seasonNumber=payload.seasonNumber,
            episodeNumber=payload.episodeNumber,
            watched=False,
            watchedAt=None,
        )

    row = db.scalar(
        select(TvEpisodeWatch).where(
            TvEpisodeWatch.user_id == user.id,
            TvEpisodeWatch.media_item_id == media_item.id,
            TvEpisodeWatch.season_number == payload.seasonNumber,
            TvEpisodeWatch.episode_number == payload.episodeNumber,
        ),
    )
    raw_at = payload.watchedAt
    watched_at: datetime | None = None
    if raw_at is not None and str(raw_at).strip():
        watched_at = _parse_completed_at(str(raw_at).strip())
        if watched_at is None:
            raise HTTPException(status_code=400, detail="Invalid watchedAt datetime.")
    stamp = watched_at if watched_at is not None else datetime.now(tz=UTC)
    if row is None:
        row = TvEpisodeWatch(
            user_id=user.id,
            media_item_id=media_item.id,
            season_number=payload.seasonNumber,
            episode_number=payload.episodeNumber,
            watched_at=stamp,
        )
        db.add(row)
    else:
        row.watched_at = stamp
    ensure_tv_tracking_row_for_episode_progress(db, user_id=user.id, media_item=media_item)
    merge_tv_episode_user_state_from_put(db, user=user, media_item=media_item, payload=payload)
    if commit:
        db.commit()
        db.refresh(row)
    else:
        db.flush()
    return TvEpisodeWatchPutResponse(
        seasonNumber=row.season_number,
        episodeNumber=row.episode_number,
        watched=True,
        watchedAt=_iso_z(row.watched_at),
    )


def put_tv_episode_watch_with_refresh(
    db: Session,
    tmdb_client: TmdbClient | None,
    payload: TvEpisodeWatchPutRequest,
) -> TvEpisodeWatchPutResponse:
    """Episode watch PUT plus cached TV progress / fully-watched update."""
    response = put_tv_episode_watch(db, payload, commit=False)
    user = db.scalar(
        select(AppUser).where(AppUser.username == require_text(payload.username, "username")),
    )
    media_item = db.scalar(select(MediaItem).where(MediaItem.id == require_text(payload.mediaId, "mediaId")))
    if user is not None and media_item is not None:
        refresh_tv_series_watch_state(
            db,
            tmdb_client,
            user_id=user.id,
            media_item=media_item,
        )
    db.commit()
    return response


_PURGE_MEDIA_TYPES = frozenset({"movie", "tv", "game", "boardgame", "book", "music"})


def _purge_media_types(payload: BackendPurgeLibraryRequest) -> set[str]:
    raw = payload.mediaTypes or []
    if not raw:
        return set(_PURGE_MEDIA_TYPES)
    normalized = {str(value).strip().lower() for value in raw if str(value).strip()}
    unknown = normalized - _PURGE_MEDIA_TYPES
    if unknown:
        allowed = ", ".join(sorted(_PURGE_MEDIA_TYPES))
        raise HTTPException(
            status_code=400,
            detail=f"Unknown mediaTypes: {', '.join(sorted(unknown))}. Allowed: {allowed}.",
        )
    return normalized


def purge_user_library(db: Session, *, payload: BackendPurgeLibraryRequest) -> BackendPurgeLibraryResponse:
    """Remove tracking (and TV episode data) for selected catalog categories."""
    username = require_text(payload.username, "username")
    user = db.scalar(select(AppUser).where(AppUser.username == username))
    if user is None:
        raise HTTPException(status_code=404, detail="Backend user not found.")
    media_types = _purge_media_types(payload)
    uid = user.id
    media_ids = select(MediaItem.id).where(MediaItem.media_type.in_(tuple(media_types)))

    n_watch = 0
    n_ep_state = 0
    n_season_state = 0
    if "tv" in media_types:
        tv_media_ids = select(MediaItem.id).where(MediaItem.media_type == "tv")
        n_watch = int(
            db.execute(
                delete(TvEpisodeWatch).where(
                    TvEpisodeWatch.user_id == uid,
                    TvEpisodeWatch.media_item_id.in_(tv_media_ids),
                ),
            ).rowcount
            or 0,
        )
        n_ep_state = int(
            db.execute(
                delete(TvEpisodeUserState).where(
                    TvEpisodeUserState.user_id == uid,
                    TvEpisodeUserState.media_item_id.in_(tv_media_ids),
                ),
            ).rowcount
            or 0,
        )
        n_season_state = int(
            db.execute(
                delete(TvSeasonUserState).where(
                    TvSeasonUserState.user_id == uid,
                    TvSeasonUserState.media_item_id.in_(tv_media_ids),
                ),
            ).rowcount
            or 0,
        )

    from .collection_service import purge_collections_for_user

    if "music" in media_types:
        db.execute(delete(UserFollow).where(UserFollow.user_id == uid))
    n_collections = purge_collections_for_user(db, user_id=uid, media_types=media_types)

    n_track = int(
        db.execute(
            delete(TrackingEntry).where(
                TrackingEntry.user_id == uid,
                TrackingEntry.media_item_id.in_(media_ids),
            ),
        ).rowcount
        or 0,
    )
    db.commit()
    labels = ", ".join(sorted(media_types))
    return BackendPurgeLibraryResponse(
        message=f"Server-side library data removed for: {labels}.",
        trackingRowsRemoved=n_track,
        tvEpisodeWatchRowsRemoved=n_watch,
        tvEpisodeUserStateRowsRemoved=n_ep_state,
        tvSeasonUserStateRowsRemoved=n_season_state,
        collectionsRemoved=n_collections,
    )
