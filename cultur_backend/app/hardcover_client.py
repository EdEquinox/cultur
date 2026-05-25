"""Hardcover GraphQL API — book editions by ISBN."""

from __future__ import annotations

import json
import logging
import re
import time
from dataclasses import dataclass, replace
from datetime import date, timedelta
from typing import Any
from urllib.parse import quote

import requests

from .catalog_match import build_title_author_query
from .catalog_person_ids import hardcover_series_key
from .openlibrary_client import BOOK_DETAIL_ENRICHED_KEY, OpenLibraryBook, _normalize_isbn, isbn13_to_isbn10

logger = logging.getLogger(__name__)

HARDCOVER_GRAPHQL_URL = "https://api.hardcover.app/v1/graphql"
_USER_AGENT = "Cultur/1.0 (+https://github.com)"
_REQUEST_RETRIES = 3
_RETRYABLE_STATUS = {429, 500, 502, 503, 504}

_EDITION_BY_ISBN13_QUERY = """
query EditionByIsbn13($isbn13: String!) {
  editions(where: { isbn_13: { _eq: $isbn13 } }, limit: 5) {
    id
    title
    subtitle
    isbn_13
    isbn_10
    pages
    release_date
    cached_image
    publisher { name }
    language { language }
    book {
      id
      title
      description
      contributions { author { name } }
    }
  }
}
"""

_EDITION_BY_ISBN10_QUERY = """
query EditionByIsbn10($isbn10: String!) {
  editions(where: { isbn_10: { _eq: $isbn10 } }, limit: 5) {
    id
    title
    subtitle
    isbn_13
    isbn_10
    pages
    release_date
    cached_image
    publisher { name }
    language { language }
    book {
      id
      title
      description
      contributions { author { name } }
    }
  }
}
"""

_SEARCH_BOOKS_QUERY = """
query SearchBooks($query: String!, $per_page: Int!) {
  search(query: $query, query_type: "Book", per_page: $per_page, page: 1) {
    results
    error
  }
}
"""

_SEARCH_QUERY = """
query SearchCatalog($query: String!, $query_type: String!, $per_page: Int!) {
  search(query: $query, query_type: $query_type, per_page: $per_page, page: 1) {
    results
    error
  }
}
"""

_TRENDING_BOOK_IDS_QUERY = """
query TrendingBookIds($from: date!, $to: date!, $limit: Int!, $offset: Int!) {
  books_trending(from: $from, to: $to, limit: $limit, offset: $offset) {
    ids
    error
  }
}
"""

_BOOKS_BY_IDS_QUERY = """
query BooksByIds($ids: [Int!]!) {
  books(where: { id: { _in: $ids } }) {
    id
    title
    slug
    description
    cached_image
    contributions(limit: 8) {
      author { id name slug }
    }
    book_series(limit: 3, order_by: { position: asc }) {
      position
      series { id name slug }
    }
    default_cover_edition {
      isbn_13
      isbn_10
      pages
      release_date
      cached_image
    }
  }
}
"""

_AUTHOR_BY_PK_QUERY = """
query AuthorByPk($id: Int!) {
  authors_by_pk(id: $id) {
    id
    name
    slug
    bio
    born_date
    death_date
    cached_image
    contributions(
      limit: 200,
      where: { contributable_type: { _eq: "Book" } },
      order_by: [{ book: { users_count: desc } }]
    ) {
      contributable_id
      contributable_type
      book {
        id
        title
        slug
        description
        cached_image
        contributions(limit: 4) { author { id name } }
        default_cover_edition { isbn_13 isbn_10 pages release_date cached_image }
        book_series(limit: 1, order_by: { position: asc }) {
          position
          series { id name slug }
        }
      }
    }
  }
}
"""

_SERIES_BY_PK_QUERY = """
query SeriesByPk($id: Int!) {
  series_by_pk(id: $id) {
    id
    name
    description
    slug
    book_series(limit: 200, order_by: { position: asc }) {
      position
      book {
        id
        title
        slug
        cached_image
        contributions(limit: 4) { author { id name } }
        default_cover_edition { isbn_13 pages release_date cached_image }
      }
    }
  }
}
"""

_USER_LISTS_BY_USERNAME_QUERY = """
query UserListsByUsername($username: citext!) {
  users(where: {username: {_eq: $username}}, limit: 1) {
    id
    username
    lists(order_by: {updated_at: desc}, limit: 100) {
      id
      name
      description
      books_count
      public
    }
  }
}
"""

