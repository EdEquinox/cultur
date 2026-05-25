from __future__ import annotations

from ..backend_models import MediaItem
from ..bgg_client import BggBoardgame
from ..catalog_person_ids import author_person_id_from_entry
from ..openlibrary_client import OpenLibraryBook, split_book_subjects_for_display, subjects_list_from_metadata
from ..igdb_client import IgdbGame
from ..omdb_client import OmdbMovie
from ..igdb_client import IgdbCompanyCatalogDetail, IgdbCompanyCatalogGame
from ..schemas import (
    BackendMediaResponse,
    BackendTrackingResponse,
    BookPublisherRef,
    GameCollectionRef,
    GameCompanyCatalogDetailResponse,
    GameCompanyCatalogItem,
    GameCompanyRef,
    GameFranchiseRef,
    GameTimeToBeat,
    MovieCatalogDetailResponse,
    MovieDetailCrewGroup,
    MovieDetailLink,
    MovieDetailMetric,
    MovieDetailPerson,
    MovieDetailVideo,
    PersonCatalogDetailResponse,
    PersonFilmographyItem,
    TvNextEpisodeCardResponse,
    WatchedEpisodeResponse,
)
from ..tmdb_client import (
    TmdbCrewGroup,
    TmdbLink,
    TmdbMovieDetail,
    TmdbPerson,
    TmdbVideo,
)
from .backend import serialize_media_item


def serialize_tmdb_person(person: TmdbPerson) -> MovieDetailPerson:
    return MovieDetailPerson(
        personId=person.person_id,
        name=person.name,
        role=person.role,
        imageUrl=person.image_url,
    )


def serialize_tmdb_crew_group(group: TmdbCrewGroup) -> MovieDetailCrewGroup:
    return MovieDetailCrewGroup(
        title=group.title,
        people=[serialize_tmdb_person(person) for person in group.people],
    )


def serialize_tmdb_video(video: TmdbVideo) -> MovieDetailVideo:
    return MovieDetailVideo(
        title=video.title,
        subtitle=video.subtitle,
        imageUrl=video.image_url,
        url=video.url,
    )


def serialize_tmdb_link(link: TmdbLink) -> MovieDetailLink:
    return MovieDetailLink(label=link.label, url=link.url)


def serialize_videos_from_game_metadata(meta: dict[str, object]) -> list[MovieDetailVideo]:
    raw = meta.get("videos")
    if not isinstance(raw, list):
        return []
    videos: list[MovieDetailVideo] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        title = entry.get("title")
        if not isinstance(title, str) or not title.strip():
            continue
        subtitle = entry.get("subtitle")
        image_url = entry.get("imageUrl")
        url = entry.get("url")
        videos.append(
            MovieDetailVideo(
                title=title.strip(),
                subtitle=subtitle if isinstance(subtitle, str) and subtitle.strip() else None,
                imageUrl=image_url if isinstance(image_url, str) and image_url.strip() else None,
                url=url if isinstance(url, str) and url.strip() else None,
            ),
        )
    return videos


def _serialize_company_catalog_item(
    *,
    media: MediaItem,
    roles: tuple[str, ...] | list[str],
) -> GameCompanyCatalogItem:
    return GameCompanyCatalogItem(
        media=serialize_media_item(media),
        roles=list(roles),
    )


def serialize_company_catalog_detail(
    *,
    bundle: IgdbCompanyCatalogDetail,
    catalog: list[GameCompanyCatalogItem],
    popular_catalog: list[GameCompanyCatalogItem],
    links: list[TmdbLink],
    primary_role: str | None,
) -> GameCompanyCatalogDetailResponse:
    return GameCompanyCatalogDetailResponse(
        companyId=bundle.company_id,
        name=bundle.name,
        description=bundle.description,
        primaryRole=primary_role,
        imageUrl=bundle.logo_url,
        catalog=catalog,
        popularCatalog=popular_catalog,
        links=[serialize_tmdb_link(link) for link in links],
    )


