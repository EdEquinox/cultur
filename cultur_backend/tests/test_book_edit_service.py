from unittest.mock import MagicMock, patch

from app.book_catalog_clients import BookCatalogClients
from app.hardcover_client import HardcoverClient
from app.openlibrary_client import OpenLibraryBook
from app.services import book_catalog_resolver, book_edit_service


def _item(**kwargs: object) -> MagicMock:
    row = MagicMock()
    row.media_type = "book"
    row.title = kwargs.get("title", "Murdle")
    row.subtitle = kwargs.get("subtitle", None)
    row.description = kwargs.get("description", "A mystery book.")
    row.image_url = kwargs.get("image_url", None)
    row.provider_payload = kwargs.get(
        "provider_payload",
        {"authors": "Steven W. Levitt", "isbn": "1250892317"},
    )
    return row


def _book(title: str, **meta: object) -> OpenLibraryBook:
    return OpenLibraryBook(
        external_id="1",
        title=title,
        subtitle=None,
        description="Provider description",
        image_url="https://example.com/cover.jpg",
        metadata=dict(meta),
    )


def test_list_book_edit_fields_includes_current_values() -> None:
    item = _item()
    rows = book_edit_service.list_book_edit_fields(item)
    by_key = {row["key"]: row for row in rows}
    assert by_key["title"]["currentValue"] == "Murdle"
    assert by_key["authors"]["currentValue"] == "Steven W. Levitt"


def test_get_book_field_options_merges_providers() -> None:
    item = _item()
    ol = MagicMock()
    ol.fetch_book_by_isbn.return_value = _book(
        "Murdle: Volume 1 (OL)",
        authors="Steven W. Levitt",
    )
    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = True
    hc.fetch_by_isbn.return_value = _book(
        "Murdle Vol 1",
        authors="Steven W. Levitt, J. Student",
    )
    pb = MagicMock()
    pb.fetch_by_isbn.return_value = None

    clients = BookCatalogClients(openlibrary=ol, porbase=pb, hardcover=hc)
    payload = book_edit_service.get_book_field_options(
        clients,
        item,
        field_key="title",
    )
    providers = {row["provider"] for row in payload["options"]}
    assert "current" in providers
    assert "openlibrary" in providers
    assert "hardcover" in providers


def test_search_books_for_edit_returns_hits() -> None:
    clients = BookCatalogClients(
        openlibrary=MagicMock(),
        porbase=MagicMock(),
        hardcover=MagicMock(spec=HardcoverClient),
    )
    with patch(
        "app.services.book_edit_service.search_catalog",
        return_value=[
            book_catalog_resolver.ResolvedCatalogBook(
                book=_book("Murdle", authors="Author"),
                source="openlibrary",
            ),
        ],
    ):
        hits = book_edit_service.search_books_for_edit(clients, query="Murdle", limit=5)
    assert len(hits) == 1
    assert hits[0]["source"] == "openlibrary"


def test_patch_book_catalog_edit_updates_columns_and_metadata() -> None:
    item = _item()
    db = MagicMock()
    book_edit_service.patch_book_catalog_edit(
        db,
        item,
        fields={"title": "Custom title", "authors": "New Author"},
        field_sources={"title": "manual", "authors": "hardcover"},
    )
    assert item.title == "Custom title"
    meta = item.provider_payload
    assert meta["authors"] == "New Author"
    assert meta["userEdited"] is True
    assert meta["userFieldSources"]["title"] == "manual"
    db.commit.assert_called_once()
