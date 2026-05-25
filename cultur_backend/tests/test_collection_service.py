from __future__ import annotations

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

from app.backend_models import AppUser, Base, CatalogItem, Collection, CollectionItem
from app.schemas import (
    CollectionBulkSyncRequest,
    CollectionCreateRequest,
    CollectionSyncListPayload,
    CollectionToggleItemRequest,
)
from app.services import collection_service


@pytest.fixture()
def db_session() -> Session:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    try:
        yield session
    finally:
        session.close()


def _user(session: Session, name: str = "alice") -> AppUser:
    user = AppUser(username=name)
    session.add(user)
    session.commit()
    return user


def _album(session: Session, *, item_id: str = "album-1") -> CatalogItem:
    item = CatalogItem(
        id=item_id,
        source="musicbrainz",
        external_id="mbid-1",
        media_type="music",
        title="Test Album",
    )
    session.add(item)
    session.commit()
    return item


def test_list_collections_ensures_builtin_lists(db_session: Session) -> None:
    _user(db_session)
    result = collection_service.list_collections(
        db_session,
        username="alice",
        media_type="music",
    )
    ids = {row.id for row in result.lists}
    assert "__builtin_music_priority_queue" in ids
    assert "__builtin_music_pending_imports" in ids


def test_create_and_toggle_collection_item(db_session: Session) -> None:
    _user(db_session)
    album = _album(db_session)

    created = collection_service.create_collection(
        db_session,
        payload=CollectionCreateRequest(
            username="alice",
            mediaType="music",
            name="Favorites",
        ),
    )
    assert created.name == "Favorites"
    assert created.items == []

    updated = collection_service.toggle_collection_item(
        db_session,
        collection_id=created.id,
        payload=CollectionToggleItemRequest(username="alice", mediaId=album.id),
    )
    assert len(updated.items) == 1
    assert updated.items[0]["id"] == album.id

    removed = collection_service.toggle_collection_item(
        db_session,
        collection_id=created.id,
        payload=CollectionToggleItemRequest(username="alice", mediaId=album.id),
    )
    assert removed.items == []


def test_sync_collections_replaces_custom_lists(db_session: Session) -> None:
    _user(db_session)
    album = _album(db_session)

    collection_service.create_collection(
        db_session,
        payload=CollectionCreateRequest(
            username="alice",
            mediaType="music",
            name="Old list",
        ),
    )

    synced = collection_service.sync_collections(
        db_session,
        payload=CollectionBulkSyncRequest(
            username="alice",
            mediaType="music",
            lists=[
                CollectionSyncListPayload(
                    id="999",
                    name="Synced",
                    items=[{"id": album.id, "source": album.source, "externalId": album.external_id, "mediaType": "music", "title": album.title, "metadata": {}}],
                ),
            ],
        ),
    )
    names = {row.name for row in synced.lists if not row.isBuiltIn}
    assert names == {"Synced"}
    custom_count = db_session.scalar(
        select(Collection.id).where(
            Collection.user_id == db_session.scalar(select(AppUser.id).where(AppUser.username == "alice")),
            Collection.is_builtin.is_(False),
        ),
    )
    assert custom_count is not None
