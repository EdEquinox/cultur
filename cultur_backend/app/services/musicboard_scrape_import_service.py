"""Import albums by scraping a Musicboard.app profile with per-list Cultur mappings."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..config import Settings
from ..lastfm_client import LastfmClient
from ..musicboard_scraper import (
    MusicboardImportSource,
    MusicboardScrapeError,
    MusicboardScrapedRow,
    builtin_musicboard_sources,
    discover_musicboard_sources,
    scrape_musicboard_profile,
    scrape_musicboard_sources,
)
from ..schemas import (
    MusicboardImportBatchResponse,
    MusicboardImportMappingPayload,
    MusicboardImportPreviewResponse,
    MusicboardImportSourceResponse,
    MusicboardProfileImportRequest,
    StashImportBatchRequest,
    StashImportEntryPayload,
)
from .musicboard_import_service import (
    _MergedRow,
    _dedupe_key,
    flags_from_cultur_targets,
    flags_from_musicboard_source_file,
    import_musicboard_batch,
    import_musicboard_merged_rows,
    normalize_musicboard_cultur_target,
)

logger = logging.getLogger(__name__)


@dataclass
class _AccumulatedMusicboardAlbum:
    title: str
    artist: str | None = None
    image_url: str | None = None
    targets: set[str] = field(default_factory=set)
    source_labels: list[str] = field(default_factory=list)
    custom_list_names: list[str] = field(default_factory=list)
    score: float | None = None
    review: str | None = None
    completed_at: str | None = None
    source_file: str = "musicboard.csv"


def preview_musicboard_import(
    musicboard_username: str,
    *,
    configured_list_paths_json: str = "",
) -> MusicboardImportPreviewResponse:
    board_user = musicboard_username.strip().lstrip("@")
    if not board_user:
        raise HTTPException(status_code=400, detail="musicboardUsername is required.")
    try:
        sources = discover_musicboard_sources(
            board_user,
            configured_list_paths_json=configured_list_paths_json,
        )
    except MusicboardScrapeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    return MusicboardImportPreviewResponse(
        musicboardUsername=board_user,
        sources=[
            MusicboardImportSourceResponse(
                sourceKey=source.source_key,
                kind=source.kind,
                name=source.name,
                path=source.path,
                defaultCulturTarget=default_cultur_target(source),
            )
            for source in sources
        ],
    )


def default_cultur_target(source: MusicboardImportSource) -> str:
    if source.kind == "list":
        return "custom_list"
    return {
        "builtin:wantlist": "later",
        "builtin:albums": "owned",
        "builtin:history": "listened",
        "builtin:reviews": "rating",
    }.get(source.source_key, "later")


def import_musicboard_from_profile(
    db: Session,
    payload: MusicboardProfileImportRequest,
    *,
    settings: Settings,
    lastfm_client: LastfmClient,
) -> MusicboardImportBatchResponse:
    cultur_user = payload.username.strip()
    if not cultur_user:
        raise HTTPException(status_code=400, detail="username is required.")

    board_user = payload.musicboardUsername.strip().lstrip("@")
    if not board_user:
        raise HTTPException(status_code=400, detail="musicboardUsername is required.")

    if payload.mappings:
        return _import_with_mappings(
            db,
            payload,
            board_user=board_user,
            lastfm_client=lastfm_client,
            configured_list_paths_json=settings.musicboard_list_paths_json,
        )

    try:
        scraped = scrape_musicboard_profile(
            board_user,
            include_wantlist=payload.includeWantlist,
            include_albums=payload.includeAlbums,
            include_reviews=payload.includeReviews,
            include_history=payload.includeHistory,
        )
    except MusicboardScrapeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    if not scraped:
        raise HTTPException(
            status_code=404,
            detail="No albums found on that Musicboard profile (check username and list paths).",
        )

    entries = [_scraped_row_to_payload(row) for row in scraped]
    logger.info(
        "Musicboard profile scrape for @%s: %d rows → importing for %s",
        board_user,
        len(entries),
        cultur_user,
    )
    return import_musicboard_batch(
        db,
        StashImportBatchRequest(username=cultur_user, entries=entries),
        lastfm_client=lastfm_client,
    )


def _import_with_mappings(
    db: Session,
    payload: MusicboardProfileImportRequest,
    *,
    board_user: str,
    lastfm_client: LastfmClient,
    configured_list_paths_json: str = "",
) -> MusicboardImportBatchResponse:
    try:
        all_sources = discover_musicboard_sources(
            board_user,
            configured_list_paths_json=configured_list_paths_json,
        )
    except MusicboardScrapeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    by_key = {source.source_key: source for source in all_sources}
    mappings = _resolve_mappings(payload.mappings, by_key)
    if not mappings:
        raise HTTPException(
            status_code=400,
            detail="No import mappings selected (choose at least one source other than Skip).",
        )

    selected_sources = [by_key[key] for key in mappings if key in by_key]
    try:
        scraped = scrape_musicboard_sources(board_user, selected_sources)
    except MusicboardScrapeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    accumulated: dict[str, _AccumulatedMusicboardAlbum] = {}
    for row in scraped:
        target = mappings.get(row.source_key)
        if not target:
            continue
        source = by_key.get(row.source_key)
        if source is None:
            continue
        _accumulate_row(accumulated, row=row, source=source, target=target)

    if not accumulated:
        raise HTTPException(status_code=404, detail="No albums found for the selected sources.")

    merged = _merged_rows_from_accumulated(accumulated)
    logger.info(
        "Musicboard mapped import for @%s: %d unique albums from %d sources",
        board_user,
        len(merged),
        len(mappings),
    )

    return import_musicboard_merged_rows(
        db,
        username=payload.username.strip(),
        merged=merged,
        lastfm_client=lastfm_client,
    )


def _resolve_mappings(
    rows: list[MusicboardImportMappingPayload],
    by_key: dict[str, MusicboardImportSource],
) -> dict[str, str]:
    out: dict[str, str] = {}
    for row in rows:
        key = row.sourceKey.strip()
        target = normalize_musicboard_cultur_target(row.culturTarget)
        if not key or target == "skip" or key not in by_key:
            continue
        out[key] = target
    return out


def _accumulate_row(
    accumulated: dict[str, _AccumulatedMusicboardAlbum],
    *,
    row: MusicboardScrapedRow,
    source: MusicboardImportSource,
    target: str,
) -> None:
    title = row.title.strip()
    if row.source_file.casefold() == "musicboardreviews.csv" and row.review_target:
        title = row.review_target.strip() or title
    if not title:
        return

    artist = (row.artist or "").strip() or None
    key = _dedupe_key(title, artist, row.image_url)
    acc = accumulated.get(key)
    if acc is None:
        acc = _AccumulatedMusicboardAlbum(
            title=title,
            artist=artist,
            image_url=row.image_url,
            source_file=row.source_file,
        )
        accumulated[key] = acc

    acc.targets.add(target)
    acc.source_labels.append(source.name)
    if target == "custom_list":
        acc.custom_list_names.append(source.name)

    rating = row.rating if row.rating and row.rating > 0 else None
    if rating is not None and rating <= 5:
        rating = round(rating * 2, 2)
    if rating is not None and (acc.score is None or rating > acc.score):
        acc.score = rating
    if row.completed_at and not acc.completed_at:
        acc.completed_at = row.completed_at
    if row.review:
        if acc.review and acc.review != row.review:
            acc.review = f"{acc.review}\n\n{row.review}"
        else:
            acc.review = row.review


def _merged_rows_from_accumulated(
    accumulated: dict[str, _AccumulatedMusicboardAlbum],
) -> dict[str, _MergedRow]:
    merged: dict[str, _MergedRow] = {}
    for acc in accumulated.values():
        key = _dedupe_key(acc.title, acc.artist, acc.image_url)
        merged[key] = _MergedRow(
            source_file=acc.source_file,
            title=acc.title,
            artist=acc.artist,
            image_url=acc.image_url,
            flags=flags_from_cultur_targets(acc.targets),
            score=acc.score,
            review=acc.review,
            completed_at=acc.completed_at,
            custom_list_names=list(dict.fromkeys(acc.custom_list_names)) or None,
        )
    return merged


def _scraped_row_to_payload(row: MusicboardScrapedRow) -> StashImportEntryPayload:
    title = row.title.strip()
    if row.source_file.casefold() == "musicboardreviews.csv" and row.review_target:
        title = row.review_target.strip() or title

    flags = flags_from_musicboard_source_file(row.source_file)
    rating = row.rating if row.rating and row.rating > 0 else None
    if rating is not None and rating <= 5:
        rating = round(rating * 2, 2)

    return StashImportEntryPayload(
        sourceFile=row.source_file,
        title=title,
        artist=(row.artist or "").strip() or None,
        imageUrl=row.image_url,
        flags=flags,
        score=rating,
        review=row.review,
        completedAt=row.completed_at,
    )
