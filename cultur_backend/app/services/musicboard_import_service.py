"""Import album library from Musicboard (Last.fm title + artist search)."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import UTC, datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..lastfm_client import LfmAlbumSearchResult, LastfmClient, LastfmError, album_match_key
from ..schemas import (
    BackendTrackingUpsertRequest,
    MusicboardCustomListAssignment,
    MusicboardImportBatchResponse,
    StashImportBatchRequest,
    StashImportEntryPayload,
    StashImportItemError,
)
from . import backend_service
from .import_pending_service import (
    IMPORT_PENDING_MUSICBOARD_SOURCE,
    upsert_pending_import_item,
)
from .music_catalog_service import upsert_lastfm_album

logger = logging.getLogger(__name__)

_FLAG_PREFIX = "[cult.flags]"


@dataclass(slots=True)
class _MergedRow:
    source_file: str
    title: str
    artist: str | None
    image_url: str | None
    flags: set[str]
    score: float | None = None
    review: str | None = None
    completed_at: str | None = None
    custom_list_names: list[str] | None = None


MUSICBOARD_CULTUR_TARGETS = frozenset(
    {
        "skip",
        "later",
        "later_priority",
        "buy",
        "listened",
        "owned",
        "priority",
        "custom_list",
        "rating",
    },
)

MUSICBOARD_CULTUR_TARGET_FLAGS: dict[str, tuple[str, ...]] = {
    "later": ("watchlist",),
    "later_priority": ("watchlist", "priority"),
    "buy": ("buy",),
    "listened": ("watched",),
    "owned": ("collected",),
    "priority": ("priority",),
    "custom_list": (),
    "rating": (),
}


def import_musicboard_batch(
    db: Session,
    payload: StashImportBatchRequest,
    *,
    lastfm_client: LastfmClient,
) -> MusicboardImportBatchResponse:
    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="username is required.")
    merged = _merge_payload_entries(payload.entries)
    return _import_merged_rows(
        db,
        username=username,
        merged=merged,
        lastfm_client=lastfm_client,
    )


def import_musicboard_merged_rows(
    db: Session,
    *,
    username: str,
    merged: dict[str, _MergedRow],
    lastfm_client: LastfmClient,
) -> MusicboardImportBatchResponse:
    return _import_merged_rows(
        db,
        username=username,
        merged=merged,
        lastfm_client=lastfm_client,
    )


def _import_merged_rows(
    db: Session,
    *,
    username: str,
    merged: dict[str, _MergedRow],
    lastfm_client: LastfmClient,
) -> MusicboardImportBatchResponse:
    imported = 0
    pending_count = 0
    skipped = 0
    errors: list[StashImportItemError] = []
    custom_assignments: list[MusicboardCustomListAssignment] = []

    for row in merged.values():
        title = row.title.strip()
        if not title:
            errors.append(
                StashImportItemError(
                    sourceFile=row.source_file,
                    title=title or row.source_file,
                    reason="missing_title",
                    message="Missing album title.",
                ),
            )
            skipped += 1
            continue
        try:
            master = _resolve_musicboard_album(
                lastfm_client,
                title=title,
                artist=row.artist,
            )
        except LastfmError as exc:
            _create_pending_from_row(db, row=row, title=title, username=username)
            errors.append(
                StashImportItemError(
                    sourceFile=row.source_file,
                    title=title,
                    reason="lastfm_error",
                    message=str(exc),
                ),
            )
            pending_count += 1
            continue
        if master is None:
            _create_pending_from_row(db, row=row, title=title, username=username)
            errors.append(
                StashImportItemError(
                    sourceFile=row.source_file,
                    title=title,
                    reason="not_found",
                    message="Saved as pending — link it from the album page.",
                ),
            )
            pending_count += 1
            continue

        media = upsert_lastfm_album(db, summary=master)
        status, notes = _tracking_from_row(row)
        backend_service.upsert_tracking_entry(
            db,
            BackendTrackingUpsertRequest(
                username=username,
                mediaId=str(media.id),
                status=status,
                score=row.score if row.score and row.score > 0 else None,
                notes=notes,
                completedAt=row.completed_at or _iso_now_if(status == "Completed"),
            ),
        )
        for list_name in dict.fromkeys(row.custom_list_names or []):
            custom_assignments.append(
                MusicboardCustomListAssignment(
                    listName=list_name,
                    mediaId=str(media.id),
                    title=media.title,
                    source=media.source,
                    externalId=media.external_id,
                ),
            )
        imported += 1

    db.commit()
    return MusicboardImportBatchResponse(
        imported=imported,
        pending=pending_count,
        skipped=skipped,
        errors=errors,
        customListAssignments=custom_assignments,
    )


def _create_pending_from_row(
    db: Session,
    *,
    row: _MergedRow,
    title: str,
    username: str,
) -> None:
    dedupe = _dedupe_key(title, row.artist, row.image_url)
    media = upsert_pending_import_item(
        db,
        media_type="music",
        source=IMPORT_PENDING_MUSICBOARD_SOURCE,
        dedupe_key=dedupe,
        title=title,
        image_url=row.image_url,
        import_source="musicboard",
        import_meta={
            "musicboardSourceFile": row.source_file,
            **({"artistName": row.artist} if row.artist else {}),
        },
    )
    status, notes = _tracking_from_row(row)
    backend_service.upsert_tracking_entry(
        db,
        BackendTrackingUpsertRequest(
            username=username,
            mediaId=str(media.id),
            status=status,
            score=row.score if row.score and row.score > 0 else None,
            notes=notes,
            completedAt=row.completed_at or _iso_now_if(status == "Completed"),
        ),
    )


def _merge_payload_entries(entries: list[StashImportEntryPayload]) -> dict[str, _MergedRow]:
    merged: dict[str, _MergedRow] = {}
    for entry in entries:
        title = (entry.title or "").strip()
        if not title:
            continue
        artist = (entry.artist or "").strip() or None
        key = _dedupe_key(title, artist, entry.imageUrl)
        flags = {str(f).strip() for f in entry.flags if str(f).strip()}
        score = _normalize_score(entry.score)
        review = (entry.review or "").strip() or None
        completed_at = (entry.completedAt or "").strip() or None
        source = (entry.sourceFile or "").strip() or "musicboard.csv"
        existing = merged.get(key)
        if existing is None:
            merged[key] = _MergedRow(
                source_file=source,
                title=title,
                artist=artist,
                image_url=(entry.imageUrl or "").strip() or None,
                flags=flags,
                score=score,
                review=review,
                completed_at=completed_at,
                custom_list_names=None,
            )
            continue
        existing.flags.update(flags)
        if artist and not existing.artist:
            existing.artist = artist
        if score is not None and (existing.score is None or score > existing.score):
            existing.score = score
        if completed_at and not existing.completed_at:
            existing.completed_at = completed_at
        if review:
            if existing.review and existing.review != review:
                existing.review = f"{existing.review}\n\n{review}"
            else:
                existing.review = review
    return merged


def _normalize_score(value: float | None) -> float | None:
    if value is None or value <= 0:
        return None
    if value <= 5:
        return round(value * 2, 2)
    return value


def _dedupe_key(title: str, artist: str | None, image_url: str | None) -> str:
    if image_url and image_url.strip():
        digest = re.sub(r"\s+", "", image_url.strip().casefold())
        if digest:
            return f"image:{digest[:120]}"
    artist_key = _normalize_title(artist or "")
    title_key = _normalize_title(title)
    if artist_key:
        return f"album:{artist_key}|{title_key}"
    return f"album:{title_key}"


def _resolve_musicboard_album(
    client: LastfmClient,
    *,
    title: str,
    artist: str | None,
) -> LfmAlbumSearchResult | None:
    seen_keys: set[str] = set()
    merged: list[LfmAlbumSearchResult] = []
    for query in _search_query_variants(title, artist):
        try:
            rows = client.search_catalog(query, limit=20)
        except LastfmError:
            continue
        for row in rows:
            key = album_match_key(artist_name=row.artist_name, title=row.title)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            merged.append(row)
    if not merged:
        return None
    return _pick_best_title_match(title, merged, artist=artist)


def _search_query_variants(title: str, artist: str | None) -> list[str]:
    raw = (title or "").strip()
    if not raw:
        return []
    variants: list[str] = []
    seen: set[str] = set()

    def add(value: str) -> None:
        text = value.strip()
        if text and text.casefold() not in seen:
            seen.add(text.casefold())
            variants.append(text)

    if artist:
        add(f"{artist} {raw}")
        add(raw)
    else:
        add(raw)
    for sep in (":", " - ", " – ", " — ", "|"):
        if sep in raw:
            left, right = raw.split(sep, 1)
            add(left)
            add(right)
            if artist:
                add(f"{artist} {left.strip()}")
                add(f"{artist} {right.strip()}")
    no_paren = re.sub(r"\([^)]*\)", "", raw).strip()
    if no_paren:
        add(no_paren)
        if artist:
            add(f"{artist} {no_paren}")
    return variants


def _pick_best_title_match(
    query: str,
    masters: list[LfmAlbumSearchResult],
    *,
    artist: str | None = None,
) -> LfmAlbumSearchResult | None:
    if not masters:
        return None
    want = _normalize_title(query)
    if not want:
        return None

    exact = [m for m in masters if _normalize_title(m.title) == want]
    if len(exact) == 1:
        return exact[0]
    if len(exact) > 1 and artist:
        want_artist = _normalize_title(artist)
        for master in exact:
            if want_artist and _normalize_title(master.artist_name or "") == want_artist:
                return master

    scored: list[tuple[LfmAlbumSearchResult, float]] = []
    for master in masters:
        score = _title_match_score(query, master.title)
        if artist and master.artist_name:
            artist_score = _title_match_score(artist, master.artist_name)
            score = 0.72 * score + 0.28 * artist_score
        if score > 0:
            scored.append((master, score))
    if not scored:
        return masters[0] if len(masters) == 1 else None

    scored.sort(key=lambda pair: (-pair[1], pair[0].title))
    best, best_score = scored[0]
    if best_score >= 0.82:
        return best
    if len(scored) == 1 and best_score >= 0.55:
        return best
    if len(scored) > 1:
        second_score = scored[1][1]
        if best_score >= 0.65 and (best_score - second_score) >= 0.12:
            return best
    return None


def _title_match_score(query: str, candidate: str) -> float:
    want_tokens = set(_normalize_title(query).split())
    cand_tokens = set(_normalize_title(candidate).split())
    if not want_tokens or not cand_tokens:
        return 0.0
    overlap = len(want_tokens & cand_tokens)
    if overlap == 0:
        return 0.0
    coverage = overlap / len(want_tokens)
    precision = overlap / len(cand_tokens)
    return 0.65 * coverage + 0.35 * precision


def _normalize_title(value: str) -> str:
    text = (value or "").strip().casefold()
    text = re.sub(r"[^\w\s]+", "", text)
    return re.sub(r"\s+", " ", text).strip()


def _tracking_from_row(row: _MergedRow) -> tuple[str, str | None]:
    flags = _finalize_tracking_flags(set(row.flags))
    if "doing" in flags:
        status = "In progress"
    elif "watched" in flags:
        status = "Completed"
    elif "dropped" in flags:
        status = "Dropped"
    else:
        status = "Planning"

    lines: list[str] = []
    if flags:
        lines.append(f"{_FLAG_PREFIX}{','.join(sorted(flags))}")
    if row.review:
        lines.append(row.review.strip())
    notes = "\n".join(lines) if lines else None
    return status, notes


def _iso_now_if(condition: bool) -> str | None:
    if not condition:
        return None
    return datetime.now(tz=UTC).isoformat()


MUSICBOARD_SOURCE_FLAGS: dict[str, list[str]] = {
    "musicboardlater.csv": ["watchlist"],
    "musicboardtobuy.csv": ["buy"],
    "musicboardowned.csv": ["collected"],
    "musicboardalbum.csv": ["collected"],
    "musicboardstory.csv": ["watchlist"],
    "musicboardfav.csv": ["priority"],
    "musicboardhistory.csv": ["watched"],
}


def normalize_musicboard_cultur_target(target: str) -> str:
    normalized = (target or "").strip().lower()
    if normalized == "priority":
        return "later_priority"
    return normalized


def flags_from_cultur_targets(targets: set[str]) -> set[str]:
    flags: set[str] = set()
    for target in targets:
        key = normalize_musicboard_cultur_target(target)
        if key in {"skip", "custom_list", "rating"}:
            continue
        flags.update(MUSICBOARD_CULTUR_TARGET_FLAGS.get(key, ()))
    return _finalize_tracking_flags(flags)


def flags_from_musicboard_source_file(source_file: str) -> list[str]:
    base = (source_file or "").strip().casefold()
    if not base.endswith(".csv"):
        base = f"musicboard{base}.csv" if base else ""
    return list(MUSICBOARD_SOURCE_FLAGS.get(base, []))


def _finalize_tracking_flags(flags: set[str]) -> set[str]:
    if "dropped" in flags:
        flags.discard("watchlist")
        flags.discard("doing")
        flags.discard("watched")
    elif "watched" in flags:
        flags.discard("watchlist")
        flags.discard("doing")
    elif "doing" in flags:
        flags.discard("watchlist")
    return flags