_LIST_BOOK_IDS_QUERY = """
query ListBookIds($list_id: Int!, $limit: Int!, $offset: Int!) {
  list_books(
    where: {list_id: {_eq: $list_id}},
    order_by: {position: asc},
    limit: $limit,
    offset: $offset,
  ) {
    book_id
  }
}
"""

_LIBRARY_SHELVES_QUERY = """
query LibraryShelves($user_id: Int!) {
  user_book_statuses(order_by: {id: asc}) {
    id
    status
    slug
    user_books_aggregate(where: {user_id: {_eq: $user_id}}) {
      aggregate { count }
    }
  }
}
"""

_USER_BOOKS_BY_STATUS_QUERY = """
query UserBooksByStatus($user_id: Int!, $status_id: Int!, $limit: Int!, $offset: Int!) {
  user_books(
    where: {user_id: {_eq: $user_id}, status_id: {_eq: $status_id}},
    order_by: {updated_at: desc},
    limit: $limit,
    offset: $offset,
  ) {
    book_id
    rating
    owned
    first_started_reading_date
    last_read_date
    first_read_date
    user_book_status { status slug }
  }
}
"""


@dataclass(slots=True)
class HardcoverListSummary:
    id: int
    name: str
    books_count: int
    description: str | None
    public: bool


@dataclass(slots=True)
class HardcoverLibraryShelf:
    status_id: int
    name: str
    slug: str
    books_count: int


@dataclass(slots=True)
class HardcoverImportSource:
    source_key: str
    kind: str
    name: str
    books_count: int
    list_id: int | None = None
    status_id: int | None = None
    slug: str | None = None
    description: str | None = None
    public: bool | None = None


@dataclass(slots=True)
class HardcoverLibraryBook:
    book_id: int
    rating: float | None = None
    owned: bool = False


class HardcoverError(RuntimeError):
    pass


