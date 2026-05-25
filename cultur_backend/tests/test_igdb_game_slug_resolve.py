from __future__ import annotations

from app.igdb_client import (
    legacy_game_slug_candidates,
    title_to_igdb_slug_candidates,
)


def test_legacy_game_slug_candidates_strips_double_suffix() -> None:
    assert legacy_game_slug_candidates("agatha-christie-the-abc-murders--1") == [
        "agatha-christie-the-abc-murders--1",
        "agatha-christie-the-abc-murders",
    ]


def test_title_to_igdb_slug_candidates_from_display_title() -> None:
    slugs = title_to_igdb_slug_candidates("Agatha Christie - The ABC Murders")
    assert "agatha-christie-the-abc-murders" in slugs
    assert "agatha-christie-the-abc-murders--1" in slugs


def test_query_suggests_edition() -> None:
    from app.igdb_client import _query_suggests_edition

    assert _query_suggests_edition("Age of Mythology: Extended Edition")
    assert not _query_suggests_edition("Age of Mythology")
