from __future__ import annotations

from collections import defaultdict
from concurrent.futures import Future, ThreadPoolExecutor, as_completed
from dataclasses import dataclass, replace
from datetime import date, timezone
import logging
import time
from urllib.parse import quote, quote_plus

import requests
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..backend_models import (
    AppUser,
    MediaItem,
    TrackingEntry,
    TvEpisodeUserState,
    TvEpisodeWatch,
    TvSeasonUserState,
)
from ..config import Settings, load_settings
from ..omdb_client import OmdbClient, OmdbError, OmdbMovie
from ..schemas import (
    ApplyBookCatalogLookupRequest,
    ApplyBookCatalogLookupResponse,
    BookEditFieldsResponse,
    BookEditPatchRequest,
    BookEditSearchHit,
    BookEditSearchResponse,
    BookFieldOptionsResponse,
    BackendMediaListResponse,
    BackendMediaResponse,
    BackendTrackingResponse,
    GameCatalogFiltersResponse,
    IgdbFilterOptionResponse,
    MovieCatalogDetailResponse,
    MovieHomeShelfResponse,
    StashGameEventsListResponse,
    GameCompanyCatalogDetailResponse,
    GameCompanyCatalogItem,
    PersonCatalogDetailResponse,
    PersonFilmographyItem,
    TvLibraryHomeResponse,
    TvEpisodeCatalogResponse,
    TvEpisodeDetailResponse,
    TvNextEpisodeCardResponse,
    TvSeasonDetailResponse,
    TvSeasonListResponse,
    TvSeasonSummaryResponse,
    WatchedEpisodeResponse,
    MovieDetailMetric,
    MovieDetailLink,
)
from ..serializers.backend import (
    serialize_media_item,
    serialize_media_item_with_overlay,
    serialize_tracking_entry,
)
from ..serializers.catalog import (
    _serialize_company_catalog_item,
    serialize_company_catalog_detail,
    serialize_bgg_boardgame_catalog_detail,
    serialize_openlibrary_book_catalog_detail,
    serialize_igdb_game_catalog_detail,
    serialize_movie_catalog_detail,
    serialize_person_catalog_detail,
    serialize_tmdb_person,
)
from ..book_catalog_clients import BookCatalogClients
from ..catalog_person_ids import (
    hardcover_person_id,
    hardcover_series_key,
    parse_book_person_id,
    parse_hardcover_series_key,
)
from ..bgg_client import BggBoardgame, BggClient, BggError
from ..openlibrary_client import (
    BOOK_DETAIL_ENRICHED_KEY,
    OpenLibraryBook,
    OpenLibraryClient,
    OpenLibraryError,
    book_detail_can_use_stored_fallback,
    book_detail_response_can_use_cache,
    openlibrary_book_from_media_item,
    openlibrary_person_id,
    parse_openlibrary_person_id,
    parse_openlibrary_publisher_id,
)
from ..igdb_client import (
    IgdbClient,
    IgdbCompanyCatalogGame,
    IgdbError,
    IgdbGame,
    _parse_igdb_id_list,
)
from .stash_events_service import list_stash_game_events_cached
from ..tmdb_client import (
    TmdbClient,
    TmdbError,
    TmdbLink,
    TmdbMovie,
    TmdbMovieDetail,
    TmdbTvAiringBrief,
    TmdbTvEpisodeTeaser,
    TmdbTvSeasonSummary,
    TmdbTvShowSeasonsBundle,
    tmdb_genre_names,
)
from ..validation import optional_text

from . import backend_service

logger = logging.getLogger(__name__)

# TMDB season-detail fan-out per request; cap keeps worst-case latency bounded.
_TV_HOME_CONTINUE_SCAN_MAX = 100
_TV_HOME_NEXT_UP_LIMIT = 64


def _resolve_tv_catalog_media(db: Session, *, media_id: str) -> MediaItem:
    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is None or item.media_type != "tv":
        raise HTTPException(status_code=404, detail="TV show not found.")
    if item.source != "tmdb":
        raise HTTPException(status_code=400, detail="Only TMDB-backed TV shows are supported for now.")
    return item


def upsert_tmdb_media(db: Session, work: TmdbMovie, *, media_type: str) -> MediaItem:
    item = db.scalar(
        select(MediaItem).where(
            MediaItem.source == "tmdb",
            MediaItem.media_type == media_type,
            MediaItem.external_id == work.external_id,
        ),
    )
    if item is None:
        item = MediaItem(
            source="tmdb",
            external_id=work.external_id,
            media_type=media_type,
            title=work.title,
            subtitle=work.subtitle,
            description=work.description,
            image_url=work.image_url,
            provider_payload=dict(work.metadata),
        )
        db.add(item)
    else:
        item.title = work.title
        item.subtitle = work.subtitle
        item.description = work.description
        item.image_url = work.image_url
        old_meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
        item.provider_payload = {**old_meta, **dict(work.metadata)}
    db.flush()
    return item


def upsert_tmdb_movie(db: Session, movie: TmdbMovie) -> MediaItem:
    return upsert_tmdb_media(db, movie, media_type="movie")


def upsert_tmdb_tv_show(db: Session, show: TmdbMovie) -> MediaItem:
    return upsert_tmdb_media(db, show, media_type="tv")


def upsert_igdb_game(db: Session, game: IgdbGame) -> MediaItem:
    item = db.scalar(
        select(MediaItem).where(
            MediaItem.source == "igdb",
            MediaItem.media_type == "game",
            MediaItem.external_id == game.external_id,
        ),
    )
    if item is None:
        item = MediaItem(
            source="igdb",
            external_id=game.external_id,
            media_type="game",
            title=game.title,
            subtitle=game.subtitle,
            description=game.description,
            image_url=game.image_url,
            provider_payload=dict(game.metadata),
        )
        db.add(item)
    else:
        item.title = game.title
        item.subtitle = game.subtitle
        item.description = game.description
        item.image_url = game.image_url
        old_meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
        item.provider_payload = {**old_meta, **dict(game.metadata)}
    db.flush()
    return item


def merge_movie_data(
    movie: TmdbMovie,
    omdb_movie: OmdbMovie,
    *,
    prefer_omdb: bool,
) -> TmdbMovie:
    subtitle = omdb_movie.subtitle if prefer_omdb and omdb_movie.subtitle else movie.subtitle
    description = omdb_movie.description if prefer_omdb and omdb_movie.description else movie.description
    image_url = movie.image_url or omdb_movie.image_url
    metadata = {**movie.metadata, **{key: value for key, value in omdb_movie.metadata.items() if value}}
    return TmdbMovie(
        external_id=movie.external_id,
        title=movie.title,
        subtitle=subtitle,
        description=description,
        image_url=image_url,
        metadata=metadata,
    )


def lookup_omdb_movie(
    *,
    settings: Settings,
    title: str,
    release_date: str,
    client: OmdbClient | None = None,
) -> OmdbMovie | None:
    if not settings.omdb_api_key:
        return None

    year = release_date[:4] if len(release_date) >= 4 else None
    omdb_client = client or OmdbClient(
        api_key=settings.omdb_api_key,
        timeout_seconds=settings.request_timeout_seconds,
    )
    try:
        return omdb_client.lookup_movie(title=title, year=year)
    except (OmdbError, requests.RequestException):
        return None


def enrich_movies_with_omdb(
    movies: list[TmdbMovie],
    *,
    settings: Settings,
    prefer_omdb: bool,
) -> list[TmdbMovie]:
    if not settings.omdb_api_key:
        return movies

    client = OmdbClient(
        api_key=settings.omdb_api_key,
        timeout_seconds=settings.request_timeout_seconds,
    )
    enriched: list[TmdbMovie] = []

    for movie in movies:
        omdb_movie = lookup_omdb_movie(
            settings=settings,
            title=movie.title,
            release_date=str(movie.metadata.get("releaseDate") or "").strip(),
            client=client,
        )
        if omdb_movie is None:
            enriched.append(movie)
            continue
        enriched.append(merge_movie_data(movie, omdb_movie, prefer_omdb=prefer_omdb))

    return enriched


def lookup_tracking_for_catalog(
    db: Session,
    *,
    username: str | None,
    media_item: MediaItem,
) -> BackendTrackingResponse | None:
    normalized_username = optional_text(username)
    if normalized_username is None:
        return None

    user = db.scalar(select(AppUser).where(AppUser.username == normalized_username))
    if user is None:
        return None

    entry = db.scalar(
        select(TrackingEntry).where(
            TrackingEntry.user_id == user.id,
            TrackingEntry.media_item_id == media_item.id,
        ),
    )
    if entry is None:
        return None

    ec = 0
    if media_item.media_type == "tv":
        ec = backend_service.count_tv_episode_watches_for_user_media(
            db,
            user_id=user.id,
            media_item_id=media_item.id,
        )
    return serialize_tracking_entry(entry, user, media_item, episode_watched_count=ec)


def list_catalog_movies(
    db: Session,
    settings: Settings,
    tmdb_client: TmdbClient,
    *,
    section: str = "popular",
    q: str | None = None,
    genre: str | None = None,
    keyword: str | None = None,
    page: int = 1,
) -> BackendMediaListResponse:
    normalized_q = optional_text(q)
    normalized_genre = optional_text(genre)
    normalized_keyword = optional_text(keyword)
    movies = tmdb_client.fetch_movies(
        section=section,
        query=normalized_q,
        genre=normalized_genre,
        keyword=normalized_keyword,
        page=page,
    )
    movies = tmdb_client.enrich_movies_directors_from_credits(movies)
    # Per-movie OMDB lookups are slow (sequential HTTP). Only merge OMDB for explicit
    # title search; browse sections (now_playing, upcoming, popular, …) stay TMDB-only.
    if settings.omdb_api_key and normalized_q is not None and bool(normalized_q):
        movies = enrich_movies_with_omdb(
            movies,
            settings=settings,
            prefer_omdb=True,
        )
    items = [upsert_tmdb_movie(db, movie) for movie in movies]
    db.commit()
    for item in items:
        db.refresh(item)
    return BackendMediaListResponse(items=[serialize_media_item(item) for item in items])


def get_game_catalog_filters(igdb_client: IgdbClient) -> GameCatalogFiltersResponse:
    from ..igdb_client import IgdbError

    try:
        taxonomies = igdb_client.fetch_game_filter_options()
    except IgdbError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    def _map_options(key: str) -> list[IgdbFilterOptionResponse]:
        return [
            IgdbFilterOptionResponse(id=opt.external_id, name=opt.name)
            for opt in taxonomies.get(key, ())
        ]

    return GameCatalogFiltersResponse(
        platforms=_map_options("platforms"),
        genres=_map_options("genres"),
        gameModes=_map_options("gameModes"),
        playerPerspectives=_map_options("playerPerspectives"),
        gameTypes=_map_options("gameTypes"),
    )