@dataclass(slots=True)
class HardcoverClient:
    api_token: str | None
    timeout_seconds: float = 25.0
    min_request_interval_seconds: float = 0.15
    _last_request_at: float = 0.0

    @property
    def enabled(self) -> bool:
        return bool((self.api_token or "").strip())

    def fetch_by_isbn(self, isbn: str) -> OpenLibraryBook | None:
        if not self.enabled:
            return None
        normalized = _normalize_isbn(isbn)
        if not normalized:
            return None
        isbn10: str | None = None
        if len(normalized) == 13:
            isbn10 = isbn13_to_isbn10(normalized)
            payload = self._graphql(_EDITION_BY_ISBN13_QUERY, {"isbn13": normalized})
            editions = self._editions_from_payload(payload)
            book = self._pick_edition_match(editions, normalized, isbn10)
            if book is not None:
                return book
            if isbn10:
                payload = self._graphql(_EDITION_BY_ISBN10_QUERY, {"isbn10": isbn10})
                editions = self._editions_from_payload(payload)
                return self._pick_edition_match(editions, normalized, isbn10)
            return None

        isbn10 = normalized
        payload = self._graphql(_EDITION_BY_ISBN10_QUERY, {"isbn10": isbn10})
        editions = self._editions_from_payload(payload)
        return self._pick_edition_match(editions, normalized, isbn10)

    def _editions_from_payload(self, payload: dict[str, Any]) -> list[dict[str, Any]]:
        editions = payload.get("data", {}).get("editions")
        if not isinstance(editions, list):
            return []
        return [raw for raw in editions if isinstance(raw, dict)]

    def _pick_edition_match(
        self,
        editions: list[dict[str, Any]],
        normalized: str,
        isbn10: str | None,
    ) -> OpenLibraryBook | None:
        if not editions:
            return None
        wanted = {normalized}
        if isbn10:
            wanted.add(isbn10)
        for raw in editions:
            book = _book_from_edition(raw)
            if book is None:
                continue
            info_isbns = _edition_isbns(raw)
            if wanted.intersection(info_isbns):
                meta = dict(book.metadata)
                meta["isbn"] = normalized
                return replace(book, metadata=meta)
        return None

    def search_by_title_author(
        self,
        title: str,
        *,
        authors: str | None = None,
        limit: int = 8,
    ) -> list[OpenLibraryBook]:
        if not self.enabled:
            return []
        query = build_title_author_query(title, authors)
        if not query:
            return []
        payload = self._graphql(
            _SEARCH_BOOKS_QUERY,
            {"query": query, "per_page": max(1, min(limit, 20))},
        )
        search = payload.get("data", {}).get("search")
        if not isinstance(search, dict):
            return []
        error = search.get("error")
        if isinstance(error, str) and error.strip():
            raise HardcoverError(f"Hardcover search error: {error.strip()}")
        return _books_from_search_results(search.get("results"), limit=limit)

    def fetch_trending_books(self, *, limit: int = 24, page: int = 1) -> list[OpenLibraryBook]:
        if not self.enabled:
            return []
        safe_limit = max(1, min(limit, 40))
        offset = max(0, (max(1, page) - 1) * safe_limit)
        today = date.today()
        past = today - timedelta(days=30)
        payload = self._graphql(
            _TRENDING_BOOK_IDS_QUERY,
            {
                "from": past.isoformat(),
                "to": today.isoformat(),
                "limit": safe_limit,
                "offset": offset,
            },
        )
        trending = payload.get("data", {}).get("books_trending")
        ids: list[int] = []
        if isinstance(trending, dict):
            error = trending.get("error")
            if isinstance(error, str) and error.strip():
                logger.warning("Hardcover books_trending error: %s", error.strip())
            raw_ids = trending.get("ids")
            if isinstance(raw_ids, list):
                for raw in raw_ids:
                    if isinstance(raw, int):
                        ids.append(raw)
                    elif isinstance(raw, str) and raw.isdigit():
                        ids.append(int(raw))
        if ids:
            books = self._fetch_books_by_ids(ids[:safe_limit])
            if books:
                return books
        return self.search_by_title_author("bestseller", limit=safe_limit)

    def search_authors(self, name: str, *, limit: int = 8) -> list[dict[str, object]]:
        if not self.enabled:
            return []
        query = (name or "").strip()
        if not query:
            return []
        payload = self._graphql(
            _SEARCH_QUERY,
            {"query": query, "query_type": "Author", "per_page": max(1, min(limit, 20))},
        )
        search = payload.get("data", {}).get("search")
        if not isinstance(search, dict):
            return []
        return _authors_from_search_results(search.get("results"), limit=limit)

    def fetch_author_by_id(self, author_id: str) -> dict[str, object] | None:
        if not self.enabled:
            return None
        token = str(author_id).strip()
        if not token.isdigit():
            return None
        payload = self._graphql(_AUTHOR_BY_PK_QUERY, {"id": int(token)})
        row = payload.get("data", {}).get("authors_by_pk")
        return row if isinstance(row, dict) else None

    def fetch_author_books(self, author_id: str, *, limit: int = 200) -> list[OpenLibraryBook]:
        row = self.fetch_author_by_id(author_id)
        if row is None:
            return []
        contributions = row.get("contributions")
        if not isinstance(contributions, list):
            return []
        books: list[OpenLibraryBook] = []
        seen: set[str] = set()
        for entry in contributions:
            if len(books) >= limit:
                break
            if not isinstance(entry, dict):
                continue
            book_node = entry.get("book")
            if not isinstance(book_node, dict):
                contributable_type = str(entry.get("contributable_type") or "").strip()
                raw_id = entry.get("contributable_id")
                if contributable_type == "Book" and raw_id is not None:
                    try:
                        fetched = self._fetch_books_by_ids([int(raw_id)])
                    except (TypeError, ValueError):
                        fetched = []
                    if fetched:
                        book_node = {
                            "id": int(raw_id),
                            "title": fetched[0].title,
                            "slug": (fetched[0].metadata or {}).get("hardcoverSlug"),
                            "description": fetched[0].description,
                            "cached_image": fetched[0].image_url,
                        }
                if not isinstance(book_node, dict):
                    continue
            book = _book_from_graphql_node(book_node)
            if book is None or book.external_id in seen:
                continue
            seen.add(book.external_id)
            books.append(book)
        return books

    def fetch_series_by_id(self, series_id: str) -> dict[str, object] | None:
        if not self.enabled:
            return None
        token = str(series_id).strip()
        if not token.isdigit():
            return None
        payload = self._graphql(_SERIES_BY_PK_QUERY, {"id": int(token)})
        row = payload.get("data", {}).get("series_by_pk")
        return row if isinstance(row, dict) else None

    def fetch_series_books(self, series_id: str, *, limit: int = 200) -> list[OpenLibraryBook]:
        row = self.fetch_series_by_id(series_id)
        if row is None:
            return []
        memberships = row.get("book_series")
        if not isinstance(memberships, list):
            return []
        series_name = str(row.get("name") or "").strip()
        series_key = str(row.get("id") or series_id).strip()
        books: list[OpenLibraryBook] = []
        for membership in memberships:
            if len(books) >= limit:
                break
            if not isinstance(membership, dict):
                continue
            book_node = membership.get("book")
            if not isinstance(book_node, dict):
                continue
            book = _book_from_graphql_node(book_node)
            if book is None:
                continue
            meta = dict(book.metadata)
            position = membership.get("position")
            if position is not None:
                meta["bookSeriesPosition"] = position
            if series_name:
                meta["bookSeriesName"] = series_name
            if series_key:
                meta["bookSeriesKey"] = hardcover_series_key(series_key)
                meta["hardcoverSeriesId"] = series_key
                meta["hardcoverSeriesUrl"] = (
                    f"https://hardcover.app/series/{row.get('slug') or series_key}"
                )
            books.append(replace(book, metadata=meta))
        return books

    def fetch_import_sources_by_username(
        self,
        username: str,
    ) -> tuple[int, str, list[HardcoverImportSource]]:
        user_id, uname, lists = self.fetch_user_lists_by_username(username)
        shelves = self.fetch_library_shelves(user_id)
        sources: list[HardcoverImportSource] = []
        for shelf in shelves:
            if shelf.books_count <= 0:
                continue
            sources.append(
                HardcoverImportSource(
                    source_key=f"shelf:{shelf.status_id}",
                    kind="shelf",
                    name=shelf.name,
                    books_count=shelf.books_count,
                    status_id=shelf.status_id,
                    slug=shelf.slug or None,
                ),
            )
        for row in lists:
            sources.append(
                HardcoverImportSource(
                    source_key=f"list:{row.id}",
                    kind="list",
                    name=row.name,
                    books_count=row.books_count,
                    list_id=row.id,
                    description=row.description,
                    public=row.public,
                ),
            )
        return user_id, uname, sources

    def fetch_user_lists_by_username(
        self,
        username: str,
    ) -> tuple[int, str, list[HardcoverListSummary]]:
        if not self.enabled:
            raise HardcoverError("Hardcover is not configured (HARDCOVER_API_TOKEN).")
        handle = (username or "").strip().lstrip("@")
        if not handle:
            raise HardcoverError("Hardcover username is required.")
        payload = self._graphql(_USER_LISTS_BY_USERNAME_QUERY, {"username": handle})
        users = payload.get("data", {}).get("users")
        if not isinstance(users, list) or not users:
            raise HardcoverError(f"Hardcover user not found: {handle}")
        user = users[0]
        if not isinstance(user, dict):
            raise HardcoverError(f"Hardcover user not found: {handle}")
        user_id = user.get("id")
        if user_id is None:
            raise HardcoverError(f"Hardcover user not found: {handle}")
        uname = str(user.get("username") or handle).strip()
        raw_lists = user.get("lists")
        summaries: list[HardcoverListSummary] = []
        if isinstance(raw_lists, list):
            for row in raw_lists:
                if not isinstance(row, dict):
                    continue
                list_id = row.get("id")
                if list_id is None:
                    continue
                summaries.append(
                    HardcoverListSummary(
                        id=int(list_id),
                        name=str(row.get("name") or "Untitled list").strip(),
                        books_count=int(row.get("books_count") or 0),
                        description=(
                            str(row.get("description")).strip()
                            if row.get("description")
                            else None
                        ),
                        public=bool(row.get("public")),
                    ),
                )
        return int(user_id), uname, summaries

    def fetch_library_shelves(self, user_id: int) -> list[HardcoverLibraryShelf]:
        if not self.enabled:
            return []
        payload = self._graphql(_LIBRARY_SHELVES_QUERY, {"user_id": int(user_id)})
        rows = payload.get("data", {}).get("user_book_statuses")
        shelves: list[HardcoverLibraryShelf] = []
        if not isinstance(rows, list):
            return shelves
        for row in rows:
            if not isinstance(row, dict):
                continue
            status_id = row.get("id")
            if status_id is None:
                continue
            aggregate = row.get("user_books_aggregate")
            count = 0
            if isinstance(aggregate, dict):
                inner = aggregate.get("aggregate")
                if isinstance(inner, dict):
                    raw_count = inner.get("count")
                    if isinstance(raw_count, int):
                        count = raw_count
            name = str(row.get("status") or row.get("slug") or "Shelf").strip()
            slug = str(row.get("slug") or "").strip()
            shelves.append(
                HardcoverLibraryShelf(
                    status_id=int(status_id),
                    name=name,
                    slug=slug,
                    books_count=count,
                ),
            )
        return shelves

    def fetch_library_books_by_status(
        self,
        user_id: int,
        status_id: int,
        *,
        limit: int = 5000,
    ) -> list[HardcoverLibraryBook]:
        if not self.enabled:
            return []
        safe_limit = max(1, min(limit, 5000))
        collected: list[HardcoverLibraryBook] = []
        offset = 0
        while len(collected) < safe_limit:
            page_size = min(100, safe_limit - len(collected))
            payload = self._graphql(
                _USER_BOOKS_BY_STATUS_QUERY,
                {
                    "user_id": int(user_id),
                    "status_id": int(status_id),
                    "limit": page_size,
                    "offset": offset,
                },
            )
            rows = payload.get("data", {}).get("user_books")
            if not isinstance(rows, list) or not rows:
                break
            for row in rows:
                if not isinstance(row, dict):
                    continue
                book_id = row.get("book_id")
                if book_id is None:
                    continue
                rating_raw = row.get("rating")
                rating: float | None = None
                if isinstance(rating_raw, (int, float)) and float(rating_raw) > 0:
                    rating = float(rating_raw)
                collected.append(
                    HardcoverLibraryBook(
                        book_id=int(book_id),
                        rating=rating,
                        owned=bool(row.get("owned")),
                    ),
                )
            if len(rows) < page_size:
                break
            offset += page_size
        return collected

    def fetch_list_book_ids(self, list_id: int, *, limit: int = 500) -> list[int]:
        if not self.enabled:
            return []
        safe_limit = max(1, min(limit, 500))
        collected: list[int] = []
        offset = 0
        while len(collected) < limit:
            page_size = min(100, limit - len(collected))
            payload = self._graphql(
                _LIST_BOOK_IDS_QUERY,
                {"list_id": int(list_id), "limit": page_size, "offset": offset},
            )
            rows = payload.get("data", {}).get("list_books")
            if not isinstance(rows, list) or not rows:
                break
            for row in rows:
                if not isinstance(row, dict):
                    continue
                book_id = row.get("book_id")
                if book_id is None:
                    continue
                collected.append(int(book_id))
            if len(rows) < page_size:
                break
            offset += page_size
        return collected

    def _fetch_books_by_ids(self, book_ids: list[int]) -> list[OpenLibraryBook]:
        if not book_ids:
            return []
        payload = self._graphql(_BOOKS_BY_IDS_QUERY, {"ids": book_ids})
        nodes = payload.get("data", {}).get("books")
        if not isinstance(nodes, list):
            return []
        by_id: dict[int, OpenLibraryBook] = {}
        for node in nodes:
            if not isinstance(node, dict):
                continue
            book = _book_from_graphql_node(node)
            if book is None:
                continue
            raw_id = node.get("id")
            if isinstance(raw_id, int):
                by_id[raw_id] = book
        ordered: list[OpenLibraryBook] = []
        for book_id in book_ids:
            book = by_id.get(book_id)
            if book is not None:
                ordered.append(book)
        return ordered

    def _graphql(self, query: str, variables: dict[str, Any]) -> dict[str, Any]:
        if self.min_request_interval_seconds > 0:
            now = time.monotonic()
            elapsed = now - self._last_request_at
            if elapsed < self.min_request_interval_seconds:
                time.sleep(self.min_request_interval_seconds - elapsed)
            self._last_request_at = time.monotonic()

        headers = {
            "User-Agent": _USER_AGENT,
            "Content-Type": "application/json",
            "authorization": _authorization_header(self.api_token),
        }
        body = {"query": query, "variables": variables}
        last_response: requests.Response | None = None
        for attempt in range(_REQUEST_RETRIES):
            try:
                response = requests.post(
                    HARDCOVER_GRAPHQL_URL,
                    headers=headers,
                    json=body,
                    timeout=self.timeout_seconds,
                )
            except requests.RequestException as exc:
                if attempt + 1 >= _REQUEST_RETRIES:
                    raise HardcoverError(f"Hardcover request failed: {exc}") from exc
                time.sleep(1.0 * (attempt + 1))
                continue
            last_response = response
            if response.status_code in _RETRYABLE_STATUS and attempt + 1 < _REQUEST_RETRIES:
                time.sleep(1.5 * (attempt + 1))
                continue
            if response.status_code == 401:
                raise HardcoverError(
                    "Hardcover token invalid or expired. Set HARDCOVER_API_TOKEN from "
                    "https://hardcover.app/account/api",
                )
            if response.status_code == 429:
                raise HardcoverError("Hardcover rate limit (429). Try again later.")
            if response.status_code >= 400:
                raise HardcoverError(
                    f"Hardcover request failed ({response.status_code}): "
                    f"{(response.text or '')[:200]}",
                )
            try:
                data = response.json()
            except ValueError as exc:
                raise HardcoverError("Hardcover returned invalid JSON.") from exc
            if not isinstance(data, dict):
                raise HardcoverError("Hardcover returned unexpected JSON.")
            if data.get("errors"):
                msg = json.dumps(data["errors"])[:300]
                raise HardcoverError(f"Hardcover GraphQL error: {msg}")
            return data
        assert last_response is not None
        raise HardcoverError(f"Hardcover request failed ({last_response.status_code})")


