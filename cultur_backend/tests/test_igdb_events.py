from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from sqlalchemy.orm import Session

from app.backend_models import StashGameEventRow
from app.config import load_settings
from app.database import DatabaseManager
from app.igdb_client import IgdbClient, IgdbEvent, IgdbEventDetail, IgdbGame
from app.services.stash_events_service import (
    get_stash_game_event_detail,
    list_stash_game_events_cached,
    sync_stash_events_from_remote,
)


@pytest.fixture
def db_session(tmp_path, monkeypatch: pytest.MonkeyPatch) -> Session:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("SERVER_API_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv(
        "SERVER_API_DATABASE_URL",
        f"sqlite:///{(tmp_path / 'data' / 'test.sqlite3').resolve()}",
    )
    settings = load_settings()
    dbm = DatabaseManager(settings)
    dbm.initialize()
    session = dbm.session()
    try:
        yield session
    finally:
        session.close()


def _sample_event() -> IgdbEvent:
    from datetime import UTC, datetime

    return IgdbEvent(
        external_id="1105",
        slug="yokaze-night-2026-dot-05-dot-14-ctulv",
        title="Yokaze Night 2026.05.14",
        starts_at=datetime(2026, 5, 14, 11, 0, tzinfo=UTC),
        ends_at=None,
        description="Showcase",
        image_url="https://images.igdb.com/igdb/image/upload/t_screenshot_huge_2x/el14c.jpg",
        game_ids=(1, 2),
    )


def _sample_detail() -> IgdbEventDetail:
    event = _sample_event()
    game = IgdbGame(
        external_id="347432",
        title="On Donuts and Holes",
        subtitle="2026",
        description=None,
        image_url="https://images.igdb.com/igdb/image/upload/t_cover_big_2x/coc29l.webp",
        metadata={"slug": "on-donuts-and-holes", "firstReleaseDate": "2026", "firstReleaseDateUnix": 1798675200},
    )
    return IgdbEventDetail(
        external_id=event.external_id,
        slug=event.slug,
        title=event.title,
        starts_at=event.starts_at,
        ends_at=event.ends_at,
        description=event.description,
        image_url=event.image_url,
        game_ids=event.game_ids,
        games=(game,),
    )


def test_sync_events_from_igdb(db_session: Session, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    settings = load_settings()
    igdb = MagicMock(spec=IgdbClient)
    igdb.fetch_all_events.side_effect = lambda **kwargs: (
        [_sample_event()] if kwargs.get("window") == "previous" else []
    )

    count = sync_stash_events_from_remote(db_session, settings, igdb)
    db_session.commit()

    assert count == 1
    row = db_session.get(StashGameEventRow, "yokaze-night-2026-dot-05-dot-14-ctulv")
    assert row is not None
    assert row.title.startswith("Yokaze")
    assert row.description == "Showcase"
    assert "igdb.com/events" in row.stash_url


def test_event_detail_returns_games_with_media_id(
    db_session: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    settings = load_settings()
    igdb = MagicMock(spec=IgdbClient)
    igdb.fetch_event_detail_resolved.return_value = _sample_detail()

    payload = get_stash_game_event_detail(
        db_session,
        settings,
        slug="yokaze-night-2026-dot-05-dot-14-ctulv",
        igdb_client=igdb,
    )

    assert payload.slug == "yokaze-night-2026-dot-05-dot-14-ctulv"
    assert len(payload.items) == 1
    assert payload.items[0].mediaId is not None
    assert payload.items[0].title == "On Donuts and Holes"


def test_list_events_uses_cache(db_session: Session, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SERVER_API_SECRET_KEY", "test-secret")
    monkeypatch.setenv("STASH_EVENTS_CACHE_TTL_SECONDS", "3600")
    settings = load_settings()
    from datetime import UTC, datetime, timedelta

    db_session.add(
        StashGameEventRow(
            slug="cached-event",
            title="Cached Event",
            description="Cached description",
            starts_at=datetime.now(tz=UTC) - timedelta(days=30),
            stash_url="https://www.igdb.com/events/cached-event",
        ),
    )
    from app.backend_models import StashEventsSyncMeta

    db_session.add(
        StashEventsSyncMeta(
            id="default",
            last_synced_at=datetime.now(tz=UTC),
            event_count=1,
        ),
    )
    db_session.commit()

    igdb = MagicMock(spec=IgdbClient)
    payload = list_stash_game_events_cached(
        db_session,
        settings,
        window="previous",
        igdb_client=igdb,
    )
    igdb.fetch_all_events.assert_not_called()
    assert payload.items[0].slug == "cached-event"
