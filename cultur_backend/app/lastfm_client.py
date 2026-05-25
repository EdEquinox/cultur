"""Last.fm API — primary music catalog (search, albums, artists, home shelves)."""

from __future__ import annotations

import hashlib
import logging
import re
import threading
import time
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import quote, unquote

import httpx

from .musicbrainz_client import compact_mbid, normalize_mbid

logger = logging.getLogger(__name__)

LASTFM_API_BASE = "https://ws.audioscrobbler.com/2.0/"
LFM_ALBUM_EXTERNAL_PREFIX = "lfm-album:"
LFM_ARTIST_PERSON_PREFIX = "lfm-artist:"
_DEFAULT_HOME_TAG = "rock"
# media_items.external_id is varchar(128); prefix is stored with the key.
_LFM_ALBUM_KEY_MAX_LEN = 128 - len(LFM_ALBUM_EXTERNAL_PREFIX)

# Last.fm returns this asset for many artists/albums after API image restrictions.
_PLACEHOLDER_IMAGE_MARKERS = (
    "2a96cbd8b46e442fc41c2b86b821562f",
    "default_album",
    "default/artist",
)


class LastfmError(RuntimeError):
    pass


@dataclass(slots=True)
class LfmAlbumSearchResult:
    lastfm_id: str
    title: str
    artist_name: str
    image_url: str | None = None
    url: str | None = None


@dataclass(slots=True)
class LfmTrackRow:
    name: str
    duration_seconds: int | None = None
    position: int | None = None


@dataclass(slots=True)
class LfmArtistDetail:
    lastfm_key: str
    name: str
    image_url: str | None = None
    url: str | None = None
    artist_mbid: str | None = None
    wiki_summary: str | None = None
    tags: list[str] = field(default_factory=list)
    listeners: int | None = None
    playcount: int | None = None


@dataclass(slots=True)
class LfmAlbumDetail:
    lastfm_id: str
    title: str
    artist_name: str
    image_url: str | None = None
    url: str | None = None
    release_group_mbid: str | None = None
    released: str | None = None
    wiki_summary: str | None = None
    tags: list[str] = field(default_factory=list)
    tracklist: list[LfmTrackRow] = field(default_factory=list)
    listeners: int | None = None
    playcount: int | None = None


