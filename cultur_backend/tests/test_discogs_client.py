from datetime import date

from app.discogs_client import (
    DiscogsClient,
    DiscogsMasterSummary,
    DiscogsReleaseSummary,
    _master_from_artist_row,
    _master_from_search_row,
    _parse_discogs_videos,
    _release_from_artist_row,
    _release_from_search_row,
    _youtube_video_id,
    discogs_master_external_id,
    parse_discogs_release_date,
)


def test_parse_discogs_release_date_iso() -> None:
    assert parse_discogs_release_date("2025-03-15") == date(2025, 3, 15)


def test_parse_discogs_release_date_year_only() -> None:
    assert parse_discogs_release_date(2024) == date(2024, 1, 1)


def test_youtube_video_id_from_discogs_uri() -> None:
    assert _youtube_video_id("https://www.youtube.com/watch?v=te2jJncBVG4") == "te2jJncBVG4"
    assert _youtube_video_id("https://youtu.be/abc123def45") == "abc123def45"


def test_master_from_search_row_strips_artist_prefix() -> None:
    row = {
        "id": 100,
        "type": "master",
        "title": "Bo Burnham - Inside",
        "year": 2021,
        "artist": "Bo Burnham",
        "uri": "https://www.discogs.com/master/100",
        "community": {"want": 42, "have": 100},
    }
    master = _master_from_search_row(row)
    assert master is not None
    assert master.discogs_id == 100
    assert master.title == "Inside"
    assert master.artist_name == "Bo Burnham"
    assert master.metadata["communityWant"] == 42
    assert master.metadata["communityHave"] == 100
    assert discogs_master_external_id(100) == "master-100"


def test_master_from_artist_row_skips_pressings() -> None:
    assert _master_from_artist_row({"id": 1, "type": "release", "title": "EP"}) is None
    master = _master_from_artist_row(
        {
            "id": 173765,
            "type": "master",
            "title": "Curb",
            "year": 1996,
            "artist": "Nickelback",
            "main_release": 3128432,
        },
    )
    assert master is not None
    assert master.title == "Curb"
    assert master.main_release_id == 3128432


def test_release_from_search_row_standalone_has_no_master() -> None:
    row = {
        "id": 36881731,
        "type": "release",
        "title": "Xtinto - Em Sonhos, É Sabido, Não Se Morre",
        "year": 2026,
        "artist": "Xtinto",
        "uri": "https://www.discogs.com/release/36881731",
    }
    release = _release_from_search_row(row)
    assert release is not None
    assert release.metadata.get("discogsMasterId") is None


def test_release_from_search_row_with_master_id() -> None:
    row = {
        "id": 249504,
        "type": "release",
        "title": "Never Gonna Give You Up",
        "master_id": 96559,
        "year": 1987,
        "artist": "Rick Astley",
    }
    release = _release_from_search_row(row)
    assert release is not None
    assert release.metadata.get("discogsMasterId") == 96559


def test_search_albums_merges_masters_and_standalone_releases(monkeypatch) -> None:
    class FakeClient(DiscogsClient):
        def __init__(self) -> None:
            pass

        def search_masters(self, query: str, *, page: int = 1, per_page: int = 25):
            return [
                DiscogsMasterSummary(
                    discogs_id=1,
                    title="Inside",
                    artist_name="Bo Burnham",
                ),
            ]

        def search_releases(self, query: str, *, page: int = 1, per_page: int = 25):
            return [
                DiscogsReleaseSummary(
                    discogs_id=99,
                    title="Inside",
                    metadata={"discogsMasterId": 1},
                ),
                DiscogsReleaseSummary(
                    discogs_id=36881731,
                    title="Em Sonhos",
                    metadata={},
                ),
            ]

    client = FakeClient()
    results = client.search_albums("test", per_page=10)
    assert len(results) == 2
    assert results[0].discogs_id == 1
    assert isinstance(results[0], DiscogsMasterSummary)
    assert results[1].discogs_id == 36881731


def test_release_from_artist_row_skips_non_release_type() -> None:
    assert _release_from_artist_row({"id": 1, "type": "master", "title": "Album"}) is None


def test_release_from_artist_row_standalone() -> None:
    release = _release_from_artist_row(
        {
            "id": 1665711,
            "type": "release",
            "title": "Bo Fo Sho",
            "artist": "Bo Burnham",
            "year": 2008,
            "format": "File, MP3, EP",
            "role": "Main",
        },
    )
    assert release is not None
    assert release.discogs_id == 1665711
    assert release.title == "Bo Fo Sho"
    assert release.metadata.get("discogsMasterId") is None


def test_fetch_artist_discography_merges_masters_and_standalone(monkeypatch) -> None:
    pages = [
        {
            "pagination": {"pages": 2, "page": 1},
            "releases": [
                {
                    "id": 2422033,
                    "type": "master",
                    "title": "Inside (The Songs)",
                    "artist": "Bo Burnham",
                    "year": 2021,
                    "role": "Main",
                    "main_release": 1,
                },
                {
                    "id": 1665711,
                    "type": "release",
                    "title": "Bo Fo Sho",
                    "artist": "Bo Burnham",
                    "year": 2008,
                    "format": "File, MP3, EP",
                    "role": "Main",
                },
                {
                    "id": 999,
                    "type": "release",
                    "title": "That Funny Feeling",
                    "artist": "Phoebe Bridgers",
                    "year": 2021,
                    "role": "Appearance",
                },
            ],
        },
        {
            "pagination": {"pages": 2, "page": 2},
            "releases": [
                {
                    "id": 287996,
                    "type": "master",
                    "title": "Words Words Words",
                    "artist": "Bo Burnham",
                    "year": 2010,
                    "role": "Main",
                    "main_release": 2,
                },
            ],
        },
    ]

    class FakeClient(DiscogsClient):
        def __init__(self) -> None:
            pass

        def _get(self, path: str, *, params: dict | None = None) -> dict:
            return pages[int(params["page"]) - 1]

    client = FakeClient()
    rows = client.fetch_artist_discography_all(1376508)
    assert len(rows) == 3
    assert rows[0].title == "Inside (The Songs)"
    assert rows[1].discogs_id == 1665711
    assert rows[2].title == "Words Words Words"


def test_parse_discogs_videos() -> None:
    rows = [
        {
            "title": "Official Video",
            "duration": 257,
            "uri": "https://www.youtube.com/watch?v=5K6-q2VqJdE",
        },
        {
            "description": "Not YouTube",
            "uri": "https://vimeo.com/123",
        },
    ]
    videos = _parse_discogs_videos(rows)
    assert len(videos) == 1
    assert videos[0]["title"] == "Official Video"
    assert videos[0]["subtitle"] == "4:17"
    assert videos[0]["url"] == "https://www.youtube.com/watch?v=5K6-q2VqJdE"
    assert videos[0]["imageUrl"] == "https://img.youtube.com/vi/5K6-q2VqJdE/hqdefault.jpg"
