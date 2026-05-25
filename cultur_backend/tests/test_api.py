from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from app import main
from app.api.routers import backend as backend_router
from app.api.routers import catalog as catalog_router
from app.services import catalog_service
from app.omdb_client import OmdbMovie
from app.igdb_client import IgdbGame
from app.tmdb_client import (
    TmdbCrewGroup,
    TmdbError,
    TmdbLink,
    TmdbMovie,
    TmdbMovieDetail,
    TmdbPerson,
    TmdbPersonCatalogDetail,
    TmdbPersonFilmCredit,
    TmdbTvAiringBrief,
    TmdbTvEpisodeCatalog,
    TmdbTvEpisodeDetail,
    TmdbTvEpisodeTeaser,
    TmdbTvSeasonDetail,
    TmdbTvSeasonSummary,
    TmdbTvShowSeasonsBundle,
    TmdbVideo,
)


def test_backend_bootstrap_media_and_tracking(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv(
        "SERVER_API_SESSION_STORE",
        str(tmp_path / "data" / "sessions.json"),
    )

    with TestClient(main.app) as client:
        health_response = client.get("/health")
        assert health_response.status_code == 200
        assert health_response.json()["service"] == "cultur_api"

        bootstrap_response = client.post(
            "/backend/bootstrap",
            json={"username": "owner", "displayName": "Owner"},
        )
        assert bootstrap_response.status_code == 200
        assert bootstrap_response.json()["databaseDialect"] == "sqlite"

        media_response = client.post(
            "/backend/media",
            json={
                "source": "tmdb",
                "externalId": "123",
                "mediaType": "movie",
                "title": "The Matrix",
                "subtitle": "Mock movie",
            },
        )
        assert media_response.status_code == 200
        media_payload = media_response.json()
        assert media_payload["title"] == "The Matrix"

        tracking_response = client.put(
            "/backend/tracking",
            json={
                "username": "owner",
                "mediaId": media_payload["id"],
                "status": "In progress",
                "progress": 50,
                "score": 9,
            },
        )
        assert tracking_response.status_code == 200
        assert tracking_response.json()["media"]["id"] == media_payload["id"]
        assert tracking_response.json().get("completedAt") is None

        completed_response = client.put(
            "/backend/tracking",
            json={
                "username": "owner",
                "mediaId": media_payload["id"],
                "status": "Completed",
                "score": 9,
                "completedAt": "2020-01-15T12:30:00+00:00",
            },
        )
        assert completed_response.status_code == 200
        assert completed_response.json()["completedAt"] is not None

        tracking_list_response = client.get(
            "/backend/tracking",
            params={"username": "owner"},
        )
        assert tracking_list_response.status_code == 200
        assert len(tracking_list_response.json()["items"]) == 1


def test_backend_purge_library_clears_server_library(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "wiper"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]
        assert (
            client.put(
                "/backend/tracking",
                json={"username": "wiper", "mediaId": media_id, "status": "In progress"},
            ).status_code
            == 200
        )
        assert (
            client.put(
                "/backend/tracking/tv/episodes",
                json={
                    "username": "wiper",
                    "mediaId": media_id,
                    "seasonNumber": 1,
                    "episodeNumber": 1,
                    "watched": True,
                },
            ).status_code
            == 200
        )
        purge = client.post("/backend/user/purge-library", json={"username": "wiper"})
        assert purge.status_code == 200, purge.text
        data = purge.json()
        assert data["trackingRowsRemoved"] >= 1
        assert data["tvEpisodeWatchRowsRemoved"] >= 1
        assert (
            client.get("/backend/tracking", params={"username": "wiper", "mediaType": "tv"}).json()["items"]
            == []
        )


def test_backend_purge_library_respects_media_types(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "picker"}).status_code == 200
        tv_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]
        movie_id = client.get("/catalog/movies", params={"section": "popular"}).json()["items"][0]["id"]
        for media_id in (tv_id, movie_id):
            assert (
                client.put(
                    "/backend/tracking",
                    json={"username": "picker", "mediaId": media_id, "status": "In progress"},
                ).status_code
                == 200
            )
        purge = client.post(
            "/backend/user/purge-library",
            json={"username": "picker", "mediaTypes": ["movie"]},
        )
        assert purge.status_code == 200, purge.text
        assert purge.json()["tvEpisodeWatchRowsRemoved"] == 0
        tv_items = client.get(
            "/backend/tracking",
            params={"username": "picker", "mediaType": "tv"},
        ).json()["items"]
        movie_items = client.get(
            "/backend/tracking",
            params={"username": "picker", "mediaType": "movie"},
        ).json()["items"]
        assert len(tv_items) == 1
        assert movie_items == []


