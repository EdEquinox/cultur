from __future__ import annotations

import re
import threading
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import requests

IGDB_API_BASE = "https://api.igdb.com/v4"
TWITCH_TOKEN_URL = "https://id.twitch.tv/oauth2/token"
# IGDB cover art maxes at cover_big (264×374); _2x is retina (~528×748).
IGDB_COVER_SIZE = "t_cover_big_2x"
IGDB_SCREENSHOT_SIZE = "t_screenshot_huge_2x"
IGDB_IMAGE_CDN_PREFIX = "https://images.igdb.com/igdb/image/upload/"
# IGDB allows up to 500 results per request; paginate for company catalogs.
_COMPANY_GAMES_PAGE_SIZE = 500
_COMPANY_GAMES_MAX_RESULTS = 2000
IGDB_IMAGE_SIZE_TOKEN_RE = re.compile(
    r"(https?:)?//images\.igdb\.com/igdb/image/upload/t_[^/]+/",
    re.IGNORECASE,
)

# Stash.games → cultur library (for a future import service).
STASH_STATUS_TO_CULTUR_FLAGS: dict[str, tuple[str, ...]] = {
    "Want": ("watchlist",),
    "Playing": ("doing",),
    "Beaten": ("watched",),
    "Archived": ("dropped",),
}
STASH_COLLECTION_TO_CULTUR_FLAGS: dict[str, tuple[str, ...]] = {
    "prioridades": ("priority",),
    "top": ("priority",),
    "abandonados": ("dropped",),
    "gaveta": ("dropped",),
    "fisical": ("collected",),
    "non_fisical": ("collected",),
}


class IgdbError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class IgdbCompany:
    external_id: str
    name: str


@dataclass(frozen=True, slots=True)
class IgdbCompanyCatalogGame:
    game: IgdbGame
    roles: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class IgdbCompanyCatalogDetail:
    company_id: str
    name: str
    description: str | None
    logo_url: str | None
    website_url: str | None
    slug: str | None
    catalog: tuple[IgdbCompanyCatalogGame, ...]
    popular_catalog: tuple[IgdbCompanyCatalogGame, ...]


@dataclass(frozen=True, slots=True)
class IgdbFilterOption:
    external_id: str
    name: str


@dataclass(frozen=True, slots=True)
class IgdbGame:
    external_id: str
    title: str
    subtitle: str | None
    description: str | None
    image_url: str | None
    metadata: dict[str, object]
    publishers: tuple[IgdbCompany, ...] = ()
    developers: tuple[IgdbCompany, ...] = ()


@dataclass(frozen=True, slots=True)
class IgdbEvent:
    external_id: str
    slug: str
    title: str
    starts_at: datetime
    ends_at: datetime | None
    description: str | None
    image_url: str | None
    game_ids: tuple[int, ...]


@dataclass(frozen=True, slots=True)
class IgdbEventDetail(IgdbEvent):
    games: tuple[IgdbGame, ...]


