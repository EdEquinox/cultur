from __future__ import annotations

from app.musicbrainz_client import (
    MusicBrainzClient,
    _release_group_from_search_row,
    _release_summary_from_row,
    is_mb_release_group_external_id,
    mb_artist_person_id,
    mb_release_group_external_id,
    parse_mb_artist_person_id,
    parse_mb_release_date,
    parse_mb_release_group_external_id,
)


def test_parse_mb_release_date_year_only() -> None:
    assert parse_mb_release_date("1997") == parse_mb_release_date(1997)


def test_external_id_helpers() -> None:
    mbid = "1a2b3c4d-e5f6-4789-a012-3456789abcde"
    ext = mb_release_group_external_id(mbid)
    assert is_mb_release_group_external_id(ext)
    _, parsed = parse_mb_release_group_external_id(ext)
    assert parsed == mbid


def test_artist_person_id_roundtrip() -> None:
    mbid = "cc197bad-dc9c-440d-a5b5-d52ba2e14234"
    person = mb_artist_person_id(mbid)
    assert parse_mb_artist_person_id(person) == mbid


def test_release_group_from_search_row() -> None:
    row = {
        "id": "1a2b3c4d-e5f6-4789-a012-3456789abcde",
        "title": "OK Computer",
        "first-release-date": "1997-06-16",
        "artist-credit": [
            {"artist": {"id": "a1b2c3d4-e5f6-4789-a012-3456789abcde", "name": "Radiohead"}},
        ],
    }
    summary = _release_group_from_search_row(row)
    assert summary.title == "OK Computer"
    assert summary.artist_name == "Radiohead"
    assert summary.year == 1997


def test_release_summary_from_row() -> None:
    row = {
        "id": "22222222-3333-4444-5555-666666666666",
        "title": "OK Computer",
        "date": "1997",
        "country": "GB",
        "artist-credit": [{"artist": {"name": "Radiohead"}}],
        "media": [{"format": "CD"}],
    }
    summary = _release_summary_from_row(row)
    assert summary.country == "GB"
    assert "CD" in summary.format_types


def test_search_release_groups_parses_fixture(monkeypatch) -> None:
    fixture = {
        "release-groups": [
            {
                "id": "1a2b3c4d-e5f6-4789-a012-3456789abcde",
                "title": "Parachutes",
                "first-release-date": "2000",
                "artist-credit": [{"artist": {"name": "Coldplay"}}],
            },
        ],
    }

    class FakeResponse:
        status_code = 200

        @staticmethod
        def json() -> dict:
            return fixture

        text = ""

    def fake_get(*_a, **_k):
        return FakeResponse()

    monkeypatch.setattr("app.musicbrainz_client.httpx.get", fake_get)
    client = MusicBrainzClient(app_name="Test", contact="test@example.com")
    rows = client.search_release_groups('releasegroup:"Parachutes"', limit=5)
    assert len(rows) == 1
    assert rows[0].title == "Parachutes"