def serialize_person_catalog_detail(
    *,
    person_id: str,
    name: str,
    biography: str | None,
    known_for_department: str | None,
    image_url: str | None,
    gender: str | None,
    birthday: str | None,
    place_of_birth: str | None,
    filmography: list[PersonFilmographyItem],
    popular_filmography: list[PersonFilmographyItem],
    links: list[TmdbLink],
) -> PersonCatalogDetailResponse:
    return PersonCatalogDetailResponse(
        personId=person_id,
        name=name,
        biography=biography,
        knownForDepartment=known_for_department,
        imageUrl=image_url,
        gender=gender,
        birthday=birthday,
        placeOfBirth=place_of_birth,
        filmography=filmography,
        popularFilmography=popular_filmography,
        links=[serialize_tmdb_link(link) for link in links],
    )


def serialize_openlibrary_book_catalog_detail(
    *,
    item: MediaItem,
    book: OpenLibraryBook,
    tracking: BackendTrackingResponse | None,
) -> MovieCatalogDetailResponse:
    meta = dict(book.metadata) if isinstance(book.metadata, dict) else {}
    item_meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    if not meta.get("isbn") and isinstance(item_meta.get("isbn"), str) and item_meta["isbn"].strip():
        meta["isbn"] = item_meta["isbn"].strip()
    ratings: list[MovieDetailMetric] = []
    ol_rating = meta.get("openLibraryRating")
    if isinstance(ol_rating, (int, float)) and float(ol_rating) > 0:
        ratings.append(MovieDetailMetric(label="Open Library", value=f"{float(ol_rating):.2f}"))

    facts: list[MovieDetailMetric] = []
    year = meta.get("firstPublishYear")
    if isinstance(year, (int, str)) and str(year).strip():
        facts.append(MovieDetailMetric(label="First published", value=str(year).strip()))
    page_count = meta.get("pageCount")
    if isinstance(page_count, int) and page_count > 0:
        facts.append(MovieDetailMetric(label="Pages", value=str(page_count)))
    language = meta.get("bookLanguage")
    if isinstance(language, str) and language.strip():
        facts.append(MovieDetailMetric(label="Language", value=language.strip()))
    isbn = meta.get("isbn")
    if isinstance(isbn, str) and isbn.strip():
        facts.append(MovieDetailMetric(label="ISBN", value=isbn.strip()))

    subjects = subjects_list_from_metadata(meta)
    genres, keywords = split_book_subjects_for_display(subjects)

    links: list[MovieDetailLink] = []
    porbase_url = meta.get("porbaseUrl")
    if isinstance(porbase_url, str) and porbase_url.startswith("http"):
        links.append(MovieDetailLink(label="PORBASE", url=porbase_url))
    hc_url = meta.get("hardcoverUrl")
    if isinstance(hc_url, str) and hc_url.startswith("http"):
        links.append(MovieDetailLink(label="Hardcover", url=hc_url))
    gb_url = meta.get("googleBooksUrl")
    if isinstance(gb_url, str) and gb_url.startswith("http"):
        links.append(MovieDetailLink(label="Google Books", url=gb_url))
    ol_url = meta.get("openLibraryUrl")
    if isinstance(ol_url, str) and ol_url.startswith("http"):
        links.append(MovieDetailLink(label="Open Library", url=ol_url))
    series_url = meta.get("openLibrarySeriesUrl")
    if isinstance(series_url, str) and series_url.startswith("http"):
        links.append(MovieDetailLink(label="Series on Open Library", url=series_url))
    hc_series_url = meta.get("hardcoverSeriesUrl")
    if isinstance(hc_series_url, str) and hc_series_url.startswith("http"):
        links.append(MovieDetailLink(label="Series on Hardcover", url=hc_series_url))

    cast: list[MovieDetailPerson] = []
    author_entries = meta.get("authorEntries")
    if isinstance(author_entries, list):
        for entry in author_entries:
            if not isinstance(entry, dict):
                continue
            author_id = str(entry.get("id") or "").strip()
            name = str(entry.get("name") or "").strip()
            if not name:
                continue
            image_url = entry.get("imageUrl")
            person_id = author_person_id_from_entry(entry)
            cast.append(
                MovieDetailPerson(
                    personId=person_id,
                    name=name,
                    role="Author",
                    imageUrl=str(image_url).strip() if isinstance(image_url, str) and image_url.strip() else None,
                ),
            )
    if not cast:
        authors_raw = meta.get("authors")
        if isinstance(authors_raw, str) and authors_raw.strip():
            for name in authors_raw.split(","):
                clean = name.strip()
                if clean:
                    cast.append(MovieDetailPerson(name=clean, role="Author"))

    book_publishers: list[BookPublisherRef] = []
    publisher_entries = meta.get("publisherEntries")
    if isinstance(publisher_entries, list):
        for entry in publisher_entries:
            if not isinstance(entry, dict):
                continue
            publisher_id = str(entry.get("id") or "").strip()
            name = str(entry.get("name") or "").strip()
            if not publisher_id or not name:
                continue
            book_publishers.append(BookPublisherRef(publisherId=publisher_id, name=name))

    if tracking is not None and tracking.score is not None and tracking.score > 0:
        ratings.append(
            MovieDetailMetric(label="Your rating", value=f"{tracking.score:.1f}"),
        )

    return MovieCatalogDetailResponse(
        media=serialize_media_item(item),
        overview=book.description,
        galleryUrls=[],
        genres=genres,
        keywords=keywords,
        ratings=ratings,
        facts=facts,
        cast=cast,
        videos=[],
        links=links,
        recommendations=[],
        bookPublishers=book_publishers,
        tracking=tracking,
    )


