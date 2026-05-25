from __future__ import annotations

from app.musicboard_scraper import MusicboardScrapedRow
from app.services.musicboard_scrape_import_service import _scraped_row_to_payload


def test_scraped_row_to_payload_maps_flags_and_review_target() -> None:
    row = MusicboardScrapedRow(
        source_file="musicboardLater.csv",
        source_key="builtin:wantlist",
        title="OK Computer",
        artist="Radiohead",
        image_url="https://example.com/cover.jpg",
    )
    payload = _scraped_row_to_payload(row)
    assert payload.title == "OK Computer"
    assert payload.artist == "Radiohead"
    assert "watchlist" in payload.flags

    review_row = MusicboardScrapedRow(
        source_file="musicboardReviews.csv",
        source_key="builtin:reviews",
        title="Track name",
        review_target="OK Computer",
        artist="Radiohead",
        rating=4.0,
        review="Great album",
    )
    review_payload = _scraped_row_to_payload(review_row)
    assert review_payload.title == "OK Computer"
    assert review_payload.score == 8.0
