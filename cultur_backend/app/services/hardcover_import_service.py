"""Import books from Hardcover library shelves and user lists."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..book_catalog_clients import BookCatalogClients
from ..hardcover_client import (
    HardcoverClient,
    HardcoverError,
    HardcoverImportSource,
    HardcoverLibraryBook,
)
from ..openlibrary_client import OpenLibraryBook
from ..schemas import (
    BackendTrackingUpsertRequest,
    BookmoryImportItemError,
    HardcoverCustomListAssignment,
    HardcoverImportBatchRequest,
    HardcoverImportBatchResponse,
    HardcoverImportMappingPayload,
    HardcoverImportPreviewResponse,
    HardcoverImportSourceResponse,
    HardcoverListSummaryResponse,
)
from . import backend_service
from .catalog_service import upsert_hardcover_book
from .import_pending_service import IMPORT_PENDING_PREFIX, upsert_pending_import_item

logger = logging.getLogger(__name__)

IMPORT_PENDING_HARDCOVER_SOURCE = f"{IMPORT_PENDING_PREFIX}-hardcover"

_FLAG_PREFIX = "[cult.flags]"

_CULTUR_TARGETS = frozenset(
    {
        "skip",
        "later",
        "later_priority",
        "buy",
        "read",
        "owned",
        "reading",
        "dropped",
        "priority",
        "custom_list",
    },
)

_STATUS_PRECEDENCE = ("In progress", "Completed", "Dropped", "Planning")


@dataclass(frozen=True, slots=True)
class _TrackingPlan:
    flags: frozenset[str]
    status: str
    score: float | None = None
    collected_at: datetime | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    dropped_at: datetime | None = None


@dataclass
class _AccumulatedHardcoverBook:
    targets: set[str] = field(default_factory=set)
    entry: HardcoverLibraryBook | None = None
    custom_list_sources: list[str] = field(default_factory=list)
    source_labels: list[str] = field(default_factory=list)


def preview_hardcover_import(
    client: HardcoverClient,
    *,
    hardcover_username: str,
) -> HardcoverImportPreviewResponse:
    try:
        user_id, uname, sources = client.fetch_import_sources_by_username(hardcover_username)
    except HardcoverError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    source_rows = [
        HardcoverImportSourceResponse(
            sourceKey=row.source_key,
            kind=row.kind,
            name=row.name,
            booksCount=row.books_count,
            description=row.description,
            public=row.public,
            defaultCulturTarget=default_cultur_target(row),
        )
        for row in sources
    ]
    list_rows = [
        HardcoverListSummaryResponse(
            listId=row.list_id or 0,
            name=row.name,
            booksCount=row.books_count,
            description=row.description,
            public=bool(row.public),
        )
        for row in sources
        if row.kind == "list" and row.list_id is not None
    ]
    return HardcoverImportPreviewResponse(
        hardcoverUserId=user_id,
        hardcoverUsername=uname,
        sources=source_rows,
        lists=list_rows,
    )


def default_cultur_target(source: HardcoverImportSource) -> str:
    if source.kind == "list":
        return "custom_list"
    slug = (source.slug or "").casefold().replace("_", "-")
    name = source.name.casefold()
    if slug in {"reading", "currently-reading"} or "currently" in name or name == "reading":
        return "reading"
    if "want" in name or slug == "want-to-read":
        return "later_priority"
    if name == "read" or name.startswith("read "):
        return "read"
    if "not finish" in name or "dnf" in name:
        return "dropped"
    return "later"


def import_hardcover_batch(
    db: Session,
    payload: HardcoverImportBatchRequest,
    *,
    book_clients: BookCatalogClients,
) -> HardcoverImportBatchResponse:
    username = payload.username.strip()
    if not username:
        raise HTTPException(status_code=400, detail="username is required.")

    client = book_clients.hardcover
    if client is None or not client.enabled:
        raise HTTPException(
            status_code=503,
            detail="Hardcover is not configured. Set HARDCOVER_API_TOKEN on the server.",
        )

    hc_user = payload.hardcoverUsername.strip().lstrip("@")
    if not hc_user:
        raise HTTPException(status_code=400, detail="hardcoverUsername is required.")

    try:
        user_id, _uname, all_sources = client.fetch_import_sources_by_username(hc_user)
    except HardcoverError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    by_key = {row.source_key: row for row in all_sources}
    mappings = _resolve_mappings(payload, all_sources, by_key)
    if not mappings:
        raise HTTPException(status_code=400, detail="No import mappings selected.")

    imported = 0
    pending_count = 0
    skipped = 0
    errors: list[BookmoryImportItemError] = []
    custom_assignments: list[HardcoverCustomListAssignment] = []
    accumulated: dict[int, _AccumulatedHardcoverBook] = {}

    for source_key, target in mappings.items():
        source = by_key.get(source_key)
        if source is None:
            skipped += 1
            continue
        target_norm = _normalize_cultur_target(target)
        if target_norm not in _CULTUR_TARGETS or target_norm == "skip":
            continue

        try:
            entries = _fetch_source_entries(client, user_id=user_id, source=source)
        except HardcoverError as exc:
            errors.append(
                BookmoryImportItemError(
                    sourceFile=source.name,
                    title=source.name,
                    reason="hardcover_source_error",
                    message=str(exc),
                ),
            )
            skipped += 1
            continue

        for entry in entries:
            row = accumulated.setdefault(entry.book_id, _AccumulatedHardcoverBook())
            row.targets.add(target_norm)
            row.source_labels.append(source.name)
            if entry.rating is not None:
                row.entry = entry
            elif row.entry is None:
                row.entry = entry
            if target_norm == "custom_list":
                row.custom_list_sources.append(source.name)

    if not accumulated:
        db.commit()
        return HardcoverImportBatchResponse(
            imported=0,
            pending=pending_count,
            skipped=skipped,
            errors=errors,
            customListAssignments=custom_assignments,
        )

    book_ids = list(accumulated.keys())
    try:
        books = client._fetch_books_by_ids(book_ids)
    except HardcoverError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    books_by_hc_id: dict[int, OpenLibraryBook] = {}
    for book in books:
        meta = book.metadata if isinstance(book.metadata, dict) else {}
        hc_id = meta.get("hardcoverBookId")
        if hc_id is not None:
            try:
                books_by_hc_id[int(hc_id)] = book
            except (TypeError, ValueError):
                pass

    for book_id, acc in accumulated.items():
        book = books_by_hc_id.get(book_id)
        label = ", ".join(dict.fromkeys(acc.source_labels)) or "Hardcover"
        title = book.title if book is not None else f"Hardcover book {book_id}"
        if book is None:
            _create_pending_hardcover_book(
                db,
                username=username,
                title=title,
                list_name=label,
                hardcover_book_id=book_id,
                cultur_targets=acc.targets,
            )
            errors.append(
                BookmoryImportItemError(
                    sourceFile=label,
                    title=title,
                    reason="hardcover_book_missing",
                    message="Saved as pending — link it from the book page.",
                ),
            )
            pending_count += 1
            continue

        media = upsert_hardcover_book(db, book)
        plan = _tracking_plan_for_targets(acc.targets, hc_entry=acc.entry)
        backend_service.upsert_tracking_entry(
            db,
            BackendTrackingUpsertRequest(
                username=username,
                mediaId=str(media.id),
                status=plan.status,
                score=plan.score,
                notes=_compose_tracking_notes(plan),
                startedAt=_iso(plan.started_at),
                completedAt=_iso(plan.completed_at),
                droppedAt=_iso(plan.dropped_at),
                collectedAt=_iso(plan.collected_at),
            ),
        )
        for list_name in dict.fromkeys(acc.custom_list_sources):
            custom_assignments.append(
                HardcoverCustomListAssignment(
                    listName=list_name,
                    mediaId=str(media.id),
                    title=book.title,
                    source=media.source,
                    externalId=media.external_id,
                ),
            )
        imported += 1

    db.commit()
    return HardcoverImportBatchResponse(
        imported=imported,
        pending=pending_count,
        skipped=skipped,
        errors=errors,
        customListAssignments=custom_assignments,
    )


def _resolve_mappings(
    payload: HardcoverImportBatchRequest,
    all_sources: list[HardcoverImportSource],
    by_key: dict[str, HardcoverImportSource],
) -> dict[str, str]:
    if payload.mappings:
        out: dict[str, str] = {}
        for row in payload.mappings:
            key = row.sourceKey.strip()
            target = row.culturTarget.strip().lower()
            if not key or target == "skip":
                continue
            if key in by_key:
                out[key] = target
        return out

    if not payload.listIds:
        return {}
    selected = {int(x) for x in payload.listIds if int(x) > 0}
    return {
        row.source_key: default_cultur_target(row)
        for row in all_sources
        if row.kind == "list" and row.list_id in selected
    }


def _fetch_source_entries(
    client: HardcoverClient,
    *,
    user_id: int,
    source: HardcoverImportSource,
) -> list[HardcoverLibraryBook]:
    if source.kind == "shelf" and source.status_id is not None:
        return client.fetch_library_books_by_status(user_id, source.status_id)
    if source.kind == "list" and source.list_id is not None:
        ids = client.fetch_list_book_ids(source.list_id)
        return [HardcoverLibraryBook(book_id=book_id) for book_id in ids]
    return []


def _normalize_cultur_target(target: str) -> str:
    normalized = (target or "").strip().lower()
    if normalized == "priority":
        return "later_priority"
    return normalized


def _tracking_plan_for_targets(
    targets: set[str],
    *,
    hc_entry: HardcoverLibraryBook | None,
) -> _TrackingPlan:
    flags: set[str] = set()
    status = "Planning"
    score: float | None = None
    collected_at: datetime | None = None
    completed_at: datetime | None = None
    dropped_at: datetime | None = None
    started_at: datetime | None = None

    for target in sorted(targets):
        if target == "skip":
            continue
        plan = _tracking_plan_for_target(target, hc_entry=hc_entry)
        flags |= set(plan.flags)
        if score is None and plan.score is not None:
            score = plan.score
        if plan.collected_at is not None:
            collected_at = plan.collected_at
        if plan.completed_at is not None:
            completed_at = plan.completed_at
        if plan.dropped_at is not None:
            dropped_at = plan.dropped_at
        if plan.started_at is not None:
            started_at = plan.started_at
        if _status_rank(plan.status) < _status_rank(status):
            status = plan.status

    flags = _finalize_tracking_flags(set(flags), status=status)

    return _TrackingPlan(
        flags=frozenset(flags),
        status=status,
        score=score,
        collected_at=collected_at,
        started_at=started_at,
        completed_at=completed_at,
        dropped_at=dropped_at,
    )


def _finalize_tracking_flags(flags: set[str], *, status: str) -> set[str]:
    """Books in Reading must not keep watchlist — it hides them from the Reading shelf."""
    if "dropped" in flags:
        flags.discard("watchlist")
        flags.discard("doing")
        flags.discard("watched")
    elif "watched" in flags:
        flags.discard("watchlist")
        flags.discard("doing")
    elif "doing" in flags and status == "In progress":
        flags.discard("watchlist")
    return flags


def _status_rank(status: str) -> int:
    try:
        return _STATUS_PRECEDENCE.index(status)
    except ValueError:
        return 0


def _tracking_plan_for_target(
    target: str,
    *,
    hc_entry: HardcoverLibraryBook | None,
) -> _TrackingPlan:
    flags: set[str] = set()
    status = "Planning"
    score = hc_entry.rating if hc_entry is not None else None
    collected_at: datetime | None = None
    completed_at: datetime | None = None
    dropped_at: datetime | None = None
    started_at: datetime | None = None

    if target == "later":
        flags.add("watchlist")
    elif target in {"later_priority", "priority"}:
        flags.update({"watchlist", "priority"})
    elif target == "reading":
        flags.update({"doing"})
        flags.discard("watchlist")
        status = "In progress"
    elif target == "read":
        flags.add("watched")
        status = "Completed"
        completed_at = datetime.now(tz=UTC)
    elif target == "dropped":
        flags.add("dropped")
        status = "Dropped"
        dropped_at = datetime.now(tz=UTC)
    elif target == "buy":
        flags.add("buy")
    elif target == "owned":
        flags.add("collected")
        collected_at = datetime.now(tz=UTC)
    elif target == "custom_list":
        flags.add("watchlist")

    if hc_entry is not None and hc_entry.owned and "collected" not in flags:
        flags.add("collected")
        if collected_at is None:
            collected_at = datetime.now(tz=UTC)

    return _TrackingPlan(
        flags=frozenset(flags),
        status=status,
        score=score,
        collected_at=collected_at,
        started_at=started_at,
        completed_at=completed_at,
        dropped_at=dropped_at,
    )


def _compose_tracking_notes(plan: _TrackingPlan) -> str | None:
    if not plan.flags:
        return None
    ordered = sorted(plan.flags)
    return f"{_FLAG_PREFIX}{','.join(ordered)}"


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(UTC).isoformat()


def _create_pending_hardcover_book(
    db: Session,
    *,
    username: str,
    title: str,
    list_name: str,
    hardcover_book_id: int,
    cultur_targets: set[str],
) -> None:
    dedupe = f"hardcover:{hardcover_book_id}"
    media = upsert_pending_import_item(
        db,
        media_type="book",
        source=IMPORT_PENDING_HARDCOVER_SOURCE,
        dedupe_key=dedupe,
        title=title,
        import_source="hardcover",
        import_meta={
            "hardcoverListName": list_name,
            "hardcoverBookId": hardcover_book_id,
            "hardcoverCulturTargets": sorted(cultur_targets),
        },
    )
    plan = _tracking_plan_for_targets(cultur_targets, hc_entry=None)
    backend_service.upsert_tracking_entry(
        db,
        BackendTrackingUpsertRequest(
            username=username,
            mediaId=str(media.id),
            status=plan.status,
            notes=_compose_tracking_notes(plan),
        ),
    )


# Backwards-compatible aliases for router imports.
preview_hardcover_lists = preview_hardcover_import
import_hardcover_lists = import_hardcover_batch
