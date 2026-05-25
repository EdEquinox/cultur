from __future__ import annotations

import base64
import hashlib
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    host: str
    port: int
    yamtrack_base_url: str | None
    database_url: str
    tmdb_api_key: str | None
    tmdb_language: str
    omdb_api_key: str | None
    igdb_client_id: str | None
    igdb_client_secret: str | None
    igdb_language: str
    data_dir: Path
    session_store_path: Path
    access_token_ttl_seconds: int
    refresh_token_ttl_seconds: int
    secret_key: str
    request_timeout_seconds: float
    stash_events_cache_ttl_seconds: int
    stash_events_sync_page_size: int
    stash_events_sync_max_pages: int
    bgg_api_token: str | None
    bgg_min_request_interval_seconds: float
    bgg_hot_cache_ttl_seconds: int
    openlibrary_min_request_interval_seconds: float
    hardcover_api_token: str | None
    porbase_isbn_url_template: str
    book_catalog_primary_source: str | None
    stash_collection_paths_json: str
    musicboard_list_paths_json: str
    discogs_api_key: str | None
    discogs_api_secret: str | None
    discogs_user_agent: str
    discogs_min_request_interval_seconds: float
    musicbrainz_app_name: str
    musicbrainz_contact: str
    musicbrainz_min_request_interval_seconds: float
    fanart_api_key: str | None
    fanart_client_key: str | None
    lastfm_api_key: str | None
    lastfm_home_tag: str

    @property
    def fernet_key(self) -> bytes:
        digest = hashlib.sha256(self.secret_key.encode("utf-8")).digest()
        return base64.urlsafe_b64encode(digest)


def load_settings() -> Settings:
    root_dir = Path(__file__).resolve().parent.parent
    data_dir = Path(os.environ.get("SERVER_API_DATA_DIR", root_dir / "data"))
    default_database_url = f"sqlite:///{(data_dir / 'backend.sqlite3').resolve()}"
    session_store_path = Path(
        os.environ.get("SERVER_API_SESSION_STORE", data_dir / "sessions.json"),
    )
    secret_key = os.environ.get("SERVER_API_SECRET_KEY")
    if not secret_key:
        raise RuntimeError("SERVER_API_SECRET_KEY must be set.")

    return Settings(
        host=os.environ.get("SERVER_API_HOST", "0.0.0.0"),
        port=int(os.environ.get("SERVER_API_PORT", "8787")),
        yamtrack_base_url=os.environ.get("YAMTRACK_BASE_URL"),
        database_url=os.environ.get("SERVER_API_DATABASE_URL", default_database_url),
        tmdb_api_key=os.environ.get("TMDB_API") or os.environ.get("TMDB_API_KEY"),
        tmdb_language=os.environ.get("TMDB_LANG", "en-US"),
        omdb_api_key=os.environ.get("OMDB_API_KEY") or os.environ.get("OMDB_API"),
        igdb_client_id=os.environ.get("IGDB_CLIENT_ID") or os.environ.get("TWITCH_CLIENT_ID"),
        igdb_client_secret=os.environ.get("IGDB_CLIENT_SECRET")
        or os.environ.get("TWITCH_CLIENT_SECRET"),
        igdb_language=os.environ.get("IGDB_LANGUAGE", "en"),
        data_dir=data_dir,
        session_store_path=session_store_path,
        access_token_ttl_seconds=int(
            os.environ.get("SERVER_API_ACCESS_TTL_SECONDS", str(60 * 60 * 24 * 14)),
        ),
        refresh_token_ttl_seconds=int(
            os.environ.get("SERVER_API_REFRESH_TTL_SECONDS", str(60 * 60 * 24 * 90)),
        ),
        secret_key=secret_key,
        request_timeout_seconds=float(
            os.environ.get("SERVER_API_REQUEST_TIMEOUT_SECONDS", "20"),
        ),
        stash_events_cache_ttl_seconds=int(
            os.environ.get("STASH_EVENTS_CACHE_TTL_SECONDS", str(60 * 60 * 6)),
        ),
        stash_events_sync_page_size=int(os.environ.get("STASH_EVENTS_SYNC_PAGE_SIZE", "60")),
        stash_events_sync_max_pages=int(os.environ.get("STASH_EVENTS_SYNC_MAX_PAGES", "5")),
        bgg_api_token=os.environ.get("BGG_API_TOKEN") or os.environ.get("BGG_APPLICATION_TOKEN"),
        bgg_min_request_interval_seconds=float(
            os.environ.get("BGG_MIN_REQUEST_INTERVAL_SECONDS", "2"),
        ),
        bgg_hot_cache_ttl_seconds=int(os.environ.get("BGG_HOT_CACHE_TTL_SECONDS", str(60 * 60))),
        openlibrary_min_request_interval_seconds=float(
            os.environ.get("OPENLIBRARY_MIN_REQUEST_INTERVAL_SECONDS", "0.25"),
        ),
        hardcover_api_token=os.environ.get("HARDCOVER_API_TOKEN")
        or os.environ.get("HARDCOVER_API_KEY"),
        porbase_isbn_url_template=os.environ.get(
            "PORBASE_ISBN_URL_TEMPLATE",
            "http://urn.porbase.org/isbn/dc/xml?id={isbn}",
        ),
        book_catalog_primary_source=(
            os.environ.get("BOOK_CATALOG_PRIMARY_SOURCE", "hardcover").strip().lower()
            or "hardcover"
        ),
        stash_collection_paths_json=os.environ.get("STASH_COLLECTION_PATHS", ""),
        musicboard_list_paths_json=os.environ.get("MUSICBOARD_LIST_PATHS", ""),
        discogs_api_key=os.environ.get("DISCOGS_API_KEY"),
        discogs_api_secret=os.environ.get("DISCOGS_API_SECRET"),
        discogs_user_agent=os.environ.get("DISCOGS_USER_AGENT", "CulturApp/1.0 +https://github.com/yamtrack"),
        discogs_min_request_interval_seconds=float(
            os.environ.get("DISCOGS_MIN_REQUEST_INTERVAL_SECONDS", "1.1"),
        ),
        musicbrainz_app_name=os.environ.get("MUSICBRAINZ_APP_NAME", "Cultur"),
        musicbrainz_contact=os.environ.get(
            "MUSICBRAINZ_CONTACT",
            "cultur@example.com",
        ),
        musicbrainz_min_request_interval_seconds=float(
            os.environ.get("MUSICBRAINZ_MIN_REQUEST_INTERVAL_SECONDS", "1.1"),
        ),
        fanart_api_key=os.environ.get("FANART_API_KEY"),
        fanart_client_key=os.environ.get("FANART_CLIENT_KEY"),
        lastfm_api_key=os.environ.get("LASTFM_API_KEY"),
        lastfm_home_tag=os.environ.get("LASTFM_HOME_TAG", "rock"),
    )
