from app.schemas import BackendMediaResponse, PersonFilmographyItem
from app.services.music_catalog_service import _image_url_from_filmography


def _filmography_item(image_url: str | None) -> PersonFilmographyItem:
    return PersonFilmographyItem(
        media=BackendMediaResponse(
            id="mb-rg:00000000-0000-0000-0000-000000000001",
            source="musicbrainz",
            externalId="mb-rg:00000000-0000-0000-0000-000000000001",
            mediaType="music",
            title="Example Album",
            imageUrl=image_url,
        ),
        role="Album",
        mediaType="music",
    )


def test_image_url_from_filmography_skips_empty_and_returns_first_cover() -> None:
    filmography = [
        _filmography_item(None),
        _filmography_item("  "),
        _filmography_item("https://coverartarchive.org/front/1"),
    ]
    assert _image_url_from_filmography(filmography) == "https://coverartarchive.org/front/1"


def test_image_url_from_filmography_returns_none_when_no_covers() -> None:
    assert _image_url_from_filmography([_filmography_item(None)]) is None
