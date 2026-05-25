from __future__ import annotations

import threading
import time
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import date

import requests


class TmdbError(RuntimeError):
    pass


def _person_gender_label(raw: object) -> str | None:
    try:
        code = int(raw)
    except (TypeError, ValueError):
        return None
    return {
        1: "Female",
        2: "Male",
        3: "Non-binary",
    }.get(code)


def _format_person_birthday(raw: object) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text or text.startswith("0000"):
        return None
    try:
        parsed = date.fromisoformat(text[:10])
    except ValueError:
        return text
    return f"{parsed.strftime('%B')} {parsed.day}, {parsed.year}"


class _TtlLruCache:
    """Process-wide bounded cache with TTL (monotonic clock)."""

    def __init__(self, *, ttl_sec: float, max_items: int) -> None:
        self._ttl = ttl_sec
        self._max = max_items
        self._lock = threading.Lock()
        self._data: OrderedDict[object, tuple[object, float]] = OrderedDict()

    def get(self, key: object) -> object | None:
        now = time.monotonic()
        with self._lock:
            item = self._data.get(key)
            if item is None:
                return None
            val, exp = item
            if exp < now:
                del self._data[key]
                return None
            self._data.move_to_end(key, last=True)
            return val

    def set(self, key: object, value: object) -> None:
        now = time.monotonic()
        exp = now + self._ttl
        with self._lock:
            self._data.pop(key, None)
            self._data[key] = (value, exp)
            self._data.move_to_end(key, last=True)
            while len(self._data) > self._max:
                self._data.popitem(last=False)


# Shared across requests: TMDB show/season payloads are user-agnostic.
_TV_HOME_DETAIL_CACHE = _TtlLruCache(ttl_sec=150.0, max_items=512)
_TV_SEASON_LIGHT_CACHE = _TtlLruCache(ttl_sec=150.0, max_items=2048)


TMDB_MOVIE_GENRE_NAMES: dict[int, str] = {
    28: "Action",
    12: "Adventure",
    16: "Animation",
    35: "Comedy",
    80: "Crime",
    99: "Documentary",
    18: "Drama",
    10751: "Family",
    14: "Fantasy",
    36: "History",
    27: "Horror",
    10402: "Music",
    9648: "Mystery",
    10749: "Romance",
    878: "Science Fiction",
    10770: "TV Movie",
    53: "Thriller",
    10752: "War",
    37: "Western",
}

TMDB_TV_GENRE_NAMES: dict[int, str] = {
    10759: "Action & Adventure",
    16: "Animation",
    35: "Comedy",
    80: "Crime",
    99: "Documentary",
    18: "Drama",
    10751: "Family",
    10762: "Kids",
    9648: "Mystery",
    10763: "News",
    10764: "Reality",
    10765: "Sci-Fi & Fantasy",
    10766: "Soap",
    10767: "Talk",
    10768: "War & Politics",
    37: "Western",
}


def tmdb_genre_names(media_type: str, genre_ids: tuple[int, ...]) -> list[str]:
    mapping = TMDB_TV_GENRE_NAMES if media_type == "tv" else TMDB_MOVIE_GENRE_NAMES
    return [mapping.get(gid, f"Genre {gid}") for gid in genre_ids]


def _parse_tmdb_genre_ids(raw: object) -> tuple[int, ...]:
    if not isinstance(raw, list):
        return ()
    out: list[int] = []
    for value in raw:
        if isinstance(value, int):
            out.append(value)
        elif isinstance(value, str) and value.strip().isdigit():
            out.append(int(value.strip(), 10))
    return tuple(out)


@dataclass(frozen=True, slots=True)
class TmdbMovie:
    external_id: str
    title: str
    subtitle: str | None
    description: str | None
    image_url: str | None
    metadata: dict[str, object]


@dataclass(frozen=True, slots=True)
class TmdbPerson:
    person_id: str | None
    name: str
    role: str | None
    image_url: str | None


@dataclass(frozen=True, slots=True)
class TmdbPersonFilmCredit:
    movie: TmdbMovie
    role: str | None
    media_type: str
    credit_kind: str
    department: str | None
    genre_ids: tuple[int, ...]
    vote_average: float | None
    episode_count: int | None
    popularity: float = 0.0


@dataclass(frozen=True, slots=True)
class TmdbPersonCatalogDetail:
    person_id: str
    name: str
    biography: str | None
    image_url: str | None
    known_for_department: str | None
    gender: str | None
    birthday: str | None
    place_of_birth: str | None
    movie_credits: list[TmdbPersonFilmCredit]
    popular_movie_credits: list[TmdbPersonFilmCredit]
    imdb_id: str | None


@dataclass(frozen=True, slots=True)
class TmdbCrewGroup:
    title: str
    people: list[TmdbPerson]


# TMDB `crew[].department` values — known departments first, then alphabetical.
_CREW_DEPARTMENT_ORDER: tuple[str, ...] = (
    "Directing",
    "Writing",
    "Production",
    "Sound",
    "Camera",
    "Editing",
    "Art",
    "Costume & Make-Up",
    "Visual Effects",
    "Lighting",
    "Crew",
)


def _crew_department_sort_key(department: str) -> tuple[int, str]:
    try:
        return (_CREW_DEPARTMENT_ORDER.index(department), department)
    except ValueError:
        return (len(_CREW_DEPARTMENT_ORDER), department.casefold())


def _crew_groups_sorted(grouped: dict[str, list[TmdbPerson]]) -> list[TmdbCrewGroup]:
    return [
        TmdbCrewGroup(title=title, people=people)
        for title, people in sorted(
            grouped.items(),
            key=lambda item: _crew_department_sort_key(item[0]),
        )
        if people
    ]


@dataclass(frozen=True, slots=True)
class TmdbVideo:
    title: str
    subtitle: str | None
    image_url: str | None
    url: str | None


@dataclass(frozen=True, slots=True)
class TmdbLink:
    label: str
    url: str


@dataclass(frozen=True, slots=True)
class TmdbMovieDetail:
    movie: TmdbMovie
    backdrop_url: str | None
    gallery_urls: list[str]
    genres: list[str]
    keywords: list[str]
    facts: dict[str, str]
    ratings: dict[str, str]
    cast: list[TmdbPerson]
    crew_groups: list[TmdbCrewGroup]
    videos: list[TmdbVideo]
    recommendations: list[TmdbMovie]
    links: list[TmdbLink]
    tv_last_episode: TmdbTvEpisodeTeaser | None = None
    tv_next_episode: TmdbTvEpisodeTeaser | None = None