def list_catalog_games(
    db: Session,
    _settings: Settings,
    igdb_client: IgdbClient,
    *,
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
) -> BackendMediaListResponse:
    normalized_q = optional_text(q)
    normalized_company_id = optional_text(company_id)
    normalized_company_role = optional_text(company_role)
    normalized_franchise_id = optional_text(franchise_id)
    normalized_collection_id = optional_text(collection_id)
    try:
        if normalized_company_id:
            games = igdb_client.fetch_games_for_company(
                normalized_company_id,
                normalized_company_role or "publisher",
            )
        elif normalized_franchise_id:
            games = igdb_client.fetch_games_for_franchise(normalized_franchise_id)
        elif normalized_collection_id:
            games = igdb_client.fetch_games_for_collection(normalized_collection_id)
        else:
            type_raw = optional_text(game_type)
            game_type_id = int(type_raw) if type_raw and type_raw.isdigit() else None
            games = igdb_client.fetch_games(
                section=section,
                query=normalized_q,
                page=page,
                platform_ids=_parse_igdb_id_list(platform),
                genre_ids=_parse_igdb_id_list(genre),
                game_mode_ids=_parse_igdb_id_list(game_mode),
                player_perspective_ids=_parse_igdb_id_list(player_perspective),
                game_type_id=game_type_id,
            )
    except IgdbError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    items = [upsert_igdb_game(db, game) for game in games]
    db.commit()
    for item in items:
        db.refresh(item)
    return BackendMediaListResponse(items=[serialize_media_item(item) for item in items])


def get_game_company_catalog_detail(
    db: Session,
    _settings: Settings,
    igdb_client: IgdbClient,
    *,
    company_id: str,
    company_role: str | None = None,
) -> GameCompanyCatalogDetailResponse:
    normalized = company_id.strip()
    if not normalized.isdigit():
        raise HTTPException(status_code=400, detail="Invalid company id.")

    role = optional_text(company_role) or "publisher"
    primary_role_label = "Developer" if role.lower() == "developer" else "Publisher"

    try:
        bundle = igdb_client.fetch_company_catalog_detail(
            normalized,
            primary_role=role,
        )
    except IgdbError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    links: list[TmdbLink] = [
        TmdbLink(
            label="IGDB",
            url=f"https://www.igdb.com/companies/{bundle.slug or bundle.company_id}",
        ),
        TmdbLink(
            label="Wikipedia",
            url=f"https://en.wikipedia.org/w/index.php?search={quote_plus(bundle.name)}",
        ),
    ]
    if bundle.website_url:
        links.append(TmdbLink(label="Website", url=bundle.website_url))

    def _build_items(
        entries: tuple[IgdbCompanyCatalogGame, ...],
    ) -> list[GameCompanyCatalogItem]:
        items: list[GameCompanyCatalogItem] = []
        seen_external_ids: set[str] = set()
        for entry in entries:
            ext = entry.game.external_id.strip()
            if not ext or ext in seen_external_ids:
                continue
            seen_external_ids.add(ext)
            item = upsert_igdb_game(db, entry.game)
            db.flush()
            items.append(
                _serialize_company_catalog_item(media=item, roles=entry.roles),
            )
        return items

    catalog = _build_items(bundle.catalog)
    popular_catalog = _build_items(bundle.popular_catalog)
    db.commit()

    return serialize_company_catalog_detail(
        bundle=bundle,
        catalog=catalog,
        popular_catalog=popular_catalog,
        links=links,
        primary_role=primary_role_label,
    )


def get_game_catalog_detail(
    db: Session,
    _settings: Settings,
    igdb_client: IgdbClient,
    *,
    media_id: str,
    username: str | None,
) -> MovieCatalogDetailResponse:
    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is None or item.media_type != "game":
        raise HTTPException(status_code=404, detail="Game not found.")

    from .import_pending_service import get_pending_game_catalog_detail, is_catalog_pending_item

    if is_catalog_pending_item(item):
        return get_pending_game_catalog_detail(db, media_id=media_id, username=username)

    if item.source != "igdb":
        raise HTTPException(status_code=400, detail="Only IGDB-backed games are supported for now.")

    try:
        game = igdb_client.fetch_game_by_id(item.external_id)
    except IgdbError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if game is None:
        raise HTTPException(status_code=404, detail="Game not found on IGDB.")

    item = upsert_igdb_game(db, game)
    recommendation_items: list[MediaItem] = []
    similar_raw = game.metadata.get("similarGames")
    if isinstance(similar_raw, list):
        for entry in similar_raw:
            if not isinstance(entry, dict):
                continue
            gid = entry.get("id")
            gname = entry.get("name")
            if not isinstance(gid, str) or not isinstance(gname, str) or not gid or not gname:
                continue
            image_val = entry.get("imageUrl")
            stub = IgdbGame(
                external_id=gid,
                title=gname,
                subtitle=None,
                description=None,
                image_url=image_val if isinstance(image_val, str) else None,
                metadata={},
            )
            recommendation_items.append(upsert_igdb_game(db, stub))
    db.commit()
    db.refresh(item)
    for rec in recommendation_items:
        db.refresh(rec)
    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
    return serialize_igdb_game_catalog_detail(
        item=item,
        game=game,
        tracking=tracking,
        recommendations=recommendation_items,
    )


def list_stash_game_events(
    db: Session,
    settings: Settings,
    *,
    window: str = "upcoming",
    offset: int = 0,
    limit: int = 60,
    force_refresh: bool = False,
    igdb_client: IgdbClient | None = None,
) -> StashGameEventsListResponse:
    return list_stash_game_events_cached(
        db,
        settings,
        window=window,
        offset=offset,
        limit=limit,
        force_refresh=force_refresh,
        igdb_client=igdb_client,
    )


def _fetch_movies_section(client: TmdbClient, section: str) -> list[TmdbMovie]:
    movies = client.fetch_movies(
        section=section,
        query=None,
        genre=None,
        keyword=None,
        page=1,
    )
    return client.enrich_movies_directors_from_credits(movies)


def list_catalog_movie_home_shelves(
    db: Session,
    _settings: Settings,
    tmdb_client: TmdbClient,
) -> MovieHomeShelfResponse:
    """Load now_playing + upcoming in one handler; TMDB calls run in parallel."""
    with ThreadPoolExecutor(max_workers=2) as pool:
        fut_now = pool.submit(_fetch_movies_section, tmdb_client, "now_playing")
        fut_up = pool.submit(_fetch_movies_section, tmdb_client, "upcoming")
        now_playing_movies = fut_now.result()
        upcoming_movies = fut_up.result()

    now_items = [upsert_tmdb_movie(db, movie) for movie in now_playing_movies]
    up_items = [upsert_tmdb_movie(db, movie) for movie in upcoming_movies]
    db.commit()
    for item in now_items:
        db.refresh(item)
    for item in up_items:
        db.refresh(item)

    return MovieHomeShelfResponse(
        nowPlaying=BackendMediaListResponse(
            items=[serialize_media_item(item) for item in now_items],
        ),
        upcoming=BackendMediaListResponse(
            items=[serialize_media_item(item) for item in up_items],
        ),
    )


def list_catalog_tv_shows(
    db: Session,
    _settings: Settings,
    tmdb_client: TmdbClient,
    *,
    section: str = "popular",
    q: str | None = None,
    genre: str | None = None,
    keyword: str | None = None,
    page: int = 1,
) -> BackendMediaListResponse:
    normalized_q = optional_text(q)
    normalized_genre = optional_text(genre)
    normalized_keyword = optional_text(keyword)
    shows = tmdb_client.fetch_tv_shows(
        section=section,
        query=normalized_q,
        genre=normalized_genre,
        keyword=normalized_keyword,
        page=page,
    )
    items = [upsert_tmdb_tv_show(db, show) for show in shows]
    db.commit()
    for item in items:
        db.refresh(item)
    return BackendMediaListResponse(items=[serialize_media_item(item) for item in items])


_TRACKING_FLAG_PREFIX = "[cult.flags]"


def _tracking_flags(notes: str | None) -> set[str]:
    text = (notes or "").strip()
    if not text.startswith(_TRACKING_FLAG_PREFIX):
        return set()
    first_line = text.split("\n", 1)[0]
    payload = first_line[len(_TRACKING_FLAG_PREFIX) :]
    return {segment.strip() for segment in payload.split(",") if segment.strip()}


def _is_watched_tracking(status: str, notes: str | None) -> bool:
    if "watched" in _tracking_flags(notes):
        return True
    return status.strip().lower() == "completed"


def _is_watchlist_tracking(status: str, notes: str | None) -> bool:
    if "watchlist" in _tracking_flags(notes):
        return True
    return status.strip().lower() == "planning"


def _is_doing_tracking(notes: str | None) -> bool:
    return "doing" in _tracking_flags(notes)


def _tv_in_continue_watching_rotation(
    *,
    watchlisted: bool,
    in_progress: bool,
    doing: bool,
    has_episode_progress: bool,
    watched: bool,
) -> bool:
    """Shows eligible for upcoming shelf and active rotation (not library-watched catch-up)."""
    if doing or in_progress or watchlisted:
        return True
    if watched:
        return False
    # Episode progress without list flags (e.g. status still Planning after flag edits).
    return has_episode_progress


def _should_enqueue_tv_continue_scan(
    *,
    entry: TrackingEntry | None,
    on_rotation: bool,
    watched: bool,
    has_episode_progress: bool,
) -> bool:
    """Whether to resolve the next episode for Continue watching."""
    if not has_episode_progress:
        return False
    if on_rotation and not watched:
        return True
    # Finished S1 in library but started a new season — still continue while eps remain.
    if watched and entry is not None and not entry.tv_fully_watched:
        return True
    if watched and entry is None:
        return True
    return False


def _is_dropped_tracking(status: str, notes: str | None) -> bool:
    if "dropped" in _tracking_flags(notes):
        return True
    return status.strip().lower() == "dropped"


def _parse_iso_date(value: str | None) -> date | None:
    if not value:
        return None
    raw = value.strip()
    if len(raw) >= 10:
        try:
            return date.fromisoformat(raw[:10])
        except ValueError:
            return None
    return None


def _tracking_reference_date(entry: TrackingEntry) -> date:
    ref_dt = entry.completed_at or entry.updated_at
    if ref_dt.tzinfo is not None:
        ref_dt = ref_dt.astimezone(timezone.utc)
    return ref_dt.date()


def _episode_subtitle(
    ep_name: str | None,
    season: int | None,
    episode: int | None,
) -> str | None:
    parts: list[str] = []
    if season is not None and episode is not None:
        parts.append(f"S{season}E{episode}")
    if ep_name:
        parts.append(ep_name)
    return " · ".join(parts) if parts else None


