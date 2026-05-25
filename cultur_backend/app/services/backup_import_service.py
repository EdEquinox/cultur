"""Import user libraries from third-party backup JSON (v1: `.avabackup` / SeriesGuide-style schema)."""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..backend_models import AppUser, MediaItem, TrackingEntry
from ..schemas import (
    AvaBackupImportRequest,
    AvaBackupImportResponse,
    BackendMediaResponse,
    BackendTrackingUpsertRequest,
    ImportedBackupListPayload,
    TvEpisodeWatchPutRequest,
)
from ..tmdb_client import TmdbClient
from ..validation import require_text

from . import backend_service
from .catalog_service import upsert_tmdb_movie, upsert_tmdb_tv_show
from .import_pending_service import (
    IMPORT_PENDING_AVA_MOVIE_SOURCE,
    IMPORT_PENDING_AVA_TV_SOURCE,
    upsert_pending_import_item,
)

logger = logging.getLogger(__name__)

_FLAG_PREFIX = "[cult.flags]"


def _ms_to_utc(ms: object) -> datetime | None:
    if not isinstance(ms, (int, float)):
        return None
    try:
        return datetime.fromtimestamp(float(ms) / 1000.0, tz=UTC)
    except (OSError, OverflowError, ValueError):
        return None


def _compose_flag_notes(flags: set[str]) -> str | None:
    if not flags:
        return None
    return f"{_FLAG_PREFIX}{','.join(sorted(flags))}"


def _coerce_tmdb_id(raw: object) -> int | None:
    """Backups may use int or string TMDB ids (e.g. JSON number vs string)."""
    if isinstance(raw, int) and raw > 0:
        return raw
    if isinstance(raw, str) and raw.strip().isdigit():
        v = int(raw.strip())
        return v if v > 0 else None
    return None


def _row_tmdb_id_any(row: dict[str, Any]) -> int | None:
    """AVA uses ``tmdbId``; SeriesGuide JSON export uses ``tmdb_id``."""
    return _coerce_tmdb_id(row.get("tmdbId")) or _coerce_tmdb_id(row.get("tmdb_id"))


def _backup_row_display_title(row: dict[str, Any]) -> str:
    for key in ("title", "name", "movieTitle", "showTitle", "originalTitle"):
        value = row.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _flags_from_movie_backup(row: dict[str, Any]) -> set[str]:
    flags: set[str] = set()
    if row.get("collection") or row.get("in_collection") is True:
        flags.add("collected")
    wl = row.get("watchlist")
    if row.get("in_watchlist") is True or wl is True or (isinstance(wl, dict) and bool(wl)):
        flags.add("watchlist")
    hist = row.get("watchHistory")
    if isinstance(hist, list) and len(hist) > 0:
        flags.add("watched")
    # Exporters often omit watchHistory but set booleans or full progress.
    if row.get("watched") is True or row.get("isWatched") is True:
        flags.add("watched")
    prog = _progress_pct_from_row(row)
    if prog is not None and prog >= 100:
        flags.add("watched")
    return flags


def _is_progress_hidden_show(row: dict[str, Any]) -> bool:
    """SeriesGuide `progressHidden`: user hid the show from progress / stopped following."""
    ph = row.get("progressHidden")
    if ph is True:
        return True
    if isinstance(ph, dict) and ph:
        return True
    if isinstance(ph, (int, float)) and ph != 0:
        return True
    return False


def _flags_from_show_backup(row: dict[str, Any]) -> set[str]:
    """Map AVA/SeriesGuide show flags — never `watched` here.

    TV **Finished** is applied after episode rows are imported, via
    `refresh_tv_series_watch_state` (all TMDB-aired episodes must be watched).
    """
    flags: set[str] = set()
    if row.get("in_watchlist") is True or row.get("watchlist"):
        flags.add("watchlist")
    if _is_progress_hidden_show(row):
        flags.add("dropped")
    return flags


def _season_episode_from_nested(obj: object) -> tuple[int, int] | None:
    if not isinstance(obj, dict):
        return None
    sn = obj.get("seasonNumber")
    en = obj.get("episodeNumber")
    if sn is None:
        sn = obj.get("season")
    if en is None:
        en = obj.get("episode")
    if isinstance(sn, int) and isinstance(en, int) and sn >= 0 and en >= 0:
        return (sn, en)
    if isinstance(sn, str) and sn.strip().isdigit() and isinstance(en, str) and en.strip().isdigit():
        return (int(sn), int(en))
    return None