@dataclass(frozen=True, slots=True)
class TmdbTvEpisodeTeaser:
    name: str | None
    air_date: str | None
    season_number: int | None
    episode_number: int | None
    still_url: str | None = None
    runtime_minutes: int | None = None


@dataclass(frozen=True, slots=True)
class TmdbTvAiringBrief:
    next_episode: TmdbTvEpisodeTeaser | None
    last_episode: TmdbTvEpisodeTeaser | None


@dataclass(frozen=True, slots=True)
class TmdbTvSeasonSummary:
    season_number: int
    name: str
    episode_count: int
    air_date: str | None
    overview: str | None
    poster_url: str | None


@dataclass(frozen=True, slots=True)
class TmdbTvEpisodeCatalog:
    episode_number: int
    name: str
    overview: str | None
    air_date: str | None
    still_url: str | None
    runtime_minutes: int | None
    vote_average: float | None
    guest_stars: tuple[TmdbPerson, ...] = ()


@dataclass(frozen=True, slots=True)
class TmdbTvSeasonDetail:
    season_number: int
    name: str
    overview: str | None
    air_date: str | None
    poster_url: str | None
    episodes: list[TmdbTvEpisodeCatalog]
    season_cast: tuple[TmdbPerson, ...] = ()
    vote_average: float | None = None
    directors: tuple[TmdbPerson, ...] = ()


@dataclass(frozen=True, slots=True)
class TmdbTvEpisodeDetail:
    season_number: int
    episode_number: int
    name: str
    overview: str | None
    air_date: str | None
    still_url: str | None
    runtime_minutes: int | None
    vote_average: float | None
    cast: tuple[TmdbPerson, ...]
    guest_stars: tuple[TmdbPerson, ...]
    directors: tuple[TmdbPerson, ...] = ()


@dataclass(frozen=True, slots=True)
class TmdbTvShowSeasonsBundle:
    show: TmdbMovie
    seasons: list[TmdbTvSeasonSummary]


def _crew_payload_from_tmdb_dict(payload: dict) -> list[object] | None:
    """TMDB movie detail nests crew under `credits`; `/movie/{id}/credits` has `crew` at top level."""
    crew = payload.get("crew")
    if isinstance(crew, list):
        return crew
    nested = payload.get("credits")
    if isinstance(nested, dict):
        inner = nested.get("crew")
        if isinstance(inner, list):
            return inner
    return None


