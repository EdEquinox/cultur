"""Build one book record by merging PORBASE, Hardcover, and Open Library snapshots."""

from __future__ import annotations

import logging

from ..book_catalog_clients import BookCatalogClients
from ..hardcover_client import HardcoverClient, HardcoverError
from ..openlibrary_client import (
    BOOK_DETAIL_ENRICHED_KEY,
    OpenLibraryBook,
    OpenLibraryClient,
    OpenLibraryError,
)
from ..porbase_client import PorbaseClient, PorbaseError
from ..openlibrary_client import _normalize_isbn
from ..catalog_match import build_title_author_query, pick_best_catalog_match

logger = logging.getLogger(__name__)

CATALOG_MERGE_VERSION = 2


def _is_pt_isbn(isbn: str) -> bool:
    return isbn.startswith("978989") or isbn.startswith("978972")


def _pick_preferred_isbn(*candidates: object) -> str:
    normalized: list[str] = []
    for raw in candidates:
        value = _normalize_isbn(str(raw or ""))
        if value and value not in normalized:
            normalized.append(value)
    for value in normalized:
        if len(value) == 13:
            return value
    return normalized[0] if normalized else ""


def _source_field_order(is_pt: bool, field: str) -> tuple[str, ...]:
    from .book_catalog_policy import is_hardcover_primary

    if is_hardcover_primary():
        if field == "title":
            return ("hardcover", "porbase", "openlibrary") if is_pt else (
                "hardcover",
                "openlibrary",
                "porbase",
            )
        if field in {"image", "pageCount", "publisher"}:
            return ("hardcover", "openlibrary", "porbase")
        return ("hardcover", "openlibrary", "porbase")

    if field == "title":
        return ("porbase", "hardcover", "openlibrary") if is_pt else (
            "hardcover",
            "openlibrary",
            "porbase",
        )
    if field in {"image", "pageCount"}:
        return ("hardcover", "openlibrary", "porbase")
    if field == "publisher":
        return ("porbase", "hardcover", "openlibrary") if is_pt else (
            "hardcover",
            "openlibrary",
            "porbase",
        )
    return ("openlibrary", "hardcover", "porbase")


def _pick_from_sources(
    field: str,
    *,
    is_pt: bool,
    books: dict[str, OpenLibraryBook],
    fallback: str | None = None,
) -> str | None:
    for source in _source_field_order(is_pt, field):
        book = books.get(source)
        if book is None:
            continue
        if field == "title":
            text = (book.title or "").strip()
        elif field == "subtitle":
            text = (book.subtitle or "").strip()
        elif field == "image":
            text = (book.image_url or "").strip()
        else:
            continue
        if text:
            return text
    return fallback


def _pick_page_count(books: dict[str, OpenLibraryBook]) -> int | None:
    for source in ("hardcover", "openlibrary", "porbase"):
        book = books.get(source)
        if book is None:
            continue
        meta = book.metadata if isinstance(book.metadata, dict) else {}
        raw = meta.get("pageCount")
        if isinstance(raw, int) and raw > 0:
            return raw
        if isinstance(raw, str) and raw.isdigit():
            return int(raw)
    return None


def collect_provider_snapshots(
    clients: BookCatalogClients,
    *,
    title: str,
    metadata: dict[str, object],
) -> dict[str, OpenLibraryBook | None]:
    """Fetch the best matching record from each configured provider."""
    isbn = _normalize_isbn(str(metadata.get("isbn") or ""))
    authors_raw = metadata.get("authors")
    author_text = authors_raw if isinstance(authors_raw, str) else None

    return {
        "openlibrary": _snapshot_openlibrary(
            clients.openlibrary,
            title=title,
            metadata=metadata,
            isbn=isbn,
            author_text=author_text,
        ),
        "hardcover": _snapshot_hardcover(
            clients.hardcover,
            title=title,
            isbn=isbn,
            author_text=author_text,
        ),
        "porbase": _snapshot_porbase(
            clients.porbase,
            title=title,
            isbn=isbn,
            author_text=author_text,
            ol_client=clients.openlibrary,
        ),
    }


def _pick_richer_description(
    current: str | None,
    incoming: str | None,
) -> str | None:
    candidates = [
        text.strip()
        for text in (current, incoming)
        if isinstance(text, str) and text.strip()
    ]
    if not candidates:
        return None
    return max(candidates, key=len)


