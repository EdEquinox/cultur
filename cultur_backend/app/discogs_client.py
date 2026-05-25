"""Discogs API client for music catalog (releases, artists, search)."""

from __future__ import annotations

import logging
import re
import threading
import time
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from typing import Any
from urllib.parse import urlencode

import httpx

logger = logging.getLogger(__name__)

DISCOGS_API_BASE = "https://api.discogs.com"
DEFAULT_USER_AGENT = "CulturApp/1.0 +https://github.com/yamtrack"
DISCOGS_MASTER_EXTERNAL_PREFIX = "master-"
DISCOGS_ARTIST_PERSON_PREFIX = "discogs-"


class DiscogsError(RuntimeError):
    pass


@dataclass(slots=True)
class DiscogsArtistSummary:
    discogs_id: int
    name: str
    image_url: str | None = None


@dataclass(slots=True)
class DiscogsArtistDetail(DiscogsArtistSummary):
    profile: str | None = None
    urls: list[str] = field(default_factory=list)
    members: list[DiscogsArtistSummary] = field(default_factory=list)


@dataclass(slots=True)
class DiscogsReleaseSummary:
    discogs_id: int
    title: str
    artist_name: str | None = None
    year: int | None = None
    released: str | None = None
    release_date: date | None = None
    thumb_url: str | None = None
    format_types: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class DiscogsTrackRow:
    position: str | None
    title: str
    duration: str | None = None


@dataclass(slots=True)
class DiscogsMasterSummary:
    discogs_id: int
    title: str
    artist_name: str | None = None
    year: int | None = None
    thumb_url: str | None = None
    main_release_id: int | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class DiscogsMasterDetail(DiscogsMasterSummary):
    genres: list[str] = field(default_factory=list)
    styles: list[str] = field(default_factory=list)
    tracklist: list[DiscogsTrackRow] = field(default_factory=list)
    videos: list[dict[str, str | None]] = field(default_factory=list)
    gallery_urls: list[str] = field(default_factory=list)
    artists: list[DiscogsArtistSummary] = field(default_factory=list)


@dataclass(slots=True)
class DiscogsReleaseVersion:
    discogs_id: int
    title: str
    format_label: str | None = None
    country: str | None = None
    released: str | None = None
    label: str | None = None
    thumb_url: str | None = None
    catno: str | None = None


@dataclass(slots=True)
class DiscogsReleaseDetail(DiscogsReleaseSummary):
    artists: list[DiscogsArtistSummary] = field(default_factory=list)
    genres: list[str] = field(default_factory=list)
    styles: list[str] = field(default_factory=list)
    tracklist: list[DiscogsTrackRow] = field(default_factory=list)
    videos: list[dict[str, str | None]] = field(default_factory=list)
    track_count: int | None = None
    gallery_urls: list[str] = field(default_factory=list)
    community_rating: float | None = None
    label: str | None = None
    country: str | None = None
    description: str | None = None


