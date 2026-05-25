"""User-editable album metadata with Last.fm lookup for field sync."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..backend_models import MediaItem
from ..lastfm_client import (
    LastfmClient,
    LastfmError,
    album_match_key,
    is_lastfm_placeholder_image,
    lastfm_album_external_id,
)
from .music_catalog_service import (
    LASTFM_SOURCE,
    MUSIC_MEDIA_TYPE,
    refresh_music_item_from_lastfm,
)

_PROVIDER_LABELS = {
    "current": "Saved copy",
    "lastfm": "Last.fm",
    "manual": "Custom",
}


@dataclass(frozen=True, slots=True)
class _MusicFieldSpec:
    key: str
    label: str
    column: str | None = None
    metadata_key: str | None = None
    multiline: bool = False


MUSIC_EDITABLE_FIELDS: tuple[_MusicFieldSpec, ...] = (
    _MusicFieldSpec("title", "Title", column="title"),
    _MusicFieldSpec("artist", "Artist", column="subtitle"),
    _MusicFieldSpec("description", "Description", column="description", multiline=True),
    _MusicFieldSpec("imageUrl", "Cover image URL", column="image_url"),
    _MusicFieldSpec("year", "Release year", metadata_key="year"),
    _MusicFieldSpec("genres", "Genres", metadata_key="genres"),
    _MusicFieldSpec("artists", "Artists (linked)", metadata_key="artists"),
    _MusicFieldSpec("musicbrainzUrl", "MusicBrainz link", metadata_key="musicbrainzUri"),
)

_FIELD_BY_KEY = {field.key: field for field in MUSIC_EDITABLE_FIELDS}


def _format_display_value(value: object | None) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        parts = [str(v).strip() for v in value if str(v).strip()]
        return ", ".join(parts)
    if isinstance(value, dict):
        return ""
    return str(value).strip()


def read_music_field_value(item: MediaItem, field_key: str) -> object | None:
    spec = _FIELD_BY_KEY.get(field_key)
    if spec is None:
        raise HTTPException(status_code=400, detail=f"Unknown album field: {field_key}")
    if spec.column == "subtitle":
        return item.subtitle
    if spec.column:
        return getattr(item, spec.column, None)
    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    if spec.metadata_key == "artists":
        artists = meta.get("artists")
        if isinstance(artists, list):
            names = []
            for row in artists:
                if isinstance(row, dict):
                    name = str(row.get("name") or "").strip()
                    if name:
                        names.append(name)
            return ", ".join(names) if names else None
        return None
    return meta.get(spec.metadata_key)


def list_music_edit_fields(item: MediaItem) -> list[dict[str, object]]:
    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    sources = meta.get("userFieldSources")
    field_sources = sources if isinstance(sources, dict) else {}
    rows: list[dict[str, object]] = []
    for spec in MUSIC_EDITABLE_FIELDS:
        value = read_music_field_value(item, spec.key)
        rows.append(
            {
                "key": spec.key,
                "label": spec.label,
                "multiline": spec.multiline,
                "currentValue": _format_display_value(value),
                "source": str(field_sources.get(spec.key) or "current"),
            },
        )
    return rows


def search_music_for_edit(
    lastfm: LastfmClient,
    *,
    query: str,
    limit: int = 20,
) -> list[dict[str, object]]:
    text = (query or "").strip()
    if not text:
        return []
    safe_limit = max(1, min(limit, 30))
    hits: list[dict[str, object]] = []
    seen: set[str] = set()
    try:
        lfm_rows = lastfm.search_albums(text, limit=safe_limit)
    except LastfmError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    for row in lfm_rows:
        key = album_match_key(artist_name=row.artist_name, title=row.title)
        if key in seen:
            continue
        seen.add(key)
        image = row.image_url
        if image and is_lastfm_placeholder_image(image):
            image = None
        hits.append(
            {
                "source": LASTFM_SOURCE,
                "externalId": lastfm_album_external_id(row.lastfm_id),
                "title": row.title,
                "subtitle": row.artist_name,
                "authors": row.artist_name,
                "imageUrl": image,
            },
        )
    return hits[:safe_limit]


def _lfm_album_labels_from_item(item: MediaItem) -> tuple[str, str, str | None]:
    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    artist_name = str(meta.get("artistName") or item.subtitle or "").strip()
    album_title = str(item.title or "").strip()
    rg_hint = str(meta.get("releaseGroupMbid") or "").strip() or None
    return artist_name, album_title, rg_hint


def fetch_lastfm_snapshot(
    lastfm: LastfmClient,
    *,
    lookup_external_id: str,
    artist_name: str | None = None,
    album_title: str | None = None,
) -> dict[str, object]:
    artist = (artist_name or "").strip()
    album = (album_title or "").strip()
    if not artist or not album:
        raise HTTPException(
            status_code=400,
            detail="Artist and album title are required to fetch Last.fm metadata.",
        )
    try:
        detail = lastfm.fetch_album(
            artist_name=artist,
            album_title=album,
            release_group_mbid=None,
        )
    except LastfmError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    year = None
    if detail.released:
        import re

        match = re.search(r"(19|20)\d{2}", detail.released)
        if match:
            year = int(match.group(0))

    meta_patch: dict[str, object] = {
        "lastfmKind": "album",
        "lastfmAlbumId": detail.lastfm_id,
        "artistName": detail.artist_name,
        "catalogSource": LASTFM_SOURCE,
        "genres": detail.tags,
        "description": detail.wiki_summary,
    }
    if detail.url:
        meta_patch["lastfmUrl"] = detail.url
    if detail.release_group_mbid:
        meta_patch["releaseGroupMbid"] = detail.release_group_mbid
        meta_patch["musicbrainzUri"] = (
            f"https://musicbrainz.org/release-group/{detail.release_group_mbid}"
        )
    if year is not None:
        meta_patch["year"] = year
    if detail.released:
        meta_patch["released"] = detail.released
    if detail.tracklist:
        meta_patch["tracklist"] = [
            {"title": t.name, "position": t.position, "duration": t.duration_seconds}
            for t in detail.tracklist
        ]

    return {
        "externalId": lastfm_album_external_id(detail.lastfm_id),
        "title": detail.title,
        "artist": detail.artist_name,
        "description": detail.wiki_summary,
        "imageUrl": detail.image_url,
        "year": year,
        "genres": detail.tags,
        "artists": [{"name": detail.artist_name}],
        "lastfmUrl": detail.url,
        "musicbrainzUrl": meta_patch.get("musicbrainzUri"),
        "metadataPatch": meta_patch,
    }


def _extract_from_snapshot(snapshot: dict[str, object], spec: _MusicFieldSpec) -> object | None:
    if spec.key == "artist":
        return snapshot.get("artist")
    if spec.column == "title":
        return snapshot.get("title")
    if spec.column == "description":
        return snapshot.get("description")
    if spec.column == "image_url":
        return snapshot.get("imageUrl")
    if spec.metadata_key == "year":
        return snapshot.get("year")
    if spec.metadata_key == "genres":
        return snapshot.get("genres")
    if spec.metadata_key == "artists":
        artists = snapshot.get("artists")
        if isinstance(artists, list):
            names = []
            for row in artists:
                if isinstance(row, dict):
                    name = str(row.get("name") or "").strip()
                    if name:
                        names.append(name)
            return ", ".join(names) if names else None
        return None
    if spec.metadata_key == "musicbrainzUri":
        return snapshot.get("musicbrainzUrl")
    return None


def _metadata_patch_for_field(
    spec: _MusicFieldSpec,
    snapshot: dict[str, object],
) -> dict[str, object] | None:
    full = snapshot.get("metadataPatch")
    if isinstance(full, dict):
        return dict(full)
    if spec.metadata_key == "year":
        year = snapshot.get("year")
        return {"year": year} if year is not None else None
    if spec.metadata_key == "genres":
        genres = snapshot.get("genres")
        return {"genres": genres} if isinstance(genres, list) else None
    if spec.metadata_key == "artists":
        artists = snapshot.get("artists")
        return {"artists": artists, "artistName": snapshot.get("artist")} if artists else None
    if spec.metadata_key == "musicbrainzUri":
        url = snapshot.get("musicbrainzUrl")
        return {"musicbrainzUri": url} if isinstance(url, str) and url.strip() else None
    return None


def get_music_field_options(
    item: MediaItem,
    lastfm: LastfmClient,
    *,
    field_key: str,
    lookup_source: str | None = None,
    lookup_external_id: str | None = None,
    search_query: str | None = None,
) -> dict[str, object]:
    spec = _FIELD_BY_KEY.get(field_key)
    if spec is None:
        raise HTTPException(status_code=400, detail=f"Unknown album field: {field_key}")

    current = read_music_field_value(item, field_key)
    options: list[dict[str, object]] = []
    seen_display: set[str] = set()

    def add_option(
        provider: str,
        *,
        value: object | None,
        display_value: str,
        metadata_patch: dict[str, object] | None = None,
        label: str | None = None,
    ) -> None:
        text = display_value.strip()
        if not text:
            return
        lowered = text.casefold()
        if lowered in seen_display:
            return
        seen_display.add(lowered)
        options.append(
            {
                "provider": provider,
                "label": label or _PROVIDER_LABELS.get(provider, provider),
                "displayValue": text,
                "value": value,
                "metadataPatch": metadata_patch,
            },
        )

    current_display = _format_display_value(current)
    if current_display:
        add_option("current", value=current, display_value=current_display)

    snapshots: list[tuple[str, dict[str, object]]] = []
    artist_name, album_title, _rg = _lfm_album_labels_from_item(item)

    if artist_name and album_title:
        try:
            snapshots.append(
                (
                    LASTFM_SOURCE,
                    fetch_lastfm_snapshot(
                        lastfm,
                        lookup_external_id=item.external_id,
                        artist_name=artist_name,
                        album_title=album_title,
                    ),
                ),
            )
        except HTTPException:
            pass

    lookup_src = (lookup_source or "").strip().lower()
    lookup_ext = (lookup_external_id or "").strip()
    if lookup_src == LASTFM_SOURCE and lookup_ext:
        hit_artist = artist_name
        hit_album = album_title
        for hit in search_music_for_edit(lastfm, query=album_title or artist_name, limit=20):
            if str(hit.get("externalId") or "") == lookup_ext:
                hit_artist = str(hit.get("subtitle") or hit_artist)
                hit_album = str(hit.get("title") or hit_album)
                break
        try:
            snapshots.append(
                (
                    f"{LASTFM_SOURCE}:{lookup_ext}",
                    fetch_lastfm_snapshot(
                        lastfm,
                        lookup_external_id=lookup_ext,
                        artist_name=hit_artist,
                        album_title=hit_album,
                    ),
                ),
            )
        except HTTPException:
            pass

    search_text = (search_query or "").strip()
    if search_text:
        for hit in search_music_for_edit(lastfm, query=search_text, limit=8):
            ext = str(hit.get("externalId") or "")
            if not ext:
                continue
            provider = f"{LASTFM_SOURCE}:{ext}"
            if any(provider == p for p, _ in snapshots):
                continue
            try:
                snapshots.append(
                    (
                        provider,
                        fetch_lastfm_snapshot(
                            lastfm,
                            lookup_external_id=ext,
                            artist_name=str(hit.get("subtitle") or ""),
                            album_title=str(hit.get("title") or ""),
                        ),
                    ),
                )
            except HTTPException:
                continue

    for provider, snapshot in snapshots:
        value = _extract_from_snapshot(snapshot, spec)
        display = _format_display_value(value)
        if not display:
            continue
        patch = _metadata_patch_for_field(spec, snapshot)
        short_title = str(snapshot.get("title") or "").strip()
        if len(short_title) > 48:
            short_title = f"{short_title[:45]}…"
        label = (
            f"Last.fm — {short_title}"
            if provider.startswith(LASTFM_SOURCE)
            else _PROVIDER_LABELS[LASTFM_SOURCE]
        )
        add_option(
            provider,
            value=value,
            display_value=display,
            metadata_patch=patch,
            label=label,
        )

    return {
        "field": field_key,
        "label": spec.label,
        "multiline": spec.multiline,
        "currentValue": current_display,
        "options": options,
    }


def apply_music_field_value(
    item: MediaItem,
    meta: dict[str, object],
    spec: _MusicFieldSpec,
    raw_value: Any,
) -> None:
    if spec.column == "subtitle":
        text = str(raw_value or "").strip()
        item.subtitle = text or None
        if text:
            meta["artistName"] = text
        return
    if spec.column:
        if spec.column == "image_url":
            text = str(raw_value or "").strip()
            item.image_url = text or None
            return
        if spec.column == "description":
            text = str(raw_value or "").strip()
            item.description = text or None
            return
        text = str(raw_value or "").strip()
        setattr(item, spec.column, text or None)
        return

    if spec.metadata_key == "genres":
        if raw_value is None:
            meta.pop("genres", None)
            return
        if isinstance(raw_value, list):
            meta["genres"] = [str(v).strip() for v in raw_value if str(v).strip()]
            return
        text = str(raw_value).strip()
        if not text:
            meta.pop("genres", None)
            return
        meta["genres"] = [part.strip() for part in text.split(",") if part.strip()]
        return

    if spec.metadata_key == "artists":
        if raw_value is None:
            meta.pop("artists", None)
            return
        if isinstance(raw_value, list):
            meta["artists"] = raw_value
            return
        text = str(raw_value).strip()
        if not text:
            meta.pop("artists", None)
            return
        meta["artists"] = [{"name": part.strip()} for part in text.split(",") if part.strip()]
        return

    if spec.metadata_key == "year":
        if raw_value is None or str(raw_value).strip() == "":
            meta.pop("year", None)
            return
        try:
            meta["year"] = int(raw_value)
        except (TypeError, ValueError):
            meta["year"] = str(raw_value).strip()
        return

    if spec.metadata_key == "musicbrainzUri":
        text = str(raw_value or "").strip()
        if text:
            meta["musicbrainzUri"] = text
        else:
            meta.pop("musicbrainzUri", None)
        return


def _merge_lfm_provider_payload(existing: dict | None, incoming: dict) -> dict:
    base = dict(existing or {})
    merged = {**base, **incoming}
    for key in ("artists", "tracklist", "genres", "description", "galleryUrls"):
        if not incoming.get(key) and base.get(key):
            merged[key] = base[key]
    return merged


def apply_lastfm_lookup(
    db: Session,
    item: MediaItem,
    lastfm: LastfmClient,
    *,
    lookup_external_id: str,
) -> MediaItem:
    artist_name, album_title, rg_hint = _lfm_album_labels_from_item(item)
    ext = lookup_external_id.strip()
    for hit in search_music_for_edit(lastfm, query=f"{artist_name} {album_title}".strip(), limit=25):
        if str(hit.get("externalId") or "") == ext:
            artist_name = str(hit.get("subtitle") or artist_name)
            album_title = str(hit.get("title") or album_title)
            break
    try:
        detail = lastfm.fetch_album(
            artist_name=artist_name,
            album_title=album_title,
            release_group_mbid=rg_hint,
        )
    except LastfmError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    refresh_music_item_from_lastfm(db, item, detail)
    if detail.wiki_summary:
        item.description = detail.wiki_summary.strip()

    merged_sources = {spec.key: LASTFM_SOURCE for spec in MUSIC_EDITABLE_FIELDS}
    merged = dict(item.provider_payload) if isinstance(item.provider_payload, dict) else {}
    merged["userFieldSources"] = merged_sources
    merged["userEdited"] = True
    item.provider_payload = merged
    db.commit()
    db.refresh(item)
    return item


def patch_music_catalog_edit(
    db: Session,
    item: MediaItem,
    *,
    fields: dict[str, Any],
    field_sources: dict[str, str] | None = None,
    metadata_patches: list[dict[str, object]] | None = None,
    lastfm: LastfmClient | None = None,
    lookup_source: str | None = None,
    lookup_external_id: str | None = None,
) -> MediaItem:
    if item.media_type != MUSIC_MEDIA_TYPE:
        raise HTTPException(status_code=400, detail="Media item is not a music album.")

    if (
        lastfm is not None
        and (lookup_source or "").strip().lower() == LASTFM_SOURCE
        and (lookup_external_id or "").strip()
    ):
        item = apply_lastfm_lookup(
            db,
            item,
            lastfm,
            lookup_external_id=str(lookup_external_id),
        )

    meta = dict(item.provider_payload) if isinstance(item.provider_payload, dict) else {}

    for patch in metadata_patches or []:
        if isinstance(patch, dict):
            meta = _merge_lfm_provider_payload(meta, patch)

    for raw_key, raw_value in fields.items():
        spec = _FIELD_BY_KEY.get(raw_key)
        if spec is None:
            continue
        apply_music_field_value(item, meta, spec, raw_value)

    if field_sources:
        existing_sources = meta.get("userFieldSources")
        merged_sources = dict(existing_sources) if isinstance(existing_sources, dict) else {}
        merged_sources.update(field_sources)
        meta["userFieldSources"] = merged_sources

    meta["userEdited"] = True
    item.provider_payload = meta
    db.commit()
    db.refresh(item)
    return item
