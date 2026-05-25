from xml.etree.ElementTree import Element, SubElement

from app.bgg_client import (
    BggClient,
    BggCollectionRow,
    _boardgame_from_hot_item,
    _boardgame_from_thing,
    _collection_row_from_item,
    _merge_collection_row,
    build_tracking_notes,
)


def test_boardgame_from_hot_item_parses_stub_fields() -> None:
    item = Element("item", {"id": "174430", "rank": "1"})
    SubElement(item, "name", {"value": "Gloomhaven"})
    SubElement(item, "yearpublished", {"value": "2017"})
    SubElement(item, "thumbnail").text = "https://example.com/thumb.jpg"

    game = _boardgame_from_hot_item(item)

    assert game.external_id == "174430"
    assert game.title == "Gloomhaven"
    assert game.image_url == "https://example.com/thumb.jpg"
    assert game.metadata["bggRank"] == "1"


def test_bgg_client_requires_token() -> None:
    try:
        BggClient(api_token="")
    except Exception as exc:
        assert "token" in str(exc).lower()
    else:
        raise AssertionError("expected BggError for empty token")


def test_boardgame_from_thing_parses_core_fields() -> None:
    item = Element("item", {"id": "174430", "type": "boardgame"})
    SubElement(item, "name", {"type": "primary", "value": "Gloomhaven"})
    SubElement(item, "yearpublished", {"value": "2017"})
    SubElement(item, "image").text = "https://example.com/gloomhaven.jpg"
    SubElement(item, "description").text = "A cooperative campaign game."

    game = _boardgame_from_thing(item)

    assert game.external_id == "174430"
    assert game.title == "Gloomhaven"
    assert game.subtitle == "2017"
    assert game.image_url == "https://example.com/gloomhaven.jpg"
    assert "cooperative" in (game.description or "")
    assert game.metadata["bggId"] == "174430"


def test_merge_collection_row_unions_flags_and_ratings() -> None:
    merged: dict[str, BggCollectionRow] = {}
    _merge_collection_row(
        merged,
        BggCollectionRow(
            external_id="1",
            title="Catan",
            flags=frozenset({"watchlist"}),
            bgg_rating=7.0,
        ),
    )
    _merge_collection_row(
        merged,
        BggCollectionRow(
            external_id="1",
            title="Catan",
            flags=frozenset({"collected"}),
            bgg_rating=8.5,
        ),
    )
    row = merged["1"]
    assert row.flags == frozenset({"watchlist", "collected"})
    assert row.bgg_rating == 8.5


def test_collection_row_maps_wanttoplay_to_watchlist() -> None:
    item = Element("item", {"objectid": "2"})
    SubElement(item, "name").text = "Wingspan"
    status = SubElement(item, "status")
    status.set("wanttoplay", "1")

    row = _collection_row_from_item(item)

    assert row is not None
    assert row.flags == frozenset({"watchlist"})


def test_collection_row_maps_bgg_flags() -> None:
    item = Element("item", {"objectid": "1"})
    SubElement(item, "name").text = "Catan"
    status = SubElement(item, "status")
    status.set("wishlist", "1")
    status.set("wanttobuy", "1")
    status.set("own", "1")
    status.set("wishlistpriority", "2")

    row = _collection_row_from_item(item)

    assert row is not None
    assert row.external_id == "1"
    assert row.flags == frozenset({"watchlist", "buy", "collected", "priority"})
    assert build_tracking_notes(row.flags) == "[cult.flags]buy,collected,priority,watchlist"