class DiscogsClient:
    def __init__(
        self,
        *,
        api_key: str | None,
        api_secret: str | None,
        user_agent: str = DEFAULT_USER_AGENT,
        timeout_seconds: float = 20.0,
        min_request_interval_seconds: float = 1.1,
    ) -> None:
        self._api_key = (api_key or "").strip()
        self._api_secret = (api_secret or "").strip()
        self._user_agent = (user_agent or DEFAULT_USER_AGENT).strip()
        self._timeout = timeout_seconds
        self._min_interval = max(0.0, min_request_interval_seconds)
        self._lock = threading.Lock()
        self._last_request_at = 0.0
        self._popular_cache_ttl = 6 * 3600.0
        self._popular_cache: tuple[float, list[DiscogsMasterSummary]] | None = None

    @property
    def enabled(self) -> bool:
        return bool(self._api_key)

    def search_masters(
        self,
        query: str,
        *,
        page: int = 1,
        per_page: int = 25,
    ) -> list[DiscogsMasterSummary]:
        """Search album masters (one row per album, not per pressing)."""
        payload = self._get(
            "/database/search",
            params={
                "q": query.strip(),
                "type": "master",
                "page": max(1, page),
                "per_page": max(1, min(per_page, 100)),
            },
        )
        rows = payload.get("results")
        if not isinstance(rows, list):
            return []
        out: list[DiscogsMasterSummary] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            parsed = _master_from_search_row(row)
            if parsed is not None:
                out.append(parsed)
        return out

    def browse_masters_by_year(
        self,
        year: int,
        *,
        page: int = 1,
        per_page: int = 50,
    ) -> list[DiscogsMasterSummary]:
        """Database search for masters in a release year (ranked by wantlist later)."""
        payload = self._get(
            "/database/search",
            params={
                "q": "a",
                "type": "master",
                "year": str(year),
                "page": max(1, page),
                "per_page": max(1, min(per_page, 100)),
            },
        )
        rows = payload.get("results")
        if not isinstance(rows, list):
            return []
        out: list[DiscogsMasterSummary] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            parsed = _master_from_search_row(row)
            if parsed is not None:
                out.append(parsed)
        return out

    def fetch_weekly_popular_masters(self, *, limit: int = 12) -> list[DiscogsMasterSummary]:
        """Proxy for weekly trending: masters with the most Discogs community wants."""
        safe_limit = max(1, min(limit, 48))
        now = time.monotonic()
        if self._popular_cache is not None:
            cached_at, cached_rows = self._popular_cache
            if now - cached_at < self._popular_cache_ttl:
                return cached_rows[:safe_limit]

        current_year = datetime.now(tz=UTC).date().year
        pool: list[DiscogsMasterSummary] = []
        for year in (current_year, current_year - 1):
            pool.extend(self.browse_masters_by_year(year, per_page=50))

        pool.sort(
            key=lambda master: int(master.metadata.get("communityWant") or 0),
            reverse=True,
        )
        seen: set[int] = set()
        ordered: list[DiscogsMasterSummary] = []
        for master in pool:
            if master.discogs_id in seen:
                continue
            seen.add(master.discogs_id)
            ordered.append(master)
            if len(ordered) >= max(safe_limit, 24):
                break

        if not ordered:
            raise DiscogsError("Discogs returned no popular masters for the current year.")

        self._popular_cache = (now, ordered)
        return ordered[:safe_limit]

    def search_albums(
        self,
        query: str,
        *,
        page: int = 1,
        per_page: int = 25,
    ) -> list[DiscogsMasterSummary | DiscogsReleaseSummary]:
        """Masters (one per album) plus standalone releases with no master on Discogs."""
        masters = self.search_masters(query, page=page, per_page=per_page)
        releases = self.search_releases(query, page=page, per_page=per_page)
        master_ids = {m.discogs_id for m in masters}
        combined: list[DiscogsMasterSummary | DiscogsReleaseSummary] = list(masters)
        for release in releases:
            master_id = release.metadata.get("discogsMasterId")
            if isinstance(master_id, int) and master_id > 0:
                continue
            combined.append(release)
            if len(combined) >= per_page:
                break
        return combined[:per_page]

    def search_releases(
        self,
        query: str,
        *,
        page: int = 1,
        per_page: int = 25,
    ) -> list[DiscogsReleaseSummary]:
        payload = self._get(
            "/database/search",
            params={
                "q": query.strip(),
                "type": "release",
                "page": max(1, page),
                "per_page": max(1, min(per_page, 100)),
            },
        )
        rows = payload.get("results")
        if not isinstance(rows, list):
            return []
        out: list[DiscogsReleaseSummary] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            parsed = _release_from_search_row(row)
            if parsed is not None:
                out.append(parsed)
        return out

    def fetch_master(self, master_id: int | str) -> DiscogsMasterDetail:
        payload = self._get(f"/masters/{int(master_id)}")
        return _master_detail_from_payload(payload)

    def fetch_master_versions(
        self,
        master_id: int | str,
        *,
        page: int = 1,
        per_page: int = 50,
    ) -> list[DiscogsReleaseVersion]:
        payload = self._get(
            f"/masters/{int(master_id)}/versions",
            params={
                "page": max(1, page),
                "per_page": max(1, min(per_page, 100)),
                "sort": "released",
                "sort_order": "desc",
            },
        )
        rows = payload.get("versions")
        if not isinstance(rows, list):
            return []
        out: list[DiscogsReleaseVersion] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            parsed = _version_from_master_versions_row(row)
            if parsed is not None:
                out.append(parsed)
        return out

    def fetch_release(self, release_id: int | str) -> DiscogsReleaseDetail:
        payload = self._get(f"/releases/{int(release_id)}")
        return _release_detail_from_payload(payload)

    def fetch_artist(self, artist_id: int | str) -> DiscogsArtistDetail:
        payload = self._get(f"/artists/{int(artist_id)}")
        return _artist_detail_from_payload(payload, fallback_id=artist_id)

    def fetch_artist_masters_all(
        self,
        artist_id: int | str,
        *,
        max_items: int = 200,
    ) -> list[DiscogsMasterSummary]:
        return [
            row
            for row in self.fetch_artist_discography_all(artist_id, max_items=max_items)
            if isinstance(row, DiscogsMasterSummary)
        ]

    def fetch_artist_discography_all(
        self,
        artist_id: int | str,
        *,
        max_items: int = 500,
    ) -> list[DiscogsMasterSummary | DiscogsReleaseSummary]:
        """Masters plus standalone releases (role Main), paginated like discogs.com."""
        page = 1
        masters_by_id: dict[int, DiscogsMasterSummary] = {}
        standalone: list[DiscogsReleaseSummary] = []
        seen_release_ids: set[int] = set()
        main_release_ids: set[int] = set()

        while len(masters_by_id) + len(standalone) < max_items:
            payload = self._get(
                f"/artists/{int(artist_id)}/releases",
                params={
                    "page": page,
                    "per_page": 100,
                    "sort": "year",
                    "sort_order": "desc",
                },
            )
            rows = payload.get("releases")
            if not isinstance(rows, list) or not rows:
                break

            for row in rows:
                if not isinstance(row, dict):
                    continue
                role = str(row.get("role") or "").strip().lower()
                if role and role != "main":
                    continue

                row_type = str(row.get("type") or "").strip().lower()
                if row_type == "master":
                    parsed = _master_from_artist_row(row)
                    if parsed is not None:
                        masters_by_id[parsed.discogs_id] = parsed
                        if parsed.main_release_id is not None:
                            main_release_ids.add(parsed.main_release_id)
                elif row_type == "release":
                    raw_id = row.get("id")
                    if raw_id is None:
                        continue
                    release_id = int(raw_id)
                    if release_id in seen_release_ids:
                        continue
                    master_id_raw = row.get("master_id")
                    if isinstance(master_id_raw, int) and master_id_raw > 0:
                        if master_id_raw in masters_by_id:
                            continue
                    if release_id in main_release_ids:
                        continue
                    parsed = _release_from_artist_row(row)
                    if parsed is not None:
                        seen_release_ids.add(release_id)
                        standalone.append(parsed)

            pagination = payload.get("pagination")
            total_pages = 1
            if isinstance(pagination, dict):
                pages_raw = pagination.get("pages")
                if isinstance(pages_raw, int) and pages_raw > 0:
                    total_pages = pages_raw
            if page >= total_pages:
                break
            page += 1

        combined: list[DiscogsMasterSummary | DiscogsReleaseSummary] = list(masters_by_id.values())
        combined.extend(standalone)
        combined.sort(
            key=lambda item: (
                -(item.year or 0),
                item.title.lower(),
            ),
        )
        return combined[:max_items]

    def fetch_artist_releases(
        self,
        artist_id: int | str,
        *,
        page: int = 1,
        per_page: int = 50,
    ) -> list[DiscogsReleaseSummary]:
        payload = self._get(
            f"/artists/{int(artist_id)}/releases",
            params={
                "page": max(1, page),
                "per_page": max(1, min(per_page, 100)),
                "sort": "year",
                "sort_order": "desc",
            },
        )
        rows = payload.get("releases")
        if not isinstance(rows, list):
            return []
        out: list[DiscogsReleaseSummary] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            parsed = _release_from_artist_row(row)
            if parsed is not None:
                out.append(parsed)
        return out

    def fetch_artist_masters(
        self,
        artist_id: int | str,
        *,
        page: int = 1,
        per_page: int = 50,
    ) -> list[DiscogsMasterSummary]:
        """Albums only (Discogs ``type: master``), like the artist page on discogs.com."""
        payload = self._get(
            f"/artists/{int(artist_id)}/releases",
            params={
                "page": max(1, page),
                "per_page": max(1, min(per_page, 100)),
                "sort": "year",
                "sort_order": "desc",
            },
        )
        rows = payload.get("releases")
        if not isinstance(rows, list):
            return []
        out: list[DiscogsMasterSummary] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            parsed = _master_from_artist_row(row)
            if parsed is not None:
                out.append(parsed)
        return out

    def _get(self, path: str, *, params: dict[str, Any] | None = None) -> dict[str, Any]:
        if not self.enabled:
            raise DiscogsError("Discogs is not configured. Set DISCOGS_API_KEY on the server.")
        merged: dict[str, Any] = dict(params or {})
        merged["key"] = self._api_key
        if self._api_secret:
            merged["secret"] = self._api_secret
        query = urlencode({k: v for k, v in merged.items() if v is not None})
        url = f"{DISCOGS_API_BASE}{path}"
        if query:
            url = f"{url}?{query}"
        self._throttle()
        headers = {"User-Agent": self._user_agent, "Accept": "application/json"}
        try:
            with httpx.Client(timeout=self._timeout) as client:
                response = client.get(url, headers=headers)
        except httpx.HTTPError as exc:
            raise DiscogsError(f"Discogs request failed: {exc}") from exc
        if response.status_code == 404:
            raise DiscogsError("Discogs resource not found.")
        if response.status_code >= 400:
            raise DiscogsError(f"Discogs HTTP {response.status_code}: {response.text[:200]}")
        data = response.json()
        if not isinstance(data, dict):
            raise DiscogsError("Unexpected Discogs response.")
        return data

    def _throttle(self) -> None:
        if self._min_interval <= 0:
            return
        with self._lock:
            now = time.monotonic()
            wait = self._min_interval - (now - self._last_request_at)
            if wait > 0:
                time.sleep(wait)
            self._last_request_at = time.monotonic()


