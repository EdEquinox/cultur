from app.person_id_path import decode_person_id_from_path, encode_person_id_for_path
from app.lastfm_client import parse_music_artist_person_id


def test_encode_person_id_escapes_slashes() -> None:
    raw = "lfm-artist:n/Metro Boomin"
    encoded = encode_person_id_for_path(raw)
    assert "/" not in encoded
    assert "%7C" in encoded or "|" in encoded


def test_decode_person_id_restores_slashes_from_pipe() -> None:
    assert decode_person_id_from_path("lfm-artist:n|Metro Boomin") == "lfm-artist:n/Metro Boomin"


def test_decode_person_id_passes_through_literal_slash() -> None:
    assert decode_person_id_from_path("lfm-artist:n/Metro Boomin") == "lfm-artist:n/Metro Boomin"


def test_metro_boomin_roundtrip() -> None:
    person_id = "lfm-artist:n/Metro Boomin"
    segment = encode_person_id_for_path(person_id)
    restored = decode_person_id_from_path(segment)
    assert restored == person_id
    name, mbid = parse_music_artist_person_id(restored)
    assert name == "Metro Boomin"
    assert mbid is None
