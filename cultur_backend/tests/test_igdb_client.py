from __future__ import annotations

from app.igdb_client import (
    IGDB_COVER_SIZE,
    STASH_COLLECTION_TO_CULTUR_FLAGS,
    STASH_STATUS_TO_CULTUR_FLAGS,
    IgdbClient,
    IgdbCompanyCatalogGame,
    IgdbGame,
    igdb_cover_url,
    igdb_screenshot_urls,
    upgrade_igdb_cover_url,
    _game_from_row,
    _first_franchise_from_row,
    _game_ids_from_involved_company_rows,
    _games_filter_where_clause,
    _involved_companies_from_row,
    _merge_company_catalog_games,
)


def test_cover_image_id_from_stash_url() -> None:
    url = "https://images.igdb.com/igdb/image/upload/t_cover_big/co7jfv.webp"
    assert IgdbClient.cover_image_id_from_url(url) == "co7jfv"
    assert IgdbClient.cover_image_id_from_url(None) is None


def test_stash_status_maps_to_cultur_flags() -> None:
    assert STASH_STATUS_TO_CULTUR_FLAGS["Playing"] == ("doing",)
    assert STASH_STATUS_TO_CULTUR_FLAGS["Beaten"] == ("watched",)
    assert STASH_COLLECTION_TO_CULTUR_FLAGS["fisical"] == ("collected",)


def test_game_from_row_builds_cover_and_subtitle() -> None:
    game = _game_from_row(
        {
            "id": 1942,
            "name": "The Witcher 3: Wild Hunt",
            "summary": "Open world RPG.",
            "first_release_date": 1431993600,
            "total_rating": 93.2,
            "cover": {"image_id": "co1wyy"},
            "platforms": [{"name": "PC"}, {"name": "PlayStation 4"}],
            "genres": [{"name": "Role-playing (RPG)"}],
        },
    )
    assert game.external_id == "1942"
    assert game.title == "The Witcher 3: Wild Hunt"
    assert "2015" in (game.subtitle or "")
    assert "IGDB 93.2" in (game.subtitle or "")
    assert game.image_url is not None
    assert "co1wyy" in game.image_url


def test_cover_url_upgrades_thumb_to_cover_big_2x() -> None:
    url = igdb_cover_url({"url": "//images.igdb.com/igdb/image/upload/t_thumb/co1.jpg"})
    assert url is not None
    assert url.startswith("https://")
    assert f"/{IGDB_COVER_SIZE}/co1." in url


def test_cover_url_prefers_image_id_over_thumb_url() -> None:
    url = igdb_cover_url(
        {
            "image_id": "co1wyy",
            "url": "//images.igdb.com/igdb/image/upload/t_thumb/co1wyy.jpg",
        },
    )
    assert url is not None
    assert f"/{IGDB_COVER_SIZE}/co1wyy.jpg" in url


def test_upgrade_igdb_cover_url_from_stash_export() -> None:
    stash = "https://images.igdb.com/igdb/image/upload/t_cover_big/co7jfv.webp"
    upgraded = upgrade_igdb_cover_url(stash)
    assert upgraded is not None
    assert f"/{IGDB_COVER_SIZE}/co7jfv.webp" in upgraded


def test_detail_row_includes_screenshot_gallery() -> None:
    game = _game_from_row(
        {
            "id": 1,
            "name": "Test",
            "screenshots": [
                {"image_id": "sc1"},
                {"url": "//images.igdb.com/igdb/image/upload/t_screenshot_med/sc2.jpg"},
            ],
        },
        include_detail=True,
    )
    gallery = game.metadata.get("galleryUrls")
    assert isinstance(gallery, list)
    assert len(gallery) == 2
    assert all("t_screenshot_huge_2x" in str(u) for u in gallery)


def test_first_franchise_from_row_prefers_main_franchise() -> None:
    series = _first_franchise_from_row(
        {
            "franchise": {"id": 10, "name": "Red Dead", "slug": "red-dead"},
            "franchises": [{"id": 99, "name": "Other"}],
        },
    )
    assert series == {
        "id": "10",
        "name": "Red Dead",
        "slug": "red-dead",
        "kind": "franchise",
    }


def test_first_franchise_from_row_falls_back_to_collection() -> None:
    series = _first_franchise_from_row(
        {
            "collection": {"id": 5, "name": "Halo", "slug": "halo"},
        },
    )
    assert series is not None
    assert series["name"] == "Halo"
    assert series["kind"] == "collection"


def test_game_ids_from_involved_company_rows() -> None:
    ids = _game_ids_from_involved_company_rows(
        [
            {"game": 101},
            {"game": {"id": 202}},
            {"game": 101},
            {},
        ],
    )
    assert ids == [101, 202, 101]


def test_involved_companies_split_publishers_and_developers() -> None:
    publishers, developers = _involved_companies_from_row(
        {
            "involved_companies": [
                {
                    "publisher": True,
                    "developer": False,
                    "company": {"id": 10, "name": "CD Projekt Red"},
                },
                {
                    "publisher": False,
                    "developer": True,
                    "company": {"id": 10, "name": "CD Projekt Red"},
                },
                {
                    "publisher": True,
                    "developer": True,
                    "company": {"id": 20, "name": "Bandai Namco"},
                },
            ],
        },
    )
    assert [c.name for c in publishers] == ["Bandai Namco", "CD Projekt Red"]
    assert [c.name for c in developers] == ["Bandai Namco", "CD Projekt Red"]
    assert {c.external_id for c in developers} == {"10", "20"}


def test_detail_row_parses_involved_companies() -> None:
    game = _game_from_row(
        {
            "id": 1,
            "name": "Test",
            "involved_companies": [
                {
                    "publisher": True,
                    "developer": False,
                    "company": {"id": 99, "name": "Nintendo"},
                },
            ],
        },
        include_detail=True,
    )
    assert len(game.publishers) == 1
    assert game.publishers[0].name == "Nintendo"
    assert game.developers == ()


def test_games_filter_where_clause_omits_sort_for_search() -> None:
    clause = _games_filter_where_clause(
        section="popular",
        platform_ids=(),
        genre_ids=(),
        game_mode_ids=(),
        player_perspective_ids=(),
        game_type_id=None,
        include_section_sort=False,
    )
    assert "sort" not in clause.lower()
    assert "hypes > 0" in clause
    assert "version_parent = null" in clause


def test_games_filter_where_clause_includes_sort_for_browse() -> None:
    clause = _games_filter_where_clause(
        section="popular",
        platform_ids=(),
        genre_ids=(),
        game_mode_ids=(),
        player_perspective_ids=(),
        game_type_id=None,
    )
    assert "sort hypes desc" in clause


def test_fake_igdb_game_dataclass() -> None:
    game = IgdbGame(
        external_id="1",
        title="Test",
        subtitle=None,
        description=None,
        image_url=None,
        metadata={},
    )
    assert game.external_id == "1"


def test_merge_company_catalog_games_dedupes_same_title() -> None:
    def entry(eid: str, rating: float) -> IgdbCompanyCatalogGame:
        return IgdbCompanyCatalogGame(
            game=IgdbGame(
                external_id=eid,
                title="Grand Theft Auto V Enhanced",
                subtitle=None,
                description=None,
                image_url=None,
                metadata={"igdbRating": rating, "firstReleaseDate": "2022"},
            ),
            roles=("Publisher",),
        )

    merged = _merge_company_catalog_games([entry("100", 90.0), entry("200", 80.0)])
    assert len(merged) == 1
    assert merged[0].game.external_id == "100"
    assert merged[0].roles == ("Publisher",)