def _authorization_header(api_token: str | None) -> str:
    token = (api_token or "").strip()
    if not token:
        return ""
    if token.casefold().startswith("bearer "):
        return token
    return f"Bearer {token}"


def _books_from_search_results(raw: object, *, limit: int) -> list[OpenLibraryBook]:
    if not isinstance(raw, dict):
        return []
    hits = raw.get("hits")
    if not isinstance(hits, list):
        return []
    books: list[OpenLibraryBook] = []
    seen_ids: set[str] = set()
    for hit in hits:
        if len(books) >= limit:
            break
        if not isinstance(hit, dict):
            continue
        document = hit.get("document")
        if not isinstance(document, dict):
            continue
        book = _book_from_search_document(document)
        if book is None or book.external_id in seen_ids:
            continue
        seen_ids.add(book.external_id)
        books.append(book)
    return books


def _book_from_search_document(document: dict[str, Any]) -> OpenLibraryBook | None:
    book_id = document.get("id")
    if book_id is None:
        return None
    title = str(document.get("title") or "").strip()
    if not title:
        return None

    authors: list[str] = []
    author_names = document.get("author_names")
    if isinstance(author_names, list):
        for raw in author_names:
            name = str(raw).strip()
            if name and name not in authors:
                authors.append(name)
    contributions = document.get("contributions")
    if isinstance(contributions, list):
        for row in contributions:
            if not isinstance(row, dict):
                continue
            author = row.get("author")
            if isinstance(author, dict):
                name = str(author.get("name") or "").strip()
                if name and name not in authors:
                    authors.append(name)
    author_entries = _author_entries_from_contributions(contributions, author_names=authors)

    isbn: str | None = None
    isbns_raw = document.get("isbns")
    if isinstance(isbns_raw, list):
        for raw in isbns_raw:
            normalized = _normalize_isbn(str(raw))
            if normalized:
                isbn = normalized
                break

    year: int | None = None
    release_year = document.get("release_year")
    if isinstance(release_year, int) and release_year > 0:
        year = release_year
    elif isinstance(release_year, str) and release_year.isdigit():
        year = int(release_year)

    pages = document.get("pages")
    page_count = pages if isinstance(pages, int) and pages > 0 else None

    description_raw = document.get("description")
    description = str(description_raw).strip() if description_raw else None

    slug = str(document.get("slug") or "").strip() or None
    volume_id = str(book_id)
    meta: dict[str, object] = {
        "importSource": "hardcover",
        "hardcoverBookId": book_id,
        BOOK_DETAIL_ENRICHED_KEY: True,
        "hardcoverUrl": f"https://hardcover.app/books/{slug or volume_id}",
    }
    if slug:
        meta["hardcoverSlug"] = slug
    if authors:
        meta["authors"] = ", ".join(authors)
    if author_entries:
        meta["authorEntries"] = author_entries
    if isbn:
        meta["isbn"] = isbn
    if page_count is not None:
        meta["pageCount"] = page_count
    if year is not None:
        meta["firstPublishYear"] = year

    image_url = _image_from_cached(document.get("image"))

    return OpenLibraryBook(
        external_id=volume_id,
        title=title,
        subtitle=str(document.get("subtitle") or "").strip() or None,
        description=description,
        image_url=image_url,
        metadata=meta,
    )


