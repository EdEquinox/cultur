"""Import games library from Stash.games CSV exports (IGDB cover URLs + title search)."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..igdb_client import (
    STASH_COLLECTION_TO_CULTUR_FLAGS,
    STASH_STATUS_TO_CULTUR_FLAGS,
    IgdbClient,
    IgdbError,
    IgdbGame,
)
from ..schemas import (
    BackendTrackingUpsertRequest,
    StashImportBatchRequest,
    StashImportBatchResponse,
    StashImportEntryPayload,
    StashImportItemError,
)
from . import backend_service
from .catalog_service import upsert_igdb_game
from .import_pending_service import (
    IMPORT_PENDING_STASH_SOURCE,
    upsert_pending_import_game,
)

logger = logging.getLogger(__name__)

_FLAG_PREFIX = "[cult.flags]"


@dataclass(slots=True)
class _MergedRow:
    source_file: str
    title: str
    image_url: str | None
    flags: set[str]
    score: float | None = None
    review: str | None = None


def import_stash_batch(
    db: Session,
    payload: StashImportBatchRequest,
    *,
    igdb_client: IgdbClient,
) -> StashImportBatchResponse:
    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="username is required.")

    merged = _merge_payload_entries(payload.entries)
    imported = 0
    pending_count = 0
    skipped = 0
    errors: list[StashImportItemError] = []

    for row in merged.values():
        title = row.title.strip()
        if not title:
            errors.append(
                StashImportItemError(
                    sourceFile=row.source_file,
                    title=title or row.source_file,
                    reason="missing_title",
                    message="Missing game title.",
                ),
            )
            skipped += 1
            continue
        try:
            game = _resolve_stash_game(igdb_client, title=title, image_url=row.image_url)
        except IgdbError as exc:
            _create_pending_from_row(db, row=row, title=title, username=username)
            errors.append(
                StashImportItemError(
                    sourceFile=row.source_file,
                    title=title,
                    reason="igdb_error",
                    message=str(exc),
                ),
            )
            pending_count += 1
            continue
        if game is None:
            _create_pending_from_row(db, row=row, title=title, username=username)
            errors.append(
                StashImportItemError(
                    sourceFile=row.source_file,
                    title=title,
                    reason="not_found",
                    message="Saved as pending — link it from the game page.",
                ),
            )
            pending_count += 1
            continue

        media = upsert_igdb_game(db, game)
        status, notes = _tracking_from_row(row)
        backend_service.upsert_tracking_entry(
            db,
            BackendTrackingUpsertRequest(
                username=username,
                mediaId=str(media.id),
                status=status,
                score=row.score if row.score and row.score > 0 else None,
                notes=notes,
                completedAt=_iso_now_if(status == "Completed"),
            ),
        )
        imported += 1

    db.commit()
    return StashImportBatchResponse(
        imported=imported,
        pending=pending_count,
        skipped=skipped,
        errors=errors,
    )


def _create_pending_from_row(
    db: Session,
    *,
    row: _MergedRow,
    title: str,
    username: str,
) -> None:
    dedupe = _dedupe_key(title, row.image_url)
    media = upsert_pending_import_game(
        db,
        source=IMPORT_PENDING_STASH_SOURCE,
        dedupe_key=dedupe,
        title=title,
        image_url=row.image_url,
        import_source="stash",
        import_meta={"stashSourceFile": row.source_file},
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
            completedAt=_iso_now_if(status == "Completed"),
        ),
    )


def _merge_payload_entries(entries: list[StashImportEntryPayload]) -> dict[str, _MergedRow]:
    merged: dict[str, _MergedRow] = {}
    for entry in entries:
        title = (entry.title or "").strip()
        if not title:
            continue
        key = _dedupe_key(title, entry.imageUrl)
        flags = {str(f).strip() for f in entry.flags if str(f).strip()}
        score = entry.score if entry.score and entry.score > 0 else None
        review = (entry.review or "").strip() or None
        source = (entry.sourceFile or "").strip() or "stash.csv"
        existing = merged.get(key)
        if existing is None:
            merged[key] = _MergedRow(
                source_file=source,
                title=title,
                image_url=(entry.imageUrl or "").strip() or None,
                flags=flags,
                score=score,
                review=review,
            )
            continue
        existing.flags.update(flags)
        if score is not None and (existing.score is None or score > existing.score):
            existing.score = score
        if review:
            if existing.review and existing.review != review:
                existing.review = f"{existing.review}\n\n{review}"
            else:
                existing.review = review
    return merged


def _dedupe_key(title: str, image_url: str | None) -> str:
    cover_id = IgdbClient.cover_image_id_from_url(image_url)
    if cover_id:
        return f"cover:{cover_id}"
    return f"title:{_normalize_title(title)}"


def _resolve_stash_game(
    client: IgdbClient,
    *,
    title: str,
    image_url: str | None,
) -> IgdbGame | None:
    from ..igdb_client import (
        igdb_collection_slug_from_url,
        igdb_game_slug_from_url,
        title_to_igdb_slug_candidates,
    )

    cover_id = IgdbClient.cover_image_id_from_url(image_url)
    if cover_id:
        game = client.fetch_game_by_cover_image_id(cover_id)
        if game is not None:
            return _hydrate_game(client, game)

    for url_candidate in (image_url,):
        slug = igdb_game_slug_from_url(url_candidate)
        if slug:
            game = client.fetch_game_by_slug_resolved(slug)
            if game is not None:
                return _hydrate_game(client, game)
        collection_slug = igdb_collection_slug_from_url(url_candidate)
        if collection_slug:
            from ..igdb_client import _games_from_collection_slug

            bundle_games = _games_from_collection_slug(client, collection_slug)
            if bundle_games:
                picked = _pick_best_title_match(title, bundle_games)
                if picked is not None:
                    return _hydrate_game(client, picked)

    for slug in title_to_igdb_slug_candidates(title):
        game = client.fetch_game_by_slug_resolved(slug)
        if game is not None:
            return _hydrate_game(client, game)

    seen_ids: set[str] = set()
    merged: list[IgdbGame] = []
    for query in _search_query_variants(title):
        for game in client.search_games(query, limit=20):
            if game.external_id in seen_ids:
                continue
            seen_ids.add(game.external_id)
            merged.append(game)
    if not merged:
        return None
    picked = _pick_best_title_match(title, merged)
    if picked is None:
        return None
    return _hydrate_game(client, picked)


def _hydrate_game(client: IgdbClient, game: IgdbGame) -> IgdbGame:
    if game.external_id.isdigit():
        detailed = client.fetch_game_by_id(game.external_id)
        return detailed or game
    return game


def _search_query_variants(title: str) -> list[str]:
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

    add(raw)
    for sep in (":", " - ", " – ", " — ", "|"):
        if sep in raw:
            left, right = raw.split(sep, 1)
            add(left)
            add(right)
            add(f"{left.strip()} {right.strip()}")
    no_paren = re.sub(r"\([^)]*\)", "", raw).strip()
    if no_paren:
        add(no_paren)
    return variants


def _pick_best_title_match(query: str, games: list[IgdbGame]) -> IgdbGame | None:
    if not games:
        return None
    want = _normalize_title(query)
    if not want:
        return None

    exact = [g for g in games if _normalize_title(g.title) == want]
    if len(exact) == 1:
        return exact[0]

    scored: list[tuple[IgdbGame, float]] = []
    for game in games:
        score = _title_match_score(query, game.title)
        if score > 0:
            scored.append((game, score))
    if not scored:
        return games[0] if len(games) == 1 else None

    scored.sort(key=lambda pair: (-pair[1], pair[0].title))
    best_game, best_score = scored[0]
    if best_score >= 0.82:
        return best_game
    if len(scored) == 1 and best_score >= 0.55:
        return best_game
    if len(scored) > 1:
        second_score = scored[1][1]
        if best_score >= 0.65 and (best_score - second_score) >= 0.12:
            return best_game
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
    from datetime import UTC, datetime

    return datetime.now(tz=UTC).isoformat()


def _finalize_tracking_flags(flags: set[str]) -> set[str]:
    """Resolve conflicting cultur flags after merging multiple Stash sources."""
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


def flags_from_stash_status(category: str | None) -> list[str]:
    """Map Stash tab status (Want, Playing, …) to cultur flag names."""
    key = (category or "").strip()
    if not key:
        return []
    mapped = STASH_STATUS_TO_CULTUR_FLAGS.get(key)
    return list(mapped) if mapped else []


def flags_from_stash_collection(collection_key: str | None) -> list[str]:
    """Map Stash collection slug (prioridades, fisical, …) to cultur flags."""
    key = (collection_key or "").strip().casefold()
    if not key:
        return []
    mapped = STASH_COLLECTION_TO_CULTUR_FLAGS.get(key)
    return list(mapped) if mapped else []