class LastfmClient:
    def __init__(
        self,
        *,
        api_key: str,
        timeout_seconds: float = 15.0,
        min_request_interval_seconds: float = 0.25,
    ) -> None:
        self._api_key = (api_key or "").strip()
        if not self._api_key:
            raise LastfmError("Last.fm API key is required.")
        self._timeout = timeout_seconds
        self._min_interval = max(0.0, min_request_interval_seconds)
        self._lock = threading.Lock()
        self._last_request_at = 0.0

    def search_albums(self, query: str, *, limit: int = 15) -> list[LfmAlbumSearchResult]:
        """Album + artist top-albums search (Last.fm often omits album `id` in JSON)."""
        return self.search_catalog(query, limit=limit)

    def search_catalog(self, query: str, *, limit: int = 30) -> list[LfmAlbumSearchResult]:
        text = (query or "").strip()
        if not text:
            return []
        safe_limit = max(1, min(limit, 30))
        out: list[LfmAlbumSearchResult] = []
        seen: set[str] = set()

        def _add(parsed: LfmAlbumSearchResult | None) -> None:
            if parsed is None:
                return
            key = album_match_key(artist_name=parsed.artist_name, title=parsed.title)
            if key in seen:
                return
            seen.add(key)
            out.append(parsed)

        try:
            payload = self._call("album.search", album=text, limit=safe_limit)
            for row in _extract_album_search_rows(payload):
                _add(_album_search_row(row))
        except LastfmError as exc:
            logger.warning("Last.fm album.search failed for %r: %s", text, exc)

        if len(out) < safe_limit:
            try:
                artist_payload = self._call("artist.search", artist=text, limit=8)
                for artist_row in _extract_artist_search_rows(artist_payload):
                    name = str(artist_row.get("name") or "").strip()
                    if not name or not _artist_name_matches_query(name, text):
                        continue
                    top_payload = self._call(
                        "artist.gettopalbums",
                        artist=name,
                        limit=min(20, safe_limit),
                    )
                    for album_row in _extract_top_album_rows(top_payload):
                        _add(_top_album_row(album_row, artist_name=name))
                    break
            except LastfmError as exc:
                logger.warning("Last.fm artist search/top albums failed for %r: %s", text, exc)

        return out[:safe_limit]

    def fetch_album(
        self,
        *,
        artist_name: str,
        album_title: str,
        release_group_mbid: str | None = None,
    ) -> LfmAlbumDetail:
        artist = (artist_name or "").strip()
        album = (album_title or "").strip()
        if not artist or not album:
            raise LastfmError("artist and album are required for album.getInfo.")
        params: dict[str, str] = {"artist": artist, "album": album}
        mbid = normalize_mbid(release_group_mbid or "")
        if mbid:
            params["mbid"] = mbid
        payload = self._call("album.getinfo", **params)
        album_payload = payload.get("album")
        if not isinstance(album_payload, dict):
            raise LastfmError("Last.fm album.getInfo returned no album.")
        return _album_detail_from_payload(album_payload)

    def fetch_artist(
        self,
        *,
        artist_name: str | None = None,
        artist_mbid: str | None = None,
    ) -> LfmArtistDetail:
        name = (artist_name or "").strip()
        mbid = normalize_mbid(artist_mbid or "")
        if not name and not mbid:
            raise LastfmError("artist name or MBID is required for artist.getInfo.")
        params: dict[str, str] = {}
        if mbid:
            params["mbid"] = mbid
        if name:
            params["artist"] = name
        payload = self._call("artist.getinfo", **params)
        artist_payload = payload.get("artist")
        if not isinstance(artist_payload, dict):
            raise LastfmError("Last.fm artist.getInfo returned no artist.")
        return _artist_detail_from_payload(artist_payload)

    def fetch_top_albums_for_artist(
        self,
        *,
        artist_name: str,
        limit: int = 48,
    ) -> list[LfmAlbumSearchResult]:
        name = (artist_name or "").strip()
        if not name:
            return []
        safe_limit = max(1, min(limit, 50))
        payload = self._call("artist.gettopalbums", artist=name, limit=safe_limit)
        out: list[LfmAlbumSearchResult] = []
        for row in _extract_top_album_rows(payload):
            parsed = _top_album_row(row, artist_name=name)
            if parsed is not None:
                out.append(parsed)
        return out

    def fetch_tag_top_albums(self, *, tag: str, limit: int = 25) -> list[LfmAlbumSearchResult]:
        tag_name = (tag or _DEFAULT_HOME_TAG).strip() or _DEFAULT_HOME_TAG
        safe_limit = max(1, min(limit, 50))
        payload = self._call("tag.gettopalbums", tag=tag_name, limit=safe_limit)
        out: list[LfmAlbumSearchResult] = []
        for row in _extract_tag_top_album_rows(payload):
            parsed = _tag_top_album_row(row)
            if parsed is not None:
                out.append(parsed)
        return out

    def _call(self, method: str, **params: str | int) -> dict[str, Any]:
        query: dict[str, str] = {
            "method": method,
            "api_key": self._api_key,
            "format": "json",
        }
        for key, value in params.items():
            query[key] = str(value)
        with self._lock:
            elapsed = time.monotonic() - self._last_request_at
            if elapsed < self._min_interval:
                time.sleep(self._min_interval - elapsed)
            try:
                response = httpx.get(
                    LASTFM_API_BASE,
                    params=query,
                    timeout=self._timeout,
                )
            except httpx.HTTPError as exc:
                raise LastfmError(str(exc)) from exc
            finally:
                self._last_request_at = time.monotonic()

        if response.status_code >= 400:
            raise LastfmError(f"Last.fm HTTP {response.status_code}")
        try:
            data = response.json()
        except ValueError as exc:
            raise LastfmError("Invalid JSON from Last.fm.") from exc
        if not isinstance(data, dict):
            raise LastfmError("Last.fm returned an unexpected payload.")
        if "error" in data:
            message = str(data.get("message") or data.get("error") or "Last.fm error")
            raise LastfmError(message)
        return data


def _fit_lfm_album_key(key: str) -> str:
    """Keep storage keys within external_id varchar(128) (with lfm-album: prefix)."""
    text = (key or "").strip()
    if len(text) <= _LFM_ALBUM_KEY_MAX_LEN:
        return text
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()[:24]
    return f"key-{digest}"


def lastfm_album_external_id(lastfm_id: str) -> str:
    key = _fit_lfm_album_key(str(lastfm_id).strip())
    return f"{LFM_ALBUM_EXTERNAL_PREFIX}{key}"


def parse_lastfm_album_external_id(external_id: str) -> str | None:
    ref = (external_id or "").strip()
    if not ref.startswith(LFM_ALBUM_EXTERNAL_PREFIX):
        return None
    value = ref[len(LFM_ALBUM_EXTERNAL_PREFIX) :].strip()
    return value or None