def _last_watched_episode_from_show_row(row: dict[str, Any]) -> tuple[int, int] | None:
    """AVA/SeriesGuide sometimes stores last watched S/E on the show row without per-episode watchHistory."""
    for key in (
        "lastWatchedEpisode",
        "lastWatched",
        "last_watched_episode",
        "lastWatchedEpisodeToAir",
        "lastEpisode",
    ):
        pair = _season_episode_from_nested(row.get(key))
        if pair is not None:
            return pair
    sn = row.get("lastWatchedSeasonNumber")
    en = row.get("lastWatchedEpisodeNumber")
    if sn is None:
        sn = row.get("lastWatchedSeason")
    if en is None:
        en = row.get("lastWatchedEp")
    if isinstance(sn, int) and isinstance(en, int) and sn >= 0 and en >= 0:
        return (sn, en)
    return None


def _status_from_flags(flags: set[str]) -> str:
    if "watched" in flags:
        return "Completed"
    if "dropped" in flags:
        return "Dropped"
    if "watchlist" in flags:
        return "Planning"
    return "In progress"


def _progress_pct_from_row(row: dict[str, Any]) -> int | None:
    """SeriesGuide-style progress: integer 0–100, or float fraction 0.0–1.0."""
    for key in ("progress", "watchedProgress", "userProgress"):
        raw = row.get(key)
        if raw is None or isinstance(raw, bool):
            continue
        if isinstance(raw, int):
            if 0 <= raw <= 100:
                return raw
            continue
        if isinstance(raw, float):
            v = raw
            if 0.0 <= v <= 1.0:
                return int(round(v * 100.0))
            if 0.0 < v <= 100.0:
                return int(round(v))
            continue
        if isinstance(raw, str) and raw.strip():
            try:
                v = float(raw.strip())
            except ValueError:
                continue
            if 0.0 <= v <= 1.0:
                return int(round(v * 100.0))
            if 0.0 < v <= 100.0:
                return int(round(v))
    return None


def _score_from_rating_block(rating: object) -> float | None:
    if not isinstance(rating, dict):
        return None
    raw = rating.get("rating")
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        return float(raw)
    if isinstance(raw, str) and raw.strip():
        try:
            return float(raw)
        except ValueError:
            return None
    return None


def _latest_watch_iso(watch_history: object) -> str | None:
    if not isinstance(watch_history, list) or not watch_history:
        return None
    best: datetime | None = None
    for w in watch_history:
        dt: datetime | None = None
        if isinstance(w, dict):
            dt = _ms_to_utc(w.get("watchedAt"))
        elif isinstance(w, (int, float)):
            dt = _ms_to_utc(w)
        if dt is None:
            continue
        if best is None or dt > best:
            best = dt
    if best is None:
        return None
    return best.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _movie_completed_at_iso(row: dict[str, Any]) -> str | None:
    """Best-effort finished date for a movie row when it is treated as watched."""
    iso = _latest_watch_iso(row.get("watchHistory"))
    if iso is not None:
        return iso
    for key in (
        "lastWatchedAt",
        "watchedAt",
        "lastPlayedAt",
        "updatedAt",
        "lastUpdated",
        "last_updated_ms",
    ):
        dt = _ms_to_utc(row.get(key))
        if dt is not None:
            return dt.astimezone(UTC).isoformat().replace("+00:00", "Z")
    return None


def _tracking_exists(db: Session, *, user_id: str, media_item_id: str) -> bool:
    return (
        db.scalar(
            select(TrackingEntry).where(
                TrackingEntry.user_id == user_id,
                TrackingEntry.media_item_id == media_item_id,
            ),
        )
        is not None
    )


def _format_id_sample(ids: list[int], *, max_show: int = 36) -> str:
    if not ids:
        return ""
    head = ids[:max_show]
    out = ", ".join(str(i) for i in head)
    if len(ids) > max_show:
        out += f", … (+{len(ids) - max_show} more)"
    return out


