"""Music catalog via Last.fm (albums/artists); Fanart optional for artist photos."""

from __future__ import annotations

import logging
import re
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from ..backend_models import AppUser, MediaItem, TrackingEntry, _utc_now
from ..config import Settings
from ..cover_art_archive_client import CoverArtArchiveClient, CoverArtArchiveError
from ..fanart_client import FanartClient
from ..lastfm_client import (
    LfmAlbumDetail,
    LastfmClient,
    LastfmError,
    LfmAlbumSearchResult,
    album_match_key,
    compact_lfm_artist_storage_id,
    is_lastfm_album_external_id,
    is_lastfm_placeholder_image,
    lastfm_album_external_id,
    lfm_artist_person_id,
    parse_music_artist_person_id,
)
from ..musicbrainz_client import (
    MB_RELEASE_GROUP_EXTERNAL_PREFIX,
    MbReleaseGroupDetail,
    MbReleaseGroupSummary,
    MbReleaseSummary,
    MusicBrainzClient,
    MusicBrainzError,
    compact_mbid,
    is_mb_release_group_external_id,
    mb_release_group_external_id,
    normalize_mbid,
    parse_mb_release_group_external_id,
    parse_mb_release_date,
)
from ..schemas import (
    ApplyBookCatalogLookupRequest,
    ApplyBookCatalogLookupResponse,
    BackendMediaListResponse,
    BackendMediaResponse,
    BookEditFieldsResponse,
    BookEditPatchRequest,
    BookEditSearchResponse,
    BookFieldOptionsResponse,
    MovieCatalogDetailResponse,
    MovieDetailLink,
    MovieDetailMetric,
    MovieDetailPerson,
    MusicHomeResponse,
    MusicReleaseVersionItem,
    MusicReleaseVersionsResponse,
    PersonCatalogDetailResponse,
    PersonFilmographyItem,
)
from ..serializers.backend import serialize_media_item
from ..serializers.catalog import serialize_person_catalog_detail, serialize_videos_from_game_metadata
from ..tmdb_client import TmdbLink
from .catalog_service import lookup_tracking_for_catalog
from .import_pending_service import is_catalog_pending_item

logger = logging.getLogger(__name__)

MUSIC_MEDIA_TYPE = "music"
MUSICBRAINZ_SOURCE = "musicbrainz"
LASTFM_SOURCE = "lastfm"
_MUSIC_SEARCH_LFM_LIMIT = 30
_HOME_CACHE_TTL_SECONDS = 600.0
_HOME_FOLLOWED_ARTIST_LIMIT = 6
_HOME_ARTIST_BROWSE_LIMIT = 40
# Artist page: keep discography modest; avoid CAA calls here (album detail fetches covers).
_ARTIST_DISCOGRAPHY_MAX_ITEMS = 48
_ARTIST_DISCOGRAPHY_CAA_BUDGET = 0
_ARTIST_DETAIL_CACHE_TTL_SECONDS = 600.0
_music_home_popular_cache: tuple[float, BackendMediaListResponse] | None = None
_music_home_latest_cache: dict[str, tuple[float, BackendMediaListResponse]] = {}
_music_artist_detail_cache: dict[str, tuple[float, PersonCatalogDetailResponse]] = {}


def invalidate_music_home_cache(username: str | None = None) -> None:
    global _music_home_popular_cache
    _music_home_popular_cache = None
    key = (username or "").strip().lower()
    if key:
        _music_home_latest_cache.pop(key, None)
    else:
        _music_home_latest_cache.clear()


def _require_lastfm_client(lastfm: LastfmClient | None) -> LastfmClient:
    if lastfm is None:
        raise HTTPException(
            status_code=503,
            detail="Last.fm is not configured. Set LASTFM_API_KEY on the server.",
        )
    return lastfm


def build_musicbrainz_client(settings: Settings) -> MusicBrainzClient:
    return MusicBrainzClient(
        app_name=settings.musicbrainz_app_name,
        contact=settings.musicbrainz_contact,
        timeout_seconds=settings.request_timeout_seconds,
        min_request_interval_seconds=settings.musicbrainz_min_request_interval_seconds,
    )


def build_cover_art_client(settings: Settings, *, mb_client: MusicBrainzClient) -> CoverArtArchiveClient:
    return CoverArtArchiveClient(user_agent=mb_client._user_agent)


def build_fanart_client(settings: Settings) -> FanartClient | None:
    if not settings.fanart_api_key:
        return None
    return FanartClient(
        api_key=settings.fanart_api_key,
        client_key=settings.fanart_client_key,
        timeout_seconds=settings.request_timeout_seconds,
    )


def build_lastfm_client(settings: Settings) -> LastfmClient | None:
    if not settings.lastfm_api_key:
        return None
    return LastfmClient(
        api_key=settings.lastfm_api_key,
        timeout_seconds=settings.request_timeout_seconds,
    )


def _is_release_group_external_id(external_id: str) -> bool:
    return is_mb_release_group_external_id(external_id)


def _cached_thumb_for_release_group(db: Session, release_group_mbid: str) -> str | None:
    return _cached_thumbs_for_release_groups(db, [release_group_mbid]).get(
        normalize_mbid(release_group_mbid),
    )


def _cached_thumbs_for_release_groups(
    db: Session,
    release_group_mbids: list[str],
) -> dict[str, str]:
    normalized = [normalize_mbid(m) for m in release_group_mbids if (m or "").strip()]
    if not normalized:
        return {}
    external_ids = [mb_release_group_external_id(mbid) for mbid in normalized]
    rows = db.scalars(
        select(MediaItem).where(
            MediaItem.source == MUSICBRAINZ_SOURCE,
            MediaItem.media_type == MUSIC_MEDIA_TYPE,
            MediaItem.external_id.in_(external_ids),
        ),
    )
    out: dict[str, str] = {}
    for item in rows:
        image = (item.image_url or "").strip()
        if not image:
            continue
        try:
            _, rg_mbid = parse_mb_release_group_external_id(item.external_id)
        except ValueError:
            continue
        out[rg_mbid] = image
    return out


