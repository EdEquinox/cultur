from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...backend_models import MediaItem
from ...config import Settings
from ...services import catalog_service
from ...bgg_client import BggClient
from ...book_catalog_clients import BookCatalogClients, build_book_catalog_clients
from ...openlibrary_client import OpenLibraryClient
from ...igdb_client import IgdbClient
from ...tmdb_client import TmdbClient
from ...schemas import (
    BackendMediaListResponse,
    GameCatalogFiltersResponse,
    BookEditFieldsResponse,
    BookEditPatchRequest,
    BookEditSearchResponse,
    BookFieldOptionsResponse,
    GameCompanyCatalogDetailResponse,
    MovieCatalogDetailResponse,
    ApplyBookCatalogLookupRequest,
    ApplyBookCatalogLookupResponse,
    ResolvePendingCatalogRequest,
    ResolvePendingCatalogResponse,
    MovieHomeShelfResponse,
    MusicHomeResponse,
    MusicReleaseVersionsResponse,
    MovieDetailLink,
    PersonCatalogDetailResponse,
    TvEpisodeDetailResponse,
    TvLibraryHomeResponse,
    TvSeasonDetailResponse,
    TvSeasonListResponse,
    StashGameEventDetailResponse,
    StashGameEventsListResponse,
)
from ...services import music_catalog_service
from ...services.stash_events_service import get_stash_game_event_detail
from ..dependencies import get_db, get_settings

router = APIRouter()


def _igdb_client(settings: Settings) -> IgdbClient:
    client = _optional_igdb_client(settings)
    if client is None:
        raise HTTPException(
            status_code=503,
            detail="IGDB is not configured. Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET on the server.",
        )
    return client


def _openlibrary_client(settings: Settings) -> OpenLibraryClient:
    return build_book_catalog_clients(settings).openlibrary


def _book_catalog_clients(settings: Settings) -> BookCatalogClients:
    return build_book_catalog_clients(settings)


def _bgg_client(settings: Settings) -> BggClient:
    token = (settings.bgg_api_token or "").strip()
    if not token:
        raise HTTPException(
            status_code=503,
            detail=(
                "BGG is not configured. Register an application at "
                "https://boardgamegeek.com/applications and set BGG_API_TOKEN on the server."
            ),
        )
    return BggClient(
        api_token=token,
        timeout_seconds=settings.request_timeout_seconds,
        min_request_interval_seconds=settings.bgg_min_request_interval_seconds,
        hot_cache_ttl_seconds=settings.bgg_hot_cache_ttl_seconds,
    )


def _music_clients(settings: Settings):
    mb = music_catalog_service.build_musicbrainz_client(settings)
    caa = music_catalog_service.build_cover_art_client(settings, mb_client=mb)
    fanart = music_catalog_service.build_fanart_client(settings)
    lastfm = music_catalog_service.build_lastfm_client(settings)
    return mb, caa, fanart, lastfm


def _optional_igdb_client(settings: Settings) -> IgdbClient | None:
    if not settings.igdb_client_id or not settings.igdb_client_secret:
        return None
    return IgdbClient(
        client_id=settings.igdb_client_id,
        client_secret=settings.igdb_client_secret,
        language=settings.igdb_language,
        timeout_seconds=settings.request_timeout_seconds,
    )


@router.get("/catalog/games/filters", response_model=GameCatalogFiltersResponse)
def catalog_game_filters(
    settings: Settings = Depends(get_settings),
) -> GameCatalogFiltersResponse:
    client = _igdb_client(settings)
    if client is None:
        raise HTTPException(status_code=503, detail="IGDB is not configured.")
    return catalog_service.get_game_catalog_filters(client)


