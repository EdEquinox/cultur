from app.stash_scraper import (
    _parse_collection_page,
    _parse_library_tab,
    _parse_rating,
    _parse_reviews_page,
    parse_collection_paths_json,
)


def test_parse_collection_page_extracts_titles() -> None:
    html = """
    <div class="games-list__item">
      <img class="games-list__item-image" data-src="//cdn.example/cover.jpg" />
      <h3 class="games-list__item-name">Hollow Knight</h3>
    </div>
    """
    rows = _parse_collection_page(html, collection_key="prioridades")
    assert len(rows) == 1
    assert rows[0].title == "Hollow Knight"
    assert rows[0].source_file == "stashprioridades.csv"
    assert rows[0].image_url == "https://cdn.example/cover.jpg"


def test_parse_reviews_page_extracts_rating_and_text() -> None:
    html = """
    <div class="recent-review p-0">
      <img class="recent-review__image" src="/img.jpg" />
      <div class="font-semibold">Celeste</div>
      <span class="game__review-rating">9.5 / 10</span>
      <p class="review-text">Great platformer.</p>
    </div>
    """
    rows = _parse_reviews_page(html)
    assert len(rows) == 1
    assert rows[0].title == "Celeste"
    assert rows[0].rating == 9.5
    assert rows[0].review == "Great platformer."
    assert rows[0].source_file == "stashReviews.csv"


def test_parse_library_tab_want_games() -> None:
    html = """
    <div class="tab-panel">
      <div class="games-list__item">
        <span class="games-list__item-name">Stardew Valley</span>
      </div>
    </div>
    """
    rows = _parse_library_tab(html, source_file="stashGames.csv", category="Want")
    assert len(rows) == 1
    assert rows[0].title == "Stardew Valley"
    assert rows[0].category == "Want"


def test_parse_rating_normalizes_percent_scale() -> None:
    assert _parse_rating("95") == 9.5
    assert _parse_rating("8.0") == 8.0
    assert _parse_rating("") is None


def test_parse_collection_paths_json_defaults_when_empty() -> None:
    paths = parse_collection_paths_json("")
    assert len(paths) >= 1
    assert paths[0].key
