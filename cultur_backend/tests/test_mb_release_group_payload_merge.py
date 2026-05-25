from app.services.music_catalog_service import _merge_mb_release_group_provider_payload


def test_merge_preserves_tracklist_and_artists_on_light_upsert() -> None:
    existing = {
        "artistName": "Radiohead",
        "artists": [{"id": "a1b2", "name": "Radiohead"}],
        "tracklist": [{"position": "1", "title": "Airbag", "duration": "4:44"}],
    }
    incoming = {
        "mbid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "musicbrainzKind": "release-group",
        "artistName": None,
        "year": 1997,
    }
    merged = _merge_mb_release_group_provider_payload(existing, incoming)
    assert merged["artistName"] == "Radiohead"
    assert merged["artists"] == existing["artists"]
    assert merged["tracklist"] == existing["tracklist"]
    assert merged["year"] == 1997