def _episode_subtitle_from_teaser(
    teaser: TmdbTvEpisodeTeaser | None,
    *,
    air_date: date | None = None,
) -> str | None:
    """Build shelf subtitle; fall back to title or air date when S/E are missing on TMDB."""
    if teaser is None:
        return None
    primary = _episode_subtitle(teaser.name, teaser.season_number, teaser.episode_number)
    if primary:
        return primary
    name = (teaser.name or "").strip()
    if name:
        return name
    if air_date is not None:
        return air_date.strftime("%d %b %Y")
    return None


def _tv_brief_teaser_ok(teaser: TmdbTvEpisodeTeaser | None) -> bool:
    return (
        teaser is not None
        and teaser.season_number is not None
        and teaser.episode_number is not None
    )


def _safe_tv_home_detail(
    client: TmdbClient, external_id: str
) -> tuple[TmdbTvAiringBrief, TmdbTvShowSeasonsBundle] | None:
    try:
        return client.fetch_tv_home_detail(tv_id=external_id)
    except Exception:
        return None


def _max_watched_episode_tuple(watched_keys: set[tuple[int, int]]) -> tuple[int, int] | None:
    if not watched_keys:
        return None
    return max(watched_keys, key=lambda t: (t[0], t[1]))


def _season_numbers_in_watch_order(summaries: list[TmdbTvSeasonSummary]) -> list[int]:
    """Prefer regular seasons 1…N, then specials (0) so new viewers start on season 1."""
    nums = [s.season_number for s in summaries if getattr(s, "episode_count", 0) > 0]
    if not nums:
        nums = [s.season_number for s in summaries]
    positive = sorted({n for n in nums if n > 0})
    ordered = list(positive)
    if 0 in nums and 0 not in ordered:
        ordered.append(0)
    return ordered


def _next_episode_to_watch_teaser(
    tmdb_client: TmdbClient,
    *,
    tv_external_id: str,
    seasons_bundle: TmdbTvShowSeasonsBundle,
    watched_keys: set[tuple[int, int]],
    today: date,
    max_seasons_to_scan: int = 8,
) -> TmdbTvEpisodeTeaser | None:
    """First aired (≤ today) episode strictly after the user's last watched key, in broadcast order."""
    seasons_order = _season_numbers_in_watch_order(list(seasons_bundle.seasons))
    if not seasons_order:
        return None
    max_k = _max_watched_episode_tuple(watched_keys)
    scanned = 0
    for sn in seasons_order:
        if max_k is not None and sn < max_k[0]:
            continue
        if scanned >= max_seasons_to_scan:
            break
        try:
            detail = tmdb_client.fetch_tv_season_detail(
                tv_id=tv_external_id,
                season_number=sn,
                include_credits=False,
            )
        except (TmdbError, Exception):
            scanned += 1
            continue
        scanned += 1
        episodes = sorted(detail.episodes, key=lambda e: e.episode_number)
        for ep in episodes:
            en = ep.episode_number
            key = (sn, en)
            if max_k is not None and key <= max_k:
                continue
            if key in watched_keys:
                continue
            ed = _parse_iso_date(ep.air_date)
            if ed is not None and ed > today:
                continue
            return TmdbTvEpisodeTeaser(
                name=ep.name,
                air_date=ep.air_date,
                season_number=sn,
                episode_number=en,
                still_url=ep.still_url,
                runtime_minutes=ep.runtime_minutes,
            )
    return None


def _tv_episode_watches_by_media_id(db: Session, *, user_id: str) -> dict[str, set[tuple[int, int]]]:
    """All TV episode watch rows for a user, grouped by media_item_id (season, episode) keys."""
    rows = db.execute(
        select(
            TvEpisodeWatch.media_item_id,
            TvEpisodeWatch.season_number,
            TvEpisodeWatch.episode_number,
        ).where(TvEpisodeWatch.user_id == user_id),
    ).all()
    out: defaultdict[str, set[tuple[int, int]]] = defaultdict(set)
    for mid, sn, en in rows:
        out[str(mid)].add((int(sn), int(en)))
    return dict(out)


def list_catalog_tv_home_shelves(
    db: Session,
    _settings: Settings,
    tmdb_client: TmdbClient,
    *,
    username: str | None = None,
) -> TvLibraryHomeResponse:
    """Next up: next episode to watch (by progress) + new aired drops after series completed; upcoming = future."""
    empty = TvLibraryHomeResponse(
        nextUp=BackendMediaListResponse(items=[]),
        upcomingEpisodes=BackendMediaListResponse(items=[]),
    )

    user_key = optional_text(username)
    if not user_key:
        return empty

    user = db.scalar(select(AppUser).where(AppUser.username == user_key))
    if user is None:
        return empty

    pairs = db.execute(
        select(TrackingEntry, MediaItem)
        .join(MediaItem, TrackingEntry.media_item_id == MediaItem.id)
        .where(
            TrackingEntry.user_id == user.id,
            MediaItem.media_type == "tv",
            MediaItem.source == "tmdb",
        ),
    ).all()

    watch_keys_by_media = _tv_episode_watches_by_media_id(db, user_id=user.id)

    tracked_ids = {m.id for _, m in pairs}
    missing_watch_mids = [mid for mid in watch_keys_by_media if mid not in tracked_ids]
    extra_medias: list[MediaItem] = []
    if missing_watch_mids:
        extra_medias = list(
            db.scalars(
                select(MediaItem).where(
                    MediaItem.id.in_(missing_watch_mids),
                    MediaItem.media_type == "tv",
                    MediaItem.source == "tmdb",
                ),
            ).all(),
        )

    ext_ids = sorted(
        {
            *(m.external_id.strip() for _, m in pairs if (m.external_id or "").strip()),
            *(m.external_id.strip() for m in extra_medias if (m.external_id or "").strip()),
        },
    )
    tv_home_by_ext: dict[str, tuple[TmdbTvAiringBrief, TmdbTvShowSeasonsBundle] | None] = {}
    if ext_ids:
        with ThreadPoolExecutor(max_workers=10) as pool:
            submitted = [(eid, pool.submit(_safe_tv_home_detail, tmdb_client, eid)) for eid in ext_ids]
        for eid, fut in submitted:
            try:
                tv_home_by_ext[eid] = fut.result()
            except Exception:
                tv_home_by_ext[eid] = None

    today = date.today()
    next_up_items: list[BackendMediaResponse] = []
    upcoming_items: list[BackendMediaResponse] = []
    continue_jobs: list[tuple[MediaItem, str, frozenset[tuple[int, int]], TmdbTvShowSeasonsBundle, float]] = []

    def _process_tv_home_row(entry: TrackingEntry | None, media: MediaItem) -> None:
        ext = (media.external_id or "").strip()
        if not ext:
            return
        home = tv_home_by_ext.get(ext)
        if home is None:
            return
        brief, bundle = home

        watched_keys = watch_keys_by_media.get(media.id, set())
        has_episode_progress = bool(watched_keys)

        if entry is None:
            watched = False
            watchlisted = False
            in_progress = True
            doing = False
        else:
            status = entry.status
            notes = entry.notes
            if _is_dropped_tracking(status, notes):
                return
            watched = _is_watched_tracking(status, notes)
            watchlisted = _is_watchlist_tracking(status, notes)
            in_progress = status.strip().lower() == "in progress"
            doing = _is_doing_tracking(notes)

        on_rotation = _tv_in_continue_watching_rotation(
            watchlisted=watchlisted,
            in_progress=in_progress,
            doing=doing,
            has_episode_progress=has_episode_progress,
            watched=watched,
        )

        if entry is not None and watched:
            watched_keys_done = watched_keys
            last = brief.last_episode
            last_d = _parse_iso_date(last.air_date if last else None)
            last_ok = _tv_brief_teaser_ok(last)
            last_key = (last.season_number, last.episode_number) if last_ok and last is not None else None
            if (
                last_key is not None
                and last_d is not None
                and last_d > _tracking_reference_date(entry)
                and last_key not in watched_keys_done
            ):
                last_sub = _episode_subtitle_from_teaser(last, air_date=last_d)
                next_up_items.append(
                    serialize_media_item_with_overlay(
                        media,
                        subtitle=last_sub or media.subtitle,
                        metadata_overlay={
                            "releaseDate": last_d.isoformat(),
                            "shelfEpisodeKind": "lastAired",
                        },
                    ),
                )

        if on_rotation:
            nxt = brief.next_episode
            nd = _parse_iso_date(nxt.air_date if nxt else None)
            if nd is not None and nd > today:
                next_sub = _episode_subtitle_from_teaser(nxt, air_date=nd)
                upcoming_items.append(
                    serialize_media_item_with_overlay(
                        media,
                        subtitle=next_sub or media.subtitle,
                        metadata_overlay={
                            "releaseDate": nd.isoformat(),
                            "shelfEpisodeKind": "nextAiring",
                        },
                    ),
                )

        if _should_enqueue_tv_continue_scan(
            entry=entry,
            on_rotation=on_rotation,
            watched=watched,
            has_episode_progress=has_episode_progress,
        ):
            sort_ts = 0.0
            if entry is not None:
                sort_ts = entry.updated_at.timestamp()
            continue_jobs.append((media, ext, frozenset(watched_keys), bundle, sort_ts))

    for entry, media in pairs:
        _process_tv_home_row(entry, media)
    for media in extra_medias:
        _process_tv_home_row(None, media)

    if len(continue_jobs) > _TV_HOME_CONTINUE_SCAN_MAX:
        continue_jobs.sort(key=lambda row: row[4], reverse=True)
        continue_jobs = continue_jobs[:_TV_HOME_CONTINUE_SCAN_MAX]

    if continue_jobs:
        with ThreadPoolExecutor(max_workers=10) as pool:
            future_to_media: dict[Future, MediaItem] = {}
            for media, ext, keys, bundle, _sort_ts in continue_jobs:
                fut = pool.submit(
                    _next_episode_to_watch_teaser,
                    tmdb_client,
                    tv_external_id=ext,
                    seasons_bundle=bundle,
                    watched_keys=set(keys),
                    today=today,
                )
                future_to_media[fut] = media
            for fut in as_completed(future_to_media):
                media = future_to_media[fut]
                try:
                    pick = fut.result()
                except Exception:
                    logger.exception("TV home shelves: continue teaser failed for media %s", media.id)
                    continue
                if pick is None:
                    continue
                pd = _parse_iso_date(pick.air_date.strip() if pick.air_date else None)
                cont_sub = _episode_subtitle_from_teaser(pick, air_date=pd)
                overlay: dict[str, str] = {"shelfEpisodeKind": "continueWatching"}
                if pd is not None:
                    overlay["releaseDate"] = pd.isoformat()
                next_up_items.append(
                    serialize_media_item_with_overlay(
                        media,
                        subtitle=cont_sub or media.subtitle,
                        metadata_overlay=overlay,
                    ),
                )

    def _air_sort_key(row: BackendMediaResponse) -> date:
        md = row.metadata or {}
        return _parse_iso_date(str(md.get("releaseDate") or "")) or date.min

    continue_rows = [
        r for r in next_up_items if str((r.metadata or {}).get("shelfEpisodeKind") or "") == "continueWatching"
    ]
    new_drop_rows = [
        r for r in next_up_items if str((r.metadata or {}).get("shelfEpisodeKind") or "") == "lastAired"
    ]
    continue_rows.sort(key=_air_sort_key)
    new_drop_rows.sort(key=_air_sort_key, reverse=True)
    next_up_items = continue_rows + new_drop_rows
    upcoming_items.sort(key=_air_sort_key)
    next_up_items = next_up_items[:_TV_HOME_NEXT_UP_LIMIT]
    upcoming_items = upcoming_items[:24]

    return TvLibraryHomeResponse(
        nextUp=BackendMediaListResponse(items=next_up_items),
        upcomingEpisodes=BackendMediaListResponse(items=upcoming_items),
    )


