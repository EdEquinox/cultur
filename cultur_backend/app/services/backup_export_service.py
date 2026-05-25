"""Export Cultur library data as SeriesGuide / AVA-compatible backup JSON (v1)."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from ..backend_models import (
    AppUser,
    MediaItem,
    TrackingEntry,
    TvEpisodeUserState,
    TvEpisodeWatch,
    TvSeasonUserState,
)
from ..schemas import AvaBackupExportResponse
from ..validation import require_text

from .backup_import_service import _coerce_tmdb_id
from .catalog_service import (
    _is_dropped_tracking,
    _is_watchlist_tracking,
    _is_watched_tracking,
    _tracking_flags,
)


def _dt_to_epoch_ms(value: datetime | None) -> int | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return int(value.timestamp() * 1000)


def _rating_block(score: float | None, rated_at: datetime | None) -> dict[str, Any] | None:
    if score is None:
        return None
    block: dict[str, Any] = {"rating": score}
    ms = _dt_to_epoch_ms(rated_at)
    if ms is not None:
        block["ratedAt"] = ms
    return block


def _watchlist_block(active: bool, watchlisted_at: datetime | None) -> dict[str, Any] | None:
    if not active:
        return None
    block: dict[str, Any] = {}
    ms = _dt_to_epoch_ms(watchlisted_at)
    if ms is not None:
        block["watchlistedAt"] = ms
    return block


def _tmdb_id_from_media(media: MediaItem) -> int | None:
    if (media.source or "").strip().lower() != "tmdb":
        return None
    return _coerce_tmdb_id(media.external_id)


def _movie_row_from_tracking(entry: TrackingEntry) -> dict[str, Any] | None:
    media = entry.media_item
    tmdb_id = _tmdb_id_from_media(media)
    if tmdb_id is None:
        return None

    flags = _tracking_flags(entry.notes)
    row: dict[str, Any] = {"tmdbId": tmdb_id}

    if "collected" in flags:
        row["collection"] = True
    if _is_watchlist_tracking(entry.status, entry.notes):
        row["in_watchlist"] = True
        row["watchlist"] = True
    if _is_watched_tracking(entry.status, entry.notes):
        row["watched"] = True
        ms = _dt_to_epoch_ms(entry.completed_at or entry.updated_at)
        if ms is not None:
            row["watchHistory"] = [{"watchedAt": ms}]
    if entry.score is not None:
        row["rating"] = _rating_block(entry.score, entry.updated_at)
    if entry.progress is not None:
        row["progress"] = entry.progress

    return row


def _show_row_from_tracking(entry: TrackingEntry) -> dict[str, Any] | None:
    media = entry.media_item
    tmdb_id = _tmdb_id_from_media(media)
    if tmdb_id is None:
        return None

    flags = _tracking_flags(entry.notes)
    row: dict[str, Any] = {"tmdbId": tmdb_id}

    if _is_watchlist_tracking(entry.status, entry.notes):
        row["in_watchlist"] = True
        row["watchlist"] = True
    if _is_dropped_tracking(entry.status, entry.notes):
        row["progressHidden"] = True
    if entry.tv_fully_watched and _is_watched_tracking(entry.status, entry.notes):
        row["watched"] = True
    if entry.score is not None:
        row["rating"] = _rating_block(entry.score, entry.updated_at)
    if entry.progress is not None:
        row["progress"] = entry.progress

    return row


def _episode_row_from_watch(
    *,
    tmdb_id: int,
    season_number: int,
    episode_number: int,
    watched_at: datetime,
    user_state: TvEpisodeUserState | None,
) -> dict[str, Any]:
    row: dict[str, Any] = {
        "tmdbId": tmdb_id,
        "seasonNumber": season_number,
        "episodeNumber": episode_number,
        "watchHistory": [{"watchedAt": _dt_to_epoch_ms(watched_at)}],
    }
    if user_state is not None:
        if user_state.rating is not None:
            row["rating"] = _rating_block(user_state.rating, user_state.rating_rated_at)
        wl = _watchlist_block(user_state.watchlist, user_state.watchlisted_at)
        if wl is not None:
            row["watchlist"] = wl
    return row


def _season_row_from_state(
    *,
    tmdb_id: int,
    season_number: int,
    state: TvSeasonUserState,
) -> dict[str, Any] | None:
    rating = _rating_block(state.rating, state.rating_rated_at)
    wl = _watchlist_block(state.watchlist, state.watchlisted_at)
    if rating is None and wl is None:
        return None
    row: dict[str, Any] = {
        "tmdbId": tmdb_id,
        "seasonNumber": season_number,
    }
    if rating is not None:
        row["rating"] = rating
    if wl is not None:
        row["watchlist"] = wl
    return row


def export_ava_backup_v1(db: Session, *, username: str) -> AvaBackupExportResponse:
    """Build AVA v1 backup JSON from server-side tracking and TV watch data."""
    user_key = require_text(username, "username")
    user = db.scalar(select(AppUser).where(AppUser.username == user_key))
    if user is None:
        raise HTTPException(status_code=404, detail="Backend user not found.")

    tracking_rows = db.scalars(
        select(TrackingEntry)
        .where(TrackingEntry.user_id == user.id)
        .options(joinedload(TrackingEntry.media_item)),
    ).all()

    ep_states = db.scalars(
        select(TvEpisodeUserState).where(TvEpisodeUserState.user_id == user.id),
    ).all()
    ep_state_by_key: dict[tuple[str, int, int], TvEpisodeUserState] = {
        (s.media_item_id, s.season_number, s.episode_number): s for s in ep_states
    }

    watches = db.scalars(
        select(TvEpisodeWatch)
        .where(TvEpisodeWatch.user_id == user.id)
        .options(joinedload(TvEpisodeWatch.media_item)),
    ).all()

    season_states = db.scalars(
        select(TvSeasonUserState).where(TvSeasonUserState.user_id == user.id),
    ).all()

    movies: list[dict[str, Any]] = []
    shows: list[dict[str, Any]] = []
    skipped_non_tmdb = 0

    for entry in tracking_rows:
        media = entry.media_item
        if _tmdb_id_from_media(media) is None:
            skipped_non_tmdb += 1
            continue
        if media.media_type == "movie":
            row = _movie_row_from_tracking(entry)
            if row is not None:
                movies.append(row)
        elif media.media_type == "tv":
            row = _show_row_from_tracking(entry)
            if row is not None:
                shows.append(row)

    episodes: list[dict[str, Any]] = []
    for watch in watches:
        media = watch.media_item
        tmdb_id = _tmdb_id_from_media(media)
        if tmdb_id is None:
            skipped_non_tmdb += 1
            continue
        key = (watch.media_item_id, watch.season_number, watch.episode_number)
        state = ep_state_by_key.get(key)
        episodes.append(
            _episode_row_from_watch(
                tmdb_id=tmdb_id,
                season_number=watch.season_number,
                episode_number=watch.episode_number,
                watched_at=watch.watched_at,
                user_state=state,
            ),
        )

    seasons: list[dict[str, Any]] = []
    media_by_id = {m.id: m for entry in tracking_rows for m in [entry.media_item]}
    for m in watches:
        media_by_id[m.media_item_id] = m.media_item
    for state in season_states:
        media = media_by_id.get(state.media_item_id)
        if media is None:
            media = db.get(MediaItem, state.media_item_id)
        if media is None:
            continue
        tmdb_id = _tmdb_id_from_media(media)
        if tmdb_id is None:
            skipped_non_tmdb += 1
            continue
        row = _season_row_from_state(
            tmdb_id=tmdb_id,
            season_number=state.season_number,
            state=state,
        )
        if row is not None:
            seasons.append(row)

    exported_at = datetime.now(tz=UTC).isoformat().replace("+00:00", "Z")
    backup: dict[str, Any] = {
        "exportVersion": 1,
        "exportedAt": exported_at,
        "source": "cultur",
        "username": user_key,
        "movies": movies,
        "shows": shows,
        "episodes": episodes,
        "seasons": seasons,
        "lists": [],
    }

    return AvaBackupExportResponse(
        ok=True,
        message=(
            f"Exported {len(movies)} movies, {len(shows)} shows, {len(episodes)} episode watches, "
            f"{len(seasons)} season states."
        ),
        backup=backup,
        moviesExported=len(movies),
        showsExported=len(shows),
        episodesExported=len(episodes),
        seasonsExported=len(seasons),
        skippedNonTmdb=skipped_non_tmdb,
    )