def parse_discogs_release_date(raw: str | int | None) -> date | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    if re.fullmatch(r"\d{4}", text):
        return date(int(text), 1, 1)
    for fmt in ("%Y-%m-%d", "%Y-%m"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    match = re.search(r"(\d{4})", text)
    if match:
        return date(int(match.group(1)), 1, 1)
    return None


def _first_image(images: Any) -> str | None:
    urls = _gallery_urls(images)
    return urls[0] if urls else None


def _gallery_urls(images: Any) -> list[str]:
    if not isinstance(images, list):
        return []
    urls: list[str] = []
    seen: set[str] = set()
    for row in images:
        if not isinstance(row, dict):
            continue
        for key in ("uri", "resource_url", "uri150"):
            raw = row.get(key)
            if isinstance(raw, str) and raw.strip():
                url = raw.strip()
                if url not in seen:
                    seen.add(url)
                    urls.append(url)
                break
    return urls


def _parse_tracklist(rows: Any) -> list[DiscogsTrackRow]:
    if not isinstance(rows, list):
        return []
    out: list[DiscogsTrackRow] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        if str(row.get("type_") or "").strip().lower() == "heading":
            continue
        title = str(row.get("title") or "").strip()
        if not title:
            continue
        position = row.get("position")
        pos = str(position).strip() if position is not None else None
        duration_raw = row.get("duration")
        duration = str(duration_raw).strip() if duration_raw else None
        out.append(DiscogsTrackRow(position=pos or None, title=title, duration=duration))
    return out


_YOUTUBE_ID_RE = re.compile(
    r"(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/)([A-Za-z0-9_-]{11})",
)


def _youtube_video_id(uri: str) -> str | None:
    text = uri.strip()
    if not text:
        return None
    match = _YOUTUBE_ID_RE.search(text)
    return match.group(1) if match else None


def _format_video_duration(seconds: object) -> str | None:
    if not isinstance(seconds, (int, float)):
        return None
    total = int(seconds)
    if total <= 0:
        return None
    minutes, secs = divmod(total, 60)
    if minutes >= 60:
        hours, minutes = divmod(minutes, 60)
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"


def _parse_discogs_videos(rows: Any, *, limit: int = 10) -> list[dict[str, str | None]]:
    """Discogs release ``videos``: title, uri (YouTube), duration (seconds)."""
    if not isinstance(rows, list):
        return []
    out: list[dict[str, str | None]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        uri = str(row.get("uri") or "").strip()
        video_id = _youtube_video_id(uri)
        if not video_id:
            continue
        title = str(row.get("title") or row.get("description") or "Video").strip()
        if not title:
            continue
        duration_label = _format_video_duration(row.get("duration"))
        out.append(
            {
                "title": title,
                "subtitle": duration_label,
                "imageUrl": f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg",
                "url": f"https://www.youtube.com/watch?v={video_id}",
            },
        )
        if len(out) >= limit:
            break
    return out


def _community_rating(payload: dict[str, Any]) -> float | None:
    community = payload.get("community")
    if not isinstance(community, dict):
        return None
    rating = community.get("rating")
    if not isinstance(rating, dict):
        return None
    avg = rating.get("average")
    if isinstance(avg, (int, float)):
        return float(avg)
    return None


def _artist_line(artists: Any) -> str | None:
    if not isinstance(artists, list) or not artists:
        return None
    names: list[str] = []
    for row in artists:
        if isinstance(row, dict):
            name = str(row.get("name") or "").strip()
            if name:
                names.append(name)
        elif isinstance(row, str) and row.strip():
            names.append(row.strip())
    return ", ".join(names) if names else None


def discogs_master_external_id(master_id: int) -> str:
    return f"{DISCOGS_MASTER_EXTERNAL_PREFIX}{master_id}"


def discogs_artist_person_id(artist_id: int) -> str:
    return f"{DISCOGS_ARTIST_PERSON_PREFIX}{artist_id}"


def parse_discogs_person_id(person_id: str) -> int | None:
    normalized = person_id.strip()
    if not normalized.startswith(DISCOGS_ARTIST_PERSON_PREFIX):
        return None
    try:
        return int(normalized[len(DISCOGS_ARTIST_PERSON_PREFIX) :])
    except ValueError:
        return None


def _artist_detail_from_payload(payload: dict[str, Any], *, fallback_id: int | str) -> DiscogsArtistDetail:
    name = str(payload.get("name") or "Artist").strip()
    members: list[DiscogsArtistSummary] = []
    for row in payload.get("members") or []:
        if not isinstance(row, dict):
            continue
        mid = row.get("id")
        if mid is None:
            continue
        mname = str(row.get("name") or "").strip()
        if not mname:
            continue
        members.append(DiscogsArtistSummary(discogs_id=int(mid), name=mname))
    urls: list[str] = []
    for raw in payload.get("urls") or []:
        if isinstance(raw, str) and raw.strip():
            urls.append(raw.strip())
    profile = str(payload.get("profile") or "").strip() or None
    return DiscogsArtistDetail(
        discogs_id=int(payload.get("id") or fallback_id),
        name=name,
        image_url=_first_image(payload.get("images")),
        profile=profile,
        urls=urls,
        members=members,
    )


def parse_discogs_external_id(external_id: str) -> tuple[str, int]:
    if external_id.startswith(DISCOGS_MASTER_EXTERNAL_PREFIX):
        return "master", int(external_id[len(DISCOGS_MASTER_EXTERNAL_PREFIX) :])
    return "release", int(external_id)


def _strip_title_artist_prefix(title: str, artist_name: str | None) -> str:
    if not artist_name:
        return title
    prefix = f"{artist_name} - "
    if title.startswith(prefix):
        return title[len(prefix) :].strip() or title
    return title


def _artist_name_from_row(row: dict[str, Any]) -> str | None:
    artist_raw = row.get("artist")
    if isinstance(artist_raw, str) and artist_raw.strip():
        return artist_raw.strip()
    return _artist_line(artist_raw)


def _community_counts_from_row(row: dict[str, Any]) -> tuple[int, int]:
    community = row.get("community")
    if not isinstance(community, dict):
        return 0, 0
    want = community.get("want")
    have = community.get("have")
    want_count = int(want) if isinstance(want, int) else 0
    have_count = int(have) if isinstance(have, int) else 0
    return want_count, have_count


def _master_from_search_row(row: dict[str, Any]) -> DiscogsMasterSummary | None:
    if str(row.get("type") or "").strip().lower() != "master":
        return None
    raw_id = row.get("id")
    if raw_id is None:
        return None
    artist_name = _artist_name_from_row(row)
    title = _strip_title_artist_prefix(str(row.get("title") or "").strip(), artist_name)
    if not title:
        return None
    year_raw = row.get("year")
    year = int(year_raw) if isinstance(year_raw, int) else None
    want_count, have_count = _community_counts_from_row(row)
    return DiscogsMasterSummary(
        discogs_id=int(raw_id),
        title=title,
        artist_name=artist_name,
        year=year,
        thumb_url=(str(row.get("thumb") or row.get("cover_image") or "").strip() or None),
        metadata={
            "discogsUri": row.get("uri"),
            "discogsKind": "master",
            "communityWant": want_count,
            "communityHave": have_count,
        },
    )


def _master_from_artist_row(row: dict[str, Any]) -> DiscogsMasterSummary | None:
    if str(row.get("type") or "").strip().lower() != "master":
        return None
    raw_id = row.get("id")
    if raw_id is None:
        return None
    title = str(row.get("title") or "").strip()
    if not title:
        return None
    year_raw = row.get("year")
    year = int(year_raw) if isinstance(year_raw, int) else None
    main_release = row.get("main_release")
    main_release_id = int(main_release) if isinstance(main_release, int) else None
    return DiscogsMasterSummary(
        discogs_id=int(raw_id),
        title=title,
        artist_name=str(row.get("artist") or "").strip() or None,
        year=year,
        thumb_url=(str(row.get("thumb") or "").strip() or None),
        main_release_id=main_release_id,
        metadata={
            "discogsUri": row.get("resource_url"),
            "discogsKind": "master",
            "discogsRole": row.get("role"),
        },
    )


def _version_from_master_versions_row(row: dict[str, Any]) -> DiscogsReleaseVersion | None:
    raw_id = row.get("id")
    if raw_id is None:
        return None
    title = str(row.get("title") or "").strip()
    if not title:
        return None
    fmt = row.get("format")
    format_label = str(fmt).strip() if isinstance(fmt, str) else None
    if format_label is None and isinstance(fmt, list):
        format_label = ", ".join(str(x).strip() for x in fmt if str(x).strip()) or None
    return DiscogsReleaseVersion(
        discogs_id=int(raw_id),
        title=title,
        format_label=format_label,
        country=(str(row.get("country") or "").strip() or None),
        released=(str(row.get("released") or "").strip() or None),
        label=(str(row.get("label") or "").strip() or None),
        thumb_url=(str(row.get("thumb") or "").strip() or None),
        catno=(str(row.get("catno") or "").strip() or None),
    )


def _master_detail_from_payload(payload: dict[str, Any]) -> DiscogsMasterDetail:
    raw_id = payload.get("id")
    if raw_id is None:
        raise DiscogsError("Master id missing.")
    title = str(payload.get("title") or "Untitled").strip()
    year_raw = payload.get("year")
    year = int(year_raw) if isinstance(year_raw, int) else None
    artists: list[DiscogsArtistSummary] = []
    for row in payload.get("artists") or []:
        if not isinstance(row, dict):
            continue
        aid = row.get("id")
        if aid is None:
            continue
        artists.append(
            DiscogsArtistSummary(
                discogs_id=int(aid),
                name=str(row.get("name") or "Artist").strip(),
            ),
        )
    genres = [str(g).strip() for g in (payload.get("genres") or []) if str(g).strip()]
    styles = [str(s).strip() for s in (payload.get("styles") or []) if str(s).strip()]
    tracklist = _parse_tracklist(payload.get("tracklist"))
    main_release = payload.get("main_release")
    main_release_id = int(main_release) if isinstance(main_release, int) else None
    return DiscogsMasterDetail(
        discogs_id=int(raw_id),
        title=title,
        artist_name=_artist_line(payload.get("artists")),
        year=year,
        thumb_url=_first_image(payload.get("images")) or None,
        main_release_id=main_release_id,
        artists=artists,
        genres=genres,
        styles=styles,
        tracklist=tracklist,
        videos=_parse_discogs_videos(payload.get("videos")),
        gallery_urls=_gallery_urls(payload.get("images")),
        metadata={
            "discogsUri": payload.get("uri"),
            "discogsKind": "master",
            "discogsMainReleaseId": main_release_id,
        },
    )


def _release_from_search_row(row: dict[str, Any]) -> DiscogsReleaseSummary | None:
    raw_id = row.get("id")
    if raw_id is None:
        return None
    artist_name = _artist_name_from_row(row)
    title = _strip_title_artist_prefix(str(row.get("title") or "").strip(), artist_name)
    if not title:
        return None
    year_raw = row.get("year")
    year = int(year_raw) if isinstance(year_raw, int) else None
    released = str(row.get("released") or "").strip() or None
    release_date = parse_discogs_release_date(released or year)
    metadata: dict[str, Any] = {"discogsUri": row.get("uri"), "discogsType": row.get("type")}
    master_id_raw = row.get("master_id")
    if isinstance(master_id_raw, int) and master_id_raw > 0:
        metadata["discogsMasterId"] = master_id_raw
    format_label = row.get("format")
    format_types: list[str] = []
    if isinstance(format_label, str) and format_label.strip():
        format_types.append(format_label.strip())
    elif isinstance(format_label, list):
        format_types.extend(str(x).strip() for x in format_label if str(x).strip())
    return DiscogsReleaseSummary(
        discogs_id=int(raw_id),
        title=title,
        artist_name=artist_name,
        year=year,
        released=released,
        release_date=release_date,
        thumb_url=(str(row.get("thumb") or row.get("cover_image") or "").strip() or None),
        format_types=format_types,
        metadata=metadata,
    )


def _release_from_artist_row(row: dict[str, Any]) -> DiscogsReleaseSummary | None:
    if str(row.get("type") or "").strip().lower() != "release":
        return None
    raw_id = row.get("id")
    if raw_id is None:
        return None
    artist_name = str(row.get("artist") or "").strip() or None
    title = _strip_title_artist_prefix(str(row.get("title") or "").strip(), artist_name)
    if not title:
        return None
    year_raw = row.get("year")
    year = int(year_raw) if isinstance(year_raw, int) else None
    released = str(row.get("released") or "").strip() or None
    release_date = parse_discogs_release_date(released or year)
    format_types: list[str] = []
    fmt = row.get("format")
    if isinstance(fmt, str) and fmt.strip():
        format_types.append(fmt.strip())
    elif isinstance(fmt, list):
        format_types.extend(str(x).strip() for x in fmt if str(x).strip())
    metadata: dict[str, Any] = {
        "discogsRole": row.get("role"),
        "discogsType": row.get("type"),
        "discogsUri": row.get("resource_url"),
    }
    master_id_raw = row.get("master_id")
    if isinstance(master_id_raw, int) and master_id_raw > 0:
        metadata["discogsMasterId"] = master_id_raw
    return DiscogsReleaseSummary(
        discogs_id=int(raw_id),
        title=title,
        artist_name=artist_name,
        year=year,
        released=released,
        release_date=release_date,
        thumb_url=(str(row.get("thumb") or "").strip() or None),
        format_types=format_types,
        metadata=metadata,
    )


def _release_detail_from_payload(payload: dict[str, Any]) -> DiscogsReleaseDetail:
    raw_id = payload.get("id")
    if raw_id is None:
        raise DiscogsError("Release id missing.")
    title = str(payload.get("title") or "Untitled").strip()
    year_raw = payload.get("year")
    year = int(year_raw) if isinstance(year_raw, int) else None
    released = str(payload.get("released") or "").strip() or None
    release_date = parse_discogs_release_date(released or year)
    artists: list[DiscogsArtistSummary] = []
    for row in payload.get("artists") or []:
        if not isinstance(row, dict):
            continue
        aid = row.get("id")
        if aid is None:
            continue
        artists.append(
            DiscogsArtistSummary(
                discogs_id=int(aid),
                name=str(row.get("name") or "Artist").strip(),
            ),
        )
    genres = [str(g).strip() for g in (payload.get("genres") or []) if str(g).strip()]
    styles = [str(s).strip() for s in (payload.get("styles") or []) if str(s).strip()]
    tracklist = _parse_tracklist(payload.get("tracklist"))
    track_count = len(tracklist) if tracklist else None
    labels = payload.get("labels")
    label: str | None = None
    if isinstance(labels, list) and labels and isinstance(labels[0], dict):
        label = str(labels[0].get("name") or "").strip() or None
    formats: list[str] = []
    for fmt in payload.get("formats") or []:
        if isinstance(fmt, dict):
            name = str(fmt.get("name") or "").strip()
            if name:
                formats.append(name)
    return DiscogsReleaseDetail(
        discogs_id=int(raw_id),
        title=title,
        artist_name=_artist_line(payload.get("artists")),
        year=year,
        released=released,
        release_date=release_date,
        thumb_url=_first_image(payload.get("images")) or (str(payload.get("thumb") or "").strip() or None),
        format_types=formats,
        artists=artists,
        genres=genres,
        styles=styles,
        tracklist=tracklist,
        videos=_parse_discogs_videos(payload.get("videos")),
        track_count=track_count,
        gallery_urls=_gallery_urls(payload.get("images")),
        community_rating=_community_rating(payload),
        label=label,
        country=(str(payload.get("country") or "").strip() or None),
        description=(str(payload.get("notes") or "").strip() or None),
        metadata={
            "discogsUri": payload.get("uri"),
            "discogsMasterId": payload.get("master_id"),
        },
    )