def _tv_next_watch_episode_card(
    *,
    tmdb_detail: TmdbMovieDetail,
    watched_items: list[WatchedEpisodeResponse],
) -> TvNextEpisodeCardResponse | None:
    """Suggest one aired episode the user has not marked watched (last aired, else next aired)."""
    today = date.today()
    watched_keys = {(w.seasonNumber, w.episodeNumber) for w in watched_items if w.watchedAt}

    def teaser_aired(teaser: TmdbTvEpisodeTeaser | None) -> bool:
        if teaser is None or not teaser.air_date:
            return False
        d = _parse_iso_date(teaser.air_date.strip())
        return d is not None and d <= today

    def teaser_ok(teaser: TmdbTvEpisodeTeaser | None) -> bool:
        return (
            teaser is not None
            and teaser.season_number is not None
            and teaser.episode_number is not None
        )

    def to_card(teaser: TmdbTvEpisodeTeaser) -> TvNextEpisodeCardResponse:
        assert teaser.season_number is not None and teaser.episode_number is not None
        return TvNextEpisodeCardResponse(
            seasonNumber=teaser.season_number,
            episodeNumber=teaser.episode_number,
            name=teaser.name,
            airDate=teaser.air_date,
            stillUrl=teaser.still_url,
            runtimeMinutes=teaser.runtime_minutes,
        )

    last = tmdb_detail.tv_last_episode
    if teaser_ok(last) and teaser_aired(last):
        assert last is not None
        if (last.season_number, last.episode_number) not in watched_keys:
            return to_card(last)

    nxt = tmdb_detail.tv_next_episode
    if teaser_ok(nxt) and teaser_aired(nxt):
        assert nxt is not None
        if (nxt.season_number, nxt.episode_number) not in watched_keys:
            return to_card(nxt)

    return None


def get_tv_catalog_detail(
    db: Session,
    _settings: Settings,
    tmdb_client: TmdbClient,
    *,
    media_id: str,
    username: str | None,
) -> MovieCatalogDetailResponse:
    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is None or item.media_type != "tv":
        raise HTTPException(status_code=404, detail="TV show not found.")

    from .import_pending_service import get_pending_catalog_detail, is_catalog_pending_item

    if is_catalog_pending_item(item):
        return get_pending_catalog_detail(db, media_id=media_id, username=username)

    item = _resolve_tv_catalog_media(db, media_id=media_id)

    detail = tmdb_client.fetch_tv_detail(tv_id=item.external_id)
    item = upsert_tmdb_tv_show(db, detail.movie)
    recommendations = [upsert_tmdb_tv_show(db, rec) for rec in detail.recommendations]
    db.commit()
    db.refresh(item)
    for recommendation in recommendations:
        db.refresh(recommendation)

    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
    watched_list = None
    user_key = optional_text(username)
    if user_key:
        watched_list = backend_service.list_tv_episode_watches(
            db,
            username=user_key,
            media_id=item.id,
        ).items

    next_card = _tv_next_watch_episode_card(
        tmdb_detail=detail,
        watched_items=list(watched_list or []),
    )

    return serialize_movie_catalog_detail(
        item=item,
        detail=detail,
        recommendations=recommendations,
        tracking=tracking,
        omdb_movie=None,
        watched_episodes=watched_list,
        next_episode_card=next_card,
    )


def list_tv_season_catalog(
    db: Session,
    _settings: Settings,
    tmdb_client: TmdbClient,
    *,
    media_id: str,
) -> TvSeasonListResponse:
    item = _resolve_tv_catalog_media(db, media_id=media_id)
    try:
        bundle = tmdb_client.fetch_tv_show_seasons_bundle(tv_id=item.external_id)
    except TmdbError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    item = upsert_tmdb_tv_show(db, bundle.show)
    db.commit()
    db.refresh(item)

    return TvSeasonListResponse(
        items=[
            TvSeasonSummaryResponse(
                seasonNumber=s.season_number,
                name=s.name,
                episodeCount=s.episode_count,
                airDate=s.air_date,
                overview=s.overview,
                posterUrl=s.poster_url,
            )
            for s in bundle.seasons
        ],
    )


def get_tv_season_catalog_detail(
    db: Session,
    _settings: Settings,
    tmdb_client: TmdbClient,
    *,
    media_id: str,
    season_number: int,
    username: str | None,
) -> TvSeasonDetailResponse:
    item = _resolve_tv_catalog_media(db, media_id=media_id)
    try:
        detail = tmdb_client.fetch_tv_season_detail(
            tv_id=item.external_id,
            season_number=season_number,
        )
    except TmdbError as exc:
        message = str(exc)
        status = 404 if "not found" in message.lower() else 502
        raise HTTPException(status_code=status, detail=message) from exc

    watched_items = []
    season_user: TvSeasonUserState | None = None
    ep_states: dict[int, TvEpisodeUserState] = {}
    user_key = optional_text(username)
    if user_key:
        watched_items = backend_service.list_tv_episode_watches(
            db,
            username=user_key,
            media_id=item.id,
        ).items
        user_row = db.scalar(select(AppUser).where(AppUser.username == user_key))
        if user_row is not None:
            season_user = db.scalar(
                select(TvSeasonUserState).where(
                    TvSeasonUserState.user_id == user_row.id,
                    TvSeasonUserState.media_item_id == item.id,
                    TvSeasonUserState.season_number == season_number,
                ),
            )
            ep_rows = db.scalars(
                select(TvEpisodeUserState).where(
                    TvEpisodeUserState.user_id == user_row.id,
                    TvEpisodeUserState.media_item_id == item.id,
                    TvEpisodeUserState.season_number == season_number,
                ),
            ).all()
            ep_states = {r.episode_number: r for r in ep_rows}

    ratings: list[MovieDetailMetric] = []
    if detail.vote_average is not None:
        ratings.append(
            MovieDetailMetric(label="TMDB", value=f"{detail.vote_average:.1f}"),
        )

    episodes_out: list[TvEpisodeCatalogResponse] = []
    for e in detail.episodes:
        st = ep_states.get(e.episode_number)
        episodes_out.append(
            TvEpisodeCatalogResponse(
                episodeNumber=e.episode_number,
                name=e.name,
                overview=e.overview,
                airDate=e.air_date,
                stillUrl=e.still_url,
                runtimeMinutes=e.runtime_minutes,
                voteAverage=e.vote_average,
                guestStars=[serialize_tmdb_person(p) for p in e.guest_stars],
                userRating=st.rating if st is not None else None,
                userRatingRatedAt=st.rating_rated_at.isoformat().replace("+00:00", "Z")
                if st is not None and st.rating_rated_at is not None
                else None,
                userWatchlist=st.watchlist if st is not None else None,
                userWatchlistedAt=st.watchlisted_at.isoformat().replace("+00:00", "Z")
                if st is not None and st.watchlisted_at is not None
                else None,
            ),
        )

    return TvSeasonDetailResponse(
        seasonNumber=detail.season_number,
        name=detail.name,
        overview=detail.overview,
        airDate=detail.air_date,
        posterUrl=detail.poster_url,
        episodes=episodes_out,
        watchedEpisodes=list(watched_items),
        cast=[serialize_tmdb_person(p) for p in detail.season_cast],
        ratings=ratings,
        directors=[serialize_tmdb_person(p) for p in detail.directors],
        userSeasonRating=season_user.rating if season_user is not None else None,
        userSeasonRatingRatedAt=season_user.rating_rated_at.isoformat().replace("+00:00", "Z")
        if season_user is not None and season_user.rating_rated_at is not None
        else None,
        userSeasonWatchlist=season_user.watchlist if season_user is not None else None,
        userSeasonWatchlistedAt=season_user.watchlisted_at.isoformat().replace("+00:00", "Z")
        if season_user is not None and season_user.watchlisted_at is not None
        else None,
    )


def get_tv_episode_catalog_detail(
    db: Session,
    _settings: Settings,
    tmdb_client: TmdbClient,
    *,
    media_id: str,
    season_number: int,
    episode_number: int,
    username: str | None,
) -> TvEpisodeDetailResponse:
    item = _resolve_tv_catalog_media(db, media_id=media_id)
    try:
        ep = tmdb_client.fetch_tv_episode_detail(
            tv_id=item.external_id,
            season_number=season_number,
            episode_number=episode_number,
        )
    except TmdbError as exc:
        message = str(exc)
        status = 404 if "not found" in message.lower() else 502
        raise HTTPException(status_code=status, detail=message) from exc

    ratings: list[MovieDetailMetric] = []
    if ep.vote_average is not None:
        ratings.append(MovieDetailMetric(label="TMDB", value=f"{ep.vote_average:.1f}"))

    watched_at_s: str | None = None
    st: TvEpisodeUserState | None = None
    user_key = optional_text(username)
    if user_key:
        user_row = db.scalar(select(AppUser).where(AppUser.username == user_key))
        if user_row is not None:
            wrow = db.scalar(
                select(TvEpisodeWatch).where(
                    TvEpisodeWatch.user_id == user_row.id,
                    TvEpisodeWatch.media_item_id == item.id,
                    TvEpisodeWatch.season_number == season_number,
                    TvEpisodeWatch.episode_number == episode_number,
                ),
            )
            if wrow is not None:
                watched_at_s = wrow.watched_at.isoformat().replace("+00:00", "Z")
            st = db.scalar(
                select(TvEpisodeUserState).where(
                    TvEpisodeUserState.user_id == user_row.id,
                    TvEpisodeUserState.media_item_id == item.id,
                    TvEpisodeUserState.season_number == season_number,
                    TvEpisodeUserState.episode_number == episode_number,
                ),
            )

    return TvEpisodeDetailResponse(
        seasonNumber=ep.season_number,
        episodeNumber=ep.episode_number,
        name=ep.name,
        overview=ep.overview,
        airDate=ep.air_date,
        stillUrl=ep.still_url,
        runtimeMinutes=ep.runtime_minutes,
        voteAverage=ep.vote_average,
        cast=[serialize_tmdb_person(p) for p in ep.cast],
        guestStars=[serialize_tmdb_person(p) for p in ep.guest_stars],
        ratings=ratings,
        directors=[serialize_tmdb_person(p) for p in ep.directors],
        watchedAt=watched_at_s,
        userRating=st.rating if st is not None else None,
        userRatingRatedAt=st.rating_rated_at.isoformat().replace("+00:00", "Z")
        if st is not None and st.rating_rated_at is not None
        else None,
        userWatchlist=st.watchlist if st is not None else None,
        userWatchlistedAt=st.watchlisted_at.isoformat().replace("+00:00", "Z")
        if st is not None and st.watchlisted_at is not None
        else None,
    )


