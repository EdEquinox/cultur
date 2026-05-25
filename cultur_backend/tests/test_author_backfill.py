from unittest.mock import MagicMock, patch

from app.openlibrary_client import (
    OpenLibraryBook,
    _enrich_book_from_sources,
    _merge_author_entry_lists,
    resolve_openlibrary_author_id,
)
from app.services.book_catalog_resolver import _backfill_openlibrary_author_entries


def test_merge_author_entry_lists_keeps_openlibrary_ids() -> None:
    merged = _merge_author_entry_lists(
        [{"id": "OL23919A", "name": "J. K. Rowling"}],
        [{"id": "", "name": "J. K. Rowling"}, {"id": "", "name": "Mary GrandPré"}],
    )
    assert merged[0]["id"] == "OL23919A"
    assert merged[1]["name"] == "Mary GrandPré"


@patch("app.openlibrary_client._authors_from_work")
def test_enrich_book_from_sources_prefers_work_author_ids(mock_work_authors) -> None:
    mock_work_authors.return_value = [{"id": "OL23919A", "name": "J. K. Rowling"}]
    client = MagicMock()
    book = OpenLibraryBook(
        external_id="OL82563W",
        title="Harry Potter",
        subtitle=None,
        description=None,
        image_url=None,
        metadata={"openLibraryWorkId": "OL82563W"},
    )
    enriched = _enrich_book_from_sources(
        client,
        book,
        {"authors": []},
        {"author_name": ["J. K. Rowling"]},
    )
    entries = enriched.metadata.get("authorEntries")
    assert isinstance(entries, list)
    assert entries[0]["id"] == "OL23919A"


@patch("app.openlibrary_client._authors_from_work")
def test_backfill_fills_missing_coauthor_when_one_has_id(mock_work_authors) -> None:
    mock_work_authors.return_value = [
        {"id": "OL23919A", "name": "J. K. Rowling"},
        {"id": "OL83318A", "name": "Mary GrandPré"},
    ]
    ol = MagicMock()
    meta = {
        "openLibraryWorkId": "OL82563W",
        "authorEntries": [
            {"id": "OL23919A", "name": "J. K. Rowling"},
            {"id": "", "name": "Mary GrandPré"},
        ],
    }
    fixed = _backfill_openlibrary_author_entries(ol, meta)
    entries = fixed["authorEntries"]
    assert entries[0]["id"] == "OL23919A"
    assert entries[1]["id"] == "OL83318A"


@patch("app.openlibrary_client._authors_from_work")
def test_backfill_resolves_work_id_from_isbn(mock_work_authors) -> None:
    from app.openlibrary_client import OpenLibraryClient

    mock_work_authors.return_value = [{"id": "OL25712A", "name": "Frank Herbert"}]
    ol = MagicMock(spec=OpenLibraryClient)
    ol.fetch_book_by_isbn.return_value = OpenLibraryBook(
        external_id="OL27448W",
        title="Dune",
        subtitle=None,
        description=None,
        image_url=None,
        metadata={"openLibraryWorkId": "OL27448W"},
    )

    meta = {
        "isbn": "9780441013595",
        "authorEntries": [{"id": "", "name": "Frank Herbert"}],
    }
    fixed = _backfill_openlibrary_author_entries(
        ol,
        meta,
        source="hardcover",
        external_id="999",
    )
    assert fixed["openLibraryWorkId"] == "OL27448W"
    assert fixed["authorEntries"][0]["id"] == "OL25712A"


def test_resolve_openlibrary_author_id_exact_match() -> None:
    client = MagicMock()
    client._get_json.return_value = {
        "docs": [
            {"key": "OL23919A", "name": "J. K. Rowling", "work_count": 400},
            {"key": "OL99999A", "name": "Other Person", "work_count": 1},
        ],
    }
    assert resolve_openlibrary_author_id(client, "J. K. Rowling") == "OL23919A"
