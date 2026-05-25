"""Import books from parsed Bookmory export rows (client parses `.txt` files)."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, replace
from datetime import UTC, datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..book_catalog_clients import BookCatalogClients
from ..hardcover_client import HardcoverError
from ..openlibrary_client import OpenLibraryError, _normalize_isbn
from ..porbase_client import PorbaseError
from ..schemas import (
    BackendTrackingUpsertRequest,
    BookmoryImportBatchRequest,
    BookmoryImportBatchResponse,
    BookmoryImportEntryPayload,
    BookmoryImportItemError,
)
from . import backend_service
from .book_catalog_resolver import BookLookupQuery, BookResolveError, resolve_single
from .import_pending_service import IMPORT_PENDING_BOOKMORY_SOURCE, upsert_pending_import_item
from .catalog_service import (
    upsert_hardcover_book,
    upsert_openlibrary_book,
    upsert_porbase_book,
)

logger = logging.getLogger(__name__)

_FLAG_PREFIX = "[cult.flags]"
_PRICE_PREFIX = "[cult.price]"
_LENT_PREFIX = "[cult.lent]"
_LENT_SEP = "\u001f"

_MONTHS = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "aug": 8,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}

_UPSERT_BY_SOURCE = {
    "porbase": upsert_porbase_book,
    "hardcover": upsert_hardcover_book,
    "openlibrary": upsert_openlibrary_book,
}


@dataclass(frozen=True, slots=True)
class _TrackingPlan:
    flags: frozenset[str]
    status: str
    score: float | None = None
    progress: int | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    dropped_at: datetime | None = None
    collected_at: datetime | None = None
    price: str | None = None
    lent_borrower: str | None = None
    lent_at: datetime | None = None


def import_bookmory_batch(
    db: Session,
    payload: BookmoryImportBatchRequest,
    *,
    book_clients: BookCatalogClients,
) -> BookmoryImportBatchResponse:
    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="username is required.")

    imported = 0
    pending_count = 0
    skipped = 0
    errors: list[BookmoryImportItemError] = []

    for row in payload.entries:
        source = (row.sourceFile or "").strip() or row.title.strip() or "unknown"
        title = row.title.strip()
        if not title:
            errors.append(
                BookmoryImportItemError(
                    sourceFile=source,
                    title=title or source,
                    reason="missing_title",
                    message="Missing book title.",
                ),
            )
            skipped += 1
            continue
        try:
            lookup = BookLookupQuery(
                title=title,
                authors=row.authors,
                isbn=row.isbn,
            )
            resolved = resolve_single(book_clients, lookup)
        except BookResolveError as exc:
            _create_pending_from_bookmory_row(db, row=row, title=title, username=username, source=source)
            errors.append(
                BookmoryImportItemError(
                    sourceFile=source,
                    title=title,
                    reason=exc.reason,
                    message="Saved as pending — link it from the book page.",
                ),
            )
            pending_count += 1
            continue
        except (OpenLibraryError, HardcoverError, PorbaseError) as exc:
            _create_pending_from_bookmory_row(db, row=row, title=title, username=username, source=source)
            errors.append(
                BookmoryImportItemError(
                    sourceFile=source,
                    title=title,
                    reason=_provider_error_reason(exc),
                    message=str(exc),
                ),
            )
            pending_count += 1
            continue

        book = _apply_row_isbn_to_book(resolved.book, row.isbn)
        upsert_fn = _UPSERT_BY_SOURCE.get(resolved.source, upsert_openlibrary_book)
        media = upsert_fn(db, book)
        plan = _tracking_plan_from_row(row)
        notes = _compose_tracking_notes(plan)
        backend_service.upsert_tracking_entry(
            db,
            BackendTrackingUpsertRequest(
                username=username,
                mediaId=str(media.id),
                status=plan.status,
                progress=plan.progress,
                score=plan.score,
                notes=notes,
                startedAt=_iso(plan.started_at),
                completedAt=_iso(plan.completed_at),
                droppedAt=_iso(plan.dropped_at),
                collectedAt=_iso(plan.collected_at),
            ),
        )
        imported += 1

    db.commit()
    return BookmoryImportBatchResponse(
        imported=imported,
        pending=pending_count,
        skipped=skipped,
        errors=errors,
    )


def _create_pending_from_bookmory_row(
    db: Session,
    *,
    row: BookmoryImportEntryPayload,
    title: str,
    username: str,
    source: str,
) -> None:
    authors = ", ".join(a.strip() for a in row.authors if a.strip())
    dedupe = f"bookmory:{title.casefold()}:{authors.casefold()}:{(row.isbn or '').strip()}"
    media = upsert_pending_import_item(
        db,
        media_type="book",
        source=IMPORT_PENDING_BOOKMORY_SOURCE,
        dedupe_key=dedupe,
        title=title,
        import_source="bookmory",
        import_meta={
            "bookmorySourceFile": source,
            "bookmoryAuthors": authors or None,
            "bookmoryIsbn": (row.isbn or "").strip() or None,
        },
        subtitle=authors or None,
    )
    plan = _tracking_plan_from_row(row)
    notes = _compose_tracking_notes(plan)
    backend_service.upsert_tracking_entry(
        db,
        BackendTrackingUpsertRequest(
            username=username,
            mediaId=str(media.id),
            status=plan.status,
            progress=plan.progress,
            score=plan.score,
            notes=notes,
            startedAt=_iso(plan.started_at),
            completedAt=_iso(plan.completed_at),
            droppedAt=_iso(plan.dropped_at),
            collectedAt=_iso(plan.collected_at),
        ),
    )


def _provider_error_reason(exc: Exception) -> str:
    if isinstance(exc, PorbaseError):
        return "porbase_error"
    if isinstance(exc, HardcoverError):
        return "hardcover_error"
    return "openlibrary_error"


def _apply_row_isbn_to_book(book: object, raw_isbn: str | None):
    from ..openlibrary_client import OpenLibraryBook

    isbn = _normalize_isbn(raw_isbn or "")
    if not isbn:
        return book
    meta = dict(book.metadata)  # type: ignore[attr-defined]
    if not meta.get("isbn"):
        meta["isbn"] = isbn
    meta["bookmoryIsbn"] = isbn
    return replace(book, metadata=meta)  # type: ignore[arg-type]


def _tracking_plan_from_row(row: BookmoryImportEntryPayload) -> _TrackingPlan:
    status_raw = (row.status or "").strip()
    flags: set[str] = set()
    tracking_status = "Planning"
    progress: int | None = None
    score = row.score if row.score and row.score > 0 else None
    started_at = _parse_iso(row.startedAt)
    completed_at = _parse_iso(row.completedAt)
    dropped_at = _parse_iso(row.droppedAt)

    if status_raw == "Reading":
        flags.update({"doing"})
        tracking_status = "In progress"
    elif status_raw == "I've read it all!":
        flags.add("watched")
        tracking_status = "Completed"
        if completed_at is None:
            completed_at = datetime.now(tz=UTC)
    elif status_raw == "Gave up":
        flags.add("dropped")
        tracking_status = "Dropped"
        if dropped_at is None:
            dropped_at = datetime.now(tz=UTC)
    elif row.wishlist or status_raw == "To read":
        flags.add("watchlist")
        tracking_status = "Planning"

    if row.collected:
        flags.add("collected")
    if row.lentBorrower:
        flags.add("collected")

    collected_at = datetime.now(tz=UTC) if row.collected else None

    return _TrackingPlan(
        flags=frozenset(flags),
        status=tracking_status,
        score=score,
        progress=progress,
        started_at=started_at,
        completed_at=completed_at,
        dropped_at=dropped_at,
        collected_at=collected_at,
        price=(row.collectedPrice or "").strip() or None,
        lent_borrower=(row.lentBorrower or "").strip() or None,
        lent_at=_parse_iso(row.lentAt),
    )


def _compose_tracking_notes(plan: _TrackingPlan) -> str | None:
    lines: list[str] = []
    if plan.flags:
        ordered = sorted(plan.flags)
        lines.append(f"{_FLAG_PREFIX}{','.join(ordered)}")
    if plan.price:
        lines.append(f"{_PRICE_PREFIX}{plan.price}")
    if plan.lent_borrower:
        lent_at = plan.lent_at or datetime.now(tz=UTC)
        lines.append(f"{_LENT_PREFIX}{plan.lent_borrower}{_LENT_SEP}{lent_at.isoformat()}")
    if not lines:
        return None
    return "\n".join(lines)


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(UTC).isoformat()


def _parse_iso(raw: str | None) -> datetime | None:
    if not raw or not str(raw).strip():
        return None
    text = str(raw).strip()
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return _parse_bookmory_date(text)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _parse_bookmory_date(raw: str) -> datetime | None:
    t = raw.strip()
    if not t or t == "?":
        return None
    m = re.match(r"^([A-Za-z]{3})\s+(\d{1,2}),\s*(\d{4})$", t)
    if not m:
        return None
    mon = _MONTHS.get(m.group(1).lower())
    if mon is None:
        return None
    try:
        day = int(m.group(2))
        year = int(m.group(3))
    except ValueError:
        return None
    return datetime(year, mon, day, tzinfo=UTC)