def get_movie_catalog_detail(
    db: Session,
    settings: Settings,
    tmdb_client: TmdbClient,
    *,
    media_id: str,
    username: str | None,
) -> MovieCatalogDetailResponse:
    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is None or item.media_type != "movie":
        raise HTTPException(status_code=404, detail="Movie not found.")

    from .import_pending_service import get_pending_catalog_detail, is_catalog_pending_item

    if is_catalog_pending_item(item):
        return get_pending_catalog_detail(db, media_id=media_id, username=username)

    if item.source != "tmdb":
        raise HTTPException(status_code=400, detail="Only TMDB-backed movies are supported for now.")

    detail = tmdb_client.fetch_movie_detail(movie_id=item.external_id)
    omdb_movie = lookup_omdb_movie(
        settings=settings,
        title=detail.movie.title,
        release_date=str(detail.movie.metadata.get("releaseDate") or "").strip(),
    )

    merged_movie = (
        merge_movie_data(detail.movie, omdb_movie, prefer_omdb=True)
        if omdb_movie is not None
        else detail.movie
    )
    item = upsert_tmdb_movie(db, merged_movie)
    recommendations = [upsert_tmdb_movie(db, movie) for movie in detail.recommendations]
    db.commit()
    db.refresh(item)
    for recommendation in recommendations:
        db.refresh(recommendation)

    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
    return serialize_movie_catalog_detail(
        item=item,
        detail=detail,
        recommendations=recommendations,
        tracking=tracking,
        omdb_movie=omdb_movie,
    )


def get_book_series_catalog_detail(
    db: Session,
    settings: Settings,
    book_clients: BookCatalogClients,
    *,
    series_id: str,
    series_name: str | None = None,
) -> GameCompanyCatalogDetailResponse:
    normalized_id = series_id.strip()
    hc_series_id = parse_hardcover_series_key(normalized_id)
    if hc_series_id is not None:
        return get_hardcover_series_catalog_detail(
            db,
            settings,
            book_clients,
            series_id=hc_series_id,
            series_name=series_name,
        )

    from .book_catalog_resolver import federate_catalog_books

    client = book_clients.openlibrary
    normalized_name = optional_text(series_name)
    if not normalized_id and not normalized_name:
        raise HTTPException(status_code=400, detail="Invalid series id.")

    try:
        books = client.fetch_series_books(
            normalized_id,
            series_name=normalized_name,
            limit=200,
            page=1,
        )
    except OpenLibraryError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    display_name = normalized_name or normalized_id
    resolved = federate_catalog_books(
        book_clients,
        books,
        query_title=display_name,
        hardcover_title_search=False,
    )
    catalog: list[GameCompanyCatalogItem] = []
    seen_external_ids: set[str] = set()
    for row in resolved:
        book = row.book
        ext = book.external_id.strip()
        if not ext or ext in seen_external_ids:
            continue
        seen_external_ids.add(ext)
        upsert_fn = _BOOK_UPSERT_BY_SOURCE.get(row.source, upsert_openlibrary_book)
        item = upsert_fn(db, book)
        db.flush()
        position = ""
        book_meta = book.metadata if isinstance(book.metadata, dict) else {}
        if isinstance(book_meta.get("bookSeriesPosition"), str):
            position = book_meta["bookSeriesPosition"].strip()
        elif isinstance(book_meta.get("bookSeriesPosition"), (int, float)):
            position = str(book_meta["bookSeriesPosition"])
        roles = [f"#{position}"] if position else ["Series"]
        catalog.append(
            GameCompanyCatalogItem(
                media=serialize_media_item(item),
                roles=roles,
            ),
        )

    db.commit()

    ol_series_id = normalized_id or normalized_name
    links = [
        MovieDetailLink(
            label="Open Library",
            url=f"https://openlibrary.org/series/{quote(ol_series_id, safe='')}",
        ),
    ]
    if book_clients.hardcover is not None and book_clients.hardcover.enabled:
        links.append(
            MovieDetailLink(
                label="Hardcover",
                url="https://hardcover.app/books",
            ),
        )
    return GameCompanyCatalogDetailResponse(
        companyId=ol_series_id,
        name=display_name,
        description=None,
        primaryRole="Series",
        imageUrl=None,
        catalog=catalog,
        popularCatalog=catalog[:12],
        links=links,
    )


def get_book_publisher_catalog_detail(
    db: Session,
    settings: Settings,
    book_clients: BookCatalogClients,
    *,
    publisher_id: str,
) -> GameCompanyCatalogDetailResponse:
    from .book_catalog_resolver import federate_catalog_books

    client = book_clients.openlibrary
    normalized = publisher_id.strip()
    if not parse_openlibrary_publisher_id(normalized):
        raise HTTPException(status_code=400, detail="Invalid publisher id.")
    try:
        publisher = client.fetch_publisher_by_id(normalized)
    except OpenLibraryError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if publisher is None:
        raise HTTPException(status_code=404, detail="Publisher not found.")

    try:
        books = client.fetch_publisher_books(normalized, limit=200, page=1)
    except OpenLibraryError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    resolved = federate_catalog_books(
        book_clients,
        books,
        query_title=publisher.name,
        hardcover_title_search=False,
    )
    catalog: list[GameCompanyCatalogItem] = []
    seen_external_ids: set[str] = set()
    for row in resolved:
        book = row.book
        ext = book.external_id.strip()
        if not ext or ext in seen_external_ids:
            continue
        seen_external_ids.add(ext)
        upsert_fn = _BOOK_UPSERT_BY_SOURCE.get(row.source, upsert_openlibrary_book)
        item = upsert_fn(db, book)
        db.flush()
        catalog.append(
            GameCompanyCatalogItem(
                media=serialize_media_item(item),
                roles=["Publisher"],
            ),
        )

    db.commit()

    ol_url_name = parse_openlibrary_publisher_id(publisher.publisher_id) or publisher.name
    links = [
        MovieDetailLink(
            label="Open Library",
            url=f"https://openlibrary.org/publishers/{quote(ol_url_name, safe='')}",
        ),
    ]
    if book_clients.hardcover is not None and book_clients.hardcover.enabled:
        links.append(
            MovieDetailLink(
                label="Hardcover",
                url="https://hardcover.app/books",
            ),
        )
    return GameCompanyCatalogDetailResponse(
        companyId=publisher.publisher_id,
        name=publisher.name,
        description=None,
        primaryRole="Publisher",
        imageUrl=None,
        catalog=catalog,
        popularCatalog=catalog[:12],
        links=links,
    )


def get_hardcover_series_catalog_detail(
    db: Session,
    _settings: Settings,
    book_clients: BookCatalogClients,
    *,
    series_id: str,
    series_name: str | None = None,
) -> GameCompanyCatalogDetailResponse:
    from ..hardcover_client import HardcoverError

    hc = book_clients.hardcover
    if hc is None or not hc.enabled:
        raise HTTPException(status_code=503, detail="Hardcover is not configured.")

    normalized_id = series_id.strip()
    if not normalized_id.isdigit():
        raise HTTPException(status_code=400, detail="Invalid Hardcover series id.")

    try:
        row = hc.fetch_series_by_id(normalized_id)
    except HardcoverError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if row is None:
        raise HTTPException(status_code=404, detail="Series not found.")

    try:
        books = hc.fetch_series_books(normalized_id, limit=200)
    except HardcoverError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    display_name = optional_text(series_name) or str(row.get("name") or "").strip() or normalized_id
    catalog: list[GameCompanyCatalogItem] = []
    seen_external_ids: set[str] = set()
    for book in books:
        ext = book.external_id.strip()
        if not ext or ext in seen_external_ids:
            continue
        seen_external_ids.add(ext)
        item = upsert_hardcover_book(db, book)
        db.flush()
        book_meta = book.metadata if isinstance(book.metadata, dict) else {}
        position = ""
        if isinstance(book_meta.get("bookSeriesPosition"), str):
            position = book_meta["bookSeriesPosition"].strip()
        elif isinstance(book_meta.get("bookSeriesPosition"), (int, float)):
            position = str(book_meta["bookSeriesPosition"])
        roles = [f"#{position}"] if position else ["Series"]
        catalog.append(
            GameCompanyCatalogItem(
                media=serialize_media_item(item),
                roles=roles,
            ),
        )

    db.commit()

    slug = str(row.get("slug") or "").strip()
    series_key = hardcover_series_key(normalized_id)
    links = [
        MovieDetailLink(
            label="Hardcover",
            url=f"https://hardcover.app/series/{slug or normalized_id}",
        ),
    ]
    return GameCompanyCatalogDetailResponse(
        companyId=series_key,
        name=display_name,
        description=str(row.get("description") or "").strip() or None,
        primaryRole="Series",
        imageUrl=None,
        catalog=catalog,
        popularCatalog=catalog[:12],
        links=links,
    )


