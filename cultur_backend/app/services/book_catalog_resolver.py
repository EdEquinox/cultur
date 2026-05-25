"""Multi-source book resolution; default catalog identity is Hardcover."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from ..book_catalog_clients import BookCatalogClients
from ..catalog_match import (
    build_title_author_query,
    catalog_match_score,
    pick_best_catalog_match,
)
from ..hardcover_client import HardcoverClient, HardcoverError
from ..openlibrary_client import (
    BOOK_DETAIL_ENRICHED_KEY,
    OpenLibraryBook,
    OpenLibraryClient,
    OpenLibraryError,
    _normalize_isbn,
)
from ..porbase_client import PorbaseClient, PorbaseError
from .book_catalog_policy import BookSearchSources

logger = logging.getLogger(__name__)


class BookResolveError(Exception):
    def __init__(self, reason: str, message: str) -> None:
        self.reason = reason
        self.message = message
        super().__init__(message)


@dataclass(frozen=True, slots=True)
class ResolvedCatalogBook:
    book: OpenLibraryBook
    source: str


@dataclass(frozen=True, slots=True)
class BookLookupQuery:
    title: str
    authors: str | None = None
    isbn: str | None = None


def resolve_single(clients: BookCatalogClients, query: BookLookupQuery) -> ResolvedCatalogBook:
    """Pick one catalog record and merge data from all providers."""
    return finalize_resolved_book(clients, _resolve_single_primary(clients, query))


def finalize_resolved_book(
    clients: BookCatalogClients,
    row: ResolvedCatalogBook,
) -> ResolvedCatalogBook:
    from .book_canonical_merge import merge_canonical_book

    meta = row.book.metadata if isinstance(row.book.metadata, dict) else {}
    try:
        book = merge_canonical_book(
            clients,
            primary_source=row.source,
            external_id=row.book.external_id,
            title=row.book.title,
            description=row.book.description,
            subtitle=row.book.subtitle,
            image_url=row.book.image_url,
            metadata=meta,
            extra_books=[(row.source, row.book)],
        )
    except (BookResolveError, PorbaseError, HardcoverError, OpenLibraryError) as exc:
        logger.warning("Canonical merge failed for %s: %s", row.source, exc)
        return row
    return ResolvedCatalogBook(book=book, source=row.source)


def _resolve_single_primary(clients: BookCatalogClients, query: BookLookupQuery) -> ResolvedCatalogBook:
    """Pick the primary catalog provider for import / ISBN lookup."""
    from .book_catalog_policy import (
        is_hardcover_primary,
        resolve_isbn_provider_order,
        resolve_title_provider_order,
    )

    row = query
    isbn = _normalize_isbn(row.isbn or "")
    failures: list[str] = []
    ol = clients.openlibrary
    pb = clients.porbase
    hc = clients.hardcover
    has_hc = hc is not None and hc.enabled

    if is_hardcover_primary() and not has_hc:
        logger.warning(
            "BOOK_CATALOG_PRIMARY_SOURCE=hardcover but HARDCOVER_API_TOKEN is missing; "
            "falling back to Open Library / PORBASE order.",
        )

    def try_provider(source: str) -> OpenLibraryBook:
        if source == "porbase":
            if pb is None:
                raise BookResolveError("porbase_unavailable", "PORBASE client not configured.")
            if isbn:
                return _resolve_porbase(pb, row, ol_client=ol)
            return _resolve_porbase_by_title(pb, row, ol_client=ol)
        if source == "hardcover":
            if hc is None or not hc.enabled:
                raise BookResolveError("hardcover_unavailable", "Hardcover is not configured.")
            if isbn:
                return _resolve_hardcover(hc, row)
            return _resolve_hardcover_by_title(hc, row)
        if isbn:
            return _resolve_openlibrary(ol, row)
        return _resolve_openlibrary_by_title(ol, row)

    order = (
        resolve_isbn_provider_order(has_porbase=pb is not None, has_hardcover=has_hc)
        if isbn
        else resolve_title_provider_order(has_porbase=pb is not None, has_hardcover=has_hc)
    )
    for source in order:
        label = {"porbase": "PORBASE", "hardcover": "Hardcover", "openlibrary": "Open Library"}[
            source
        ]
        try:
            book = try_provider(source)
            return ResolvedCatalogBook(book=book, source=source)
        except BookResolveError as exc:
            failures.append(f"{label}: {exc.message}")
        except (PorbaseError, HardcoverError, OpenLibraryError) as exc:
            failures.append(f"{label}: {exc}")

    context = "ISBN" if isbn else "title"
    raise BookResolveError(
        "not_found",
        f"No catalog match for {context}. " + " | ".join(failures),
    )


def search_catalog(
    clients: BookCatalogClients,
    *,
    query_text: str,
    authors: str | None = None,
    limit: int = 24,
    sources: BookSearchSources | None = None,
    auto_fallback: bool = False,
) -> list[ResolvedCatalogBook]:
    """Search books using configured catalog sources.

    Default (Hardcover-primary): query Hardcover only. Open Library and PORBASE run
    only when the client passes explicit ``sources`` (e.g. app source chips).
    """
    from .book_catalog_policy import BookSearchSources, default_search_sources

    src = sources or default_search_sources()
    return _search_catalog_with_sources(
        clients,
        query_text=query_text,
        authors=authors,
        limit=limit,
        sources=src,
    )


def _search_catalog_with_sources(
    clients: BookCatalogClients,
    *,
    query_text: str,
    authors: str | None,
    limit: int,
    sources: BookSearchSources,
) -> list[ResolvedCatalogBook]:
    text = (query_text or "").strip()
    if not text:
        return []

    isbn = _normalize_isbn(text)
    if isbn:
        return _search_by_isbn(
            clients,
            isbn=isbn,
            title=text,
            authors=authors,
            limit=limit,
            sources=sources,
        )

    title = text
    search_query = build_title_author_query(title, authors)
    merged: dict[str, ResolvedCatalogBook] = {}

    ol = clients.openlibrary
    hc = clients.hardcover
    pb = clients.porbase

    if sources.hardcover and hc is not None and hc.enabled:
        try:
            for book in hc.search_by_title_author(title, authors=authors, limit=limit):
                _add_search_result(
                    merged,
                    ResolvedCatalogBook(book=book, source="hardcover"),
                    clients=clients,
                )
        except HardcoverError as exc:
            logger.warning("Hardcover search failed: %s", exc)

    if sources.openlibrary:
        try:
            for book in ol.search_books(search_query, limit=limit):
                _add_search_result(
                    merged,
                    ResolvedCatalogBook(book=book, source="openlibrary"),
                    clients=clients,
                )
        except OpenLibraryError as exc:
            logger.warning("Open Library search failed: %s", exc)

    if sources.porbase and pb is not None:
        _enrich_pt_isbns_with_porbase(
            merged,
            pb,
            ol,
            clients=clients,
            title=title,
            authors=authors,
        )

    ranked = sorted(
        merged.values(),
        key=lambda row: catalog_match_score(row.book, title=title, authors=authors),
        reverse=True,
    )
    return ranked[:limit]


def refresh_book_from_providers(
    clients: BookCatalogClients,
    *,
    source: str,
    title: str,
    external_id: str,
    metadata: dict[str, object],
    description: str | None = None,
    subtitle: str | None = None,
    image_url: str | None = None,
) -> OpenLibraryBook:
    """Live refresh for catalog detail — canonical merge from all providers."""
    book, _notes = enrich_book_from_all_providers(
        clients,
        title=title,
        external_id=external_id,
        source=source,
        metadata=metadata,
        description=description,
        subtitle=subtitle,
        image_url=image_url,
    )
    return book


def federate_catalog_books(
    clients: BookCatalogClients,
    ol_books: list[OpenLibraryBook],
    *,
    query_title: str | None = None,
    query_authors: str | None = None,
    limit: int | None = None,
    hardcover_title_search: bool = True,
) -> list[ResolvedCatalogBook]:
    """Enrich an Open Library result set with Hardcover ISBN matches and PORBASE (PT)."""
    merged: dict[str, ResolvedCatalogBook] = {}
    title = (query_title or "").strip()
    authors = query_authors

    for book in ol_books:
        _add_search_result(
            merged,
            ResolvedCatalogBook(book=book, source="openlibrary"),
            clients=clients,
        )

    hc = clients.hardcover
    if hc is not None and hc.enabled:
        for key in list(merged.keys()):
            if not key.startswith("isbn:"):
                continue
            isbn = key.removeprefix("isbn:")
            try:
                hc_book = hc.fetch_by_isbn(isbn)
            except HardcoverError:
                continue
            if hc_book is not None:
                _add_search_result(
                    merged,
                    ResolvedCatalogBook(book=hc_book, source="hardcover"),
                    clients=clients,
                )
        if hardcover_title_search and title:
            try:
                for book in hc.search_by_title_author(title, authors=authors, limit=limit or 24):
                    _add_search_result(
                        merged,
                        ResolvedCatalogBook(book=book, source="hardcover"),
                        clients=clients,
                    )
            except HardcoverError as exc:
                logger.warning("Hardcover search failed during federate: %s", exc)

    pb = clients.porbase
    if pb is not None:
        _enrich_pt_isbns_with_porbase(
            merged,
            pb,
            clients.openlibrary,
            clients=clients,
            title=title or "books",
            authors=authors,
        )

    ranked = sorted(
        merged.values(),
        key=lambda row: catalog_match_score(
            row.book,
            title=title or row.book.title,
            authors=authors,
        ),
        reverse=True,
    )
    if limit is not None:
        return ranked[: max(1, limit)]
    return ranked


def merge_resolved_catalog_rows(
    *groups: list[ResolvedCatalogBook],
    limit: int,
    query_title: str = "",
    query_authors: str | None = None,
    clients: BookCatalogClients | None = None,
) -> list[ResolvedCatalogBook]:
    """Dedupe and rank multiple federated result groups."""
    merged: dict[str, ResolvedCatalogBook] = {}
    title = query_title.strip()
    for group in groups:
        for row in group:
            _add_search_result(merged, row, clients=clients)
    ranked = sorted(
        merged.values(),
        key=lambda row: catalog_match_score(
            row.book,
            title=title or row.book.title,
            authors=query_authors,
        ),
        reverse=True,
    )
    return ranked[: max(1, limit)]


def _search_by_isbn(
    clients: BookCatalogClients,
    *,
    isbn: str,
    title: str,
    authors: str | None,
    limit: int,
    sources: BookSearchSources,
) -> list[ResolvedCatalogBook]:
    lookup = BookLookupQuery(title=title or isbn, authors=authors, isbn=isbn)
    if sources.openlibrary and not sources.hardcover and not sources.porbase:
        try:
            book = _resolve_openlibrary(clients.openlibrary, lookup)
            return [ResolvedCatalogBook(book=book, source="openlibrary")]
        except (BookResolveError, OpenLibraryError):
            return []
    if sources.porbase and not sources.hardcover and not sources.openlibrary:
        pb = clients.porbase
        if pb is None:
            return []
        try:
            book = _resolve_porbase(pb, lookup, ol_client=clients.openlibrary)
            return [ResolvedCatalogBook(book=book, source="porbase")]
        except (BookResolveError, PorbaseError):
            return []
    try:
        return [resolve_single(clients, lookup)]
    except BookResolveError:
        return []


def _enrich_pt_isbns_with_porbase(
    merged: dict[str, ResolvedCatalogBook],
    pb: PorbaseClient,
    ol: OpenLibraryClient,
    *,
    clients: BookCatalogClients,
    title: str,
    authors: str | None,
) -> None:
    for key, row in list(merged.items()):
        if not key.startswith("isbn:"):
            continue
        isbn = key.removeprefix("isbn:")
        if not (isbn.startswith("978989") or isbn.startswith("978972")):
            continue
        try:
            porbase_book = pb.fetch_by_isbn(isbn)
        except PorbaseError:
            continue
        if porbase_book is not None:
            _add_search_result(
                merged,
                ResolvedCatalogBook(book=porbase_book, source="porbase"),
                clients=clients,
            )

    # Also try discovery from OL for PT titles not yet in merged
    candidates = _discover_isbn_candidates(
        BookLookupQuery(title=title, authors=authors),
        ol,
    )
    for candidate_isbn in candidates:
        if not (candidate_isbn.startswith("978989") or candidate_isbn.startswith("978972")):
            continue
        key = f"isbn:{candidate_isbn}"
        if key in merged:
            continue
        try:
            porbase_book = pb.fetch_by_isbn(candidate_isbn)
        except PorbaseError:
            continue
        if porbase_book is not None:
            _add_search_result(
                merged,
                ResolvedCatalogBook(book=porbase_book, source="porbase"),
                clients=clients,
            )


def _add_search_result(
    merged: dict[str, ResolvedCatalogBook],
    row: ResolvedCatalogBook,
    *,
    clients: BookCatalogClients | None = None,
) -> None:
    key = _result_key(row)
    existing = merged.get(key)
    if existing is None:
        merged[key] = row
        return
    from .book_catalog_policy import merge_source_priority

    priority = merge_source_priority()
    if clients is None:
        if priority.get(row.source, 0) > priority.get(existing.source, 0):
            merged[key] = row
        return
    from .book_canonical_merge import merge_canonical_book
    primary = (
        existing
        if priority.get(existing.source, 0) >= priority.get(row.source, 0)
        else row
    )
    book = merge_canonical_book(
        clients,
        primary_source=primary.source,
        external_id=primary.book.external_id,
        title=primary.book.title,
        description=primary.book.description,
        subtitle=primary.book.subtitle,
        image_url=primary.book.image_url,
        metadata=primary.book.metadata if isinstance(primary.book.metadata, dict) else {},
        extra_books=[
            (existing.source, existing.book),
            (row.source, row.book),
        ],
    )
    merged[key] = ResolvedCatalogBook(book=book, source=primary.source)


def _result_key(row: ResolvedCatalogBook) -> str:
    meta = row.book.metadata if isinstance(row.book.metadata, dict) else {}
    isbn = _normalize_isbn(str(meta.get("isbn") or ""))
    if isbn:
        return f"isbn:{isbn}"
    return f"{row.source}:{row.book.external_id}"


def _refresh_porbase(
    client: PorbaseClient,
    *,
    title: str,
    external_id: str,
    metadata: dict[str, object],
) -> OpenLibraryBook:
    isbn = _normalize_isbn(str(metadata.get("isbn") or "")) or _normalize_isbn(external_id)
    if not isbn:
        raise BookResolveError("porbase_no_isbn", "Cannot refresh PORBASE book without ISBN.")
    book = client.fetch_by_isbn(isbn)
    if book is None:
        raise BookResolveError("not_found", f"ISBN {isbn} not found in PORBASE.")
    return book


def _refresh_hardcover(
    client: HardcoverClient,
    *,
    title: str,
    external_id: str,
    metadata: dict[str, object],
) -> OpenLibraryBook:
    isbn = _normalize_isbn(str(metadata.get("isbn") or ""))
    if isbn:
        book = client.fetch_by_isbn(isbn)
        if book is not None:
            return book
    authors = metadata.get("authors")
    author_text = authors if isinstance(authors, str) else None
    books = client.search_by_title_author(title, authors=author_text, limit=6)
    best = pick_best_catalog_match(books, title=title, authors=author_text)
    if best is not None:
        return best
    raise BookResolveError("not_found", "Book not found on Hardcover.")


def _resolve_porbase(
    client: PorbaseClient,
    query: BookLookupQuery,
    *,
    ol_client: OpenLibraryClient | None = None,
) -> OpenLibraryBook:
    isbn = _normalize_isbn(query.isbn or "")
    if isbn:
        book = client.fetch_by_isbn(isbn)
        if book is not None:
            return book
    return _resolve_porbase_by_title(client, query, ol_client=ol_client)


def _resolve_porbase_by_title(
    client: PorbaseClient,
    query: BookLookupQuery,
    *,
    ol_client: OpenLibraryClient | None = None,
) -> OpenLibraryBook:
    candidates = _discover_isbn_candidates(query, ol_client)
    if not candidates:
        raise BookResolveError(
            "porbase_title_not_found",
            "No ISBN candidates for PORBASE title/author lookup.",
        )
    books: list[OpenLibraryBook] = []
    for isbn in candidates:
        book = client.fetch_by_isbn(isbn)
        if book is not None:
            books.append(book)
    if not books:
        raise BookResolveError(
            "porbase_title_not_found",
            "Title/author search found ISBNs but none exist in PORBASE.",
        )
    best = pick_best_catalog_match(books, title=query.title, authors=query.authors)
    if best is None:
        raise BookResolveError(
            "porbase_title_ambiguous",
            f'PORBASE matches do not align with "{query.title}".',
        )
    return best


def _discover_isbn_candidates(
    query: BookLookupQuery,
    ol_client: OpenLibraryClient | None,
) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []

    def add(raw: str | None) -> None:
        normalized = _normalize_isbn(raw or "")
        if normalized and normalized not in seen:
            seen.add(normalized)
            ordered.append(normalized)

    add(query.isbn)
    search_q = build_title_author_query(query.title, query.authors)
    if not search_q:
        return _prioritize_pt_isbns(ordered)

    if ol_client is not None:
        try:
            for book in ol_client.search_books(search_q, limit=8):
                meta = book.metadata if isinstance(book.metadata, dict) else {}
                add(str(meta.get("isbn") or ""))
        except OpenLibraryError:
            pass

    return _prioritize_pt_isbns(ordered)


def _prioritize_pt_isbns(isbns: list[str]) -> list[str]:
    pt = [i for i in isbns if i.startswith("978989") or i.startswith("978972")]
    other = [i for i in isbns if i not in pt]
    return (pt + other)[:12]


def _resolve_hardcover(client: HardcoverClient, query: BookLookupQuery) -> OpenLibraryBook:
    isbn = _normalize_isbn(query.isbn or "")
    if isbn:
        book = client.fetch_by_isbn(isbn)
        if book is not None:
            return book
    return _resolve_hardcover_by_title(client, query)


def _resolve_hardcover_by_title(client: HardcoverClient, query: BookLookupQuery) -> OpenLibraryBook:
    books = client.search_by_title_author(query.title, authors=query.authors, limit=8)
    if not books:
        raise BookResolveError(
            "hardcover_title_not_found",
            "No Hardcover match for title/author.",
        )
    best = pick_best_catalog_match(books, title=query.title, authors=query.authors)
    if best is None:
        raise BookResolveError(
            "hardcover_title_ambiguous",
            f'Hardcover best match looks too different from "{query.title}".',
        )
    row_isbn = _normalize_isbn(query.isbn or "")
    if row_isbn:
        for book in books:
            meta = book.metadata if isinstance(book.metadata, dict) else {}
            candidate = _normalize_isbn(str(meta.get("isbn") or ""))
            if candidate == row_isbn:
                return book
        edition = client.fetch_by_isbn(row_isbn)
        if edition is not None:
            return edition
    return best


def _resolve_openlibrary(client: OpenLibraryClient, query: BookLookupQuery) -> OpenLibraryBook:
    isbn = _normalize_isbn(query.isbn or "")
    if isbn:
        books = client.search_books("", isbn=isbn, limit=5)
        if books:
            best = pick_best_catalog_match(books, title=query.title, authors=query.authors)
            if best is not None:
                return best
        by_isbn = client.fetch_book_by_isbn(isbn)
        if by_isbn is not None:
            return by_isbn
        try:
            return _resolve_openlibrary_by_title(client, query)
        except BookResolveError:
            raise BookResolveError(
                "isbn_not_found",
                f"ISBN {isbn} is not on Open Library and title search did not find a close match.",
            ) from None
    return _resolve_openlibrary_by_title(client, query)


def _resolve_openlibrary_by_title(
    client: OpenLibraryClient,
    query: BookLookupQuery,
) -> OpenLibraryBook:
    search_q = build_title_author_query(query.title, query.authors)
    books = client.search_books(search_q, limit=8)
    if not books:
        raise BookResolveError(
            "title_not_found",
            "No Open Library match for title.",
        )
    best = pick_best_catalog_match(books, title=query.title, authors=query.authors)
    if best is None:
        raise BookResolveError(
            "title_ambiguous",
            f'Best Open Library match looks too different from "{query.title}".',
        )
    return best


_METADATA_URL_KEYS = (
    "porbaseUrl",
    "hardcoverUrl",
    "openLibraryUrl",
    "googleBooksUrl",
    "openLibrarySeriesUrl",
    "hardcoverBookId",
    "hardcoverSlug",
    "openLibraryWorkId",
    "openLibraryEditionId",
)

_METADATA_FILL_KEYS = (
    "isbn",
    "pageCount",
    "firstPublishYear",
    "bookLanguage",
    "bookLanguageCode",
    "openLibraryRating",
    "publisher",
)


def _author_entry_name_key(entry: object) -> str | None:
    if not isinstance(entry, dict):
        return None
    name = str(entry.get("name") or "").strip().casefold()
    return name or None


def _merge_author_entries(
    base_entries: object,
    incoming_entries: object,
) -> list[dict[str, object]]:
    """Union author rows by name; keep Open Library ids when providers omit them."""
    ordered_names: list[str] = []
    merged: dict[str, dict[str, object]] = {}

    def absorb(entry: object) -> None:
        if not isinstance(entry, dict):
            return
        name_key = _author_entry_name_key(entry)
        if name_key is None:
            return
        author_id = str(entry.get("id") or "").strip()
        image_url = entry.get("imageUrl")
        existing = merged.get(name_key)
        if existing is None:
            merged[name_key] = {
                "id": author_id,
                "name": str(entry.get("name") or "").strip(),
            }
            if isinstance(image_url, str) and image_url.strip():
                merged[name_key]["imageUrl"] = image_url.strip()
            ordered_names.append(name_key)
            return
        existing_id = str(existing.get("id") or "").strip()
        if not existing_id and author_id:
            existing["id"] = author_id
        if (
            not isinstance(existing.get("imageUrl"), str)
            and isinstance(image_url, str)
            and image_url.strip()
        ):
            existing["imageUrl"] = image_url.strip()

    if isinstance(base_entries, list):
        for entry in base_entries:
            absorb(entry)
    if isinstance(incoming_entries, list):
        for entry in incoming_entries:
            absorb(entry)

    return [merged[name_key] for name_key in ordered_names]


def merge_book_metadata(
    base: dict[str, object],
    incoming: dict[str, object],
) -> dict[str, object]:
    """Merge provider metadata into an existing book row (fill gaps, union lists)."""
    out = dict(base)
    for key in _METADATA_URL_KEYS:
        value = incoming.get(key)
        if isinstance(value, str) and value.strip() and not out.get(key):
            out[key] = value.strip()

    for key in _METADATA_FILL_KEYS:
        if out.get(key) in (None, "", 0) and incoming.get(key) not in (None, "", 0):
            out[key] = incoming[key]

    base_authors = str(out.get("authors") or "").strip()
    incoming_authors = str(incoming.get("authors") or "").strip()
    if len(incoming_authors) > len(base_authors):
        out["authors"] = incoming_authors

    merged_authors = _merge_author_entries(out.get("authorEntries"), incoming.get("authorEntries"))
    if merged_authors:
        out["authorEntries"] = merged_authors

    base_publishers = out.get("publisherEntries")
    incoming_publishers = incoming.get("publisherEntries")
    if isinstance(incoming_publishers, list):
        merged_publishers = (
            list(base_publishers) if isinstance(base_publishers, list) else []
        )
        seen = {
            str(entry.get("id") or "").strip()
            for entry in merged_publishers
            if isinstance(entry, dict)
        }
        for entry in incoming_publishers:
            if not isinstance(entry, dict):
                continue
            publisher_id = str(entry.get("id") or "").strip()
            if publisher_id and publisher_id not in seen:
                seen.add(publisher_id)
                merged_publishers.append(entry)
        if merged_publishers:
            out["publisherEntries"] = merged_publishers

    for list_key in ("subjects", "seriesNames"):
        base_list = out.get(list_key)
        incoming_list = incoming.get(list_key)
        if not isinstance(incoming_list, list):
            continue
        merged: list[object] = list(base_list) if isinstance(base_list, list) else []
        seen_values = {str(value).strip().lower() for value in merged if str(value).strip()}
        for value in incoming_list:
            text = str(value).strip()
            if not text:
                continue
            lowered = text.lower()
            if lowered not in seen_values:
                seen_values.add(lowered)
                merged.append(value)
        if merged:
            out[list_key] = merged

    return out


def _resolve_openlibrary_work_id(
    client: OpenLibraryClient,
    metadata: dict[str, object],
    *,
    external_id: str | None = None,
    source: str | None = None,
) -> str | None:
    from ..openlibrary_client import _normalize_work_id

    work_id = metadata.get("openLibraryWorkId")
    if isinstance(work_id, str):
        normalized = _normalize_work_id(work_id.strip())
        if normalized:
            return normalized

    ol_url = metadata.get("openLibraryUrl")
    if isinstance(ol_url, str) and "/works/" in ol_url:
        fragment = ol_url.rsplit("/works/", 1)[-1].split("/", 1)[0].strip()
        normalized = _normalize_work_id(fragment)
        if normalized:
            return normalized

    if source == "openlibrary" and external_id:
        normalized = _normalize_work_id(external_id.strip())
        if normalized:
            return normalized

    isbn = metadata.get("isbn")
    if isinstance(isbn, str) and isbn.strip():
        try:
            book = client.fetch_book_by_isbn(isbn.strip())
        except OpenLibraryError:
            book = None
        if book is not None:
            book_meta = book.metadata if isinstance(book.metadata, dict) else {}
            candidate = book_meta.get("openLibraryWorkId")
            if isinstance(candidate, str):
                normalized = _normalize_work_id(candidate.strip())
                if normalized:
                    return normalized
            external = book.external_id
            if isinstance(external, str):
                normalized = _normalize_work_id(external.strip())
                if normalized:
                    return normalized

    return None


def _backfill_openlibrary_author_entries(
    client: OpenLibraryClient,
    metadata: dict[str, object],
    *,
    external_id: str | None = None,
    source: str | None = None,
) -> dict[str, object]:
    """Fill missing Open Library author ids so detail links work."""
    from ..openlibrary_client import (
        _authors_from_work,
        resolve_openlibrary_author_id,
    )

    entries_raw = metadata.get("authorEntries")
    entries: list[dict[str, object]] = []
    if isinstance(entries_raw, list):
        entries = [entry for entry in entries_raw if isinstance(entry, dict)]
    if not entries:
        authors_raw = metadata.get("authors")
        if isinstance(authors_raw, str) and authors_raw.strip():
            entries = [
                {"id": "", "name": name.strip()}
                for name in authors_raw.split(",")
                if name.strip()
            ]
    if not entries:
        return metadata

    if all(
        str(entry.get("id") or "").strip() and str(entry.get("imageUrl") or "").strip()
        for entry in entries
    ):
        return metadata

    work_id = _resolve_openlibrary_work_id(
        client,
        metadata,
        external_id=external_id,
        source=source,
    )
    ol_entries: list[dict[str, object]] = []
    if work_id:
        try:
            payload = client._get_json(f"/works/{work_id}.json", {})
            ol_entries = _authors_from_work(client, payload, limit=12)
        except OpenLibraryError:
            ol_entries = []

    merged = _merge_author_entries(entries, ol_entries) if ol_entries else list(entries)

    resolved_by_name: list[dict[str, object]] = []
    for entry in merged:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name") or "").strip()
        author_id = str(entry.get("id") or "").strip()
        if not name:
            continue
        if not author_id and len(resolved_by_name) < 4:
            author_id = resolve_openlibrary_author_id(client, name) or ""
            if author_id:
                resolved_by_name.append({"id": author_id, "name": name})
                continue
        resolved_by_name.append(entry)

    if resolved_by_name:
        merged = _merge_author_entries(merged, resolved_by_name)

    if not merged or merged == entries:
        return metadata

    out = dict(metadata)
    out["authorEntries"] = merged
    if work_id and not out.get("openLibraryWorkId"):
        out["openLibraryWorkId"] = work_id
    return out


def _hardcover_author_image_url(author: dict[str, object]) -> str | None:
    cached_image = author.get("cached_image")
    if isinstance(cached_image, str) and cached_image.startswith("http"):
        return cached_image.replace("http://", "https://")
    if isinstance(cached_image, dict):
        for key in ("url", "image_url", "large", "medium"):
            val = cached_image.get(key)
            if isinstance(val, str) and val.startswith("http"):
                return val.replace("http://", "https://")
    return None


def _openlibrary_author_image_url(client: OpenLibraryClient, author_id: str) -> str | None:
    try:
        author = client.fetch_author_by_id(author_id)
    except OpenLibraryError:
        return None
    if author is None:
        return None
    url = (author.image_url or "").strip()
    return url or None


def enrich_author_entry_images(
    book_clients: BookCatalogClients,
    metadata: dict[str, object],
    *,
    allow_openlibrary: bool = True,
    max_image_lookups: int = 8,
) -> dict[str, object]:
    """Attach author photos to authorEntries for book detail hero chips."""
    entries_raw = metadata.get("authorEntries")
    if not isinstance(entries_raw, list):
        return metadata

    enriched: list[dict[str, object]] = []
    changed = False
    lookups = 0
    for row in entries_raw:
        if not isinstance(row, dict):
            continue
        entry = dict(row)
        if str(entry.get("imageUrl") or "").strip():
            enriched.append(entry)
            continue
        if lookups >= max(0, max_image_lookups):
            enriched.append(entry)
            continue
        author_id = str(entry.get("id") or "").strip()
        provider = str(entry.get("provider") or entry.get("source") or "").strip().lower()
        image_url: str | None = None
        if (provider == "hardcover" or author_id.isdigit()) and book_clients.hardcover is not None:
            hc = book_clients.hardcover
            if hc.enabled and author_id.isdigit():
                lookups += 1
                author = hc.fetch_author_by_id(author_id)
                if isinstance(author, dict):
                    image_url = _hardcover_author_image_url(author)
        elif allow_openlibrary and author_id and re.fullmatch(r"OL\d+A", author_id):
            lookups += 1
            image_url = _openlibrary_author_image_url(book_clients.openlibrary, author_id)
        elif allow_openlibrary and author_id:
            lookups += 1
            image_url = _openlibrary_author_image_url(book_clients.openlibrary, author_id)
        if image_url:
            entry["imageUrl"] = image_url
            changed = True
        enriched.append(entry)

    if not changed:
        return metadata
    out = dict(metadata)
    out["authorEntries"] = enriched
    return out


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


def _fetch_openlibrary_for_enrichment(
    client: OpenLibraryClient,
    *,
    title: str,
    authors: str | None,
    isbn: str,
    metadata: dict[str, object],
) -> OpenLibraryBook | None:
    work_id = metadata.get("openLibraryWorkId")
    if isinstance(work_id, str) and work_id.strip():
        book = client.fetch_book_by_work_id(work_id.strip())
        if book is not None:
            return book
    if isbn:
        book = client.fetch_book_by_isbn(isbn)
        if book is not None:
            return book
    search_q = build_title_author_query(title, authors)
    if not search_q:
        return None
    books = client.search_books(search_q, limit=8)
    return pick_best_catalog_match(books, title=title, authors=authors)


def enrich_book_from_all_providers(
    clients: BookCatalogClients,
    *,
    title: str,
    external_id: str,
    source: str,
    metadata: dict[str, object],
    description: str | None = None,
    subtitle: str | None = None,
    image_url: str | None = None,
) -> tuple[OpenLibraryBook, list[str]]:
    """Fetch all providers and build one canonical merged book."""
    from .book_canonical_merge import collect_provider_snapshots, merge_canonical_book

    meta = dict(metadata)
    snapshots = collect_provider_snapshots(clients, title=title, metadata=meta)
    notes: list[str] = []
    for provider, book in snapshots.items():
        if book is None:
            notes.append(f"{provider}: no match")
    book = merge_canonical_book(
        clients,
        primary_source=source,
        external_id=external_id,
        title=title,
        description=description,
        subtitle=subtitle,
        image_url=image_url,
        metadata=meta,
        provider_snapshots=snapshots,
    )
    return book, notes
