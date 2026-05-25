from __future__ import annotations

from datetime import date

from app.services.catalog_service import _episode_subtitle_from_teaser
from app.tmdb_client import TmdbClient, TmdbTvEpisodeTeaser, _coerce_optional_int


def test_coerce_optional_int_accepts_float_and_string() -> None:
    assert _coerce_optional_int(1) == 1
    assert _coerce_optional_int(2.0) == 2
    assert _coerce_optional_int("3") == 3
    assert _coerce_optional_int(None) is None


def test_parse_tv_episode_teaser_coerces_season_episode() -> None:
    client = TmdbClient(api_key="test", language="en-US")
    teaser = client._parse_tv_episode_teaser(
        {
            "name": "Pilot",
            "air_date": "2026-05-01",
            "season_number": 1.0,
            "episode_number": "2",
        },
    )
    assert teaser is not None
    assert teaser.season_number == 1
    assert teaser.episode_number == 2
    assert _episode_subtitle_from_teaser(teaser) == "S1E2 · Pilot"


def test_episode_subtitle_fallback_to_name_only() -> None:
    teaser = TmdbTvEpisodeTeaser(
        name="Season Finale",
        air_date="2026-12-20",
        season_number=None,
        episode_number=None,
    )
    assert _episode_subtitle_from_teaser(teaser) == "Season Finale"


def test_episode_subtitle_fallback_to_air_date() -> None:
    teaser = TmdbTvEpisodeTeaser(
        name=None,
        air_date="2026-12-20",
        season_number=None,
        episode_number=None,
    )
    assert _episode_subtitle_from_teaser(teaser, air_date=date(2026, 12, 20)) == "20 Dec 2026"
