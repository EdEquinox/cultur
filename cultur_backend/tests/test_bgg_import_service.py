from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

from app.backend_models import AppUser, Base, CatalogSource, MediaItem, TrackingEntry
from app.bgg_client import BggBoardgame, BggCollectionRow
from app.schemas import BggCollectionImportRequest
from app.services import bgg_import_service


@pytest.fixture()
def db_session() -> Session:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    session.add(CatalogSource(code="bgg", label="BoardGameGeek"))
    session.commit()
    try:
        yield session
    finally:
        session.close()


def _game(game_id: str = "1", title: str = "Catan") -> BggBoardgame:
    return BggBoardgame(
        external_id=game_id,
        title=title,
        subtitle="1995",
        description=None,
        image_url="https://example.com/catan.jpg",
        metadata={"bggId": game_id},
    )


def test_import_bgg_collection_upserts_tracking_with_flags(db_session: Session) -> None:
    db_session.add(AppUser(username="alice"))
    db_session.commit()

    client = MagicMock()
    client.fetch_user_collection.return_value = [
        BggCollectionRow(
            external_id="1",
            title="Catan",
            flags=frozenset({"watchlist", "buy", "collected", "priority"}),
            bgg_rating=8.5,
        ),
    ]
    client.fetch_boardgames_by_ids.return_value = [_game()]

    result = bgg_import_service.import_bgg_collection(
        db_session,
        BggCollectionImportRequest(username="alice", bggUsername="bgguser"),
        bgg_client=client,
    )

    assert result.imported == 1
    assert result.skipped == 0
    assert result.total == 1

    media = db_session.scalar(select(MediaItem).where(MediaItem.external_id == "1"))
    assert media is not None
    assert media.media_type == "boardgame"
    assert media.source == "bgg"

    entry = db_session.scalar(
        select(TrackingEntry).where(TrackingEntry.media_item_id == media.id),
    )
    assert entry is not None
    assert entry.score == 8.5
    assert entry.notes == "[cult.flags]buy,collected,priority,watchlist"


def test_import_merges_flags_with_existing_tracking(db_session: Session) -> None:
    user = AppUser(username="alice")
    db_session.add(user)
    db_session.flush()
    media = MediaItem(
        source="bgg",
        external_id="1",
        media_type="boardgame",
        title="Catan",
    )
    db_session.add(media)
    db_session.flush()
    db_session.add(
        TrackingEntry(
            user_id=user.id,
            media_item_id=media.id,
            status="Planning",
            notes="[cult.flags]dropped",
        ),
    )
    db_session.commit()

    client = MagicMock()
    client.fetch_user_collection.return_value = [
        BggCollectionRow(
            external_id="1",
            title="Catan",
            flags=frozenset({"collected"}),
            bgg_rating=None,
        ),
    ]
    client.fetch_boardgames_by_ids.return_value = [_game()]

    bgg_import_service.import_bgg_collection(
        db_session,
        BggCollectionImportRequest(username="alice", bggUsername="bgguser"),
        bgg_client=client,
    )

    entry = db_session.scalar(
        select(TrackingEntry).where(TrackingEntry.media_item_id == media.id),
    )
    assert entry is not None
    assert "collected" in (entry.notes or "")
    assert "dropped" in (entry.notes or "")


def test_collection_row_imports_rated_only_games() -> None:
    from xml.etree.ElementTree import Element, SubElement

    from app.bgg_client import _collection_row_from_item

    item = Element("item", {"objectid": "99"})
    SubElement(item, "name").text = "Rated Only"
    stats = SubElement(item, "stats")
    stats.set("rating", "7")

    row = _collection_row_from_item(item)

    assert row is not None
    assert row.external_id == "99"
    assert row.bgg_rating == 7.0
    assert row.flags == frozenset()
