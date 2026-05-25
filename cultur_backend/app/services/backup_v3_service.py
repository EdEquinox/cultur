"""Export/import full Cultur library backups (cultur-backup-v3, with v2 compatibility)."""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy import delete, select
from sqlalchemy.orm import Session, selectinload

from ..backend_models import (
    AppUser,
    CatalogItem,
    CatalogSource,
    Collection,
    CollectionItem,
    MediaItem,
    Person,
    TrackingCollectedDetail,
    TrackingEntry,
    TrackingLoan,
    TvEpisodeUserState,
    TvEpisodeWatch,
    TvSeasonUserState,
    UserFollow,
)
from ..config import Settings
from ..schemas import (
    AvaBackupImportRequest,
    BackendTrackingUpsertRequest,
    CollectionBulkSyncRequest,
    CollectionSyncListPayload,
    CulturBackupV3ExportResponse,
    CulturBackupV3ImportRequest,
    CulturBackupV3ImportResponse,
    TvEpisodeWatchPutRequest,
    UserFollowPayload,
)
from ..serializers.backend import serialize_media_item
from . import backend_service
from . import backup_export_service
from . import backup_import_service
from .collection_service import _VALID_MEDIA_TYPES, sync_collections
from .tracking_library import (
    append_lent_line_to_notes,
    compose_notes_with_flags,
    load_tracking_flags,
    replace_tracking_flags,
)
from .user_follow_service import follow_user

logger = logging.getLogger(__name__)

FORMAT_V3 = "cultur-backup-v3"
FORMAT_V2 = "cultur-backup-v2"
VERSION_V3 = 3