def _coerce_optional_int(value: object) -> int | None:
    """TMDB sometimes returns season/episode numbers as int, float, or string."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.isdigit():
            return int(stripped)
    return None


def _tv_crew_job_is_director(job: str) -> bool:
    jl = job.strip().lower()
    if not jl:
        return False
    noise_substrings = (
        "assistant director",
        "second unit",
        "trainee",
        "art director",
        "casting director",
        "creative director",
        "technical director",
        "lighting director",
        "director of photography",
        "photo director",
    )
    if any(n in jl for n in noise_substrings):
        return False
    positive_substrings = (
        "director",
        "realizador",
        "réalisateur",
        "regisseur",
        "regista",
    )
    return any(p in jl for p in positive_substrings)


def _director_names_from_crew_list(crew: list[object]) -> str | None:
    """Match director-like jobs (incl. localized TMDB labels) and skip common false positives."""
    directors: list[str] = []
    for c in crew:
        if not isinstance(c, dict):
            continue
        job = str(c.get("job") or "").strip()
        if not _tv_crew_job_is_director(job):
            continue
        name = str(c.get("name") or "").strip()
        if name and name not in directors:
            directors.append(name)
    if directors:
        return ", ".join(directors)
    return None


def _director_names_from_credits_or_crew_payload(payload: object) -> str | None:
    if not isinstance(payload, dict):
        return None
    crew = _crew_payload_from_tmdb_dict(payload)
    if crew is None:
        return None
    return _director_names_from_crew_list(crew)


def _director_names_from_tmdb_media_raw(raw: dict) -> str | None:
    """Primary director(s) or TV show creators when TMDB `credits` / `created_by` is present."""
    created = raw.get("created_by")
    if isinstance(created, list) and created:
        names: list[str] = []
        for entry in created[:4]:
            if isinstance(entry, dict):
                n = str(entry.get("name") or "").strip()
                if n:
                    names.append(n)
        if names:
            return ", ".join(names)
    credits = raw.get("credits")
    if isinstance(credits, dict):
        line = _director_names_from_credits_or_crew_payload(credits)
        if line:
            return line
    return None


class TmdbClient:
    def __init__(
        self,
        *,
        api_key: str,
        language: str = "en-US",
        timeout_seconds: float = 20,
    ) -> None:
        self.api_key = api_key
        self.language = language
        self.timeout_seconds = timeout_seconds
        self.base_url = "https://api.themoviedb.org/3"
        self._genre_name_to_id: dict[str, str] | None = None
        self._genre_tv_name_to_id: dict[str, str] | None = None
        self._thread_local = threading.local()

    def fetch_movies(
        self,
        *,
        section: str = "popular",
        query: str | None = None,
        genre: str | None = None,
        keyword: str | None = None,
        page: int = 1,
    ) -> list[TmdbMovie]:
        safe_page = max(1, min(page, 20))

        if query and query.strip():
            response = self._get(
                "/search/movie",
                query=query.strip(),
                page=safe_page,
                include_adult="false",
            )
        elif keyword and keyword.strip():
            keyword_id = self._resolve_keyword_id(keyword.strip())
            if keyword_id is None:
                response = self._get(
                    "/search/movie",
                    query=keyword.strip(),
                    page=safe_page,
                    include_adult="false",
                )
            else:
                response = self._get(
                    "/discover/movie",
                    page=safe_page,
                    with_keywords=keyword_id,
                    sort_by="popularity.desc",
                    include_adult="false",
                )
        elif genre and genre.strip():
            genre_id = self._resolve_genre_id(genre.strip())
            if genre_id is None:
                response = self._get(
                    "/search/movie",
                    query=genre.strip(),
                    page=safe_page,
                    include_adult="false",
                )
            else:
                response = self._get(
                    "/discover/movie",
                    page=safe_page,
                    with_genres=genre_id,
                    sort_by="popularity.desc",
                    include_adult="false",
                )
        else:
            safe_section = section if section in {
                "popular",
                "now_playing",
                "top_rated",
                "upcoming",
            } else "popular"
            response = self._get(f"/movie/{safe_section}", page=safe_page)

        response.raise_for_status()
        payload = response.json()
        raw_results = payload.get("results")
        if not isinstance(raw_results, list):
            raise TmdbError("TMDB returned an invalid response payload.")

        items: list[TmdbMovie] = []
        for raw in raw_results:
            movie = self._movie_from_raw(raw)
            if movie is not None:
                items.append(movie)

        return items

    def fetch_movie_director_line(self, *, movie_id: str) -> str | None:
        """Crew from `/movie/{id}/credits` (list/discover responses omit credits)."""
        response = self._get(f"/movie/{movie_id}/credits")
        try:
            response.raise_for_status()
        except requests.HTTPError:
            return None
        payload = response.json()
        return _director_names_from_credits_or_crew_payload(payload)

    def enrich_movies_directors_from_credits(self, movies: list[TmdbMovie]) -> list[TmdbMovie]:
        missing = [m for m in movies if not str(m.metadata.get("director") or "").strip()]
        if not missing:
            return movies

        lines: dict[str, str] = {}
        workers = min(8, len(missing))
        with ThreadPoolExecutor(max_workers=workers) as pool:
            future_to_id = {
                pool.submit(self.fetch_movie_director_line, movie_id=m.external_id): m.external_id for m in missing
            }
            for fut in as_completed(future_to_id):
                eid = future_to_id[fut]
                try:
                    line = fut.result()
                except (requests.RequestException, TmdbError, OSError, ValueError):
                    line = None
                if line:
                    lines[eid] = line

        out: list[TmdbMovie] = []
        for m in movies:
            existing = str(m.metadata.get("director") or "").strip()
            if existing:
                out.append(m)
                continue
            line = (lines.get(m.external_id) or "").strip()
            if not line:
                out.append(m)
                continue
            meta = dict(m.metadata)
            meta["director"] = line
            out.append(
                TmdbMovie(
                    external_id=m.external_id,
                    title=m.title,
                    subtitle=m.subtitle,
                    description=m.description,
                    image_url=m.image_url,
                    metadata=meta,
                ),
            )
        return out

    def fetch_tmdb_movie_minimal(self, *, movie_id: str) -> TmdbMovie | None:
        """Single-movie TMDB fetch for import paths (arbitrary ids)."""
        try:
            response = self._get(f"/movie/{movie_id}")
            if response.status_code == 404:
                return None
            response.raise_for_status()
        except requests.RequestException:
            return None
        payload = response.json()
        if not isinstance(payload, dict):
            return None
        return self._movie_from_raw(payload)

    def fetch_tmdb_tv_minimal(self, *, tv_id: str) -> TmdbMovie | None:
        try:
            response = self._get(f"/tv/{tv_id}")
            if response.status_code == 404:
                return None
            response.raise_for_status()
        except requests.RequestException:
            return None
        payload = response.json()
        if not isinstance(payload, dict):
            return None
        return self._movie_from_raw(payload)

    def fetch_tv_shows(
        self,
        *,
        section: str = "popular",
        query: str | None = None,
        genre: str | None = None,
        keyword: str | None = None,
        page: int = 1,
    ) -> list[TmdbMovie]:
        safe_page = max(1, min(page, 20))

        if query and query.strip():
            response = self._get(
                "/search/tv",
                query=query.strip(),
                page=safe_page,
                include_adult="false",
            )
        elif keyword and keyword.strip():
            keyword_id = self._resolve_keyword_id(keyword.strip())
            if keyword_id is None:
                response = self._get(
                    "/search/tv",
                    query=keyword.strip(),
                    page=safe_page,
                    include_adult="false",
                )
            else:
                response = self._get(
                    "/discover/tv",
                    page=safe_page,
                    with_keywords=keyword_id,
                    sort_by="popularity.desc",
                    include_adult="false",
                )
        elif genre and genre.strip():
            genre_id = self._resolve_tv_genre_id(genre.strip())
            if genre_id is None:
                response = self._get(
                    "/search/tv",
                    query=genre.strip(),
                    page=safe_page,
                    include_adult="false",
                )
            else:
                response = self._get(
                    "/discover/tv",
                    page=safe_page,
                    with_genres=genre_id,
                    sort_by="popularity.desc",
                    include_adult="false",
                )
        else:
            safe_section = section if section in {
                "popular",
                "on_the_air",
                "top_rated",
                "airing_today",
            } else "popular"
            response = self._get(f"/tv/{safe_section}", page=safe_page)

        response.raise_for_status()
        payload = response.json()
        raw_results = payload.get("results")
        if not isinstance(raw_results, list):
            raise TmdbError("TMDB returned an invalid TV response payload.")

        items: list[TmdbMovie] = []
        for raw in raw_results:
            show = self._movie_from_raw(raw)
            if show is not None:
                items.append(show)

        return items

    def fetch_tv_detail(self, *, tv_id: str) -> TmdbMovieDetail:
        response = self._get(
            f"/tv/{tv_id}",
            append_to_response="credits,videos,recommendations,images,keywords,external_ids",
            include_image_language="en,null",
        )
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise TmdbError("TMDB returned an invalid TV detail payload.")

        show = self._movie_from_raw(payload)
        if show is None:
            raise TmdbError("TMDB returned an incomplete TV detail payload.")

        first_air = str(payload.get("first_air_date") or "").strip()
        last_air = str(payload.get("last_air_date") or "").strip()
        status = str(payload.get("status") or "").strip() or None
        original_name = str(payload.get("original_name") or "").strip() or None
        original_language = str(payload.get("original_language") or "").strip() or None
        spoken_languages = self._string_list_from_objects(
            payload.get("spoken_languages"),
            key="english_name",
        )
        production_countries = self._string_list_from_objects(
            payload.get("production_countries"),
            key="name",
        )
        genres = self._string_list_from_objects(payload.get("genres"), key="name")
        keywords = self._keyword_names_from_payload(payload.get("keywords"))

        seasons = payload.get("number_of_seasons")
        episodes = payload.get("number_of_episodes")
        run_times = payload.get("episode_run_time")
        avg_runtime: str | None = None
        if isinstance(run_times, list) and run_times:
            minutes: list[int] = []
            for x in run_times:
                if isinstance(x, int):
                    minutes.append(x)
                elif isinstance(x, str) and x.strip().isdigit():
                    minutes.append(int(x.strip(), 10))
            if minutes:
                avg = sum(minutes) // len(minutes)
                avg_runtime = f"~{avg} min / episode"

        facts: dict[str, str] = {}
        if original_name and original_name != show.title:
            facts["Original title"] = original_name
        if status:
            facts["Status"] = status
        if first_air:
            facts["First aired"] = first_air
        if last_air:
            facts["Last aired"] = last_air
        if isinstance(seasons, int) and seasons > 0:
            facts["Seasons"] = str(seasons)
        if isinstance(episodes, int) and episodes > 0:
            facts["Episodes"] = f"{episodes:,}"
        if avg_runtime:
            facts["Typical episode length"] = avg_runtime
        if production_countries:
            facts["Countries of production"] = ", ".join(production_countries)
        if spoken_languages:
            facts["Spoken languages"] = ", ".join(spoken_languages)
        if original_language:
            facts["Original language"] = original_language.upper()

        ratings: dict[str, str] = {}
        tmdb_rating = show.metadata.get("tmdbRating")
        if isinstance(tmdb_rating, str) and tmdb_rating:
            ratings["TMDB"] = tmdb_rating
        vote_count = payload.get("vote_count")
        if isinstance(vote_count, int) and vote_count > 0:
            ratings["Votes"] = f"{vote_count:,}"
        if first_air and len(first_air) >= 4:
            ratings["Premiere year"] = first_air[:4]

        backdrop_url = self._image_url(payload.get("backdrop_path"), size="w780")
        gallery_urls = self._parse_gallery_urls(payload)
        cast = self._parse_cast(payload.get("credits"))
        crew_groups = self._parse_crew(payload.get("credits"))
        videos = self._parse_videos(payload.get("videos"))
        recommendations = self._parse_recommendations(payload.get("recommendations"))

        links: list[TmdbLink] = [
            TmdbLink(label="TMDB", url=f"https://www.themoviedb.org/tv/{show.external_id}"),
        ]
        homepage = str(payload.get("homepage") or "").strip()
        if homepage:
            links.append(TmdbLink(label="Homepage", url=homepage))
        ext = payload.get("external_ids")
        imdb_id: str | None = None
        if isinstance(ext, dict):
            raw_imdb = ext.get("imdb_id")
            if raw_imdb is not None:
                candidate = str(raw_imdb).strip()
                imdb_id = candidate or None
        if imdb_id:
            links.append(TmdbLink(label="IMDb", url=f"https://www.imdb.com/title/{imdb_id}/"))

        tv_next = self._parse_tv_episode_teaser(payload.get("next_episode_to_air"))
        tv_last = self._parse_tv_episode_teaser(payload.get("last_episode_to_air"))

        return TmdbMovieDetail(
            movie=show,
            backdrop_url=backdrop_url,
            gallery_urls=gallery_urls,
            genres=genres,
            keywords=keywords,
            facts=facts,
            ratings=ratings,
            cast=cast,
            crew_groups=crew_groups,
            videos=videos,
            recommendations=recommendations,
            links=links,
            tv_last_episode=tv_last,
            tv_next_episode=tv_next,
        )

    def _parse_tv_episode_teaser(self, raw: object) -> TmdbTvEpisodeTeaser | None:
        if not isinstance(raw, dict):
            return None
        air = str(raw.get("air_date") or "").strip() or None
        name = str(raw.get("name") or "").strip() or None
        sn = _coerce_optional_int(raw.get("season_number"))
        en = _coerce_optional_int(raw.get("episode_number"))
        rt = raw.get("runtime")
        runtime_minutes = int(rt) if isinstance(rt, int) else None
        still = self._image_url(raw.get("still_path"), size="w500")
        still_url = still if isinstance(still, str) and still.strip() else None
        return TmdbTvEpisodeTeaser(
            name=name,
            air_date=air,
            season_number=sn,
            episode_number=en,
            still_url=still_url,
            runtime_minutes=runtime_minutes,
        )

    def fetch_tv_airing_brief(self, *, tv_id: str) -> TmdbTvAiringBrief:
        """Lightweight /tv/{id} read for next/last episode to air (home rails)."""
        brief, _bundle = self.fetch_tv_home_detail(tv_id=tv_id)
        return brief

    def fetch_tv_show_seasons_bundle(self, *, tv_id: str) -> TmdbTvShowSeasonsBundle:
        """Single /tv/{id} read for show upsert + season list (no append_to_response)."""
        _brief, bundle = self.fetch_tv_home_detail(tv_id=tv_id)
        return bundle

    def fetch_tv_home_detail(self, *, tv_id: str) -> tuple[TmdbTvAiringBrief, TmdbTvShowSeasonsBundle]:
        """Single GET /tv/{id}: next/last to air plus season summaries (TV home shelves)."""
        cache_key = ("tv_home", self.language, tv_id)
        hit = _TV_HOME_DETAIL_CACHE.get(cache_key)
        if hit is not None:
            return hit  # type: ignore[return-value]

        response = self._get(f"/tv/{tv_id}")
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise TmdbError("TMDB returned an invalid TV payload.")

        next_raw = payload.get("next_episode_to_air")
        last_raw = payload.get("last_episode_to_air")
        brief = TmdbTvAiringBrief(
            next_episode=self._parse_tv_episode_teaser(next_raw),
            last_episode=self._parse_tv_episode_teaser(last_raw),
        )
        show = self._movie_from_raw(payload)
        if show is None:
            raise TmdbError("TMDB returned an incomplete TV payload.")

        seasons = self._parse_tv_season_summaries(payload)
        bundle = TmdbTvShowSeasonsBundle(show=show, seasons=seasons)
        out = (brief, bundle)
        _TV_HOME_DETAIL_CACHE.set(cache_key, out)
        return out

    def fetch_tv_season_detail(
        self,
        *,
        tv_id: str,
        season_number: int,
        include_credits: bool = True,
    ) -> TmdbTvSeasonDetail:
        cache_key: tuple[object, ...] | None = None
        if not include_credits:
            cache_key = ("tv_season_light", self.language, tv_id, season_number)
            hit = _TV_SEASON_LIGHT_CACHE.get(cache_key)
            if hit is not None:
                return hit  # type: ignore[return-value]

        extra: dict[str, object] = {}
        if include_credits:
            extra["append_to_response"] = "credits"
        response = self._get(
            f"/tv/{tv_id}/season/{season_number}",
            **extra,
        )
        if response.status_code == 404:
            raise TmdbError("Season not found.")
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise TmdbError("TMDB returned an invalid season payload.")

        sn = payload.get("season_number")
        season_n = int(sn) if isinstance(sn, int) else season_number
        name = str(payload.get("name") or f"Season {season_n}").strip()
        overview = str(payload.get("overview") or "").strip() or None
        air = str(payload.get("air_date") or "").strip() or None
        poster_url = self._image_url(payload.get("poster_path"), size="w500")
        sva = payload.get("vote_average")
        vote_average = float(sva) if isinstance(sva, (int, float)) and float(sva) > 0 else None

        season_cast: tuple[TmdbPerson, ...] = ()
        crew_directors: tuple[TmdbPerson, ...] = ()
        if include_credits:
            credits_block = payload.get("credits")
            if isinstance(credits_block, dict):
                season_cast = tuple(self._parse_tv_episode_credit_people(credits_block.get("cast"), limit=120))
                crew_directors = self._director_people_from_tv_crew_raw(credits_block.get("crew"))

        episodes: list[TmdbTvEpisodeCatalog] = []
        raw_eps = payload.get("episodes")
        if isinstance(raw_eps, list):
            for raw in raw_eps:
                if not isinstance(raw, dict):
                    continue
                en = raw.get("episode_number")
                if not isinstance(en, int):
                    continue
                ep_name = str(raw.get("name") or f"Episode {en}").strip()
                ep_overview = str(raw.get("overview") or "").strip() or None
                ep_air = str(raw.get("air_date") or "").strip() or None
                still = self._image_url(raw.get("still_path"), size="w500")
                rt = raw.get("runtime")
                runtime_minutes = int(rt) if isinstance(rt, int) else None
                va = raw.get("vote_average")
                vote_ep = float(va) if isinstance(va, (int, float)) else None
                guest_stars = tuple(self._parse_tv_episode_credit_people(raw.get("guest_stars")))
                episodes.append(
                    TmdbTvEpisodeCatalog(
                        episode_number=en,
                        name=ep_name,
                        overview=ep_overview,
                        air_date=ep_air,
                        still_url=still,
                        runtime_minutes=runtime_minutes,
                        vote_average=vote_ep,
                        guest_stars=guest_stars,
                    ),
                )

        episodes.sort(key=lambda e: e.episode_number)

        result = TmdbTvSeasonDetail(
            season_number=season_n,
            name=name,
            overview=overview,
            air_date=air,
            poster_url=poster_url,
            episodes=episodes,
            season_cast=season_cast,
            vote_average=vote_average,
            directors=crew_directors,
        )
        if cache_key is not None:
            _TV_SEASON_LIGHT_CACHE.set(cache_key, result)
        return result

    def fetch_tv_episode_detail(self, *, tv_id: str, season_number: int, episode_number: int) -> TmdbTvEpisodeDetail:
        response = self._get(f"/tv/{tv_id}/season/{season_number}/episode/{episode_number}")
        if response.status_code == 404:
            raise TmdbError("Episode not found.")
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise TmdbError("TMDB returned an invalid episode payload.")

        en = payload.get("episode_number")
        ep_n = int(en) if isinstance(en, int) else episode_number
        sn = payload.get("season_number")
        sn_n = int(sn) if isinstance(sn, int) else season_number
        ep_name = str(payload.get("name") or f"Episode {ep_n}").strip()
        ep_overview = str(payload.get("overview") or "").strip() or None
        ep_air = str(payload.get("air_date") or "").strip() or None
        still = self._image_url(payload.get("still_path"), size="w500")
        rt = payload.get("runtime")
        runtime_minutes = int(rt) if isinstance(rt, int) else None
        va = payload.get("vote_average")
        vote_ep = float(va) if isinstance(va, (int, float)) else None

        guest_stars = tuple(self._parse_tv_episode_credit_people(payload.get("guest_stars")))
        credits_block = payload.get("credits")
        cast_list: tuple[TmdbPerson, ...] = ()
        crew_directors: tuple[TmdbPerson, ...] = ()
        if isinstance(credits_block, dict):
            cast_list = tuple(self._parse_tv_episode_credit_people(credits_block.get("cast"), limit=120))
            crew_directors = self._director_people_from_tv_crew_raw(credits_block.get("crew"))

        return TmdbTvEpisodeDetail(
            season_number=sn_n,
            episode_number=ep_n,
            name=ep_name,
            overview=ep_overview,
            air_date=ep_air,
            still_url=still,
            runtime_minutes=runtime_minutes,
            vote_average=vote_ep,
            cast=cast_list,
            guest_stars=guest_stars,
            directors=crew_directors,
        )

    def _parse_tv_season_summaries(self, payload: dict[str, object]) -> list[TmdbTvSeasonSummary]:
        raw_seasons = payload.get("seasons")
        out: list[TmdbTvSeasonSummary] = []
        if not isinstance(raw_seasons, list):
            return out

        for raw in raw_seasons:
            if not isinstance(raw, dict):
                continue
            sn = raw.get("season_number")
            if not isinstance(sn, int):
                continue
            ep_count = raw.get("episode_count")
            count = int(ep_count) if isinstance(ep_count, int) else 0
            name = str(raw.get("name") or f"Season {sn}").strip()
            air = str(raw.get("air_date") or "").strip() or None
            overview = str(raw.get("overview") or "").strip() or None
            poster = self._image_url(raw.get("poster_path"), size="w342")
            out.append(
                TmdbTvSeasonSummary(
                    season_number=sn,
                    name=name,
                    episode_count=count,
                    air_date=air,
                    overview=overview,
                    poster_url=poster,
                ),
            )

        out.sort(key=lambda s: s.season_number)
        return out

    def _genre_map(self) -> dict[str, str]:
        if self._genre_name_to_id is not None:
            return self._genre_name_to_id
        response = self._get("/genre/movie/list")
        response.raise_for_status()
        payload = response.json()
        raw_genres = payload.get("genres")
        mapping: dict[str, str] = {}
        if isinstance(raw_genres, list):
            for raw in raw_genres:
                if not isinstance(raw, dict):
                    continue
                name = str(raw.get("name") or "").strip().lower()
                gid = raw.get("id")
                if name and gid is not None:
                    mapping[name] = str(gid)
        self._genre_name_to_id = mapping
        return mapping

    def _resolve_genre_id(self, label: str) -> str | None:
        key = label.strip().lower()
        if not key:
            return None
        aliases = {
            "sci-fi": "science fiction",
            "sci fi": "science fiction",
            "scifi": "science fiction",
        }
        key = aliases.get(key, key)
        genres = self._genre_map()
        if key in genres:
            return genres[key]
        for name, gid in genres.items():
            if key in name or name in key:
                return gid
        return None

    def _genre_map_tv(self) -> dict[str, str]:
        if self._genre_tv_name_to_id is not None:
            return self._genre_tv_name_to_id
        response = self._get("/genre/tv/list")
        response.raise_for_status()
        payload = response.json()
        raw_genres = payload.get("genres")
        mapping: dict[str, str] = {}
        if isinstance(raw_genres, list):
            for raw in raw_genres:
                if not isinstance(raw, dict):
                    continue
                name = str(raw.get("name") or "").strip().lower()
                gid = raw.get("id")
                if name and gid is not None:
                    mapping[name] = str(gid)
        self._genre_tv_name_to_id = mapping
        return mapping

    def _resolve_tv_genre_id(self, label: str) -> str | None:
        key = label.strip().lower()
        if not key:
            return None
        aliases = {
            "sci-fi": "science fiction",
            "sci fi": "science fiction",
            "scifi": "science fiction",
        }
        key = aliases.get(key, key)
        genres = self._genre_map_tv()
        if key in genres:
            return genres[key]
        for name, gid in genres.items():
            if key in name or name in key:
                return gid
        return None

    def _resolve_keyword_id(self, label: str) -> str | None:
        q = label.strip()
        if not q:
            return None
        response = self._get("/search/keyword", query=q, page=1)
        response.raise_for_status()
        payload = response.json()
        results = payload.get("results")
        if not isinstance(results, list) or not results:
            return None
        first = results[0]
        if not isinstance(first, dict):
            return None
        kid = first.get("id")
        return str(kid) if kid is not None else None

    def fetch_movie_detail(self, *, movie_id: str) -> TmdbMovieDetail:
        response = self._get(
            f"/movie/{movie_id}",
            append_to_response="credits,videos,recommendations,images,keywords",
            include_image_language="en,null",
        )
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise TmdbError("TMDB returned an invalid movie detail payload.")

        movie = self._movie_from_raw(payload)
        if movie is None:
            raise TmdbError("TMDB returned an incomplete movie detail payload.")

        release_date = str(payload.get("release_date") or "").strip()
        release_year = release_date[:4] if len(release_date) >= 4 else None
        runtime = payload.get("runtime")
        status = str(payload.get("status") or "").strip() or None
        original_title = str(payload.get("original_title") or "").strip() or None
        original_language = str(payload.get("original_language") or "").strip() or None
        spoken_languages = self._string_list_from_objects(
            payload.get("spoken_languages"),
            key="english_name",
        )
        production_countries = self._string_list_from_objects(
            payload.get("production_countries"),
            key="name",
        )
        genres = self._string_list_from_objects(payload.get("genres"), key="name")
        keywords = self._keyword_names_from_payload(payload.get("keywords"))

        facts: dict[str, str] = {}
        if original_title and original_title != movie.title:
            facts["Original title"] = original_title
        if status:
            facts["Status"] = status
        if release_date:
            facts["Original release"] = release_date
        if runtime:
            facts["Runtime"] = f"{runtime} min"
        if production_countries:
            facts["Countries of production"] = ", ".join(production_countries)
        if spoken_languages:
            facts["Spoken languages"] = ", ".join(spoken_languages)
        if original_language:
            facts["Original language"] = original_language.upper()
        budget = payload.get("budget")
        if isinstance(budget, int) and budget > 0:
            facts["Budget"] = f"${budget:,}"
        revenue = payload.get("revenue")
        if isinstance(revenue, int) and revenue > 0:
            facts["Grosses"] = f"${revenue:,}"

        ratings: dict[str, str] = {}
        tmdb_rating = movie.metadata.get("tmdbRating")
        if isinstance(tmdb_rating, str) and tmdb_rating:
            ratings["TMDB"] = tmdb_rating
        vote_count = payload.get("vote_count")
        if isinstance(vote_count, int) and vote_count > 0:
            ratings["Votes"] = f"{vote_count:,}"
        if release_year:
            ratings["Year"] = release_year

        backdrop_url = self._image_url(payload.get("backdrop_path"), size="w780")
        gallery_urls = self._parse_gallery_urls(payload)
        cast = self._parse_cast(payload.get("credits"))
        crew_groups = self._parse_crew(payload.get("credits"))
        videos = self._parse_videos(payload.get("videos"))
        recommendations = self._parse_recommendations(payload.get("recommendations"))

        links: list[TmdbLink] = [
            TmdbLink(label="TMDB", url=f"https://www.themoviedb.org/movie/{movie.external_id}"),
        ]
        homepage = str(payload.get("homepage") or "").strip()
        if homepage:
            links.append(TmdbLink(label="Homepage", url=homepage))
        imdb_id = str(payload.get("imdb_id") or "").strip()
        if imdb_id:
            links.append(TmdbLink(label="IMDb", url=f"https://www.imdb.com/title/{imdb_id}/"))

        return TmdbMovieDetail(
            movie=movie,
            backdrop_url=backdrop_url,
            gallery_urls=gallery_urls,
            genres=genres,
            keywords=keywords,
            facts=facts,
            ratings=ratings,
            cast=cast,
            crew_groups=crew_groups,
            videos=videos,
            recommendations=recommendations,
            links=links,
        )

    def fetch_person_catalog_detail(self, *, person_id: str) -> TmdbPersonCatalogDetail:
        response = self._get(
            f"/person/{person_id}",
            append_to_response="combined_credits,external_ids",
        )
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise TmdbError("TMDB returned an invalid person detail payload.")

        pid = payload.get("id")
        name = str(payload.get("name") or "").strip()
        if pid is None or not name:
            raise TmdbError("TMDB returned an incomplete person detail payload.")

        combined = payload.get("combined_credits")
        movie_credits_all = self._parse_person_combined_filmography(combined)
        movie_credits = sorted(
            movie_credits_all,
            key=lambda c: str(c.movie.metadata.get("releaseDate") or ""),
            reverse=True,
        )[:80]
        popular_movie_credits = sorted(
            movie_credits_all,
            key=lambda c: c.popularity,
            reverse=True,
        )[:12]

        imdb_id: str | None = None
        ext = payload.get("external_ids")
        if isinstance(ext, dict):
            raw_imdb = ext.get("imdb_id")
            if raw_imdb is not None:
                candidate = str(raw_imdb).strip()
                imdb_id = candidate or None

        biography = str(payload.get("biography") or "").strip() or None
        known_for = str(payload.get("known_for_department") or "").strip() or None
        place_of_birth = str(payload.get("place_of_birth") or "").strip() or None

        return TmdbPersonCatalogDetail(
            person_id=str(pid),
            name=name,
            biography=biography,
            image_url=self._image_url(payload.get("profile_path")),
            known_for_department=known_for,
            gender=_person_gender_label(payload.get("gender")),
            birthday=_format_person_birthday(payload.get("birthday")),
            place_of_birth=place_of_birth,
            movie_credits=movie_credits,
            popular_movie_credits=popular_movie_credits,
            imdb_id=imdb_id,
        )

    def _thread_session(self) -> requests.Session:
        sess = getattr(self._thread_local, "session", None)
        if sess is None:
            sess = requests.Session()
            self._thread_local.session = sess
        return sess

    def _get(self, path: str, **params: object) -> requests.Response:
        return self._thread_session().get(
            f"{self.base_url}{path}",
            params={
                "api_key": self.api_key,
                "language": self.language,
                **params,
            },
            timeout=self.timeout_seconds,
        )

    def _movie_from_raw(self, raw: object) -> TmdbMovie | None:
        if not isinstance(raw, dict):
            return None

        movie_id = raw.get("id")
        title = (raw.get("title") or raw.get("name") or "").strip()
        if movie_id is None or not title:
            return None

        release_date = str(raw.get("release_date") or raw.get("first_air_date") or "").strip()
        release_year = release_date[:4] if len(release_date) >= 4 else None
        vote_average = raw.get("vote_average")
        rating = f"{float(vote_average):.1f}" if isinstance(vote_average, (int, float)) else None
        subtitle_parts = [part for part in (release_year, f"TMDB {rating}" if rating else None) if part]

        meta: dict[str, object] = {
            "releaseDate": release_date or None,
            "tmdbRating": rating,
            "language": self.language,
        }
        director = _director_names_from_tmdb_media_raw(raw)
        if director:
            meta["director"] = director

        return TmdbMovie(
            external_id=str(movie_id),
            title=title,
            subtitle=" • ".join(subtitle_parts) if subtitle_parts else None,
            description=str(raw.get("overview") or "").strip() or None,
            image_url=self._image_url(raw.get("poster_path")),
            metadata=meta,
        )

    def _director_people_from_tv_crew_raw(self, crew: object) -> tuple[TmdbPerson, ...]:
        if not isinstance(crew, list):
            return ()
        out: list[TmdbPerson] = []
        seen: set[str] = set()
        for c in crew:
            if not isinstance(c, dict):
                continue
            job = str(c.get("job") or "").strip()
            if not _tv_crew_job_is_director(job):
                continue
            name = str(c.get("name") or "").strip()
            if not name:
                continue
            key = name.lower()
            if key in seen:
                continue
            seen.add(key)
            raw_pid = c.get("id")
            person_id = str(raw_pid) if raw_pid is not None else None
            out.append(
                TmdbPerson(
                    person_id=person_id,
                    name=name,
                    role=job,
                    image_url=self._image_url(c.get("profile_path")),
                ),
            )
        return tuple(out)

    def _parse_tv_episode_credit_people(self, raw_list: object, *, limit: int = 80) -> list[TmdbPerson]:
        if not isinstance(raw_list, list):
            return []
        items: list[TmdbPerson] = []
        for raw in raw_list[:limit]:
            if not isinstance(raw, dict):
                continue
            name = str(raw.get("name") or "").strip()
            if not name:
                continue
            raw_pid = raw.get("id")
            person_id = str(raw_pid) if raw_pid is not None else None
            items.append(
                TmdbPerson(
                    person_id=person_id,
                    name=name,
                    role=str(raw.get("character") or "").strip() or None,
                    image_url=self._image_url(raw.get("profile_path")),
                ),
            )
        return items

    def _parse_cast(self, credits_payload: object) -> list[TmdbPerson]:
        if not isinstance(credits_payload, dict):
            return []
        cast_payload = credits_payload.get("cast")
        if not isinstance(cast_payload, list):
            return []

        items: list[TmdbPerson] = []
        for raw in cast_payload[:200]:
            if not isinstance(raw, dict):
                continue
            name = str(raw.get("name") or "").strip()
            if not name:
                continue
            raw_pid = raw.get("id")
            person_id = str(raw_pid) if raw_pid is not None else None
            items.append(
                TmdbPerson(
                    person_id=person_id,
                    name=name,
                    role=str(raw.get("character") or "").strip() or None,
                    image_url=self._image_url(raw.get("profile_path")),
                ),
            )
        return items

    def _parse_crew(self, credits_payload: object) -> list[TmdbCrewGroup]:
        if not isinstance(credits_payload, dict):
            return []
        crew_payload = credits_payload.get("crew")
        if not isinstance(crew_payload, list):
            return []

        grouped: dict[str, list[TmdbPerson]] = {}
        for raw in crew_payload:
            if not isinstance(raw, dict):
                continue
            department = str(raw.get("department") or "").strip()
            if not department:
                department = "Crew"
            name = str(raw.get("name") or "").strip()
            if not name:
                continue
            bucket = grouped.setdefault(department, [])
            if len(bucket) >= 80:
                continue
            raw_pid = raw.get("id")
            person_id = str(raw_pid) if raw_pid is not None else None
            bucket.append(
                TmdbPerson(
                    person_id=person_id,
                    name=name,
                    role=str(raw.get("job") or "").strip() or None,
                    image_url=self._image_url(raw.get("profile_path")),
                ),
            )

        return _crew_groups_sorted(grouped)

    def _media_from_combined_credit(self, raw: dict, media_type: str) -> TmdbMovie | None:
        mid = raw.get("id")
        title = (raw.get("title") or raw.get("name") or "").strip()
        if mid is None or not title:
            return None

        release_date = str(raw.get("release_date") or raw.get("first_air_date") or "").strip()
        release_year = release_date[:4] if len(release_date) >= 4 else None
        vote_average = raw.get("vote_average")
        rating = f"{float(vote_average):.1f}" if isinstance(vote_average, (int, float)) else None
        subtitle_parts: list[str] = []
        if release_year:
            subtitle_parts.append(release_year)
        if rating:
            subtitle_parts.append(f"TMDB {rating}")
        if media_type == "tv":
            subtitle_parts.append("TV")

        return TmdbMovie(
            external_id=str(mid),
            title=title,
            subtitle=" • ".join(subtitle_parts) if subtitle_parts else None,
            description=str(raw.get("overview") or "").strip() or None,
            image_url=self._image_url(raw.get("poster_path")),
            metadata={
                "releaseDate": release_date or None,
                "tmdbRating": rating,
                "language": self.language,
                "mediaType": media_type,
            },
        )

    def _parse_person_combined_filmography(self, combined_payload: object) -> list[TmdbPersonFilmCredit]:
        if not isinstance(combined_payload, dict):
            return []

        credits: list[TmdbPersonFilmCredit] = []
        seen: set[tuple[str, str, str, str, str | None]] = set()

        cast_payload = combined_payload.get("cast")
        if isinstance(cast_payload, list):
            for raw in cast_payload:
                if not isinstance(raw, dict):
                    continue
                media_type = str(raw.get("media_type") or "movie").strip()
                if media_type not in ("movie", "tv"):
                    continue
                work = self._media_from_combined_credit(raw, media_type)
                if work is None:
                    continue
                character = str(raw.get("character") or "").strip() or None
                key = (media_type, work.external_id, "cast", character or "", None)
                if key in seen:
                    continue
                seen.add(key)
                genre_ids = _parse_tmdb_genre_ids(raw.get("genre_ids"))
                vote_raw = raw.get("vote_average")
                vote_f = float(vote_raw) if isinstance(vote_raw, (int, float)) else None
                ep_raw = raw.get("episode_count")
                ep_i: int | None
                if isinstance(ep_raw, int):
                    ep_i = ep_raw
                elif isinstance(ep_raw, str) and ep_raw.strip().isdigit():
                    ep_i = int(ep_raw.strip(), 10)
                else:
                    ep_i = None
                pop_raw = raw.get("popularity")
                popularity = float(pop_raw) if isinstance(pop_raw, (int, float)) else 0.0
                credits.append(
                    TmdbPersonFilmCredit(
                        movie=work,
                        role=character,
                        media_type=media_type,
                        credit_kind="cast",
                        department=None,
                        genre_ids=genre_ids,
                        vote_average=vote_f,
                        episode_count=ep_i,
                        popularity=popularity,
                    ),
                )

        crew_payload = combined_payload.get("crew")
        if isinstance(crew_payload, list):
            for raw in crew_payload:
                if not isinstance(raw, dict):
                    continue
                media_type = str(raw.get("media_type") or "movie").strip()
                if media_type not in ("movie", "tv"):
                    continue
                work = self._media_from_combined_credit(raw, media_type)
                if work is None:
                    continue
                job = str(raw.get("job") or "").strip() or None
                department = str(raw.get("department") or "").strip() or None
                key = (media_type, work.external_id, "crew", job or "", department)
                if key in seen:
                    continue
                seen.add(key)
                genre_ids = _parse_tmdb_genre_ids(raw.get("genre_ids"))
                vote_raw = raw.get("vote_average")
                vote_f = float(vote_raw) if isinstance(vote_raw, (int, float)) else None
                pop_raw = raw.get("popularity")
                popularity = float(pop_raw) if isinstance(pop_raw, (int, float)) else 0.0
                credits.append(
                    TmdbPersonFilmCredit(
                        movie=work,
                        role=job,
                        media_type=media_type,
                        credit_kind="crew",
                        department=department,
                        genre_ids=genre_ids,
                        vote_average=vote_f,
                        episode_count=None,
                        popularity=popularity,
                    ),
                )

        return credits[:250]

    def _parse_videos(self, videos_payload: object) -> list[TmdbVideo]:
        if not isinstance(videos_payload, dict):
            return []
        results = videos_payload.get("results")
        if not isinstance(results, list):
            return []

        items: list[TmdbVideo] = []
        for raw in results:
            if not isinstance(raw, dict):
                continue
            site = str(raw.get("site") or "").strip().lower()
            key = str(raw.get("key") or "").strip()
            name = str(raw.get("name") or "").strip()
            if site != "youtube" or not key or not name:
                continue
            kind = str(raw.get("type") or "").strip() or None
            published_at = str(raw.get("published_at") or "").strip() or None
            subtitle_parts = [part for part in (kind, published_at[:10] if published_at else None) if part]
            items.append(
                TmdbVideo(
                    title=name,
                    subtitle=" • ".join(subtitle_parts) if subtitle_parts else None,
                    image_url=f"https://img.youtube.com/vi/{key}/hqdefault.jpg",
                    url=f"https://www.youtube.com/watch?v={key}",
                ),
            )
            if len(items) >= 10:
                break
        return items

    def _parse_recommendations(self, recommendations_payload: object) -> list[TmdbMovie]:
        if not isinstance(recommendations_payload, dict):
            return []
        results = recommendations_payload.get("results")
        if not isinstance(results, list):
            return []

        items: list[TmdbMovie] = []
        for raw in results[:12]:
            movie = self._movie_from_raw(raw)
            if movie is not None:
                items.append(movie)
        return items

    def _parse_gallery_urls(self, payload: object) -> list[str]:
        if not isinstance(payload, dict):
            return []

        urls: list[str] = []
        primary = self._image_url(payload.get("backdrop_path"), size="w780")
        if primary:
            urls.append(primary)

        images_payload = payload.get("images")
        if isinstance(images_payload, dict):
            backdrops = images_payload.get("backdrops")
            if isinstance(backdrops, list):
                for raw in backdrops:
                    if not isinstance(raw, dict):
                        continue
                    url = self._image_url(raw.get("file_path"), size="w780")
                    if url and url not in urls:
                        urls.append(url)
                    if len(urls) >= 6:
                        break

        return urls

    def _keyword_names_from_payload(self, payload: object) -> list[str]:
        if not isinstance(payload, dict):
            return []
        raw_keywords = payload.get("keywords")
        if not isinstance(raw_keywords, list):
            return []
        names: list[str] = []
        for entry in raw_keywords:
            if not isinstance(entry, dict):
                continue
            name = str(entry.get("name") or "").strip()
            if name:
                names.append(name)
        return names

    def _string_list_from_objects(self, payload: object, *, key: str) -> list[str]:
        if not isinstance(payload, list):
            return []
        values: list[str] = []
        for raw in payload:
            if not isinstance(raw, dict):
                continue
            value = str(raw.get(key) or "").strip()
            if value:
                values.append(value)
        return values

    def _image_url(self, path: object, *, size: str = "w500") -> str | None:
        if isinstance(path, str) and path:
            return f"https://image.tmdb.org/t/p/{size}{path}"
        return None
