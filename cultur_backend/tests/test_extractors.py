from app.extractors import (
    decode_media_ref,
    extract_csrf_token,
    extract_discover_sections,
    extract_home_sections,
    extract_list_summaries,
    extract_media_cards,
    extract_media_detail,
)


def test_extract_csrf_token() -> None:
    html = """
    <form method="post">
      <input type="hidden" name="csrfmiddlewaretoken" value="abc123" />
    </form>
    """

    assert extract_csrf_token(html) == "abc123"


def test_extract_media_cards() -> None:
    html = """
    <div class="search-result-card">
      <a href="/details/tmdb/movie/550/fight-club" title="Fight Club">
        <img src="/images/fight-club.jpg" alt="Fight Club" />
      </a>
      <p>Completed 1999 • 139 min</p>
    </div>
    <div class="search-result-card">
      <a href="/details/tmdb/tv/1399/game-of-thrones">
        <img src="/images/got.jpg" alt="Game of Thrones" />
      </a>
      <p>In progress 8 seasons</p>
    </div>
    """

    cards = extract_media_cards(html, "https://yamtrack.example.com")

    assert len(cards) == 2
    assert cards[0]["title"] == "Fight Club"
    assert cards[0]["status"] == "Completed"
    assert cards[0]["imageUrl"] == "https://yamtrack.example.com/images/fight-club.jpg"
    assert cards[0]["mediaType"] == "movie"
    assert cards[0]["mediaTypeLabel"] == "Movies"
    assert decode_media_ref(cards[0]["mediaRef"]) == "/details/tmdb/movie/550/fight-club"


def test_extract_home_sections() -> None:
    html = """
    <section class="space-y-4">
      <div class="mb-2 flex items-start justify-between gap-3">
        <h3 class="home-row-heading flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <span class="home-row-heading-title">In Progress</span>
          <span class="home-row-heading-detail">Not Caught Up</span>
          <button type="button">
            <span class="home-row-heading-sort-label">Episode Air Date</span>
          </button>
        </h3>
      </div>
      <div data-home-row="true">
        <a href="/details/tmdb/tv/204490/criminal-record" title="Criminal Record">
          <img src="/images/criminal-record.jpg" alt="Criminal Record" />
        </a>
        <p>In progress 2024</p>
      </div>
    </section>
    """

    sections = extract_home_sections(html, "https://yamtrack.example.com")

    assert len(sections) == 1
    assert sections[0]["title"] == "TV"
    assert sections[0]["subtitle"] == "In Progress • Not Caught Up • Episode Air Date"
    assert sections[0]["mediaType"] == "tv"


def test_extract_discover_sections() -> None:
    html = """
    <section id="discover-row-trending_right_now" data-discover-row-key="trending_right_now">
      <div>
        <h2>Trending Right Now</h2>
        <p>What everyone has been watching this week.</p>
      </div>
      <div class="media-grid">
        <div class="search-result-card">
          <a href="/details/tmdb/movie/1325734/the-drama" title="The Drama">
            <img src="/images/the-drama.jpg" alt="The Drama" />
          </a>
          <p>April 3, 2026</p>
        </div>
      </div>
    </section>
    """

    sections = extract_discover_sections(
        html,
        "https://yamtrack.example.com",
        selected_media_type="movie",
    )

    assert len(sections) == 1
    assert sections[0]["title"] == "Trending Right Now"
    assert sections[0]["subtitle"] == "What everyone has been watching this week."
    assert sections[0]["mediaType"] == "movie"
    assert sections[0]["items"][0]["title"] == "The Drama"


def test_extract_list_summaries() -> None:
    html = """
    <section>
      <a href="/list/42">Weekend Picks</a>
      <p>7 items • Shared with friends</p>
    </section>
    """

    lists = extract_list_summaries(html, "https://yamtrack.example.com")

    assert lists[0]["title"] == "Weekend Picks"
    assert lists[0]["itemsCount"] == 7


def test_extract_media_detail() -> None:
    html = """
    <html>
      <head><title>Fight Club - Yamtrack</title></head>
      <body>
        <img src="/images/fight-club-banner.jpg" />
        <dl>
          <dt>Status</dt>
          <dd>Completed</dd>
          <dt>Source</dt>
          <dd>TMDB</dd>
        </dl>
        <p>A dark comedy-drama about identity and consumerism.</p>
      </body>
    </html>
    """

    detail = extract_media_detail(
        html,
        "https://yamtrack.example.com",
        path="/details/tmdb/movie/550/fight-club",
    )

    assert detail["title"] == "Fight Club"
    assert detail["metadata"]["Status"] == "Completed"
    assert detail["canUpdateProgress"] is True
    assert detail["imageUrl"] == "https://yamtrack.example.com/images/fight-club-banner.jpg"
