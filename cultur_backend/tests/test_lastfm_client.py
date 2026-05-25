from app.lastfm_client import (
    LastfmClient,
    lfm_artist_person_id,
    parse_lfm_album_key_labels,
    parse_music_artist_person_id,
    _album_search_row,
    _best_image_url,
    _extract_album_search_rows,
    _artist_name_matches_query,
    album_match_key,
    is_lastfm_placeholder_image,
    lastfm_album_external_id,
    parse_lastfm_album_external_id,
    stable_lfm_album_key,
)


def test_album_match_key_normalizes_whitespace() -> None:
    assert album_match_key(artist_name="  Radiohead ", title="OK  Computer ") == album_match_key(
        artist_name="radiohead",
        title="ok computer",
    )


def test_lastfm_external_id_roundtrip() -> None:
    assert parse_lastfm_album_external_id("lfm-album:2025180") == "2025180"
    assert lastfm_album_external_id("2025180") == "lfm-album:2025180"


def test_placeholder_image_detection() -> None:
    assert is_lastfm_placeholder_image(
        "https://lastfm.freetls.fastly.net/i/u/64s/2a96cbd8b46e442fc41c2b86b821562f.png",
    )
    assert not is_lastfm_placeholder_image("https://lastfm.freetls.fastly.net/i/u/real-cover.jpg")


def test_extract_album_search_rows_single_and_list() -> None:
    payload_list = {
        "results": {
            "albummatches": {
                "album": [
                    {"name": "A", "artist": "X", "id": "1"},
                    {"name": "B", "artist": "Y", "id": "2"},
                ],
            },
        },
    }
    assert len(_extract_album_search_rows(payload_list)) == 2

    payload_single = {
        "results": {"albummatches": {"album": {"name": "A", "artist": "X", "id": "1"}}},
    }
    assert len(_extract_album_search_rows(payload_single)) == 1


def test_album_search_row_skips_placeholder_cover() -> None:
    row = _album_search_row(
        {
            "name": "OK Computer",
            "artist": "Radiohead",
            "id": "99",
            "image": [
                {
                    "size": "large",
                    "#text": "https://lastfm.freetls.fastly.net/i/u/64s/2a96cbd8b46e442fc41c2b86b821562f.png",
                },
            ],
        },
    )
    assert row is not None
    assert row.image_url is None


def test_album_search_row_without_numeric_id_uses_url_path() -> None:
    row = _album_search_row(
        {
            "name": "Como Ninguém",
            "artist": "Nastyfactor",
            "url": "https://www.last.fm/music/Nastyfactor/Como+Ningu%C3%A9m",
            "mbid": "",
        },
    )
    assert row is not None
    assert row.artist_name == "Nastyfactor"
    assert row.title == "Como Ninguém"
    assert row.lastfm_id.startswith("ph-")
    assert len(lastfm_album_external_id(row.lastfm_id)) <= 128


def test_stable_lfm_album_key_prefers_mbid() -> None:
    key = stable_lfm_album_key(
        artist_name="A",
        title="B",
        mbid="61bf0388-b8a9-48f4-81d1-7eb02706dfb0",
    )
    assert key == "mbid-61bf0388-b8a9-48f4-81d1-7eb02706dfb0"


def test_artist_name_matches_query() -> None:
    assert _artist_name_matches_query("Nastyfactor", "nastyfactor")
    assert not _artist_name_matches_query("Other Artist", "nastyfactor")


def test_lfm_artist_person_id_roundtrip_mbid() -> None:
    mbid = "6b0e7b5f-9a1c-4c2d-8e3f-1a2b3c4d5e6f"
    person = lfm_artist_person_id(artist_name="Radiohead", artist_mbid=mbid)
    name, parsed = parse_music_artist_person_id(person)
    assert name is None
    assert parsed == mbid


def test_parse_legacy_mb_artist_person_prefixes() -> None:
    mbid = "6b0e7b5f-9a1c-4c2d-8e3f-1a2b3c4d5e6f"
    assert parse_music_artist_person_id(f"mb-artist:{mbid}") == (None, mbid)
    assert parse_music_artist_person_id(f"mb-artist-{mbid}") == (None, mbid)


def test_lfm_artist_person_id_name_only() -> None:
    person = lfm_artist_person_id(artist_name="Nastyfactor")
    name, mbid = parse_music_artist_person_id(person)
    assert name == "Nastyfactor"
    assert mbid is None


def test_parse_lfm_album_key_labels_path() -> None:
    artist, album = parse_lfm_album_key_labels("path-Nastyfactor/Como+Ningu%C3%A9m")
    assert artist == "Nastyfactor"
    assert album == "Como Ninguém"


def test_stable_lfm_album_key_fits_varchar_128() -> None:
    key = stable_lfm_album_key(
        artist_name="Metro Boomin",
        title="METRO BOOMIN PRESENTS SPIDER-MAN: ACROSS THE SPIDER-VERSE",
        url=(
            "https://www.last.fm/music/Metro+Boomin/METRO+BOOMIN+PRESENTS+SPIDER-MAN:"
            "+ACROSS+THE+SPIDER-VERSE+(SOUNDTRACK+FROM+AND+INSPIRED+BY+THE+MOTION+"
            "PICTURE+%2F+DELUXE+EDITION)"
        ),
    )
    assert key.startswith("ph-")
    assert len(lastfm_album_external_id(key)) <= 128


def test_lastfm_client_has_artist_methods() -> None:
    client = LastfmClient(api_key="test-key")
    assert hasattr(client, "fetch_artist")
    assert hasattr(client, "fetch_top_albums_for_artist")
    assert hasattr(client, "fetch_tag_top_albums")


def test_best_image_url_prefers_extralarge() -> None:
    url = _best_image_url(
        [
            {"size": "small", "#text": "https://example.com/s.jpg"},
            {"size": "extralarge", "#text": "https://example.com/xl.jpg"},
        ],
    )
    assert url == "https://example.com/xl.jpg"
