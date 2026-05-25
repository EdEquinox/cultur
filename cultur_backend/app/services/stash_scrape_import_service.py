"""Import games by scraping a Stash.games profile (no CSV upload)."""

from __future__ import annotations

import logging

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..config import Settings
from ..igdb_client import IgdbClient
from ..schemas import (
    StashImportBatchRequest,
    StashImportBatchResponse,
    StashImportEntryPayload,
    StashProfileImportRequest,
)
from ..stash_scraper import (
    StashCollectionPath,
    StashScrapeError,
    StashScrapedRow,
    parse_collection_paths_json,
    scrape_stash_profile,
)
from .stash_import_service import (
    flags_from_stash_collection,
    flags_from_stash_status,
    import_stash_batch,
)

logger = logging.getLogger(__name__)


def import_stash_from_profile(
    db: Session,
    payload: StashProfileImportRequest,
    *,
    settings: Settings,
    igdb_client: IgdbClient,
) -> StashImportBatchResponse:
    cultur_user = payload.username.strip()
    if not cultur_user:
        raise HTTPException(status_code=400, detail="username is required.")

    stash_user = payload.stashUsername.strip().lstrip("@")
    if not stash_user:
        raise HTTPException(status_code=400, detail="stashUsername is required.")

    collection_paths = _resolve_collection_paths(payload, settings)

    try:
        scraped = scrape_stash_profile(
            stash_user,
            collection_paths=collection_paths,
            include_reviews=payload.includeReviews,
            include_library_tabs=payload.includeLibraryTabs,
        )
    except StashScrapeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    if not scraped:
        raise HTTPException(
            status_code=404,
            detail="No games found on that Stash profile (check username and collection paths).",
        )

    entries = [_scraped_row_to_payload(row) for row in scraped]
    logger.info(
        "Stash profile scrape for @%s: %d rows → importing for %s",
        stash_user,
        len(entries),
        cultur_user,
    )

    return import_stash_batch(
        db,
        StashImportBatchRequest(username=cultur_user, entries=entries),
        igdb_client=igdb_client,
    )


def _resolve_collection_paths(
    payload: StashProfileImportRequest,
    settings: Settings,
) -> list[StashCollectionPath]:
    if payload.collectionPaths:
        out: list[StashCollectionPath] = []
        for row in payload.collectionPaths:
            key = row.key.strip()
            path = row.path.strip().lstrip("/")
            if key and path:
                out.append(StashCollectionPath(key=key, path=path))
        if not out:
            raise HTTPException(status_code=400, detail="collectionPaths is empty.")
        return out
    return parse_collection_paths_json(settings.stash_collection_paths_json)


def _scraped_row_to_payload(row: StashScrapedRow) -> StashImportEntryPayload:
    flags: set[str] = set()
    collection_key = _collection_key_from_source_file(row.source_file)
    flags.update(flags_from_stash_collection(collection_key))
    flags.update(flags_from_stash_status(row.category))
    return StashImportEntryPayload(
        sourceFile=row.source_file,
        title=row.title,
        imageUrl=row.image_url,
        flags=sorted(flags),
        score=row.rating,
        review=row.review,
    )


def _collection_key_from_source_file(source_file: str) -> str:
    base = (source_file or "").strip().casefold()
    if base.startswith("stash") and base.endswith(".csv"):
        return base[5:-4]
    return base.replace("stash", "").replace(".csv", "")
