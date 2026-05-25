from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.lastfm_client import LfmAlbumSearchResult, LastfmClient
from app.schemas import StashImportBatchRequest, StashImportEntryPayload
from app.services import musicboard_import_service


def _album(title: str, lastfm_id: str = "key-abc", artist: str = "Artist") -> LfmAlbumSearchResult:
    return LfmAlbumSearchResult(
        lastfm_id=lastfm_id,
        title=title,
        artist_name=artist,
    )


def test_merge_payload_entries_unions_flags() -> None:
    merged = musicboard_import_service._merge_payload_entries(
        [
            StashImportEntryPayload(
                sourceFile="musicboardLater.csv",
                title="OK Computer",
                artist="Radiohead",
                flags=["watchlist"],
            ),
            StashImportEntryPayload(
                sourceFile="musicboardFav.csv",
                title="OK Computer",
                artist="Radiohead",
                flags=["priority"],
            ),
        ],
    )
    assert len(merged) == 1
    row = next(iter(merged.values()))
    assert "watchlist" in row.flags
    assert "priority" in row.flags


def test_normalize_score() -> None:
    assert musicboard_import_service._normalize_score(4.5) == 9.0
    assert musicboard_import_service._normalize_score(8.0) == 8.0


def test_pick_best_title_match_prefers_exact() -> None:
    picked = musicboard_import_service._pick_best_title_match(
        "Parachutes",
        [
            _album("Parachutes", lastfm_id="match-1"),
            _album("Other", lastfm_id="other-1"),
        ],
        artist="Coldplay",
    )
    assert picked is not None
    assert picked.lastfm_id == "match-1"


def test_import_musicboard_batch_imports_and_pending() -> None:
    client = MagicMock(spec=LastfmClient)

    media = MagicMock()
    media.id = "media-1"
    media.title = "OK Computer"
    media.source = "lastfm"
    media.external_id = "lfm-album:key-abc"

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(musicboard_import_service, "upsert_lastfm_album", lambda _db, *, summary, **_: media)
        mp.setattr(
            musicboard_import_service,
            "_resolve_musicboard_album",
            lambda *_a, **_k: _album("OK Computer", artist="Radiohead"),
        )
        mp.setattr(musicboard_import_service.backend_service, "upsert_tracking_entry", lambda *_a, **_k: None)
        db = MagicMock()

        out = musicboard_import_service.import_musicboard_batch(
            db,
            StashImportBatchRequest(
                username="tester",
                entries=[
                    StashImportEntryPayload(
                        sourceFile="musicboardLater.csv",
                        title="OK Computer",
                        artist="Radiohead",
                        flags=["watchlist"],
                    ),
                    StashImportEntryPayload(
                        sourceFile="musicboardHistory.csv",
                        title="Unknown Album",
                        artist="Nobody",
                        flags=["watched"],
                    ),
                ],
            ),
            lastfm_client=client,
        )

    assert out.imported >= 1
    assert out.pending >= 0
