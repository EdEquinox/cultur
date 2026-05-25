"""Placeholder catalog items from imports that could not be matched automatically."""

from __future__ import annotations

import hashlib
import logging
import uuid
from typing import Any

from fastapi import HTTPException
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from ..backend_models import AppUser, MediaItem, TrackingEntry
from ..book_catalog_clients import BookCatalogClients
from ..musicbrainz_client import (
    MbReleaseGroupSummary,
    MusicBrainzClient,
    MusicBrainzError,
    is_mb_release_group_external_id,
    normalize_mbid,
    parse_mb_release_group_external_id,
)
from ..igdb_client import IgdbClient, IgdbError
from ..schemas import (
    BackendTrackingUpsertRequest,
    CreateManualLibraryItemRequest,
    CreateManualLibraryItemResponse,
    MovieCatalogDetailResponse,
    ResolvePendingCatalogRequest,
    ResolvePendingCatalogResponse,
)
from ..serializers.catalog import (
    serialize_pending_catalog_detail,
    serialize_pending_game_catalog_detail,
)
from ..tmdb_client import TmdbClient
from . import backend_service
from .catalog_service import (
    lookup_tracking_for_catalog,
    upsert_hardcover_book,
    upsert_igdb_game,
    upsert_openlibrary_book,
    upsert_porbase_book,
    upsert_tmdb_movie,
    upsert_tmdb_tv_show,
)

_BOOK_UPSERT_BY_SOURCE = {
    "porbase": upsert_porbase_book,
    "hardcover": upsert_hardcover_book,
    "openlibrary": upsert_openlibrary_book,
}

logger = logging.getLogger(__name__)

IMPORT_PENDING_PREFIX = "import-pending"
IMPORT_PENDING_STASH_SOURCE = f"{IMPORT_PENDING_PREFIX}-stash"
IMPORT_PENDING_MUSICBOARD_SOURCE = f"{IMPORT_PENDING_PREFIX}-musicboard"
IMPORT_PENDING_BOOKMORY_SOURCE = f"{IMPORT_PENDING_PREFIX}-bookmory"
IMPORT_PENDING_AVA_MOVIE_SOURCE = f"{IMPORT_PENDING_PREFIX}-ava-movie"
IMPORT_PENDING_AVA_TV_SOURCE = f"{IMPORT_PENDING_PREFIX}-ava-tv"
IMPORT_PENDING_MANUAL_SOURCE = f"{IMPORT_PENDING_PREFIX}-manual"

_PENDING_SUBTITLE = "Pending catalog match"


def is_catalog_pending_item(item: MediaItem) -> bool:
    payload = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    if payload.get("catalogPending") is True:
        return True
    return item.source.startswith(IMPORT_PENDING_PREFIX)


def pending_external_id(dedupe_key: str) -> str:
    digest = hashlib.sha256(dedupe_key.encode("utf-8")).hexdigest()
    return digest[:32]


def upsert_pending_import_item(
    db: Session,
    *,
    media_type: str,
    source: str,
    dedupe_key: str,
    title: str,
    image_url: str | None = None,
    import_source: str,
    import_meta: dict[str, Any] | None = None,
    subtitle: str | None = None,
    description: str | None = None,
) -> MediaItem:
    mtype = media_type.strip().lower()
    external_id = pending_external_id(dedupe_key)
    item = db.scalar(
        select(MediaItem).where(
            MediaItem.source == source,
            MediaItem.media_type == mtype,
            MediaItem.external_id == external_id,
        ),
    )
    meta: dict[str, Any] = {
        "catalogPending": True,
        "importSource": import_source,
        "importDedupeKey": dedupe_key,
        **(import_meta or {}),
    }
    default_title = {
        "movie": "Unknown movie",
        "tv": "Unknown series",
        "game": "Unknown game",
        "book": "Unknown book",
        "boardgame": "Unknown board game",
        "music": "Unknown album",
    }.get(mtype, "Unknown item")
    if item is None:
        item = MediaItem(
            source=source,
            external_id=external_id,
            media_type=mtype,
            title=title.strip() or default_title,
            subtitle=subtitle or _PENDING_SUBTITLE,
            description=description,
            image_url=image_url,
            provider_payload=meta,
            is_pending=True,
        )
        db.add(item)
    else:
        item.is_pending = True
        item.title = title.strip() or item.title
        if subtitle:
            item.subtitle = subtitle
        if description:
            item.description = description
        if image_url:
            item.image_url = image_url
        old = item.provider_payload if isinstance(item.provider_payload, dict) else {}
        item.provider_payload = {**old, **meta}
    db.flush()
    return item