def parse_lfm_album_key_labels(lastfm_key: str) -> tuple[str | None, str | None]:
    """Decode artist/title from stable keys like path-Artist/Album."""
    key = (lastfm_key or "").strip()
    if not key.startswith("path-"):
        return None, None
    path = unquote(key[5:])
    if "/" not in path:
        return None, None
    artist_part, album_part = path.split("/", 1)
    artist = unquote(artist_part.replace("+", " ")).strip()
    album = unquote(album_part.replace("+", " ")).strip()
    return (artist or None), (album or None)


def is_lastfm_album_external_id(external_id: str) -> bool:
    return parse_lastfm_album_external_id(external_id) is not None


def compact_lfm_artist_storage_id(*, artist_name: str, artist_mbid: str | None = None) -> str:
    """32-char key for FollowedArtist.discogs_artist_id (MBID or name hash)."""
    mb = normalize_mbid(artist_mbid or "")
    if mb:
        return compact_mbid(mb)
    digest = hashlib.sha256((artist_name or "").strip().casefold().encode("utf-8")).hexdigest()
    return digest[:32]


def lfm_artist_person_id(*, artist_name: str, artist_mbid: str | None = None) -> str:
    mb = normalize_mbid(artist_mbid or "")
    if mb:
        return f"{LFM_ARTIST_PERSON_PREFIX}{mb}"
    name = (artist_name or "").strip()
    if not name:
        raise ValueError("artist name is required when MBID is missing.")
    return f"{LFM_ARTIST_PERSON_PREFIX}n/{quote(name, safe='')}"


def parse_music_artist_person_id(person_id: str) -> tuple[str | None, str | None]:
    """Return (artist_name, artist_mbid). At least one is set when the id is a music artist."""
    raw = (person_id or "").strip()
    prefixes = (
        LFM_ARTIST_PERSON_PREFIX,
        "lfm-artist-",
        "mb-artist:",
        "mb-artist-",
    )
    key: str | None = None
    for prefix in prefixes:
        if raw.startswith(prefix):
            key = raw[len(prefix) :].strip()
            break
    if not key:
        return None, None
    if key.startswith("n/"):
        return unquote(key[2:]), None
    compact = key.replace("-", "").lower()
    if len(compact) == 32 and all(c in "0123456789abcdef" for c in compact):
        return None, normalize_mbid(key)
    return key, None


def album_match_key(*, artist_name: str, title: str) -> str:
    artist = re.sub(r"\s+", " ", (artist_name or "").strip().casefold())
    album = re.sub(r"\s+", " ", (title or "").strip().casefold())
    return f"{artist}|{album}"


def is_lastfm_placeholder_image(url: str | None) -> bool:
    value = (url or "").strip().casefold()
    if not value:
        return True
    return any(marker in value for marker in _PLACEHOLDER_IMAGE_MARKERS)


def _extract_album_search_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    results = payload.get("results")
    if not isinstance(results, dict):
        return []
    matches = results.get("albummatches")
    if not isinstance(matches, dict):
        return []
    album = matches.get("album")
    if isinstance(album, list):
        return [row for row in album if isinstance(row, dict)]
    if isinstance(album, dict):
        return [album]
    return []


def stable_lfm_album_key(
    *,
    artist_name: str,
    title: str,
    url: str | None = None,
    lastfm_id: str | None = None,
    mbid: str | None = None,
) -> str:
    """Last.fm album.search often leaves `id` empty; build a stable storage key."""
    if (lastfm_id or "").strip():
        return _fit_lfm_album_key(str(lastfm_id).strip())
    mb = normalize_mbid(mbid or "")
    if mb:
        return _fit_lfm_album_key(f"mbid-{mb}")
    raw_url = (url or "").strip()
    if "/music/" in raw_url:
        path = raw_url.split("/music/", 1)[1].strip("/")
        if path:
            digest = hashlib.sha256(
                f"{artist_name.casefold()}\0{path.casefold()}".encode("utf-8"),
            ).hexdigest()[:24]
            return f"ph-{digest}"
    digest = hashlib.sha256(
        f"{artist_name.casefold()}\0{title.casefold()}".encode("utf-8"),
    ).hexdigest()[:20]
    return f"key-{digest}"


def _artist_name_matches_query(artist_name: str, query: str) -> bool:
    artist = re.sub(r"\s+", " ", (artist_name or "").strip().casefold())
    q = re.sub(r"\s+", " ", (query or "").strip().casefold())
    if not artist or not q:
        return False
    return artist == q or artist.startswith(q) or q.startswith(artist)