def hardcover_book_from_media_item(item: object) -> OpenLibraryBook:
    meta = getattr(item, "provider_payload", None)
    payload = dict(meta) if isinstance(meta, dict) else {}
    return OpenLibraryBook(
        external_id=str(getattr(item, "external_id", "") or ""),
        title=str(getattr(item, "title", "") or ""),
        subtitle=getattr(item, "subtitle", None),
        description=getattr(item, "description", None),
        image_url=getattr(item, "image_url", None),
        metadata=payload,
    )


def _edition_isbns(edition: dict[str, Any]) -> set[str]:
    out: set[str] = set()
    for key in ("isbn_13", "isbn_10"):
        raw = edition.get(key)
        if isinstance(raw, str):
            n = _normalize_isbn(raw)
            if n:
                out.add(n)
    return out


def _book_from_edition(edition: dict[str, Any]) -> OpenLibraryBook | None:
    edition_id = edition.get("id")
    if edition_id is None:
        return None
    book_node = edition.get("book") if isinstance(edition.get("book"), dict) else {}
    title = str(edition.get("title") or book_node.get("title") or "").strip()
    if not title:
        return None
    subtitle = str(edition.get("subtitle") or "").strip() or None
    description_raw = book_node.get("description")
    description = str(description_raw).strip() if description_raw else None

    authors: list[str] = []
    contributions = book_node.get("contributions")
    if isinstance(contributions, list):
        for row in contributions:
            if not isinstance(row, dict):
                continue
            author = row.get("author")
            if isinstance(author, dict):
                name = str(author.get("name") or "").strip()
                if name:
                    authors.append(name)
    author_entries = _author_entries_from_contributions(contributions, author_names=authors)

    publisher_name: str | None = None
    publisher = edition.get("publisher")
    if isinstance(publisher, dict):
        publisher_name = str(publisher.get("name") or "").strip() or None

    language_label: str | None = None
    language = edition.get("language")
    if isinstance(language, dict):
        language_label = str(language.get("language") or "").strip() or None

    pages = edition.get("pages")
    page_count = pages if isinstance(pages, int) and pages > 0 else None
    release_date = str(edition.get("release_date") or "").strip()
    year: int | None = None
    if release_date and len(release_date) >= 4 and release_date[:4].isdigit():
        year = int(release_date[:4])

    volume_id = str(edition_id)
    book_id = book_node.get("id")
    meta: dict[str, object] = {
        "importSource": "hardcover",
        "hardcoverEditionId": int(edition_id) if str(edition_id).isdigit() else edition_id,
        BOOK_DETAIL_ENRICHED_KEY: True,
        "hardcoverUrl": f"https://hardcover.app/books/{book_id or volume_id}",
    }
    if book_id is not None:
        meta["hardcoverBookId"] = book_id
    if authors:
        meta["authors"] = ", ".join(authors)
    if author_entries:
        meta["authorEntries"] = author_entries
    if publisher_name:
        meta["publisher"] = publisher_name
    if page_count is not None:
        meta["pageCount"] = page_count
    if year is not None:
        meta["firstPublishYear"] = year
    if language_label:
        meta["bookLanguage"] = language_label

    isbn13 = edition.get("isbn_13")
    if isinstance(isbn13, str) and isbn13.strip():
        n = _normalize_isbn(isbn13)
        if n:
            meta["isbn"] = n

    image_url = _image_from_cached(edition.get("cached_image"))

    return OpenLibraryBook(
        external_id=volume_id,
        title=title,
        subtitle=subtitle,
        description=description,
        image_url=image_url,
        metadata=meta,
    )