def _backup_import_warnings(
    *,
    movie_row_not_dict: int,
    movie_row_no_tmdb_id: int,
    movie_tmdb_failed_ids: list[int],
    movies_skipped_tmdb: int,
    show_prefetch_failed_ids: list[int],
    shows_skipped_tmdb: int,
    tracking_skipped_existing: int,
    show_row_no_tmdb_id: int,
    show_row_unknown_series: int,
    episode_row_not_dict: int,
    episode_row_no_show_id: int,
    episode_row_unknown_series: int,
    episode_row_bad_season_episode: int,
) -> list[str]:
    lines: list[str] = []
    if movie_row_not_dict:
        lines.append(f"{movie_row_not_dict} movie backup entr(y/ies) ignored (not a JSON object).")
    if movie_row_no_tmdb_id:
        lines.append(
            f"{movie_row_no_tmdb_id} movie row(s) skipped — missing or invalid TMDB id (`tmdbId` / `tmdb_id`).",
        )
    if movies_skipped_tmdb:
        sample = _format_id_sample(movie_tmdb_failed_ids)
        if sample:
            lines.append(
                f"{movies_skipped_tmdb} movie(s) not found on TMDB (sample ids: {sample}). "
                "Check TMDB id, API key, or network.",
            )
        else:
            lines.append(f"{movies_skipped_tmdb} movie(s) not found on TMDB.")

    if shows_skipped_tmdb:
        sample = _format_id_sample(show_prefetch_failed_ids)
        if sample:
            lines.append(
                f"{shows_skipped_tmdb} TV show(s) not found on TMDB during prefetch (sample ids: {sample}). "
                "Episodes and tracking for those ids were skipped.",
            )
        else:
            lines.append(f"{shows_skipped_tmdb} TV show(s) not found on TMDB during prefetch.")

    if show_row_no_tmdb_id:
        lines.append(f"{show_row_no_tmdb_id} show row(s) skipped — missing or invalid TMDB id.")
    if show_row_unknown_series:
        lines.append(
            f"{show_row_unknown_series} show row(s) skipped — series not in library "
            "(TMDB prefetch failed for that id).",
        )

    if episode_row_not_dict:
        lines.append(f"{episode_row_not_dict} episode entr(y/ies) ignored (not a JSON object).")
    if episode_row_no_show_id:
        lines.append(f"{episode_row_no_show_id} episode row(s) skipped — missing or invalid show TMDB id.")
    if episode_row_unknown_series:
        lines.append(
            f"{episode_row_unknown_series} episode row(s) skipped — show not in library "
            "(prefetch failed or wrong id).",
        )
    if episode_row_bad_season_episode:
        lines.append(
            f"{episode_row_bad_season_episode} episode row(s) skipped — "
            "need integer `seasonNumber` and `episodeNumber` (SeriesGuide nested exports use a different shape).",
        )

    if tracking_skipped_existing:
        lines.append(
            f"{tracking_skipped_existing} tracking update(s) skipped — "
            "`skipExistingTracking` was true and a row already existed for that title.",
        )
    return lines


