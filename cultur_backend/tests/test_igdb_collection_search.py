from __future__ import annotations

from unittest.mock import MagicMock

from app.igdb_client import (
    IgdbClient,
    IgdbGame,
    _collection_title_match_score,
    _merge_games_with_collection_bundles,
)


def _game(title: str, ext_id: str) -> IgdbGame:
    return IgdbGame(
        external_id=ext_id,
        title=title,
        subtitle=None,
        description=None,
        image_url=None,
        metadata={},
    )


def test_collection_title_match_score_exact() -> None:
    assert _collection_title_match_score("halo", "Halo") >= 0.99


def test_merge_games_with_collection_bundles_prepends_on_strong_match() -> None:
    client = MagicMock(spec=IgdbClient)
    client.search_collections.return_value = [
        {"id": 1, "name": "Crysis Trilogy", "games": [10, 11]},
    ]
    client._fetch_games_by_ids.return_value = [
        _game("Crysis", "10"),
        _game("Crysis 2", "11"),
    ]

    merged = _merge_games_with_collection_bundles(
        client,
        [_game("Other Game", "99")],
        "Crysis Trilogy",
        cap=10,
    )
    assert merged[0].external_id == "10"
    assert any(g.external_id == "99" for g in merged)


def test_igdb_collection_slug_from_url() -> None:
    from app.igdb_client import igdb_collection_slug_from_url

    assert (
        igdb_collection_slug_from_url(
            "https://www.igdb.com/collections/the-elder-scrolls-anthology",
        )
        == "the-elder-scrolls-anthology"
    )