def serialize_bgg_boardgame_catalog_detail(
    *,
    item: MediaItem,
    game: BggBoardgame,
    tracking: BackendTrackingResponse | None,
) -> MovieCatalogDetailResponse:
    meta = game.metadata if isinstance(game.metadata, dict) else {}
    ratings: list[MovieDetailMetric] = []
    average = meta.get("bggAverage")
    if isinstance(average, str) and average and average != "0":
        ratings.append(MovieDetailMetric(label="BGG avg", value=average))
    bayes = meta.get("bggBayesAverage")
    if isinstance(bayes, str) and bayes and bayes != "0":
        ratings.append(MovieDetailMetric(label="BGG geek", value=bayes))
    rank = meta.get("bggRank")
    if isinstance(rank, str) and rank and rank != "Not Ranked":
        ratings.append(MovieDetailMetric(label="BGG rank", value=f"#{rank}"))

    facts: list[MovieDetailMetric] = []
    year = meta.get("yearPublished")
    if isinstance(year, str) and year:
        facts.append(MovieDetailMetric(label="Published", value=year))

    links: list[MovieDetailLink] = []
    bgg_url = meta.get("bggUrl")
    if isinstance(bgg_url, str) and bgg_url.startswith("http"):
        links.append(MovieDetailLink(label="BoardGameGeek", url=bgg_url))

    return MovieCatalogDetailResponse(
        media=serialize_media_item(item),
        overview=game.description,
        galleryUrls=[],
        genres=[],
        ratings=ratings,
        facts=facts,
        videos=[],
        links=links,
        recommendations=[],
        tracking=tracking,
    )


