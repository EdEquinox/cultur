"""Book catalog provider priority and search source selection."""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache

HARDCOVER_PRIMARY = "hardcover"

_DEFAULT_MERGE_PRIORITY = {"porbase": 3, "hardcover": 2, "openlibrary": 1}
_HARDCOVER_MERGE_PRIORITY = {"hardcover": 3, "openlibrary": 2, "porbase": 1}


@dataclass(frozen=True, slots=True)
class BookSearchSources:
    """Which providers to query for book search / browse."""

    hardcover: bool = True
    openlibrary: bool = False
    porbase: bool = False

    def uses_fallback_providers(self) -> bool:
        return self.openlibrary or self.porbase

    @staticmethod
    def hardcover_only() -> BookSearchSources:
        return BookSearchSources(hardcover=True, openlibrary=False, porbase=False)

    @staticmethod
    def federated() -> BookSearchSources:
        return BookSearchSources(hardcover=True, openlibrary=True, porbase=True)

    @staticmethod
    def openlibrary_only() -> BookSearchSources:
        return BookSearchSources(hardcover=False, openlibrary=True, porbase=False)

    @staticmethod
    def porbase_only() -> BookSearchSources:
        return BookSearchSources(hardcover=False, openlibrary=False, porbase=True)


@lru_cache(maxsize=1)
def catalog_primary_source() -> str | None:
    raw = os.environ.get("BOOK_CATALOG_PRIMARY_SOURCE", "").strip().lower()
    if raw:
        return raw
    return HARDCOVER_PRIMARY


def is_hardcover_primary() -> bool:
    return catalog_primary_source() == HARDCOVER_PRIMARY


def uses_openlibrary_catalog() -> bool:
    """When False, skip Open Library HTTP for browse, resolve, and detail enrichment."""
    return not is_hardcover_primary()


def merge_source_priority() -> dict[str, int]:
    if is_hardcover_primary():
        return dict(_HARDCOVER_MERGE_PRIORITY)
    return dict(_DEFAULT_MERGE_PRIORITY)


def default_search_sources() -> BookSearchSources:
    """Normal book search: Hardcover only when in Hardcover-primary mode."""
    if is_hardcover_primary():
        return BookSearchSources.hardcover_only()
    return BookSearchSources.federated()


def fallback_search_sources() -> BookSearchSources:
    """Used when Hardcover returns no hits (automatic fallback)."""
    if is_hardcover_primary():
        return BookSearchSources.hardcover_only()
    return BookSearchSources.federated()


def parse_search_sources_param(value: str | None) -> BookSearchSources:
    """Parse API ``sources`` query (explicit user/catalog picker)."""
    token = (value or "").strip().lower()
    if token in {"", "hardcover", "hc"}:
        return BookSearchSources.hardcover_only()
    if token in {"openlibrary", "ol", "open_library"}:
        return BookSearchSources.openlibrary_only()
    if token in {"porbase", "pb"}:
        return BookSearchSources.porbase_only()
    if token in {"all", "federated", "any"}:
        return BookSearchSources.federated()
    return default_search_sources()


def resolve_isbn_provider_order(
    *,
    has_porbase: bool,
    has_hardcover: bool,
) -> tuple[str, ...]:
    """Provider try-order for ISBN lookups (import, Bookmory, detail resolve)."""
    if is_hardcover_primary():
        order: list[str] = []
        if has_hardcover:
            order.append("hardcover")
        if has_porbase:
            order.append("porbase")
        return tuple(order)
    order = []
    if has_porbase:
        order.append("porbase")
    if has_hardcover:
        order.append("hardcover")
    order.append("openlibrary")
    return tuple(order)


def resolve_title_provider_order(
    *,
    has_porbase: bool,
    has_hardcover: bool,
) -> tuple[str, ...]:
    return resolve_isbn_provider_order(
        has_porbase=has_porbase,
        has_hardcover=has_hardcover,
    )