def get_hardcover_author_catalog_detail(
    db: Session,
    _settings: Settings,
    book_clients: BookCatalogClients,
    *,
    person_id: str,
    author_id: str,
) -> PersonCatalogDetailResponse:
    from ..hardcover_client import HardcoverError

    hc = book_clients.hardcover
    if hc is None or not hc.enabled:
        raise HTTPException(status_code=503, detail="Hardcover is not configured.")

    token = str(author_id).strip()
    if not token.isdigit():
        raise HTTPException(status_code=400, detail="Invalid Hardcover author id.")

    try:
        author = hc.fetch_author_by_id(token)
    except HardcoverError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if author is None:
        raise HTTPException(status_code=404, detail="Author not found.")

    name = str(author.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=404, detail="Author not found.")

    try:
        books = hc.fetch_author_books(token, limit=200)
    except HardcoverError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    filmography: list[PersonFilmographyItem] = []
    seen_external_ids: set[str] = set()
    for book in books:
        ext = book.external_id.strip()
        if not ext or ext in seen_external_ids:
            continue
        seen_external_ids.add(ext)
        item = upsert_hardcover_book(db, book)
        db.flush()
        filmography.append(
            PersonFilmographyItem(
                media=serialize_media_item(item),
                role="Author",
                mediaType="book",
                creditKind="author",
            ),
        )

    db.commit()

    biography = str(author.get("bio") or "").strip() or None
    birthday = str(author.get("born_date") or "").strip() or None
    death = str(author.get("death_date") or "").strip()
    if death:
        birthday = f"{birthday} – {death}" if birthday else death

    image_url = None
    cached_image = author.get("cached_image")
    if isinstance(cached_image, str) and cached_image.startswith("http"):
        image_url = cached_image.replace("http://", "https://")
    elif isinstance(cached_image, dict):
        for key in ("url", "image_url", "large", "medium"):
            val = cached_image.get(key)
            if isinstance(val, str) and val.startswith("http"):
                image_url = val.replace("http://", "https://")
                break

    slug = str(author.get("slug") or "").strip()
    hc_person_id = hardcover_person_id(token)
    links = [
        TmdbLink(
            label="Hardcover",
            url=f"https://hardcover.app/authors/{slug or token}",
        ),
    ]
    return serialize_person_catalog_detail(
        person_id=hc_person_id or person_id.strip(),
        name=name,
        biography=biography,
        known_for_department="Author",
        image_url=image_url,
        gender=None,
        birthday=birthday or None,
        place_of_birth=None,
        filmography=filmography,
        popular_filmography=filmography[:12],
        links=links,
    )


def get_openlibrary_author_catalog_detail(
    db: Session,
    settings: Settings,
    book_clients: BookCatalogClients,
    *,
    person_id: str,
    author_id: str,
) -> PersonCatalogDetailResponse:
    from ..hardcover_client import HardcoverError
    from .book_catalog_resolver import (
        ResolvedCatalogBook,
        federate_catalog_books,
        merge_resolved_catalog_rows,
    )

    client = book_clients.openlibrary
    try:
        author = client.fetch_author_by_id(author_id)
    except OpenLibraryError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if author is None:
        raise HTTPException(status_code=404, detail="Author not found.")

    try:
        works = client.fetch_author_works(author_id, limit=200)
    except OpenLibraryError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if not works:
        try:
            works = client.fetch_author_books_search(
                author_id=author_id,
                author_name=author.name,
                limit=200,
            )
        except OpenLibraryError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc

    hc_rows: list = []
    hc = book_clients.hardcover
    if hc is not None and hc.enabled:
        try:
            hc_rows = [
                ResolvedCatalogBook(book=book, source="hardcover")
                for book in hc.search_by_title_author(author.name, limit=80)
            ]
        except HardcoverError:
            hc_rows = []

    federated_ol = federate_catalog_books(
        book_clients,
        works,
        query_title=author.name,
        query_authors=author.name,
        hardcover_title_search=False,
    )
    resolved = merge_resolved_catalog_rows(
        hc_rows,
        federated_ol,
        limit=200,
        query_title=author.name,
        query_authors=author.name,
        clients=book_clients,
    )

    filmography: list[PersonFilmographyItem] = []
    seen_external_ids: set[str] = set()
    for row in resolved:
        book = row.book
        ext = book.external_id.strip()
        if not ext or ext in seen_external_ids:
            continue
        seen_external_ids.add(ext)
        upsert_fn = _BOOK_UPSERT_BY_SOURCE.get(row.source, upsert_openlibrary_book)
        item = upsert_fn(db, book)
        db.flush()
        filmography.append(
            PersonFilmographyItem(
                media=serialize_media_item(item),
                role="Author",
                mediaType="book",
                creditKind="author",
            )
        )

    db.commit()

    ol_person_id = openlibrary_person_id(author_id) or person_id.strip()
    birthday = author.birth_date
    if author.death_date:
        if birthday:
            birthday = '$birthday – ${author.death_date}'
        else:
            birthday = author.death_date
    return serialize_person_catalog_detail(
        person_id=ol_person_id,
        name=author.name,
        biography=author.biography,
        known_for_department="Author",
        image_url=author.image_url,
        gender=None,
        birthday=birthday,
        place_of_birth=None,
        filmography=filmography,
        popular_filmography=[],
        links=_author_catalog_links(author.author_id, book_clients),
    )


def _author_catalog_links(author_id: str, book_clients: BookCatalogClients) -> list[TmdbLink]:
    links = [
        TmdbLink(
            label="Open Library",
            url=f"https://openlibrary.org/authors/{author_id}",
        ),
    ]
    if book_clients.hardcover is not None and book_clients.hardcover.enabled:
        links.append(TmdbLink(label="Hardcover", url="https://hardcover.app/books"))
    return links


def get_person_catalog_detail(
    db: Session,
    settings: Settings,
    tmdb_client: TmdbClient,
    book_clients: BookCatalogClients,
    *,
    person_id: str,
) -> PersonCatalogDetailResponse:
    normalized = person_id.strip()
    parsed = parse_book_person_id(normalized)
    if parsed is not None:
        provider, external_id = parsed
        if provider == "hardcover":
            return get_hardcover_author_catalog_detail(
                db,
                settings,
                book_clients,
                person_id=normalized,
                author_id=external_id,
            )
        return get_openlibrary_author_catalog_detail(
            db,
            settings,
            book_clients,
            person_id=normalized,
            author_id=external_id,
        )
    if not normalized.isdigit():
        raise HTTPException(status_code=400, detail="Invalid person id.")

    bundle = tmdb_client.fetch_person_catalog_detail(person_id=normalized)
    links: list[TmdbLink] = [
        TmdbLink(label="IMDb", url=f"https://www.imdb.com/name/{bundle.imdb_id}/")
        if bundle.imdb_id
        else TmdbLink(
            label="IMDb",
            url=f"https://www.imdb.com/find/?q={quote_plus(bundle.name)}",
        ),
        TmdbLink(label="TMDB", url=f"https://www.themoviedb.org/person/{bundle.person_id}"),
        TmdbLink(
            label="Wikipedia",
            url=f"https://en.wikipedia.org/w/index.php?search={quote_plus(bundle.name)}",
        ),
    ]

    filmography: list[PersonFilmographyItem] = []
    for credit in bundle.movie_credits:
        item = upsert_tmdb_media(db, credit.movie, media_type=credit.media_type)
        db.flush()
        filmography.append(
            PersonFilmographyItem(
                media=serialize_media_item(item),
                role=credit.role,
                mediaType=credit.media_type,
                creditKind=credit.credit_kind,
                department=credit.department,
                genreIds=list(credit.genre_ids),
                genreNames=tmdb_genre_names(credit.media_type, credit.genre_ids),
                voteAverage=credit.vote_average,
                episodeCount=credit.episode_count,
            )
        )

    popular_filmography: list[PersonFilmographyItem] = []
    for credit in bundle.popular_movie_credits:
        item = upsert_tmdb_media(db, credit.movie, media_type=credit.media_type)
        db.flush()
        popular_filmography.append(
            PersonFilmographyItem(
                media=serialize_media_item(item),
                role=credit.role,
                mediaType=credit.media_type,
                creditKind=credit.credit_kind,
                department=credit.department,
                genreIds=list(credit.genre_ids),
                genreNames=tmdb_genre_names(credit.media_type, credit.genre_ids),
                voteAverage=credit.vote_average,
                episodeCount=credit.episode_count,
            )
        )

    db.commit()

    return serialize_person_catalog_detail(
        person_id=bundle.person_id,
        name=bundle.name,
        biography=bundle.biography,
        known_for_department=bundle.known_for_department,
        image_url=bundle.image_url,
        gender=bundle.gender,
        birthday=bundle.birthday,
        place_of_birth=bundle.place_of_birth,
        filmography=filmography,
        popular_filmography=popular_filmography,
        links=links,
    )


def upsert_bgg_boardgame(db: Session, game: BggBoardgame) -> MediaItem:
    item = db.scalar(
        select(MediaItem).where(
            MediaItem.source == "bgg",
            MediaItem.media_type == "boardgame",
            MediaItem.external_id == game.external_id,
        ),
    )
    if item is None:
        item = MediaItem(
            source="bgg",
            external_id=game.external_id,
            media_type="boardgame",
            title=game.title,
            subtitle=game.subtitle,
            description=game.description,
            image_url=game.image_url,
            provider_payload=dict(game.metadata),
        )
        db.add(item)
    else:
        item.title = game.title
        item.subtitle = game.subtitle
        item.description = game.description
        item.image_url = game.image_url
        old_meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
        item.provider_payload = {**old_meta, **dict(game.metadata)}
    db.flush()
    return item


def list_catalog_boardgames(
    db: Session,
    _settings: Settings,
    bgg_client: BggClient,
    *,
    section: str = "popular",
    q: str | None = None,
    page: int = 1,
) -> BackendMediaListResponse:
    _ = page
    normalized_q = optional_text(q)
    try:
        if normalized_q:
            games = bgg_client.search_boardgames(normalized_q)
        elif section.strip().lower() in {"popular", "hot"}:
            games = bgg_client.fetch_hot_boardgames()
        else:
            games = bgg_client.fetch_hot_boardgames()
    except BggError as exc:
        if normalized_q:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        cached = _list_cached_boardgames(db, limit=48)
        if cached:
            return BackendMediaListResponse(items=[serialize_media_item(item) for item in cached])
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    items = [upsert_bgg_boardgame(db, game) for game in games]
    db.commit()
    for item in items:
        db.refresh(item)
    return BackendMediaListResponse(items=[serialize_media_item(item) for item in items])


def _list_cached_boardgames(db: Session, *, limit: int) -> list[MediaItem]:
    return list(
        db.scalars(
            select(MediaItem)
            .where(
                MediaItem.media_type == "boardgame",
                MediaItem.source == "bgg",
            )
            .order_by(MediaItem.updated_at.desc())
            .limit(limit),
        ),
    )


def get_boardgame_catalog_detail(
    db: Session,
    _settings: Settings,
    bgg_client: BggClient,
    *,
    media_id: str,
    username: str | None,
) -> MovieCatalogDetailResponse:
    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is None or item.media_type != "boardgame":
        raise HTTPException(status_code=404, detail="Board game not found.")
    if item.source != "bgg":
        raise HTTPException(status_code=400, detail="Only BGG-backed board games are supported.")

    try:
        game = bgg_client.fetch_boardgame_by_id(item.external_id)
    except BggError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if game is None:
        raise HTTPException(status_code=404, detail="Board game not found on BGG.")

    item = upsert_bgg_boardgame(db, game)
    db.commit()
    db.refresh(item)
    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
    return serialize_bgg_boardgame_catalog_detail(
        item=item,
        game=game,
        tracking=tracking,
    )