def merge_canonical_book(
    clients: BookCatalogClients,
    *,
    primary_source: str,
    external_id: str,
    title: str,
    description: str | None = None,
    subtitle: str | None = None,
    image_url: str | None = None,
    metadata: dict[str, object] | None = None,
    provider_snapshots: dict[str, OpenLibraryBook | None] | None = None,
    extra_books: list[tuple[str, OpenLibraryBook]] | None = None,
) -> OpenLibraryBook:
    """Merge provider payloads into one book while keeping catalog identity."""
    from .book_catalog_resolver import (
        _backfill_openlibrary_author_entries,
        _merge_author_entries,
        merge_book_metadata,
    )

    base_meta = dict(metadata or {})
    snapshots = provider_snapshots or collect_provider_snapshots(
        clients,
        title=title,
        metadata=base_meta,
    )

    books: dict[str, OpenLibraryBook] = {}
    for source, book in snapshots.items():
        if book is not None:
            books[source] = book
    for source, book in extra_books or []:
        books[source] = book

    isbn = _pick_preferred_isbn(
        base_meta.get("isbn"),
        *[((b.metadata or {}).get("isbn") if isinstance(b.metadata, dict) else "") for b in books.values()],
    )
    is_pt = bool(isbn and _is_pt_isbn(isbn))

    meta: dict[str, object] = {}
    for source in ("openlibrary", "hardcover", "porbase"):
        book = books.get(source)
        if book is None:
            continue
        book_meta = book.metadata if isinstance(book.metadata, dict) else {}
        meta = merge_book_metadata(meta, book_meta)
    meta = merge_book_metadata(meta, base_meta)

    if isbn:
        meta["isbn"] = isbn

    page_count = _pick_page_count(books)
    if page_count is not None:
        meta["pageCount"] = page_count

    merged_title = _pick_from_sources("title", is_pt=is_pt, books=books, fallback=title) or title
    merged_subtitle = _pick_from_sources("subtitle", is_pt=is_pt, books=books, fallback=subtitle)
    merged_image = _pick_from_sources("image", is_pt=is_pt, books=books, fallback=image_url)

    merged_description = description
    for source in ("openlibrary", "hardcover", "porbase"):
        book = books.get(source)
        if book is not None:
            merged_description = _pick_richer_description(merged_description, book.description)

    merged_authors = base_meta.get("authorEntries")
    for book in books.values():
        book_meta = book.metadata if isinstance(book.metadata, dict) else {}
        merged_authors = _merge_author_entries(merged_authors, book_meta.get("authorEntries"))
    if merged_authors:
        meta["authorEntries"] = merged_authors
    author_names = [
        str(entry.get("name") or "").strip()
        for entry in merged_authors
        if isinstance(entry, dict) and str(entry.get("name") or "").strip()
    ]
    if author_names:
        meta["authors"] = ", ".join(author_names)
    elif isinstance(meta.get("authors"), str) and not str(meta.get("authors")).strip():
        for source in _source_field_order(is_pt, "title"):
            book = books.get(source)
            if book is None:
                continue
            book_meta = book.metadata if isinstance(book.metadata, dict) else {}
            authors = book_meta.get("authors")
            if isinstance(authors, str) and authors.strip():
                meta["authors"] = authors.strip()
                break

    from .book_catalog_policy import uses_openlibrary_catalog

    if uses_openlibrary_catalog():
        meta = _backfill_openlibrary_author_entries(
            clients.openlibrary,
            meta,
            external_id=external_id,
            source=primary_source,
        )
    meta[BOOK_DETAIL_ENRICHED_KEY] = True
    meta["catalogMergeVersion"] = CATALOG_MERGE_VERSION
    meta["catalogMergedSources"] = [source for source, book in books.items() if book is not None]
    meta.setdefault("importSource", primary_source)

    return OpenLibraryBook(
        external_id=external_id,
        title=merged_title,
        subtitle=merged_subtitle,
        description=merged_description,
        image_url=merged_image,
        metadata=meta,
    )


def _snapshot_openlibrary(
    client: OpenLibraryClient,
    *,
    title: str,
    metadata: dict[str, object],
    isbn: str,
    author_text: str | None,
) -> OpenLibraryBook | None:
    try:
        work_id = metadata.get("openLibraryWorkId")
        if isinstance(work_id, str) and work_id.strip():
            book = client.fetch_book_by_work_id(work_id.strip())
            if book is not None:
                return book
        if isbn:
            book = client.fetch_book_by_isbn(isbn)
            if book is not None:
                return book
        search_q = build_title_author_query(title, author_text)
        if not search_q:
            return None
        books = client.search_books(search_q, limit=6)
        return pick_best_catalog_match(books, title=title, authors=author_text)
    except OpenLibraryError:
        return None


def _snapshot_hardcover(
    client: HardcoverClient | None,
    *,
    title: str,
    isbn: str,
    author_text: str | None,
) -> OpenLibraryBook | None:
    if client is None or not client.enabled:
        return None
    try:
        if isbn:
            book = client.fetch_by_isbn(isbn)
            if book is not None:
                return book
        books = client.search_by_title_author(title, authors=author_text, limit=6)
        return pick_best_catalog_match(books, title=title, authors=author_text)
    except (HardcoverError, BookResolveError):
        return None


def _snapshot_porbase(
    client: PorbaseClient | None,
    *,
    title: str,
    isbn: str,
    author_text: str | None,
    ol_client: OpenLibraryClient,
) -> OpenLibraryBook | None:
    if client is None:
        return None
    try:
        if isbn:
            return client.fetch_by_isbn(isbn)
        from .book_catalog_resolver import BookLookupQuery, _resolve_porbase_by_title

        return _resolve_porbase_by_title(
            client,
            BookLookupQuery(title=title, authors=author_text),
            ol_client=ol_client,
        )
    except Exception:
        return None