def import_ava_backup_v1(
    db: Session,
    tmdb: TmdbClient,
    payload: AvaBackupImportRequest,
) -> AvaBackupImportResponse:
    """Map AVA v1 backup into Cultur `MediaItem`, `TrackingEntry`, and `TvEpisodeWatch` rows."""
    username = require_text(payload.username, "username")
    user = db.scalar(select(AppUser).where(AppUser.username == username))
    if user is None:
        raise HTTPException(status_code=404, detail="Backend user not found.")

    backup = payload.backup
    if not isinstance(backup, dict):
        raise HTTPException(status_code=400, detail="Backup payload must be a JSON object.")

    movies_list = backup["movies"] if isinstance(backup.get("movies"), list) else []
    shows_list = backup["shows"] if isinstance(backup.get("shows"), list) else []
    episodes_list = backup["episodes"] if isinstance(backup.get("episodes"), list) else []
    lists_raw = backup.get("lists")
    lists_len = len(lists_raw) if isinstance(lists_raw, list) else 0

    movie_row_not_dict = 0
    movie_row_no_tmdb_id = 0
    movie_tmdb_failed_ids: list[int] = []
    show_prefetch_failed_ids: list[int] = []
    show_row_no_tmdb_id = 0
    show_row_unknown_series = 0
    episode_row_not_dict = 0
    episode_row_no_show_id = 0
    episode_row_unknown_series = 0
    episode_row_bad_season_episode = 0

    show_tmdb_ids: set[int] = set()
    for s in shows_list:
        if isinstance(s, dict):
            tid = _row_tmdb_id_any(s)
            if tid is not None:
                show_tmdb_ids.add(tid)
    seasons_list_pre = backup["seasons"] if isinstance(backup.get("seasons"), list) else []
    for s in seasons_list_pre:
        if isinstance(s, dict):
            tid = _row_tmdb_id_any(s)
            if tid is not None:
                show_tmdb_ids.add(tid)
    for e in episodes_list:
        if isinstance(e, dict):
            tid = _row_tmdb_id_any(e)
            if tid is not None:
                show_tmdb_ids.add(tid)

    show_row_by_tmdb: dict[int, dict[str, Any]] = {}
    for srow in shows_list:
        if isinstance(srow, dict):
            tid = _row_tmdb_id_any(srow)
            if tid is not None:
                show_row_by_tmdb[tid] = srow

    media_by_show: dict[str, MediaItem] = {}
    shows_skipped = 0
    shows_pending = 0
    shows_imported = 0

    for sid in sorted(show_tmdb_ids):
        work = tmdb.fetch_tmdb_tv_minimal(tv_id=str(sid))
        if work is None:
            title = _backup_row_display_title(show_row_by_tmdb.get(sid, {})) or f"TV series (TMDB {sid})"
            _create_pending_ava_tv(
                db,
                username=username,
                tmdb_id=sid,
                title=title,
                row=show_row_by_tmdb.get(sid, {}),
            )
            shows_pending += 1
            if len(show_prefetch_failed_ids) < 120:
                show_prefetch_failed_ids.append(sid)
            continue
        item = upsert_tmdb_tv_show(db, work)
        db.flush()
        media_by_show[str(sid)] = item
        shows_imported += 1
    db.commit()

    movies_imported = 0
    movies_skipped = 0
    movies_pending = 0
    tracking_written = 0
    tracking_skipped = 0

    for row in movies_list:
        if not isinstance(row, dict):
            movie_row_not_dict += 1
            continue
        tmdb_id = _row_tmdb_id_any(row)
        if tmdb_id is None:
            title = _backup_row_display_title(row)
            if title:
                _create_pending_ava_movie(
                    db,
                    username=username,
                    tmdb_id=None,
                    title=title,
                    row=row,
                )
                movies_pending += 1
            else:
                movie_row_no_tmdb_id += 1
            continue
        mid = str(tmdb_id)
        work = tmdb.fetch_tmdb_movie_minimal(movie_id=mid)
        if work is None:
            title = _backup_row_display_title(row) or f"Movie (TMDB {tmdb_id})"
            _create_pending_ava_movie(
                db,
                username=username,
                tmdb_id=tmdb_id,
                title=title,
                row=row,
            )
            movies_pending += 1
            if len(movie_tmdb_failed_ids) < 120:
                movie_tmdb_failed_ids.append(tmdb_id)
            continue
        item = upsert_tmdb_movie(db, work)
        db.flush()
        movies_imported += 1

        flags = _flags_from_movie_backup(row)
        notes = _compose_flag_notes(flags)
        score = _score_from_rating_block(row.get("rating"))
        if score is None and isinstance(row.get("rating_user"), (int, float)):
            score = float(row["rating_user"])
        status = _status_from_flags(flags)
        completed_at = _movie_completed_at_iso(row) if "watched" in flags else None

        if payload.skipExistingTracking and _tracking_exists(db, user_id=user.id, media_item_id=item.id):
            tracking_skipped += 1
            db.commit()
            continue

        tr_req: dict[str, Any] = {
            "username": username,
            "mediaId": item.id,
            "status": status,
            "score": score,
            "notes": notes,
        }
        if completed_at is not None:
            tr_req["completedAt"] = completed_at
        prog = _progress_pct_from_row(row)
        if prog is not None:
            tr_req["progress"] = prog
        backend_service.upsert_tracking_entry(db, BackendTrackingUpsertRequest(**tr_req))
        tracking_written += 1

    for srow in shows_list:
        if not isinstance(srow, dict):
            continue
        tid = _row_tmdb_id_any(srow)
        if tid is None:
            show_row_no_tmdb_id += 1
            continue
        item = media_by_show.get(str(tid))
        if item is None:
            show_row_unknown_series += 1
            continue
        flags = _flags_from_show_backup(srow)
        score = _score_from_rating_block(srow.get("rating"))
        prog = _progress_pct_from_row(srow)
        if not flags and score is None and prog is None:
            continue
        notes = _compose_flag_notes(flags)
        status = _status_from_flags(flags)
        if payload.skipExistingTracking and _tracking_exists(db, user_id=user.id, media_item_id=item.id):
            tracking_skipped += 1
            continue
        tr_req: dict[str, Any] = {
            "username": username,
            "mediaId": item.id,
            "status": status,
            "score": score,
            "notes": notes,
        }
        if prog is not None:
            tr_req["progress"] = prog
        backend_service.upsert_tracking_entry(db, BackendTrackingUpsertRequest(**tr_req))
        tracking_written += 1

    ep_written = 0
    ep_state_written = 0
    seasons_list = backup["seasons"] if isinstance(backup.get("seasons"), list) else []
    season_state_written = 0
    media_ids_with_episode_watch_import: set[str] = set()

    for erow in episodes_list:
        if not isinstance(erow, dict):
            episode_row_not_dict += 1
            continue
        sid = _row_tmdb_id_any(erow)
        if sid is None:
            episode_row_no_show_id += 1
            continue
        item = media_by_show.get(str(sid))
        if item is None:
            episode_row_unknown_series += 1
            continue
        sn = erow.get("seasonNumber")
        en = erow.get("episodeNumber")
        if not isinstance(sn, int) or not isinstance(en, int):
            episode_row_bad_season_episode += 1
            continue

        hist = erow.get("watchHistory")
        if isinstance(hist, list) and len(hist) > 0:
            watched_iso = _latest_watch_iso(hist)
            if watched_iso is not None:
                backend_service.put_tv_episode_watch(
                    db,
                    TvEpisodeWatchPutRequest(
                        username=username,
                        mediaId=item.id,
                        seasonNumber=sn,
                        episodeNumber=en,
                        watched=True,
                        watchedAt=watched_iso,
                    ),
                    commit=False,
                )
                ep_written += 1
                media_ids_with_episode_watch_import.add(item.id)

        rating_block = erow.get("rating")
        score = _score_from_rating_block(rating_block)
        r_at = (
            _ms_to_utc(rating_block.get("ratedAt"))
            if isinstance(rating_block, dict)
            else None
        )
        wl = erow.get("watchlist")
        wl_active = isinstance(wl, dict)
        wl_at = _ms_to_utc(wl.get("watchlistedAt")) if isinstance(wl, dict) else None
        set_rating = score is not None
        set_watchlist = wl_active
        if not set_rating and not set_watchlist:
            continue
        backend_service.apply_tv_episode_user_state_from_backup(
            db,
            user_id=user.id,
            media_item_id=item.id,
            season_number=sn,
            episode_number=en,
            rating=score,
            set_rating=set_rating,
            rating_rated_at=r_at,
            watchlist=True,
            set_watchlist=set_watchlist,
            watchlisted_at=wl_at,
        )
        ep_state_written += 1

    for srow in shows_list:
        if not isinstance(srow, dict):
            continue
        tid = _row_tmdb_id_any(srow)
        if tid is None:
            continue
        item = media_by_show.get(str(tid))
        if item is None:
            continue
        if item.id in media_ids_with_episode_watch_import:
            continue
        lw = _last_watched_episode_from_show_row(srow)
        if lw is None:
            continue
        sn, en = lw
        hist = srow.get("watchHistory")
        watched_iso = _latest_watch_iso(hist) if isinstance(hist, list) else None
        if watched_iso is None:
            watched_iso = datetime(1970, 1, 1, tzinfo=UTC).isoformat().replace("+00:00", "Z")
        backend_service.put_tv_episode_watch(
            db,
            TvEpisodeWatchPutRequest(
                username=username,
                mediaId=item.id,
                seasonNumber=sn,
                episodeNumber=en,
                watched=True,
                watchedAt=watched_iso,
            ),
            commit=False,
        )
        ep_written += 1
        media_ids_with_episode_watch_import.add(item.id)

    for srow in seasons_list:
        if not isinstance(srow, dict):
            continue
        tid = _row_tmdb_id_any(srow)
        sn = srow.get("seasonNumber")
        if tid is None or not isinstance(sn, int):
            continue
        item = media_by_show.get(str(tid))
        if item is None:
            continue
        rating_block = srow.get("rating")
        score = _score_from_rating_block(rating_block)
        r_at = (
            _ms_to_utc(rating_block.get("ratedAt"))
            if isinstance(rating_block, dict)
            else None
        )
        wl = srow.get("watchlist")
        wl_active = isinstance(wl, dict)
        wl_at = _ms_to_utc(wl.get("watchlistedAt")) if isinstance(wl, dict) else None
        set_rating = score is not None
        set_watchlist = wl_active
        if not set_rating and not set_watchlist:
            continue
        backend_service.apply_tv_season_user_state_from_backup(
            db,
            user_id=user.id,
            media_item_id=item.id,
            season_number=sn,
            rating=score,
            set_rating=set_rating,
            rating_rated_at=r_at,
            watchlist=True,
            set_watchlist=set_watchlist,
            watchlisted_at=wl_at,
        )
        season_state_written += 1

    for media_id in media_ids_with_episode_watch_import:
        media_item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
        if media_item is None:
            continue
        backend_service.refresh_tv_series_watch_state(
            db,
            tmdb,
            user_id=user.id,
            media_item=media_item,
        )

    db.commit()

    imported_movie_lists: list[ImportedBackupListPayload] = []
    imported_tv_lists: list[ImportedBackupListPayload] = []
    list_item_total = 0
    if isinstance(lists_raw, list):
        from ..serializers.backend import serialize_media_item

        def _backup_list_name(raw: dict[str, Any]) -> str:
            for key in ("name", "listName", "title"):
                v = raw.get(key)
                if isinstance(v, str) and v.strip():
                    return v.strip()
            return "Imported list"

        def _backup_list_dict_entries(raw: dict[str, Any], key: str) -> list[dict[str, Any]]:
            v = raw.get(key)
            if not isinstance(v, list):
                return []
            return [x for x in v if isinstance(x, dict)]

        for raw in lists_raw:
            if not isinstance(raw, dict):
                continue
            list_name = _backup_list_name(raw)
            items_movie: list[BackendMediaResponse] = []
            items_tv: list[BackendMediaResponse] = []
            for key in ("listMovieBackups", "movieBackups"):
                for m in _backup_list_dict_entries(raw, key):
                    tmid = _row_tmdb_id_any(m)
                    if tmid is None:
                        continue
                    row_item = db.scalar(
                        select(MediaItem).where(
                            MediaItem.source == "tmdb",
                            MediaItem.media_type == "movie",
                            MediaItem.external_id == str(tmid),
                        ),
                    )
                    if row_item is None:
                        work = tmdb.fetch_tmdb_movie_minimal(movie_id=str(tmid))
                        if work is None:
                            continue
                        row_item = upsert_tmdb_movie(db, work)
                        db.flush()
                    items_movie.append(serialize_media_item(row_item))
            for key in ("listTvShowBackups", "tvShowBackups", "listShowBackups"):
                for s in _backup_list_dict_entries(raw, key):
                    tid = _row_tmdb_id_any(s)
                    if tid is None:
                        continue
                    row_item = media_by_show.get(str(tid))
                    if row_item is None:
                        work = tmdb.fetch_tmdb_tv_minimal(tv_id=str(tid))
                        if work is None:
                            continue
                        row_item = upsert_tmdb_tv_show(db, work)
                        db.flush()
                        media_by_show[str(tid)] = row_item
                    items_tv.append(serialize_media_item(row_item))
            for key in ("listEpisodeBackups", "episodeBackups"):
                for e in _backup_list_dict_entries(raw, key):
                    tid = _row_tmdb_id_any(e)
                    if tid is None:
                        continue
                    row_item = media_by_show.get(str(tid))
                    if row_item is None:
                        work = tmdb.fetch_tmdb_tv_minimal(tv_id=str(tid))
                        if work is None:
                            continue
                        row_item = upsert_tmdb_tv_show(db, work)
                        db.flush()
                        media_by_show[str(tid)] = row_item
                    items_tv.append(serialize_media_item(row_item))
            if items_movie:
                list_item_total += len(items_movie)
                imported_movie_lists.append(ImportedBackupListPayload(name=list_name, items=items_movie))
            if items_tv:
                list_item_total += len(items_tv)
                imported_tv_lists.append(ImportedBackupListPayload(name=list_name, items=items_tv))

    imported_list_payloads = len(imported_movie_lists) + len(imported_tv_lists)

    import_warnings = _backup_import_warnings(
        movie_row_not_dict=movie_row_not_dict,
        movie_row_no_tmdb_id=movie_row_no_tmdb_id,
        movie_tmdb_failed_ids=movie_tmdb_failed_ids,
        movies_skipped_tmdb=movies_skipped,
        show_prefetch_failed_ids=show_prefetch_failed_ids,
        shows_skipped_tmdb=shows_skipped,
        tracking_skipped_existing=tracking_skipped,
        show_row_no_tmdb_id=show_row_no_tmdb_id,
        show_row_unknown_series=show_row_unknown_series,
        episode_row_not_dict=episode_row_not_dict,
        episode_row_no_show_id=episode_row_no_show_id,
        episode_row_unknown_series=episode_row_unknown_series,
        episode_row_bad_season_episode=episode_row_bad_season_episode,
    )

    logger.info(
        "AVA backup import for %s: movies=%s skipped_tmdb=%s shows=%s skipped_tmdb=%s "
        "tracking=%s skipped=%s episodes=%s ep_user_state=%s season_user_state=%s lists=%s "
        "imported_movie_lists=%s imported_tv_lists=%s list_items=%s",
        username,
        movies_imported,
        movies_skipped,
        shows_imported,
        shows_skipped,
        tracking_written,
        tracking_skipped,
        ep_written,
        ep_state_written,
        season_state_written,
        lists_len,
        len(imported_movie_lists),
        len(imported_tv_lists),
        list_item_total,
    )

    return AvaBackupImportResponse(
        message="Import finished.",
        moviesImported=movies_imported,
        moviesSkippedTmdb=movies_skipped,
        moviesPending=movies_pending,
        showsImported=shows_imported,
        showsSkippedTmdb=shows_skipped,
        showsPending=shows_pending,
        trackingWritten=tracking_written,
        trackingSkippedExisting=tracking_skipped,
        episodeWatchesWritten=ep_written,
        curatedListsDetected=lists_len,
        seasonUserStatesWritten=season_state_written,
        episodeUserStatesWritten=ep_state_written,
        importedListCount=imported_list_payloads,
        importedListItemCount=list_item_total,
        importedMovieLists=imported_movie_lists,
        importedTvLists=imported_tv_lists,
        importWarnings=import_warnings,
    )


