from __future__ import annotations

from app.igdb_client import legacy_event_slug_candidates


def test_legacy_event_slug_candidates_strips_stash_suffix() -> None:
    candidates = legacy_event_slug_candidates("yokaze-night-2026-dot-05-dot-14-ctulv")
    assert candidates[0] == "yokaze-night-2026-dot-05-dot-14-ctulv"
    assert "yokaze-night-2026-dot-05-dot-14" in candidates


def test_legacy_event_slug_candidates_keeps_igdb_slug() -> None:
    candidates = legacy_event_slug_candidates("yokaze-night-2026-dot-05-dot-14")
    assert candidates == ["yokaze-night-2026-dot-05-dot-14"]