@router.get("/catalog/games", response_model=BackendMediaListResponse)
def catalog_games(
    section: str = "popular",
    q: str | None = None,
    page: int = 1,
    company_id: str | None = None,
    company_role: str | None = None,
    franchise_id: str | None = None,
    collection_id: str | None = None,
    platform: str | None = None,
    genre: str | None = None,
    game_mode: str | None = None,
    player_perspective: str | None = None,
    game_type: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BackendMediaListResponse:
    client = _igdb_client(settings)
    return catalog_service.list_catalog_games(
        db,
        settings,
        client,
        section=section,
        q=q,
        page=page,
        company_id=company_id,
        company_role=company_role,
        franchise_id=franchise_id,
        collection_id=collection_id,
        platform=platform,
        genre=genre,
        game_mode=game_mode,
        player_perspective=player_perspective,
        game_type=game_type,
    )


@router.get("/catalog/games/events", response_model=StashGameEventsListResponse)
def catalog_game_events(
    window: str = "upcoming",
    offset: int = 0,
    limit: int = 60,
    refresh: bool = False,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> StashGameEventsListResponse:
    return catalog_service.list_stash_game_events(
        db,
        settings,
        window=window,
        offset=offset,
        limit=limit,
        force_refresh=refresh,
        igdb_client=_igdb_client(settings),
    )


@router.get("/catalog/games/events/{slug}", response_model=StashGameEventDetailResponse)
def catalog_game_event_detail(
    slug: str,
    offset: int = 0,
    limit: int = 36,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> StashGameEventDetailResponse:
    return get_stash_game_event_detail(
        db,
        settings,
        slug=slug,
        offset=offset,
        limit=limit,
        igdb_client=_igdb_client(settings),
    )


@router.get("/catalog/games/companies/{company_id}", response_model=GameCompanyCatalogDetailResponse)
def catalog_game_company_detail(
    company_id: str,
    company_role: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> GameCompanyCatalogDetailResponse:
    client = _igdb_client(settings)
    return catalog_service.get_game_company_catalog_detail(
        db,
        settings,
        client,
        company_id=company_id,
        company_role=company_role,
    )


@router.get("/catalog/books", response_model=BackendMediaListResponse)
def catalog_books(
    section: str = "popular",
    q: str | None = None,
    page: int = 1,
    limit: int = 24,
    language: str | None = None,
    year: str | None = None,
    genre: str | None = None,
    sources: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BackendMediaListResponse:
    clients = _book_catalog_clients(settings)
    return catalog_service.list_catalog_books(
        db,
        settings,
        clients,
        section=section,
        q=q,
        page=page,
        limit=limit,
        language=language,
        year=year,
        genre=genre,
        sources=sources,
    )


@router.get(
    "/catalog/books/series/{series_id}",
    response_model=GameCompanyCatalogDetailResponse,
)
def catalog_book_series_detail(
    series_id: str,
    series_name: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> GameCompanyCatalogDetailResponse:
    clients = _book_catalog_clients(settings)
    return catalog_service.get_book_series_catalog_detail(
        db,
        settings,
        clients,
        series_id=series_id,
        series_name=series_name,
    )


@router.get(
    "/catalog/books/publishers/{publisher_id:path}",
    response_model=GameCompanyCatalogDetailResponse,
)
def catalog_book_publisher_detail(
    publisher_id: str,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> GameCompanyCatalogDetailResponse:
    clients = _book_catalog_clients(settings)
    return catalog_service.get_book_publisher_catalog_detail(
        db,
        settings,
        clients,
        publisher_id=publisher_id,
    )


@router.get("/catalog/books/edit-search", response_model=BookEditSearchResponse)
def catalog_book_edit_search(
    q: str,
    limit: int = 20,
    sources: str | None = None,
    settings: Settings = Depends(get_settings),
) -> BookEditSearchResponse:
    clients = _book_catalog_clients(settings)
    return catalog_service.search_books_for_edit(
        clients,
        query=q,
        limit=limit,
        sources=sources,
    )


@router.get("/catalog/books/{media_id}/edit", response_model=BookEditFieldsResponse)
def catalog_book_edit_fields(
    media_id: str,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BookEditFieldsResponse:
    return catalog_service.get_book_edit_fields(db, media_id=media_id)


@router.get(
    "/catalog/books/{media_id}/fields/{field_key}/options",
    response_model=BookFieldOptionsResponse,
)
def catalog_book_field_options(
    media_id: str,
    field_key: str,
    lookupSource: str | None = None,
    lookupExternalId: str | None = None,
    lookupIsbn: str | None = None,
    lookupTitle: str | None = None,
    lookupAuthors: str | None = None,
    search: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BookFieldOptionsResponse:
    clients = _book_catalog_clients(settings)
    return catalog_service.get_book_field_options(
        db,
        clients,
        media_id=media_id,
        field_key=field_key,
        lookup_source=lookupSource,
        lookup_external_id=lookupExternalId,
        lookup_isbn=lookupIsbn,
        lookup_title=lookupTitle,
        lookup_authors=lookupAuthors,
        search_query=search,
    )


@router.patch("/catalog/books/{media_id}", response_model=MovieCatalogDetailResponse)
def catalog_book_patch(
    media_id: str,
    payload: BookEditPatchRequest,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieCatalogDetailResponse:
    clients = _book_catalog_clients(settings)
    return catalog_service.patch_book_catalog_edit(
        db,
        settings,
        clients,
        media_id=media_id,
        payload=payload,
        username=username,
    )


@router.get("/catalog/books/{media_id}", response_model=MovieCatalogDetailResponse)
def catalog_book_detail(
    media_id: str,
    username: str | None = None,
    refresh: bool = False,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieCatalogDetailResponse:
    clients = _book_catalog_clients(settings)
    return catalog_service.get_book_catalog_detail(
        db,
        settings,
        clients,
        media_id=media_id,
        username=username,
        force_refresh=refresh,
    )


@router.get("/catalog/boardgames", response_model=BackendMediaListResponse)
def catalog_boardgames(
    section: str = "popular",
    q: str | None = None,
    page: int = 1,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BackendMediaListResponse:
    client = _bgg_client(settings)
    return catalog_service.list_catalog_boardgames(
        db,
        settings,
        client,
        section=section,
        q=q,
        page=page,
    )


@router.get("/catalog/boardgames/{media_id}", response_model=MovieCatalogDetailResponse)
def catalog_boardgame_detail(
    media_id: str,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieCatalogDetailResponse:
    client = _bgg_client(settings)
    return catalog_service.get_boardgame_catalog_detail(
        db,
        settings,
        client,
        media_id=media_id,
        username=username,
    )


@router.get("/catalog/games/{media_id}", response_model=MovieCatalogDetailResponse)
def catalog_game_detail(
    media_id: str,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieCatalogDetailResponse:
    client = _igdb_client(settings)
    return catalog_service.get_game_catalog_detail(
        db,
        settings,
        client,
        media_id=media_id,
        username=username,
    )


@router.post(
    "/catalog/games/{media_id}/resolve-pending",
    response_model=ResolvePendingCatalogResponse,
)
def catalog_resolve_pending_game(
    media_id: str,
    payload: ResolvePendingCatalogRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> ResolvePendingCatalogResponse:
    from ...services.import_pending_service import resolve_pending_import_game

    if payload.pendingMediaId.strip() != media_id.strip():
        raise HTTPException(
            status_code=400,
            detail="pendingMediaId must match the path media_id.",
        )
    client = _igdb_client(settings)
    return resolve_pending_import_game(db, payload, igdb_client=client)


def _tmdb_client(settings: Settings) -> TmdbClient:
    if not settings.tmdb_api_key:
        raise HTTPException(
            status_code=503,
            detail="TMDB is not configured. Set TMDB_API_KEY on the server.",
        )
    return TmdbClient(
        api_key=settings.tmdb_api_key,
        language=settings.tmdb_language,
        timeout_seconds=settings.request_timeout_seconds,
    )


def _resolve_pending_catalog_route(
    db: Session,
    settings: Settings,
    *,
    media_id: str,
    payload: ResolvePendingCatalogRequest,
    igdb_client: IgdbClient | None = None,
    tmdb_client: TmdbClient | None = None,
) -> ResolvePendingCatalogResponse:
    from ...services.import_pending_service import resolve_pending_catalog

    if payload.pendingMediaId.strip() != media_id.strip():
        raise HTTPException(
            status_code=400,
            detail="pendingMediaId must match the path media_id.",
        )
    return resolve_pending_catalog(
        db,
        payload,
        igdb_client=igdb_client,
        tmdb_client=tmdb_client,
    )


@router.post(
    "/catalog/books/{media_id}/resolve-pending",
    response_model=ResolvePendingCatalogResponse,
)
def catalog_resolve_pending_book(
    media_id: str,
    payload: ResolvePendingCatalogRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> ResolvePendingCatalogResponse:
    from ...services.import_pending_service import resolve_pending_catalog

    if payload.pendingMediaId.strip() != media_id.strip():
        raise HTTPException(
            status_code=400,
            detail="pendingMediaId must match the path media_id.",
        )
    clients = build_book_catalog_clients(settings)
    return resolve_pending_catalog(db, payload, book_clients=clients)


@router.post(
    "/catalog/books/{media_id}/apply-lookup",
    response_model=ApplyBookCatalogLookupResponse,
)
def catalog_apply_book_lookup(
    media_id: str,
    payload: ApplyBookCatalogLookupRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> ApplyBookCatalogLookupResponse:
    clients = build_book_catalog_clients(settings)
    return catalog_service.apply_book_catalog_lookup(
        db,
        clients,
        media_id=media_id,
        payload=payload,
    )


@router.post(
    "/catalog/movies/{media_id}/resolve-pending",
    response_model=ResolvePendingCatalogResponse,
)
def catalog_resolve_pending_movie(
    media_id: str,
    payload: ResolvePendingCatalogRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> ResolvePendingCatalogResponse:
    return _resolve_pending_catalog_route(
        db,
        settings,
        media_id=media_id,
        payload=payload,
        tmdb_client=_tmdb_client(settings),
    )


@router.post(
    "/catalog/tv/{media_id}/resolve-pending",
    response_model=ResolvePendingCatalogResponse,
)
def catalog_resolve_pending_tv(
    media_id: str,
    payload: ResolvePendingCatalogRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> ResolvePendingCatalogResponse:
    return _resolve_pending_catalog_route(
        db,
        settings,
        media_id=media_id,
        payload=payload,
        tmdb_client=_tmdb_client(settings),
    )


@router.get("/catalog/movies/home", response_model=MovieHomeShelfResponse)
def catalog_movies_home(
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieHomeShelfResponse:
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
    return catalog_service.list_catalog_movie_home_shelves(db, settings, client)


@router.get("/catalog/movies", response_model=BackendMediaListResponse)
def catalog_movies(
    section: str = "popular",
    q: str | None = None,
    genre: str | None = None,
    keyword: str | None = None,
    page: int = 1,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BackendMediaListResponse:
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
    return catalog_service.list_catalog_movies(
        db,
        settings,
        client,
        section=section,
        q=q,
        genre=genre,
        keyword=keyword,
        page=page,
    )


@router.get("/catalog/movies/{media_id}", response_model=MovieCatalogDetailResponse)
def catalog_movie_detail(
    media_id: str,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieCatalogDetailResponse:
    from ...services.import_pending_service import get_pending_catalog_detail, is_catalog_pending_item

    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is not None and is_catalog_pending_item(item):
        return get_pending_catalog_detail(db, media_id=media_id, username=username)

    client = _tmdb_client(settings)
    return catalog_service.get_movie_catalog_detail(
        db,
        settings,
        client,
        media_id=media_id,
        username=username,
    )


@router.get("/catalog/people/{person_id:path}", response_model=PersonCatalogDetailResponse)
def catalog_person_detail(
    person_id: str,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> PersonCatalogDetailResponse:
    from app.person_id_path import decode_person_id_from_path

    person_id = decode_person_id_from_path(person_id)

    from app.catalog_person_ids import parse_book_person_id

    parsed_book = parse_book_person_id(person_id)
    if parsed_book is not None:
        provider, external_id = parsed_book
        from app.services.book_catalog_policy import is_hardcover_primary

        if provider == "openlibrary" and is_hardcover_primary():
            raise HTTPException(
                status_code=400,
                detail="Open Library authors are disabled. Use Hardcover (hc-…) author links.",
            )
        clients = _book_catalog_clients(settings)
        if provider == "hardcover":
            return catalog_service.get_hardcover_author_catalog_detail(
                db,
                settings,
                clients,
                person_id=person_id,
                author_id=external_id,
            )
        return catalog_service.get_openlibrary_author_catalog_detail(
            db,
            settings,
            clients,
            person_id=person_id,
            author_id=external_id,
        )

    from app.lastfm_client import parse_music_artist_person_id

    artist_name, artist_mbid = parse_music_artist_person_id(person_id)
    if artist_name or artist_mbid:
        _mb, _caa, fanart, lastfm = _music_clients(settings)
        if lastfm is None:
            raise HTTPException(
                status_code=503,
                detail="Last.fm is not configured. Set LASTFM_API_KEY on the server.",
            )
        return music_catalog_service.get_lfm_artist_catalog_detail(
            db,
            lastfm,
            artist_name=artist_name,
            artist_mbid=artist_mbid,
            person_id=person_id,
            fanart=fanart,
        )

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
    book_clients = _book_catalog_clients(settings)
    return catalog_service.get_person_catalog_detail(
        db,
        settings,
        client,
        book_clients,
        person_id=person_id,
    )


@router.get("/catalog/tv/home", response_model=TvLibraryHomeResponse)
def catalog_tv_home(
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> TvLibraryHomeResponse:
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
    return catalog_service.list_catalog_tv_home_shelves(
        db,
        settings,
        client,
        username=username,
    )


@router.get("/catalog/tv", response_model=BackendMediaListResponse)
def catalog_tv(
    section: str = "popular",
    q: str | None = None,
    genre: str | None = None,
    keyword: str | None = None,
    page: int = 1,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BackendMediaListResponse:
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
    return catalog_service.list_catalog_tv_shows(
        db,
        settings,
        client,
        section=section,
        q=q,
        genre=genre,
        keyword=keyword,
        page=page,
    )


@router.get("/catalog/tv/{media_id}/seasons/{season_number}", response_model=TvSeasonDetailResponse)
def catalog_tv_season_detail(
    media_id: str,
    season_number: int,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> TvSeasonDetailResponse:
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
    return catalog_service.get_tv_season_catalog_detail(
        db,
        settings,
        client,
        media_id=media_id,
        season_number=season_number,
        username=username,
    )


@router.get(
    "/catalog/tv/{media_id}/seasons/{season_number}/episodes/{episode_number}",
    response_model=TvEpisodeDetailResponse,
)
def catalog_tv_episode_detail(
    media_id: str,
    season_number: int,
    episode_number: int,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> TvEpisodeDetailResponse:
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
    return catalog_service.get_tv_episode_catalog_detail(
        db,
        settings,
        client,
        media_id=media_id,
        season_number=season_number,
        episode_number=episode_number,
        username=username,
    )


@router.get("/catalog/tv/{media_id}/seasons", response_model=TvSeasonListResponse)
def catalog_tv_seasons(
    media_id: str,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> TvSeasonListResponse:
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
    return catalog_service.list_tv_season_catalog(
        db,
        settings,
        client,
        media_id=media_id,
    )


@router.get("/catalog/tv/{media_id}", response_model=MovieCatalogDetailResponse)
def catalog_tv_detail(
    media_id: str,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieCatalogDetailResponse:
    from ...services.import_pending_service import get_pending_catalog_detail, is_catalog_pending_item

    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is not None and is_catalog_pending_item(item):
        return get_pending_catalog_detail(db, media_id=media_id, username=username)

    client = _tmdb_client(settings)
    return catalog_service.get_tv_catalog_detail(
        db,
        settings,
        client,
        media_id=media_id,
        username=username,
    )


@router.get("/catalog/music/home", response_model=MusicHomeResponse)
def catalog_music_home(
    username: str,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MusicHomeResponse:
    _mb, _caa, _fanart, lastfm = _music_clients(settings)
    return music_catalog_service.get_music_home(
        db,
        lastfm,
        username=username,
        home_tag=settings.lastfm_home_tag,
    )


@router.get("/catalog/music/home/latest", response_model=BackendMediaListResponse)
def catalog_music_home_latest(
    username: str,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BackendMediaListResponse:
    return music_catalog_service.get_music_home_latest(db, username=username)


@router.get("/catalog/music", response_model=BackendMediaListResponse)
def catalog_music_search(
    section: str = "search",
    q: str | None = None,
    page: int = 1,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BackendMediaListResponse:
    mb, caa, _fanart, lastfm = _music_clients(settings)
    return music_catalog_service.list_catalog_music(
        db,
        mb,
        caa,
        section=section,
        q=q,
        page=page,
        lastfm=lastfm,
    )


@router.get("/catalog/music/edit-search", response_model=BookEditSearchResponse)
def catalog_music_edit_search(
    q: str,
    limit: int = 20,
    settings: Settings = Depends(get_settings),
) -> BookEditSearchResponse:
    _mb, _caa, _fanart, lastfm = _music_clients(settings)
    return music_catalog_service.search_music_for_edit(lastfm, query=q, limit=limit)


@router.get("/catalog/music/{media_id}/versions", response_model=MusicReleaseVersionsResponse)
def catalog_music_release_versions(
    media_id: str,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MusicReleaseVersionsResponse:
    mb, caa, _fanart, _lastfm = _music_clients(settings)
    return music_catalog_service.list_music_release_versions(db, mb, caa, media_id=media_id)


@router.get("/catalog/music/{media_id}", response_model=MovieCatalogDetailResponse)
def catalog_music_detail(
    media_id: str,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieCatalogDetailResponse:
    from ...services.import_pending_service import get_pending_catalog_detail, is_catalog_pending_item

    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is not None and is_catalog_pending_item(item):
        return get_pending_catalog_detail(db, media_id=media_id, username=username)

    mb, caa, fanart, lastfm = _music_clients(settings)
    return music_catalog_service.get_music_catalog_detail(
        db,
        mb,
        caa,
        media_id=media_id,
        username=username,
        lastfm=lastfm,
        fanart=fanart,
    )


@router.get("/catalog/music/{media_id}/edit", response_model=BookEditFieldsResponse)
def catalog_music_edit_fields(
    media_id: str,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BookEditFieldsResponse:
    return music_catalog_service.get_music_edit_fields(db, media_id=media_id)


@router.get(
    "/catalog/music/{media_id}/fields/{field_key}/options",
    response_model=BookFieldOptionsResponse,
)
def catalog_music_field_options(
    media_id: str,
    field_key: str,
    lookupSource: str | None = None,
    lookupExternalId: str | None = None,
    search: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> BookFieldOptionsResponse:
    _mb, _caa, _fanart, lastfm = _music_clients(settings)
    return music_catalog_service.get_music_field_options(
        db,
        lastfm,
        media_id=media_id,
        field_key=field_key,
        lookup_source=lookupSource,
        lookup_external_id=lookupExternalId,
        search_query=search,
    )


@router.patch("/catalog/music/{media_id}", response_model=MovieCatalogDetailResponse)
def catalog_music_patch(
    media_id: str,
    payload: BookEditPatchRequest,
    username: str | None = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> MovieCatalogDetailResponse:
    _mb, _caa, _fanart, lastfm = _music_clients(settings)
    return music_catalog_service.patch_music_catalog_edit(
        db,
        lastfm,
        media_id=media_id,
        payload=payload,
        username=username,
    )


@router.post(
    "/catalog/music/{media_id}/apply-lookup",
    response_model=ApplyBookCatalogLookupResponse,
)
def catalog_apply_music_lookup(
    media_id: str,
    payload: ApplyBookCatalogLookupRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> ApplyBookCatalogLookupResponse:
    _mb, _caa, _fanart, lastfm = _music_clients(settings)
    return music_catalog_service.apply_music_catalog_lookup(
        db,
        lastfm,
        media_id=media_id,
        payload=payload,
    )


@router.post(
    "/catalog/music/{media_id}/resolve-pending",
    response_model=ResolvePendingCatalogResponse,
)
def catalog_resolve_pending_music(
    media_id: str,
    payload: ResolvePendingCatalogRequest,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> ResolvePendingCatalogResponse:
    from ...services.import_pending_service import resolve_pending_catalog

    if payload.pendingMediaId.strip() != media_id.strip():
        raise HTTPException(
            status_code=400,
            detail="pendingMediaId must match the path media_id.",
        )
    _mb, _caa, _fanart, lastfm = _music_clients(settings)
    return resolve_pending_catalog(db, payload, lastfm_client=lastfm)
