"""User lists (collections) — replaces local custom_*_lists storage."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy import delete, select
from sqlalchemy.orm import Session, selectinload

from ..backend_models import AppUser, CatalogItem, Collection, CollectionItem
from ..schemas import (
    BackendMediaResponse,
    CollectionBulkSyncRequest,
    CollectionCreateRequest,
    CollectionListResponse,
    CollectionRenameRequest,
    CollectionResponse,
    CollectionToggleItemRequest,
)
from ..serializers.backend import serialize_media_item
from ..validation import require_text

_BUILTIN_LISTS: dict[str, list[tuple[str, str]]] = {
    "movie": [
        ("__builtin_priority_queue", "Priority queue"),
        ("__builtin_cinema_queue", "Movies in cinema"),
        ("__builtin_movie_pending_imports", "Pending imports"),
    ],
    "tv": [
        ("__builtin_tv_pending_imports", "Pending imports"),
    ],
    "game": [
        ("__builtin_game_priority_queue", "Priority queue"),
        ("__builtin_game_pending_imports", "Pending imports"),
    ],
    "boardgame": [
        ("__builtin_boardgame_priority_queue", "Priority queue"),
    ],
    "book": [
        ("__builtin_book_priority_queue", "Priority queue"),
        ("__builtin_book_pending_imports", "Pending imports"),
    ],
    "music": [
        ("__builtin_music_priority_queue", "Priority queue"),
        ("__builtin_music_pending_imports", "Pending imports"),
    ],
}

_VALID_MEDIA_TYPES = frozenset(_BUILTIN_LISTS.keys())


def _normalize_media_type(value: str) -> str:
    media_type = require_text(value, "mediaType").lower()
    if media_type not in _VALID_MEDIA_TYPES:
        allowed = ", ".join(sorted(_VALID_MEDIA_TYPES))
        raise HTTPException(status_code=400, detail=f"mediaType must be one of: {allowed}.")
    return media_type


def _require_user(db: Session, username: str) -> AppUser:
    user = db.scalar(select(AppUser).where(AppUser.username == username.strip()))
    if user is None:
        raise HTTPException(status_code=404, detail="User not found.")
    return user


def _ensure_builtin_lists(db: Session, *, user_id: str, media_type: str) -> None:
    existing_ids = set(
        db.scalars(
            select(Collection.id).where(
                Collection.user_id == user_id,
                Collection.media_type == media_type,
                Collection.is_builtin.is_(True),
            ),
        ).all(),
    )
    for index, (list_id, name) in enumerate(_BUILTIN_LISTS.get(media_type, [])):
        if list_id in existing_ids:
            continue
        db.add(
            Collection(
                id=list_id,
                user_id=user_id,
                name=name,
                media_type=media_type,
                slug=list_id,
                is_builtin=True,
                sort_order=index,
            ),
        )
    db.flush()


def _serialize_catalog_item(item: CatalogItem) -> BackendMediaResponse:
    return serialize_media_item(item)


def _serialize_collection_items(
    collection: Collection,
    *,
    media_type: str,
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    sorted_rows = sorted(
        collection.items,
        key=lambda row: (row.sort_order if row.sort_order is not None else 999_999, row.created_at),
    )
    if media_type == "tv":
        for row in sorted_rows:
            show = row.catalog_item
            if show is None:
                continue
            payload: dict[str, Any] = {
                "show": _serialize_catalog_item(show).model_dump(),
            }
            if row.season_number is not None:
                payload["seasonNumber"] = row.season_number
            if row.episode_number is not None:
                payload["episodeNumber"] = row.episode_number
            items.append(payload)
    else:
        for row in sorted_rows:
            if row.catalog_item is None:
                continue
            items.append(_serialize_catalog_item(row.catalog_item).model_dump())
    return items


def _collection_to_response(collection: Collection) -> CollectionResponse:
    created = collection.created_at.isoformat().replace("+00:00", "Z")
    return CollectionResponse(
        id=collection.id,
        name=collection.name,
        createdAt=created,
        isBuiltIn=bool(collection.is_builtin),
        mediaType=collection.media_type,
        items=_serialize_collection_items(collection, media_type=collection.media_type),
    )


def list_collections(
    db: Session,
    *,
    username: str,
    media_type: str,
) -> CollectionListResponse:
    user = _require_user(db, username)
    mtype = _normalize_media_type(media_type)
    _ensure_builtin_lists(db, user_id=user.id, media_type=mtype)
    db.commit()

    rows = db.scalars(
        select(Collection)
        .where(Collection.user_id == user.id, Collection.media_type == mtype)
        .options(selectinload(Collection.items).selectinload(CollectionItem.catalog_item))
        .order_by(Collection.is_builtin.desc(), Collection.sort_order.asc(), Collection.name.asc()),
    ).all()
    return CollectionListResponse(
        lists=[_collection_to_response(row) for row in rows],
    )


def get_collection(
    db: Session,
    *,
    username: str,
    collection_id: str,
) -> CollectionResponse:
    user = _require_user(db, username)
    row = db.scalar(
        select(Collection)
        .where(Collection.id == collection_id, Collection.user_id == user.id)
        .options(selectinload(Collection.items).selectinload(CollectionItem.catalog_item)),
    )
    if row is None:
        raise HTTPException(status_code=404, detail="List not found.")
    return _collection_to_response(row)


def create_collection(db: Session, *, payload: CollectionCreateRequest) -> CollectionResponse:
    user = _require_user(db, payload.username)
    mtype = _normalize_media_type(payload.mediaType)
    name = require_text(payload.name, "name")
    _ensure_builtin_lists(db, user_id=user.id, media_type=mtype)

    duplicate = db.scalar(
        select(Collection.id).where(
            Collection.user_id == user.id,
            Collection.media_type == mtype,
            Collection.name == name,
            Collection.is_builtin.is_(False),
        ),
    )
    if duplicate is not None:
        raise HTTPException(status_code=409, detail="A list with this name already exists.")

    row = Collection(
        id=str(uuid4()),
        user_id=user.id,
        name=name,
        media_type=mtype,
        is_builtin=False,
    )
    db.add(row)
    db.commit()
    return get_collection(db, username=payload.username, collection_id=row.id)


def rename_collection(
    db: Session,
    *,
    collection_id: str,
    payload: CollectionRenameRequest,
) -> CollectionResponse:
    user = _require_user(db, payload.username)
    name = require_text(payload.name, "name")
    row = db.get(Collection, collection_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="List not found.")
    if row.is_builtin:
        raise HTTPException(status_code=400, detail="Built-in lists cannot be renamed.")
    row.name = name
    row.updated_at = datetime.now(tz=UTC)
    db.commit()
    db.refresh(row)
    row = db.scalar(
        select(Collection)
        .where(Collection.id == collection_id)
        .options(selectinload(Collection.items).selectinload(CollectionItem.catalog_item)),
    )
    assert row is not None
    return _collection_to_response(row)


def delete_collection(db: Session, *, username: str, collection_id: str) -> None:
    user = _require_user(db, username)
    row = db.get(Collection, collection_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="List not found.")
    if row.is_builtin:
        raise HTTPException(status_code=400, detail="Built-in lists cannot be deleted.")
    db.delete(row)
    db.commit()


def _resolve_catalog_item(db: Session, media_id: str) -> CatalogItem:
    item = db.scalar(select(CatalogItem).where(CatalogItem.id == media_id))
    if item is None:
        raise HTTPException(status_code=404, detail="Catalog item not found.")
    return item


def _find_collection_item(
    db: Session,
    *,
    collection_id: str,
    catalog_item_id: str,
    season_number: int | None,
    episode_number: int | None,
) -> CollectionItem | None:
    rows = db.scalars(
        select(CollectionItem).where(CollectionItem.collection_id == collection_id),
    ).all()
    for row in rows:
        if row.catalog_item_id != catalog_item_id:
            continue
        if row.season_number == season_number and row.episode_number == episode_number:
            return row
    return None


def toggle_collection_item(
    db: Session,
    *,
    collection_id: str,
    payload: CollectionToggleItemRequest,
) -> CollectionResponse:
    user = _require_user(db, payload.username)
    media_id = require_text(payload.mediaId or payload.catalogItemId, "mediaId")
    row = db.scalar(
        select(Collection)
        .where(Collection.id == collection_id, Collection.user_id == user.id)
        .options(selectinload(Collection.items).selectinload(CollectionItem.catalog_item)),
    )
    if row is None:
        raise HTTPException(status_code=404, detail="List not found.")

    catalog_item = _resolve_catalog_item(db, media_id)
    if row.media_type == "tv":
        if catalog_item.media_type != "tv":
            raise HTTPException(status_code=400, detail="TV lists only accept TV series items.")
    elif catalog_item.media_type != row.media_type:
        raise HTTPException(
            status_code=400,
            detail=f"List is for {row.media_type}; item is {catalog_item.media_type}.",
        )

    season_number = payload.seasonNumber
    episode_number = payload.episodeNumber
    if row.media_type != "tv":
        season_number = None
        episode_number = None

    existing = _find_collection_item(
        db,
        collection_id=collection_id,
        catalog_item_id=catalog_item.id,
        season_number=season_number,
        episode_number=episode_number,
    )
    if existing is not None:
        db.delete(existing)
    else:
        db.add(
            CollectionItem(
                collection_id=collection_id,
                catalog_item_id=catalog_item.id,
                season_number=season_number,
                episode_number=episode_number,
                sort_order=len(row.items),
            ),
        )
    row.updated_at = datetime.now(tz=UTC)
    db.commit()
    return get_collection(db, username=payload.username, collection_id=collection_id)


def replace_collection_items(
    db: Session,
    *,
    collection_id: str,
    username: str,
    items: list[dict[str, Any]],
) -> None:
    user = _require_user(db, username)
    row = db.get(Collection, collection_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="List not found.")

    db.execute(delete(CollectionItem).where(CollectionItem.collection_id == collection_id))

    for index, raw in enumerate(items):
        if row.media_type == "tv":
            show_raw = raw.get("show")
            if not isinstance(show_raw, dict):
                continue
            media_id = str(show_raw.get("id") or "").strip()
            if not media_id:
                continue
            catalog_item = _resolve_catalog_item(db, media_id)
            season = raw.get("seasonNumber")
            episode = raw.get("episodeNumber")
            season_number = int(season) if season is not None else None
            episode_number = int(episode) if episode is not None else None
        else:
            media_id = str(raw.get("id") or "").strip()
            if not media_id:
                continue
            catalog_item = _resolve_catalog_item(db, media_id)
            season_number = None
            episode_number = None

        db.add(
            CollectionItem(
                collection_id=collection_id,
                catalog_item_id=catalog_item.id,
                season_number=season_number,
                episode_number=episode_number,
                sort_order=index,
            ),
        )
    row.updated_at = datetime.now(tz=UTC)


def sync_collections(db: Session, *, payload: CollectionBulkSyncRequest) -> CollectionListResponse:
    """Replace custom lists for a media type (built-ins are ensured, not removed)."""
    user = _require_user(db, payload.username)
    mtype = _normalize_media_type(payload.mediaType)
    _ensure_builtin_lists(db, user_id=user.id, media_type=mtype)

    custom_ids = db.scalars(
        select(Collection.id).where(
            Collection.user_id == user.id,
            Collection.media_type == mtype,
            Collection.is_builtin.is_(False),
        ),
    ).all()
    if custom_ids:
        db.execute(delete(Collection).where(Collection.id.in_(custom_ids)))

    for list_payload in payload.lists:
        list_id = str(list_payload.id).strip()
        name = str(list_payload.name).strip() or "Untitled list"
        if not list_id:
            continue
        is_builtin = list_id in {bid for bid, _ in _BUILTIN_LISTS.get(mtype, [])}
        if is_builtin:
            row = db.get(Collection, list_id)
            if row is None or row.user_id != user.id:
                continue
            replace_collection_items(
                db,
                collection_id=list_id,
                username=payload.username,
                items=list_payload.items,
            )
            continue

        created_at = datetime.now(tz=UTC)
        if list_payload.createdAt:
            parsed = datetime.fromisoformat(str(list_payload.createdAt).replace("Z", "+00:00"))
            created_at = parsed.astimezone(UTC) if parsed.tzinfo else parsed.replace(tzinfo=UTC)

        row = Collection(
            id=list_id,
            user_id=user.id,
            name=name,
            media_type=mtype,
            is_builtin=False,
            created_at=created_at,
        )
        db.add(row)
        db.flush()
        replace_collection_items(
            db,
            collection_id=list_id,
            username=payload.username,
            items=list_payload.items,
        )

    db.commit()
    return list_collections(db, username=payload.username, media_type=mtype)


def purge_collections_for_user(db: Session, *, user_id: str, media_types: set[str]) -> int:
    ids = db.scalars(
        select(Collection.id).where(
            Collection.user_id == user_id,
            Collection.media_type.in_(tuple(media_types)),
        ),
    ).all()
    if not ids:
        return 0
    result = db.execute(delete(Collection).where(Collection.id.in_(ids)))
    return int(result.rowcount or 0)