def _book_page_count(meta: dict[str, object]) -> int | None:
    raw = meta.get("pageCount")
    if isinstance(raw, int) and raw > 0:
        return raw
    if isinstance(raw, float) and raw > 0:
        return int(raw)
    if isinstance(raw, str):
        parsed = int(raw.strip()) if raw.strip().isdigit() else None
        if parsed is not None and parsed > 0:
            return parsed
    return None


def backfill_openlibrary_book_page_counts(
    db: Session,
    media_items: list[MediaItem],
    *,
    ol_client: OpenLibraryClient | None = None,
    max_items: int = 24,
) -> int:
    """Fill missing pageCount on stored Open Library books (e.g. for tracking/home)."""
    if not media_items:
        return 0
    settings = load_settings()
    client = ol_client or OpenLibraryClient(
        timeout_seconds=settings.request_timeout_seconds,
        min_request_interval_seconds=settings.openlibrary_min_request_interval_seconds,
    )
    updated = 0
    for item in media_items:
        if updated >= max(1, max_items):
            break
        if item.media_type != "book" or item.source != "openlibrary":
            continue
        meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
        if _book_page_count(meta) is not None:
            continue
        work_id = (item.external_id or "").strip()
        if not work_id:
            continue
        try:
            book = client.fetch_book_by_work_id(work_id)
        except OpenLibraryError:
            continue
        if book is None:
            continue
        book_meta = book.metadata if isinstance(book.metadata, dict) else {}
        if _book_page_count(book_meta) is None:
            continue
        upsert_openlibrary_book(db, book)
        updated += 1
    if updated:
        db.flush()
    return updated


def _legacy_catalog_book_from_media_item(item: object) -> OpenLibraryBook:
    """Rebuild book fields from persisted provider_payload (no external API)."""
    meta = getattr(item, "provider_payload", None)
    payload = dict(meta) if isinstance(meta, dict) else {}
    return OpenLibraryBook(
        external_id=str(getattr(item, "external_id", "") or ""),
        title=str(getattr(item, "title", "") or ""),
        subtitle=getattr(item, "subtitle", None),
        description=getattr(item, "description", None),
        image_url=getattr(item, "image_url", None),
        metadata=payload,
    )


def upsert_porbase_book(db: Session, book: OpenLibraryBook) -> MediaItem:
    return _upsert_catalog_book(db, book, source="porbase")


def upsert_hardcover_book(db: Session, book: OpenLibraryBook) -> MediaItem:
    return _upsert_catalog_book(db, book, source="hardcover")


def upsert_openlibrary_book(db: Session, book: OpenLibraryBook) -> MediaItem:
    return _upsert_catalog_book(db, book, source="openlibrary")


def _upsert_catalog_book(db: Session, book: OpenLibraryBook, *, source: str) -> MediaItem:
    item = db.scalar(
        select(MediaItem).where(
            MediaItem.source == source,
            MediaItem.media_type == "book",
            MediaItem.external_id == book.external_id,
        ),
    )
    if item is None:
        item = MediaItem(
            source=source,
            external_id=book.external_id,
            media_type="book",
            title=book.title,
            subtitle=book.subtitle,
            description=book.description,
            image_url=book.image_url,
            provider_payload=dict(book.metadata),
        )
        db.add(item)
    else:
        item.title = book.title
        item.subtitle = book.subtitle
        item.description = book.description
        item.image_url = book.image_url or item.image_url
        old_meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
        item.provider_payload = {**old_meta, **dict(book.metadata)}
    db.flush()
    return item


_BOOK_UPSERT_BY_SOURCE = {
    "porbase": upsert_porbase_book,
    "hardcover": upsert_hardcover_book,
    "openlibrary": upsert_openlibrary_book,
}

_POPULAR_OL_CACHE_TTL_SECONDS = 3600.0
_POPULAR_HOME_LIMIT = 12


@dataclass(slots=True)
class _PopularOlCache:
    fetched_at: float
    books: list[OpenLibraryBook]

_popular_ol_cache: _PopularOlCache | None = None
_popular_hc_cache: _PopularOlCache | None = None


def _upsert_resolved_books(
    db: Session,
    resolved: list,
) -> list[MediaItem]:
    items: list[MediaItem] = []
    for row in resolved:
        upsert_fn = _BOOK_UPSERT_BY_SOURCE.get(row.source, upsert_openlibrary_book)
        items.append(upsert_fn(db, row.book))
    return items


def _fetch_popular_hardcover_books(
    hc_client: object,
    *,
    limit: int,
    page: int,
) -> list[OpenLibraryBook]:
    from ..hardcover_client import HardcoverClient

    global _popular_hc_cache
    if not isinstance(hc_client, HardcoverClient) or not hc_client.enabled:
        return []
    safe_limit = max(1, min(limit, 48))
    if page != 1:
        return hc_client.fetch_trending_books(limit=safe_limit, page=page)

    now = time.monotonic()
    cached = _popular_hc_cache
    if cached is not None and (now - cached.fetched_at) < _POPULAR_OL_CACHE_TTL_SECONDS:
        return cached.books[:safe_limit]

    books = hc_client.fetch_trending_books(limit=safe_limit, page=page)
    _popular_hc_cache = _PopularOlCache(fetched_at=now, books=books)
    return books[:safe_limit]


def _fetch_popular_openlibrary_books(
    ol_client: OpenLibraryClient,
    *,
    limit: int,
    page: int,
) -> list[OpenLibraryBook]:
    global _popular_ol_cache
    safe_limit = max(1, min(limit, 48))
    if page != 1:
        return ol_client.fetch_popular_books(limit=safe_limit, page=page)

    now = time.monotonic()
    cached = _popular_ol_cache
    if cached is not None and (now - cached.fetched_at) < _POPULAR_OL_CACHE_TTL_SECONDS:
        return cached.books[:safe_limit]

    books = ol_client.fetch_popular_books(limit=safe_limit, page=page)
    _popular_ol_cache = _PopularOlCache(fetched_at=now, books=books)
    return books[:safe_limit]


def list_catalog_books(
    db: Session,
    _settings: Settings,
    book_clients: BookCatalogClients,
    *,
    section: str = "popular",
    q: str | None = None,
    page: int = 1,
    limit: int = 24,
    language: str | None = None,
    year: str | None = None,
    genre: str | None = None,
    sources: str | None = None,
) -> BackendMediaListResponse:
    from .book_catalog_policy import is_hardcover_primary, parse_search_sources_param
    from .book_catalog_resolver import (
        federate_catalog_books,
        merge_resolved_catalog_rows,
        search_catalog,
    )

    clients = book_clients
    ol_client = clients.openlibrary
    normalized_q = optional_text(q)
    normalized_language = optional_text(language)
    normalized_year = optional_text(year)
    normalized_genre = optional_text(genre)
    search_sources = parse_search_sources_param(sources)
    has_ol_filters = bool(normalized_language or normalized_year or normalized_genre)
    has_text_search = bool(normalized_q)
    safe_limit = max(1, min(limit, 48))
    is_popular_section = section.strip().lower() in {"popular", "trending", "top_rated"}
    popular_limit = min(safe_limit, _POPULAR_HOME_LIMIT) if is_popular_section and not has_text_search else safe_limit

    if has_ol_filters and not search_sources.openlibrary:
        raise HTTPException(
            status_code=400,
            detail="Language, year, and genre filters require sources=openlibrary.",
        )

    try:
        if has_text_search and not has_ol_filters:
            resolved = search_catalog(
                clients,
                query_text=normalized_q or "",
                limit=safe_limit,
                sources=search_sources,
            )
            items = _upsert_resolved_books(db, resolved)
        elif has_text_search or has_ol_filters:
            ol_books = ol_client.search_books(
                normalized_q or "",
                page=page,
                limit=safe_limit,
                language=normalized_language,
                year=normalized_year,
                genre=normalized_genre,
            )
            groups: list = [
                federate_catalog_books(
                    clients,
                    ol_books,
                    query_title=normalized_q or "",
                    limit=safe_limit,
                ),
            ]
            if has_text_search:
                groups.insert(
                    0,
                    search_catalog(
                        clients,
                        query_text=normalized_q or "",
                        limit=safe_limit,
                        sources=search_sources,
                    ),
                )
            resolved = merge_resolved_catalog_rows(
                *groups,
                limit=safe_limit,
                query_title=normalized_q or "",
                clients=clients,
            )
            items = _upsert_resolved_books(db, resolved)
        elif is_popular_section and is_hardcover_primary() and not search_sources.openlibrary:
            from .book_catalog_resolver import ResolvedCatalogBook

            hc = clients.hardcover
            hc_books: list[OpenLibraryBook] = []
            if hc is not None and hc.enabled:
                hc_books = _fetch_popular_hardcover_books(
                    hc,
                    limit=popular_limit,
                    page=page,
                )
            if hc_books:
                resolved = [
                    ResolvedCatalogBook(book=book, source="hardcover") for book in hc_books
                ]
                items = _upsert_resolved_books(db, resolved)
            else:
                cached = _list_cached_books(
                    db,
                    limit=popular_limit,
                    preferred_sources={"hardcover"},
                )
                items = cached
        elif is_popular_section:
            ol_books = _fetch_popular_openlibrary_books(
                ol_client,
                limit=popular_limit,
                page=page,
            )
            resolved = federate_catalog_books(
                clients,
                ol_books,
                limit=popular_limit,
                hardcover_title_search=False,
            )
            items = _upsert_resolved_books(db, resolved)
        else:
            if is_hardcover_primary():
                items = _list_cached_books(
                    db,
                    limit=popular_limit,
                    preferred_sources={"hardcover"},
                )
            else:
                ol_books = _fetch_popular_openlibrary_books(
                    ol_client,
                    limit=popular_limit,
                    page=page,
                )
                resolved = federate_catalog_books(
                    clients,
                    ol_books,
                    limit=popular_limit,
                    hardcover_title_search=False,
                )
                items = _upsert_resolved_books(db, resolved)
    except OpenLibraryError as exc:
        if has_text_search or has_ol_filters:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        cached = _list_cached_books(db, limit=safe_limit)
        if cached:
            return BackendMediaListResponse(items=[serialize_media_item(item) for item in cached])
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    db.commit()
    return BackendMediaListResponse(items=[serialize_media_item(item) for item in items])


def _list_cached_books(
    db: Session,
    *,
    limit: int,
    exclude_sources: set[str] | None = None,
    preferred_sources: set[str] | None = None,
) -> list[MediaItem]:
    stmt = (
        select(MediaItem)
        .where(MediaItem.media_type == "book")
        .order_by(MediaItem.updated_at.desc())
        .limit(limit)
    )
    if preferred_sources:
        stmt = stmt.where(MediaItem.source.in_(tuple(preferred_sources)))
    if exclude_sources:
        stmt = stmt.where(~MediaItem.source.in_(tuple(exclude_sources)))
    return list(db.scalars(stmt))


