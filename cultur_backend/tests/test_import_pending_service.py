from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.igdb_client import IgdbClient, IgdbGame
from app.schemas import ResolvePendingCatalogRequest
from app.openlibrary_client import OpenLibraryBook
from app.services import import_pending_service


def test_pending_external_id_is_stable() -> None:
    a = import_pending_service.pending_external_id("title:foo")
    b = import_pending_service.pending_external_id("title:foo")
    assert a == b
    assert len(a) == 32


def test_upsert_pending_import_game_sets_catalog_pending_flag() -> None:
    db = MagicMock()
    db.scalar.return_value = None
    item = import_pending_service.upsert_pending_import_game(
        db,
        source=import_pending_service.IMPORT_PENDING_STASH_SOURCE,
        dedupe_key="title:test game",
        title="Test Game",
        image_url="https://example.com/cover.jpg",
        import_source="stash",
    )
    assert item.provider_payload.get("catalogPending") is True
    db.add.assert_called_once()


def test_resolve_pending_import_game_transfers_tracking() -> None:
    db = MagicMock()
    pending = MagicMock()
    pending.id = "pending-id"
    pending.media_type = "game"
    pending.source = import_pending_service.IMPORT_PENDING_STASH_SOURCE
    pending.provider_payload = {"catalogPending": True}

    resolved_item = MagicMock()
    resolved_item.id = "resolved-id"
    resolved_item.external_id = "12345"

    game = IgdbGame(
        external_id="12345",
        title="Resolved",
        subtitle=None,
        description=None,
        image_url=None,
        metadata={},
    )

    client = MagicMock(spec=IgdbClient)
    client.fetch_game_by_id.return_value = game

    db.scalar.side_effect = [pending, None, None]

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(import_pending_service, "upsert_igdb_game", lambda _db, _g: resolved_item)
        mp.setattr(import_pending_service, "_transfer_tracking", lambda *_a, **_k: None)
        mp.setattr(import_pending_service, "_delete_pending_media_if_orphan", lambda *_a, **_k: None)

        out = import_pending_service.resolve_pending_import_game(
            db,
            ResolvePendingCatalogRequest(
                username="tester",
                pendingMediaId="pending-id",
                igdbExternalId="12345",
            ),
            igdb_client=client,
        )

    assert out.resolvedMediaId == "resolved-id"
    assert out.resolvedExternalId == "12345"
    db.commit.assert_called_once()


def test_resolve_pending_book_from_hardcover_lookup() -> None:
    from app.openlibrary_client import OpenLibraryBook

    db = MagicMock()
    pending = MagicMock()
    pending.id = "pending-book"
    pending.media_type = "book"
    pending.source = import_pending_service.IMPORT_PENDING_BOOKMORY_SOURCE
    pending.provider_payload = {"catalogPending": True}

    class _Resolved:
        id = "resolved-book"
        external_id = "99100"

    resolved_item = _Resolved()

    snapshot = OpenLibraryBook(
        external_id="99100",
        title="Test Book",
        subtitle=None,
        description=None,
        image_url=None,
        metadata={},
    )

    book_clients = MagicMock()
    db.scalar.side_effect = [pending, None, None]

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(
            "app.services.book_edit_service.fetch_book_snapshot_by_lookup",
            lambda *_a, **_k: snapshot,
        )
        mp.setitem(
            import_pending_service._BOOK_UPSERT_BY_SOURCE,
            "hardcover",
            lambda _db, _b: resolved_item,
        )
        mp.setattr(import_pending_service, "_transfer_tracking", lambda *_a, **_k: None)
        mp.setattr(import_pending_service, "_delete_pending_media_if_orphan", lambda *_a, **_k: None)

        out = import_pending_service.resolve_pending_catalog(
            db,
            ResolvePendingCatalogRequest(
                username="tester",
                pendingMediaId="pending-book",
                resolvedSource="hardcover",
                resolvedExternalId="99100",
            ),
            book_clients=book_clients,
        )

    assert out.resolvedMediaId == "resolved-book"
    assert out.resolvedExternalId == "99100"
