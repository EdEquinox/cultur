"""MusicBrainz WS/2 API client for music catalog (release groups, releases, artists)."""

from __future__ import annotations

import contextlib
import logging
import re
import socket
import threading
import time
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from typing import Any
import httpx

logger = logging.getLogger(__name__)

MUSICBRAINZ_API_BASE = "https://musicbrainz.org/ws/2"
_REQUEST_RETRIES = 4
_RETRYABLE_HTTP_STATUS = {429, 500, 502, 503, 504}
MB_RELEASE_GROUP_EXTERNAL_PREFIX = "mb-rg:"
MB_RELEASE_EXTERNAL_PREFIX = "mb-rel:"
MB_ARTIST_PERSON_PREFIX = "mb-artist:"


class MusicBrainzError(RuntimeError):
    pass


@dataclass(slots=True)
class MbArtistSummary:
    mbid: str
    name: str
    image_url: str | None = None


@dataclass(slots=True)
class MbArtistDetail(MbArtistSummary):
    profile: str | None = None
    urls: list[str] = field(default_factory=list)
    country: str | None = None


@dataclass(slots=True)
class MbTrackRow:
    position: str | None
    title: str
    duration: str | None = None


@dataclass(slots=True)
class MbReleaseSummary:
    mbid: str
    title: str
    artist_name: str | None = None
    year: int | None = None
    released: str | None = None
    release_date: date | None = None
    thumb_url: str | None = None
    format_types: list[str] = field(default_factory=list)
    country: str | None = None
    label: str | None = None
    release_group_mbid: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class MbReleaseGroupSummary:
    mbid: str
    title: str
    artist_name: str | None = None
    year: int | None = None
    thumb_url: str | None = None
    primary_release_mbid: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class MbReleaseGroupDetail(MbReleaseGroupSummary):
    genres: list[str] = field(default_factory=list)
    styles: list[str] = field(default_factory=list)
    tracklist: list[MbTrackRow] = field(default_factory=list)
    gallery_urls: list[str] = field(default_factory=list)
    artists: list[MbArtistSummary] = field(default_factory=list)
    description: str | None = None


@dataclass(slots=True)
class MbReleaseDetail(MbReleaseSummary):
    artists: list[MbArtistSummary] = field(default_factory=list)
    genres: list[str] = field(default_factory=list)
    styles: list[str] = field(default_factory=list)
    tracklist: list[MbTrackRow] = field(default_factory=list)
    gallery_urls: list[str] = field(default_factory=list)
    track_count: int | None = None
    description: str | None = None


@dataclass(slots=True)
class MbReleaseVersion:
    mbid: str
    title: str
    format_label: str | None = None
    country: str | None = None
    released: str | None = None
    label: str | None = None
    thumb_url: str | None = None
    catno: str | None = None


def compact_mbid(mbid: str) -> str:
    return (mbid or "").strip().replace("-", "").lower()


def normalize_mbid(mbid: str) -> str:
    text = (mbid or "").strip().lower()
    if len(text) == 32 and "-" not in text:
        return f"{text[0:8]}-{text[8:12]}-{text[12:16]}-{text[16:20]}-{text[20:32]}"
    return text


def mb_release_group_external_id(mbid: str) -> str:
    return f"{MB_RELEASE_GROUP_EXTERNAL_PREFIX}{normalize_mbid(mbid)}"


def mb_release_external_id(mbid: str) -> str:
    return f"{MB_RELEASE_EXTERNAL_PREFIX}{normalize_mbid(mbid)}"


def parse_mb_release_group_external_id(external_id: str) -> tuple[str, str]:
    raw = (external_id or "").strip()
    if not raw.startswith(MB_RELEASE_GROUP_EXTERNAL_PREFIX):
        raise ValueError(f"Not a MusicBrainz release-group external id: {external_id!r}")
    mbid = normalize_mbid(raw.removeprefix(MB_RELEASE_GROUP_EXTERNAL_PREFIX))
    return MB_RELEASE_GROUP_EXTERNAL_PREFIX, mbid