def test_native_register_login_refresh_and_logout(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv(
        "SERVER_API_SESSION_STORE",
        str(tmp_path / "data" / "sessions.json"),
    )
    monkeypatch.delenv("YAMTRACK_BASE_URL", raising=False)

    with TestClient(main.app) as client:
        register_response = client.post(
            "/auth/register",
            json={
                "username": "owner",
                "password": "super-secret",
                "displayName": "Owner",
            },
        )
        assert register_response.status_code == 200
        register_payload = register_response.json()
        assert register_payload["displayName"] == "Owner"

        me_response = client.get(
            "/me",
            headers={"Authorization": f"Bearer {register_payload['sessionToken']}"},
        )
        assert me_response.status_code == 200
        assert me_response.json()["displayName"] == "Owner"

        logout_response = client.post(
            "/auth/logout",
            headers={"Authorization": f"Bearer {register_payload['sessionToken']}"},
        )
        assert logout_response.status_code == 200

        login_response = client.post(
            "/auth/login",
            json={
                "username": "owner",
                "password": "super-secret",
            },
        )
        assert login_response.status_code == 200
        login_payload = login_response.json()

        refresh_response = client.post(
            "/auth/refresh",
            json={"refreshToken": login_payload["refreshToken"]},
        )
        assert refresh_response.status_code == 200
        refreshed_payload = refresh_response.json()
        assert refreshed_payload["sessionToken"] != login_payload["sessionToken"]


class FakeIgdbClient:
    def __init__(
        self,
        *,
        client_id: str,
        client_secret: str,
        language: str = "en",
        timeout_seconds: float = 20.0,
    ) -> None:
        self.client_id = client_id
        self.client_secret = client_secret
        self.language = language
        self.timeout_seconds = timeout_seconds

    def fetch_games(
        self,
        *,
        section: str = "popular",
        query: str | None = None,
        page: int = 1,
        limit: int = 24,
    ) -> list[IgdbGame]:
        return [
            IgdbGame(
                external_id="1942",
                title="The Witcher 3: Wild Hunt",
                subtitle="2015 · IGDB 93.2",
                description="Open world RPG.",
                image_url="https://images.igdb.com/igdb/image/upload/t_cover_big/co1wyy.jpg",
                metadata={"firstReleaseDate": "2015", "igdbRating": 93.2},
            ),
        ]

    def fetch_game_by_id(self, game_id: str | int) -> IgdbGame | None:
        if str(game_id) == "1942":
            return IgdbGame(
                external_id="1942",
                title="The Witcher 3: Wild Hunt",
                subtitle="2015 · IGDB 93.2",
                description="Open world RPG.",
                image_url="https://images.igdb.com/igdb/image/upload/t_cover_big/co1wyy.jpg",
                metadata={
                    "firstReleaseDate": "2015",
                    "igdbRating": 93.2,
                    "igdbUrl": "https://www.igdb.com/games/the-witcher-3-wild-hunt",
                    "genres": "Role-playing (RPG)",
                    "platforms": "PC, PlayStation 4",
                    "videos": [
                        {
                            "title": "Official Trailer",
                            "subtitle": None,
                            "imageUrl": "https://img.youtube.com/vi/abc123def45/hqdefault.jpg",
                            "url": "https://www.youtube.com/watch?v=abc123def45",
                        },
                    ],
                },
            )
        return None

    def fetch_game_videos(self, game_id: str | int) -> list[dict[str, str | None]]:
        if str(game_id) == "1942":
            return [
                {
                    "title": "Official Trailer",
                    "subtitle": None,
                    "imageUrl": "https://img.youtube.com/vi/abc123def45/hqdefault.jpg",
                    "url": "https://www.youtube.com/watch?v=abc123def45",
                },
            ]
        return []

    def fetch_company_catalog_detail(
        self,
        company_id: str | int,
        *,
        primary_role: str | None = None,
        max_catalog: int = 2000,
    ):
        from app.igdb_client import IgdbCompanyCatalogDetail, IgdbCompanyCatalogGame

        game = IgdbGame(
            external_id="1942",
            title="The Witcher 3: Wild Hunt",
            subtitle="2015 · IGDB 93.2",
            description="Open world RPG.",
            image_url="https://images.igdb.com/igdb/image/upload/t_cover_big/co1wyy.jpg",
            metadata={"firstReleaseDate": "2015", "igdbRating": 93.2, "firstReleaseDateUnix": 1420070400},
        )
        entry = IgdbCompanyCatalogGame(game=game, roles=("Developer", "Publisher"))
        return IgdbCompanyCatalogDetail(
            company_id=str(company_id),
            name="CD Projekt Red",
            description="Polish game developer.",
            logo_url="https://images.igdb.com/igdb/image/upload/t_thumb/co1qq9.jpg",
            website_url="https://www.cdprojekt.com/",
            slug="cd-projekt-red",
            catalog=(entry,),
            popular_catalog=(entry,),
        )


class FakeTmdbClient:
    def __init__(self, *, api_key: str, language: str = "en-US", timeout_seconds: float = 20) -> None:
        self.api_key = api_key
        self.language = language
        self.timeout_seconds = timeout_seconds

    def fetch_movies(
        self,
        *,
        section: str = "popular",
        query: str | None = None,
        page: int = 1,
        genre: str | None = None,
        keyword: str | None = None,
    ) -> list[TmdbMovie]:
        return [
            TmdbMovie(
                external_id="603",
                title="The Matrix",
                subtitle="1999 • TMDB 8.7",
                description="A computer hacker learns the truth.",
                image_url="https://image.tmdb.org/t/p/w500/example.jpg",
                metadata={"releaseDate": "1999-03-30", "tmdbRating": "8.7"},
            ),
        ]

    def fetch_movie_director_line(self, *, movie_id: str) -> str | None:
        if movie_id == "603":
            return "Lana Wachowski, Lilly Wachowski"
        return None

    def enrich_movies_directors_from_credits(self, movies: list[TmdbMovie]) -> list[TmdbMovie]:
        out: list[TmdbMovie] = []
        for m in movies:
            if str(m.metadata.get("director") or "").strip():
                out.append(m)
                continue
            line = (self.fetch_movie_director_line(movie_id=m.external_id) or "").strip()
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
        if movie_id == "603":
            return TmdbMovie(
                external_id="603",
                title="The Matrix",
                subtitle="1999 • TMDB 8.7",
                description="A computer hacker learns the truth.",
                image_url="https://image.tmdb.org/t/p/w500/example.jpg",
                metadata={"releaseDate": "1999-03-30", "tmdbRating": "8.7"},
            )
        if movie_id == "99999":
            return None
        if movie_id.isdigit():
            return TmdbMovie(
                external_id=movie_id,
                title=f"Movie {movie_id}",
                subtitle="",
                description="",
                image_url="https://example.invalid/poster.jpg",
                metadata={"releaseDate": "2000-01-01", "tmdbRating": "6.0"},
            )
        return None

    def fetch_tmdb_tv_minimal(self, *, tv_id: str) -> TmdbMovie | None:
        return TmdbMovie(
            external_id=tv_id,
            title="Breaking Bad",
            subtitle="2008 • TMDB 9.5",
            description="A high school chemistry teacher turned meth cook.",
            image_url="https://image.tmdb.org/t/p/w500/bb.jpg",
            metadata={"releaseDate": "2008-01-20", "tmdbRating": "9.5"},
        )

    def fetch_tv_shows(
        self,
        *,
        section: str = "popular",
        query: str | None = None,
        page: int = 1,
        genre: str | None = None,
        keyword: str | None = None,
    ) -> list[TmdbMovie]:
        return [
            TmdbMovie(
                external_id="1396",
                title="Breaking Bad",
                subtitle="2008 • TMDB 9.5",
                description="A high school chemistry teacher turned meth cook.",
                image_url="https://image.tmdb.org/t/p/w500/bb.jpg",
                metadata={"releaseDate": "2008-01-20", "tmdbRating": "9.5"},
            ),
        ]

    def fetch_tv_detail(self, *, tv_id: str) -> TmdbMovieDetail:
        return TmdbMovieDetail(
            movie=TmdbMovie(
                external_id=tv_id,
                title="Breaking Bad",
                subtitle="2008 • TMDB 9.5",
                description="A high school chemistry teacher turned meth cook.",
                image_url="https://image.tmdb.org/t/p/w500/bb.jpg",
                metadata={"releaseDate": "2008-01-20", "tmdbRating": "9.5"},
            ),
            backdrop_url="https://image.tmdb.org/t/p/w780/tv-backdrop.jpg",
            gallery_urls=["https://image.tmdb.org/t/p/w780/tv-backdrop.jpg"],
            genres=["Drama", "Crime"],
            keywords=["meth", "new mexico"],
            facts={"First aired": "2008-01-20", "Seasons": "5", "Episodes": "62"},
            ratings={"TMDB": "9.5", "Votes": "9,999"},
            cast=[
                TmdbPerson(
                    person_id="17419",
                    name="Bryan Cranston",
                    role="Walter White",
                    image_url="https://image.tmdb.org/t/p/w500/walt.jpg",
                ),
            ],
            crew_groups=[
                TmdbCrewGroup(
                    title="Directing",
                    people=[
                        TmdbPerson(
                            person_id="1",
                            name="Vince Gilligan",
                            role="Director",
                            image_url=None,
                        ),
                    ],
                ),
            ],
            videos=[
                TmdbVideo(
                    title="Trailer",
                    subtitle="Trailer • 2008-01-01",
                    image_url="https://img.youtube.com/vi/tvabc/hqdefault.jpg",
                    url="https://www.youtube.com/watch?v=tvabc",
                ),
            ],
            recommendations=[
                TmdbMovie(
                    external_id="1399",
                    title="Game of Thrones",
                    subtitle="2011 • TMDB 8.3",
                    description="Nine noble families fight for control.",
                    image_url="https://image.tmdb.org/t/p/w500/got.jpg",
                    metadata={"releaseDate": "2011-04-17", "tmdbRating": "8.3"},
                ),
            ],
            links=[
                TmdbLink(label="TMDB", url="https://www.themoviedb.org/tv/1396"),
            ],
            tv_last_episode=TmdbTvEpisodeTeaser(
                name="Ozymandias",
                air_date="2024-01-15",
                season_number=5,
                episode_number=14,
                still_url="https://image.tmdb.org/t/p/w500/still.jpg",
                runtime_minutes=48,
            ),
            tv_next_episode=TmdbTvEpisodeTeaser(
                name="Finale",
                air_date="2026-12-20",
                season_number=6,
                episode_number=1,
            ),
        )

    def fetch_tv_airing_brief(self, *, tv_id: str) -> TmdbTvAiringBrief:
        return self.fetch_tv_home_detail(tv_id=tv_id)[0]

    def fetch_tv_show_seasons_bundle(self, *, tv_id: str) -> TmdbTvShowSeasonsBundle:
        return self.fetch_tv_home_detail(tv_id=tv_id)[1]

    def fetch_tv_home_detail(self, *, tv_id: str) -> tuple[TmdbTvAiringBrief, TmdbTvShowSeasonsBundle]:
        brief = TmdbTvAiringBrief(
            next_episode=TmdbTvEpisodeTeaser(
                name="Finale",
                air_date="2026-12-20",
                season_number=6,
                episode_number=1,
                still_url=None,
                runtime_minutes=None,
            ),
            last_episode=TmdbTvEpisodeTeaser(
                name="Ozymandias",
                air_date="2025-08-15",
                season_number=5,
                episode_number=14,
                still_url=None,
                runtime_minutes=None,
            ),
        )
        base = self.fetch_tv_detail(tv_id=tv_id)
        seasons = [
            TmdbTvSeasonSummary(
                season_number=0,
                name="Specials",
                episode_count=1,
                air_date="2008-01-01",
                overview=None,
                poster_url=None,
            ),
            TmdbTvSeasonSummary(
                season_number=1,
                name="Season 1",
                episode_count=7,
                air_date="2008-01-20",
                overview="Where it all begins.",
                poster_url="https://image.tmdb.org/t/p/w342/s1.jpg",
            ),
            TmdbTvSeasonSummary(
                season_number=2,
                name="Season 2",
                episode_count=13,
                air_date="2009-03-08",
                overview=None,
                poster_url=None,
            ),
        ]
        bundle = TmdbTvShowSeasonsBundle(show=base.movie, seasons=seasons)
        return brief, bundle

    def fetch_tv_season_detail(self, *, tv_id: str, season_number: int, include_credits: bool = True) -> TmdbTvSeasonDetail:
        if season_number == 999:
            raise TmdbError("Season not found.")
        if season_number == 1:
            episodes = [
                TmdbTvEpisodeCatalog(
                    episode_number=1,
                    name="Pilot",
                    overview="It begins.",
                    air_date="2008-01-20",
                    still_url="https://image.tmdb.org/t/p/w500/still1.jpg",
                    runtime_minutes=58,
                    vote_average=9.1,
                    guest_stars=(
                        TmdbPerson(
                            person_id="999001",
                            name="Guest Actor",
                            role="The Patient",
                            image_url="https://image.tmdb.org/t/p/w500/guest.jpg",
                        ),
                    ),
                ),
                TmdbTvEpisodeCatalog(
                    episode_number=2,
                    name="Cat's in the Bag...",
                    overview=None,
                    air_date=None,
                    still_url=None,
                    runtime_minutes=48,
                    vote_average=8.8,
                    guest_stars=(),
                ),
            ]
        elif season_number == 0:
            episodes = [
                TmdbTvEpisodeCatalog(
                    episode_number=1,
                    name="Minisode",
                    overview=None,
                    air_date="2008-01-01",
                    still_url=None,
                    runtime_minutes=10,
                    vote_average=7.5,
                    guest_stars=(),
                ),
            ]
        else:
            episodes = [
                TmdbTvEpisodeCatalog(
                    episode_number=1,
                    name="Seven Thirty-Seven",
                    overview=None,
                    air_date="2009-03-08",
                    still_url=None,
                    runtime_minutes=47,
                    vote_average=8.9,
                    guest_stars=(),
                ),
            ]
        return TmdbTvSeasonDetail(
            season_number=season_number,
            name="Specials" if season_number == 0 else f"Season {season_number}",
            overview="Mock season overview." if season_number == 1 else None,
            air_date="2008-01-20" if season_number == 1 else ("2008-01-01" if season_number == 0 else "2009-03-08"),
            poster_url="https://image.tmdb.org/t/p/w500/s1.jpg" if season_number == 1 else None,
            episodes=episodes,
            season_cast=(
                TmdbPerson(
                    person_id="2001",
                    name="Season Cast Member",
                    role="Himself",
                    image_url=None,
                ),
            )
            if season_number == 1
            else (),
            vote_average=8.6 if season_number == 1 else None,
            directors=(
                TmdbPerson(
                    person_id="3001",
                    name="Season Director",
                    role="Director",
                    image_url=None,
                ),
            )
            if season_number == 1
            else (),
        )

    def fetch_tv_episode_detail(self, *, tv_id: str, season_number: int, episode_number: int) -> TmdbTvEpisodeDetail:
        if season_number == 999:
            raise TmdbError("Episode not found.")
        sd = self.fetch_tv_season_detail(tv_id=tv_id, season_number=season_number)
        ep = next((e for e in sd.episodes if e.episode_number == episode_number), None)
        if ep is None:
            raise TmdbError("Episode not found.")
        return TmdbTvEpisodeDetail(
            season_number=season_number,
            episode_number=ep.episode_number,
            name=ep.name,
            overview=ep.overview,
            air_date=ep.air_date,
            still_url=ep.still_url,
            runtime_minutes=ep.runtime_minutes,
            vote_average=ep.vote_average,
            cast=(
                TmdbPerson(
                    person_id="5001",
                    name="Episode Star",
                    role="Lead",
                    image_url="https://image.tmdb.org/t/p/w500/ep.jpg",
                ),
            ),
            guest_stars=ep.guest_stars,
            directors=(
                TmdbPerson(
                    person_id="6001",
                    name="Episode Director",
                    role="Director",
                    image_url=None,
                ),
            ),
        )

    def fetch_movie_detail(self, *, movie_id: str) -> TmdbMovieDetail:
        return TmdbMovieDetail(
            movie=TmdbMovie(
                external_id=movie_id,
                title="The Matrix",
                subtitle="1999 • TMDB 8.7",
                description="A computer hacker learns the truth.",
                image_url="https://image.tmdb.org/t/p/w500/example.jpg",
                metadata={"releaseDate": "1999-03-30", "tmdbRating": "8.7"},
            ),
            backdrop_url="https://image.tmdb.org/t/p/w780/backdrop.jpg",
            gallery_urls=[
                "https://image.tmdb.org/t/p/w780/backdrop.jpg",
                "https://image.tmdb.org/t/p/w780/backdrop-2.jpg",
            ],
            genres=["Action", "Science Fiction"],
            keywords=["simulated reality", "artificial intelligence", "dystopia"],
            facts={
                "Original release": "1999-03-30",
                "Runtime": "136 min",
            },
            ratings={"TMDB": "8.7", "Votes": "12,345"},
            cast=[
                TmdbPerson(
                    person_id="6384",
                    name="Keanu Reeves",
                    role="Neo",
                    image_url="https://image.tmdb.org/t/p/w500/neo.jpg",
                ),
            ],
            crew_groups=[
                TmdbCrewGroup(
                    title="Directing",
                    people=[
                        TmdbPerson(
                            person_id="9339",
                            name="Lana Wachowski",
                            role="Director",
                            image_url=None,
                        ),
                    ],
                ),
            ],
            videos=[
                TmdbVideo(
                    title="Official Trailer",
                    subtitle="Trailer • 1999-03-30",
                    image_url="https://img.youtube.com/vi/abc/hqdefault.jpg",
                    url="https://www.youtube.com/watch?v=abc",
                ),
            ],
            recommendations=[
                TmdbMovie(
                    external_id="604",
                    title="The Matrix Reloaded",
                    subtitle="2003 • TMDB 7.2",
                    description="The sequel.",
                    image_url="https://image.tmdb.org/t/p/w500/reloaded.jpg",
                    metadata={"releaseDate": "2003-05-15", "tmdbRating": "7.2"},
                ),
            ],
            links=[
                TmdbLink(label="TMDB", url="https://www.themoviedb.org/movie/603"),
            ],
        )

    def fetch_person_catalog_detail(self, *, person_id: str) -> TmdbPersonCatalogDetail:
        matrix = TmdbMovie(
            external_id="603",
            title="The Matrix",
            subtitle="1999 • TMDB 8.7",
            description="A computer hacker learns the truth.",
            image_url="https://image.tmdb.org/t/p/w500/example.jpg",
            metadata={"releaseDate": "1999-03-30", "tmdbRating": "8.7"},
        )
        return TmdbPersonCatalogDetail(
            person_id=person_id,
            name="Keanu Reeves",
            biography="Sample biography.",
            image_url="https://image.tmdb.org/t/p/w500/neo.jpg",
            known_for_department="Acting",
            gender="Male",
            birthday="September 2, 1964",
            place_of_birth="Beirut, Lebanon",
            movie_credits=[
                TmdbPersonFilmCredit(
                    movie=matrix,
                    role="Neo",
                    media_type="movie",
                    credit_kind="cast",
                    department=None,
                    genre_ids=(28, 878),
                    vote_average=8.7,
                    episode_count=None,
                    popularity=45.2,
                ),
            ],
            popular_movie_credits=[
                TmdbPersonFilmCredit(
                    movie=matrix,
                    role="Neo",
                    media_type="movie",
                    credit_kind="cast",
                    department=None,
                    genre_ids=(28, 878),
                    vote_average=8.7,
                    episode_count=None,
                    popularity=45.2,
                ),
            ],
            imdb_id="nm0000206",
        )


def test_catalog_games_uses_igdb_source(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("IGDB_CLIENT_ID", "igdb-test-id")
    monkeypatch.setenv("IGDB_CLIENT_SECRET", "igdb-test-secret")
    monkeypatch.setattr(catalog_router, "IgdbClient", FakeIgdbClient)

    with TestClient(main.app) as client:
        list_resp = client.get("/catalog/games", params={"section": "popular"})
        assert list_resp.status_code == 200
        payload = list_resp.json()
        assert payload["items"][0]["source"] == "igdb"
        assert payload["items"][0]["mediaType"] == "game"
        assert payload["items"][0]["title"] == "The Witcher 3: Wild Hunt"

        media_id = payload["items"][0]["id"]
        detail_resp = client.get(f"/catalog/games/{media_id}")
        assert detail_resp.status_code == 200
        detail = detail_resp.json()
        assert detail["media"]["id"] == media_id
        assert detail["overview"] == "Open world RPG."
        assert detail["links"][0]["label"] == "IGDB"
        assert detail["videos"][0]["title"] == "Official Trailer"
        assert detail["videos"][0]["url"] == "https://www.youtube.com/watch?v=abc123def45"


def test_catalog_game_company_detail(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("IGDB_CLIENT_ID", "igdb-test-id")
    monkeypatch.setenv("IGDB_CLIENT_SECRET", "igdb-test-secret")
    monkeypatch.setattr(catalog_router, "IgdbClient", FakeIgdbClient)

    with TestClient(main.app) as client:
        resp = client.get("/catalog/games/companies/964", params={"company_role": "developer"})
        assert resp.status_code == 200
        payload = resp.json()
        assert payload["companyId"] == "964"
        assert payload["name"] == "CD Projekt Red"
        assert payload["primaryRole"] == "Developer"
        assert len(payload["catalog"]) == 1
        assert payload["catalog"][0]["roles"] == ["Developer", "Publisher"]
        assert payload["catalog"][0]["media"]["title"] == "The Witcher 3: Wild Hunt"
        assert any(link["label"] == "IGDB" for link in payload["links"])


def test_catalog_games_returns_503_without_credentials(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.delenv("IGDB_CLIENT_ID", raising=False)
    monkeypatch.delenv("IGDB_CLIENT_SECRET", raising=False)

    with TestClient(main.app) as client:
        response = client.get("/catalog/games")
        assert response.status_code == 503


def test_catalog_movies_uses_tmdb_source(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        response = client.get("/catalog/movies", params={"section": "popular"})
        assert response.status_code == 200
        payload = response.json()
        assert payload["items"][0]["source"] == "tmdb"
        assert payload["items"][0]["mediaType"] == "movie"
        assert payload["items"][0]["title"] == "The Matrix"


def test_catalog_movies_home_returns_both_shelves(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        response = client.get("/catalog/movies/home")
        assert response.status_code == 200
        payload = response.json()
        assert "nowPlaying" in payload
        assert "upcoming" in payload
        assert payload["nowPlaying"]["items"][0]["title"] == "The Matrix"
        assert payload["upcoming"]["items"][0]["title"] == "The Matrix"


def test_catalog_tv_list_home_and_detail(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        list_resp = client.get("/catalog/tv", params={"section": "popular"})
        assert list_resp.status_code == 200
        assert list_resp.json()["items"][0]["mediaType"] == "tv"
        assert list_resp.json()["items"][0]["title"] == "Breaking Bad"

        home_resp = client.get("/catalog/tv/home")
        assert home_resp.status_code == 200
        home = home_resp.json()
        assert home["nextUp"]["items"] == []
        assert home["upcomingEpisodes"]["items"] == []

        bootstrap_response = client.post(
            "/backend/bootstrap",
            json={"username": "owner", "displayName": "Owner"},
        )
        assert bootstrap_response.status_code == 200

        media_id = list_resp.json()["items"][0]["id"]
        detail_resp = client.get(f"/catalog/tv/{media_id}", params={"username": "owner"})
        assert detail_resp.status_code == 200
        detail = detail_resp.json()
        assert detail["media"]["id"] == media_id
        assert detail["media"]["mediaType"] == "tv"
        assert detail["watchedEpisodes"] == []
        nec = detail["nextEpisodeCard"]
        assert nec is not None
        assert nec["seasonNumber"] == 5
        assert nec["episodeNumber"] == 14
        assert nec["name"] == "Ozymandias"
        assert detail["cast"][0]["name"] == "Bryan Cranston"
        assert detail["recommendations"][0]["title"] == "Game of Thrones"


def test_catalog_tv_home_next_up_and_upcoming_from_tracking(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        bootstrap_response = client.post(
            "/backend/bootstrap",
            json={"username": "owner", "displayName": "Owner"},
        )
        assert bootstrap_response.status_code == 200

        list_resp = client.get("/catalog/tv", params={"section": "popular"})
        assert list_resp.status_code == 200
        media_id = list_resp.json()["items"][0]["id"]

        client.put(
            "/backend/tracking",
            json={
                "username": "owner",
                "mediaId": media_id,
                "status": "Planning",
                "notes": "[cult.flags]watchlist",
            },
        )
        assert (
            client.put(
                "/backend/tracking/tv/episodes",
                json={
                    "username": "owner",
                    "mediaId": media_id,
                    "seasonNumber": 1,
                    "episodeNumber": 1,
                    "watched": True,
                },
            ).status_code
            == 200
        )

        home_watch = client.get("/catalog/tv/home", params={"username": "owner"})
        assert home_watch.status_code == 200
        body_watch = home_watch.json()
        nu_watch = body_watch["nextUp"]["items"]
        assert len(nu_watch) == 1
        assert nu_watch[0]["title"] == "Breaking Bad"
        assert nu_watch[0]["metadata"]["shelfEpisodeKind"] == "continueWatching"
        assert "S1E2" in (nu_watch[0].get("subtitle") or "")
        up_payload = body_watch["upcomingEpisodes"]["items"]
        assert len(up_payload) == 1
        assert up_payload[0]["title"] == "Breaking Bad"
        assert up_payload[0]["metadata"]["releaseDate"] == "2026-12-20"

        client.put(
            "/backend/tracking",
            json={
                "username": "owner",
                "mediaId": media_id,
                "status": "Completed",
                "notes": "[cult.flags]watched",
                "completedAt": "2024-01-01T00:00:00Z",
            },
        )

        home_watched = client.get("/catalog/tv/home", params={"username": "owner"})
        assert home_watched.status_code == 200
        body = home_watched.json()
        assert body["upcomingEpisodes"]["items"] == []
        nu = body["nextUp"]["items"]
        assert len(nu) == 1
        assert nu[0]["title"] == "Breaking Bad"
        assert nu[0]["metadata"]["releaseDate"] == "2025-08-15"


def test_catalog_tv_home_next_up_is_next_to_watch_not_latest_aired(tmp_path: Path, monkeypatch) -> None:
    """After watching S1E1, next up must be S1E2 — not TMDB's last_episode_to_air (e.g. S5)."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "u1"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]
        assert (
            client.put(
                "/backend/tracking",
                json={
                    "username": "u1",
                    "mediaId": media_id,
                    "status": "In progress",
                },
            ).status_code
            == 200
        )
        assert (
            client.put(
                "/backend/tracking/tv/episodes",
                json={
                    "username": "u1",
                    "mediaId": media_id,
                    "seasonNumber": 1,
                    "episodeNumber": 1,
                    "watched": True,
                },
            ).status_code
            == 200
        )
        home = client.get("/catalog/tv/home", params={"username": "u1"})
        assert home.status_code == 200
        nu = home.json()["nextUp"]["items"]
        assert len(nu) == 1
        assert nu[0]["metadata"]["shelfEpisodeKind"] == "continueWatching"
        sub = nu[0].get("subtitle") or ""
        assert "S1E2" in sub
        assert "Cat" in sub


def test_upsert_tracking_tv_watched_requires_all_aired_episodes(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "u4"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]
        assert (
            client.put(
                "/backend/tracking/tv/episodes",
                json={
                    "username": "u4",
                    "mediaId": media_id,
                    "seasonNumber": 1,
                    "episodeNumber": 1,
                    "watched": True,
                },
            ).status_code
            == 200
        )
        blocked = client.put(
            "/backend/tracking",
            json={
                "username": "u4",
                "mediaId": media_id,
                "status": "Completed",
                "notes": "[cult.flags]watched",
            },
        )
        assert blocked.status_code == 400
        for ep in range(1, 8):
            assert (
                client.put(
                    "/backend/tracking/tv/episodes",
                    json={
                        "username": "u4",
                        "mediaId": media_id,
                        "seasonNumber": 1,
                        "episodeNumber": ep,
                        "watched": True,
                    },
                ).status_code
                == 200
            )
        for season_number, episode_number in ((0, 1), (2, 1)):
            assert (
                client.put(
                    "/backend/tracking/tv/episodes",
                    json={
                        "username": "u4",
                        "mediaId": media_id,
                        "seasonNumber": season_number,
                        "episodeNumber": episode_number,
                        "watched": True,
                    },
                ).status_code
                == 200
            )
        ok = client.put(
            "/backend/tracking",
            json={
                "username": "u4",
                "mediaId": media_id,
                "status": "Completed",
                "notes": "[cult.flags]watched",
            },
        )
        assert ok.status_code == 200


def test_catalog_tv_home_continue_watching_when_library_watched_but_new_eps_remain(
    tmp_path: Path, monkeypatch
) -> None:
    """Library-watched show with a new season in progress still appears on Continue watching."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "u3"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]
        assert (
            client.put(
                "/backend/tracking",
                json={
                    "username": "u3",
                    "mediaId": media_id,
                    "status": "Completed",
                    "notes": "[cult.flags]watched",
                    "completedAt": "2024-01-01T00:00:00Z",
                },
            ).status_code
            == 200
        )
        for ep in (1, 2):
            assert (
                client.put(
                    "/backend/tracking/tv/episodes",
                    json={
                        "username": "u3",
                        "mediaId": media_id,
                        "seasonNumber": 1,
                        "episodeNumber": ep,
                        "watched": True,
                    },
                ).status_code
                == 200
            )
        home = client.get("/catalog/tv/home", params={"username": "u3"})
        assert home.status_code == 200
        kinds = [
            row["metadata"].get("shelfEpisodeKind")
            for row in home.json()["nextUp"]["items"]
            if row["id"] == media_id
        ]
        assert "continueWatching" in kinds


def test_catalog_tv_home_continue_watching_with_doing_flag_and_planning_status(
    tmp_path: Path, monkeypatch
) -> None:
    """Doing + episode progress must appear on Continue watching even when status is Planning."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "u2"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]
        assert (
            client.put(
                "/backend/tracking",
                json={
                    "username": "u2",
                    "mediaId": media_id,
                    "status": "Planning",
                    "notes": "[cult.flags]doing",
                },
            ).status_code
            == 200
        )
        assert (
            client.put(
                "/backend/tracking/tv/episodes",
                json={
                    "username": "u2",
                    "mediaId": media_id,
                    "seasonNumber": 1,
                    "episodeNumber": 1,
                    "watched": True,
                },
            ).status_code
            == 200
        )
        home = client.get("/catalog/tv/home", params={"username": "u2"})
        assert home.status_code == 200
        nu = home.json()["nextUp"]["items"]
        assert len(nu) == 1
        assert nu[0]["metadata"]["shelfEpisodeKind"] == "continueWatching"
        assert "S1E2" in (nu[0].get("subtitle") or "")


def test_catalog_tv_home_episode_put_creates_tracking_row(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "owner"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]

        put = client.put(
            "/backend/tracking/tv/episodes",
            json={
                "username": "owner",
                "mediaId": media_id,
                "seasonNumber": 2,
                "episodeNumber": 5,
                "watched": True,
            },
        )
        assert put.status_code == 200
        put_body = put.json()
        assert put_body["watched"] is True
        assert put_body["seasonNumber"] == 2
        assert put_body["episodeNumber"] == 5
        assert put_body["watchedAt"]

        listed = client.get(
            "/backend/tracking/tv/episodes",
            params={"username": "owner", "mediaId": media_id},
        )
        assert listed.status_code == 200
        items = listed.json()["items"]
        assert len(items) == 1
        assert items[0]["seasonNumber"] == 2
        assert items[0]["episodeNumber"] == 5

        lib_tv = client.get("/backend/tracking", params={"username": "owner", "mediaType": "tv"})
        assert lib_tv.status_code == 200
        lib_items = lib_tv.json()["items"]
        assert any(
            row["media"]["id"] == media_id and row.get("episodeWatchedCount", 0) >= 1 for row in lib_items
        )

        lib_ep = client.get("/backend/tracking/tv/watched-episodes", params={"username": "owner"}).json()[
            "items"
        ]
        assert len(lib_ep) == 1
        assert lib_ep[0]["media"]["id"] == media_id
        assert lib_ep[0]["seasonNumber"] == 2
        assert lib_ep[0]["episodeNumber"] == 5

        detail = client.get(f"/catalog/tv/{media_id}", params={"username": "owner"}).json()
        assert len(detail["watchedEpisodes"]) == 1
        assert detail["watchedEpisodes"][0]["seasonNumber"] == 2

        put_custom = client.put(
            "/backend/tracking/tv/episodes",
            json={
                "username": "owner",
                "mediaId": media_id,
                "seasonNumber": 2,
                "episodeNumber": 5,
                "watched": True,
                "watchedAt": "2020-06-15T20:30:00Z",
            },
        )
        assert put_custom.status_code == 200
        assert put_custom.json()["watchedAt"].startswith("2020-06-15T20:30:00")

        clear = client.put(
            "/backend/tracking/tv/episodes",
            json={
                "username": "owner",
                "mediaId": media_id,
                "seasonNumber": 2,
                "episodeNumber": 5,
                "watched": False,
            },
        )
        assert clear.status_code == 200
        assert clear.json()["watched"] is False
        assert client.get(
            "/backend/tracking/tv/episodes",
            params={"username": "owner", "mediaId": media_id},
        ).json()["items"] == []


def test_tv_watched_episodes_library_newest_first(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "owner"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]

        assert (
            client.put(
                "/backend/tracking/tv/episodes",
                json={
                    "username": "owner",
                    "mediaId": media_id,
                    "seasonNumber": 1,
                    "episodeNumber": 1,
                    "watched": True,
                    "watchedAt": "2010-01-01T00:00:00Z",
                },
            ).status_code
            == 200
        )
        assert (
            client.put(
                "/backend/tracking/tv/episodes",
                json={
                    "username": "owner",
                    "mediaId": media_id,
                    "seasonNumber": 2,
                    "episodeNumber": 5,
                    "watched": True,
                    "watchedAt": "2020-06-15T12:00:00Z",
                },
            ).status_code
            == 200
        )

        rows = client.get("/backend/tracking/tv/watched-episodes", params={"username": "owner"}).json()[
            "items"
        ]
        assert len(rows) == 2
        assert (rows[0]["seasonNumber"], rows[0]["episodeNumber"]) == (2, 5)
        assert (rows[1]["seasonNumber"], rows[1]["episodeNumber"]) == (1, 1)


def test_tv_mark_episodes_through(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "owner"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]

        mark = client.put(
            "/backend/tracking/tv/episodes/mark-through",
            json={
                "username": "owner",
                "mediaId": media_id,
                "throughSeasonNumber": 1,
                "throughEpisodeNumber": 2,
            },
        )
        assert mark.status_code == 200
        assert mark.json()["markedCount"] == 3

        listed = client.get(
            "/backend/tracking/tv/episodes",
            params={"username": "owner", "mediaId": media_id},
        ).json()["items"]
        assert len(listed) == 3


def test_tv_mark_episodes_through_only_one_season(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "owner"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]

        only = client.put(
            "/backend/tracking/tv/episodes/mark-through",
            json={
                "username": "owner",
                "mediaId": media_id,
                "throughSeasonNumber": 1,
                "throughEpisodeNumber": 2,
                "onlySeasonNumber": 1,
            },
        )
        assert only.status_code == 200
        assert only.json()["markedCount"] == 2

        items = client.get(
            "/backend/tracking/tv/episodes",
            params={"username": "owner", "mediaId": media_id},
        ).json()["items"]
        assert len(items) == 2
        assert all(row["seasonNumber"] == 1 for row in items)

        cleared = client.put(
            "/backend/tracking/tv/episodes/clear-season",
            json={"username": "owner", "mediaId": media_id, "seasonNumber": 1},
        )
        assert cleared.status_code == 200
        assert cleared.json()["removedCount"] == 2
        remaining = client.get(
            "/backend/tracking/tv/episodes",
            params={"username": "owner", "mediaId": media_id},
        ).json()["items"]
        assert remaining == []


def test_catalog_tv_seasons_list_and_season_detail(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "owner"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]

        seasons_resp = client.get(f"/catalog/tv/{media_id}/seasons")
        assert seasons_resp.status_code == 200
        items = seasons_resp.json()["items"]
        assert len(items) == 3
        s1 = next(row for row in items if row["seasonNumber"] == 1)
        assert s1["name"] == "Season 1"
        assert s1["episodeCount"] == 7

        detail = client.get(f"/catalog/tv/{media_id}/seasons/1")
        assert detail.status_code == 200
        body = detail.json()
        assert body["seasonNumber"] == 1
        assert len(body["episodes"]) == 2
        assert body["episodes"][0]["episodeNumber"] == 1
        assert body["episodes"][0]["name"] == "Pilot"
        gs = body["episodes"][0]["guestStars"]
        assert len(gs) == 1
        assert gs[0]["name"] == "Guest Actor"
        assert gs[0]["role"] == "The Patient"
        assert body["episodes"][1]["guestStars"] == []
        assert body["watchedEpisodes"] == []
        assert len(body["cast"]) == 1
        assert body["cast"][0]["name"] == "Season Cast Member"
        assert len(body["ratings"]) == 1
        assert body["ratings"][0]["label"] == "TMDB"
        assert body["ratings"][0]["value"] == "8.6"

        ep_detail = client.get(f"/catalog/tv/{media_id}/seasons/1/episodes/1")
        assert ep_detail.status_code == 200
        ep_body = ep_detail.json()
        assert ep_body["episodeNumber"] == 1
        assert ep_body["cast"][0]["name"] == "Episode Star"
        assert len(ep_body["guestStars"]) == 1

        client.put(
            "/backend/tracking/tv/episodes",
            json={
                "username": "owner",
                "mediaId": media_id,
                "seasonNumber": 1,
                "episodeNumber": 1,
                "watched": True,
            },
        )
        watched = client.get(
            f"/catalog/tv/{media_id}/seasons/1",
            params={"username": "owner"},
        ).json()["watchedEpisodes"]
        assert len(watched) == 1
        assert watched[0]["seasonNumber"] == 1
        assert watched[0]["episodeNumber"] == 1

        missing = client.get(f"/catalog/tv/{media_id}/seasons/999")
        assert missing.status_code == 404


class FakeOmdbClient:
    def __init__(self, *, api_key: str, timeout_seconds: float = 20) -> None:
        self.api_key = api_key
        self.timeout_seconds = timeout_seconds

    def lookup_movie(self, *, title: str, year: str | None = None) -> OmdbMovie | None:
        return OmdbMovie(
            subtitle="30 Mar 1999 • IMDb 8.7",
            description="OMDb enriched plot.",
            image_url="https://omdb.example/poster.jpg",
            metadata={
                "imdbRating": "8.7",
                "runtime": "136 min",
                "genre": "Action, Sci-Fi",
                "imdbId": "tt0133093",
            },
        )


def test_catalog_movies_can_enrich_with_omdb(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setenv("OMDB_API_KEY", "omdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)
    monkeypatch.setattr(catalog_service, "OmdbClient", FakeOmdbClient)

    with TestClient(main.app) as client:
        response = client.get("/catalog/movies", params={"q": "The Matrix"})
        assert response.status_code == 200
        payload = response.json()
        assert payload["items"][0]["subtitle"] == "30 Mar 1999 • IMDb 8.7"
        assert payload["items"][0]["description"] == "OMDb enriched plot."
        assert payload["items"][0]["metadata"]["imdbRating"] == "8.7"


def test_catalog_movie_detail_returns_rich_payload(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        bootstrap_response = client.post(
            "/backend/bootstrap",
            json={"username": "owner", "displayName": "Owner"},
        )
        assert bootstrap_response.status_code == 200

        catalog_response = client.get("/catalog/movies")
        assert catalog_response.status_code == 200
        media_id = catalog_response.json()["items"][0]["id"]

        tracking_response = client.put(
            "/backend/tracking",
            json={
                "username": "owner",
                "mediaId": media_id,
                "status": "In progress",
                "progress": 42,
            },
        )
        assert tracking_response.status_code == 200

        detail_response = client.get(
            f"/catalog/movies/{media_id}",
            params={"username": "owner"},
        )
        assert detail_response.status_code == 200
        payload = detail_response.json()
        assert payload["media"]["id"] == media_id
        assert payload["backdropUrl"] == "https://image.tmdb.org/t/p/w780/backdrop.jpg"
        assert len(payload["galleryUrls"]) == 2
        assert payload["cast"][0]["name"] == "Keanu Reeves"
        assert payload["cast"][0]["personId"] == "6384"
        assert payload["videos"][0]["url"] == "https://www.youtube.com/watch?v=abc"
        assert payload["recommendations"][0]["title"] == "The Matrix Reloaded"
        assert payload["tracking"]["status"] == "In progress"


def test_catalog_person_detail_returns_payload(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        bootstrap_response = client.post(
            "/backend/bootstrap",
            json={"username": "owner", "displayName": "Owner"},
        )
        assert bootstrap_response.status_code == 200

        detail_response = client.get("/catalog/people/6384")
        assert detail_response.status_code == 200
        payload = detail_response.json()
        assert payload["personId"] == "6384"
        assert payload["name"] == "Keanu Reeves"
        assert payload["biography"] == "Sample biography."
        assert len(payload["filmography"]) == 1
        assert payload["filmography"][0]["role"] == "Neo"
        assert payload["filmography"][0]["media"]["title"] == "The Matrix"
        assert len(payload["popularFilmography"]) == 1
        assert payload["gender"] == "Male"
        assert payload["birthday"] == "September 2, 1964"
        assert payload["placeOfBirth"] == "Beirut, Lebanon"
        assert {link["label"] for link in payload["links"]} == {"IMDb", "TMDB", "Wikipedia"}


def test_ava_backup_import_v1_smoke(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    backup = {
        "movies": [
            {
                "tmdbId": 603,
                "rating": {"rating": 8, "ratedAt": 1},
                "collection": None,
                "watchHistory": [{"watchedAt": 1_000_000_000_000}],
                "watchlist": None,
                "progress": 42,
            },
        ],
        "shows": [{"tmdbId": 1396, "rating": None, "watchlist": {"watchlistedAt": 1}}],
        "episodes": [
            {
                "tmdbId": 1396,
                "seasonId": 1,
                "seasonNumber": 1,
                "episodeId": 1,
                "episodeNumber": 1,
                "rating": None,
                "watchlist": None,
                "collection": None,
                "watchHistory": [{"watchedAt": 2_000_000_000_000}],
            },
            {
                "tmdbId": 1396,
                "seasonNumber": 1,
                "episodeNumber": 2,
                "rating": {"rating": 10, "ratedAt": 3},
                "watchlist": {"watchlistedAt": 4},
                "watchHistory": [],
            },
        ],
        "lists": [
            {
                "name": "Test list",
                "listMovieBackups": [{"tmdbId": 603}],
                "listTvShowBackups": [{"tmdbId": 1396}],
            },
        ],
        "people": [],
        "seasons": [
            {
                "tmdbId": 1396,
                "seasonNumber": 1,
                "rating": {"rating": 7.5, "ratedAt": 5},
                "watchlist": {"watchlistedAt": 6},
            },
        ],
        "favoriteCuratedLists": [],
        "createdAt": 1,
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "importer"}).status_code == 200
        resp = client.post(
            "/backend/import/ava-backup-v1",
            json={
                "username": "importer",
                "skipExistingTracking": False,
                "backup": backup,
            },
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["moviesImported"] == 1
        assert data["showsImported"] == 1
        assert data["episodeWatchesWritten"] == 1
        assert data["episodeUserStatesWritten"] == 1
        assert data["seasonUserStatesWritten"] == 1
        assert data["importedListCount"] == 2
        assert data["importedListItemCount"] == 2
        assert len(data["importedMovieLists"]) == 1
        assert data["importedMovieLists"][0]["name"] == "Test list"
        assert len(data["importedMovieLists"][0]["items"]) == 1
        assert len(data["importedTvLists"]) == 1
        assert data["importedTvLists"][0]["name"] == "Test list"
        assert len(data["importedTvLists"][0]["items"]) == 1
        assert data["trackingWritten"] >= 2
        assert data.get("importWarnings") == []
        lib = client.get("/backend/tracking", params={"username": "importer"}).json()["items"]
        movie_row = next(
            (x for x in lib if x.get("media", {}).get("externalId") == "603" and x["media"].get("mediaType") == "movie"),
            None,
        )
        assert movie_row is not None
        assert movie_row.get("progress") == 42


def test_ava_backup_export_v1(tmp_path: Path, monkeypatch) -> None:
    """Export returns AVA-shaped backup after import."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    backup = {
        "movies": [{"tmdbId": 603, "watchHistory": [{"watchedAt": 1_000_000_000_000}]}],
        "shows": [{"tmdbId": 1396}],
        "episodes": [
            {
                "tmdbId": 1396,
                "seasonNumber": 1,
                "episodeNumber": 1,
                "watchHistory": [{"watchedAt": 2_000_000_000_000}],
            },
        ],
        "lists": [],
        "seasons": [],
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "exporter"}).status_code == 200
        imp = client.post(
            "/backend/import/ava-backup-v1",
            json={"username": "exporter", "skipExistingTracking": False, "backup": backup},
        )
        assert imp.status_code == 200, imp.text

        resp = client.post(
            "/backend/export/ava-backup-v1",
            json={"username": "exporter"},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["moviesExported"] >= 1
        assert data["showsExported"] >= 1
        assert data["episodesExported"] >= 1
        out = data["backup"]
        assert out["source"] == "cultur"
        assert out["username"] == "exporter"
        assert isinstance(out["movies"], list)
        assert isinstance(out["shows"], list)
        assert isinstance(out["episodes"], list)
        assert isinstance(out["lists"], list)
        movie_ids = {m.get("tmdbId") for m in out["movies"] if isinstance(m, dict)}
        assert 603 in movie_ids


def test_cultur_backup_v3_export_import_roundtrip(tmp_path: Path, monkeypatch) -> None:
    """v3 export captures tracking/TV data and import restores after purge."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    backup = {
        "movies": [{"tmdbId": 603, "watchHistory": [{"watchedAt": 1_000_000_000_000}]}],
        "shows": [{"tmdbId": 1396}],
        "episodes": [
            {
                "tmdbId": 1396,
                "seasonNumber": 1,
                "episodeNumber": 1,
                "watchHistory": [{"watchedAt": 2_000_000_000_000}],
            },
        ],
        "lists": [],
        "seasons": [],
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "v3user"}).status_code == 200
        imp = client.post(
            "/backend/import/ava-backup-v1",
            json={"username": "v3user", "skipExistingTracking": False, "backup": backup},
        )
        assert imp.status_code == 200, imp.text

        export_resp = client.post(
            "/backend/export/cultur-backup-v3",
            json={"username": "v3user"},
        )
        assert export_resp.status_code == 200, export_resp.text
        export_data = export_resp.json()
        document = export_data["document"]
        assert document["format"] == "cultur-backup-v3"
        assert export_data["summary"]["tracking"] >= 1
        assert export_data["summary"]["tvEpisodeWatches"] >= 1

        purge = client.post(
            "/backend/user/purge-library",
            json={
                "username": "v3user",
                "scopes": ["tracking", "tvWatches", "collections", "follows"],
            },
        )
        assert purge.status_code == 200, purge.text

        import_resp = client.post(
            "/backend/import/cultur-backup-v3",
            json={
                "username": "v3user",
                "document": document,
                "skipExistingTracking": False,
                "importLegacyAva": False,
            },
        )
        assert import_resp.status_code == 200, import_resp.text
        summary = import_resp.json()["summary"]
        assert summary["trackingWritten"] >= 1
        assert summary["tvEpisodeWatchesWritten"] >= 1

        tracking = client.get(
            "/backend/tracking",
            params={"username": "v3user", "limit": "50"},
        )
        assert tracking.status_code == 200
        items = tracking.json().get("items") or []
        assert len(items) >= 1


def test_ava_backup_import_movie_watched_variants(tmp_path: Path, monkeypatch) -> None:
    """Watched movies: string tmdbId, progress-only, raw-ms watchHistory, isWatched flag."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    backup = {
        "movies": [
            {"tmdbId": "603", "watchHistory": [], "progress": 100},
            {"tmdbId": 604, "isWatched": True, "watchHistory": [], "lastWatchedAt": 1_700_000_000_000},
            {"tmdbId": 605, "watchHistory": [1_700_000_100_000]},
            {"tmdb_id": 606, "watched": True, "last_updated_ms": 1_700_000_200_000},
        ],
        "shows": [],
        "episodes": [],
        "lists": [],
        "people": [],
        "seasons": [],
        "favoriteCuratedLists": [],
        "createdAt": 1,
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "movwatch"}).status_code == 200
        resp = client.post(
            "/backend/import/ava-backup-v1",
            json={
                "username": "movwatch",
                "skipExistingTracking": False,
                "backup": backup,
            },
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["moviesImported"] == 4
        lib = client.get(
            "/backend/tracking",
            params={"username": "movwatch", "mediaType": "movie"},
        ).json()["items"]
        by_ext = {x["media"]["externalId"]: x for x in lib}
        assert by_ext["603"]["status"] == "Completed"
        assert by_ext["604"]["status"] == "Completed"
        assert by_ext["604"].get("completedAt")
        assert by_ext["605"]["status"] == "Completed"
        assert by_ext["605"].get("completedAt")
        assert by_ext["606"]["status"] == "Completed"
        assert by_ext["606"].get("completedAt")


def test_ava_backup_import_reports_import_warnings(tmp_path: Path, monkeypatch) -> None:
    """Invalid movie rows and TMDB misses appear in importWarnings."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    backup = {
        "movies": [
            "not-an-object",
            {"nope": 1},
            {"tmdbId": 99999},
        ],
        "shows": [],
        "episodes": [],
        "lists": [],
        "people": [],
        "seasons": [],
        "favoriteCuratedLists": [],
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "warnuser"}).status_code == 200
        resp = client.post(
            "/backend/import/ava-backup-v1",
            json={"username": "warnuser", "skipExistingTracking": False, "backup": backup},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["moviesImported"] == 0
        assert data["moviesSkippedTmdb"] == 1
        warnings = data["importWarnings"]
        assert isinstance(warnings, list)
        assert len(warnings) >= 2
        joined = " ".join(warnings)
        assert "not a JSON object" in joined
        assert "missing or invalid TMDB id" in joined
        assert "99999" in joined


def test_ava_backup_import_show_last_watched_nested(tmp_path: Path, monkeypatch) -> None:
    """Show row may carry last watched S/E without episode-level watchHistory arrays."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    backup = {
        "movies": [],
        "shows": [
            {
                "tmdbId": 1396,
                "rating": None,
                "watchlist": None,
                "lastWatchedEpisode": {"seasonNumber": 1, "episodeNumber": 1},
            },
        ],
        "episodes": [],
        "lists": [],
        "people": [],
        "seasons": [],
        "favoriteCuratedLists": [],
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "sglast"}).status_code == 200
        resp = client.post(
            "/backend/import/ava-backup-v1",
            json={"username": "sglast", "skipExistingTracking": False, "backup": backup},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["episodeWatchesWritten"] == 1
        lib = client.get("/backend/tracking", params={"username": "sglast", "mediaType": "tv"}).json()["items"]
        assert len(lib) >= 1
        media_id = lib[0]["media"]["id"]
        eps = client.get(
            "/backend/tracking/tv/episodes",
            params={"username": "sglast", "mediaId": media_id},
        ).json()["items"]
        assert len(eps) == 1
        assert eps[0]["seasonNumber"] == 1
        assert eps[0]["episodeNumber"] == 1


def test_ava_backup_import_tv_progress_100_does_not_mark_finished_until_all_aired_eps(
    tmp_path: Path, monkeypatch
) -> None:
    """Show row `progress: 100` with only last-watched S1E1 must not get library Finished."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    backup = {
        "movies": [],
        "shows": [
            {
                "tmdbId": 1396,
                "progress": 100,
                "watched": True,
                "lastWatchedEpisode": {"seasonNumber": 1, "episodeNumber": 1},
            },
        ],
        "episodes": [],
        "lists": [],
        "people": [],
        "seasons": [],
        "favoriteCuratedLists": [],
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "sgprog"}).status_code == 200
        resp = client.post(
            "/backend/import/ava-backup-v1",
            json={"username": "sgprog", "skipExistingTracking": False, "backup": backup},
        )
        assert resp.status_code == 200, resp.text
        lib = client.get("/backend/tracking", params={"username": "sgprog", "mediaType": "tv"}).json()[
            "items"
        ]
        assert len(lib) == 1
        row = lib[0]
        assert row["status"] != "Completed"
        assert "watched" not in (row.get("notes") or "")
        assert row.get("tvFullyWatched") is False


def test_ava_backup_import_tv_marks_finished_when_all_aired_episodes_imported(
    tmp_path: Path, monkeypatch
) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    ts = 1_700_000_000_000
    episodes = [
        {"tmdbId": 1396, "seasonNumber": 0, "episodeNumber": 1, "watchHistory": [{"watchedAt": ts}]},
    ]
    for ep in range(1, 8):
        episodes.append(
            {
                "tmdbId": 1396,
                "seasonNumber": 1,
                "episodeNumber": ep,
                "watchHistory": [{"watchedAt": ts}],
            },
        )
    episodes.append(
        {"tmdbId": 1396, "seasonNumber": 2, "episodeNumber": 1, "watchHistory": [{"watchedAt": ts}]},
    )

    backup = {
        "movies": [],
        "shows": [{"tmdbId": 1396}],
        "episodes": episodes,
        "lists": [],
        "people": [],
        "seasons": [],
        "favoriteCuratedLists": [],
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "sgfull"}).status_code == 200
        resp = client.post(
            "/backend/import/ava-backup-v1",
            json={"username": "sgfull", "skipExistingTracking": False, "backup": backup},
        )
        assert resp.status_code == 200, resp.text
        lib = client.get("/backend/tracking", params={"username": "sgfull", "mediaType": "tv"}).json()[
            "items"
        ]
        assert len(lib) == 1
        row = lib[0]
        assert row.get("tvFullyWatched") is True
        assert row["status"] == "Completed"
        assert "watched" in (row.get("notes") or "")


def test_ava_backup_import_show_progress_hidden_maps_to_dropped(
    tmp_path: Path, monkeypatch
) -> None:
    """SeriesGuide `progressHidden` (object with hiddenAt) means stopped following — import as dropped."""
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(backend_router, "TmdbClient", FakeTmdbClient)

    backup = {
        "movies": [],
        "shows": [
            {
                "tmdbId": 1396,
                "rating": None,
                "watchlist": None,
                "progressHidden": {"hiddenAt": 1_727_559_912_000},
            },
        ],
        "episodes": [],
        "lists": [],
        "people": [],
        "seasons": [],
        "favoriteCuratedLists": [],
    }

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "pghide"}).status_code == 200
        resp = client.post(
            "/backend/import/ava-backup-v1",
            json={"username": "pghide", "skipExistingTracking": False, "backup": backup},
        )
        assert resp.status_code == 200, resp.text
        lib = client.get("/backend/tracking", params={"username": "pghide", "mediaType": "tv"}).json()[
            "items"
        ]
        assert len(lib) == 1
        row = lib[0]
        assert row["status"] == "Dropped"
        assert "dropped" in (row.get("notes") or "")


def test_catalog_tv_home_skips_dropped_tracking(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'backend.sqlite3').resolve()}",
    )
    monkeypatch.setenv("TMDB_API", "tmdb-test-key")
    monkeypatch.setattr(catalog_router, "TmdbClient", FakeTmdbClient)

    with TestClient(main.app) as client:
        assert client.post("/backend/bootstrap", json={"username": "dropu", "displayName": "D"}).status_code == 200
        media_id = client.get("/catalog/tv", params={"section": "popular"}).json()["items"][0]["id"]
        assert (
            client.put(
                "/backend/tracking",
                json={
                    "username": "dropu",
                    "mediaId": media_id,
                    "status": "Planning",
                    "notes": "[cult.flags]watchlist",
                },
            ).status_code
            == 200
        )
        assert (
            client.put(
                "/backend/tracking/tv/episodes",
                json={
                    "username": "dropu",
                    "mediaId": media_id,
                    "seasonNumber": 1,
                    "episodeNumber": 1,
                    "watched": True,
                },
            ).status_code
            == 200
        )
        home_before = client.get("/catalog/tv/home", params={"username": "dropu"}).json()
        assert len(home_before["nextUp"]["items"]) >= 1

        assert (
            client.put(
                "/backend/tracking",
                json={
                    "username": "dropu",
                    "mediaId": media_id,
                    "status": "Dropped",
                    "notes": "[cult.flags]dropped",
                },
            ).status_code
            == 200
        )
        home_after = client.get("/catalog/tv/home", params={"username": "dropu"}).json()
        assert home_after["nextUp"]["items"] == []
        assert home_after["upcomingEpisodes"]["items"] == []