def _author_entries_from_contributions(
    contributions: object,
    *,
    author_names: list[str] | None = None,
) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    seen_keys: set[str] = set()
    if isinstance(contributions, list):
        for row in contributions:
            if not isinstance(row, dict):
                continue
            author = row.get("author")
            if not isinstance(author, dict):
                continue
            author_id = str(author.get("id") or "").strip()
            name = str(author.get("name") or "").strip()
            if not name:
                continue
            dedupe_key = author_id or name.casefold()
            if dedupe_key in seen_keys:
                continue
            seen_keys.add(dedupe_key)
            entry: dict[str, object] = {"name": name, "provider": "hardcover"}
            if author_id:
                entry["id"] = author_id
            slug = author.get("slug")
            if isinstance(slug, str) and slug.strip():
                entry["slug"] = slug.strip()
            entries.append(entry)
    existing_names = {
        str(entry.get("name") or "").strip().casefold()
        for entry in entries
        if entry.get("name")
    }
    for name in author_names or []:
        clean = name.strip()
        if not clean or clean.casefold() in existing_names:
            continue
        entries.append({"name": clean, "provider": "hardcover"})
        existing_names.add(clean.casefold())
    return entries[:8]


def _book_from_graphql_node(node: dict[str, Any]) -> OpenLibraryBook | None:
    book_id = node.get("id")
    if book_id is None:
        return None
    title = str(node.get("title") or "").strip()
    if not title:
        return None

    authors: list[str] = []
    contributions = node.get("contributions")
    if isinstance(contributions, list):
        for row in contributions:
            if not isinstance(row, dict):
                continue
            author = row.get("author")
            if isinstance(author, dict):
                name = str(author.get("name") or "").strip()
                if name and name not in authors:
                    authors.append(name)
    author_entries = _author_entries_from_contributions(contributions, author_names=authors)

    edition = node.get("default_cover_edition")
    edition_dict = edition if isinstance(edition, dict) else {}

    isbn: str | None = None
    for key in ("isbn_13", "isbn_10"):
        raw = edition_dict.get(key)
        if isinstance(raw, str):
            normalized = _normalize_isbn(raw)
            if normalized:
                isbn = normalized
                break

    year: int | None = None
    release_date = str(edition_dict.get("release_date") or "").strip()
    if release_date and len(release_date) >= 4 and release_date[:4].isdigit():
        year = int(release_date[:4])

    pages = edition_dict.get("pages")
    page_count = pages if isinstance(pages, int) and pages > 0 else None

    description_raw = node.get("description")
    description = str(description_raw).strip() if description_raw else None

    slug = str(node.get("slug") or "").strip() or None
    volume_id = str(book_id)
    meta: dict[str, object] = {
        "importSource": "hardcover",
        "hardcoverBookId": book_id,
        BOOK_DETAIL_ENRICHED_KEY: True,
        "hardcoverUrl": f"https://hardcover.app/books/{slug or volume_id}",
    }
    if slug:
        meta["hardcoverSlug"] = slug
    if authors:
        meta["authors"] = ", ".join(authors)
    if author_entries:
        meta["authorEntries"] = author_entries
    if isbn:
        meta["isbn"] = isbn
    if page_count is not None:
        meta["pageCount"] = page_count
    if year is not None:
        meta["firstPublishYear"] = year

    series_memberships = node.get("book_series")
    if isinstance(series_memberships, list) and series_memberships:
        first = series_memberships[0]
        if isinstance(first, dict):
            position = first.get("position")
            if position is not None:
                meta["bookSeriesPosition"] = position
            series = first.get("series")
            if isinstance(series, dict):
                series_name = str(series.get("name") or "").strip()
                series_id = series.get("id")
                if series_name:
                    meta["bookSeriesName"] = series_name
                if series_id is not None:
                    series_token = str(series_id).strip()
                    meta["hardcoverSeriesId"] = series_token
                    meta["bookSeriesKey"] = hardcover_series_key(series_token)
                    series_slug = str(series.get("slug") or "").strip()
                    meta["hardcoverSeriesUrl"] = (
                        f"https://hardcover.app/series/{series_slug or series_token}"
                    )

    image_url = _image_from_cached(node.get("cached_image"))
    if image_url is None:
        image_url = _image_from_cached(edition_dict.get("cached_image"))

    return OpenLibraryBook(
        external_id=volume_id,
        title=title,
        subtitle=None,
        description=description,
        image_url=image_url,
        metadata=meta,
    )