def serialize_igdb_game_catalog_detail(
    *,
    item: MediaItem,
    game: IgdbGame,
    tracking: BackendTrackingResponse | None,
    recommendations: list[MediaItem] | None = None,
) -> MovieCatalogDetailResponse:
    meta = game.metadata if isinstance(game.metadata, dict) else {}
    ratings: list[MovieDetailMetric] = []
    igdb_rating = meta.get("igdbRating")
    if isinstance(igdb_rating, (int, float)) and float(igdb_rating) > 0:
        ratings.append(MovieDetailMetric(label="IGDB", value=f"{float(igdb_rating):.1f}"))
    aggregated = meta.get("aggregatedRating")
    if isinstance(aggregated, (int, float)) and float(aggregated) > 0:
        ratings.append(MovieDetailMetric(label="Critics", value=f"{float(aggregated):.1f}"))
    user_rating = meta.get("userRating")
    if isinstance(user_rating, (int, float)) and float(user_rating) > 0:
        ratings.append(MovieDetailMetric(label="Users", value=f"{float(user_rating):.1f}"))

    facts: list[MovieDetailMetric] = []
    year = meta.get("firstReleaseDate")
    if isinstance(year, str) and year:
        facts.append(MovieDetailMetric(label="Release", value=year))
    platforms = meta.get("platforms")
    if isinstance(platforms, str) and platforms:
        facts.append(MovieDetailMetric(label="Platforms", value=platforms))
    genres = meta.get("genres")
    if isinstance(genres, str) and genres:
        facts.append(MovieDetailMetric(label="Genres", value=genres))

    genre_list: list[str] = []
    if isinstance(genres, str) and genres:
        genre_list = [part.strip() for part in genres.split(",") if part.strip()]

    links: list[MovieDetailLink] = []
    igdb_url = meta.get("igdbUrl")
    if isinstance(igdb_url, str) and igdb_url.startswith("http"):
        links.append(MovieDetailLink(label="IGDB", url=igdb_url))

    game_time_to_beat: GameTimeToBeat | None = None
    main_ttb = meta.get("timeToBeatMain")
    extras_ttb = meta.get("timeToBeatExtras")
    completion_ttb = meta.get("timeToBeatCompletion")
    if any(isinstance(v, str) and v for v in (main_ttb, extras_ttb, completion_ttb)):
        game_time_to_beat = GameTimeToBeat(
            main=main_ttb if isinstance(main_ttb, str) else None,
            extras=extras_ttb if isinstance(extras_ttb, str) else None,
            completion=completion_ttb if isinstance(completion_ttb, str) else None,
        )

    game_franchise: GameFranchiseRef | None = None
    franchise_raw = meta.get("franchise")
    if isinstance(franchise_raw, dict):
        fid = franchise_raw.get("id")
        fname = franchise_raw.get("name")
        if isinstance(fid, str) and isinstance(fname, str) and fid and fname:
            slug_val = franchise_raw.get("slug")
            kind_val = franchise_raw.get("kind")
            game_franchise = GameFranchiseRef(
                franchiseId=fid,
                name=fname,
                slug=slug_val if isinstance(slug_val, str) and slug_val else None,
                seriesKind=kind_val if isinstance(kind_val, str) and kind_val else None,
            )

    game_collections: list[GameCollectionRef] = []
    collections_raw = meta.get("collections")
    if isinstance(collections_raw, list):
        for entry in collections_raw:
            if not isinstance(entry, dict):
                continue
            cid = entry.get("id")
            cname = entry.get("name")
            if not isinstance(cid, str) or not isinstance(cname, str) or not cid or not cname:
                continue
            slug_val = entry.get("slug")
            game_collections.append(
                GameCollectionRef(
                    collectionId=cid,
                    name=cname,
                    slug=slug_val if isinstance(slug_val, str) and slug_val else None,
                ),
            )

    if recommendations is not None:
        recommendation_rows = [serialize_media_item(rec) for rec in recommendations]
    else:
        recommendation_rows = []

    game_type_val = meta.get("gameType")
    game_type = game_type_val if isinstance(game_type_val, str) and game_type_val.strip() else None

    game_modes: list[str] = []
    modes_raw = meta.get("gameModes")
    if isinstance(modes_raw, str) and modes_raw.strip():
        game_modes = [part.strip() for part in modes_raw.split(",") if part.strip()]

    player_perspectives: list[str] = []
    perspectives_raw = meta.get("playerPerspectives")
    if isinstance(perspectives_raw, str) and perspectives_raw.strip():
        player_perspectives = [
            part.strip() for part in perspectives_raw.split(",") if part.strip()
        ]

    gallery_raw = meta.get("galleryUrls")
    gallery_urls: list[str] = []
    if isinstance(gallery_raw, list):
        gallery_urls = [
            str(u).strip()
            for u in gallery_raw
            if isinstance(u, str) and str(u).strip().startswith("http")
        ]

    return MovieCatalogDetailResponse(
        media=serialize_media_item(item),
        overview=game.description,
        galleryUrls=gallery_urls,
        genres=genre_list,
        ratings=ratings,
        facts=facts,
        videos=serialize_videos_from_game_metadata(meta),
        links=links,
        gamePublishers=[
            GameCompanyRef(companyId=c.external_id, name=c.name) for c in game.publishers
        ],
        gameDevelopers=[
            GameCompanyRef(companyId=c.external_id, name=c.name) for c in game.developers
        ],
        gameTimeToBeat=game_time_to_beat,
        gameFranchise=game_franchise,
        gameCollections=game_collections,
        gameType=game_type,
        gameModes=game_modes,
        playerPerspectives=player_perspectives,
        recommendations=recommendation_rows,
        tracking=tracking,
    )


