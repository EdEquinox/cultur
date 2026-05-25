from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ...database import DatabaseManager
from ...config import Settings
from ...schemas import (
    AvaBackupExportRequest,
    AvaBackupExportResponse,
    AvaBackupImportRequest,
    AvaBackupImportResponse,
    CulturBackupV3ExportRequest,
    CulturBackupV3ExportResponse,
    CulturBackupV3ImportRequest,
    CulturBackupV3ImportResponse,
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
    TvEpisodeWatchClearSeasonRequest,
    TvEpisodeWatchClearSeasonResponse,
    TvEpisodeWatchListResponse,
    TvEpisodeWatchMarkThroughRequest,
    TvEpisodeWatchMarkThroughResponse,
    TvEpisodeWatchPutRequest,
    TvEpisodeWatchPutResponse,
    WatchedTvEpisodeLibraryListResponse,
)
from ...services import backend_service
from ...services import backup_export_service
from ...services import backup_import_service
from ...services import backup_v3_service
from ...bgg_client import BggClient
from ...tmdb_client import TmdbClient
from ...book_catalog_clients import build_book_catalog_clients
from ...igdb_client import IgdbClient
from ...schemas import (
    BggCollectionImportRequest,
    BggCollectionImportResponse,
    BookmoryImportBatchRequest,
    BookmoryImportBatchResponse,
    HardcoverImportBatchRequest,
    HardcoverImportBatchResponse,
    HardcoverImportPreviewResponse,
    CreateManualLibraryItemRequest,
    CreateManualLibraryItemResponse,
    StashImportBatchRequest,
    StashImportBatchResponse,
    MusicboardImportBatchResponse,
    MusicboardImportPreviewResponse,
    MusicboardProfileImportRequest,
    StashProfileImportRequest,
    FollowedArtistPayload,
    FollowedArtistsListResponse,
    FollowedArtistResponse,
    CollectionBulkSyncRequest,
    CollectionCreateRequest,
    CollectionListResponse,
    CollectionRenameRequest,
    CollectionResponse,
    CollectionToggleItemRequest,
    UserFollowListResponse,
    UserFollowPayload,
    UserFollowResponse,
)
from ...services import bgg_import_service
from ...services import collection_service
from ...services import user_follow_service
from ...services import bookmory_import_service
from ...services import hardcover_import_service
from ...services import import_pending_service
from ...services import musicboard_import_service
from ...services import musicboard_scrape_import_service
from ...services import stash_import_service
from ...services import stash_scrape_import_service
from ..dependencies import get_database_manager, get_db, get_settings

router = APIRouter()


@router.post("/backend/bootstrap", response_model=BackendBootstrapResponse)
def backend_bootstrap(
    payload: BackendBootstrapRequest,
    database: DatabaseManager = Depends(get_database_manager),
    db: Session = Depends(get_db),
) -> BackendBootstrapResponse:
    return backend_service.bootstrap_user(
        db,
        database_dialect=database.dialect,
        payload=payload,
    )


@router.post("/backend/media", response_model=BackendMediaResponse)
def backend_upsert_media(
    payload: BackendMediaUpsertRequest,
    db: Session = Depends(get_db),
) -> BackendMediaResponse:
    return backend_service.upsert_media_item(db, payload)


@router.get("/backend/media", response_model=BackendMediaListResponse)
def backend_list_media(
    mediaType: str | None = None,
    limit: int = 50,
    db: Session = Depends(get_db),
) -> BackendMediaListResponse:
    return backend_service.list_media_items(db, media_type=mediaType, limit=limit)


