from unittest.mock import MagicMock

from app.book_catalog_clients import BookCatalogClients
from app.openlibrary_client import OpenLibraryBook
from app.services.book_canonical_merge import (
    CATALOG_MERGE_VERSION,
    merge_canonical_book,
)


def _book(
    title: str,
    external_id: str,
    *,
    source_meta: dict[str, object] | None = None,
    description: str | None = None,
    image_url: str | None = None,
) -> OpenLibraryBook:
    return OpenLibraryBook(
        external_id=external_id,
        title=title,
        subtitle=None,
        description=description,
        image_url=image_url,
        metadata=source_meta or {},
    )


def test_merge_canonical_prefers_porbase_title_for_pt_isbn() -> None:
    ol = MagicMock()
    ol.fetch_book_by_isbn.return_value = None
    clients = BookCatalogClients(
        openlibrary=ol,
        porbase=MagicMock(),
        hardcover=MagicMock(),
    )
    snapshots = {
        "openlibrary": _book(
            "The Elves Blood",
            "OL-PT",
            source_meta={"isbn": "9789897730870", "authors": "Author"},
        ),
        "porbase": _book(
            "O Sangue dos Elfos",
            "2808776",
            source_meta={"isbn": "9789897730870", "authors": "Autor"},
        ),
        "hardcover": None,
    }
    merged = merge_canonical_book(
        clients,
        primary_source="porbase",
        external_id="2808776",
        title="The Elves Blood",
        metadata={"isbn": "9789897730870"},
        provider_snapshots=snapshots,
    )
    assert merged.title == "O Sangue dos Elfos"
    meta = merged.metadata
    assert meta.get("catalogMergeVersion") == CATALOG_MERGE_VERSION
    assert "porbase" in meta.get("catalogMergedSources", [])


def test_merge_canonical_keeps_openlibrary_author_ids() -> None:
    ol = MagicMock()
    ol.fetch_book_by_isbn.return_value = None
    clients = BookCatalogClients(
        openlibrary=ol,
        porbase=MagicMock(),
        hardcover=MagicMock(),
    )
    snapshots = {
        "openlibrary": _book(
            "Harry Potter",
            "OL1W",
            source_meta={
                "authorEntries": [{"id": "OL23919A", "name": "J. K. Rowling"}],
            },
        ),
        "hardcover": _book(
            "Harry Potter",
            "445065",
            source_meta={
                "authorEntries": [
                    {"id": "", "name": "J. K. Rowling"},
                    {"id": "", "name": "Mary GrandPré"},
                ],
            },
        ),
        "porbase": None,
    }
    merged = merge_canonical_book(
        clients,
        primary_source="hardcover",
        external_id="445065",
        title="Harry Potter",
        metadata={},
        provider_snapshots=snapshots,
    )
    entries = merged.metadata.get("authorEntries")
    assert isinstance(entries, list)
    assert entries[0]["id"] == "OL23919A"
    assert entries[1]["name"] == "Mary GrandPré"


def test_merge_canonical_picks_longest_description_and_hardcover_cover() -> None:
    ol = MagicMock()
    ol.fetch_book_by_isbn.return_value = None
    clients = BookCatalogClients(
        openlibrary=ol,
        porbase=MagicMock(),
        hardcover=MagicMock(),
    )
    snapshots = {
        "openlibrary": _book(
            "Murdle",
            "OL1W",
            description="Short.",
            source_meta={"isbn": "9781250892314", "pageCount": 200},
        ),
        "hardcover": _book(
            "Murdle",
            "1250892317",
            description="A much longer synopsis from Hardcover.",
            image_url="https://hardcover.example/cover.jpg",
            source_meta={"isbn": "9781250892314", "pageCount": 256},
        ),
        "porbase": None,
    }
    merged = merge_canonical_book(
        clients,
        primary_source="hardcover",
        external_id="1250892317",
        title="Murdle",
        metadata={"isbn": "9781250892314"},
        provider_snapshots=snapshots,
    )
    assert merged.description == "A much longer synopsis from Hardcover."
    assert merged.image_url == "https://hardcover.example/cover.jpg"
    assert merged.metadata.get("pageCount") == 256