def serialize_movie_catalog_detail(
    *,
    item: MediaItem,
    detail: TmdbMovieDetail,
    recommendations: list[MediaItem],
    tracking: BackendTrackingResponse | None,
    omdb_movie: OmdbMovie | None,
    watched_episodes: list[WatchedEpisodeResponse] | None = None,
    next_episode_card: TvNextEpisodeCardResponse | None = None,
) -> MovieCatalogDetailResponse:
    ratings = [
        MovieDetailMetric(label=label, value=value)
        for label, value in detail.ratings.items()
        if value
    ]
    facts = [
        MovieDetailMetric(label=label, value=value)
        for label, value in detail.facts.items()
        if value
    ]

    if omdb_movie is not None:
        omdb_ratings = {
            "IMDb": omdb_movie.metadata.get("imdbRating"),
            "Metascore": omdb_movie.metadata.get("metascore"),
            "Rotten Tomatoes": omdb_movie.metadata.get("rottenTomatoes"),
        }
        for label, value in omdb_ratings.items():
            if isinstance(value, str) and value:
                ratings.append(MovieDetailMetric(label=label, value=value))

    return MovieCatalogDetailResponse(
        media=serialize_media_item(item),
        overview=omdb_movie.description if omdb_movie and omdb_movie.description else detail.movie.description,
        backdropUrl=detail.backdrop_url,
        galleryUrls=detail.gallery_urls,
        genres=detail.genres,
        keywords=detail.keywords,
        ratings=ratings,
        facts=facts,
        cast=[serialize_tmdb_person(person) for person in detail.cast],
        crew=[serialize_tmdb_crew_group(group) for group in detail.crew_groups],
        videos=[serialize_tmdb_video(video) for video in detail.videos],
        recommendations=[serialize_media_item(recommendation) for recommendation in recommendations],
        links=[serialize_tmdb_link(link) for link in detail.links],
        tracking=tracking,
        watchedEpisodes=list(watched_episodes or []),
        nextEpisodeCard=next_episode_card,
    )


def serialize_pending_catalog_detail(
    *,
    item: MediaItem,
    tracking: BackendTrackingResponse | None,
) -> MovieCatalogDetailResponse:
    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    import_source = meta.get("importSource")
    type_label = {
        "movie": "movie",
        "tv": "TV series",
        "game": "game",
        "book": "book",
        "boardgame": "board game",
    }.get(item.media_type, "item")

    overview_parts: list[str] = [
        f"This {type_label} could not be matched automatically in the catalog.",
        "Use “Search catalog” to link the correct entry. Your tracking (status, score, notes) is kept.",
    ]
    for key, label in (
        ("stashSourceFile", "Import file"),
        ("bookmorySourceFile", "Import file"),
        ("avaBackupHint", "Backup"),
    ):
        val = meta.get(key)
        if isinstance(val, str) and val.strip():
            overview_parts.append(f"{label}: {val.strip()}")

    gallery: list[str] = []
    if item.image_url and str(item.image_url).startswith("http"):
        gallery.append(str(item.image_url))

    return MovieCatalogDetailResponse(
        media=serialize_media_item(item),
        overview="\n\n".join(overview_parts),
        galleryUrls=gallery,
        tracking=tracking,
        catalogPending=True,
        importSource=import_source if isinstance(import_source, str) else None,
    )


def serialize_pending_game_catalog_detail(
    *,
    item: MediaItem,
    tracking: BackendTrackingResponse | None,
) -> MovieCatalogDetailResponse:
    return serialize_pending_catalog_detail(item=item, tracking=tracking)