@router.put("/backend/tracking", response_model=BackendTrackingResponse)
def backend_upsert_tracking(
    payload: BackendTrackingUpsertRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> BackendTrackingResponse:
    client: TmdbClient | None = None
    if settings.tmdb_api_key:
        client = TmdbClient(
            api_key=settings.tmdb_api_key,
            language=settings.tmdb_language,
            timeout_seconds=settings.request_timeout_seconds,
        )
    return backend_service.upsert_tracking_entry(db, payload, tmdb_client=client)


@router.get("/backend/tracking/tv/episodes", response_model=TvEpisodeWatchListResponse)
def backend_list_tv_episode_watches(
    username: str,
    mediaId: str,
    db: Session = Depends(get_db),
) -> TvEpisodeWatchListResponse:
    return backend_service.list_tv_episode_watches(db, username=username, media_id=mediaId)


@router.get(
    "/backend/tracking/tv/watched-episodes",
    response_model=WatchedTvEpisodeLibraryListResponse,
)
def backend_list_tv_watched_episodes_library(
    username: str,
    limit: int = 200,
    offset: int = 0,
    db: Session = Depends(get_db),
) -> WatchedTvEpisodeLibraryListResponse:
    return backend_service.list_tv_watched_episodes_library(
        db,
        username=username,
        limit=limit,
        offset=offset,
    )


@router.get(
    "/backend/tracking/tv/fully-watched-series",
    response_model=BackendTrackingListResponse,
)
def backend_list_tv_fully_watched_series_library(
    username: str,
    limit: int = 500,
    db: Session = Depends(get_db),
) -> BackendTrackingListResponse:
    return backend_service.list_tv_fully_watched_series_library(
        db,
        username=username,
        limit=limit,
    )


@router.post("/backend/tracking/tv/recompute-series-state")
def backend_recompute_tv_series_watch_state(
    username: str,
    limit: int = 200,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> dict[str, int]:
    if not settings.tmdb_api_key:
        raise HTTPException(
            status_code=503,
            detail="TMDB is not configured. Set TMDB_API_KEY on the server.",
        )
    client = TmdbClient(
        api_key=settings.tmdb_api_key,
        language=settings.tmdb_language,
        timeout_seconds=max(30.0, settings.request_timeout_seconds),
    )
    updated = backend_service.recompute_tv_series_watch_states_for_user(
        db,
        client,
        username=username,
        limit=limit,
    )
    return {"updated": updated}


@router.put("/backend/tracking/tv/episodes", response_model=TvEpisodeWatchPutResponse)
def backend_put_tv_episode_watch(
    payload: TvEpisodeWatchPutRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> TvEpisodeWatchPutResponse:
    client: TmdbClient | None = None
    if settings.tmdb_api_key:
        client = TmdbClient(
            api_key=settings.tmdb_api_key,
            language=settings.tmdb_language,
            timeout_seconds=settings.request_timeout_seconds,
        )
    return backend_service.put_tv_episode_watch_with_refresh(db, client, payload)


@router.put("/backend/tracking/tv/episodes/mark-through", response_model=TvEpisodeWatchMarkThroughResponse)
def backend_mark_tv_episodes_through(
    payload: TvEpisodeWatchMarkThroughRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> TvEpisodeWatchMarkThroughResponse:
    if not settings.tmdb_api_key:
        raise HTTPException(
            status_code=503,
            detail="TMDB is not configured. Set TMDB_API_KEY on the server.",
        )
    client = TmdbClient(
        api_key=settings.tmdb_api_key,
        language=settings.tmdb_language,
        timeout_seconds=settings.request_timeout_seconds,
    )
    return backend_service.mark_tv_episodes_watched_through(db, client, payload)


@router.put(
    "/backend/tracking/tv/episodes/clear-season",
    response_model=TvEpisodeWatchClearSeasonResponse,
)
def backend_clear_tv_season_episode_watches(
    payload: TvEpisodeWatchClearSeasonRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> TvEpisodeWatchClearSeasonResponse:
    client: TmdbClient | None = None
    if settings.tmdb_api_key:
        client = TmdbClient(
            api_key=settings.tmdb_api_key,
            language=settings.tmdb_language,
            timeout_seconds=settings.request_timeout_seconds,
        )
    return backend_service.clear_tv_season_episode_watches(db, payload, tmdb_client=client)


@router.get("/backend/tracking", response_model=BackendTrackingListResponse)
def backend_list_tracking(
    username: str,
    mediaType: str | None = None,
    limit: int = 50,
    db: Session = Depends(get_db),
) -> BackendTrackingListResponse:
    return backend_service.list_tracking_entries(
        db,
        username=username,
        media_type=mediaType,
        limit=limit,
    )


@router.post("/backend/user/purge-library", response_model=BackendPurgeLibraryResponse)
def backend_purge_user_library(
    payload: BackendPurgeLibraryRequest,
    db: Session = Depends(get_db),
) -> BackendPurgeLibraryResponse:
    return backend_service.purge_user_library(db, payload=payload)


@router.post("/backend/import/ava-backup-v1", response_model=AvaBackupImportResponse)
def backend_import_ava_backup_v1(
    payload: AvaBackupImportRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> AvaBackupImportResponse:
    if not settings.tmdb_api_key:
        raise HTTPException(
            status_code=503,
            detail="TMDB is not configured. Set TMDB_API_KEY on the server.",
        )
    client = TmdbClient(
        api_key=settings.tmdb_api_key,
        language=settings.tmdb_language,
        timeout_seconds=max(30.0, settings.request_timeout_seconds),
    )
    return backup_import_service.import_ava_backup_v1(db, client, payload)


@router.post("/backend/import/bgg-collection", response_model=BggCollectionImportResponse)
def backend_import_bgg_collection(
    payload: BggCollectionImportRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> BggCollectionImportResponse:
    token = (settings.bgg_api_token or "").strip()
    if not token:
        raise HTTPException(
            status_code=503,
            detail=(
                "BGG is not configured. Register an application at "
                "https://boardgamegeek.com/applications and set BGG_API_TOKEN on the server."
            ),
        )
    client = BggClient(
        api_token=token,
        timeout_seconds=max(30.0, settings.request_timeout_seconds),
        min_request_interval_seconds=settings.bgg_min_request_interval_seconds,
        hot_cache_ttl_seconds=settings.bgg_hot_cache_ttl_seconds,
    )
    return bgg_import_service.import_bgg_collection(db, payload, bgg_client=client)


@router.post(
    "/backend/library/manual-item",
    response_model=CreateManualLibraryItemResponse,
)
def backend_create_manual_library_item(
    payload: CreateManualLibraryItemRequest,
    db: Session = Depends(get_db),
) -> CreateManualLibraryItemResponse:
    return import_pending_service.create_manual_library_item(db, payload)


@router.get("/backend/music/followed-artists", response_model=FollowedArtistsListResponse)
def backend_list_followed_artists(
    username: str,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> FollowedArtistsListResponse:
    return user_follow_service.list_followed_artists(db, settings, username=username)


@router.post("/backend/music/followed-artists", response_model=FollowedArtistResponse)
def backend_follow_artist(
    payload: FollowedArtistPayload,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> FollowedArtistResponse:
    return user_follow_service.follow_artist(
        db,
        settings,
        username=payload.username,
        payload=payload,
    )


@router.delete("/backend/music/followed-artists/{discogs_artist_id}", status_code=204)
def backend_unfollow_artist(
    discogs_artist_id: str,
    username: str,
    db: Session = Depends(get_db),
) -> None:
    user_follow_service.unfollow_artist(
        db,
        username=username,
        discogs_artist_id=discogs_artist_id,
    )


@router.get("/backend/follows", response_model=UserFollowListResponse)
def backend_list_follows(
    username: str,
    entityKind: str | None = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> UserFollowListResponse:
    return user_follow_service.list_user_follows(
        db,
        settings,
        username=username,
        entity_kind=entityKind,
    )


@router.post("/backend/follows", response_model=UserFollowResponse)
def backend_follow(
    payload: UserFollowPayload,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> UserFollowResponse:
    return user_follow_service.follow_user(db, settings, payload=payload)


@router.delete("/backend/follows/{person_id}", status_code=204)
def backend_unfollow(
    person_id: str,
    username: str,
    db: Session = Depends(get_db),
) -> None:
    user_follow_service.unfollow_user(db, username=username, person_id=person_id)


@router.get("/backend/collections", response_model=CollectionListResponse)
def backend_list_collections(
    username: str,
    mediaType: str,
    db: Session = Depends(get_db),
) -> CollectionListResponse:
    return collection_service.list_collections(db, username=username, media_type=mediaType)


@router.get("/backend/collections/{collection_id}", response_model=CollectionResponse)
def backend_get_collection(
    collection_id: str,
    username: str,
    db: Session = Depends(get_db),
) -> CollectionResponse:
    return collection_service.get_collection(
        db,
        username=username,
        collection_id=collection_id,
    )


@router.post("/backend/collections", response_model=CollectionResponse)
def backend_create_collection(
    payload: CollectionCreateRequest,
    db: Session = Depends(get_db),
) -> CollectionResponse:
    return collection_service.create_collection(db, payload=payload)


@router.patch("/backend/collections/{collection_id}", response_model=CollectionResponse)
def backend_rename_collection(
    collection_id: str,
    payload: CollectionRenameRequest,
    db: Session = Depends(get_db),
) -> CollectionResponse:
    return collection_service.rename_collection(
        db,
        collection_id=collection_id,
        payload=payload,
    )


@router.delete("/backend/collections/{collection_id}", status_code=204)
def backend_delete_collection(
    collection_id: str,
    username: str,
    db: Session = Depends(get_db),
) -> None:
    collection_service.delete_collection(db, username=username, collection_id=collection_id)


@router.post("/backend/collections/{collection_id}/items/toggle", response_model=CollectionResponse)
def backend_toggle_collection_item(
    collection_id: str,
    payload: CollectionToggleItemRequest,
    db: Session = Depends(get_db),
) -> CollectionResponse:
    return collection_service.toggle_collection_item(
        db,
        collection_id=collection_id,
        payload=payload,
    )


@router.put("/backend/collections/sync", response_model=CollectionListResponse)
def backend_sync_collections(
    payload: CollectionBulkSyncRequest,
    db: Session = Depends(get_db),
) -> CollectionListResponse:
    return collection_service.sync_collections(db, payload=payload)


@router.post("/backend/import/bookmory-batch", response_model=BookmoryImportBatchResponse)
def backend_import_bookmory_batch(
    payload: BookmoryImportBatchRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> BookmoryImportBatchResponse:
    clients = build_book_catalog_clients(settings)
    return bookmory_import_service.import_bookmory_batch(
        db,
        payload,
        book_clients=clients,
    )


@router.get(
    "/backend/import/hardcover-lists",
    response_model=HardcoverImportPreviewResponse,
)
def backend_preview_hardcover_lists(
    hardcover_username: str,
    settings: Settings = Depends(get_settings),
) -> HardcoverImportPreviewResponse:
    clients = build_book_catalog_clients(settings)
    client = clients.hardcover
    if client is None or not client.enabled:
        raise HTTPException(
            status_code=503,
            detail="Hardcover is not configured. Set HARDCOVER_API_TOKEN on the server.",
        )
    return hardcover_import_service.preview_hardcover_import(
        client,
        hardcover_username=hardcover_username,
    )


@router.post(
    "/backend/import/hardcover-batch",
    response_model=HardcoverImportBatchResponse,
)
def backend_import_hardcover_batch(
    payload: HardcoverImportBatchRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HardcoverImportBatchResponse:
    clients = build_book_catalog_clients(settings)
    return hardcover_import_service.import_hardcover_batch(
        db,
        payload,
        book_clients=clients,
    )


@router.post("/backend/import/stash-batch", response_model=StashImportBatchResponse)
def backend_import_stash_batch(
    payload: StashImportBatchRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> StashImportBatchResponse:
    client_id = (settings.igdb_client_id or "").strip()
    client_secret = (settings.igdb_client_secret or "").strip()
    if not client_id or not client_secret:
        raise HTTPException(
            status_code=503,
            detail="IGDB is not configured. Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET on the server.",
        )
    client = IgdbClient(
        client_id=client_id,
        client_secret=client_secret,
        language=settings.igdb_language,
        timeout_seconds=max(30.0, settings.request_timeout_seconds),
    )
    return stash_import_service.import_stash_batch(db, payload, igdb_client=client)


@router.get(
    "/backend/import/musicboard-sources",
    response_model=MusicboardImportPreviewResponse,
)
def backend_preview_musicboard_sources(
    musicboard_username: str,
    settings: Settings = Depends(get_settings),
) -> MusicboardImportPreviewResponse:
    return musicboard_scrape_import_service.preview_musicboard_import(
        musicboard_username,
        configured_list_paths_json=settings.musicboard_list_paths_json,
    )


@router.post("/backend/import/musicboard-batch", response_model=MusicboardImportBatchResponse)
def backend_import_musicboard_batch(
    payload: StashImportBatchRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> MusicboardImportBatchResponse:
    from ...services.music_catalog_service import build_lastfm_client

    client = build_lastfm_client(settings)
    if client is None:
        raise HTTPException(
            status_code=503,
            detail="Last.fm is not configured. Set LASTFM_API_KEY on the server.",
        )
    return musicboard_import_service.import_musicboard_batch(
        db,
        payload,
        lastfm_client=client,
    )


@router.post("/backend/import/musicboard-profile", response_model=MusicboardImportBatchResponse)
def backend_import_musicboard_profile(
    payload: MusicboardProfileImportRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> MusicboardImportBatchResponse:
    from ...services.music_catalog_service import build_lastfm_client

    client = build_lastfm_client(settings)
    if client is None:
        raise HTTPException(
            status_code=503,
            detail="Last.fm is not configured. Set LASTFM_API_KEY on the server.",
        )
    return musicboard_scrape_import_service.import_musicboard_from_profile(
        db,
        payload,
        settings=settings,
        lastfm_client=client,
    )


@router.post("/backend/import/stash-profile", response_model=StashImportBatchResponse)
def backend_import_stash_profile(
    payload: StashProfileImportRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> StashImportBatchResponse:
    client_id = (settings.igdb_client_id or "").strip()
    client_secret = (settings.igdb_client_secret or "").strip()
    if not client_id or not client_secret:
        raise HTTPException(
            status_code=503,
            detail="IGDB is not configured. Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET on the server.",
        )
    client = IgdbClient(
        client_id=client_id,
        client_secret=client_secret,
        language=settings.igdb_language,
        timeout_seconds=max(30.0, settings.request_timeout_seconds),
    )
    return stash_scrape_import_service.import_stash_from_profile(
        db,
        payload,
        settings=settings,
        igdb_client=client,
    )


@router.post("/backend/export/ava-backup-v1", response_model=AvaBackupExportResponse)
def backend_export_ava_backup_v1(
    payload: AvaBackupExportRequest,
    db: Session = Depends(get_db),
) -> AvaBackupExportResponse:
    return backup_export_service.export_ava_backup_v1(db, username=payload.username)


@router.post("/backend/export/cultur-backup-v3", response_model=CulturBackupV3ExportResponse)
def backend_export_cultur_backup_v3(
    payload: CulturBackupV3ExportRequest,
    db: Session = Depends(get_db),
) -> CulturBackupV3ExportResponse:
    return backup_v3_service.export_cultur_backup_v3(db, username=payload.username)


@router.post("/backend/import/cultur-backup-v3", response_model=CulturBackupV3ImportResponse)
def backend_import_cultur_backup_v3(
    payload: CulturBackupV3ImportRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> CulturBackupV3ImportResponse:
    tmdb_client = None
    if settings.tmdb_api_key:
        tmdb_client = TmdbClient(
            api_key=settings.tmdb_api_key,
            language=settings.tmdb_language,
            timeout_seconds=max(30.0, settings.request_timeout_seconds),
        )
    return backup_v3_service.import_cultur_backup_v3(
        db,
        settings,
        payload=payload,
        tmdb_client=tmdb_client,
    )