def _attach_cover_art_front_only(
    caa: CoverArtArchiveClient,
    *,
    release_mbid: str | None,
    release_group_mbid: str | None,
) -> str | None:
    if release_mbid:
        try:
            thumb = caa.front_url_for_release(release_mbid, size="/medium")
            if thumb:
                return thumb
        except CoverArtArchiveError:
            logger.debug("CAA release art failed for %s", release_mbid)
    if release_group_mbid:
        try:
            return caa.front_url_for_release_group(release_group_mbid, size="/medium")
        except CoverArtArchiveError:
            logger.debug("CAA release-group art failed for %s", release_group_mbid)
    return None


def _attach_cover_art(
    caa: CoverArtArchiveClient,
    *,
    release_mbid: str | None,
    release_group_mbid: str | None,
) -> tuple[str | None, list[str]]:
    thumb = _attach_cover_art_front_only(
        caa,
        release_mbid=release_mbid,
        release_group_mbid=release_group_mbid,
    )
    gallery: list[str] = []
    if release_mbid and thumb:
        try:
            gallery = caa.gallery_urls_for_release(release_mbid)
        except CoverArtArchiveError:
            logger.debug("CAA gallery failed for %s", release_mbid)
    return thumb, gallery


def _resolve_thumb_for_release_group(
    db: Session,
    caa: CoverArtArchiveClient,
    group: MbReleaseGroupSummary,
    *,
    include_gallery: bool,
) -> tuple[str | None, list[str]]:
    thumb = _cached_thumb_for_release_group(db, group.mbid) or group.thumb_url
    if thumb:
        return thumb, []
    if include_gallery:
        return _attach_cover_art(
            caa,
            release_mbid=group.primary_release_mbid,
            release_group_mbid=group.mbid,
        )
    return (
        _attach_cover_art_front_only(
            caa,
            release_mbid=group.primary_release_mbid,
            release_group_mbid=group.mbid,
        ),
        [],
    )


def _mb_release_group_payload(
    summary: MbReleaseGroupSummary,
    *,
    gallery_urls: list[str] | None = None,
    extra_payload: dict | None = None,
) -> dict:
    payload = {
        "mbid": summary.mbid,
        "musicbrainzKind": "release-group",
        "releaseGroupMbid": summary.mbid,
        "primaryReleaseMbid": summary.primary_release_mbid,
        "artistName": summary.artist_name,
        "year": summary.year,
        **(summary.metadata or {}),
        **(extra_payload or {}),
    }
    if gallery_urls:
        payload["galleryUrls"] = gallery_urls
    return payload


def _image_url_from_filmography(filmography: list[PersonFilmographyItem]) -> str | None:
    """MusicBrainz has no artist photos; use an album cover from discography when available."""
    for entry in filmography:
        url = (entry.media.imageUrl or "").strip()
        if url:
            return url
    return None


def _artist_image_from_library(db: Session, *, artist_name: str) -> str | None:
    """Reuse a cover already stored for this artist on another album in the library."""
    name = (artist_name or "").strip()
    if not name:
        return None
    item = db.scalar(
        select(MediaItem)
        .where(
            MediaItem.media_type == MUSIC_MEDIA_TYPE,
            MediaItem.subtitle == name,
            MediaItem.image_url.isnot(None),
            MediaItem.image_url != "",
        )
        .order_by(MediaItem.updated_at.desc())
        .limit(1),
    )
    if item is None:
        return None
    return (item.image_url or "").strip() or None


def resolve_artist_display_image_url(
    db: Session,
    *,
    artist_name: str,
    artist_mbid: str | None = None,
    filmography: list[PersonFilmographyItem] | None = None,
    explicit: str | None = None,
    fanart: FanartClient | None = None,
) -> str | None:
    if (explicit or "").strip():
        return explicit.strip()
    if fanart is not None and artist_mbid:
        fanart_url = fanart.artist_thumb_url(artist_mbid)
        if fanart_url:
            return fanart_url
    if filmography:
        from_discography = _image_url_from_filmography(filmography)
        if from_discography:
            return from_discography
    return _artist_image_from_library(db, artist_name=artist_name)


def _payload_field_nonempty(value: object) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (list, dict, tuple, set)):
        return len(value) > 0
    return True


def _merge_mb_release_group_provider_payload(
    existing: dict | None,
    incoming: dict,
) -> dict:
    """Merge browse/light upserts without wiping album detail fetched earlier."""
    base = dict(existing or {})
    merged = {**base, **incoming}
    for key in (
        "artists",
        "tracklist",
        "galleryUrls",
        "genres",
        "styles",
        "description",
        "videos",
    ):
        if not _payload_field_nonempty(incoming.get(key)) and _payload_field_nonempty(base.get(key)):
            merged[key] = base[key]
    if not _payload_field_nonempty(incoming.get("artistName")) and _payload_field_nonempty(
        base.get("artistName"),
    ):
        merged["artistName"] = base["artistName"]
    return merged


def _apply_mb_release_group_fields(
    item: MediaItem,
    summary: MbReleaseGroupSummary,
    *,
    thumb_url: str | None = None,
    gallery_urls: list[str] | None = None,
    extra_payload: dict | None = None,
) -> None:
    payload = _mb_release_group_payload(
        summary,
        gallery_urls=gallery_urls,
        extra_payload=extra_payload,
    )
    image = thumb_url or summary.thumb_url
    item.title = summary.title
    artist_subtitle = (summary.artist_name or "").strip()
    if artist_subtitle:
        item.subtitle = artist_subtitle
    if image:
        item.image_url = image
    item.provider_payload = _merge_mb_release_group_provider_payload(
        item.provider_payload if isinstance(item.provider_payload, dict) else None,
        payload,
    )


