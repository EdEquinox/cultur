from unittest.mock import MagicMock

from app.book_catalog_clients import BookCatalogClients
from app.hardcover_client import HardcoverClient
from app.openlibrary_client import OpenLibraryBook
from app.services import book_catalog_resolver
from app.services.book_catalog_policy import BookSearchSources


def _book(title: str, work_id: str = "OL1W", *, isbn: str | None = None) -> OpenLibraryBook:
    meta: dict[str, object] = {}
    if isbn:
        meta["isbn"] = isbn
    return OpenLibraryBook(
        external_id=work_id,
        title=title,
        subtitle=None,
        description=None,
        image_url=None,
        metadata=meta,
    )


def test_search_merges_hardcover_and_openlibrary() -> None:
    ol = MagicMock()
    ol.search_books.return_value = [_book("Blood of Elves", "OL1W", isbn="9780142437239")]

    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = True
    hc.search_by_title_author.return_value = [
        _book("Blood of Elves", "445065", isbn="9780142437239"),
    ]

    clients = BookCatalogClients(openlibrary=ol, porbase=MagicMock(), hardcover=hc)
    results = book_catalog_resolver.search_catalog(clients, query_text="Blood of Elves", limit=10)
    assert len(results) == 1
    assert results[0].source == "hardcover"


def test_search_enriches_pt_isbn_with_porbase() -> None:
    ol = MagicMock()
    ol.search_books.return_value = [
        _book("O Sangue dos Elfos", "OL-PT", isbn="9789897730870"),
    ]

    pb = MagicMock()
    pb.fetch_by_isbn.return_value = _book("O Sangue dos Elfos", "2808776", isbn="9789897730870")

    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = False

    clients = BookCatalogClients(openlibrary=ol, porbase=pb, hardcover=hc)
    results = book_catalog_resolver.search_catalog(
        clients,
        query_text="9789897730870",
        limit=10,
        sources=BookSearchSources.porbase_only(),
        auto_fallback=False,
    )
    assert len(results) == 1
    assert results[0].source == "porbase"
    assert results[0].book.external_id == "2808776"


def test_merge_author_entries_preserves_openlibrary_ids() -> None:
    base = {
        "authorEntries": [{"id": "OL23919A", "name": "J. K. Rowling"}],
    }
    incoming = {
        "authorEntries": [
            {"id": "", "name": "J. K. Rowling"},
            {"id": "", "name": "Mary GrandPré"},
        ],
    }
    merged = book_catalog_resolver.merge_book_metadata(base, incoming)
    entries = merged["authorEntries"]
    assert entries[0]["id"] == "OL23919A"
    assert entries[0]["name"] == "J. K. Rowling"
    assert entries[1]["name"] == "Mary GrandPré"


def test_merge_book_metadata_adds_missing_provider_urls() -> None:
    base = {"authors": "A", "isbn": "1250892317"}
    incoming = {
        "hardcoverUrl": "https://hardcover.app/books/murdle",
        "openLibraryUrl": "https://openlibrary.org/works/OL123W",
        "porbaseUrl": "http://urn.porbase.org/isbn/dc/xml?id=9789720000000",
    }
    merged = book_catalog_resolver.merge_book_metadata(base, incoming)
    assert merged["hardcoverUrl"] == incoming["hardcoverUrl"]
    assert merged["openLibraryUrl"] == incoming["openLibraryUrl"]
    assert merged["porbaseUrl"] == incoming["porbaseUrl"]


def test_enrich_book_from_all_providers_merges_sources() -> None:
    ol = MagicMock()
    ol.fetch_book_by_isbn.return_value = _book(
        "Murdle",
        "OL1W",
        isbn="1250892317",
    )
    ol.fetch_book_by_isbn.return_value.metadata["openLibraryUrl"] = (
        "https://openlibrary.org/works/OL1W"
    )

    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = True
    hc.fetch_by_isbn.return_value = _book("Murdle", "817972", isbn="1250892317")
    hc.fetch_by_isbn.return_value.metadata["hardcoverUrl"] = (
        "https://hardcover.app/books/murdle"
    )

    pb = MagicMock()
    pb.fetch_by_isbn.return_value = None

    clients = BookCatalogClients(openlibrary=ol, porbase=pb, hardcover=hc)
    book, notes = book_catalog_resolver.enrich_book_from_all_providers(
        clients,
        title="Murdle: Volume 1",
        external_id="817972",
        source="hardcover",
        metadata={"isbn": "1250892317", "authors": "Steven W. Levitt"},
    )
    assert book.metadata.get("hardcoverUrl")
    assert book.metadata.get("openLibraryUrl")
    assert "porbase: no match" in notes