def _album_search_row(row: dict[str, Any]) -> LfmAlbumSearchResult | None:
    title = str(row.get("name") or "").strip()
    artist = _artist_name_from_row(row)
    if not title or not artist:
        return None
    url = str(row.get("url") or "").strip() or None
    storage_key = stable_lfm_album_key(
        artist_name=artist,
        title=title,
        url=url,
        lastfm_id=str(row.get("id") or "").strip() or None,
        mbid=str(row.get("mbid") or "").strip() or None,
    )
    image_url = _best_image_url(row.get("image"))
    if is_lastfm_placeholder_image(image_url):
        image_url = None
    return LfmAlbumSearchResult(
        lastfm_id=storage_key,
        title=title,
        artist_name=artist,
        image_url=image_url,
        url=url,
    )


def _artist_name_from_row(row: dict[str, Any]) -> str:
    artist = row.get("artist")
    if isinstance(artist, dict):
        return str(artist.get("name") or "").strip()
    return str(artist or "").strip()


def _top_album_row(row: dict[str, Any], *, artist_name: str) -> LfmAlbumSearchResult | None:
    title = str(row.get("name") or "").strip()
    if not title or not artist_name:
        return None
    url = str(row.get("url") or "").strip() or None
    storage_key = stable_lfm_album_key(
        artist_name=artist_name,
        title=title,
        url=url,
        lastfm_id=str(row.get("id") or "").strip() or None,
        mbid=str(row.get("mbid") or "").strip() or None,
    )
    image_url = _best_image_url(row.get("image"))
    if is_lastfm_placeholder_image(image_url):
        image_url = None
    return LfmAlbumSearchResult(
        lastfm_id=storage_key,
        title=title,
        artist_name=artist_name,
        image_url=image_url,
        url=url,
    )


def _extract_artist_search_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    results = payload.get("results")
    if not isinstance(results, dict):
        return []
    matches = results.get("artistmatches")
    if not isinstance(matches, dict):
        return []
    artist = matches.get("artist")
    if isinstance(artist, list):
        return [row for row in artist if isinstance(row, dict)]
    if isinstance(artist, dict):
        return [artist]
    return []


def _extract_tag_top_album_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    albums = payload.get("albums")
    if not isinstance(albums, dict):
        return []
    album = albums.get("album")
    if isinstance(album, list):
        return [row for row in album if isinstance(row, dict)]
    if isinstance(album, dict):
        return [album]
    return []


def _tag_top_album_row(row: dict[str, Any]) -> LfmAlbumSearchResult | None:
    title = str(row.get("name") or "").strip()
    artist_name = _artist_name_from_row(row)
    if not title or not artist_name:
        return None
    url = str(row.get("url") or "").strip() or None
    storage_key = stable_lfm_album_key(
        artist_name=artist_name,
        title=title,
        url=url,
        lastfm_id=str(row.get("id") or "").strip() or None,
        mbid=str(row.get("mbid") or "").strip() or None,
    )
    image_url = _best_image_url(row.get("image"))
    if is_lastfm_placeholder_image(image_url):
        image_url = None
    return LfmAlbumSearchResult(
        lastfm_id=storage_key,
        title=title,
        artist_name=artist_name,
        image_url=image_url,
        url=url,
    )


def _artist_detail_from_payload(payload: dict[str, Any]) -> LfmArtistDetail:
    name = str(payload.get("name") or "").strip()
    if not name:
        raise LastfmError("Last.fm artist detail is missing a name.")
    url = str(payload.get("url") or "").strip() or None
    mbid_raw = str(payload.get("mbid") or "").strip()
    artist_mbid = normalize_mbid(mbid_raw) if mbid_raw else None
    lastfm_key = compact_lfm_artist_storage_id(artist_name=name, artist_mbid=artist_mbid)
    image_url = _best_image_url(payload.get("image"))
    if is_lastfm_placeholder_image(image_url):
        image_url = None
    tags: list[str] = []
    toptags = payload.get("tags")
    if isinstance(toptags, dict):
        tag_rows = toptags.get("tag")
        if isinstance(tag_rows, dict):
            tag_rows = [tag_rows]
        if isinstance(tag_rows, list):
            for tag in tag_rows:
                if isinstance(tag, dict):
                    tag_name = str(tag.get("name") or "").strip()
                    if tag_name:
                        tags.append(tag_name)
    wiki_summary: str | None = None
    bio = payload.get("bio")
    if isinstance(bio, dict):
        wiki_summary = str(bio.get("summary") or bio.get("content") or "").strip() or None
    stats = payload.get("stats")
    listeners = playcount = None
    if isinstance(stats, dict):
        listeners = _safe_int(stats.get("listeners"))
        playcount = _safe_int(stats.get("playcount"))
    return LfmArtistDetail(
        lastfm_key=lastfm_key,
        name=name,
        image_url=image_url,
        url=url,
        artist_mbid=artist_mbid,
        wiki_summary=wiki_summary,
        tags=tags,
        listeners=listeners,
        playcount=playcount,
    )


