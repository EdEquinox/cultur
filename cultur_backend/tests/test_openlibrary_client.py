from datetime import UTC, datetime, timedelta

from app.openlibrary_client import (
    BOOK_DETAIL_ENRICHED_KEY,
    OpenLibraryClient,
    _archive_cover_url,
    _author_entries_from_search_doc,
    _book_from_author_work_entry,
    _book_from_search_doc,
    _book_from_work_payload,
    _cover_url_from_search_doc,
    _ia_cover_url,
    _metadata_from_edition_entries,
    _normalize_author_id,
    isbn13_to_isbn10,
    _normalize_work_id,
    book_detail_can_use_stored_fallback,
    book_detail_response_can_use_cache,
    openlibrary_person_id,
    parse_openlibrary_person_id,
    split_book_subjects_for_display,
)


def test_normalize_work_id() -> None:
    assert _normalize_work_id("/works/OL27448W") == "OL27448W"
    assert _normalize_work_id("OL27448W") == "OL27448W"
    assert _normalize_work_id("invalid") == ""


def test_isbn13_to_isbn10() -> None:
    assert isbn13_to_isbn10("9780142437230") == "0142437239"


def test_normalize_author_id_and_person_id() -> None:
    assert _normalize_author_id("/authors/OL23919A") == "OL23919A"
    assert _normalize_author_id("OL23919A") == "OL23919A"
    assert openlibrary_person_id("OL23919A") == "ol-OL23919A"
    assert parse_openlibrary_person_id("ol-OL23919A") == "OL23919A"
    # TMDB person ids are numeric; must not be treated as Open Library authors.
    assert parse_openlibrary_person_id("1398631") is None


def test_book_from_author_work_entry() -> None:
    book = _book_from_author_work_entry(
        {
            "key": "/works/OL82563W",
            "title": "Harry Potter and the Philosopher's Stone",
            "first_publish_year": 1997,
            "cover_id": 10521270,
        },
    )
    assert book.external_id == "OL82563W"
    assert book.metadata["firstPublishYear"] == 1997


def test_book_from_search_doc() -> None:
    book = _book_from_search_doc(
        {
            "key": "/works/OL82563W",
            "title": "Harry Potter and the Philosopher's Stone",
            "author_name": ["J. K. Rowling"],
            "first_publish_year": 1997,
            "cover_i": 12345,
            "ratings_average": 4.5,
        },
    )
    assert book.external_id == "OL82563W"
    assert book.title.startswith("Harry Potter")
    assert book.image_url is not None
    assert book.image_url == _archive_cover_url(12345)
    assert book.metadata["authors"] == "J. K. Rowling"


def test_book_from_search_doc_uses_first_sentence_as_description() -> None:
    book = _book_from_search_doc(
        {
            "key": "/works/OL82563W",
            "title": "Harry Potter and the Philosopher's Stone",
            "author_name": ["J. K. Rowling"],
            "first_publish_year": 1997,
            "cover_i": 12345,
            "first_sentence": ["Mr. and Mrs. Dursley were proud to say that they were perfectly normal."],
        },
    )
    assert book.description is not None
    assert "Dursley" in book.description


def test_book_from_search_doc_uses_pages_median() -> None:
    book = _book_from_search_doc(
        {
            "key": "/works/OL17625829W",
            "title": "Empire of Storms",
            "author_name": ["Sarah J. Maas"],
            "first_publish_year": 2016,
            "cover_i": 12345,
            "number_of_pages_median": 704,
        },
    )
    assert book.metadata.get("pageCount") == 704


def test_cover_url_prefers_ia_when_scanned() -> None:
    url = _cover_url_from_search_doc(
        {
            "cover_i": 15155833,
            "ia": ["harrypottersorce0000rowl"],
        },
    )
    assert url == _ia_cover_url("harrypottersorce0000rowl")


def test_publish_year_from_openlibrary_date_dict() -> None:
    from app.openlibrary_client import _publish_year_label

    assert _publish_year_label({"type": "/type/datetime", "value": "2014-03-04"}) == "2014"


def test_archive_cover_url_format() -> None:
    assert _archive_cover_url(14658334) == (
        "https://archive.org/download/m_covers_0014/m_covers_0014_65.zip/0014658334-M.jpg"
    )


def test_book_from_work_payload() -> None:
    book = _book_from_work_payload(
        "OL82563W",
        {
            "title": "Harry Potter and the Philosopher's Stone",
            "description": "A young wizard attends Hogwarts.",
            "covers": [10521270],
            "first_publish_date": "1997",
            "subjects": ["Fantasy", "Magic"],
            "number_of_pages": 223,
        },
    )
    assert book.external_id == "OL82563W"
    assert book.description is not None
    assert book.metadata["pageCount"] == 223


def test_author_entries_from_search_doc() -> None:
    entries = _author_entries_from_search_doc(
        {"author_name": ["J. K. Rowling", "Other Author"]},
    )
    assert len(entries) == 2
    assert entries[0]["name"] == "J. K. Rowling"


def test_metadata_from_edition_entries_page_median() -> None:
    client = OpenLibraryClient(min_request_interval_seconds=0)
    publishers, _, _, isbn, page_count = _metadata_from_edition_entries(
        client,
        [
            {"number_of_pages": 200, "publishers": ["Test Pub"]},
            {"number_of_pages": 300},
        ],
    )
    assert page_count == 300
    assert isbn is None
    assert len(publishers) == 1


def test_book_detail_response_can_use_cache() -> None:
    now = datetime.now(tz=UTC)
    meta = {
        "openLibraryWorkId": "OL82563W",
        "authors": "J. K. Rowling",
        BOOK_DETAIL_ENRICHED_KEY: True,
    }
    assert book_detail_response_can_use_cache(updated_at=now, metadata=meta)
    assert not book_detail_response_can_use_cache(
        updated_at=now - timedelta(days=8),
        metadata=meta,
    )


def test_book_detail_hardcover_metadata_can_cache_and_fallback() -> None:
    now = datetime.now(tz=UTC)
    meta = {
        "hardcoverUrl": "https://hardcover.app/books/murdle",
        "hardcoverBookId": "817972",
        "authors": "Steven W. Levitt",
        BOOK_DETAIL_ENRICHED_KEY: True,
        "isbn": "1250892317",
    }
    assert book_detail_response_can_use_cache(updated_at=now, metadata=meta)
    assert book_detail_can_use_stored_fallback(meta)
    assert not book_detail_response_can_use_cache(
        updated_at=now - timedelta(days=8),
        metadata=meta,
    )
    assert book_detail_can_use_stored_fallback(meta)


def test_split_book_subjects_for_display_dedupes_and_splits() -> None:
    subjects = [
        "Fiction",
        "Fantasy",
        "fiction",
        "Translations Into English",
        "nyt:mass-market-paperback=2015-07-05",
        "New York Times Bestseller",
        "Short Stories",
    ]
    genres, tags = split_book_subjects_for_display(subjects)
    assert "Fiction" in genres
    assert "Fantasy" in genres
    assert "Short Stories" in genres
    assert len(genres) == 3
    assert "Translations Into English" in tags
    assert any("nyt:" in tag for tag in tags)
    assert "Fiction" not in tags