def parse_mb_release_external_id(external_id: str) -> tuple[str, str]:
    raw = (external_id or "").strip()
    if not raw.startswith(MB_RELEASE_EXTERNAL_PREFIX):
        raise ValueError(f"Not a MusicBrainz release external id: {external_id!r}")
    mbid = normalize_mbid(raw.removeprefix(MB_RELEASE_EXTERNAL_PREFIX))
    return MB_RELEASE_EXTERNAL_PREFIX, mbid


def is_mb_release_group_external_id(external_id: str) -> bool:
    return (external_id or "").strip().startswith(MB_RELEASE_GROUP_EXTERNAL_PREFIX)


def is_mb_release_external_id(external_id: str) -> bool:
    return (external_id or "").strip().startswith(MB_RELEASE_EXTERNAL_PREFIX)


def mb_artist_person_id(mbid: str) -> str:
    return f"{MB_ARTIST_PERSON_PREFIX}{normalize_mbid(mbid)}"


def parse_mb_artist_person_id(person_id: str) -> str | None:
    raw = (person_id or "").strip()
    if not raw.startswith(MB_ARTIST_PERSON_PREFIX):
        return None
    return normalize_mbid(raw.removeprefix(MB_ARTIST_PERSON_PREFIX))


def parse_mb_release_date(raw: object) -> date | None:
    if raw is None:
        return None
    if isinstance(raw, int):
        return date(raw, 1, 1) if 1900 <= raw <= 2100 else None
    text = str(raw).strip()
    if not text:
        return None
    if re.fullmatch(r"\d{4}", text):
        return date(int(text), 1, 1)
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        return parsed.date()
    except ValueError:
        return None


def _year_from_date(value: date | None) -> int | None:
    return value.year if value is not None else None


