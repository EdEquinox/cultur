"""Tracking flags, loans, and collected metadata (DB tables + notes compat)."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from ..backend_models import TrackingCollectedDetail, TrackingEntry, TrackingFlag, TrackingLoan

TRACKING_FLAG_PREFIX = "[cult.flags]"
TRACKING_LENT_PREFIX = "[cult.lent]"
TRACKING_PRICE_PREFIX = "[cult.price]"
TRACKING_MB_RELEASE_PREFIX = "[cult.mb_release]"
TRACKING_DISCOGS_RELEASE_PREFIX = "[cult.discogs_release]"
_LENT_FIELD_SEPARATOR = "\u001f"

_STRUCTURED_PREFIXES = (
    TRACKING_FLAG_PREFIX,
    "[cult.owned]",
    TRACKING_LENT_PREFIX,
    TRACKING_PRICE_PREFIX,
    TRACKING_MB_RELEASE_PREFIX,
    TRACKING_DISCOGS_RELEASE_PREFIX,
)


def flags_from_notes(notes: str | None) -> set[str]:
    text = (notes or "").strip()
    if not text.startswith(TRACKING_FLAG_PREFIX):
        return set()
    first_line = text.split("\n", 1)[0]
    payload = first_line[len(TRACKING_FLAG_PREFIX) :]
    return {segment.strip() for segment in payload.split(",") if segment.strip()}


def load_tracking_flags(db: Session, entry: TrackingEntry) -> set[str]:
    db.refresh(entry, attribute_names=["flags"])
    if entry.flags:
        return {row.flag for row in entry.flags}
    return flags_from_notes(entry.notes)


def replace_tracking_flags(db: Session, entry: TrackingEntry, flags: set[str]) -> None:
    db.execute(delete(TrackingFlag).where(TrackingFlag.tracking_entry_id == entry.id))
    for flag in sorted(flags):
        db.add(TrackingFlag(tracking_entry_id=entry.id, flag=flag))
    entry.notes = compose_notes_with_flags(entry.notes, flags)


def compose_notes_with_flags(notes: str | None, flags: set[str]) -> str | None:
    rest_lines = _non_structured_note_lines(notes)
    prefix = f"{TRACKING_FLAG_PREFIX}{','.join(sorted(flags))}" if flags else None
    lines = [line for line in (prefix, *rest_lines) if line]
    return "\n".join(lines) if lines else None


def sync_tracking_flags_from_notes(db: Session, entry: TrackingEntry) -> None:
    flags = flags_from_notes(entry.notes)
    if flags or entry.flags:
        replace_tracking_flags(db, entry, flags)


def _non_structured_note_lines(notes: str | None) -> list[str]:
    if not notes or not notes.strip():
        return []
    lines: list[str] = []
    for line in notes.split("\n"):
        trimmed = line.strip()
        if not trimmed:
            continue
        if any(trimmed.startswith(prefix) for prefix in _STRUCTURED_PREFIXES):
            continue
        lines.append(line)
    return lines


def _parse_lent_from_notes(notes: str | None) -> tuple[str, datetime] | None:
    value = notes or ""
    for line in value.split("\n"):
        trimmed = line.strip()
        if not trimmed.startswith(TRACKING_LENT_PREFIX):
            continue
        payload = trimmed[len(TRACKING_LENT_PREFIX) :].strip()
        if not payload:
            return None
        sep = payload.find(_LENT_FIELD_SEPARATOR)
        if sep <= 0:
            continue
        name = payload[:sep].strip()
        at_raw = payload[sep + 1 :].strip()
        at = datetime.fromisoformat(at_raw.replace("Z", "+00:00"))
        if at.tzinfo is None:
            at = at.replace(tzinfo=UTC)
        else:
            at = at.astimezone(UTC)
        if name:
            return name, at
    return None


def active_tracking_loan(db: Session, entry: TrackingEntry) -> TrackingLoan | None:
    return db.scalar(
        select(TrackingLoan)
        .where(
            TrackingLoan.tracking_entry_id == entry.id,
            TrackingLoan.returned_at.is_(None),
        )
        .order_by(TrackingLoan.lent_at.desc())
        .limit(1),
    )


def sync_tracking_loan_from_notes(db: Session, entry: TrackingEntry) -> None:
    parsed = _parse_lent_from_notes(entry.notes)
    active = active_tracking_loan(db, entry)
    if parsed is None:
        if active is not None:
            active.returned_at = datetime.now(tz=UTC)
        return
    borrower, lent_at = parsed
    if active is not None:
        active.borrower_name = borrower
        active.lent_at = lent_at
        return
    db.add(
        TrackingLoan(
            tracking_entry_id=entry.id,
            borrower_name=borrower,
            lent_at=lent_at,
        ),
    )


def append_lent_line_to_notes(notes: str | None, *, borrower: str, lent_at: datetime) -> str:
    rest = _non_structured_note_lines(notes)
    line = (
        f"{TRACKING_LENT_PREFIX}{borrower}{_LENT_FIELD_SEPARATOR}"
        f"{lent_at.astimezone(UTC).isoformat().replace('+00:00', 'Z')}"
    )
    lines = [line, *rest]
    return "\n".join(lines)


def sync_tracking_collected_from_notes(db: Session, entry: TrackingEntry) -> None:
    notes = entry.notes or ""
    price: str | None = None
    release_source: str | None = None
    release_id: str | None = None
    for line in notes.split("\n"):
        trimmed = line.strip()
        if trimmed.startswith(TRACKING_PRICE_PREFIX):
            price = trimmed[len(TRACKING_PRICE_PREFIX) :].strip() or None
        elif trimmed.startswith(TRACKING_MB_RELEASE_PREFIX):
            release_source = "musicbrainz"
            release_id = trimmed[len(TRACKING_MB_RELEASE_PREFIX) :].strip() or None
        elif trimmed.startswith(TRACKING_DISCOGS_RELEASE_PREFIX):
            release_source = "discogs"
            release_id = trimmed[len(TRACKING_DISCOGS_RELEASE_PREFIX) :].strip() or None
    if not any((price, release_source, release_id)):
        if entry.collected_detail is not None:
            db.delete(entry.collected_detail)
        return
    detail = entry.collected_detail
    if detail is None:
        detail = TrackingCollectedDetail(tracking_entry_id=entry.id)
        db.add(detail)
    detail.price = price
    detail.owned_release_source = release_source
    detail.owned_release_external_id = release_id


def sync_tracking_structured_fields(db: Session, entry: TrackingEntry) -> None:
    sync_tracking_flags_from_notes(db, entry)
    sync_tracking_loan_from_notes(db, entry)
    sync_tracking_collected_from_notes(db, entry)


def tv_library_watched_requested(*, status: str, notes: str | None, flags: set[str] | None = None) -> bool:
    flag_set = flags if flags is not None else flags_from_notes(notes)
    if "watched" in flag_set:
        return True
    return status.strip().lower() == "completed"
