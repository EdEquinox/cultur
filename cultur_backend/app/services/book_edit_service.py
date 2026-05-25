"""User-editable book metadata with per-field provider options."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..backend_models import MediaItem
from ..book_catalog_clients import BookCatalogClients
from ..hardcover_client import HardcoverClient, HardcoverError
from ..openlibrary_client import (
    OpenLibraryBook,
    OpenLibraryClient,
    OpenLibraryError,
    subjects_list_from_metadata,
)
from ..porbase_client import PorbaseClient, PorbaseError
from ..catalog_match import build_title_author_query
from .book_catalog_resolver import (
    BookLookupQuery,
    BookResolveError,
    ResolvedCatalogBook,
    _normalize_isbn,
    pick_best_catalog_match,
    search_catalog,
)

_PROVIDER_LABELS = {
    "current": "Saved copy",
    "openlibrary": "Open Library",
    "hardcover": "Hardcover",
    "porbase": "PORBASE",
    "manual": "Custom",
}


@dataclass(frozen=True, slots=True)
class _BookFieldSpec:
    key: str
    label: str
    column: str | None = None
    metadata_key: str | None = None
    multiline: bool = False


BOOK_EDITABLE_FIELDS: tuple[_BookFieldSpec, ...] = (
    _BookFieldSpec("title", "Title", column="title"),
    _BookFieldSpec("subtitle", "Subtitle", column="subtitle"),
    _BookFieldSpec("description", "Description", column="description", multiline=True),
    _BookFieldSpec("imageUrl", "Cover image URL", column="image_url"),
    _BookFieldSpec("authors", "Authors", metadata_key="authors"),
    _BookFieldSpec("isbn", "ISBN", metadata_key="isbn"),
    _BookFieldSpec("pageCount", "Page count", metadata_key="pageCount"),
    _BookFieldSpec("firstPublishYear", "First published", metadata_key="firstPublishYear"),
    _BookFieldSpec("bookLanguage", "Language", metadata_key="bookLanguage"),
    _BookFieldSpec("publisher", "Publisher", metadata_key="publisher"),
    _BookFieldSpec("subjects", "Subjects / tags", metadata_key="subjects"),
    _BookFieldSpec("porbaseUrl", "PORBASE link", metadata_key="porbaseUrl"),
    _BookFieldSpec("hardcoverUrl", "Hardcover link", metadata_key="hardcoverUrl"),
    _BookFieldSpec("openLibraryUrl", "Open Library link", metadata_key="openLibraryUrl"),
)

_FIELD_BY_KEY = {field.key: field for field in BOOK_EDITABLE_FIELDS}


def list_book_edit_fields(item: MediaItem) -> list[dict[str, object]]:
    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    sources = meta.get("userFieldSources")
    field_sources = sources if isinstance(sources, dict) else {}
    rows: list[dict[str, object]] = []
    for spec in BOOK_EDITABLE_FIELDS:
        value = read_book_field_value(item, spec.key)
        rows.append(
            {
                "key": spec.key,
                "label": spec.label,
                "multiline": spec.multiline,
                "currentValue": _format_display_value(value),
                "source": str(field_sources.get(spec.key) or "current"),
            },
        )
    return rows


def read_book_field_value(item: MediaItem, field_key: str) -> object | None:
    spec = _FIELD_BY_KEY.get(field_key)
    if spec is None:
        raise HTTPException(status_code=400, detail=f"Unknown book field: {field_key}")
    if spec.column:
        return getattr(item, spec.column, None)
    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    if spec.metadata_key == "subjects":
        subjects = subjects_list_from_metadata(meta)
        return ", ".join(subjects) if subjects else None
    return meta.get(spec.metadata_key)


def search_books_for_edit(
    book_clients: BookCatalogClients,
    *,
    query: str,
    limit: int = 20,
    sources: object | None = None,
) -> list[dict[str, object]]:
    from .book_catalog_policy import BookSearchSources, default_search_sources

    text = (query or "").strip()
    if not text:
        return []
    src = sources if isinstance(sources, BookSearchSources) else default_search_sources()
    resolved = search_catalog(
        book_clients,
        query_text=text,
        limit=max(1, min(limit, 30)),
        sources=src,
    )
    hits: list[dict[str, object]] = []
    for row in resolved:
        book = row.book
        meta = book.metadata if isinstance(book.metadata, dict) else {}
        authors = meta.get("authors")
        isbn = meta.get("isbn")
        hits.append(
            {
                "source": row.source,
                "externalId": book.external_id,
                "title": book.title,
                "subtitle": book.subtitle,
                "authors": str(authors).strip() if isinstance(authors, str) else None,
                "isbn": str(isbn).strip() if isinstance(isbn, str) else None,
                "imageUrl": book.image_url,
            },
        )
    return hits


def fetch_book_snapshot_by_lookup(
    book_clients: BookCatalogClients,
    *,
    source: str,
    external_id: str,
    isbn: str | None = None,
    title: str | None = None,
    authors: str | None = None,
) -> OpenLibraryBook | None:
    normalized_source = (source or "").strip().lower()
    external = (external_id or "").strip()
    if not normalized_source or not external:
        return None
    meta: dict[str, object] = {}
    if isbn:
        meta["isbn"] = _normalize_isbn(isbn)
    if title:
        meta["title"] = title
    if authors:
        meta["authors"] = authors
    if normalized_source == "openlibrary":
        meta["openLibraryWorkId"] = external
        return _snapshot_openlibrary(
            book_clients.openlibrary,
            title=title or "",
            metadata=meta,
            isbn=str(meta.get("isbn") or ""),
            author_text=authors,
        )
    if normalized_source == "hardcover":
        client = book_clients.hardcover
        if client is None or not client.enabled:
            return None
        if meta.get("isbn"):
            book = client.fetch_by_isbn(str(meta["isbn"]))
            if book is not None:
                return book
        books = client.search_by_title_author(title or external, authors=authors, limit=8)
        for book in books:
            if book.external_id == external:
                return book
        return pick_best_catalog_match(books, title=title or "", authors=authors)
    if normalized_source == "porbase":
        client = book_clients.porbase
        if client is None:
            return None
        if meta.get("isbn"):
            return client.fetch_by_isbn(str(meta["isbn"]))
        return _snapshot_porbase(
            client,
            title=title or "",
            isbn="",
            author_text=authors,
            ol_client=book_clients.openlibrary,
        )
    return None


def get_book_field_options(
    book_clients: BookCatalogClients,
    item: MediaItem,
    *,
    field_key: str,
    lookup_source: str | None = None,
    lookup_external_id: str | None = None,
    lookup_isbn: str | None = None,
    lookup_title: str | None = None,
    lookup_authors: str | None = None,
    search_query: str | None = None,
) -> dict[str, object]:
    spec = _FIELD_BY_KEY.get(field_key)
    if spec is None:
        raise HTTPException(status_code=400, detail=f"Unknown book field: {field_key}")

    meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
    current = read_book_field_value(item, field_key)
    snapshots = fetch_book_snapshots_from_providers(
        book_clients,
        title=item.title,
        metadata=meta,
    )

    lookup_rows: list[ResolvedCatalogBook] = []
    if lookup_source and lookup_external_id:
        lookup_book = fetch_book_snapshot_by_lookup(
            book_clients,
            source=lookup_source,
            external_id=lookup_external_id,
            isbn=lookup_isbn,
            title=lookup_title or item.title,
            authors=lookup_authors,
        )
        if lookup_book is not None:
            lookup_rows.append(
                ResolvedCatalogBook(
                    book=lookup_book,
                    source=lookup_source.strip().lower(),
                ),
            )

    search_text = (search_query or "").strip()
    if search_text:
        lookup_rows.extend(
            search_catalog(book_clients, query_text=search_text, limit=12),
        )

    options: list[dict[str, object]] = []
    seen_display: set[str] = set()

    def add_option(
        provider: str,
        *,
        value: object | None,
        display_value: str,
        metadata_patch: dict[str, object] | None = None,
        label: str | None = None,
    ) -> None:
        text = display_value.strip()
        if not text:
            return
        lowered = text.casefold()
        if lowered in seen_display:
            return
        seen_display.add(lowered)
        options.append(
            {
                "provider": provider,
                "label": label or _PROVIDER_LABELS.get(provider, provider),
                "displayValue": text,
                "value": value,
                "metadataPatch": metadata_patch,
            },
        )

    current_display = _format_display_value(current)
    if current_display:
        patch = _metadata_patch_for_field(spec, item, meta) if spec.metadata_key else None
        add_option(
            "current",
            value=current,
            display_value=current_display,
            metadata_patch=patch,
        )

    for provider, book in snapshots.items():
        if book is None:
            continue
        value = _extract_from_book(book, spec)
        display = _format_display_value(value)
        if not display:
            continue
        patch = None
        if spec.metadata_key:
            book_meta = book.metadata if isinstance(book.metadata, dict) else {}
            patch = _metadata_patch_for_provider_field(spec, book_meta)
        add_option(
            provider,
            value=value,
            display_value=display,
            metadata_patch=patch,
        )

    for row in lookup_rows:
        book = row.book
        value = _extract_from_book(book, spec)
        display = _format_display_value(value)
        if not display:
            continue
        book_meta = book.metadata if isinstance(book.metadata, dict) else {}
        patch = _metadata_patch_for_provider_field(spec, book_meta) if spec.metadata_key else None
        provider_label = _PROVIDER_LABELS.get(row.source, row.source)
        short_title = book.title.strip()
        if len(short_title) > 48:
            short_title = f"{short_title[:45]}…"
        add_option(
            f"{row.source}:{book.external_id}",
            value=value,
            display_value=display,
            metadata_patch=patch,
            label=f"{provider_label} — {short_title}",
        )

    return {
        "field": field_key,
        "label": spec.label,
        "multiline": spec.multiline,
        "currentValue": current_display,
        "options": options,
    }


def patch_book_catalog_edit(
    db: Session,
    item: MediaItem,
    *,
    fields: dict[str, Any],
    field_sources: dict[str, str] | None = None,
    metadata_patches: list[dict[str, object]] | None = None,
) -> MediaItem:
    if item.media_type != "book":
        raise HTTPException(status_code=400, detail="Media item is not a book.")

    meta = dict(item.provider_payload) if isinstance(item.provider_payload, dict) else {}

    for patch in metadata_patches or []:
        if isinstance(patch, dict):
            meta.update(patch)

    for raw_key, raw_value in fields.items():
        spec = _FIELD_BY_KEY.get(raw_key)
        if spec is None:
            continue
        apply_book_field_value(item, meta, spec, raw_value)

    if field_sources:
        existing_sources = meta.get("userFieldSources")
        merged_sources = dict(existing_sources) if isinstance(existing_sources, dict) else {}
        merged_sources.update(field_sources)
        meta["userFieldSources"] = merged_sources

    meta["userEdited"] = True
    item.provider_payload = meta
    db.commit()
    db.refresh(item)
    return item


def apply_book_field_value(
    item: MediaItem,
    meta: dict[str, object],
    spec: _BookFieldSpec,
    raw_value: Any,
) -> None:
    if spec.column:
        if spec.column == "image_url":
            text = str(raw_value or "").strip()
            item.image_url = text or None
            return
        text = str(raw_value or "").strip()
        if spec.column == "description":
            item.description = text or None
            return
        setattr(item, spec.column, text or None)
        return

    if spec.metadata_key == "subjects":
        if raw_value is None:
            meta.pop("subjects", None)
            return
        if isinstance(raw_value, list):
            meta["subjects"] = [str(v).strip() for v in raw_value if str(v).strip()]
            return
        text = str(raw_value).strip()
        if not text:
            meta.pop("subjects", None)
            return
        meta["subjects"] = [part.strip() for part in text.split(",") if part.strip()]
        return

    if spec.metadata_key == "pageCount":
        if raw_value in (None, ""):
            meta.pop("pageCount", None)
            return
        try:
            meta["pageCount"] = int(raw_value)
        except (TypeError, ValueError):
            meta.pop("pageCount", None)
        return

    if spec.metadata_key == "firstPublishYear":
        if raw_value in (None, ""):
            meta.pop("firstPublishYear", None)
            return
        try:
            meta["firstPublishYear"] = int(raw_value)
        except (TypeError, ValueError):
            meta.pop("firstPublishYear", None)
        return

    if raw_value in (None, ""):
        meta.pop(spec.metadata_key or "", None)
        return
    meta[spec.metadata_key or ""] = str(raw_value).strip()


def fetch_book_snapshots_from_providers(
    clients: BookCatalogClients,
    *,
    title: str,
    metadata: dict[str, object],
) -> dict[str, OpenLibraryBook | None]:
    from .book_canonical_merge import collect_provider_snapshots

    return collect_provider_snapshots(clients, title=title, metadata=metadata)


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
        from .book_catalog_resolver import _resolve_porbase_by_title

        return _resolve_porbase_by_title(
            client,
            BookLookupQuery(title=title, authors=author_text),
            ol_client=ol_client,
        )
    except (PorbaseError, BookResolveError):
        return None


def _extract_from_book(book: OpenLibraryBook, spec: _BookFieldSpec) -> object | None:
    if spec.column == "title":
        return book.title
    if spec.column == "subtitle":
        return book.subtitle
    if spec.column == "description":
        return book.description
    if spec.column == "image_url":
        return book.image_url
    meta = book.metadata if isinstance(book.metadata, dict) else {}
    if spec.metadata_key == "subjects":
        subjects = subjects_list_from_metadata(meta)
        return ", ".join(subjects) if subjects else None
    return meta.get(spec.metadata_key)


def _format_display_value(value: object | None) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return ", ".join(str(part).strip() for part in value if str(part).strip())
    return str(value).strip()


def _metadata_patch_for_field(
    spec: _BookFieldSpec,
    item: MediaItem,
    meta: dict[str, object],
) -> dict[str, object] | None:
    if spec.metadata_key == "authors":
        return {
            "authors": meta.get("authors"),
            "authorEntries": meta.get("authorEntries"),
        }
    if spec.metadata_key == "publisher":
        patch: dict[str, object] = {}
        if meta.get("publisher"):
            patch["publisher"] = meta.get("publisher")
        if meta.get("publisherEntries"):
            patch["publisherEntries"] = meta.get("publisherEntries")
        return patch or None
    if spec.metadata_key == "subjects":
        subjects = subjects_list_from_metadata(meta)
        return {"subjects": subjects} if subjects else None
    return None


def _metadata_patch_for_provider_field(
    spec: _BookFieldSpec,
    book_meta: dict[str, object],
) -> dict[str, object] | None:
    if spec.metadata_key == "authors":
        patch: dict[str, object] = {}
        if book_meta.get("authors"):
            patch["authors"] = book_meta.get("authors")
        if book_meta.get("authorEntries"):
            patch["authorEntries"] = book_meta.get("authorEntries")
        return patch or None
    if spec.metadata_key == "publisher":
        patch = {}
        if book_meta.get("publisher"):
            patch["publisher"] = book_meta.get("publisher")
        if book_meta.get("publisherEntries"):
            patch["publisherEntries"] = book_meta.get("publisherEntries")
        return patch or None
    if spec.metadata_key == "subjects" and book_meta.get("subjects"):
        return {"subjects": book_meta.get("subjects")}
    return None