def _find_mb_release_group_item(db: Session, summary: MbReleaseGroupSummary) -> MediaItem | None:
    external_id = mb_release_group_external_id(summary.mbid)
    return db.scalar(
        select(MediaItem).where(
            MediaItem.source == MUSICBRAINZ_SOURCE,
            MediaItem.media_type == MUSIC_MEDIA_TYPE,
            MediaItem.external_id == external_id,
        ),
    )


def _existing_mb_release_group_items(
    db: Session,
    release_group_mbids: list[str],
) -> dict[str, MediaItem]:
    normalized = [normalize_mbid(m) for m in release_group_mbids if (m or "").strip()]
    if not normalized:
        return {}
    external_ids = [mb_release_group_external_id(mbid) for mbid in normalized]
    rows = db.scalars(
        select(MediaItem).where(
            MediaItem.source == MUSICBRAINZ_SOURCE,
            MediaItem.media_type == MUSIC_MEDIA_TYPE,
            MediaItem.external_id.in_(external_ids),
        ),
    ).all()
    out: dict[str, MediaItem] = {}
    for item in rows:
        try:
            _, rg_mbid = parse_mb_release_group_external_id(item.external_id)
        except ValueError:
            continue
        out[rg_mbid] = item
    return out


def _serialize_artist_discography_media(
    item: MediaItem | None,
    *,
    thumb_url: str | None,
) -> BackendMediaResponse:
    if item is None:
        raise ValueError("item is required for artist discography media")
    image = (item.image_url or "").strip() or (thumb_url or "").strip() or None
    if image and image != (item.image_url or "").strip():
        base = serialize_media_item(item)
        return base.model_copy(update={"imageUrl": image})
    return serialize_media_item(item)


def upsert_mb_release_group(
    db: Session,
    summary: MbReleaseGroupSummary,
    *,
    thumb_url: str | None = None,
    gallery_urls: list[str] | None = None,
    extra_payload: dict | None = None,
) -> MediaItem:
    """Insert or update by (source, media_type, external_id); safe under concurrent requests."""
    external_id = mb_release_group_external_id(summary.mbid)
    image = thumb_url or summary.thumb_url
    payload = _mb_release_group_payload(
        summary,
        gallery_urls=gallery_urls,
        extra_payload=extra_payload,
    )
    existing = _find_mb_release_group_item(db, summary)
    existing_payload = (
        existing.provider_payload if existing and isinstance(existing.provider_payload, dict) else None
    )
    merged_payload = _merge_mb_release_group_provider_payload(existing_payload, payload)
    artist_subtitle = (summary.artist_name or "").strip()
    if not artist_subtitle and existing is not None:
        artist_subtitle = (existing.subtitle or "").strip()
    subtitle_value = artist_subtitle or None

    now = _utc_now()
    update_set: dict = {
        "title": summary.title,
        "provider_payload": merged_payload,
        "updated_at": now,
    }
    if subtitle_value:
        update_set["subtitle"] = subtitle_value
    if image:
        update_set["image_url"] = image

    stmt = (
        pg_insert(MediaItem)
        .values(
            id=str(uuid4()),
            source=MUSICBRAINZ_SOURCE,
            external_id=external_id,
            media_type=MUSIC_MEDIA_TYPE,
            title=summary.title,
            subtitle=subtitle_value,
            image_url=image,
            provider_payload=merged_payload,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            constraint="uq_catalog_items_source_type_external",
            set_=update_set,
        )
        .returning(MediaItem.id)
    )
    media_id = db.execute(stmt).scalar_one()
    item = db.get(MediaItem, media_id)
    if item is None:
        raise RuntimeError(f"upsert_mb_release_group failed for {external_id}")
    return item


def _lfm_tracklist_payload(detail: LfmAlbumDetail) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for track in detail.tracklist:
        entry: dict[str, object] = {
            "title": track.name,
            "position": track.position,
        }
        if track.duration_seconds is not None:
            entry["duration"] = track.duration_seconds
        rows.append(entry)
    return rows


def _lfm_year_from_released(released: str | None) -> int | None:
    text = (released or "").strip()
    if not text:
        return None
    match = re.search(r"(19|20)\d{2}", text)
    if not match:
        return None
    try:
        return int(match.group(0))
    except ValueError:
        return None