class IgdbClient:
    """IGDB API v4 client (Twitch application credentials)."""

    def __init__(
        self,
        *,
        client_id: str,
        client_secret: str,
        language: str = "en",
        timeout_seconds: float = 20.0,
    ) -> None:
        self.client_id = client_id.strip()
        self.client_secret = client_secret.strip()
        self.language = language.strip() or "en"
        self.timeout_seconds = timeout_seconds
        self._token_lock = threading.Lock()
        self._access_token: str | None = None
        self._token_expires_at: float = 0.0
        self._last_request_at: float = 0.0
        self._filter_options_cache: dict[str, tuple[float, tuple[IgdbFilterOption, ...]]] = {}

    def verify_credentials(self) -> dict[str, object]:
        """Fetch a token and run a minimal games query (health / smoke test)."""
        token = self._get_access_token(force_refresh=True)
        rows = self._post(
            "games",
            'fields name; where version_parent = null; limit 1;',
        )
        return {
            "ok": True,
            "tokenPreview": f"{token[:8]}…" if len(token) > 8 else token,
            "sampleGame": rows[0].get("name") if rows else None,
        }

    def fetch_games(
        self,
        *,
        section: str = "popular",
        query: str | None = None,
        page: int = 1,
        limit: int = 24,
        company_id: str | None = None,
        company_role: str | None = None,
        platform_ids: tuple[int, ...] = (),
        genre_ids: tuple[int, ...] = (),
        game_mode_ids: tuple[int, ...] = (),
        player_perspective_ids: tuple[int, ...] = (),
        game_type_id: int | None = None,
    ) -> list[IgdbGame]:
        safe_limit = max(1, min(limit, 50))
        safe_page = max(1, page)
        offset = (safe_page - 1) * safe_limit

        if company_id and str(company_id).strip().isdigit():
            return self.fetch_games_for_company(
                company_id,
                company_role or "publisher",
            )

        has_query = bool(query and query.strip())
        if has_query:
            # Text search must not apply browse filters (e.g. popular → hypes > 0), or
            # many valid games (low hype) never appear — Agatha Christie: The ABC Murders, etc.
            where_clause = "where version_parent = null; "
            qtext = query.strip()
            body = (
                f'search "{_escape_apicalypse_string(qtext)}"; '
                f"fields {_list_fields()}; "
                f"{where_clause} "
                f"limit {safe_limit}; "
                f"offset {offset};"
            )
            rows = self._post("games", body)
            games = [_game_from_row(row) for row in rows if isinstance(row, dict)]
            if not games or _query_suggests_edition(qtext):
                games = _merge_edition_search_results(self, games, qtext, cap=safe_limit)
            games = _merge_games_with_direct_lookups(self, games, qtext, cap=safe_limit)
            return _merge_games_with_collection_bundles(self, games, qtext, cap=safe_limit)
        where_clause = _games_filter_where_clause(
            section=section,
            platform_ids=platform_ids,
            genre_ids=genre_ids,
            game_mode_ids=game_mode_ids,
            player_perspective_ids=player_perspective_ids,
            game_type_id=game_type_id,
            include_section_sort=True,
        )
        body = (
            f"fields {_list_fields()}; "
            f"{where_clause} "
            f"limit {safe_limit}; "
            f"offset {offset};"
        )
        rows = self._post("games", body)
        return [_game_from_row(row) for row in rows if isinstance(row, dict)]

    def fetch_game_filter_options(self) -> dict[str, tuple[IgdbFilterOption, ...]]:
        """Taxonomies for game browse filters (cached ~1h per category)."""
        cache_ttl = 3600.0
        now = time.time()
        categories: list[tuple[str, str, str, str, int]] = [
            ("platforms", "platforms", "id,name,abbreviation", "name", 150),
            ("genres", "genres", "id,name", "name", 500),
            ("gameModes", "game_modes", "id,name", "name", 50),
            ("playerPerspectives", "player_perspectives", "id,name", "name", 50),
            ("gameTypes", "game_types", "id,type", "type", 50),
        ]
        out: dict[str, tuple[IgdbFilterOption, ...]] = {}
        for key, endpoint, fields, label_field, cap in categories:
            cached = self._filter_options_cache.get(key)
            if cached is not None and now - cached[0] < cache_ttl:
                out[key] = cached[1]
                continue
            rows = self._post(
                endpoint,
                f"fields {fields}; sort {label_field} asc; limit {cap};",
            )
            options: list[IgdbFilterOption] = []
            for row in rows:
                if not isinstance(row, dict) or row.get("id") is None:
                    continue
                label = _text(row.get(label_field))
                if label_field == "name" and not label:
                    label = _text(row.get("abbreviation"))
                if not label:
                    continue
                options.append(
                    IgdbFilterOption(external_id=str(int(row["id"])), name=label),
                )
            frozen = tuple(options)
            self._filter_options_cache[key] = (now, frozen)
            out[key] = frozen
        return out

    def fetch_games_for_company(
        self,
        company_id: str | int,
        company_role: str = "publisher",
        *,
        max_results: int = _COMPANY_GAMES_MAX_RESULTS,
    ) -> list[IgdbGame]:
        """List games for a publisher/developer by paging IGDB involved_companies."""
        cid = int(str(company_id).strip())
        role = (company_role or "publisher").strip().lower()
        role_filter = " & developer = true" if role == "developer" else " & publisher = true"
        cap = max(1, min(max_results, _COMPANY_GAMES_MAX_RESULTS))

        game_ids: list[int] = []
        seen_ids: set[int] = set()
        offset = 0
        while len(game_ids) < cap:
            body = (
                "fields game; "
                f"where company = {cid}{role_filter}; "
                "sort game asc; "
                f"limit {_COMPANY_GAMES_PAGE_SIZE}; "
                f"offset {offset};"
            )
            rows = self._post("involved_companies", body)
            if not rows:
                break
            batch_ids = _game_ids_from_involved_company_rows(rows)
            if not batch_ids:
                break
            for gid in batch_ids:
                if gid in seen_ids:
                    continue
                seen_ids.add(gid)
                game_ids.append(gid)
                if len(game_ids) >= cap:
                    break
            if len(rows) < _COMPANY_GAMES_PAGE_SIZE:
                break
            offset += _COMPANY_GAMES_PAGE_SIZE

        return self._fetch_games_by_ids(game_ids)

    def fetch_company_catalog_detail(
        self,
        company_id: str | int,
        *,
        primary_role: str | None = None,
        max_catalog: int = _COMPANY_GAMES_MAX_RESULTS,
    ) -> IgdbCompanyCatalogDetail:
        """Company profile, full catalog (developer + publisher), and popular picks."""
        cid = int(str(company_id).strip())
        cap = max(1, min(max_catalog, _COMPANY_GAMES_MAX_RESULTS))

        company_rows = self._post(
            "companies",
            "fields name, description, logo.image_id, logo.url, url, slug, "
            "websites.url, websites.category; "
            f"where id = {cid}; limit 1;",
        )
        if not company_rows or not isinstance(company_rows[0], dict):
            raise IgdbError(f"IGDB company {cid} was not found.")

        company_row = company_rows[0]
        name = _text(company_row.get("name")) or f"Company {cid}"
        description = _text(company_row.get("description"))
        slug = _text(company_row.get("slug"))
        logo = company_row.get("logo")
        logo_url: str | None = None
        if isinstance(logo, dict):
            logo_url = igdb_cover_url(logo)
        website_url = _company_website_url(company_row)

        game_roles: dict[int, set[str]] = {}
        offset = 0
        while len(game_roles) < cap:
            body = (
                "fields game.id, game.version_parent, developer, publisher; "
                f"where company = {cid}; "
                "sort game asc; "
                f"limit {_COMPANY_GAMES_PAGE_SIZE}; "
                f"offset {offset};"
            )
            rows = self._post("involved_companies", body)
            if not rows:
                break
            added = 0
            for row in rows:
                if not isinstance(row, dict):
                    continue
                gid = _canonical_game_id_from_involved_row(row)
                if gid is None:
                    continue
                roles = game_roles.setdefault(gid, set())
                if row.get("developer") is True:
                    roles.add("Developer")
                if row.get("publisher") is True:
                    roles.add("Publisher")
                if roles:
                    added += 1
            if added == 0 or len(rows) < _COMPANY_GAMES_PAGE_SIZE:
                break
            offset += _COMPANY_GAMES_PAGE_SIZE

        game_ids = list(game_roles.keys())[:cap]
        games = self._fetch_games_by_ids(game_ids)
        by_external_id = {int(g.external_id): g for g in games}

        catalog_entries: list[IgdbCompanyCatalogGame] = []
        for gid in game_ids:
            game = by_external_id.get(gid)
            if game is None:
                continue
            role_set = game_roles.get(gid) or set()
            if not role_set:
                fallback = (primary_role or "publisher").strip().lower()
                role_set = {"Developer"} if fallback == "developer" else {"Publisher"}
            roles = tuple(sorted(role_set, key=lambda r: (0 if r == "Developer" else 1, r)))
            catalog_entries.append(IgdbCompanyCatalogGame(game=game, roles=roles))

        catalog_entries = _merge_company_catalog_games(catalog_entries)
        catalog_entries.sort(
            key=lambda entry: (
                _game_release_unix(entry.game),
                entry.game.title.casefold(),
            ),
            reverse=True,
        )
        popular = sorted(
            catalog_entries,
            key=lambda entry: (_game_rating(entry.game), _game_release_unix(entry.game)),
            reverse=True,
        )[:12]

        return IgdbCompanyCatalogDetail(
            company_id=str(cid),
            name=name,
            description=description,
            logo_url=logo_url,
            website_url=website_url,
            slug=slug,
            catalog=tuple(catalog_entries),
            popular_catalog=tuple(popular),
        )

    def fetch_games_for_franchise(
        self,
        franchise_id: str | int,
        *,
        max_results: int = _COMPANY_GAMES_MAX_RESULTS,
    ) -> list[IgdbGame]:
        """Games in an IGDB franchise (series)."""
        fid = int(str(franchise_id).strip())
        cap = max(1, min(max_results, _COMPANY_GAMES_MAX_RESULTS))
        games: list[IgdbGame] = []
        seen: set[int] = set()
        offset = 0
        while len(games) < cap:
            body = (
                f"fields {_list_fields()}; "
                f"where (franchise = {fid} | franchises = [{fid}]) & version_parent = null; "
                "sort first_release_date asc; "
                f"limit {_COMPANY_GAMES_PAGE_SIZE}; "
                f"offset {offset};"
            )
            rows = self._post("games", body)
            if not rows:
                break
            added = 0
            for row in rows:
                if not isinstance(row, dict) or row.get("id") is None:
                    continue
                gid = int(row["id"])
                if gid in seen:
                    continue
                seen.add(gid)
                games.append(_game_from_row(row))
                added += 1
                if len(games) >= cap:
                    break
            if added == 0 or len(rows) < _COMPANY_GAMES_PAGE_SIZE:
                break
            offset += _COMPANY_GAMES_PAGE_SIZE
        return games

    def fetch_games_for_collection(
        self,
        collection_id: str | int,
        *,
        max_results: int = _COMPANY_GAMES_MAX_RESULTS,
    ) -> list[IgdbGame]:
        """Games in an IGDB collection (bundle / edition group)."""
        cid = int(str(collection_id).strip())
        cap = max(1, min(max_results, _COMPANY_GAMES_MAX_RESULTS))
        game_ids: list[int] = []
        seen_ids: set[int] = set()
        offset = 0
        while len(game_ids) < cap:
            body = (
                "fields game; "
                f"where collection = {cid}; "
                "sort game asc; "
                f"limit {_COMPANY_GAMES_PAGE_SIZE}; "
                f"offset {offset};"
            )
            rows = self._post("collection_memberships", body)
            if not rows:
                break
            batch_ids = _game_ids_from_involved_company_rows(rows)
            if not batch_ids:
                break
            for gid in batch_ids:
                if gid in seen_ids:
                    continue
                seen_ids.add(gid)
                game_ids.append(gid)
                if len(game_ids) >= cap:
                    break
            if len(rows) < _COMPANY_GAMES_PAGE_SIZE:
                break
            offset += _COMPANY_GAMES_PAGE_SIZE
        return self._fetch_games_by_ids(game_ids)

    def _fetch_games_by_ids(self, game_ids: list[int]) -> list[IgdbGame]:
        if not game_ids:
            return []
        games: list[IgdbGame] = []
        for start in range(0, len(game_ids), _COMPANY_GAMES_PAGE_SIZE):
            chunk = game_ids[start : start + _COMPANY_GAMES_PAGE_SIZE]
            id_clause = ",".join(str(gid) for gid in chunk)
            body = (
                f"fields {_list_fields()}; "
                f"where id = ({id_clause}) & version_parent = null; "
                f"limit {len(chunk)};"
            )
            rows = self._post("games", body)
            by_id = {
                int(row["id"]): _game_from_row(row)
                for row in rows
                if isinstance(row, dict) and row.get("id") is not None
            }
            for gid in chunk:
                game = by_id.get(gid)
                if game is not None:
                    games.append(game)
        return games

    def fetch_game_by_cover_image_id(self, image_id: str) -> IgdbGame | None:
        """Resolve a game from an IGDB cover hash (``co…``), as used in Stash CDN URLs."""
        iid = str(image_id).strip()
        if not iid:
            return None
        body = (
            f"fields {_list_fields()}; "
            f'where cover.image_id = "{_escape_apicalypse_string(iid)}" & version_parent = null; '
            "limit 1;"
        )
        rows = self._post("games", body)
        if not rows or not isinstance(rows[0], dict):
            return None
        return _game_from_row(rows[0])

    def fetch_game_by_slug(self, slug: str) -> IgdbGame | None:
        safe_slug = slug.strip().strip("/")
        if not safe_slug:
            return None
        escaped = _escape_apicalypse_string(safe_slug)
        for where in (
            f'where slug = "{escaped}" & version_parent = null; ',
            f'where slug = "{escaped}"; ',
        ):
            body = f"fields {_list_fields()}; {where} limit 1;"
            rows = self._post("games", body)
            if rows and isinstance(rows[0], dict):
                return _game_from_row(rows[0])
        return None

    def fetch_game_by_slug_resolved(self, slug: str) -> IgdbGame | None:
        """Resolve by IGDB slug, trying disambiguation suffix variants (``--1``, etc.)."""
        for candidate in legacy_game_slug_candidates(slug):
            game = self.fetch_game_by_slug(candidate)
            if game is not None:
                return game
        return None

    def fetch_game_by_id(self, game_id: str | int) -> IgdbGame | None:
        gid = str(game_id).strip()
        if not gid.isdigit():
            return None
        body = f"fields {_detail_fields()}; where id = {gid};"
        rows = self._post("games", body)
        if not rows or not isinstance(rows[0], dict):
            return None
        game = _game_from_row(rows[0], include_detail=True)
        meta = dict(game.metadata)
        meta.update(self.fetch_game_time_to_beat(gid))
        meta["videos"] = self.fetch_game_videos(gid)
        series = meta.get("franchise")
        if isinstance(series, dict) and series.get("id") and not series.get("name"):
            resolved = self.fetch_franchise_by_id(series["id"])
            if resolved:
                meta["franchise"] = resolved
        return IgdbGame(
            external_id=game.external_id,
            title=game.title,
            subtitle=game.subtitle,
            description=game.description,
            image_url=game.image_url,
            metadata=meta,
            publishers=game.publishers,
            developers=game.developers,
        )

    def fetch_franchise_by_id(self, franchise_id: str | int) -> dict[str, str] | None:
        fid = str(franchise_id).strip()
        if not fid.isdigit():
            return None
        body = f"fields name, slug; where id = {int(fid)};"
        rows = self._post("franchises", body)
        if not rows or not isinstance(rows[0], dict):
            return None
        return _franchise_dict_from_entry(rows[0])

    def fetch_game_videos(self, game_id: str | int) -> list[dict[str, str | None]]:
        """YouTube trailers/clips from IGDB ``game_videos``."""
        gid = str(game_id).strip()
        if not gid.isdigit():
            return []
        body = (
            "fields name,video_id; "
            f"where game = {int(gid)}; "
            "sort id desc; "
            "limit 10;"
        )
        try:
            rows = self._post("game_videos", body)
        except IgdbError:
            return []
        return _game_videos_from_rows(rows)

    def fetch_game_time_to_beat(self, game_id: str | int) -> dict[str, str]:
        """Returns formatted playtime labels keyed for catalog metadata."""
        gid = str(game_id).strip()
        if not gid.isdigit():
            return {}
        body = (
            "fields normally, hastily, completely; "
            f"where game_id = {int(gid)}; "
            "limit 1;"
        )
        rows = self._post("game_time_to_beats", body)
        if not rows or not isinstance(rows[0], dict):
            return {}
        row = rows[0]
        out: dict[str, str] = {}
        main = _format_playtime_seconds(row.get("normally"))
        extras = _format_playtime_seconds(row.get("hastily"))
        completion = _format_playtime_seconds(row.get("completely"))
        if main:
            out["timeToBeatMain"] = main
        if extras:
            out["timeToBeatExtras"] = extras
        if completion:
            out["timeToBeatCompletion"] = completion
        return out

    def search_games(self, query: str, *, limit: int = 10) -> list[IgdbGame]:
        return self.fetch_games(section="search", query=query, page=1, limit=limit)

    def search_collections(self, query: str, *, limit: int = 8) -> list[dict[str, Any]]:
        """IGDB collections (bundles / edition groups) matching a text query."""
        qtext = query.strip()
        if not qtext:
            return []
        safe_limit = max(1, min(limit, 25))
        body = (
            f'search "{_escape_apicalypse_string(qtext)}"; '
            "fields id,name,slug,games; "
            f"limit {safe_limit};"
        )
        rows = self._post("collections", body)
        return [row for row in rows if isinstance(row, dict)]

    def fetch_collection_by_slug(self, slug: str) -> dict[str, Any] | None:
        safe_slug = slug.strip().strip("/")
        if not safe_slug:
            return None
        body = (
            "fields id,name,slug,games; "
            f'where slug = "{_escape_apicalypse_string(safe_slug)}"; '
            "limit 1;"
        )
        rows = self._post("collections", body)
        if not rows or not isinstance(rows[0], dict):
            return None
        return rows[0]

    def fetch_games_from_collection_search(
        self,
        query: str,
        *,
        limit: int = 20,
        collection_limit: int = 8,
    ) -> list[IgdbGame]:
        """Games belonging to IGDB collections (bundles) that match the query."""
        rows = self.search_collections(query, limit=collection_limit)
        return _games_from_collection_rows(self, rows, query=query, limit=limit)

    def fetch_events(
        self,
        *,
        window: str = "previous",
        offset: int = 0,
        limit: int = 60,
    ) -> list[IgdbEvent]:
        """Industry events (Gamescom, showcases, etc.) from IGDB ``/events``."""
        safe_limit = max(1, min(limit, 50))
        safe_offset = max(0, offset)
        now = int(datetime.now(tz=UTC).timestamp())
        if window.strip().lower() == "upcoming":
            where = f"where start_time >= {now};"
            sort = "sort start_time asc;"
        else:
            where = "where start_time < {now} & start_time > 0;".format(now=now)
            sort = "sort start_time desc;"
        body = (
            f"fields {_event_list_fields()}; "
            f"{where} {sort} "
            f"limit {safe_limit}; offset {safe_offset};"
        )
        rows = self._post("events", body)
        return [_event_from_row(row) for row in rows if isinstance(row, dict)]

    def fetch_all_events(
        self,
        *,
        window: str = "previous",
        page_size: int = 50,
        max_pages: int = 5,
    ) -> list[IgdbEvent]:
        safe_page_size = max(1, min(page_size, 50))
        safe_max_pages = max(1, min(max_pages, 20))
        merged: list[IgdbEvent] = []
        for page in range(safe_max_pages):
            batch = self.fetch_events(
                window=window,
                offset=page * safe_page_size,
                limit=safe_page_size,
            )
            if not batch:
                break
            merged.extend(batch)
            if len(batch) < safe_page_size:
                break
        return _dedupe_events(merged)

    def fetch_event_by_slug(self, slug: str) -> IgdbEventDetail | None:
        safe_slug = slug.strip().strip("/")
        if not safe_slug:
            return None
        body = (
            f"fields {_event_detail_fields()}; "
            f'where slug = "{_escape_apicalypse_string(safe_slug)}";'
        )
        rows = self._post("events", body)
        if not rows or not isinstance(rows[0], dict):
            return None
        return _event_detail_from_row(rows[0])

    def fetch_event_by_id(self, event_id: str | int) -> IgdbEventDetail | None:
        eid = str(event_id).strip()
        if not eid.isdigit():
            return None
        body = f"fields {_event_detail_fields()}; where id = {eid};"
        rows = self._post("events", body)
        if not rows or not isinstance(rows[0], dict):
            return None
        return _event_detail_from_row(rows[0])

    def fetch_event_detail_resolved(self, slug: str) -> IgdbEventDetail | None:
        """Resolve event detail by IGDB slug, including legacy Stash slug variants."""
        for candidate in legacy_event_slug_candidates(slug):
            detail = self.fetch_event_by_slug(candidate)
            if detail is not None:
                return detail
        return None

    @staticmethod
    def cover_image_id_from_url(url: str | None) -> str | None:
        """Parse IGDB CDN URLs from Stash exports, e.g. …/t_cover_big/co7jfv.webp."""
        return igdb_image_id_from_url(url)

    @staticmethod
    def upgrade_cover_url(url: str | None) -> str | None:
        """Rewrite IGDB CDN URLs (often t_thumb from the API) to high-res cover size."""
        return upgrade_igdb_cover_url(url)

    def _get_access_token(self, *, force_refresh: bool = False) -> str:
        now = time.monotonic()
        with self._token_lock:
            if (
                not force_refresh
                and self._access_token
                and now < self._token_expires_at - 120
            ):
                return self._access_token

        response = requests.post(
            TWITCH_TOKEN_URL,
            params={
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "grant_type": "client_credentials",
            },
            timeout=self.timeout_seconds,
        )
        if response.status_code >= 400:
            raise IgdbError(
                f"Twitch token request failed ({response.status_code}): {response.text[:200]}",
            )
        payload = response.json()
        if not isinstance(payload, dict):
            raise IgdbError("Twitch token response was not JSON.")
        token = payload.get("access_token")
        expires_in = payload.get("expires_in", 3600)
        if not isinstance(token, str) or not token:
            raise IgdbError("Twitch token response missing access_token.")

        ttl = int(expires_in) if isinstance(expires_in, (int, float)) else 3600
        self._access_token = token
        self._token_expires_at = now + max(300, ttl)
        return token

    def _throttle(self) -> None:
        """Stay under IGDB's ~4 requests/second limit."""
        now = time.monotonic()
        elapsed = now - self._last_request_at
        if elapsed < 0.26:
            time.sleep(0.26 - elapsed)
        self._last_request_at = time.monotonic()

    def _post(self, endpoint: str, body: str) -> list[dict[str, Any]]:
        self._throttle()
        token = self._get_access_token()
        url = f"{IGDB_API_BASE}/{endpoint.strip('/')}"
        response = requests.post(
            url,
            data=body,
            headers={
                "Client-ID": self.client_id,
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
            timeout=self.timeout_seconds,
        )
        if response.status_code == 401:
            with self._token_lock:
                self._access_token = None
                self._token_expires_at = 0.0
            token = self._get_access_token(force_refresh=True)
            response = requests.post(
                url,
                data=body,
                headers={
                    "Client-ID": self.client_id,
                    "Authorization": f"Bearer {token}",
                    "Accept": "application/json",
                },
                timeout=self.timeout_seconds,
            )
        if response.status_code == 429:
            raise IgdbError("IGDB rate limit exceeded (429). Try again shortly.")
        if response.status_code >= 400:
            raise IgdbError(f"IGDB request failed ({response.status_code}): {response.text[:300]}")
        payload = response.json()
        if not isinstance(payload, list):
            raise IgdbError("IGDB response was not a JSON array.")
        return [row for row in payload if isinstance(row, dict)]


def _escape_apicalypse_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _list_fields() -> str:
    return (
        "name, slug, summary, first_release_date, total_rating, total_rating_count, "
        "cover.image_id, cover.url, platforms.name, genres.name, game_type.type"
    )


def _event_list_fields() -> str:
    """Fields for paginated event lists (sync / shelves)."""
    return "id,name,slug,start_time,end_time,description,event_logo.image_id,games"


def _event_detail_fields() -> str:
    """Fields for a single event with expanded games."""
    return (
        "id,name,slug,start_time,end_time,description,event_logo.image_id,"
        "games.id,games.name,games.slug,games.summary,games.cover.image_id,games.first_release_date"
    )


def igdb_game_slug_from_url(url: str | None) -> str | None:
    if not url:
        return None
    match = re.search(r"igdb\.com/games/([^/?#]+)", url.strip(), re.IGNORECASE)
    return match.group(1).strip() if match else None


def igdb_collection_slug_from_url(url: str | None) -> str | None:
    if not url:
        return None
    match = re.search(r"igdb\.com/collections/([^/?#]+)", url.strip(), re.IGNORECASE)
    return match.group(1).strip() if match else None


def title_to_igdb_slug_candidates(title: str) -> list[str]:
    """Build plausible IGDB slugs from a Stash/game title for direct lookup."""
    text = re.sub(r"[^\w\s]", " ", (title or "").strip().lower())
    base = re.sub(r"\s+", "-", text).strip("-")
    if not base:
        return []
    seen: set[str] = set()
    out: list[str] = []

    def add(value: str) -> None:
        key = value.strip().strip("/")
        if key and key not in seen:
            seen.add(key)
            out.append(key)

    add(base)
    for suffix in ("--1", "--2", "--3", "-1"):
        add(f"{base}{suffix}")
    for candidate in legacy_game_slug_candidates(base):
        add(candidate)
    return out


def legacy_game_slug_candidates(slug: str) -> list[str]:
    """IGDB game slugs may use ``--1`` disambiguation; try shorter variants too."""
    current = slug.strip().strip("/")
    if not current:
        return []
    candidates: list[str] = []
    seen: set[str] = set()

    def add(value: str) -> None:
        key = value.strip().strip("/")
        if key and key not in seen:
            seen.add(key)
            candidates.append(key)

    add(current)
    double_suffix = re.match(r"^(.+?)--(\d+)$", current)
    if double_suffix:
        add(double_suffix.group(1))
    single_suffix = re.match(r"^(.+?)-(\d+)$", current)
    if single_suffix and not single_suffix.group(1).endswith("-"):
        add(single_suffix.group(1))
    return candidates


def _merge_games_with_direct_lookups(
    client: IgdbClient,
    games: list[IgdbGame],
    query: str,
    *,
    cap: int,
) -> list[IgdbGame]:
    """Prepend slug / IGDB URL hits so paste-from-browser always works."""
    extras: list[IgdbGame] = []
    slug_from_url = igdb_game_slug_from_url(query)
    if slug_from_url:
        hit = client.fetch_game_by_slug_resolved(slug_from_url)
        if hit is not None:
            extras.append(hit)
    collection_slug_from_url = igdb_collection_slug_from_url(query)
    if collection_slug_from_url:
        extras.extend(_games_from_collection_slug(client, collection_slug_from_url))
    q = query.strip()
    if not slug_from_url and " " not in q and "-" in q and re.fullmatch(r"[\w-]+", q, re.IGNORECASE):
        hit = client.fetch_game_by_slug_resolved(q)
        if hit is not None:
            extras.append(hit)
        if not hit:
            extras.extend(_games_from_collection_slug(client, q))
    if not slug_from_url and " " in q:
        for slug in title_to_igdb_slug_candidates(q)[:4]:
            hit = client.fetch_game_by_slug_resolved(slug)
            if hit is not None:
                extras.append(hit)
                break

    seen: set[str] = set()
    merged: list[IgdbGame] = []
    for game in [*extras, *games]:
        gid = game.external_id
        if gid in seen:
            continue
        seen.add(gid)
        merged.append(game)
        if len(merged) >= cap:
            break
    return merged


def _merge_games_with_collection_bundles(
    client: IgdbClient,
    games: list[IgdbGame],
    query: str,
    *,
    cap: int,
) -> list[IgdbGame]:
    """Merge games from IGDB collection (bundle) search into catalog / import results."""
    qtext = query.strip()
    if not qtext:
        return games
    rows = client.search_collections(qtext, limit=8)
    bundle_games = _games_from_collection_rows(client, rows, query=qtext, limit=cap)
    if not bundle_games:
        return games

    want = _normalize_match_text(qtext)
    strong_bundle_match = any(
        _collection_title_match_score(want, _text(row.get("name"))) >= 0.92 for row in rows
    )
    ordered = bundle_games + games if strong_bundle_match else games + bundle_games

    seen: set[str] = set()
    merged: list[IgdbGame] = []
    for game in ordered:
        gid = game.external_id
        if gid in seen:
            continue
        seen.add(gid)
        merged.append(game)
        if len(merged) >= cap:
            break
    return merged


def _games_from_collection_rows(
    client: IgdbClient,
    rows: list[dict[str, Any]],
    *,
    query: str,
    limit: int,
) -> list[IgdbGame]:
    if not rows:
        return []
    want = _normalize_match_text(query)
    ranked = sorted(
        rows,
        key=lambda row: -_collection_title_match_score(want, _text(row.get("name"))),
    )
    game_ids: list[int] = []
    seen: set[int] = set()
    cap_ids = max(limit * 3, 30)
    for row in ranked:
        for gid in _game_ids_from_collection_row(row):
            if gid in seen:
                continue
            seen.add(gid)
            game_ids.append(gid)
            if len(game_ids) >= cap_ids:
                break
        if len(game_ids) >= cap_ids:
            break
    return client._fetch_games_by_ids(game_ids)[:limit]


def _games_from_collection_slug(client: IgdbClient, slug: str) -> list[IgdbGame]:
    row = client.fetch_collection_by_slug(slug)
    if row is None:
        for candidate in legacy_game_slug_candidates(slug):
            row = client.fetch_collection_by_slug(candidate)
            if row is not None:
                break
    if row is None:
        return []
    game_ids = _game_ids_from_collection_row(row)
    return client._fetch_games_by_ids(game_ids)


def _game_ids_from_collection_row(row: dict[str, Any]) -> list[int]:
    raw = row.get("games")
    if not isinstance(raw, list):
        return []
    out: list[int] = []
    for item in raw:
        if isinstance(item, int):
            out.append(item)
        elif isinstance(item, str) and item.isdigit():
            out.append(int(item))
    return out


def _normalize_match_text(text: str) -> str:
    cleaned = re.sub(r"[^\w\s]", " ", (text or "").strip().lower())
    return re.sub(r"\s+", " ", cleaned).strip()


_EDITION_QUERY_HINTS = (
    "edition",
    "remaster",
    "definitive",
    "complete",
    "goty",
    "game of the year",
    "enhanced",
    "deluxe",
    "ultimate",
    "gold pack",
    "anthology",
)


def _query_suggests_edition(query: str) -> bool:
    text = query.casefold()
    return any(hint in text for hint in _EDITION_QUERY_HINTS)


def _merge_edition_search_results(
    client: IgdbClient,
    games: list[IgdbGame],
    query: str,
    *,
    cap: int,
) -> list[IgdbGame]:
    """Include IGDB editions (version_parent set) when the main search omits them."""
    qtext = query.strip()
    if not qtext:
        return games
    body = (
        f'search "{_escape_apicalypse_string(qtext)}"; '
        f"fields {_list_fields()}; "
        "limit 15;"
    )
    rows = client._post("games", body)
    edition_games = [_game_from_row(row) for row in rows if isinstance(row, dict)]
    if not edition_games:
        return games

    want = _normalize_match_text(qtext)
    strong_edition = any(
        _collection_title_match_score(want, g.title) >= 0.85 for g in edition_games
    )
    ordered = edition_games + games if (not games or strong_edition) else games + edition_games

    seen: set[str] = set()
    merged: list[IgdbGame] = []
    for game in ordered:
        if game.external_id in seen:
            continue
        seen.add(game.external_id)
        merged.append(game)
        if len(merged) >= cap:
            break
    return merged


def _collection_title_match_score(want: str, name: str) -> float:
    if not want or not name:
        return 0.0
    got = _normalize_match_text(name)
    if want == got:
        return 1.0
    if want in got or got in want:
        return 0.92
    want_tokens = set(want.split())
    got_tokens = set(got.split())
    if not want_tokens or not got_tokens:
        return 0.0
    overlap = len(want_tokens & got_tokens) / max(len(want_tokens), len(got_tokens))
    return overlap


def legacy_event_slug_candidates(slug: str) -> list[str]:
    """Stash slugs often append a 5-char suffix (e.g. ``…-ctulv``); IGDB does not."""
    current = slug.strip().strip("/")
    if not current:
        return []
    candidates = [current]
    while True:
        parts = current.rsplit("-", 1)
        if len(parts) != 2 or len(parts[1]) != 5 or not parts[1].isalnum():
            break
        current = parts[0]
        if current in candidates:
            break
        candidates.append(current)
    return candidates


def _detail_fields() -> str:
    return (
        "name, summary, storyline, first_release_date, total_rating, total_rating_count, "
        "aggregated_rating, rating, rating_count, "
        "cover.image_id, cover.url, screenshots.url, screenshots.image_id, "
        "platforms.name, genres.name, game_modes.name, game_type.type, "
        "player_perspectives.name, "
        "involved_companies.developer, involved_companies.publisher, "
        "involved_companies.company.id, involved_companies.company.name, "
        "franchise.id, franchise.name, franchise.slug, "
        "franchises.id, franchises.name, franchises.slug, "
        "collection.id, collection.name, collection.slug, "
        "collections.id, collections.name, collections.slug, "
        "game_status.status, "
        "similar_games.id, similar_games.name, similar_games.slug, "
        "similar_games.cover.image_id, similar_games.cover.url, url, slug"
    )


def _parse_igdb_id_list(raw: str | None) -> tuple[int, ...]:
    if not raw or not str(raw).strip():
        return ()
    out: list[int] = []
    for part in str(raw).split(","):
        token = part.strip()
        if token.isdigit():
            out.append(int(token))
    return tuple(out)


def _games_filter_where_clause(
    *,
    section: str,
    platform_ids: tuple[int, ...],
    genre_ids: tuple[int, ...],
    game_mode_ids: tuple[int, ...],
    player_perspective_ids: tuple[int, ...],
    game_type_id: int | None,
    include_section_sort: bool = True,
) -> str:
    key = section.strip().lower().replace("-", "_")
    now = int(datetime.now(tz=UTC).timestamp())
    clauses = ["version_parent = null"]
    if platform_ids:
        clauses.append(f"platforms = ({','.join(str(i) for i in platform_ids)})")
    if genre_ids:
        clauses.append(f"genres = ({','.join(str(i) for i in genre_ids)})")
    if game_mode_ids:
        clauses.append(f"game_modes = ({','.join(str(i) for i in game_mode_ids)})")
    if player_perspective_ids:
        ids = ",".join(str(i) for i in player_perspective_ids)
        clauses.append(f"player_perspectives = ({ids})")
    if game_type_id is not None:
        clauses.append(f"game_type = {game_type_id}")

    if key in {"popular", "hyped", "hypes"}:
        clauses.append("hypes > 0")
        sort = "sort hypes desc"
    elif key in {"top_rated", "top", "rated"}:
        clauses.append("total_rating > 0")
        sort = "sort total_rating desc"
    elif key in {"upcoming", "future"}:
        clauses.append(f"first_release_date > {now}")
        sort = "sort first_release_date asc"
    elif key in {"recent", "new", "latest"}:
        clauses.append("first_release_date > 0")
        sort = "sort first_release_date desc"
    else:
        sort = "sort total_rating desc"

    where = f"where {' & '.join(clauses)};"
    if not include_section_sort:
        return f"{where} "
    return f"{where} {sort}; "


def _section_where_clause(section: str) -> str:
    return _games_filter_where_clause(
        section=section,
        platform_ids=(),
        genre_ids=(),
        game_mode_ids=(),
        player_perspective_ids=(),
        game_type_id=None,
    )


def igdb_event_url(slug: str) -> str:
    return f"https://www.igdb.com/events/{slug.strip().strip('/')}"


def igdb_game_url(slug: str) -> str:
    return f"https://www.igdb.com/games/{slug.strip().strip('/')}"


def igdb_event_logo_url(logo: dict[str, Any]) -> str | None:
    image_id = _text(logo.get("image_id"))
    if image_id:
        return igdb_build_image_url(image_id, size=IGDB_SCREENSHOT_SIZE)
    return upgrade_igdb_screenshot_url(_text(logo.get("url")))


def _event_from_row(row: dict[str, Any]) -> IgdbEvent:
    eid = row.get("id")
    title = str(row.get("name") or "").strip()
    slug = str(row.get("slug") or "").strip()
    starts_at = _datetime_from_unix(row.get("start_time"))
    if eid is None or not title or not slug or starts_at is None:
        raise IgdbError("IGDB event row missing id, name, slug, or start_time.")

    logo = row.get("event_logo") if isinstance(row.get("event_logo"), dict) else {}
    raw_games = row.get("games")
    game_ids: list[int] = []
    if isinstance(raw_games, list):
        for entry in raw_games:
            if isinstance(entry, int):
                game_ids.append(entry)
            elif isinstance(entry, dict):
                gid = entry.get("id")
                if isinstance(gid, int):
                    game_ids.append(gid)

    return IgdbEvent(
        external_id=str(int(eid)),
        slug=slug,
        title=title,
        starts_at=starts_at,
        ends_at=_datetime_from_unix(row.get("end_time")),
        description=_text(row.get("description")),
        image_url=igdb_event_logo_url(logo),
        game_ids=tuple(game_ids),
    )


def _event_detail_from_row(row: dict[str, Any]) -> IgdbEventDetail:
    base = _event_from_row(row)
    games: list[IgdbGame] = []
    raw_games = row.get("games")
    if isinstance(raw_games, list):
        for game_row in raw_games:
            if not isinstance(game_row, dict):
                continue
            if game_row.get("id") is None:
                continue
            try:
                games.append(_game_from_row(game_row))
            except IgdbError:
                continue
    return IgdbEventDetail(
        external_id=base.external_id,
        slug=base.slug,
        title=base.title,
        starts_at=base.starts_at,
        ends_at=base.ends_at,
        description=base.description,
        image_url=base.image_url,
        game_ids=base.game_ids,
        games=tuple(games),
    )


def _dedupe_events(events: list[IgdbEvent]) -> list[IgdbEvent]:
    seen: set[str] = set()
    out: list[IgdbEvent] = []
    for event in events:
        if event.slug in seen:
            continue
        seen.add(event.slug)
        out.append(event)
    return out


def _datetime_from_unix(value: object) -> datetime | None:
    if not isinstance(value, (int, float)) or value <= 0:
        return None
    return datetime.fromtimestamp(int(value), tz=UTC)


def _game_from_row(row: dict[str, Any], *, include_detail: bool = False) -> IgdbGame:
    gid = row.get("id")
    title = str(row.get("name") or "").strip()
    if gid is None or not title:
        raise IgdbError("IGDB game row missing id or name.")

    summary = _text(row.get("summary"))
    if include_detail:
        storyline = _text(row.get("storyline"))
        description = storyline or summary
    else:
        description = summary

    cover = row.get("cover") if isinstance(row.get("cover"), dict) else {}
    image_url = igdb_cover_url(cover)
    gallery_urls: list[str] = []
    if include_detail:
        gallery_urls = igdb_screenshot_urls(row.get("screenshots"))

    year = _year_from_unix(row.get("first_release_date"))
    rating = _rating_label(row.get("total_rating"))
    platforms = _join_names(row.get("platforms"))
    genre = _join_names(row.get("genres"))
    game_type = _game_type_label(row.get("game_type"))

    subtitle_parts: list[str] = []
    if year:
        subtitle_parts.append(year)
    if rating:
        subtitle_parts.append(rating)
    if platforms:
        subtitle_parts.append(platforms)
    elif genre:
        subtitle_parts.append(genre)

    slug = _text(row.get("slug"))
    release_unix = row.get("first_release_date")
    metadata: dict[str, object] = {
        "firstReleaseDate": year,
        "igdbRating": row.get("total_rating"),
        "igdbRatingCount": row.get("total_rating_count"),
        "platforms": platforms,
        "genres": genre,
    }
    if game_type:
        metadata["gameType"] = game_type
    if isinstance(release_unix, (int, float)) and release_unix > 0:
        metadata["firstReleaseDateUnix"] = int(release_unix)
    if slug:
        metadata["slug"] = slug
    publishers: tuple[IgdbCompany, ...] = ()
    developers: tuple[IgdbCompany, ...] = ()
    if include_detail:
        game_modes = _join_names(row.get("game_modes"), max_items=8)
        if game_modes:
            metadata["gameModes"] = game_modes
        perspectives = _join_names(row.get("player_perspectives"), max_items=8)
        if perspectives:
            metadata["playerPerspectives"] = perspectives
        metadata["storyline"] = _text(row.get("storyline"))
        metadata["aggregatedRating"] = row.get("aggregated_rating")
        metadata["userRating"] = row.get("rating")
        metadata["igdbUrl"] = row.get("url")
        metadata["slug"] = row.get("slug")
        if gallery_urls:
            metadata["galleryUrls"] = gallery_urls
        franchise = _first_franchise_from_row(row)
        if franchise:
            franchise.setdefault("kind", "franchise")
            metadata["franchise"] = franchise
        collections = _collections_from_row(row)
        if collections:
            metadata["collections"] = collections
        similar = _similar_games_from_row(row)
        if similar:
            metadata["similarGames"] = similar
        publishers, developers = _involved_companies_from_row(row)

    return IgdbGame(
        external_id=str(int(gid)),
        title=title,
        subtitle=" · ".join(subtitle_parts) if subtitle_parts else None,
        description=description,
        image_url=image_url,
        metadata=metadata,
        publishers=publishers,
        developers=developers,
    )


def _youtube_id_from_igdb_video_id(value: object) -> str | None:
    text = _text(value)
    if not text:
        return None
    if len(text) == 11 and text.replace("-", "").replace("_", "").isalnum():
        return text
    if "youtu.be/" in text:
        tail = text.split("youtu.be/", 1)[-1].split("?", 1)[0].strip("/")
        return tail[:11] if tail else None
    if "v=" in text:
        tail = text.split("v=", 1)[-1].split("&", 1)[0].strip()
        return tail[:11] if tail else None
    return None


def _game_videos_from_rows(rows: object) -> list[dict[str, str | None]]:
    if not isinstance(rows, list):
        return []
    out: list[dict[str, str | None]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        youtube_id = _youtube_id_from_igdb_video_id(row.get("video_id"))
        if not youtube_id:
            continue
        title = _text(row.get("name")) or "Video"
        out.append(
            {
                "title": title,
                "subtitle": None,
                "imageUrl": f"https://img.youtube.com/vi/{youtube_id}/hqdefault.jpg",
                "url": f"https://www.youtube.com/watch?v={youtube_id}",
            },
        )
        if len(out) >= 10:
            break
    return out


def _format_playtime_seconds(value: object) -> str | None:
    if not isinstance(value, (int, float)) or value <= 0:
        return None
    total = int(value)
    hours = total // 3600
    minutes = (total % 3600) // 60
    if hours > 0 and minutes > 0:
        return f"{hours}h {minutes}m"
    if hours > 0:
        return f"{hours}h"
    if minutes > 0:
        return f"{minutes}m"
    return None


def _franchise_dict_from_entry(entry: object) -> dict[str, str] | None:
    if isinstance(entry, dict):
        fid = entry.get("id")
        name = _text(entry.get("name"))
        slug = _text(entry.get("slug"))
        if fid is None:
            return None
        out: dict[str, str] = {"id": str(int(fid))}
        if name:
            out["name"] = name
        if slug:
            out["slug"] = slug
        return out
    if isinstance(entry, int):
        return {"id": str(entry)}
    return None


def _first_franchise_from_row(row: dict[str, Any]) -> dict[str, str] | None:
    main = _franchise_dict_from_entry(row.get("franchise"))
    if main is not None and main.get("name"):
        main.setdefault("kind", "franchise")
        return main

    raw = row.get("franchises")
    if isinstance(raw, list):
        for entry in raw:
            parsed = _franchise_dict_from_entry(entry)
            if parsed is not None and parsed.get("name"):
                return parsed
        for entry in raw:
            parsed = _franchise_dict_from_entry(entry)
            if parsed is not None:
                return parsed

    collection = _franchise_dict_from_entry(row.get("collection"))
    if collection is not None and collection.get("name"):
        collection["kind"] = "collection"
        return collection

    if main is not None and main.get("name"):
        main.setdefault("kind", "franchise")
        return main
    return None


def _collections_from_row(row: dict[str, Any]) -> list[dict[str, str]]:
    raw = row.get("collections")
    if not isinstance(raw, list):
        return []
    out: list[dict[str, str]] = []
    seen: set[str] = set()
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        cid = entry.get("id")
        name = _text(entry.get("name"))
        slug = _text(entry.get("slug"))
        if cid is None or not name:
            continue
        key = str(int(cid))
        if key in seen:
            continue
        seen.add(key)
        item: dict[str, str] = {"id": key, "name": name}
        if slug:
            item["slug"] = slug
        out.append(item)
    out.sort(key=lambda item: item["name"].casefold())
    return out


def _similar_games_from_row(row: dict[str, Any]) -> list[dict[str, object]]:
    raw = row.get("similar_games")
    if not isinstance(raw, list):
        return []
    out: list[dict[str, object]] = []
    seen: set[str] = set()
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        gid = entry.get("id")
        name = _text(entry.get("name"))
        if gid is None or not name:
            continue
        key = str(int(gid))
        if key in seen:
            continue
        seen.add(key)
        cover = entry.get("cover") if isinstance(entry.get("cover"), dict) else {}
        image_url = igdb_cover_url(cover)
        slug = _text(entry.get("slug"))
        item: dict[str, object] = {"id": key, "name": name}
        if image_url:
            item["imageUrl"] = image_url
        if slug:
            item["slug"] = slug
        out.append(item)
    return out[:12]


def _canonical_game_id_from_involved_row(row: dict[str, Any]) -> int | None:
    """Map edition/child IGDB ids to their parent game when present."""
    return _canonical_igdb_game_id(row.get("game"))


def _canonical_igdb_game_id(raw_game: object) -> int | None:
    if isinstance(raw_game, int):
        return raw_game
    if not isinstance(raw_game, dict):
        return None
    parent = raw_game.get("version_parent")
    if isinstance(parent, int):
        return parent
    if isinstance(parent, dict):
        parent_id = parent.get("id")
        if isinstance(parent_id, int):
            return parent_id
    game_id = raw_game.get("id")
    if isinstance(game_id, int):
        return game_id
    return None


def _game_id_from_involved_row(row: dict[str, Any]) -> int | None:
    return _canonical_game_id_from_involved_row(row)


def _company_catalog_dedupe_key(game: IgdbGame) -> str:
    """Collapse duplicate IGDB rows that share slug or display title."""
    slug = _text(game.metadata.get("slug"))
    if slug:
        return f"slug:{slug.casefold()}"
    title = game.title.strip().casefold()
    if not title:
        return f"id:{game.external_id}"
    year = _text(str(game.metadata.get("firstReleaseDate") or ""))
    if year:
        return f"title:{title}|y:{year}"
    return f"title:{title}"


def _pick_preferred_company_catalog_entry(
    left: IgdbCompanyCatalogGame,
    right: IgdbCompanyCatalogGame,
) -> IgdbCompanyCatalogGame:
    left_rating = _game_rating(left.game)
    right_rating = _game_rating(right.game)
    if right_rating > left_rating:
        return right
    if left_rating > right_rating:
        return left
    if _game_release_unix(right.game) > _game_release_unix(left.game):
        return right
    return left


def _merge_company_catalog_games(
    entries: list[IgdbCompanyCatalogGame],
) -> list[IgdbCompanyCatalogGame]:
    merged: dict[str, IgdbCompanyCatalogGame] = {}
    for entry in entries:
        key = _company_catalog_dedupe_key(entry.game)
        prior = merged.get(key)
        if prior is None:
            merged[key] = entry
            continue
        combined = set(prior.roles) | set(entry.roles)
        roles = tuple(sorted(combined, key=lambda r: (0 if r == "Developer" else 1, r)))
        preferred = _pick_preferred_company_catalog_entry(prior, entry)
        merged[key] = IgdbCompanyCatalogGame(game=preferred.game, roles=roles)
    return list(merged.values())


def _game_ids_from_involved_company_rows(rows: list[dict[str, Any]]) -> list[int]:
    ids: list[int] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        gid = _game_id_from_involved_row(row)
        if gid is not None:
            ids.append(gid)
    return ids


def _company_website_url(row: dict[str, Any]) -> str | None:
    websites = row.get("websites")
    if isinstance(websites, list):
        official: str | None = None
        fallback: str | None = None
        for entry in websites:
            if not isinstance(entry, dict):
                continue
            url = _text(entry.get("url"))
            if not url:
                continue
            category = entry.get("category")
            if category == 1:
                official = url
                break
            if fallback is None:
                fallback = url
        if official:
            return official
        if fallback:
            return fallback
    return _text(row.get("url"))


def _game_release_unix(game: IgdbGame) -> int:
    raw = game.metadata.get("firstReleaseDateUnix")
    if isinstance(raw, int):
        return raw
    return 0


def _game_rating(game: IgdbGame) -> float:
    raw = game.metadata.get("igdbRating")
    if isinstance(raw, (int, float)):
        return float(raw)
    return 0.0


def _involved_companies_from_row(
    row: dict[str, Any],
) -> tuple[tuple[IgdbCompany, ...], tuple[IgdbCompany, ...]]:
    raw = row.get("involved_companies")
    if not isinstance(raw, list):
        return (), ()
    publishers: list[IgdbCompany] = []
    developers: list[IgdbCompany] = []
    seen_pub: set[str] = set()
    seen_dev: set[str] = set()
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        company = entry.get("company")
        if not isinstance(company, dict):
            continue
        cid = company.get("id")
        name = _text(company.get("name"))
        if cid is None or not name:
            continue
        company_id = str(int(cid))
        ref = IgdbCompany(external_id=company_id, name=name)
        if entry.get("publisher") is True and company_id not in seen_pub:
            seen_pub.add(company_id)
            publishers.append(ref)
        if entry.get("developer") is True and company_id not in seen_dev:
            seen_dev.add(company_id)
            developers.append(ref)
    publishers.sort(key=lambda c: c.name.casefold())
    developers.sort(key=lambda c: c.name.casefold())
    return tuple(publishers), tuple(developers)


def _text(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _year_from_unix(value: object) -> str | None:
    if not isinstance(value, (int, float)) or value <= 0:
        return None
    return str(datetime.fromtimestamp(int(value), tz=UTC).year)


def _rating_label(value: object) -> str | None:
    if not isinstance(value, (int, float)):
        return None
    score = float(value)
    if score <= 0:
        return None
    return f"IGDB {score:.1f}"


def _game_type_label(value: object) -> str | None:
    if isinstance(value, dict):
        return _text(value.get("type"))
    return None


def _join_names(value: object, *, max_items: int = 4) -> str | None:
    if not isinstance(value, list):
        return None
    names: list[str] = []
    for item in value[:max_items]:
        if isinstance(item, dict):
            name = _text(item.get("name"))
            if name:
                names.append(name)
    if not names:
        return None
    return ", ".join(names)


def igdb_image_id_from_url(url: str | None) -> str | None:
    if not url:
        return None
    match = re.search(r"/t_[^/]+/([a-z0-9]+)", url, re.IGNORECASE)
    return match.group(1) if match else None


def igdb_build_image_url(image_id: str, *, size: str, ext: str = "jpg") -> str:
    safe_id = image_id.strip()
    return f"{IGDB_IMAGE_CDN_PREFIX}{size}/{safe_id}.{ext}"


def upgrade_igdb_cover_url(url: str | None) -> str | None:
    """IGDB list/detail payloads often ship cover.url as t_thumb (~90px)."""
    if not url:
        return None
    normalized = url.strip()
    if not normalized:
        return None
    if not normalized.startswith("http"):
        normalized = f"https:{normalized}"

    image_id = igdb_image_id_from_url(normalized)
    if image_id:
        ext = "webp" if normalized.lower().endswith(".webp") else "jpg"
        return igdb_build_image_url(image_id, size=IGDB_COVER_SIZE, ext=ext)

    if IGDB_IMAGE_SIZE_TOKEN_RE.search(normalized):
        return IGDB_IMAGE_SIZE_TOKEN_RE.sub(
            f"{IGDB_IMAGE_CDN_PREFIX}{IGDB_COVER_SIZE}/",
            normalized,
            count=1,
        )
    return normalized


def igdb_cover_url(cover: dict[str, Any]) -> str | None:
    image_id = _text(cover.get("image_id"))
    if image_id:
        return igdb_build_image_url(image_id, size=IGDB_COVER_SIZE)
    return upgrade_igdb_cover_url(_text(cover.get("url")))


def igdb_screenshot_urls(value: object, *, limit: int = 8) -> list[str]:
    if not isinstance(value, list):
        return []
    urls: list[str] = []
    for item in value[:limit]:
        if not isinstance(item, dict):
            continue
        image_id = _text(item.get("image_id"))
        if image_id:
            urls.append(igdb_build_image_url(image_id, size=IGDB_SCREENSHOT_SIZE))
            continue
        upgraded = upgrade_igdb_screenshot_url(_text(item.get("url")))
        if upgraded:
            urls.append(upgraded)
    return urls


def upgrade_igdb_screenshot_url(url: str | None) -> str | None:
    if not url:
        return None
    normalized = url.strip()
    if not normalized:
        return None
    if not normalized.startswith("http"):
        normalized = f"https:{normalized}"
    image_id = igdb_image_id_from_url(normalized)
    if image_id:
        ext = "webp" if normalized.lower().endswith(".webp") else "jpg"
        return igdb_build_image_url(image_id, size=IGDB_SCREENSHOT_SIZE, ext=ext)
    if IGDB_IMAGE_SIZE_TOKEN_RE.search(normalized):
        return IGDB_IMAGE_SIZE_TOKEN_RE.sub(
            f"{IGDB_IMAGE_CDN_PREFIX}{IGDB_SCREENSHOT_SIZE}/",
            normalized,
            count=1,
        )
    return normalized