def _escape_lucene(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


@contextlib.contextmanager
def _prefer_ipv4_dns():
    """Avoid broken IPv6 routes in some Docker networks."""
    original = socket.getaddrinfo

    def _getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
        if family in (0, socket.AF_UNSPEC):
            family = socket.AF_INET
        return original(host, port, family, type, proto, flags)

    socket.getaddrinfo = _getaddrinfo
    try:
        yield
    finally:
        socket.getaddrinfo = original


def _is_retryable_mb_error(exc: MusicBrainzError) -> bool:
    message = str(exc).lower()
    return any(
        token in message
        for token in (
            "ssl",
            "eof",
            "timed out",
            "timeout",
            "connection",
            "temporarily unavailable",
            "rate-limiting",
            "http 429",
            "http 500",
            "http 502",
            "http 503",
            "http 504",
        )
    )


class MusicBrainzClient:
    def __init__(
        self,
        *,
        app_name: str,
        contact: str,
        timeout_seconds: float = 20.0,
        min_request_interval_seconds: float = 1.1,
    ) -> None:
        name = (app_name or "Cultur").strip()
        contact_info = (contact or "cultur@example.com").strip()
        self._user_agent = f"{name}/1.0 ({contact_info})"
        self._timeout = timeout_seconds
        self._min_interval = max(1.0, min_request_interval_seconds)
        self._lock = threading.Lock()
        self._last_request_at = 0.0
        self._featured_cache_ttl = 6 * 3600.0
        self._featured_cache: tuple[float, list[MbReleaseGroupSummary]] | None = None

    @property
    def enabled(self) -> bool:
        return bool(self._user_agent)

    def search_release_groups(
        self,
        query: str,
        *,
        limit: int = 25,
        offset: int = 0,
    ) -> list[MbReleaseGroupSummary]:
        payload = self._get(
            "/release-group",
            params={
                "query": query.strip(),
                "limit": max(1, min(limit, 100)),
                "offset": max(0, offset),
            },
        )
        rows = payload.get("release-groups")
        if not isinstance(rows, list):
            return []
        return [_release_group_from_search_row(row) for row in rows if isinstance(row, dict)]

    def search_albums(
        self,
        title: str,
        artist: str | None = None,
        *,
        limit: int = 25,
    ) -> list[MbReleaseGroupSummary]:
        """Search album release groups by title and optional artist."""
        title_q = _escape_lucene(title.strip())
        if artist and artist.strip():
            artist_q = _escape_lucene(artist.strip())
            query = f'releasegroup:"{title_q}" AND artist:"{artist_q}"'
        else:
            query = f'releasegroup:"{title_q}"'
        return self.search_release_groups(query, limit=limit)

    def search_albums_query(
        self,
        query: str,
        *,
        limit: int = 25,
    ) -> list[MbReleaseGroupSummary]:
        """Free-text search (browse UI)."""
        return self.search_release_groups(query.strip(), limit=limit)

    def fetch_release_group(self, mbid: str) -> MbReleaseGroupDetail:
        payload = self._get(
            f"/release-group/{normalize_mbid(mbid)}",
            params={"inc": "artist-credits+releases+tags+ratings"},
        )
        return _release_group_detail_from_payload(payload)

    def fetch_release(self, mbid: str) -> MbReleaseDetail:
        payload = self._get(
            f"/release/{normalize_mbid(mbid)}",
            params={"inc": "recordings+artist-credits+labels+release-groups+media"},
        )
        return _release_detail_from_payload(payload)

    def browse_releases_for_release_group(
        self,
        release_group_mbid: str,
        *,
        limit: int = 100,
    ) -> list[MbReleaseVersion]:
        payload = self._get(
            "/release",
            params={
                "release-group": normalize_mbid(release_group_mbid),
                "limit": max(1, min(limit, 100)),
                "inc": "labels+media",
            },
        )
        rows = payload.get("releases")
        if not isinstance(rows, list):
            return []
        out: list[MbReleaseVersion] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            parsed = _version_from_release_row(row)
            if parsed is not None:
                out.append(parsed)
        out.sort(key=lambda v: (v.released or "", v.title), reverse=True)
        return out

    def fetch_artist(self, mbid: str) -> MbArtistDetail:
        payload = self._get(
            f"/artist/{normalize_mbid(mbid)}",
            params={"inc": "url-rels+tags"},
        )
        return _artist_detail_from_payload(payload)

    def browse_release_groups_by_artist(
        self,
        artist_mbid: str,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[MbReleaseGroupSummary]:
        payload = self._get(
            "/release-group",
            params={
                "artist": normalize_mbid(artist_mbid),
                "limit": max(1, min(limit, 100)),
                "offset": max(0, offset),
                "type": "album|ep|single",
            },
        )
        rows = payload.get("release-groups")
        if not isinstance(rows, list):
            return []
        out = [_release_group_from_search_row(row) for row in rows if isinstance(row, dict)]
        out.sort(key=lambda rg: (-(rg.year or 0), rg.title.lower()))
        return out

    def fetch_artist_discography(
        self,
        artist_mbid: str,
        *,
        max_items: int = 200,
    ) -> list[MbReleaseGroupSummary]:
        return self.browse_release_groups_by_artist(
            artist_mbid,
            limit=min(max_items, 100),
        )[:max_items]

    def fetch_featured_release_groups(self, *, limit: int = 12) -> list[MbReleaseGroupSummary]:
        """Recent official albums (proxy for a home 'popular' shelf)."""
        safe_limit = max(1, min(limit, 48))
        now = time.monotonic()
        if self._featured_cache is not None:
            cached_at, cached_rows = self._featured_cache
            if now - cached_at < self._featured_cache_ttl:
                return cached_rows[:safe_limit]

        current_year = datetime.now(tz=UTC).date().year
        query = (
            f'primarytype:album AND status:official AND '
            f'firstreleasedate:[{current_year - 1} TO {current_year}]'
        )
        rows = self.search_release_groups(query, limit=max(safe_limit, 24))
        if not rows:
            rows = self.search_release_groups("primarytype:album AND status:official", limit=safe_limit)
        if not rows:
            raise MusicBrainzError("MusicBrainz returned no featured release groups.")

        self._featured_cache = (now, rows)
        return rows[:safe_limit]

    def _get(self, path: str, *, params: dict[str, Any] | None = None) -> dict[str, Any]:
        last_error: MusicBrainzError | None = None
        for attempt in range(_REQUEST_RETRIES):
            try:
                return self._get_once(path, params=params)
            except MusicBrainzError as exc:
                last_error = exc
                if not _is_retryable_mb_error(exc) or attempt + 1 >= _REQUEST_RETRIES:
                    raise
                logger.warning(
                    "MusicBrainz request retry %s/%s for %s: %s",
                    attempt + 1,
                    _REQUEST_RETRIES,
                    path,
                    exc,
                )
                time.sleep(1.5 * (attempt + 1))
        if last_error is not None:
            raise last_error
        raise MusicBrainzError("MusicBrainz request failed.")

    def _get_once(self, path: str, *, params: dict[str, Any] | None = None) -> dict[str, Any]:
        with self._lock:
            elapsed = time.monotonic() - self._last_request_at
            if elapsed < self._min_interval:
                time.sleep(self._min_interval - elapsed)

            url = f"{MUSICBRAINZ_API_BASE}{path}"
            query = dict(params or {})
            query.setdefault("fmt", "json")
            headers = {
                "User-Agent": self._user_agent,
                "Accept": "application/json",
            }
            try:
                with _prefer_ipv4_dns():
                    response = httpx.get(
                        url,
                        params=query,
                        headers=headers,
                        timeout=self._timeout,
                        follow_redirects=True,
                    )
            except httpx.HTTPError as exc:
                raise MusicBrainzError(f"MusicBrainz request failed: {exc}") from exc
            finally:
                self._last_request_at = time.monotonic()

        if response.status_code == 404:
            raise MusicBrainzError("MusicBrainz resource not found.")
        if response.status_code == 503:
            raise MusicBrainzError("MusicBrainz is rate-limiting or unavailable; retry later.")
        if response.status_code in _RETRYABLE_HTTP_STATUS:
            raise MusicBrainzError(
                f"MusicBrainz HTTP {response.status_code}: {response.text[:200]}",
            )
        if response.status_code >= 400:
            raise MusicBrainzError(
                f"MusicBrainz HTTP {response.status_code}: {response.text[:200]}",
            )
        try:
            payload = response.json()
        except ValueError as exc:
            raise MusicBrainzError("MusicBrainz returned invalid JSON.") from exc
        if not isinstance(payload, dict):
            raise MusicBrainzError("MusicBrainz returned unexpected payload.")
        return payload


def _artist_credit_name(row: dict[str, Any]) -> str | None:
    credits = row.get("artist-credit")
    if not isinstance(credits, list) or not credits:
        return None
    parts: list[str] = []
    for credit in credits:
        if not isinstance(credit, dict):
            continue
        artist = credit.get("artist")
        if isinstance(artist, dict):
            name = str(artist.get("name") or "").strip()
            if name:
                parts.append(name)
        name = str(credit.get("name") or "").strip()
        if name and name not in parts:
            parts.append(name)
    return ", ".join(parts) if parts else None


def _artist_credits_list(row: dict[str, Any]) -> list[MbArtistSummary]:
    credits = row.get("artist-credit")
    if not isinstance(credits, list):
        return []
    out: list[MbArtistSummary] = []
    seen: set[str] = set()
    for credit in credits:
        if not isinstance(credit, dict):
            continue
        artist = credit.get("artist")
        if not isinstance(artist, dict):
            continue
        mbid = str(artist.get("id") or "").strip()
        name = str(artist.get("name") or "").strip()
        if not mbid or not name or mbid in seen:
            continue
        seen.add(mbid)
        out.append(MbArtistSummary(mbid=normalize_mbid(mbid), name=name))
    return out


def _tags_as_genres(row: dict[str, Any]) -> list[str]:
    tags = row.get("tags")
    if not isinstance(tags, list):
        return []
    scored: list[tuple[int, str]] = []
    for tag in tags:
        if not isinstance(tag, dict):
            continue
        name = str(tag.get("name") or "").strip()
        if not name:
            continue
        count_raw = tag.get("count")
        count = int(count_raw) if isinstance(count_raw, int) else 0
        scored.append((count, name))
    scored.sort(reverse=True)
    return [name for _, name in scored[:8]]


def _release_group_from_search_row(row: dict[str, Any]) -> MbReleaseGroupSummary:
    mbid = normalize_mbid(str(row.get("id") or ""))
    title = str(row.get("title") or "Unknown album").strip()
    release_date = parse_mb_release_date(row.get("first-release-date"))
    primary_release = row.get("primary-release")
    primary_mbid = None
    if isinstance(primary_release, dict):
        primary_mbid = str(primary_release.get("id") or "").strip() or None
        if primary_mbid:
            primary_mbid = normalize_mbid(primary_mbid)
    return MbReleaseGroupSummary(
        mbid=mbid,
        title=title,
        artist_name=_artist_credit_name(row),
        year=_year_from_date(release_date),
        primary_release_mbid=primary_mbid,
        metadata={
            "primaryType": row.get("primary-type"),
            "secondaryTypes": row.get("secondary-types"),
            "musicbrainzUri": f"https://musicbrainz.org/release-group/{mbid}",
        },
    )


def _pick_primary_release_mbid(rg_payload: dict[str, Any]) -> str | None:
    releases = rg_payload.get("releases")
    if not isinstance(releases, list) or not releases:
        return None
    candidates: list[tuple[date | None, str]] = []
    for rel in releases:
        if not isinstance(rel, dict):
            continue
        mbid = str(rel.get("id") or "").strip()
        if not mbid:
            continue
        candidates.append((parse_mb_release_date(rel.get("date")), normalize_mbid(mbid)))
    if not candidates:
        return None
    candidates.sort(key=lambda pair: (pair[0] is None, pair[0] or date.max))
    return candidates[0][1]


def _release_group_detail_from_payload(payload: dict[str, Any]) -> MbReleaseGroupDetail:
    summary = _release_group_from_search_row(payload)
    primary_mbid = summary.primary_release_mbid or _pick_primary_release_mbid(payload)
    genres = _tags_as_genres(payload)
    disambig = str(payload.get("disambiguation") or "").strip()
    description = disambig or None
    return MbReleaseGroupDetail(
        mbid=summary.mbid,
        title=summary.title,
        artist_name=summary.artist_name,
        year=summary.year,
        thumb_url=summary.thumb_url,
        primary_release_mbid=primary_mbid,
        metadata=summary.metadata,
        genres=genres,
        artists=_artist_credits_list(payload),
        description=description,
    )


def _format_types_from_media(payload: dict[str, Any]) -> list[str]:
    media_rows = payload.get("media")
    if not isinstance(media_rows, list):
        return []
    formats: list[str] = []
    for media in media_rows:
        if not isinstance(media, dict):
            continue
        fmt = str(media.get("format") or "").strip()
        if fmt and fmt not in formats:
            formats.append(fmt)
    return formats


def _label_from_release(payload: dict[str, Any]) -> str | None:
    labels = payload.get("label-info")
    if not isinstance(labels, list) or not labels:
        return None
    first = labels[0]
    if not isinstance(first, dict):
        return None
    label = first.get("label")
    if isinstance(label, dict):
        return str(label.get("name") or "").strip() or None
    return None


def _catno_from_release(payload: dict[str, Any]) -> str | None:
    labels = payload.get("label-info")
    if not isinstance(labels, list) or not labels:
        return None
    first = labels[0]
    if not isinstance(first, dict):
        return None
    return str(first.get("catalog-number") or "").strip() or None


def _release_summary_from_row(row: dict[str, Any]) -> MbReleaseSummary:
    mbid = normalize_mbid(str(row.get("id") or ""))
    title = str(row.get("title") or "Unknown release").strip()
    release_date = parse_mb_release_date(row.get("date"))
    rg = row.get("release-group")
    rg_mbid = None
    if isinstance(rg, dict):
        rg_mbid = str(rg.get("id") or "").strip() or None
        if rg_mbid:
            rg_mbid = normalize_mbid(rg_mbid)
    return MbReleaseSummary(
        mbid=mbid,
        title=title,
        artist_name=_artist_credit_name(row),
        year=_year_from_date(release_date),
        released=str(row.get("date") or "").strip() or None,
        release_date=release_date,
        format_types=_format_types_from_media(row),
        country=str(row.get("country") or "").strip() or None,
        label=_label_from_release(row),
        release_group_mbid=rg_mbid,
        metadata={
            "musicbrainzUri": f"https://musicbrainz.org/release/{mbid}",
            "status": row.get("status"),
        },
    )


def _tracklist_from_release(payload: dict[str, Any]) -> list[MbTrackRow]:
    media_rows = payload.get("media")
    if not isinstance(media_rows, list):
        return []
    tracks: list[MbTrackRow] = []
    for disc in media_rows:
        if not isinstance(disc, dict):
            continue
        track_rows = disc.get("tracks")
        if not isinstance(track_rows, list):
            continue
        for track in track_rows:
            if not isinstance(track, dict):
                continue
            recording = track.get("recording")
            title = str(track.get("title") or "").strip()
            if not title and isinstance(recording, dict):
                title = str(recording.get("title") or "").strip()
            if not title:
                continue
            length_ms = track.get("length")
            duration = None
            if isinstance(length_ms, int) and length_ms > 0:
                seconds = length_ms // 1000
                duration = f"{seconds // 60}:{seconds % 60:02d}"
            tracks.append(
                MbTrackRow(
                    position=str(track.get("position") or track.get("number") or "").strip() or None,
                    title=title,
                    duration=duration,
                ),
            )
    return tracks


def _release_detail_from_payload(payload: dict[str, Any]) -> MbReleaseDetail:
    summary = _release_summary_from_row(payload)
    genres = _tags_as_genres(payload)
    tracklist = _tracklist_from_release(payload)
    disambig = str(payload.get("disambiguation") or "").strip()
    return MbReleaseDetail(
        mbid=summary.mbid,
        title=summary.title,
        artist_name=summary.artist_name,
        year=summary.year,
        released=summary.released,
        release_date=summary.release_date,
        thumb_url=summary.thumb_url,
        format_types=summary.format_types,
        country=summary.country,
        label=summary.label,
        release_group_mbid=summary.release_group_mbid,
        metadata=summary.metadata,
        artists=_artist_credits_list(payload),
        genres=genres,
        tracklist=tracklist,
        track_count=len(tracklist) if tracklist else None,
        description=disambig or None,
    )


def _version_from_release_row(row: dict[str, Any]) -> MbReleaseVersion | None:
    mbid = str(row.get("id") or "").strip()
    if not mbid:
        return None
    return MbReleaseVersion(
        mbid=normalize_mbid(mbid),
        title=str(row.get("title") or "Release").strip(),
        format_label=", ".join(_format_types_from_media(row)) or None,
        country=str(row.get("country") or "").strip() or None,
        released=str(row.get("date") or "").strip() or None,
        label=_label_from_release(row),
        catno=_catno_from_release(row),
    )


def _artist_detail_from_payload(payload: dict[str, Any]) -> MbArtistDetail:
    mbid = normalize_mbid(str(payload.get("id") or ""))
    name = str(payload.get("name") or "Unknown artist").strip()
    country = str(payload.get("country") or "").strip() or None
    disambig = str(payload.get("disambiguation") or "").strip()
    profile = disambig or None
    urls: list[str] = []
    relations = payload.get("relations")
    if isinstance(relations, list):
        for rel in relations:
            if not isinstance(rel, dict):
                continue
            url_obj = rel.get("url")
            if isinstance(url_obj, dict):
                resource = str(url_obj.get("resource") or "").strip()
                if resource:
                    urls.append(resource)
    return MbArtistDetail(
        mbid=mbid,
        name=name,
        country=country,
        profile=profile,
        urls=urls[:12],
    )