def _book_from_stored_media_item(item: MediaItem) -> OpenLibraryBook:
    if item.source == "porbase":
        from ..porbase_client import porbase_book_from_media_item

        return porbase_book_from_media_item(item)
    if item.source == "hardcover":
        from ..hardcover_client import hardcover_book_from_media_item

        return hardcover_book_from_media_item(item)
    return openlibrary_book_from_media_item(item)


def _book_detail_metadata_ready(metadata: dict[str, object]) -> bool:
    """Skip live enrichment when stored payload is already complete."""
    if metadata.get(BOOK_DETAIL_ENRICHED_KEY):
        return True
    entries_raw = metadata.get("authorEntries")
    if not isinstance(entries_raw, list) or not entries_raw:
        return False
    for row in entries_raw:
        if not isinstance(row, dict):
            continue
        if not str(row.get("id") or "").strip():
            return False
    return True


def _book_for_catalog_detail_response(
    book_clients: BookCatalogClients,
    item: MediaItem,
    *,
    db: Session | None = None,
) -> OpenLibraryBook:
    from .book_catalog_policy import uses_openlibrary_catalog
    from .book_catalog_resolver import (
        _backfill_openlibrary_author_entries,
        enrich_author_entry_images,
        merge_book_metadata,
    )

    book = _book_from_stored_media_item(item)

    meta = book.metadata if isinstance(book.metadata, dict) else {}
    if _book_detail_metadata_ready(meta):
        return book

    if uses_openlibrary_catalog():
        fixed_meta = _backfill_openlibrary_author_entries(
            book_clients.openlibrary,
            meta,
            external_id=item.external_id,
            source=item.source,
        )
        fixed_meta = enrich_author_entry_images(
            book_clients,
            fixed_meta,
            allow_openlibrary=True,
        )
    else:
        fixed_meta = enrich_author_entry_images(
            book_clients,
            meta,
            allow_openlibrary=False,
            max_image_lookups=3,
        )
    if fixed_meta is meta:
        return book
    if db is not None:
        stored = item.provider_payload if isinstance(item.provider_payload, dict) else {}
        patch: dict[str, object] = {
            "authorEntries": fixed_meta.get("authorEntries"),
            BOOK_DETAIL_ENRICHED_KEY: True,
        }
        work_id = fixed_meta.get("openLibraryWorkId")
        if isinstance(work_id, str) and work_id.strip():
            patch["openLibraryWorkId"] = work_id.strip()
        item.provider_payload = merge_book_metadata(stored, patch)
        db.commit()
        db.refresh(item)
    return replace(book, metadata=fixed_meta)


def _apply_enriched_book_to_media_item(item: MediaItem, book: OpenLibraryBook) -> None:
    if book.description:
        current = (item.description or "").strip()
        incoming = book.description.strip()
        if len(incoming) > len(current):
            item.description = incoming
    if book.subtitle and not (item.subtitle or "").strip():
        item.subtitle = book.subtitle
    if book.image_url and not item.image_url:
        item.image_url = book.image_url
    from .book_catalog_resolver import merge_book_metadata

    old_meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    merged = merge_book_metadata(old_meta, dict(book.metadata))
    merged[BOOK_DETAIL_ENRICHED_KEY] = True
    item.provider_payload = merged


def apply_book_catalog_lookup(
    db: Session,
    book_clients: BookCatalogClients,
    *,
    media_id: str,
    payload: ApplyBookCatalogLookupRequest,
) -> ApplyBookCatalogLookupResponse:
    from .book_edit_service import fetch_book_snapshot_by_lookup
    from .import_pending_service import is_catalog_pending_item

    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="username is required.")

    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id.strip()))
    if item is None or item.media_type != "book":
        raise HTTPException(status_code=404, detail="Book not found.")
    if is_catalog_pending_item(item):
        raise HTTPException(
            status_code=400,
            detail="Use resolve-pending for import placeholders.",
        )

    source = payload.source.strip().lower()
    external_id = payload.externalId.strip()
    if not source or not external_id:
        raise HTTPException(status_code=400, detail="source and externalId are required.")

    snapshot = fetch_book_snapshot_by_lookup(
        book_clients,
        source=source,
        external_id=external_id,
        isbn=payload.isbn,
        title=payload.title,
        authors=payload.authors,
    )
    if snapshot is None:
        raise HTTPException(status_code=404, detail="Book not found in catalog provider.")

    _apply_enriched_book_to_media_item(item, snapshot)
    if snapshot.title and snapshot.title.strip():
        item.title = snapshot.title.strip()
    db.commit()
    db.refresh(item)
    lookup_tracking_for_catalog(db, username=username, media_item=item)
    return ApplyBookCatalogLookupResponse(mediaId=str(item.id))


def get_book_catalog_detail(
    db: Session,
    _settings: Settings,
    book_clients: BookCatalogClients,
    *,
    media_id: str,
    username: str | None,
    force_refresh: bool = False,
) -> MovieCatalogDetailResponse:
    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is None or item.media_type != "book":
        raise HTTPException(status_code=404, detail="Book not found.")

    from .import_pending_service import get_pending_catalog_detail, is_catalog_pending_item

    if is_catalog_pending_item(item):
        return get_pending_catalog_detail(db, media_id=media_id, username=username)

    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    if item.source == "googlebooks":
        if not book_detail_response_can_use_cache(updated_at=item.updated_at, metadata=meta):
            raise HTTPException(
                status_code=404,
                detail="Cached metadata is missing for this googlebooks title.",
            )
        book = _legacy_catalog_book_from_media_item(item)
        tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
        return serialize_openlibrary_book_catalog_detail(
            item=item,
            book=book,
            tracking=tracking,
        )

    if item.source in {"porbase", "hardcover", "openlibrary"}:
        if force_refresh:
            return _get_book_catalog_detail_enrich_all(
                db,
                book_clients,
                item=item,
                meta=meta,
                username=username,
            )
        return _get_book_catalog_detail_live(
            db,
            book_clients,
            item=item,
            meta=meta,
            username=username,
        )

    raise HTTPException(status_code=400, detail="Unsupported book catalog source.")


def _get_book_catalog_detail_enrich_all(
    db: Session,
    book_clients: BookCatalogClients,
    *,
    item: MediaItem,
    meta: dict[str, object],
    username: str | None,
) -> MovieCatalogDetailResponse:
    from .book_catalog_resolver import enrich_book_from_all_providers

    book, notes = enrich_book_from_all_providers(
        book_clients,
        title=item.title,
        external_id=item.external_id,
        source=item.source,
        metadata=meta,
        description=item.description,
        subtitle=item.subtitle,
        image_url=item.image_url,
    )
    _apply_enriched_book_to_media_item(item, book)
    db.commit()
    db.refresh(item)

    response_book = _book_for_catalog_detail_response(book_clients, item, db=db)

    if notes:
        logger.info(
            "Book %s enrich notes: %s",
            item.id,
            " | ".join(notes),
        )

    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
    return serialize_openlibrary_book_catalog_detail(
        item=item,
        book=response_book,
        tracking=tracking,
    )


def _get_book_catalog_detail_live(
    db: Session,
    book_clients: BookCatalogClients,
    *,
    item: MediaItem,
    meta: dict[str, object],
    username: str | None,
) -> MovieCatalogDetailResponse:
    book = _book_for_catalog_detail_response(book_clients, item, db=db)
    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
    return serialize_openlibrary_book_catalog_detail(
        item=item,
        book=book,
        tracking=tracking,
    )


def _require_book_media_item(db: Session, media_id: str) -> MediaItem:
    item = db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    if item is None or item.media_type != "book":
        raise HTTPException(status_code=404, detail="Book not found.")
    return item


def get_book_edit_fields(db: Session, *, media_id: str) -> BookEditFieldsResponse:
    from ..schemas import BookEditFieldInfo
    from .book_edit_service import list_book_edit_fields

    item = _require_book_media_item(db, media_id)
    rows = list_book_edit_fields(item)
    return BookEditFieldsResponse(
        mediaId=item.id,
        fields=[BookEditFieldInfo.model_validate(row) for row in rows],
    )


def search_books_for_edit(
    book_clients: BookCatalogClients,
    *,
    query: str,
    limit: int = 20,
    sources: str | None = None,
) -> BookEditSearchResponse:
    from .book_catalog_policy import parse_search_sources_param
    from .book_edit_service import search_books_for_edit as _search

    text = (query or "").strip()
    rows = _search(
        book_clients,
        query=text,
        limit=limit,
        sources=parse_search_sources_param(sources),
    )
    return BookEditSearchResponse(
        query=text,
        results=[BookEditSearchHit.model_validate(row) for row in rows],
    )


def get_book_field_options(
    db: Session,
    book_clients: BookCatalogClients,
    *,
    media_id: str,
    field_key: str,
    lookup_source: str | None = None,
    lookup_external_id: str | None = None,
    lookup_isbn: str | None = None,
    lookup_title: str | None = None,
    lookup_authors: str | None = None,
    search_query: str | None = None,
) -> BookFieldOptionsResponse:
    from ..schemas import BookFieldOption
    from .book_edit_service import get_book_field_options as _field_options

    item = _require_book_media_item(db, media_id)
    payload = _field_options(
        book_clients,
        item,
        field_key=field_key,
        lookup_source=lookup_source,
        lookup_external_id=lookup_external_id,
        lookup_isbn=lookup_isbn,
        lookup_title=lookup_title,
        lookup_authors=lookup_authors,
        search_query=search_query,
    )
    return BookFieldOptionsResponse(
        field=str(payload["field"]),
        label=str(payload["label"]),
        multiline=bool(payload.get("multiline")),
        currentValue=str(payload.get("currentValue") or ""),
        options=[BookFieldOption.model_validate(row) for row in payload.get("options", [])],
    )


def patch_book_catalog_edit(
    db: Session,
    _settings: Settings,
    book_clients: BookCatalogClients,
    *,
    media_id: str,
    payload: BookEditPatchRequest,
    username: str | None,
) -> MovieCatalogDetailResponse:
    from .book_edit_service import patch_book_catalog_edit as _patch_book

    item = _require_book_media_item(db, media_id)
    item = _patch_book(
        db,
        item,
        fields=dict(payload.fields),
        field_sources=payload.fieldSources,
        metadata_patches=list(payload.metadataPatches),
    )
    book = _book_for_catalog_detail_response(book_clients, item, db=db)
    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item)
    return serialize_openlibrary_book_catalog_detail(
        item=item,
        book=book,
        tracking=tracking,
    )


