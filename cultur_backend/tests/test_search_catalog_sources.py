from unittest.mock import MagicMock

import pytest

from app.book_catalog_clients import BookCatalogClients
from app.hardcover_client import HardcoverClient
from app.openlibrary_client import OpenLibraryBook
from app.services import book_catalog_policy
from app.services.book_catalog_policy import BookSearchSources
from app.services.book_catalog_resolver import search_catalog


def _book(title: str, ext: str, *, isbn: str | None = None) -> OpenLibraryBook:
    meta: dict[str, object] = {"isbn": isbn} if isbn else {}
    return OpenLibraryBook(
        external_id=ext,
        title=title,
        subtitle=None,
        description=None,
        image_url=None,
        metadata=meta,
    )


@pytest.fixture(autouse=True)
def _hardcover_primary(monkeypatch):
    monkeypatch.setenv("BOOK_CATALOG_PRIMARY_SOURCE", "hardcover")
    book_catalog_policy.catalog_primary_source.cache_clear()
    yield
    book_catalog_policy.catalog_primary_source.cache_clear()


def test_search_hardcover_only_does_not_query_openlibrary() -> None:
    ol = MagicMock()
    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = True
    hc.search_by_title_author.return_value = [
        _book("Dune", "123", isbn="9780441013595"),
    ]
    clients = BookCatalogClients(openlibrary=ol, porbase=MagicMock(), hardcover=hc)

    results = search_catalog(
        clients,
        query_text="Dune",
        limit=10,
        sources=BookSearchSources.hardcover_only(),
        auto_fallback=False,
    )
    assert len(results) == 1
    assert results[0].source == "hardcover"
    ol.search_books.assert_not_called()


def test_search_default_does_not_fallback_when_hardcover_empty() -> None:
    ol = MagicMock()
    ol.search_books.return_value = [_book("Dune", "OL1W")]
    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = True
    hc.search_by_title_author.return_value = []
    clients = BookCatalogClients(openlibrary=ol, porbase=MagicMock(), hardcover=hc)

    results = search_catalog(
        clients,
        query_text="Dune",
        limit=10,
        sources=BookSearchSources.hardcover_only(),
    )
    assert results == []
    ol.search_books.assert_not_called()
