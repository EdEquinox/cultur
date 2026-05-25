"""Catalog person / series id prefixes for Hardcover vs Open Library."""

from __future__ import annotations

import re

from .openlibrary_client import (
    OPENLIBRARY_PERSON_ID_PREFIX,
    openlibrary_person_id,
    parse_openlibrary_person_id,
)

HARDCOVER_PERSON_ID_PREFIX = "hc-"
HARDCOVER_SERIES_ID_PREFIX = "hc-series-"


def hardcover_person_id(author_id: int | str) -> str:
    token = str(author_id).strip()
    if not token:
        return ""
    return f"{HARDCOVER_PERSON_ID_PREFIX}{token}"


def parse_hardcover_person_id(person_id: str) -> str | None:
    value = person_id.strip()
    if value.startswith(HARDCOVER_PERSON_ID_PREFIX):
        token = value.removeprefix(HARDCOVER_PERSON_ID_PREFIX).strip()
        return token if token.isdigit() else None
    return None


def hardcover_series_key(series_id: int | str) -> str:
    token = str(series_id).strip()
    if not token:
        return ""
    return f"{HARDCOVER_SERIES_ID_PREFIX}{token}"


def parse_hardcover_series_key(raw: str) -> str | None:
    value = raw.strip()
    if value.startswith(HARDCOVER_SERIES_ID_PREFIX):
        token = value.removeprefix(HARDCOVER_SERIES_ID_PREFIX).strip()
        return token if token.isdigit() else None
    if value.isdigit():
        return value
    return None


def author_person_id_from_entry(entry: dict[str, object]) -> str | None:
    """Build a routable person id from a merged authorEntries row."""
    author_id = str(entry.get("id") or "").strip()
    if not author_id:
        return None
    provider = str(entry.get("provider") or entry.get("source") or "").strip().lower()
    if provider == "hardcover" or re.fullmatch(r"\d+", author_id):
        return hardcover_person_id(author_id)
    ol_id = openlibrary_person_id(author_id)
    return ol_id or None


def parse_book_person_id(person_id: str) -> tuple[str, str] | None:
    """Return (provider, external_id) for book author person routes."""
    normalized = person_id.strip()
    hc = parse_hardcover_person_id(normalized)
    if hc is not None:
        return ("hardcover", hc)
    ol = parse_openlibrary_person_id(normalized)
    if ol is not None:
        return ("openlibrary", ol)
    return None
