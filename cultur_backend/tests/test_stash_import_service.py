from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.igdb_client import IgdbClient, IgdbGame
from app.schemas import StashImportBatchRequest, StashImportEntryPayload
from app.services import stash_import_service


def _game(title: str, ext_id: str = "42") -> IgdbGame:
    return IgdbGame(
        external_id=ext_id,
        title=title,
        subtitle=None,
        description=None,
        image_url="https://images.igdb.com/igdb/image/upload/t_cover_big/co7jfv.webp",
        metadata={},
    )


def test_merge_payload_entries_unions_flags() -> None:
    merged = stash_import_service._merge_payload_entries(
        [
            StashImportEntryPayload(
                sourceFile="stashPlaying.csv",
                title="Dead Cells",
                imageUrl="https://images.igdb.com/igdb/image/upload/t_cover_big/co7jfv.webp",
                flags=["doing"],
            ),
            StashImportEntryPayload(
                sourceFile="stashprioridades.csv",
                title="Dead Cells",
                imageUrl="https://images.igdb.com/igdb/image/upload/t_cover_big/co7jfv.webp",
                flags=["priority"],
            ),
        ],
    )
    assert len(merged) == 1
    row = next(iter(merged.values()))
    assert row.flags == {"doing", "priority"}


def test_resolve_stash_game_uses_cover_image_id() -> None:
    client = MagicMock(spec=IgdbClient)
    stub = _game("Dead Cells", "99")
    client.fetch_game_by_cover_image_id.return_value = stub
    client.fetch_game_by_id.return_value = stub

    game = stash_import_service._resolve_stash_game(
        client,
        title="Dead Cells",
        image_url="https://images.igdb.com/igdb/image/upload/t_cover_big/co7jfv.webp",
    )
    assert game is not None
    assert game.external_id == "99"
    client.fetch_game_by_cover_image_id.assert_called_once_with("co7jfv")
    client.search_games.assert_not_called()


def test_pick_best_title_match_scores_partial_titles() -> None:
    games = [
        _game("Agatha Christie - The ABC Murders", "101"),
        _game("Agatha Christie: Murder on the Orient Express", "102"),
    ]
    picked = stash_import_service._pick_best_title_match(
        "Agatha Christie - The ABC Murders",
        games,
    )
    assert picked is not None
    assert picked.external_id == "101"


def test_title_to_slug_candidates_includes_disambiguation() -> None:
    from app.igdb_client import title_to_igdb_slug_candidates

    slugs = title_to_igdb_slug_candidates("Agatha Christie - The ABC Murders")
    assert "agatha-christie-the-abc-murders" in slugs
    assert "agatha-christie-the-abc-murders--1" in slugs


def test_import_stash_batch_imports_and_skips() -> None:
    db = MagicMock()
    client = MagicMock(spec=IgdbClient)
    dead_cells = _game("Dead Cells", "100")
    client.fetch_game_by_cover_image_id.return_value = dead_cells
    client.fetch_game_by_slug_resolved.return_value = None
    client.fetch_game_by_id.return_value = dead_cells
    client.search_games.return_value = []

    media = MagicMock()
    media.id = "media-1"
    pending_media = MagicMock()
    pending_media.id = "pending-1"
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(stash_import_service, "upsert_igdb_game", lambda _db, _g: media)
        mp.setattr(
            stash_import_service,
            "_create_pending_from_row",
            lambda *_a, **_k: None,
        )
        mp.setattr(
            stash_import_service.backend_service,
            "upsert_tracking_entry",
            lambda *_a, **_k: None,
        )
        out = stash_import_service.import_stash_batch(
            db,
            StashImportBatchRequest(
                username="tester",
                entries=[
                    StashImportEntryPayload(
                        sourceFile="stashPlaying.csv",
                        title="Dead Cells",
                        imageUrl="https://images.igdb.com/igdb/image/upload/t_cover_big/co7jfv.webp",
                        flags=["doing"],
                    ),
                    StashImportEntryPayload(
                        sourceFile="missing.csv",
                        title="Unknown Game XYZ",
                        flags=["watchlist"],
                    ),
                ],
            ),
            igdb_client=client,
        )

    assert out.imported == 1
    assert out.pending == 1
    assert out.skipped == 0
    assert len(out.errors) == 1
    db.commit.assert_called_once()