def upsert_pending_import_game(
    db: Session,
    *,
    source: str,
    dedupe_key: str,
    title: str,
    image_url: str | None,
    import_source: str,
    import_meta: dict[str, Any] | None = None,
) -> MediaItem:
    return upsert_pending_import_item(
        db,
        media_type="game",
        source=source,
        dedupe_key=dedupe_key,
        title=title,
        image_url=image_url,
        import_source=import_source,
        import_meta=import_meta,
    )


def get_pending_catalog_detail(
    db: Session,
    *,
    media_id: str,
    username: str | None,
) -> MovieCatalogDetailResponse:
    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is None:
        raise HTTPException(status_code=404, detail="Media item not found.")
    if not is_catalog_pending_item(item):
        raise HTTPException(status_code=400, detail="This item is not a pending import placeholder.")
    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
    if item.media_type == "game":
        return serialize_pending_game_catalog_detail(item=item, tracking=tracking)
    return serialize_pending_catalog_detail(item=item, tracking=tracking)


def get_pending_game_catalog_detail(
    db: Session,
    *,
    media_id: str,
    username: str | None,
) -> MovieCatalogDetailResponse:
    return get_pending_catalog_detail(db, media_id=media_id, username=username)


def resolve_pending_catalog(
    db: Session,
    payload: ResolvePendingCatalogRequest,
    *,
    igdb_client: IgdbClient | None = None,
    tmdb_client: TmdbClient | None = None,
    book_clients: BookCatalogClients | None = None,
    discogs_client: MusicBrainzClient | None = None,
    musicbrainz_client: MusicBrainzClient | None = None,
    lastfm_client: object | None = None,
) -> ResolvePendingCatalogResponse:
    del discogs_client, musicbrainz_client
    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="username is required.")

    pending = db.scalar(select(MediaItem).where(MediaItem.id == payload.pendingMediaId.strip()))
    if pending is None:
        raise HTTPException(status_code=404, detail="Pending media item not found.")
    if not is_catalog_pending_item(pending):
        raise HTTPException(status_code=400, detail="Media item is not a pending import placeholder.")

    resolved: MediaItem | None = None
    if payload.resolvedMediaId and payload.resolvedMediaId.strip():
        resolved = db.scalar(select(MediaItem).where(MediaItem.id == payload.resolvedMediaId.strip()))
        if resolved is None:
            raise HTTPException(status_code=404, detail="Resolved media item not found.")
    elif pending.media_type == "game":
        igdb_id = (payload.igdbExternalId or "").strip()
        if not igdb_id.isdigit():
            raise HTTPException(status_code=400, detail="igdbExternalId must be a numeric IGDB game id.")
        if igdb_client is None:
            raise HTTPException(status_code=503, detail="IGDB client is required to resolve games.")
        try:
            game = igdb_client.fetch_game_by_id(igdb_id)
        except IgdbError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        if game is None:
            raise HTTPException(status_code=404, detail="Game not found on IGDB.")
        resolved = upsert_igdb_game(db, game)
    elif pending.media_type in {"movie", "tv"}:
        tmdb_id = (payload.tmdbId or "").strip()
        if not tmdb_id.isdigit():
            raise HTTPException(status_code=400, detail="tmdbId must be a numeric TMDB id.")
        if tmdb_client is None:
            raise HTTPException(status_code=503, detail="TMDB client is required to resolve movies and TV.")
        if pending.media_type == "movie":
            work = tmdb_client.fetch_tmdb_movie_minimal(movie_id=tmdb_id)
            if work is None:
                raise HTTPException(status_code=404, detail="Movie not found on TMDB.")
            resolved = upsert_tmdb_movie(db, work)
        else:
            work = tmdb_client.fetch_tmdb_tv_minimal(tv_id=tmdb_id)
            if work is None:
                raise HTTPException(status_code=404, detail="TV show not found on TMDB.")
            resolved = upsert_tmdb_tv_show(db, work)
    elif pending.media_type == "book":
        source = (payload.resolvedSource or "").strip().lower()
        external_id = (payload.resolvedExternalId or "").strip()
        if not source or not external_id:
            raise HTTPException(
                status_code=400,
                detail="Books require resolvedSource and resolvedExternalId (e.g. hardcover + edition id).",
            )
        if book_clients is None:
            raise HTTPException(
                status_code=503,
                detail="Book catalog clients are required to resolve books from Hardcover or other sources.",
            )
        from .book_edit_service import fetch_book_snapshot_by_lookup

        snapshot = fetch_book_snapshot_by_lookup(
            book_clients,
            source=source,
            external_id=external_id,
        )
        if snapshot is None:
            raise HTTPException(status_code=404, detail="Book not found in catalog provider.")
        upsert = _BOOK_UPSERT_BY_SOURCE.get(source)
        if upsert is None:
            raise HTTPException(status_code=400, detail=f"Unsupported book catalog source: {source}")
        resolved = upsert(db, snapshot)
    elif pending.media_type == "music":
        from ..lastfm_client import (
            LastfmClient,
            LastfmError,
            is_lastfm_album_external_id,
            lastfm_album_external_id,
            parse_lfm_album_key_labels,
            parse_lastfm_album_external_id,
        )
        from .music_catalog_service import upsert_lastfm_album

        if lastfm_client is None:
            raise HTTPException(
                status_code=503,
                detail="Last.fm is not configured. Set LASTFM_API_KEY on the server.",
            )
        lfm = lastfm_client
        if not isinstance(lfm, LastfmClient):
            raise HTTPException(status_code=503, detail="Last.fm client is required to resolve albums.")

        ext_raw = (payload.resolvedExternalId or "").strip()
        if not ext_raw or not is_lastfm_album_external_id(ext_raw):
            raise HTTPException(
                status_code=400,
                detail="Provide resolvedExternalId as a Last.fm album id (lfm-album:…).",
            )
        pending_meta = (
            pending.provider_payload if isinstance(pending.provider_payload, dict) else {}
        )
        album_title = (pending.title or "").strip()
        subtitle = (pending.subtitle or "").strip()
        artist_name = str(pending_meta.get("artistName") or "").strip()
        if subtitle and subtitle != _PENDING_SUBTITLE:
            artist_name = artist_name or subtitle

        lfm_key = parse_lastfm_album_external_id(ext_raw) or ""
        path_artist, path_album = parse_lfm_album_key_labels(lfm_key)
        if path_artist:
            artist_name = path_artist
        if path_album:
            album_title = path_album

        if not artist_name and album_title:
            try:
                for row in lfm.search_catalog(album_title, limit=25):
                    if lastfm_album_external_id(row.lastfm_id) != ext_raw:
                        continue
                    artist_name = row.artist_name
                    album_title = row.title
                    break
            except LastfmError:
                pass

        if not artist_name or not album_title:
            raise HTTPException(
                status_code=400,
                detail="Pending album must include artist and title to resolve via Last.fm.",
            )
        try:
            detail = lfm.fetch_album(
                artist_name=artist_name,
                album_title=album_title,
            )
        except LastfmError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        resolved = upsert_lastfm_album(db, summary=detail, detail=detail)
    else:
        raise HTTPException(
            status_code=400,
            detail="Provide resolvedMediaId, resolvedSource/resolvedExternalId (books), igdbExternalId, or tmdbId.",
        )

    if resolved is None:
        raise HTTPException(status_code=400, detail="Could not resolve pending item.")

    _transfer_tracking(db, username=username, from_item=pending, to_item=resolved)
    _delete_pending_media_if_orphan(db, pending)
    db.commit()
    db.refresh(resolved)

    return ResolvePendingCatalogResponse(
        pendingMediaId=str(pending.id),
        resolvedMediaId=str(resolved.id),
        resolvedExternalId=resolved.external_id,
    )