def _create_pending_ava_movie(
    db: Session,
    *,
    username: str,
    tmdb_id: int | None,
    title: str,
    row: dict[str, Any],
) -> None:
    dedupe = f"ava-movie:{tmdb_id or 'no-id'}:{title.casefold()}"
    media = upsert_pending_import_item(
        db,
        media_type="movie",
        source=IMPORT_PENDING_AVA_MOVIE_SOURCE,
        dedupe_key=dedupe,
        title=title,
        import_source="ava",
        import_meta={
            "avaBackupHint": "AVA / SeriesGuide backup",
            "tmdbId": tmdb_id,
        },
    )
    flags = _flags_from_movie_backup(row)
    if not flags:
        flags = {"watchlist"}
    backend_service.upsert_tracking_entry(
        db,
        BackendTrackingUpsertRequest(
            username=username,
            mediaId=str(media.id),
            status=_status_from_flags(flags),
            score=_score_from_rating_block(row.get("rating")),
            notes=_compose_flag_notes(flags),
            completedAt=_movie_completed_at_iso(row) if "watched" in flags else None,
        ),
    )


def _create_pending_ava_tv(
    db: Session,
    *,
    username: str,
    tmdb_id: int,
    title: str,
    row: dict[str, Any],
) -> None:
    dedupe = f"ava-tv:{tmdb_id}:{title.casefold()}"
    media = upsert_pending_import_item(
        db,
        media_type="tv",
        source=IMPORT_PENDING_AVA_TV_SOURCE,
        dedupe_key=dedupe,
        title=title,
        import_source="ava",
        import_meta={
            "avaBackupHint": "AVA / SeriesGuide backup",
            "tmdbId": tmdb_id,
        },
    )
    flags = _flags_from_show_backup(row)
    if not flags:
        flags = {"watchlist"}
    backend_service.upsert_tracking_entry(
        db,
        BackendTrackingUpsertRequest(
            username=username,
            mediaId=str(media.id),
            status=_status_from_flags(flags),
            score=_score_from_rating_block(row.get("rating")),
            notes=_compose_flag_notes(flags),
        ),
    )
