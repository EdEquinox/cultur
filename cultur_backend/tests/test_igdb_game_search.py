from __future__ import annotations

import os
from pathlib import Path

import pytest

from app.igdb_client import IgdbClient, _games_filter_where_clause


def test_popular_section_filter_requires_hypes() -> None:
    clause = _games_filter_where_clause(
        section="popular",
        platform_ids=(),
        genre_ids=(),
        game_mode_ids=(),
        player_perspective_ids=(),
        game_type_id=None,
    )
    assert "hypes > 0" in clause


@pytest.mark.skipif(
    not os.environ.get("IGDB_CLIENT_ID") or not os.environ.get("IGDB_CLIENT_SECRET"),
    reason="IGDB credentials required",
)
def test_fetch_games_text_search_finds_low_hype_title() -> None:
    env_path = Path(__file__).resolve().parents[1] / ".env"
    if env_path.is_file():
        for line in env_path.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())

    client = IgdbClient(
        client_id=os.environ["IGDB_CLIENT_ID"],
        client_secret=os.environ["IGDB_CLIENT_SECRET"],
    )
    query = "Agatha Christie - The ABC Murders"
    games = client.fetch_games(section="popular", query=query, limit=20)
    titles = {g.title.casefold() for g in games}
    assert any("abc murders" in t for t in titles)

    url_hit = client.fetch_games(
        section="popular",
        query="https://www.igdb.com/games/agatha-christie-the-abc-murders--1",
        limit=5,
    )
    assert len(url_hit) >= 1
    assert url_hit[0].external_id == "17470"


@pytest.mark.skipif(
    not os.environ.get("IGDB_CLIENT_ID") or not os.environ.get("IGDB_CLIENT_SECRET"),
    reason="IGDB credentials required",
)
def test_fetch_game_by_slug_resolves_extended_edition() -> None:
    env_path = Path(__file__).resolve().parents[1] / ".env"
    if env_path.is_file():
        for line in env_path.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())

    client = IgdbClient(
        client_id=os.environ["IGDB_CLIENT_ID"],
        client_secret=os.environ["IGDB_CLIENT_SECRET"],
    )
    slug = "age-of-mythology-extended-edition"
    game = client.fetch_game_by_slug_resolved(slug)
    assert game is not None
    assert game.external_id == "9902"
    assert "extended edition" in game.title.casefold()

    url_hit = client.fetch_games(
        section="popular",
        query="https://www.igdb.com/games/age-of-mythology-extended-edition",
        limit=5,
    )
    assert len(url_hit) >= 1
    assert url_hit[0].external_id == "9902"