def resolve_pending_import_game(
    db: Session,
    payload: ResolvePendingCatalogRequest,
    *,
    igdb_client: IgdbClient,
) -> ResolvePendingCatalogResponse:
    return resolve_pending_catalog(db, payload, igdb_client=igdb_client)


def create_manual_library_item(
    db: Session,
    payload: CreateManualLibraryItemRequest,
) -> CreateManualLibraryItemResponse:
    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="username is required.")
    media_type = payload.mediaType.strip().lower()
    if media_type not in {"movie", "tv", "game", "book", "boardgame", "music"}:
        raise HTTPException(status_code=400, detail="Unsupported mediaType.")

    title = payload.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required.")

    dedupe = f"manual:{media_type}:{title.casefold()}:{uuid.uuid4().hex[:8]}"
    item = upsert_pending_import_item(
        db,
        media_type=media_type,
        source=IMPORT_PENDING_MANUAL_SOURCE,
        dedupe_key=dedupe,
        title=title,
        image_url=(payload.imageUrl or "").strip() or None,
        import_source="manual",
        subtitle=(payload.subtitle or "").strip() or "Added manually",
        description=(payload.description or "").strip() or None,
    )
    backend_service.upsert_tracking_entry(
        db,
        BackendTrackingUpsertRequest(
            username=username,
            mediaId=str(item.id),
            status="Planning",
        ),
    )
    db.commit()
    db.refresh(item)
    return CreateManualLibraryItemResponse(mediaId=str(item.id))


