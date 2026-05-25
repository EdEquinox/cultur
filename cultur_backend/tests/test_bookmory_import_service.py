from datetime import UTC, datetime
from unittest.mock import MagicMock

import pytest

from app.book_catalog_clients import BookCatalogClients
from app.catalog_match import title_similarity
from app.hardcover_client import HardcoverClient
from app.openlibrary_client import OpenLibraryBook
from app.schemas import BookmoryImportBatchRequest, BookmoryImportEntryPayload
from app.services import book_catalog_resolver, bookmory_import_service


def _book(title: str, work_id: str = "OL1W") -> OpenLibraryBook:
    return OpenLibraryBook(
        external_id=work_id,
        title=title,
        subtitle=None,
        description=None,
        image_url=None,
        metadata={},
    )


def _clients(
    *,
    ol: MagicMock | None = None,
    pb: MagicMock | None = None,
    hc: MagicMock | None = None,
) -> BookCatalogClients:
    return BookCatalogClients(
        openlibrary=ol or MagicMock(),
        porbase=pb or MagicMock(),
        hardcover=hc,
    )


def test_tracking_plan_read_status() -> None:
    plan = bookmory_import_service._tracking_plan_from_row(
        BookmoryImportEntryPayload(
            sourceFile="a.txt",
            title="Test",
            status="I've read it all!",
            score=4.5,
            completedAt="2025-12-31T00:00:00Z",
        ),
    )
    assert "watched" in plan.flags
    assert plan.status == "Completed"
    assert plan.score == 4.5


def test_compose_notes_with_price_and_lent() -> None:
    plan = bookmory_import_service._TrackingPlan(
        flags=frozenset({"collected"}),
        status="Planning",
        price="€9.99",
        lent_borrower="Alex",
        lent_at=datetime(2026, 4, 20, tzinfo=UTC),
    )
    notes = bookmory_import_service._compose_tracking_notes(plan)
    assert notes is not None
    assert "[cult.price]€9.99" in notes
    assert "[cult.lent]Alex" in notes


def test_title_similarity_substring() -> None:
    assert title_similarity(
        "Harry Potter",
        "Harry Potter and the Stone",
    ) >= 0.8


def test_porbase_title_fallback_uses_discovered_isbn() -> None:
    ol = MagicMock()
    ol.search_books.return_value = [_book("O Sangue dos Elfos", "OL-W")]
    ol.search_books.return_value[0].metadata["isbn"] = "9789897730870"

    pb = MagicMock()

    def fetch_side_effect(isbn: str):
        if isbn == "9789897730870":
            return _book("O Sangue dos Elfos", "2808776")
        return None

    pb.fetch_by_isbn.side_effect = fetch_side_effect

    book = book_catalog_resolver._resolve_porbase_by_title(
        pb,
        book_catalog_resolver.BookLookupQuery(
            title="O Sangue dos Elfos",
            authors="Andrzej Sapkowski",
        ),
        ol_client=ol,
    )
    assert book.external_id == "2808776"


def test_isbn_uses_porbase_before_hardcover() -> None:
    pb = MagicMock()
    pb.fetch_by_isbn.return_value = _book("O Sangue dos Elfos", "2808776")
    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = True

    resolved = book_catalog_resolver.resolve_single(
        _clients(pb=pb, hc=hc),
        book_catalog_resolver.BookLookupQuery(
            title="O Sangue dos Elfos",
            isbn="9789897730870",
        ),
    )
    assert resolved.source == "porbase"
    pb.fetch_by_isbn.assert_called_once_with("9789897730870")
    hc.fetch_by_isbn.assert_not_called()


def test_import_batch_counts_error() -> None:
    db = MagicMock()
    ol = MagicMock()
    ol.search_books.return_value = []
    ol.fetch_book_by_isbn.return_value = None
    pb = MagicMock()
    pb.fetch_by_isbn.return_value = None
    hc = MagicMock(spec=HardcoverClient)
    hc.enabled = False

    payload = BookmoryImportBatchRequest(
        username="tester",
        entries=[
            BookmoryImportEntryPayload(
                sourceFile="missing.txt",
                title="Unknown Book",
                isbn="9780000000000",
            ),
        ],
    )
    out = bookmory_import_service.import_bookmory_batch(
        db,
        payload,
        book_clients=_clients(ol=ol, pb=pb, hc=hc),
    )
    assert out.imported == 0
    assert out.skipped == 1
    assert len(out.errors) == 1
    assert out.errors[0].reason == "not_found"