def upsert_lastfm_album(
    db: Session,
    *,
    summary: LfmAlbumSearchResult | LfmAlbumDetail,
    detail: LfmAlbumDetail | None = None,
) -> MediaItem:
    """Persist a Last.fm album stub or enriched detail for browse/search."""
    enriched = detail
    if enriched is None and isinstance(summary, LfmAlbumDetail):
        enriched = summary
    search_row = summary if isinstance(summary, LfmAlbumSearchResult) else None
    if enriched is None and search_row is None:
        raise ValueError("summary must be LfmAlbumSearchResult or LfmAlbumDetail")

    lastfm_id = (
        (search_row.lastfm_id if search_row else enriched.lastfm_id if enriched else "") or ""
    ).strip()
    title = (search_row.title if search_row else enriched.title if enriched else "").strip()
    artist_name = (
        search_row.artist_name if search_row else enriched.artist_name if enriched else ""
    ).strip()
    if not lastfm_id or not title or not artist_name:
        raise ValueError("Last.fm album requires id, title, and artist.")

    external_id = lastfm_album_external_id(lastfm_id)
    image = None
    if search_row and search_row.image_url and not is_lastfm_placeholder_image(search_row.image_url):
        image = search_row.image_url
    if enriched and enriched.image_url and not is_lastfm_placeholder_image(enriched.image_url):
        image = enriched.image_url

    tracklist = _lfm_tracklist_payload(enriched) if enriched else []
    year = _lfm_year_from_released(enriched.released if enriched else None)
    payload: dict[str, object] = {
        "lastfmKind": "album",
        "lastfmAlbumId": lastfm_id,
        "artistName": artist_name,
        "catalogSource": LASTFM_SOURCE,
    }
    if enriched:
        if enriched.url:
            payload["lastfmUrl"] = enriched.url
        if enriched.release_group_mbid:
            payload["releaseGroupMbid"] = enriched.release_group_mbid
        if enriched.tags:
            payload["genres"] = enriched.tags
        if tracklist:
            payload["tracklist"] = tracklist
        if year is not None:
            payload["year"] = year
        if enriched.listeners is not None:
            payload["lastfmListeners"] = enriched.listeners
        if enriched.playcount is not None:
            payload["lastfmPlaycount"] = enriched.playcount
        if enriched.wiki_summary:
            payload["description"] = enriched.wiki_summary
        if enriched.released:
            payload["released"] = enriched.released
    elif search_row and search_row.url:
        payload["lastfmUrl"] = search_row.url

    existing = db.scalar(
        select(MediaItem).where(
            MediaItem.source == LASTFM_SOURCE,
            MediaItem.media_type == MUSIC_MEDIA_TYPE,
            MediaItem.external_id == external_id,
        ),
    )
    now = _utc_now()
    update_set: dict = {
        "title": title,
        "subtitle": artist_name,
        "provider_payload": payload,
        "updated_at": now,
    }
    if image:
        update_set["image_url"] = image

    stmt = (
        pg_insert(MediaItem)
        .values(
            id=str(uuid4()),
            source=LASTFM_SOURCE,
            external_id=external_id,
            media_type=MUSIC_MEDIA_TYPE,
            title=title,
            subtitle=artist_name,
            image_url=image,
            provider_payload=payload,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_update(
            constraint="uq_catalog_items_source_type_external",
            set_=update_set,
        )
        .returning(MediaItem.id)
    )
    media_id = db.execute(stmt).scalar_one()
    item = db.get(MediaItem, media_id)
    if item is None:
        raise RuntimeError(f"upsert_lastfm_album failed for {external_id}")
    return item


def _artist_album_labels_from_item(item: MediaItem) -> tuple[str, str, str | None]:
    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    artist_name = str(meta.get("artistName") or item.subtitle or "").strip()
    album_title = str(item.title or "").strip()
    if not artist_name or not album_title:
        raise HTTPException(
            status_code=400,
            detail="Album is missing artist or title required for Last.fm.",
        )
    rg_hint = str(meta.get("releaseGroupMbid") or "").strip() or None
    if not rg_hint and _is_release_group_external_id(item.external_id):
        _, rg_hint = parse_mb_release_group_external_id(item.external_id)
    return artist_name, album_title, rg_hint


def refresh_music_item_from_lastfm(
    db: Session,
    item: MediaItem,
    detail: LfmAlbumDetail,
) -> MediaItem:
    """Apply Last.fm album.getInfo to an existing library row (keeps media id / tracking)."""
    tracklist = _lfm_tracklist_payload(detail)
    year = _lfm_year_from_released(detail.released)
    payload: dict[str, object] = {
        "lastfmKind": "album",
        "lastfmAlbumId": detail.lastfm_id,
        "artistName": detail.artist_name,
        "catalogSource": LASTFM_SOURCE,
        "tracklist": tracklist,
        "artists": [{"name": detail.artist_name}],
    }
    if detail.url:
        payload["lastfmUrl"] = detail.url
    if detail.release_group_mbid:
        payload["releaseGroupMbid"] = detail.release_group_mbid
    if detail.tags:
        payload["genres"] = detail.tags
    if year is not None:
        payload["year"] = year
    if detail.released:
        payload["released"] = detail.released
    if detail.listeners is not None:
        payload["lastfmListeners"] = detail.listeners
    if detail.playcount is not None:
        payload["lastfmPlaycount"] = detail.playcount
    if detail.wiki_summary:
        payload["description"] = detail.wiki_summary

    image: str | None = None
    if detail.image_url and not is_lastfm_placeholder_image(detail.image_url):
        image = detail.image_url

    item.source = LASTFM_SOURCE
    item.external_id = lastfm_album_external_id(detail.lastfm_id)
    item.title = detail.title
    item.subtitle = detail.artist_name
    item.provider_payload = payload
    item.updated_at = _utc_now()
    if image:
        item.image_url = image
    db.add(item)
    db.flush()
    return item


def upsert_mb_release(db: Session, release: MbReleaseSummary, *, thumb_url: str | None = None) -> MediaItem:
    external_id = mb_release_group_external_id(release.release_group_mbid) if release.release_group_mbid else (
        f"mb-rel:{normalize_mbid(release.mbid)}"
    )
    if release.release_group_mbid:
        return upsert_mb_release_group(
            db,
            MbReleaseGroupSummary(
                mbid=release.release_group_mbid,
                title=release.title,
                artist_name=release.artist_name,
                year=release.year,
                thumb_url=thumb_url or release.thumb_url,
                primary_release_mbid=release.mbid,
                metadata=release.metadata,
            ),
            thumb_url=thumb_url or release.thumb_url,
        )
    item = db.scalar(
        select(MediaItem).where(
            MediaItem.source == MUSICBRAINZ_SOURCE,
            MediaItem.media_type == MUSIC_MEDIA_TYPE,
            MediaItem.external_id == external_id,
        ),
    )
    payload = {
        "mbid": release.mbid,
        "musicbrainzKind": "release",
        "artistName": release.artist_name,
        "year": release.year,
        **(release.metadata or {}),
    }
    if item is None:
        item = MediaItem(
            source=MUSICBRAINZ_SOURCE,
            external_id=external_id,
            media_type=MUSIC_MEDIA_TYPE,
            title=release.title,
            subtitle=release.artist_name,
            image_url=thumb_url or release.thumb_url,
            provider_payload=payload,
        )
        db.add(item)
    else:
        item.title = release.title
        item.subtitle = release.artist_name
        if thumb_url or release.thumb_url:
            item.image_url = thumb_url or release.thumb_url
        merged = dict(item.provider_payload or {})
        merged.update(payload)
        item.provider_payload = merged
    db.flush()
    return item


def _rg_metadata_from_detail(detail: MbReleaseGroupDetail, *, gallery: list[str]) -> dict:
    return {
        **detail.metadata,
        "genres": detail.genres,
        "styles": detail.styles,
        "trackCount": len(detail.tracklist) if detail.tracklist else None,
        "description": detail.description,
        "artists": [
            {"id": a.mbid, "name": a.name, "imageUrl": a.image_url}
            for a in detail.artists
        ],
        "tracklist": [
            {"position": t.position, "title": t.title, "duration": t.duration}
            for t in detail.tracklist
        ],
        "galleryUrls": gallery,
        "videos": [],
    }


def _music_cast_from_metadata(
    meta: dict,
    *,
    db: Session | None = None,
    lastfm: LastfmClient | None = None,
    fanart: FanartClient | None = None,
) -> list[MovieDetailPerson]:
    artists_raw = meta.get("artists")
    cast: list[MovieDetailPerson] = []
    if isinstance(artists_raw, list):
        for row in artists_raw:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name") or "").strip()
            if not name:
                continue
            artist_name_row = name
            raw_id = row.get("id")
            artist_mbid = (
                normalize_mbid(raw_id) if isinstance(raw_id, str) and raw_id.strip() else None
            )
            person_id = lfm_artist_person_id(
                artist_name=artist_name_row,
                artist_mbid=artist_mbid,
            )
            image_url = row.get("imageUrl")
            cast.append(
                MovieDetailPerson(
                    personId=person_id,
                    name=name,
                    role="Artist",
                    imageUrl=image_url.strip()
                    if isinstance(image_url, str) and image_url.strip()
                    else None,
                ),
            )
    if not cast:
        artist_name = str(meta.get("artistName") or "").strip()
        if artist_name:
            cast = [
                MovieDetailPerson(
                    personId=lfm_artist_person_id(artist_name=artist_name),
                    name=artist_name,
                    role="Artist",
                ),
            ]

    if not cast or lastfm is None or db is None:
        return cast

    enriched: list[MovieDetailPerson] = []
    for person in cast:
        if (person.imageUrl or "").strip():
            enriched.append(person)
            continue
        parsed_name, parsed_mbid = parse_music_artist_person_id(person.personId or "")
        lookup_name = (parsed_name or person.name).strip()
        image: str | None = None
        try:
            artist = lastfm.fetch_artist(
                artist_name=lookup_name or None,
                artist_mbid=parsed_mbid,
            )
            image = resolve_artist_display_image_url(
                db,
                artist_name=artist.name,
                artist_mbid=artist.artist_mbid,
                explicit=(artist.image_url or "").strip() or None,
                fanart=fanart,
            )
        except LastfmError:
            image = resolve_artist_display_image_url(
                db,
                artist_name=lookup_name,
                artist_mbid=parsed_mbid,
                fanart=fanart,
            )
        if image:
            enriched.append(
                person.model_copy(update={"imageUrl": image}),
            )
        else:
            enriched.append(person)
    return enriched


def list_catalog_music(
    db: Session,
    client: MusicBrainzClient,
    caa: CoverArtArchiveClient,
    *,
    section: str,
    q: str | None,
    page: int,
    lastfm: LastfmClient | None = None,
) -> BackendMediaListResponse:
    del page  # Album browse search is single-page (Last.fm only).
    del client  # MusicBrainz is not used for catalog search; only popular/home shelves.
    section_norm = (section or "search").strip().lower()
    if section_norm == "search":
        query = (q or "").strip()
        if not query:
            return BackendMediaListResponse(items=[])
        if lastfm is None:
            raise HTTPException(
                status_code=503,
                detail="Last.fm is not configured. Set LASTFM_API_KEY on the server.",
            )
        try:
            lfm_rows = lastfm.search_catalog(query, limit=_MUSIC_SEARCH_LFM_LIMIT)
        except LastfmError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc

        items: list[BackendMediaResponse] = []
        seen_match_keys: set[str] = set()
        for row in lfm_rows:
            match_key = album_match_key(artist_name=row.artist_name, title=row.title)
            if match_key in seen_match_keys:
                continue
            seen_match_keys.add(match_key)
            items.append(
                serialize_media_item(upsert_lastfm_album(db, summary=row)),
            )

        db.commit()
        return BackendMediaListResponse(items=items)

    if section_norm in {"popular", "trending", "hot"}:
        lfm = _require_lastfm_client(lastfm)
        try:
            rows = lfm.fetch_tag_top_albums(tag="rock", limit=25)
        except LastfmError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        items: list[BackendMediaResponse] = []
        seen_keys: set[str] = set()
        for row in rows:
            key = album_match_key(artist_name=row.artist_name, title=row.title)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            items.append(serialize_media_item(upsert_lastfm_album(db, summary=row)))
        db.commit()
        return BackendMediaListResponse(items=items)

    raise HTTPException(status_code=400, detail=f"Unknown music section: {section}")


def get_music_home_popular(
    db: Session,
    lastfm: LastfmClient | None,
    *,
    popular_limit: int = 12,
    home_tag: str = "rock",
) -> BackendMediaListResponse:
    global _music_home_popular_cache
    lfm = _require_lastfm_client(lastfm)
    if _music_home_popular_cache is not None:
        cached_at, cached = _music_home_popular_cache
        if time.monotonic() - cached_at < _HOME_CACHE_TTL_SECONDS:
            return cached

    popular_items: list[BackendMediaResponse] = []
    try:
        rows = lfm.fetch_tag_top_albums(tag=home_tag, limit=popular_limit)
        seen_keys: set[str] = set()
        for row in rows:
            key = album_match_key(artist_name=row.artist_name, title=row.title)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            popular_items.append(serialize_media_item(upsert_lastfm_album(db, summary=row)))
    except LastfmError as exc:
        logger.warning("Last.fm tag top albums failed: %s", exc)

    db.commit()
    response = BackendMediaListResponse(items=popular_items)
    _music_home_popular_cache = (time.monotonic(), response)
    return response


def _serialize_media_with_user_rating(
    item: MediaItem,
    *,
    score: float,
    rated_at: datetime | None,
) -> BackendMediaResponse:
    media = serialize_media_item(item)
    meta = dict(media.metadata) if isinstance(media.metadata, dict) else {}
    meta["userScore"] = score
    if rated_at is not None:
        meta["userRatingRatedAt"] = rated_at.isoformat().replace("+00:00", "Z")
    return media.model_copy(update={"metadata": meta})


def get_music_home_latest(
    db: Session,
    *,
    username: str,
    latest_limit: int = 12,
) -> BackendMediaListResponse:
    """Recent albums the user rated (library tracking), newest first."""
    cache_key = username.strip().lower()
    if cache_key:
        cached = _music_home_latest_cache.get(cache_key)
        if cached is not None and time.monotonic() - cached[0] < _HOME_CACHE_TTL_SECONDS:
            return cached[1]

    latest_items: list[BackendMediaResponse] = []
    user = db.scalar(select(AppUser).where(AppUser.username == username.strip()))
    if user is not None:
        rows = db.execute(
            select(TrackingEntry, MediaItem)
            .join(MediaItem, TrackingEntry.media_item_id == MediaItem.id)
            .where(
                TrackingEntry.user_id == user.id,
                MediaItem.media_type == MUSIC_MEDIA_TYPE,
                TrackingEntry.score.is_not(None),
                TrackingEntry.score > 0,
            )
            .order_by(TrackingEntry.updated_at.desc())
            .limit(max(1, min(latest_limit, 50))),
        ).all()
        for entry, item in rows:
            score = float(entry.score) if entry.score is not None else 0.0
            if score <= 0:
                continue
            latest_items.append(
                _serialize_media_with_user_rating(
                    item,
                    score=score,
                    rated_at=entry.updated_at,
                ),
            )

    response = BackendMediaListResponse(items=latest_items)
    if cache_key:
        _music_home_latest_cache[cache_key] = (time.monotonic(), response)
    return response


def get_music_home(
    db: Session,
    lastfm: LastfmClient | None,
    *,
    username: str,
    popular_limit: int = 12,
    latest_limit: int = 12,
    home_tag: str = "rock",
) -> MusicHomeResponse:
    popular = get_music_home_popular(
        db,
        lastfm,
        popular_limit=popular_limit,
        home_tag=home_tag,
    )
    latest = get_music_home_latest(
        db,
        username=username,
        latest_limit=latest_limit,
    )
    return MusicHomeResponse(popular=popular, latest=latest)


def _is_mb_fetch_ref(external_ref: str) -> bool:
    ref = (external_ref or "").strip()
    return ref.startswith(MB_RELEASE_GROUP_EXTERNAL_PREFIX) or ref.startswith("mb-rel:")


def _music_item_has_cached_detail(item: MediaItem) -> bool:
    if item.media_type != MUSIC_MEDIA_TYPE:
        return False
    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    tracklist = meta.get("tracklist")
    if not isinstance(tracklist, list) or len(tracklist) == 0:
        return False
    has_artist_name = bool(str(meta.get("artistName") or "").strip()) or bool(
        (item.subtitle or "").strip(),
    )
    if item.source == LASTFM_SOURCE or is_lastfm_album_external_id(item.external_id):
        return has_artist_name
    if not _is_release_group_external_id(item.external_id):
        return False
    return bool(item.image_url) and has_artist_name


def get_music_detail(
    db: Session,
    client: MusicBrainzClient,
    caa: CoverArtArchiveClient,
    *,
    media_id: str,
    lastfm: LastfmClient | None = None,
) -> BackendMediaResponse:
    del client, caa  # Album detail is Last.fm-only; MB/CAA not used here.
    item = db.get(MediaItem, media_id)
    if item is not None and item.media_type == MUSIC_MEDIA_TYPE:
        if is_catalog_pending_item(item):
            return serialize_media_item(item)
        if _music_item_has_cached_detail(item):
            return serialize_media_item(item)
    else:
        raise HTTPException(status_code=404, detail="Album not found.")

    if lastfm is None:
        raise HTTPException(
            status_code=503,
            detail="Last.fm is not configured. Set LASTFM_API_KEY on the server.",
        )

    artist_name, album_title, rg_hint = _artist_album_labels_from_item(item)
    try:
        lfm_detail = lastfm.fetch_album(
            artist_name=artist_name,
            album_title=album_title,
            release_group_mbid=rg_hint,
        )
    except LastfmError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    saved = refresh_music_item_from_lastfm(db, item, lfm_detail)
    db.commit()
    return serialize_media_item(saved)


def list_music_release_versions(
    db: Session,
    client: MusicBrainzClient,
    caa: CoverArtArchiveClient,
    *,
    media_id: str,
) -> MusicReleaseVersionsResponse:
    del client, caa  # Last.fm catalog has no release-level versions in Cultur.
    item = db.get(MediaItem, media_id)
    if item is None or item.media_type != MUSIC_MEDIA_TYPE:
        raise HTTPException(status_code=404, detail="Album not found.")
    return MusicReleaseVersionsResponse(items=[])


def get_music_catalog_detail(
    db: Session,
    client: MusicBrainzClient,
    caa: CoverArtArchiveClient,
    *,
    media_id: str,
    username: str | None = None,
    lastfm: LastfmClient | None = None,
    fanart: FanartClient | None = None,
) -> MovieCatalogDetailResponse:
    media = get_music_detail(db, client, caa, media_id=media_id, lastfm=lastfm)
    item = db.get(MediaItem, media.id)
    tracking = lookup_tracking_for_catalog(db, username=username, media_item=item) if item else None

    meta = media.metadata if isinstance(media.metadata, dict) else {}
    genres_raw = meta.get("genres") if isinstance(meta.get("genres"), list) else []
    styles_raw = meta.get("styles") if isinstance(meta.get("styles"), list) else []
    genres = [str(g) for g in genres_raw if str(g).strip()]
    styles = [str(s) for s in styles_raw if str(s).strip()]
    overview = meta.get("description") if isinstance(meta.get("description"), str) else None

    gallery: list[str] = []
    if media.imageUrl and media.imageUrl.strip():
        gallery.append(media.imageUrl.strip())

    facts: list[MovieDetailMetric] = []
    released = meta.get("released")
    if isinstance(released, str) and released.strip():
        facts.append(MovieDetailMetric(label="Released", value=released.strip()))
    else:
        year = meta.get("year")
        if year is not None:
            facts.append(MovieDetailMetric(label="Release", value=str(year)))
    listeners = meta.get("lastfmListeners")
    if listeners is not None:
        facts.append(MovieDetailMetric(label="Listeners", value=str(listeners)))
    playcount = meta.get("lastfmPlaycount")
    if playcount is not None:
        facts.append(MovieDetailMetric(label="Plays", value=str(playcount)))

    links: list[MovieDetailLink] = []
    lfm_url = meta.get("lastfmUrl")
    if isinstance(lfm_url, str) and lfm_url.strip():
        links.append(MovieDetailLink(label="Last.fm", url=lfm_url.strip()))
    else:
        artist = (media.subtitle or "").strip()
        title = (media.title or "").strip()
        if artist and title:
            from urllib.parse import quote

            links.append(
                MovieDetailLink(
                    label="Last.fm",
                    url=f"https://www.last.fm/music/{quote(artist)}/{quote(title)}",
                ),
            )
    rg_mbid = meta.get("releaseGroupMbid")
    if isinstance(rg_mbid, str) and rg_mbid.strip():
        links.append(
            MovieDetailLink(
                label="MusicBrainz",
                url=f"https://musicbrainz.org/release-group/{normalize_mbid(rg_mbid)}",
            ),
        )

    # Skip synchronous "more from artist" shelf — it added 1 MB browse + many CAA calls
    # and made album detail feel stuck loading (MusicBrainz rate limit).
    recommendations: list[BackendMediaResponse] = []

    videos = serialize_videos_from_game_metadata(meta)
    cast = _music_cast_from_metadata(
        meta,
        db=db,
        lastfm=lastfm,
        fanart=fanart,
    )

    return MovieCatalogDetailResponse(
        media=media,
        overview=overview,
        galleryUrls=gallery,
        genres=genres,
        keywords=styles,
        ratings=[],
        facts=facts,
        cast=cast,
        videos=videos,
        links=links,
        recommendations=recommendations,
        tracking=tracking,
    )


def _strip_html_summary(text: str | None) -> str | None:
    if not text:
        return None
    cleaned = re.sub(r"<[^>]+>", "", text)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned or None


def get_lfm_artist_catalog_detail(
    db: Session,
    lastfm: LastfmClient,
    *,
    artist_name: str | None = None,
    artist_mbid: str | None = None,
    person_id: str | None = None,
    fanart: FanartClient | None = None,
) -> PersonCatalogDetailResponse:
    name_hint = (artist_name or "").strip()
    mbid_hint = normalize_mbid(artist_mbid or "") if artist_mbid else None
    if person_id:
        parsed_name, parsed_mbid = parse_music_artist_person_id(person_id)
        name_hint = name_hint or (parsed_name or "").strip()
        mbid_hint = mbid_hint or parsed_mbid
    if not name_hint and not mbid_hint:
        raise HTTPException(status_code=400, detail="Artist name or id is required.")

    cache_key = mbid_hint or name_hint.casefold()
    cached = _music_artist_detail_cache.get(cache_key)
    if cached is not None:
        cached_at, response = cached
        if time.monotonic() - cached_at < _ARTIST_DETAIL_CACHE_TTL_SECONDS:
            return response

    fanart_url: str | None = None
    with ThreadPoolExecutor(max_workers=3) as pool:
        future_artist = pool.submit(
            lastfm.fetch_artist,
            artist_name=name_hint or None,
            artist_mbid=mbid_hint,
        )
        future_fanart = (
            pool.submit(fanart.artist_thumb_url, mbid_hint)
            if fanart is not None and mbid_hint
            else None
        )
        try:
            artist = future_artist.result()
        except LastfmError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        if future_fanart is not None:
            fanart_url = future_fanart.result()
        try:
            album_rows = lastfm.fetch_top_albums_for_artist(
                artist_name=artist.name,
                limit=_ARTIST_DISCOGRAPHY_MAX_ITEMS,
            )
        except LastfmError as exc:
            logger.warning("Last.fm top albums failed for %s: %s", artist.name, exc)
            album_rows = []

    filmography: list[PersonFilmographyItem] = []
    seen_keys: set[str] = set()
    for row in album_rows[:_ARTIST_DISCOGRAPHY_MAX_ITEMS]:
        key = album_match_key(artist_name=row.artist_name, title=row.title)
        if key in seen_keys:
            continue
        seen_keys.add(key)
        item = upsert_lastfm_album(db, summary=row)
        filmography.append(
            PersonFilmographyItem(
                media=serialize_media_item(item),
                role=None,
                mediaType=MUSIC_MEDIA_TYPE,
                creditKind="album",
            ),
        )

    db.commit()

    links: list[TmdbLink] = []
    if artist.url:
        links.append(TmdbLink(label="Last.fm", url=artist.url))
    if artist.artist_mbid:
        links.append(
            TmdbLink(
                label="MusicBrainz",
                url=f"https://musicbrainz.org/artist/{artist.artist_mbid}",
            ),
        )

    resolved_person_id = (person_id or "").strip() or lfm_artist_person_id(
        artist_name=artist.name,
        artist_mbid=artist.artist_mbid,
    )
    artist_image = resolve_artist_display_image_url(
        db,
        artist_name=artist.name,
        artist_mbid=artist.artist_mbid,
        filmography=filmography,
        explicit=(artist.image_url or "").strip() or fanart_url,
        fanart=None,
    )
    response = serialize_person_catalog_detail(
        person_id=resolved_person_id,
        name=artist.name,
        biography=_strip_html_summary(artist.wiki_summary),
        known_for_department="Artist",
        image_url=artist_image,
        gender=None,
        birthday=None,
        place_of_birth=None,
        filmography=filmography,
        popular_filmography=filmography[:12],
        links=links,
    )
    _music_artist_detail_cache[cache_key] = (time.monotonic(), response)
    return response


# Legacy aliases used by catalog router
get_mb_artist_catalog_detail = get_lfm_artist_catalog_detail
get_discogs_artist_catalog_detail = get_lfm_artist_catalog_detail


def build_discogs_client(settings: Settings) -> MusicBrainzClient:
    """Deprecated alias — returns MusicBrainz client."""
    return build_musicbrainz_client(settings)


def _require_music_media_item(db: Session, media_id: str) -> MediaItem:
    item = db.get(MediaItem, media_id)
    if item is None or item.media_type != MUSIC_MEDIA_TYPE:
        raise HTTPException(status_code=404, detail="Album not found.")
    return item


def get_music_edit_fields(db: Session, *, media_id: str) -> BookEditFieldsResponse:
    from ..schemas import BookEditFieldInfo
    from .music_edit_service import list_music_edit_fields

    item = _require_music_media_item(db, media_id)
    rows = list_music_edit_fields(item)
    return BookEditFieldsResponse(
        mediaId=item.id,
        fields=[BookEditFieldInfo.model_validate(row) for row in rows],
    )


def search_music_for_edit(
    lastfm: LastfmClient | None,
    *,
    query: str,
    limit: int = 20,
) -> BookEditSearchResponse:
    from ..schemas import BookEditSearchHit
    from .music_edit_service import search_music_for_edit as _search

    text = (query or "").strip()
    rows = _search(_require_lastfm_client(lastfm), query=text, limit=limit)
    return BookEditSearchResponse(
        query=text,
        results=[BookEditSearchHit.model_validate(row) for row in rows],
    )


def get_music_field_options(
    db: Session,
    lastfm: LastfmClient | None,
    *,
    media_id: str,
    field_key: str,
    lookup_source: str | None = None,
    lookup_external_id: str | None = None,
    search_query: str | None = None,
) -> BookFieldOptionsResponse:
    from ..schemas import BookFieldOption
    from .music_edit_service import get_music_field_options as _field_options

    item = _require_music_media_item(db, media_id)
    payload = _field_options(
        item,
        _require_lastfm_client(lastfm),
        field_key=field_key,
        lookup_source=lookup_source,
        lookup_external_id=lookup_external_id,
        search_query=search_query,
    )
    return BookFieldOptionsResponse(
        field=str(payload["field"]),
        label=str(payload["label"]),
        multiline=bool(payload.get("multiline")),
        currentValue=str(payload.get("currentValue") or ""),
        options=[BookFieldOption.model_validate(row) for row in payload.get("options", [])],
    )


def apply_music_catalog_lookup(
    db: Session,
    lastfm: LastfmClient | None,
    *,
    media_id: str,
    payload: ApplyBookCatalogLookupRequest,
) -> ApplyBookCatalogLookupResponse:
    from .import_pending_service import is_catalog_pending_item
    from .music_edit_service import apply_lastfm_lookup

    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="username is required.")

    item = _require_music_media_item(db, media_id)
    if is_catalog_pending_item(item):
        raise HTTPException(
            status_code=400,
            detail="Use resolve-pending for import placeholders.",
        )

    source = payload.source.strip().lower()
    external_id = payload.externalId.strip()
    if source != LASTFM_SOURCE or not external_id:
        raise HTTPException(
            status_code=400,
            detail="source must be lastfm and externalId is required.",
        )

    lfm = _require_lastfm_client(lastfm)
    item = apply_lastfm_lookup(
        db,
        item,
        lfm,
        lookup_external_id=external_id,
    )
    lookup_tracking_for_catalog(db, username=username, media_item=item)
    _music_artist_detail_cache.clear()
    return ApplyBookCatalogLookupResponse(mediaId=str(item.id))


def patch_music_catalog_edit(
    db: Session,
    lastfm: LastfmClient | None,
    *,
    media_id: str,
    payload: BookEditPatchRequest,
    username: str | None,
) -> MovieCatalogDetailResponse:
    from .music_edit_service import patch_music_catalog_edit as _patch_music

    item = _require_music_media_item(db, media_id)
    lfm = _require_lastfm_client(lastfm)
    item = _patch_music(
        db,
        item,
        fields=dict(payload.fields),
        field_sources=payload.fieldSources,
        metadata_patches=list(payload.metadataPatches),
        lastfm=lfm,
        lookup_source=payload.lookupSource,
        lookup_external_id=payload.lookupExternalId,
    )
    return get_music_catalog_detail(
        db,
        None,
        None,
        media_id=item.id,
        username=username,
        lastfm=lfm,
    )
