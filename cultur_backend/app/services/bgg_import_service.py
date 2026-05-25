from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..backend_models import AppUser, MediaItem, TrackingEntry
from ..bgg_client import BggBoardgame, BggClient, BggCollectionRow, BggError, build_tracking_notes
from ..schemas import BackendTrackingUpsertRequest, BggCollectionImportRequest, BggCollectionImportResponse
from . import backend_service
from .catalog_service import upsert_bgg_boardgame
from .tracking_library import flags_from_notes


def _merge_tracking_notes(
    db: Session,
    *,
    cult_username: str,
    media_item_id: str,
    new_flags: frozenset[str],
) -> str | None:
    user = db.scalar(select(AppUser).where(AppUser.username == cult_username))
    if user is None:
        return build_tracking_notes(new_flags)
    entry = db.scalar(
        select(TrackingEntry).where(
            TrackingEntry.user_id == user.id,
            TrackingEntry.media_item_id == media_item_id,
        ),
    )
    existing = flags_from_notes(entry.notes if entry else None)
    merged = frozenset(existing | set(new_flags))
    return build_tracking_notes(merged)


def import_bgg_collection(
    db: Session,
    payload: BggCollectionImportRequest,
    *,
    bgg_client: BggClient,
) -> BggCollectionImportResponse:
    cult_username = payload.username.strip()
    bgg_username = payload.bggUsername.strip()
    if not cult_username:
        raise HTTPException(status_code=400, detail="username is required.")
    if not bgg_username:
        raise HTTPException(status_code=400, detail="bggUsername is required.")

    try:
        rows = bgg_client.fetch_user_collection(bgg_username)
    except BggError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    if not rows:
        raise HTTPException(
            status_code=404,
            detail=(
                f"No board games found for BGG user “{bgg_username}”. "
                "Check the username and that your collection is public under "
                "BGG Settings → Privacy."
            ),
        )

    total = len(rows)
    games_by_id = {
        game.external_id: game
        for game in bgg_client.fetch_boardgames_by_ids([row.external_id for row in rows])
    }

    imported = 0
    skipped = 0
    for row in rows:
        game = games_by_id.get(row.external_id)
        if game is None:
            skipped += 1
            continue
        media = upsert_bgg_boardgame(db, game)
        notes = _merge_tracking_notes(
            db,
            cult_username=cult_username,
            media_item_id=str(media.id),
            new_flags=row.flags,
        )
        score = row.bgg_rating if row.bgg_rating and row.bgg_rating > 0 else None
        backend_service.upsert_tracking_entry(
            db,
            BackendTrackingUpsertRequest(
                username=cult_username,
                mediaId=str(media.id),
                status="Planning",
                score=score,
                notes=notes,
            ),
        )
        imported += 1

    db.commit()
    return BggCollectionImportResponse(imported=imported, skipped=skipped, total=total)
