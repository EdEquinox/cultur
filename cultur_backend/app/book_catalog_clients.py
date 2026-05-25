"""Shared Open Library + PORBASE + Hardcover clients for book catalog routes."""

from __future__ import annotations

import logging
from dataclasses import dataclass

from .config import Settings
from .hardcover_client import HardcoverClient
from .openlibrary_client import OpenLibraryClient
from .porbase_client import PorbaseClient

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class BookCatalogClients:
    openlibrary: OpenLibraryClient
    porbase: PorbaseClient
    hardcover: HardcoverClient | None


def build_book_catalog_clients(settings: Settings) -> BookCatalogClients:
    from .services.book_catalog_policy import catalog_primary_source, is_hardcover_primary

    timeout = max(30.0, settings.request_timeout_seconds)
    hc_token = (settings.hardcover_api_token or "").strip()
    primary = settings.book_catalog_primary_source or catalog_primary_source()
    if primary:
        logger.info("Book catalog primary source mode: %s", primary)
    if is_hardcover_primary() and not hc_token:
        logger.warning(
            "BOOK_CATALOG_PRIMARY_SOURCE=hardcover requires HARDCOVER_API_TOKEN.",
        )
    return BookCatalogClients(
        openlibrary=OpenLibraryClient(
            timeout_seconds=timeout,
            min_request_interval_seconds=settings.openlibrary_min_request_interval_seconds,
        ),
        porbase=PorbaseClient(
            isbn_url_template=settings.porbase_isbn_url_template,
            timeout_seconds=timeout,
        ),
        hardcover=(
            HardcoverClient(api_token=hc_token, timeout_seconds=timeout)
            if hc_token
            else None
        ),
    )