def _iso_z(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return dt.isoformat().replace("+00:00", "Z")


def _parse_iso_z(value: str | None) -> datetime | None:
    if not value or not str(value).strip():
        return None
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _require_user(db: Session, username: str) -> AppUser:
    user = db.scalar(select(AppUser).where(AppUser.username == username.strip()))
    if user is None:
        raise HTTPException(status_code=404, detail="User not found.")
    return user


def _media_ref(item: MediaItem) -> dict[str, Any]:
    return serialize_media_item(item).model_dump()


def _ensure_catalog_source(db: Session, code: str) -> None:
    if db.get(CatalogSource, code) is None:
        db.add(CatalogSource(code=code, label=code))
        db.flush()


def ensure_catalog_item_from_ref(db: Session, ref: dict[str, Any]) -> MediaItem | None:
    source = str(ref.get("source") or "").strip().lower()
    external_id = str(ref.get("externalId") or "").strip()
    media_type = str(ref.get("mediaType") or "").strip().lower()
    title = str(ref.get("title") or "").strip()
    if not source or not external_id or not media_type:
        return None
    if not title:
        title = f"{media_type} ({source}:{external_id})"

    _ensure_catalog_source(db, source)
    item = db.scalar(
        select(MediaItem).where(
            MediaItem.source == source,
            MediaItem.media_type == media_type,
            MediaItem.external_id == external_id,
        ),
    )
    metadata = ref.get("metadata")
    meta_dict = metadata if isinstance(metadata, dict) else {}
    if item is None:
        item = MediaItem(
            source=source,
            external_id=external_id,
            media_type=media_type,
            title=title,
            subtitle=ref.get("subtitle"),
            description=ref.get("description"),
            image_url=ref.get("imageUrl"),
            provider_payload=meta_dict,
        )
        db.add(item)
        db.flush()
    else:
        item.title = title
        if ref.get("subtitle") is not None:
            item.subtitle = ref.get("subtitle")
        if ref.get("description") is not None:
            item.description = ref.get("description")
        if ref.get("imageUrl") is not None:
            item.image_url = ref.get("imageUrl")
        if meta_dict:
            item.provider_payload = {**(item.provider_payload or {}), **meta_dict}
    return item


def _resolve_media_ref(db: Session, ref: dict[str, Any] | None) -> MediaItem | None:
    if not isinstance(ref, dict):
        return None
    item = ensure_catalog_item_from_ref(db, ref)
    if item is not None:
        return item
    media_id = str(ref.get("id") or "").strip()
    if media_id:
        return db.scalar(select(MediaItem).where(MediaItem.id == media_id))
    return None


def _serialize_tracking_row(db: Session, entry: TrackingEntry) -> dict[str, Any]:
    media = entry.media_item
    flags = sorted(load_tracking_flags(db, entry))
    loans: list[dict[str, Any]] = []
    for loan in entry.loans:
        loans.append(
            {
                "borrowerName": loan.borrower_name,
                "lentAt": _iso_z(loan.lent_at),
                "returnedAt": _iso_z(loan.returned_at),
            },
        )
    collected: dict[str, Any] | None = None
    if entry.collected_detail is not None:
        detail = entry.collected_detail
        collected = {
            "price": detail.price,
            "ownedReleaseSource": detail.owned_release_source,
            "ownedReleaseExternalId": detail.owned_release_external_id,
        }
    return {
        "mediaRef": _media_ref(media),
        "status": entry.status,
        "progress": entry.progress,
        "score": entry.score,
        "notes": entry.notes,
        "startedAt": _iso_z(entry.started_at),
        "completedAt": _iso_z(entry.completed_at),
        "droppedAt": _iso_z(entry.dropped_at),
        "collectedAt": _iso_z(entry.collected_at),
        "tvFullyWatched": bool(entry.tv_fully_watched),
        "tvAiredEpisodeTotal": entry.tv_aired_episode_total,
        "flags": flags,
        "loans": loans,
        "collectedDetail": collected,
    }


def _collection_items_for_backup(collection: Collection) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    sorted_rows = sorted(
        collection.items,
        key=lambda row: (row.sort_order if row.sort_order is not None else 999_999, row.created_at),
    )
    if collection.media_type == "tv":
        for row in sorted_rows:
            show = row.catalog_item
            if show is None:
                continue
            payload: dict[str, Any] = {"mediaRef": _media_ref(show)}
            if row.season_number is not None:
                payload["seasonNumber"] = row.season_number
            if row.episode_number is not None:
                payload["episodeNumber"] = row.episode_number
            out.append(payload)
    else:
        for row in sorted_rows:
            item = row.catalog_item
            if item is None:
                continue
            out.append({"mediaRef": _media_ref(item)})
    return out


def export_cultur_backup_v3(db: Session, *, username: str) -> CulturBackupV3ExportResponse:
    user = _require_user(db, username)
    exported_at = datetime.now(tz=UTC).isoformat().replace("+00:00", "Z")

    entries = db.scalars(
        select(TrackingEntry)
        .where(TrackingEntry.user_id == user.id)
        .options(
            selectinload(TrackingEntry.media_item),
            selectinload(TrackingEntry.flags),
            selectinload(TrackingEntry.loans),
            selectinload(TrackingEntry.collected_detail),
        ),
    ).all()
    tracking_rows = [_serialize_tracking_row(db, entry) for entry in entries]

    tv_watches = db.scalars(
        select(TvEpisodeWatch)
        .where(TvEpisodeWatch.user_id == user.id)
        .options(selectinload(TvEpisodeWatch.media_item)),
    ).all()
    tv_episode_watches = [
        {
            "mediaRef": _media_ref(row.media_item),
            "seasonNumber": row.season_number,
            "episodeNumber": row.episode_number,
            "watchedAt": _iso_z(row.watched_at),
        }
        for row in tv_watches
    ]

    ep_states = db.scalars(
        select(TvEpisodeUserState)
        .where(TvEpisodeUserState.user_id == user.id)
        .options(selectinload(TvEpisodeUserState.media_item)),
    ).all()
    tv_episode_user_states = [
        {
            "mediaRef": _media_ref(row.media_item),
            "seasonNumber": row.season_number,
            "episodeNumber": row.episode_number,
            "rating": row.rating,
            "ratingRatedAt": _iso_z(row.rating_rated_at),
            "watchlist": bool(row.watchlist),
            "watchlistedAt": _iso_z(row.watchlisted_at),
        }
        for row in ep_states
    ]

    season_states = db.scalars(
        select(TvSeasonUserState)
        .where(TvSeasonUserState.user_id == user.id)
        .options(selectinload(TvSeasonUserState.media_item)),
    ).all()
    tv_season_user_states = [
        {
            "mediaRef": _media_ref(row.media_item),
            "seasonNumber": row.season_number,
            "rating": row.rating,
            "ratingRatedAt": _iso_z(row.rating_rated_at),
            "watchlist": bool(row.watchlist),
            "watchlistedAt": _iso_z(row.watchlisted_at),
        }
        for row in season_states
    ]

    collections_by_media_type: dict[str, Any] = {}
    for mtype in sorted(_VALID_MEDIA_TYPES):
        rows = db.scalars(
            select(Collection)
            .where(Collection.user_id == user.id, Collection.media_type == mtype)
            .options(selectinload(Collection.items).selectinload(CollectionItem.catalog_item))
            .order_by(Collection.is_builtin.desc(), Collection.created_at),
        ).all()
        collections_by_media_type[mtype] = {
            "lists": [
                {
                    "id": row.id,
                    "name": row.name,
                    "createdAt": row.created_at.isoformat().replace("+00:00", "Z"),
                    "isBuiltIn": bool(row.is_builtin),
                    "items": _collection_items_for_backup(row),
                }
                for row in rows
            ],
        }

    follow_rows = db.scalars(
        select(UserFollow)
        .where(UserFollow.user_id == user.id)
        .options(selectinload(UserFollow.person).selectinload(Person.identities)),
    ).all()
    follows: list[dict[str, Any]] = []
    for row in follow_rows:
        person = row.person
        identity = person.identities[0] if person.identities else None
        follows.append(
            {
                "entityKind": person.entity_kind,
                "personId": person.id,
                "name": person.display_name,
                "imageUrl": person.image_url,
                "sourceCode": identity.source_code if identity else None,
                "externalId": identity.external_id if identity else None,
            },
        )

    legacy_ava: dict[str, Any] | None = None
    try:
        ava_resp = backup_export_service.export_ava_backup_v1(db, username=username)
        legacy_ava = ava_resp.backup
    except Exception as exc:  # noqa: BLE001
        logger.warning("AVA legacy export skipped for %s: %s", username, exc)

    document: dict[str, Any] = {
        "format": FORMAT_V3,
        "version": VERSION_V3,
        "exportedAt": exported_at,
        "username": username,
        "data": {
            "tracking": tracking_rows,
            "tvEpisodeWatches": tv_episode_watches,
            "tvEpisodeUserStates": tv_episode_user_states,
            "tvSeasonUserStates": tv_season_user_states,
            "collectionsByMediaType": collections_by_media_type,
            "follows": follows,
        },
    }
    if legacy_ava is not None:
        document["legacy"] = {"ava": legacy_ava}

    summary = {
        "tracking": len(tracking_rows),
        "tvEpisodeWatches": len(tv_episode_watches),
        "tvEpisodeUserStates": len(tv_episode_user_states),
        "tvSeasonUserStates": len(tv_season_user_states),
        "follows": len(follows),
        "collectionLists": sum(
            len(block.get("lists") or [])
            for block in collections_by_media_type.values()
            if isinstance(block, dict)
        ),
    }
    return CulturBackupV3ExportResponse(
        ok=True,
        message=f"Exported Cultur backup v3 for {username}.",
        document=document,
        summary=summary,
    )


def _extract_v3_data(document: dict[str, Any]) -> dict[str, Any]:
    fmt = str(document.get("format") or "")
    if fmt == FORMAT_V3:
        data = document.get("data")
        return data if isinstance(data, dict) else {}
    if fmt == FORMAT_V2:
        server = document.get("server")
        if not isinstance(server, dict):
            return {}
        tracking_payload = server.get("tracking")
        tracking_items: list[Any] = []
        if isinstance(tracking_payload, dict):
            raw_items = tracking_payload.get("items")
            if isinstance(raw_items, list):
                tracking_items = raw_items
        elif isinstance(tracking_payload, list):
            tracking_items = tracking_payload

        tracking_rows: list[dict[str, Any]] = []
        for raw in tracking_items:
            if not isinstance(raw, dict):
                continue
            media = raw.get("media")
            if not isinstance(media, dict):
                continue
            tracking_rows.append(
                {
                    "mediaRef": media,
                    "status": raw.get("status") or "In progress",
                    "progress": raw.get("progress"),
                    "score": raw.get("score"),
                    "notes": raw.get("notes"),
                    "startedAt": raw.get("startedAt"),
                    "completedAt": raw.get("completedAt"),
                    "droppedAt": raw.get("droppedAt"),
                    "collectedAt": raw.get("collectedAt"),
                    "tvFullyWatched": raw.get("tvFullyWatched"),
                    "tvAiredEpisodeTotal": raw.get("tvAiredEpisodeTotal"),
                    "flags": [],
                },
            )

        tv_watches_raw = server.get("tvWatchedEpisodes")
        tv_items: list[Any] = []
        if isinstance(tv_watches_raw, dict):
            tv_items = tv_watches_raw.get("items") or []
        elif isinstance(tv_watches_raw, list):
            tv_items = tv_watches_raw

        tv_episode_watches: list[dict[str, Any]] = []
        for raw in tv_items:
            if not isinstance(raw, dict):
                continue
            media = raw.get("media") or raw.get("show")
            if not isinstance(media, dict):
                continue
            tv_episode_watches.append(
                {
                    "mediaRef": media,
                    "seasonNumber": raw.get("seasonNumber"),
                    "episodeNumber": raw.get("episodeNumber"),
                    "watchedAt": raw.get("watchedAt"),
                },
            )

        legacy = document.get("legacy")
        ava = None
        if isinstance(legacy, dict):
            ava = legacy.get("ava")
        if ava is None and isinstance(server.get("ava"), dict):
            ava = server.get("ava")

        return {
            "tracking": tracking_rows,
            "tvEpisodeWatches": tv_episode_watches,
            "tvEpisodeUserStates": [],
            "tvSeasonUserStates": [],
            "collectionsByMediaType": {},
            "follows": [],
            "legacyAva": ava,
        }
    raise HTTPException(
        status_code=400,
        detail="Unsupported backup format. Expected cultur-backup-v3 or cultur-backup-v2.",
    )


def _collection_items_to_sync(items: list[Any], *, media_type: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for raw in items:
        if not isinstance(raw, dict):
            continue
        media_ref = raw.get("mediaRef")
        if not isinstance(media_ref, dict):
            show = raw.get("show")
            if isinstance(show, dict):
                media_ref = show
            elif raw.get("id"):
                media_ref = raw
        if not isinstance(media_ref, dict):
            continue
        if media_type == "tv":
            out.append(
                {
                    "show": {"id": str(media_ref.get("id") or "")},
                    "seasonNumber": raw.get("seasonNumber"),
                    "episodeNumber": raw.get("episodeNumber"),
                    "_mediaRef": media_ref,
                },
            )
        else:
            out.append({"id": str(media_ref.get("id") or ""), "_mediaRef": media_ref})
    return out


def _apply_collected_detail(
    db: Session,
    entry: TrackingEntry,
    detail: dict[str, Any] | None,
) -> None:
    if not isinstance(detail, dict):
        return
    row = entry.collected_detail
    if row is None:
        row = TrackingCollectedDetail(tracking_entry_id=entry.id)
        db.add(row)
    row.price = detail.get("price")
    row.owned_release_source = detail.get("ownedReleaseSource")
    row.owned_release_external_id = detail.get("ownedReleaseExternalId")


def _apply_loans(db: Session, entry: TrackingEntry, loans: list[Any]) -> None:
    db.execute(delete(TrackingLoan).where(TrackingLoan.tracking_entry_id == entry.id))
    if not isinstance(loans, list):
        return
    for raw in loans:
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("borrowerName") or "").strip()
        if not name:
            continue
        lent_at = _parse_iso_z(raw.get("lentAt")) or datetime.now(tz=UTC)
        returned_at = _parse_iso_z(raw.get("returnedAt"))
        db.add(
            TrackingLoan(
                tracking_entry_id=entry.id,
                borrower_name=name,
                lent_at=lent_at,
                returned_at=returned_at,
            ),
        )


def import_cultur_backup_v3(
    db: Session,
    settings: Settings,
    *,
    payload: CulturBackupV3ImportRequest,
    tmdb_client: Any | None = None,
) -> CulturBackupV3ImportResponse:
    user = _require_user(db, payload.username)
    document = payload.document
    if not isinstance(document, dict):
        raise HTTPException(status_code=400, detail="document must be a JSON object.")

    data = _extract_v3_data(document)
    warnings: list[str] = []
    summary: dict[str, int] = {
        "trackingWritten": 0,
        "trackingSkipped": 0,
        "tvEpisodeWatchesWritten": 0,
        "collectionsSynced": 0,
        "followsWritten": 0,
    }

    skip_existing = payload.skipExistingTracking

    for raw in data.get("tracking") or []:
        if not isinstance(raw, dict):
            continue
        media = _resolve_media_ref(db, raw.get("mediaRef") if isinstance(raw.get("mediaRef"), dict) else None)
        if media is None:
            warnings.append("Skipped tracking row: could not resolve media.")
            summary["trackingSkipped"] += 1
            continue

        existing = db.scalar(
            select(TrackingEntry).where(
                TrackingEntry.user_id == user.id,
                TrackingEntry.media_item_id == media.id,
            ),
        )
        if existing is not None and skip_existing:
            summary["trackingSkipped"] += 1
            continue

        flags_raw = raw.get("flags")
        flags = {str(f).strip() for f in flags_raw if isinstance(flags_raw, list) and str(f).strip()}
        notes = raw.get("notes")
        if flags:
            notes = compose_notes_with_flags(notes if isinstance(notes, str) else None, flags)

        loans_raw = raw.get("loans")
        if isinstance(loans_raw, list):
            for loan in loans_raw:
                if not isinstance(loan, dict):
                    continue
                borrower = str(loan.get("borrowerName") or "").strip()
                if not borrower:
                    continue
                lent_at = _parse_iso_z(loan.get("lentAt")) or datetime.now(tz=UTC)
                if loan.get("returnedAt") is None:
                    notes = append_lent_line_to_notes(
                        notes if isinstance(notes, str) else None,
                        borrower=borrower,
                        lent_at=lent_at,
                    )

        upsert_payload = BackendTrackingUpsertRequest(
            username=payload.username,
            mediaId=media.id,
            status=str(raw.get("status") or "In progress"),
            progress=raw.get("progress"),
            score=raw.get("score"),
            notes=notes if isinstance(notes, str) else None,
            startedAt=raw.get("startedAt"),
            completedAt=raw.get("completedAt"),
            droppedAt=raw.get("droppedAt"),
            collectedAt=raw.get("collectedAt"),
        )
        backend_service.upsert_tracking_entry(db, upsert_payload, tmdb_client=tmdb_client)
        entry = db.scalar(
            select(TrackingEntry).where(
                TrackingEntry.user_id == user.id,
                TrackingEntry.media_item_id == media.id,
            ),
        )
        if entry is None:
            continue
        if flags:
            replace_tracking_flags(db, entry, flags)
        _apply_loans(db, entry, raw.get("loans") or [])
        _apply_collected_detail(db, entry, raw.get("collectedDetail"))
        if raw.get("tvFullyWatched") is not None:
            entry.tv_fully_watched = bool(raw.get("tvFullyWatched"))
        if raw.get("tvAiredEpisodeTotal") is not None:
            entry.tv_aired_episode_total = raw.get("tvAiredEpisodeTotal")
        db.flush()
        summary["trackingWritten"] += 1

    for raw in data.get("tvEpisodeWatches") or []:
        if not isinstance(raw, dict):
            continue
        media = _resolve_media_ref(db, raw.get("mediaRef") if isinstance(raw.get("mediaRef"), dict) else None)
        if media is None:
            continue
        season = raw.get("seasonNumber")
        episode = raw.get("episodeNumber")
        if season is None or episode is None:
            continue
        backend_service.put_tv_episode_watch(
            db,
            TvEpisodeWatchPutRequest(
                username=payload.username,
                mediaId=media.id,
                seasonNumber=int(season),
                episodeNumber=int(episode),
                watched=True,
                watchedAt=raw.get("watchedAt"),
            ),
            commit=True,
        )
        summary["tvEpisodeWatchesWritten"] += 1

    for raw in data.get("tvEpisodeUserStates") or []:
        if not isinstance(raw, dict):
            continue
        media = _resolve_media_ref(db, raw.get("mediaRef") if isinstance(raw.get("mediaRef"), dict) else None)
        if media is None:
            continue
        backend_service.apply_tv_episode_user_state_from_backup(
            db,
            user_id=user.id,
            media_item_id=media.id,
            season_number=int(raw["seasonNumber"]),
            episode_number=int(raw["episodeNumber"]),
            rating=raw.get("rating"),
            set_rating="rating" in raw,
            rating_rated_at=_parse_iso_z(raw.get("ratingRatedAt")),
            watchlist=bool(raw.get("watchlist")),
            set_watchlist="watchlist" in raw,
            watchlisted_at=_parse_iso_z(raw.get("watchlistedAt")),
        )

    for raw in data.get("tvSeasonUserStates") or []:
        if not isinstance(raw, dict):
            continue
        media = _resolve_media_ref(db, raw.get("mediaRef") if isinstance(raw.get("mediaRef"), dict) else None)
        if media is None:
            continue
        backend_service.apply_tv_season_user_state_from_backup(
            db,
            user_id=user.id,
            media_item_id=media.id,
            season_number=int(raw["seasonNumber"]),
            rating=raw.get("rating"),
            set_rating="rating" in raw,
            rating_rated_at=_parse_iso_z(raw.get("ratingRatedAt")),
            watchlist=bool(raw.get("watchlist")),
            set_watchlist="watchlist" in raw,
            watchlisted_at=_parse_iso_z(raw.get("watchlistedAt")),
        )

    collections_block = data.get("collectionsByMediaType")
    if isinstance(collections_block, dict):
        for mtype, block in collections_block.items():
            if mtype not in _VALID_MEDIA_TYPES or not isinstance(block, dict):
                continue
            lists_raw = block.get("lists")
            if not isinstance(lists_raw, list):
                continue
            sync_lists: list[CollectionSyncListPayload] = []
            for list_raw in lists_raw:
                if not isinstance(list_raw, dict):
                    continue
                items_raw = list_raw.get("items") or []
                sync_items: list[dict[str, Any]] = []
                for item_raw in _collection_items_to_sync(items_raw, media_type=mtype):
                    media_ref = item_raw.pop("_mediaRef", None)
                    resolved = _resolve_media_ref(db, media_ref if isinstance(media_ref, dict) else None)
                    if resolved is None:
                        continue
                    if mtype == "tv":
                        sync_items.append(
                            {
                                "show": {"id": resolved.id},
                                "seasonNumber": item_raw.get("seasonNumber"),
                                "episodeNumber": item_raw.get("episodeNumber"),
                            },
                        )
                    else:
                        sync_items.append({"id": resolved.id})
                sync_lists.append(
                    CollectionSyncListPayload(
                        id=str(list_raw.get("id") or uuid4()),
                        name=str(list_raw.get("name") or "Untitled list"),
                        createdAt=list_raw.get("createdAt"),
                        items=sync_items,
                    ),
                )
            if sync_lists:
                sync_collections(
                    db,
                    payload=CollectionBulkSyncRequest(
                        username=payload.username,
                        mediaType=mtype,
                        lists=sync_lists,
                    ),
                )
                summary["collectionsSynced"] += len(sync_lists)

    for raw in data.get("follows") or []:
        if not isinstance(raw, dict):
            continue
        entity_kind = str(raw.get("entityKind") or "person").strip().lower()
        source = raw.get("sourceCode")
        external = raw.get("externalId")
        name = str(raw.get("name") or "").strip()
        if not name and not raw.get("personId"):
            continue
        try:
            follow_user(
                db,
                settings,
                payload=UserFollowPayload(
                    username=payload.username,
                    entityKind=entity_kind,
                    personId=raw.get("personId"),
                    sourceCode=source,
                    externalId=external,
                    name=name or None,
                    imageUrl=raw.get("imageUrl"),
                ),
            )
            summary["followsWritten"] += 1
        except HTTPException as exc:
            warnings.append(f"Follow skipped ({name or external}): {exc.detail}")

    legacy_ava = data.get("legacyAva")
    if payload.importLegacyAva and isinstance(legacy_ava, dict) and tmdb_client is not None:
        backup_import_service.import_ava_backup_v1(
            db,
            tmdb_client,
            AvaBackupImportRequest(
                username=payload.username,
                backup=legacy_ava,
                skipExistingTracking=payload.skipExistingTracking,
            ),
        )

    db.commit()
    return CulturBackupV3ImportResponse(
        ok=True,
        message=f"Imported Cultur backup for {payload.username}.",
        summary=summary,
        warnings=warnings,
    )