def _extract_top_album_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    top = payload.get("topalbums")
    if not isinstance(top, dict):
        return []
    album = top.get("album")
    if isinstance(album, list):
        return [row for row in album if isinstance(row, dict)]
    if isinstance(album, dict):
        return [album]
    return []


def _album_detail_from_payload(payload: dict[str, Any]) -> LfmAlbumDetail:
    title = str(payload.get("name") or "").strip()
    artist_name = str(payload.get("artist") or "").strip()
    if not artist_name:
        artist_block = payload.get("artist")
        if isinstance(artist_block, dict):
            artist_name = str(artist_block.get("name") or "").strip()
    url = str(payload.get("url") or "").strip() or None
    lastfm_id = stable_lfm_album_key(
        artist_name=artist_name,
        title=title,
        url=url,
        lastfm_id=str(payload.get("id") or "").strip() or None,
        mbid=str(payload.get("mbid") or "").strip() or None,
    )
    if not title or not artist_name:
        raise LastfmError("Last.fm album detail is missing title or artist.")

    image_url = _best_image_url(payload.get("image"))
    if is_lastfm_placeholder_image(image_url):
        image_url = None

    mbid_raw = str(payload.get("mbid") or "").strip()
    release_group_mbid = normalize_mbid(mbid_raw) if mbid_raw else None

    tags: list[str] = []
    toptags = payload.get("tags")
    if isinstance(toptags, dict):
        tag_rows = toptags.get("tag")
        if isinstance(tag_rows, dict):
            tag_rows = [tag_rows]
        if isinstance(tag_rows, list):
            for tag in tag_rows:
                if isinstance(tag, dict):
                    name = str(tag.get("name") or "").strip()
                    if name:
                        tags.append(name)

    tracklist = _parse_tracklist(payload.get("tracks"))

    listeners = _safe_int(payload.get("listeners"))
    playcount = _safe_int(payload.get("playcount"))

    wiki_summary: str | None = None
    wiki = payload.get("wiki")
    if isinstance(wiki, dict):
        wiki_summary = str(wiki.get("summary") or wiki.get("content") or "").strip() or None

    return LfmAlbumDetail(
        lastfm_id=lastfm_id,
        title=title,
        artist_name=artist_name,
        image_url=image_url,
        url=url,
        release_group_mbid=release_group_mbid,
        released=str(payload.get("releasedate") or "").strip() or None,
        wiki_summary=wiki_summary,
        tags=tags,
        tracklist=tracklist,
        listeners=listeners,
        playcount=playcount,
    )


def _parse_tracklist(raw: object) -> list[LfmTrackRow]:
    if not isinstance(raw, dict):
        return []
    track_rows = raw.get("track")
    if isinstance(track_rows, dict):
        track_rows = [track_rows]
    if not isinstance(track_rows, list):
        return []
    out: list[LfmTrackRow] = []
    for index, row in enumerate(track_rows, start=1):
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").strip()
        if not name:
            continue
        duration = _safe_int(row.get("duration"))
        attr = row.get("@attr")
        rank = _safe_int(attr.get("rank")) if isinstance(attr, dict) else None
        out.append(
            LfmTrackRow(
                name=name,
                duration_seconds=duration,
                position=rank or index,
            ),
        )
    return out


def _best_image_url(raw: object) -> str | None:
    if not isinstance(raw, list):
        return None
    size_order = ("extralarge", "large", "medium", "small")
    by_size: dict[str, str] = {}
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        size = str(entry.get("size") or "").strip().casefold()
        url = str(entry.get("#text") or entry.get("url") or "").strip()
        if size and url:
            by_size[size] = url
    for size in size_order:
        url = by_size.get(size)
        if url and not is_lastfm_placeholder_image(url):
            return url
    for url in by_size.values():
        if not is_lastfm_placeholder_image(url):
            return url
    return None


def _safe_int(value: object) -> int | None:
    if value is None:
        return None
    try:
        return int(str(value).strip())
    except ValueError:
        return None