def _transfer_tracking(
    db: Session,
    *,
    username: str,
    from_item: MediaItem,
    to_item: MediaItem,
) -> None:
    if str(from_item.id) == str(to_item.id):
        return

    user = db.scalar(select(AppUser).where(AppUser.username == username))
    if user is None:
        raise HTTPException(status_code=404, detail="Backend user not found.")

    source_entry = db.scalar(
        select(TrackingEntry).where(
            TrackingEntry.user_id == user.id,
            TrackingEntry.media_item_id == from_item.id,
        ),
    )
    if source_entry is None:
        return

    target_entry = db.scalar(
        select(TrackingEntry).where(
            TrackingEntry.user_id == user.id,
            TrackingEntry.media_item_id == to_item.id,
        ),
    )
    if target_entry is None:
        source_entry.media_item_id = to_item.id
        db.flush()
        return

    merged_notes = _merge_notes(target_entry.notes, source_entry.notes)
    merged_score = target_entry.score
    if source_entry.score is not None and (
        merged_score is None or float(source_entry.score) > float(merged_score)
    ):
        merged_score = source_entry.score

    backend_service.upsert_tracking_entry(
        db,
        BackendTrackingUpsertRequest(
            username=username,
            mediaId=str(to_item.id),
            status=source_entry.status or target_entry.status,
            progress=source_entry.progress if source_entry.progress is not None else target_entry.progress,
            score=merged_score,
            notes=merged_notes,
            startedAt=source_entry.started_at.isoformat() if source_entry.started_at else None,
            completedAt=source_entry.completed_at.isoformat() if source_entry.completed_at else None,
            droppedAt=source_entry.dropped_at.isoformat() if source_entry.dropped_at else None,
            collectedAt=source_entry.collected_at.isoformat() if source_entry.collected_at else None,
        ),
    )
    db.execute(
        delete(TrackingEntry).where(
            TrackingEntry.user_id == user.id,
            TrackingEntry.media_item_id == from_item.id,
        ),
    )
    db.flush()


def _merge_notes(existing: str | None, incoming: str | None) -> str | None:
    a = (existing or "").strip()
    b = (incoming or "").strip()
    if not a:
        return b or None
    if not b or b in a:
        return a or None
    if a in b:
        return b or None
    return f"{a}\n\n{b}"


def _delete_pending_media_if_orphan(db: Session, item: MediaItem) -> None:
    refs = db.scalar(
        select(TrackingEntry.id)
        .where(TrackingEntry.media_item_id == item.id)
        .limit(1),
    )
    if refs is not None:
        return
    db.delete(item)
    db.flush()
