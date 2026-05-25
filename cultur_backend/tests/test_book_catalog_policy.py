import os
from unittest.mock import MagicMock

import pytest

from app.book_catalog_clients import BookCatalogClients
from app.hardcover_client import HardcoverClient
from app.openlibrary_client import OpenLibraryBook
from app.services import book_catalog_policy, book_catalog_resolver
from app.services.book_catalog_resolver import BookLookupQuery, BookResolveError


def _clear_policy_cache() -> None:
    book_catalog_policy.catalog_primary_source.cache_clear()


@pytest.fixture(autouse=True)
def _reset_primary_source_env(monkeypatch):
    monkeypatch.delenv("BOOK_CATALOG_PRIMARY_SOURCE", raising=False)
    _clear_policy_cache()
    yield
    _clear_policy_cache()


def test_default_merge_priority_is_hardcover_primary() -> None:
    assert book_catalog_policy.is_hardcover_primary()
    assert book_catalog_policy.merge_source_priority() == {
        "hardcover": 3,
        "openlibrary": 2,
        "porbase": 1,
    }


def test_legacy_merge_priority_when_not_hardcover(monkeypatch) -> None:
    monkeypatch.setenv("BOOK_CATALOG_PRIMARY_SOURCE", "porbase")
    _clear_policy_cache()
    assert not book_catalog_policy.is_hardcover_primary()
    assert book_catalog_policy.merge_source_priority() == {
        "porbase": 3,
        "hardcover": 2,
        "openlibrary": 1,
    }


def test_hardcover_primary_merge_priority(monkeypatch) -> None:
    monkeypatch.setenv("BOOK_CATALOG_PRIMARY_SOURCE", "hardcover")
    _clear_policy_cache()
    assert book_catalog_policy.merge_source_priority() == {
        "hardcover": 3,
        "openlibrary": 2,
        "porbase": 1,
    }


def test_hardcover_primary_resolve_order(monkeypatch) -> None:
    monkeypatch.setenv("BOOK_CATALOG_PRIMARY_SOURCE", "hardcover")
    _clear_policy_cache()
    assert book_catalog_policy.resolve_isbn_provider_order(
        has_porbase=True,
        has_hardcover=True,
    ) == ("hardcover", "porbase")


def test_resolve_single_primary_tries_hardcover_first(monkeypatch) -> None:
    monkeypatch.setenv("BOOK_CATALOG_PRIMARY_SOURCE", "hardcover")
    _clear_policy_cache()

    ol = MagicMock()
    pb = MagicMock()
    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = True
    hc.fetch_by_isbn.return_value = _book("Murdle", "817972", isbn="1250892317")

    clients = BookCatalogClients(openlibrary=ol, porbase=pb, hardcover=hc)
    row = book_catalog_resolver._resolve_single_primary(
        clients,
        BookLookupQuery(title="Murdle", isbn="1250892317"),
    )
    assert row.source == "hardcover"
    hc.fetch_by_isbn.assert_called_once()
    ol.fetch_book_by_isbn.assert_not_called()
    pb.fetch_by_isbn.assert_not_called()


def test_resolve_single_primary_hardcover_only_raises_when_missing(monkeypatch) -> None:
    monkeypatch.setenv("BOOK_CATALOG_PRIMARY_SOURCE", "hardcover")
    _clear_policy_cache()
    monkeypatch.setattr(
        book_catalog_policy,
        "resolve_isbn_provider_order",
        lambda **_: ("hardcover",),
    )

    ol = MagicMock()
    pb = MagicMock()
    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = True
    hc.fetch_by_isbn.return_value = None
    hc.search_by_title_author.return_value = []

    clients = BookCatalogClients(openlibrary=ol, porbase=pb, hardcover=hc)
    with pytest.raises(BookResolveError):
        book_catalog_resolver._resolve_single_primary(
            clients,
            BookLookupQuery(title="Murdle", isbn="1250892317"),
        )
    hc.fetch_by_isbn.assert_called_once()
    ol.fetch_book_by_isbn.assert_not_called()


def _book(title: str, work_id: str, *, isbn: str | None = None) -> OpenLibraryBook:
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