def _authors_from_search_results(raw: object, *, limit: int) -> list[dict[str, object]]:
    if not isinstance(raw, dict):
        return []
    hits = raw.get("hits")
    if not isinstance(hits, list):
        return []
    authors: list[dict[str, object]] = []
    seen: set[str] = set()
    for hit in hits:
        if len(authors) >= limit:
            break
        if not isinstance(hit, dict):
            continue
        document = hit.get("document")
        if not isinstance(document, dict):
            continue
        author_id = document.get("id")
        name = str(document.get("name") or "").strip()
        if not name:
            continue
        token = str(author_id) if author_id is not None else name
        if token in seen:
            continue
        seen.add(token)
        row: dict[str, object] = {"name": name, "provider": "hardcover"}
        if author_id is not None:
            row["id"] = author_id
        slug = document.get("slug")
        if isinstance(slug, str) and slug.strip():
            row["slug"] = slug.strip()
        authors.append(row)
    return authors


def _image_from_cached(raw: object) -> str | None:
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            if raw.startswith("http"):
                return raw.replace("http://", "https://")
            return None
    if isinstance(raw, dict):
        for key in ("url", "image_url", "large", "medium", "small"):
            val = raw.get(key)
            if isinstance(val, str) and val.startswith("http"):
                return val.replace("http://", "https://")
    return None
