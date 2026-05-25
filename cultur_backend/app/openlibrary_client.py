from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.parse import quote, unquote

import requests

OPENLIBRARY_API_BASE = "https://openlibrary.org"
_COVERS_BASE = "https://covers.openlibrary.org"
_ARCHIVE_DOWNLOAD = "https://archive.org/download"
_COVER_ITEM_SIZE = 1_000_000
_COVER_BATCH_SIZE = 10_000
_REQUEST_RETRIES = 3
_RETRYABLE_STATUS = {429, 500, 502, 503, 504}
_USER_AGENT = "Cultur/1.0 (+https://github.com)"
BOOK_DETAIL_ENRICHED_KEY = "detailEnriched"
BOOK_DETAIL_CACHE_TTL = timedelta(days=7)


class OpenLibraryError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class OpenLibraryBook:
    external_id: str
    title: str
    subtitle: str | None
    description: str | None
    image_url: str | None
    metadata: dict[str, object] = field(default_factory=dict)


def openlibrary_book_from_media_item(item: object) -> OpenLibraryBook:
    """Rebuild [OpenLibraryBook] from a persisted [MediaItem] row (no HTTP)."""
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


def _book_detail_metadata_is_usable(metadata: dict[str, object]) -> bool:
    has_catalog_identity = bool(
        metadata.get("openLibraryWorkId")
        or metadata.get("openLibraryUrl")
        or metadata.get("porbaseUrl")
        or metadata.get("hardcoverUrl")
        or metadata.get("hardcoverBookId")
        or metadata.get("googleBooksUrl")
        or metadata.get("importSource") in {"porbase", "hardcover", "googlebooks"}
    )
    if not has_catalog_identity:
        return False
    if not (metadata.get("authors") or metadata.get("authorEntries")):
        return False
    if metadata.get(BOOK_DETAIL_ENRICHED_KEY):
        return True
    return bool(
        metadata.get("isbn")
        or metadata.get("bookLanguage")
        or metadata.get("publisherEntries")
    )


def book_detail_response_can_use_cache(
    *,
    updated_at: datetime,
    metadata: dict[str, object],
    ttl: timedelta = BOOK_DETAIL_CACHE_TTL,
) -> bool:
    """True when DB metadata is rich enough and was refreshed within [ttl]."""
    if not _book_detail_metadata_is_usable(metadata):
        return False
    stamp = updated_at if updated_at.tzinfo is not None else updated_at.replace(tzinfo=UTC)
    return datetime.now(tz=UTC) - stamp < ttl


def book_detail_can_use_stored_fallback(metadata: dict[str, object]) -> bool:
    """True when a failed live refresh may still return the stored catalog row."""
    return _book_detail_metadata_is_usable(metadata)


@dataclass(frozen=True, slots=True)
class OpenLibraryAuthor:
    author_id: str
    name: str
    biography: str | None
    birth_date: str | None
    death_date: str | None
    image_url: str | None


@dataclass(frozen=True, slots=True)
class OpenLibraryPublisher:
    publisher_id: str
    name: str
    work_count: int | None = None


class OpenLibraryClient:
    """Open Library Search + Works API (no API key required)."""

    def __init__(
        self,
        *,
        base_url: str = OPENLIBRARY_API_BASE,
        timeout_seconds: float = 25.0,
        min_request_interval_seconds: float = 0.25,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.min_request_interval_seconds = max(0.0, min_request_interval_seconds)
        self._last_request_at = 0.0

    def fetch_popular_books(self, *, limit: int = 48, page: int = 1) -> list[OpenLibraryBook]:
        payload = self._get_json(
            "/search.json",
            {
                "q": "fiction",
                "sort": "rating",
                "limit": str(max(1, min(limit, 100))),
                "page": str(max(1, page)),
                "fields": _SEARCH_FIELDS,
            },
        )
        return self._books_from_search_payload(payload, limit=limit)

    def search_books(
        self,
        query: str = "",
        *,
        limit: int = 24,
        page: int = 1,
        publisher: str | None = None,
        isbn: str | None = None,
        language: str | None = None,
        year: str | None = None,
        genre: str | None = None,
    ) -> list[OpenLibraryBook]:
        built_query = _build_book_search_query(
            text=query,
            publisher=publisher,
            isbn=isbn,
            language=language,
            year=year,
            genre=genre,
        )
        if not built_query:
            return []
        payload = self._get_json(
            "/search.json",
            {
                "q": built_query,
                "limit": str(max(1, min(limit, 100))),
                "page": str(max(1, page)),
                "fields": _SEARCH_FIELDS,
            },
        )
        return self._books_from_search_payload(payload, limit=limit)

    def fetch_author_by_id(self, author_id: str) -> OpenLibraryAuthor | None:
        normalized = _normalize_author_id(author_id)
        if not normalized:
            return None
        payload = self._get_json(f"/authors/{normalized}.json", {})
        name = str(payload.get("name") or "").strip()
        if not name:
            return None
        return OpenLibraryAuthor(
            author_id=normalized,
            name=name,
            biography=_description_text(payload.get("bio")),
            birth_date=_author_date_label(payload.get("birth_date")),
            death_date=_author_date_label(payload.get("death_date")),
            image_url=_author_image_url(normalized, payload.get("photos")),
        )

    def fetch_publisher_by_id(self, publisher_id: str) -> OpenLibraryPublisher | None:
        name = parse_openlibrary_publisher_id(publisher_id)
        if not name:
            return None
        path = f"/publishers/{quote(name, safe='')}.json"
        payload = self._get_json(path, {})
        resolved_name = str(payload.get("name") or name).strip()
        if not resolved_name:
            return None
        work_count_raw = payload.get("work_count")
        work_count = work_count_raw if isinstance(work_count_raw, int) and work_count_raw > 0 else None
        return OpenLibraryPublisher(
            publisher_id=openlibrary_publisher_id(resolved_name),
            name=resolved_name,
            work_count=work_count,
        )

    def fetch_series_books(
        self,
        series_id: str,
        *,
        series_name: str | None = None,
        limit: int = 100,
        page: int = 1,
    ) -> list[OpenLibraryBook]:
        normalized_id = series_id.strip()
        name = (series_name or "").strip()
        if normalized_id:
            query = f"series_key:{normalized_id}"
        elif name:
            query = f'series:"{_escape_solr_phrase(name)}"'
        else:
            return []
        payload = self._get_json(
            "/search.json",
            {
                "q": query,
                "limit": str(max(1, min(limit, 100))),
                "page": str(max(1, page)),
                "fields": _SEARCH_FIELDS,
            },
        )
        return self._books_from_search_payload(payload, limit=limit)

    def fetch_publisher_books(
        self,
        publisher_id: str,
        *,
        limit: int = 100,
        page: int = 1,
    ) -> list[OpenLibraryBook]:
        name = parse_openlibrary_publisher_id(publisher_id)
        if not name:
            return []
        payload = self._get_json(
            "/search.json",
            {
                "q": f'publisher_facet:"{name}"',
                "limit": str(max(1, min(limit, 100))),
                "page": str(max(1, page)),
                "fields": _SEARCH_FIELDS,
            },
        )
        return self._books_from_search_payload(payload, limit=limit)

    def fetch_author_works(
        self,
        author_id: str,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[OpenLibraryBook]:
        normalized = _normalize_author_id(author_id)
        if not normalized:
            return []
        payload = self._get_json(
            f"/authors/{normalized}/works.json",
            {
                "limit": str(max(1, min(limit, 1000))),
                "offset": str(max(0, offset)),
            },
        )
        entries = payload.get("entries")
        if not isinstance(entries, list):
            return []
        books: list[OpenLibraryBook] = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            try:
                books.append(_book_from_author_work_entry(entry))
            except OpenLibraryError:
                continue
            if len(books) >= limit:
                break
        return books

    def fetch_author_books_search(
        self,
        *,
        author_id: str | None = None,
        author_name: str,
        limit: int = 100,
    ) -> list[OpenLibraryBook]:
        """Fallback when /authors/{{id}}/works.json is empty."""
        normalized = _normalize_author_id((author_id or "").strip())
        name = (author_name or "").strip()
        if normalized:
            query = f'author_key:"/authors/{normalized}"'
        elif name:
            query = f'author_name:"{_escape_solr_phrase(name)}"'
        else:
            return []
        payload = self._get_json(
            "/search.json",
            {
                "q": query,
                "limit": str(max(1, min(limit, 100))),
                "fields": _SEARCH_FIELDS,
            },
        )
        return self._books_from_search_payload(payload, limit=limit)

    def fetch_book_by_work_id(self, work_id: str) -> OpenLibraryBook | None:
        normalized = _normalize_work_id(work_id)
        if not normalized:
            return None
        payload = self._get_json(f"/works/{normalized}.json", {})
        try:
            book = _book_from_work_payload(normalized, payload)
        except OpenLibraryError:
            return None
        search_doc = _search_doc_for_work(self, normalized)
        return _enrich_book_from_sources(self, book, payload, search_doc)

    def fetch_book_by_isbn(self, isbn: str) -> OpenLibraryBook | None:
        """Resolve an edition by ISBN via ``/isbn/{{isbn}}.json`` (often works when search misses)."""
        normalized = _normalize_isbn(isbn)
        if not normalized:
            return None
        try:
            edition = self._get_json(f"/isbn/{normalized}.json", {})
        except OpenLibraryError:
            return None
        works = edition.get("works")
        work_key: str | None = None
        if isinstance(works, list) and works:
            first = works[0]
            if isinstance(first, dict):
                work_key = str(first.get("key") or "").strip()
            elif isinstance(first, str):
                work_key = first.strip()
        if not work_key:
            work_key = str(edition.get("works") or "").strip()
        work_id = _normalize_work_id(work_key) if work_key else ""
        if work_id:
            book = self.fetch_book_by_work_id(work_id)
            if book is not None:
                meta = dict(book.metadata)
                meta["isbn"] = normalized
                return replace(book, metadata=meta)
        title = str(edition.get("title") or "").strip()
        if not title:
            return None
        authors_raw = edition.get("authors")
        authors = ""
        if isinstance(authors_raw, list) and authors_raw:
            names: list[str] = []
            for entry in authors_raw[:4]:
                if isinstance(entry, dict):
                    name = str(entry.get("name") or "").strip()
                    if name:
                        names.append(name)
            authors = ", ".join(names)
        meta: dict[str, object] = {"isbn": normalized}
        if authors:
            meta["authors"] = authors
        publish_date = str(edition.get("publish_date") or "").strip()
        if publish_date:
            meta["publishDate"] = publish_date
        page_count = _page_count_value(edition.get("number_of_pages"))
        _apply_page_count(meta, page_count)
        cover_ids = edition.get("covers")
        image_url: str | None = None
        if isinstance(cover_ids, list) and cover_ids:
            image_url = _archive_cover_url(_cover_id_value(cover_ids[0]))
        edition_key = str(edition.get("key") or "").strip()
        external_id = _normalize_work_id(work_key) if work_id else (
            edition_key.replace("/books/", "").replace("/books", "") if edition_key else normalized
        )
        if not external_id:
            external_id = normalized
        return OpenLibraryBook(
            external_id=external_id,
            title=title,
            subtitle=str(edition.get("subtitle") or "").strip() or None,
            description=None,
            image_url=image_url,
            metadata=meta,
        )

    def _books_from_search_payload(self, payload: dict[str, Any], *, limit: int) -> list[OpenLibraryBook]:
        docs = payload.get("docs")
        if not isinstance(docs, list):
            return []
        books: list[OpenLibraryBook] = []
        for doc in docs:
            if not isinstance(doc, dict):
                continue
            try:
                books.append(_book_from_search_doc(doc))
            except OpenLibraryError:
                continue
            if len(books) >= limit:
                break
        return books

    def _get_json(self, path: str, params: dict[str, str]) -> dict[str, Any]:
        query_path = path if path.startswith("/") else f"/{path}"
        url = f"{self.base_url}{query_path}"
        headers = {"User-Agent": _USER_AGENT, "Accept": "application/json"}
        last_response: requests.Response | None = None
        for attempt in range(_REQUEST_RETRIES):
            self._throttle()
            try:
                response = requests.get(
                    url,
                    params=params or None,
                    headers=headers,
                    timeout=self.timeout_seconds,
                )
            except requests.RequestException as exc:
                if attempt + 1 >= _REQUEST_RETRIES:
                    raise OpenLibraryError(f"Open Library request failed: {exc}") from exc
                time.sleep(1.0 * (attempt + 1))
                continue
            last_response = response
            if response.status_code in _RETRYABLE_STATUS and attempt + 1 < _REQUEST_RETRIES:
                time.sleep(1.5 * (attempt + 1))
                continue
            if response.status_code >= 400:
                raise OpenLibraryError(
                    f"Open Library request failed ({response.status_code}): "
                    f"{(response.text or '')[:200]}",
                )
            try:
                data = response.json()
            except ValueError as exc:
                raise OpenLibraryError("Open Library returned invalid JSON.") from exc
            if not isinstance(data, dict):
                raise OpenLibraryError("Open Library returned unexpected JSON.")
            return data
        assert last_response is not None
        raise OpenLibraryError(
            f"Open Library request failed ({last_response.status_code}): "
            f"{(last_response.text or '')[:200]}",
        )

    def _throttle(self) -> None:
        if self.min_request_interval_seconds <= 0:
            return
        now = time.monotonic()
        elapsed = now - self._last_request_at
        if elapsed < self.min_request_interval_seconds:
            time.sleep(self.min_request_interval_seconds - elapsed)
        self._last_request_at = time.monotonic()


OPENLIBRARY_PERSON_ID_PREFIX = "ol-"
OPENLIBRARY_PUBLISHER_ID_PREFIX = "olpub-"


def openlibrary_publisher_id(publisher_name: str) -> str:
    name = publisher_name.strip()
    if not name:
        return ""
    return f"{OPENLIBRARY_PUBLISHER_ID_PREFIX}{quote(name, safe='')}"


def parse_openlibrary_publisher_id(publisher_id: str) -> str | None:
    value = publisher_id.strip()
    if value.startswith(OPENLIBRARY_PUBLISHER_ID_PREFIX):
        value = value.removeprefix(OPENLIBRARY_PUBLISHER_ID_PREFIX)
    elif value.startswith("/publishers/"):
        value = value.removeprefix("/publishers/")
    elif value.startswith("publishers/"):
        value = value.removeprefix("publishers/")
    decoded = unquote(value).strip()
    return decoded or None


def openlibrary_person_id(author_id: str) -> str:
    normalized = _normalize_author_id(author_id)
    if not normalized:
        return ""
    return f"{OPENLIBRARY_PERSON_ID_PREFIX}{normalized}"


def parse_openlibrary_person_id(person_id: str) -> str | None:
    value = person_id.strip()
    if value.startswith(OPENLIBRARY_PERSON_ID_PREFIX):
        normalized = _normalize_author_id(value.removeprefix(OPENLIBRARY_PERSON_ID_PREFIX))
    else:
        normalized = _normalize_author_id(value)
    return normalized or None


def _normalize_author_id(raw: str) -> str:
    value = raw.strip()
    if value.startswith("/authors/"):
        value = value.removeprefix("/authors/")
    if value.startswith("authors/"):
        value = value.removeprefix("authors/")
    if re.fullmatch(r"OL\d+A", value):
        return value
    return ""


def _normalize_work_id(raw: str) -> str:
    value = raw.strip()
    if value.startswith("/works/"):
        value = value.removeprefix("/works/")
    if value.startswith("works/"):
        value = value.removeprefix("works/")
    if re.fullmatch(r"OL\d+W", value):
        return value
    return ""


_SEARCH_FIELDS = (
    "key,title,author_name,first_publish_year,cover_i,cover_edition_key,ia,"
    "edition_count,ratings_average,number_of_pages_median,isbn,first_sentence"
)

# Subjects that map to the genre row (everything else becomes a tag).
_GENRE_SUBJECT_PHRASES = frozenset(
    {
        "fiction",
        "fantasy",
        "science fiction",
        "mystery",
        "romance",
        "horror",
        "thriller",
        "biography",
        "history",
        "poetry",
        "drama",
        "adventure",
        "general",
        "short stories",
        "collections & anthologies",
        "young adult fiction",
        "children's fiction",
        "juvenile fiction",
        "literary fiction",
        "historical fiction",
        "graphic novels",
        "comics",
        "humor",
        "war",
        "western",
        "crime",
        "suspense",
        "nonfiction",
        "non-fiction",
    },
)


def _dedupe_subjects_preserve_order(subjects: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for raw in subjects:
        text = raw.strip()
        if not text:
            continue
        key = text.casefold()
        if key in seen:
            continue
        seen.add(key)
        out.append(text)
    return out


def subjects_list_from_metadata(meta: dict[str, object]) -> list[str]:
    raw = meta.get("subjects")
    if isinstance(raw, list):
        items = [str(item).strip() for item in raw if str(item).strip()]
    elif isinstance(raw, str) and raw.strip():
        items = [part.strip() for part in raw.split(",") if part.strip()]
    else:
        return []
    return _dedupe_subjects_preserve_order(items)


def _is_genre_subject(subject: str) -> bool:
    normalized = subject.strip().casefold()
    if not normalized:
        return False
    if normalized.startswith("nyt:"):
        return False
    if "translation" in normalized or "bestseller" in normalized:
        return False
    if "new york times" in normalized:
        return False
    if normalized in _GENRE_SUBJECT_PHRASES:
        return True
    if normalized.endswith(" fiction") and normalized.count(" ") <= 2:
        prefix = normalized.removesuffix(" fiction").strip()
        return prefix in {"science", "general", "literary", "historical", "urban", "contemporary"}
    return False


def split_book_subjects_for_display(
    subjects: list[str],
    *,
    genre_limit: int = 8,
    tag_limit: int = 20,
) -> tuple[list[str], list[str]]:
    deduped = _dedupe_subjects_preserve_order(subjects)
    genres: list[str] = []
    tags: list[str] = []
    genre_keys: set[str] = set()
    tag_keys: set[str] = set()
    for subject in deduped:
        key = subject.casefold()
        if _is_genre_subject(subject):
            if key not in genre_keys:
                genre_keys.add(key)
                genres.append(subject)
        elif key not in genre_keys and key not in tag_keys:
            tag_keys.add(key)
            tags.append(subject)
    return genres[:genre_limit], tags[:tag_limit]

_PUBLISHER_QUERY_PREFIX = re.compile(r"^publisher:\s*(.+)$", re.IGNORECASE)
_ISBN_QUERY_PREFIX = re.compile(r"^isbn[:\s]+(.+)$", re.IGNORECASE)


def _normalize_isbn(raw: str) -> str | None:
    value = raw.strip()
    if not value:
        return None
    prefix_match = _ISBN_QUERY_PREFIX.match(value)
    if prefix_match:
        value = prefix_match.group(1).strip()
    digits = re.sub(r"[\s\-]", "", value)
    if len(digits) in {10, 13} and digits.isdigit():
        return digits
    return None


def isbn13_to_isbn10(isbn13: str) -> str | None:
    if len(isbn13) != 13 or not isbn13.startswith("978") or not isbn13.isdigit():
        return None
    core = isbn13[3:12]
    total = sum(int(ch) * (10 - i) for i, ch in enumerate(core))
    check = (11 - (total % 11)) % 11
    return core + ("X" if check == 10 else str(check))


def _escape_solr_phrase(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _build_book_search_query(
    *,
    text: str | None = None,
    publisher: str | None = None,
    isbn: str | None = None,
    language: str | None = None,
    year: str | None = None,
    genre: str | None = None,
) -> str:
    clauses: list[str] = []
    remaining = (text or "").strip()

    explicit_isbn = _normalize_isbn(isbn or "")
    if explicit_isbn:
        clauses.append(f"isbn:{explicit_isbn}")
        remaining = ""

    if remaining:
        publisher_match = _PUBLISHER_QUERY_PREFIX.match(remaining)
        if publisher_match:
            pub_name = publisher_match.group(1).strip()
            if pub_name:
                clauses.append(f'publisher_facet:"{_escape_solr_phrase(pub_name)}"')
            remaining = ""
        else:
            inline_isbn = _normalize_isbn(remaining)
            if inline_isbn:
                clauses.append(f"isbn:{inline_isbn}")
                remaining = ""

    publisher_name = (publisher or "").strip()
    if publisher_name:
        clauses.append(f'publisher_facet:"{_escape_solr_phrase(publisher_name)}"')

    if remaining:
        if " " in remaining:
            clauses.append(f'"{_escape_solr_phrase(remaining)}"')
        else:
            clauses.append(remaining)

    language_code = (language or "").strip().lower()
    if language_code:
        clauses.append(f"language:{language_code}")

    year_text = (year or "").strip()
    if year_text.isdigit() and len(year_text) == 4:
        clauses.append(f"first_publish_year:{year_text}")

    subject = (genre or "").strip()
    if subject:
        clauses.append(f'subject:"{_escape_solr_phrase(subject)}"')

    return " AND ".join(clauses)


def _cover_id_value(raw: object) -> int | None:
    if isinstance(raw, int) and raw > 0:
        return raw
    if isinstance(raw, str) and raw.isdigit():
        return int(raw)
    return None


def _archive_cover_url(cover_id: int, *, size: str = "M") -> str:
    """Internet Archive zip path used by Open Library coverstore (works without covers.openlibrary.org)."""
    item_id = f"{cover_id // _COVER_ITEM_SIZE:04}"
    rem = cover_id - (_COVER_ITEM_SIZE * (cover_id // _COVER_ITEM_SIZE))
    batch_id = f"{rem // _COVER_BATCH_SIZE:02}"
    size_key = size.strip().lower() or "m"
    prefix = f"{size_key}_covers"
    item = f"{prefix}_{item_id}"
    zip_name = f"{prefix}_{item_id}_{batch_id}.zip"
    filename = f"{cover_id:010d}-{size.upper()}.jpg"
    return f"{_ARCHIVE_DOWNLOAD}/{item}/{zip_name}/{filename}"


def _openlibrary_covers_url(cover_id: int, *, size: str = "M") -> str:
    return f"{_COVERS_BASE}/b/id/{cover_id}-{size.upper()}.jpg"


def _ia_cover_url(ia_identifier: str) -> str:
    safe = ia_identifier.strip()
    return f"{_ARCHIVE_DOWNLOAD}/{safe}/page/cover_w200_h300.jpg"


def _first_ia_identifier(raw: object) -> str | None:
    if not isinstance(raw, list):
        return None
    for entry in raw:
        value = str(entry).strip()
        if value:
            return value
    return None


def _page_count_value(raw: object) -> int | None:
    if isinstance(raw, int) and raw > 0:
        return raw
    if isinstance(raw, float) and raw > 0:
        return int(raw)
    if isinstance(raw, str) and raw.isdigit():
        value = int(raw)
        return value if value > 0 else None
    return None


def _page_count_from_search_doc(doc: dict[str, Any] | None) -> int | None:
    if not doc:
        return None
    return _page_count_value(doc.get("number_of_pages_median"))


def _page_count_from_editions(client: OpenLibraryClient, work_id: str, *, limit: int = 12) -> int | None:
    """Fallback when work/search lack page count — scan a few editions for number_of_pages."""
    payload = client._get_json(f"/works/{work_id}/editions.json", {"limit": str(max(1, min(limit, 25)))})
    entries = payload.get("entries")
    if not isinstance(entries, list):
        return None
    counts: list[int] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        key = entry.get("key")
        if not isinstance(key, str) or not key.startswith("/books/"):
            continue
        edition_id = key.rsplit("/", 1)[-1].strip()
        if not edition_id:
            continue
        pages = _page_count_value(entry.get("number_of_pages"))
        if pages is not None:
            counts.append(pages)
            continue
        try:
            edition_payload = client._get_json(f"/books/{edition_id}.json", {})
        except OpenLibraryError:
            continue
        pages = _page_count_value(edition_payload.get("number_of_pages"))
        if pages is None:
            pages = _page_count_value(edition_payload.get("pagination"))
        if pages is not None:
            counts.append(pages)
    if not counts:
        return None
    counts.sort()
    return counts[len(counts) // 2]


def _apply_page_count(meta: dict[str, object], page_count: int | None) -> None:
    if page_count is not None and page_count > 0:
        meta["pageCount"] = page_count


def _cover_url_from_search_doc(doc: dict[str, Any] | None) -> str | None:
    if not doc:
        return None
    ia_id = _first_ia_identifier(doc.get("ia"))
    if ia_id is not None:
        return _ia_cover_url(ia_id)
    cover_id = _cover_id_value(doc.get("cover_i"))
    if cover_id is not None:
        return _archive_cover_url(cover_id)
    edition_key = doc.get("cover_edition_key")
    if isinstance(edition_key, str) and edition_key.strip():
        olid = edition_key.strip()
        return f"{_COVERS_BASE}/b/olid/{olid}-M.jpg"
    return None


def _author_entries_from_search_doc(
    search_doc: dict[str, Any] | None,
    *,
    limit: int = 6,
) -> list[dict[str, str]]:
    if not search_doc:
        return []
    names = search_doc.get("author_name")
    if not isinstance(names, list):
        return []
    entries: list[dict[str, str]] = []
    for raw in names:
        if len(entries) >= limit:
            break
        name = str(raw).strip()
        if name:
            entries.append({"id": "", "name": name})
    return entries


def _author_entry_name_key(entry: dict[str, str]) -> str | None:
    name = str(entry.get("name") or "").strip().casefold()
    return name or None


def _merge_author_entry_lists(
    base_entries: list[dict[str, str]],
    incoming_entries: list[dict[str, str]],
) -> list[dict[str, str]]:
    """Union authors by name; keep Open Library ids when a source only has display names."""
    ordered_names: list[str] = []
    merged: dict[str, dict[str, str]] = {}

    def absorb(entry: dict[str, str]) -> None:
        name_key = _author_entry_name_key(entry)
        if name_key is None:
            return
        author_id = str(entry.get("id") or "").strip()
        image_url = entry.get("imageUrl")
        existing = merged.get(name_key)
        if existing is None:
            row: dict[str, str] = {
                "id": author_id,
                "name": str(entry.get("name") or "").strip(),
            }
            if isinstance(image_url, str) and image_url.strip():
                row["imageUrl"] = image_url.strip()
            merged[name_key] = row
            ordered_names.append(name_key)
            return
        if not str(existing.get("id") or "").strip() and author_id:
            existing["id"] = author_id
        if (
            not isinstance(existing.get("imageUrl"), str)
            and isinstance(image_url, str)
            and image_url.strip()
        ):
            existing["imageUrl"] = image_url.strip()

    for entry in base_entries:
        absorb(entry)
    for entry in incoming_entries:
        absorb(entry)
    return [merged[name_key] for name_key in ordered_names]


def resolve_openlibrary_author_id(
    client: OpenLibraryClient,
    author_name: str,
) -> str | None:
    """Resolve an Open Library author key (e.g. OL23919A) from a display name."""
    query = author_name.strip()
    if len(query) < 2:
        return None
    try:
        payload = client._get_json("/search/authors.json", {"q": query, "limit": 8})
    except OpenLibraryError:
        return None
    docs = payload.get("docs")
    if not isinstance(docs, list):
        return None
    target = query.casefold()
    exact: list[tuple[int, str]] = []
    fuzzy: list[tuple[int, str]] = []
    for doc in docs:
        if not isinstance(doc, dict):
            continue
        name = str(doc.get("name") or "").strip()
        key = str(doc.get("key") or "").strip()
        author_id = _normalize_author_id(key.rsplit("/", 1)[-1] if key else "")
        if not author_id or not name:
            continue
        work_count = doc.get("work_count")
        weight = work_count if isinstance(work_count, int) else 0
        name_cf = name.casefold()
        if name_cf == target:
            exact.append((weight, author_id))
        elif target in name_cf or name_cf in target:
            fuzzy.append((weight, author_id))
    if exact:
        exact.sort(reverse=True)
        return exact[0][1]
    if fuzzy:
        fuzzy.sort(reverse=True)
        return fuzzy[0][1]
    return None


def _enrich_book_from_sources(
    client: OpenLibraryClient,
    book: OpenLibraryBook,
    work_payload: dict[str, Any],
    search_doc: dict[str, Any] | None,
) -> OpenLibraryBook:
    meta = dict(book.metadata)
    work_author_entries = _authors_from_work(client, work_payload, limit=8)
    search_author_entries = _author_entries_from_search_doc(search_doc, limit=8)
    if work_author_entries:
        author_entries = _merge_author_entry_lists(
            work_author_entries,
            search_author_entries,
        )
    else:
        author_entries = search_author_entries
    authors = _authors_label(search_doc.get("author_name") if search_doc else None)
    if not authors and author_entries:
        authors = ", ".join(entry["name"] for entry in author_entries if entry.get("name"))
    if authors:
        meta["authors"] = authors
    if author_entries:
        meta["authorEntries"] = author_entries
    work_id = str(meta.get("openLibraryWorkId") or book.external_id)
    editions_entries = _fetch_work_editions_entries(client, work_id)
    (
        publisher_entries,
        language_code,
        language_label,
        isbn,
        editions_page_count,
    ) = _metadata_from_edition_entries(client, editions_entries)
    if publisher_entries:
        meta["publisherEntries"] = publisher_entries
    if language_code:
        meta["bookLanguageCode"] = language_code
    if language_label:
        meta["bookLanguage"] = language_label
    if isbn:
        meta["isbn"] = isbn
    if search_doc and "isbn" not in meta:
        search_isbn = _primary_isbn_from_search_doc(search_doc)
        if search_isbn:
            meta["isbn"] = search_isbn
    if isinstance(work_payload.get("series"), list) and work_payload["series"]:
        meta.update(_series_metadata_from_work(client, work_payload))
    cover_url = _cover_url_from_search_doc(search_doc) or book.image_url
    page_count = (
        _page_count_value(meta.get("pageCount"))
        or _page_count_from_search_doc(search_doc)
        or _page_count_value(work_payload.get("number_of_pages"))
        or editions_page_count
    )
    _apply_page_count(meta, page_count)
    meta[BOOK_DETAIL_ENRICHED_KEY] = True
    return replace(
        book,
        image_url=cover_url,
        metadata=meta,
    )


def _author_date_label(raw: object) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    return text or None


def _author_image_url(author_id: str, photos: object) -> str | None:
    if isinstance(photos, list):
        for photo in photos:
            photo_id = _cover_id_value(photo)
            if photo_id is not None:
                return f"{_COVERS_BASE}/a/id/{photo_id}-M.jpg"
    if author_id:
        return f"{_COVERS_BASE}/a/olid/{author_id}-M.jpg"
    return None


_OPENLIBRARY_LANGUAGE_LABELS: dict[str, str] = {
    "eng": "English",
    "en": "English",
    "spa": "Spanish",
    "es": "Spanish",
    "fre": "French",
    "fra": "French",
    "fr": "French",
    "ger": "German",
    "deu": "German",
    "de": "German",
    "por": "Portuguese",
    "pt": "Portuguese",
    "ita": "Italian",
    "it": "Italian",
    "dut": "Dutch",
    "nld": "Dutch",
    "nl": "Dutch",
    "rus": "Russian",
    "ru": "Russian",
    "jpn": "Japanese",
    "ja": "Japanese",
    "chi": "Chinese",
    "zho": "Chinese",
    "zh": "Chinese",
    "pol": "Polish",
    "pl": "Polish",
    "cat": "Catalan",
    "ca": "Catalan",
    "glg": "Galician",
    "gl": "Galician",
    "gle": "Irish",
    "ga": "Irish",
    "wel": "Welsh",
    "cy": "Welsh",
    "lat": "Latin",
    "la": "Latin",
    "grc": "Ancient Greek",
    "heb": "Hebrew",
    "he": "Hebrew",
    "ara": "Arabic",
    "ar": "Arabic",
}


def _normalize_language_code(raw: object) -> str | None:
    if isinstance(raw, dict):
        key = raw.get("key")
        if isinstance(key, str):
            raw = key
        else:
            return None
    if not isinstance(raw, str):
        return None
    value = raw.strip()
    if value.startswith("/languages/"):
        value = value.removeprefix("/languages/")
    if value.startswith("languages/"):
        value = value.removeprefix("languages/")
    value = value.strip().lower()
    return value or None


def _language_label_for_code(code: str) -> str:
    normalized = code.strip().lower()
    if not normalized:
        return ""
    return _OPENLIBRARY_LANGUAGE_LABELS.get(normalized, normalized.upper())


def _first_isbn_from_field(raw: object) -> str | None:
    if not isinstance(raw, list):
        return None
    for item in raw:
        normalized = _normalize_isbn(str(item))
        if normalized:
            return normalized
    return None


def _isbn_from_edition_entry(entry: dict[str, Any]) -> str | None:
    isbn13 = _first_isbn_from_field(entry.get("isbn_13"))
    if isbn13:
        return isbn13
    return _first_isbn_from_field(entry.get("isbn_10"))


def _primary_isbn_from_search_doc(doc: dict[str, Any]) -> str | None:
    raw = doc.get("isbn")
    if not isinstance(raw, list):
        return None
    for item in raw:
        normalized = _normalize_isbn(str(item))
        if not normalized:
            continue
        if len(normalized) == 13:
            return normalized
    for item in raw:
        normalized = _normalize_isbn(str(item))
        if normalized:
            return normalized
    return None


def _fetch_work_editions_entries(
    client: OpenLibraryClient,
    work_id: str,
    *,
    limit: int = 25,
) -> list[Any]:
    normalized = _normalize_work_id(work_id)
    if not normalized:
        return []
    payload = client._get_json(
        f"/works/{normalized}/editions.json",
        {"limit": str(max(1, min(limit, 25)))},
    )
    entries = payload.get("entries")
    return entries if isinstance(entries, list) else []


def _metadata_from_edition_entries(
    client: OpenLibraryClient,
    entries: list[Any],
    *,
    publisher_limit: int = 6,
    max_isbn_edition_fetches: int = 1,
) -> tuple[list[dict[str, str]], str | None, str | None, str | None, int | None]:
    """Publishers, language, ISBN, and median page count from edition list rows."""
    seen_publishers: set[str] = set()
    publishers: list[dict[str, str]] = []
    language_counts: dict[str, int] = {}
    isbn: str | None = None
    edition_fetches = 0
    page_counts: list[int] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        pages = _page_count_value(entry.get("number_of_pages"))
        if pages is not None:
            page_counts.append(pages)
        if isbn is None:
            isbn = _isbn_from_edition_entry(entry)
        if isbn is None and edition_fetches < max_isbn_edition_fetches:
            key = entry.get("key")
            if isinstance(key, str) and key.startswith("/books/"):
                edition_id = key.rsplit("/", 1)[-1].strip()
                if edition_id:
                    edition_fetches += 1
                    try:
                        edition_payload = client._get_json(f"/books/{edition_id}.json", {})
                    except OpenLibraryError:
                        edition_payload = None
                    if isinstance(edition_payload, dict):
                        isbn = _isbn_from_edition_entry(edition_payload)
                        pages = _page_count_value(edition_payload.get("number_of_pages"))
                        if pages is None:
                            pages = _page_count_value(edition_payload.get("pagination"))
                        if pages is not None:
                            page_counts.append(pages)
        raw_publishers = entry.get("publishers")
        if isinstance(raw_publishers, list):
            for raw_name in raw_publishers:
                if len(publishers) >= publisher_limit:
                    break
                name = str(raw_name).strip()
                if not name:
                    continue
                key = name.casefold()
                if key in seen_publishers:
                    continue
                seen_publishers.add(key)
                publishers.append(
                    {
                        "id": openlibrary_publisher_id(name),
                        "name": name,
                    },
                )
        raw_languages = entry.get("languages")
        if isinstance(raw_languages, list):
            for raw_lang in raw_languages:
                code = _normalize_language_code(raw_lang)
                if code:
                    language_counts[code] = language_counts.get(code, 0) + 1
    language_code: str | None = None
    if language_counts:
        language_code = max(language_counts, key=lambda c: language_counts[c])
    language_label = _language_label_for_code(language_code) if language_code else None
    page_count: int | None = None
    if page_counts:
        page_counts.sort()
        page_count = page_counts[len(page_counts) // 2]
    return publishers, language_code, language_label or None, isbn, page_count


def _work_editions_metadata(
    client: OpenLibraryClient,
    work_id: str,
    *,
    publisher_limit: int = 6,
) -> tuple[list[dict[str, str]], str | None, str | None, str | None]:
    entries = _fetch_work_editions_entries(client, work_id)
    publishers, language_code, language_label, isbn, _ = _metadata_from_edition_entries(
        client,
        entries,
        publisher_limit=publisher_limit,
    )
    return publishers, language_code, language_label or None, isbn


def _authors_from_work(
    client: OpenLibraryClient,
    payload: dict[str, Any],
    *,
    limit: int = 6,
) -> list[dict[str, str]]:
    raw = payload.get("authors")
    if not isinstance(raw, list):
        return []
    authors: list[dict[str, str]] = []
    for entry in raw:
        if len(authors) >= limit:
            break
        if not isinstance(entry, dict):
            continue
        author = entry.get("author")
        if not isinstance(author, dict):
            continue
        key = author.get("key")
        if not isinstance(key, str) or not key.strip():
            continue
        author_id = _normalize_author_id(key.rsplit("/", 1)[-1])
        if not author_id:
            continue
        try:
            author_payload = client._get_json(f"/authors/{author_id}.json", {})
        except OpenLibraryError:
            continue
        name = str(author_payload.get("name") or "").strip()
        if not name:
            continue
        image_url = _author_image_url(author_id, author_payload.get("photos"))
        authors.append(
            {
                "id": author_id,
                "name": name,
                **({"imageUrl": image_url} if image_url else {}),
            },
        )
    return authors


def _author_names_from_work(client: OpenLibraryClient, payload: dict[str, Any], *, limit: int = 6) -> list[str]:
    return [a["name"] for a in _authors_from_work(client, payload, limit=limit)]


def _series_metadata_from_work(client: OpenLibraryClient, payload: dict[str, Any]) -> dict[str, object]:
    raw = payload.get("series")
    if not isinstance(raw, list) or not raw:
        return {}
    first = raw[0]
    if not isinstance(first, dict):
        return {}
    series_obj = first.get("series")
    if not isinstance(series_obj, dict):
        return {}
    key = series_obj.get("key")
    if not isinstance(key, str) or not key.strip():
        return {}
    series_id = key.rsplit("/", 1)[-1].strip()
    if not series_id:
        return {}
    position = str(first.get("position") or "").strip()
    try:
        series_payload = client._get_json(f"/series/{series_id}.json", {})
    except OpenLibraryError:
        return {}
    name = str(series_payload.get("name") or "").strip()
    if not name:
        return {}
    meta: dict[str, object] = {
        "bookSeriesKey": series_id,
        "bookSeriesName": name,
        "openLibrarySeriesUrl": f"https://openlibrary.org/series/{series_id}",
    }
    if position:
        meta["bookSeriesPosition"] = position
    return meta


def _search_doc_for_work(client: OpenLibraryClient, work_id: str) -> dict[str, Any] | None:
    payload = client._get_json(
        "/search.json",
        {
            "q": f"key:/works/{work_id}",
            "limit": "1",
            "fields": "cover_i,cover_edition_key,ia,author_name,number_of_pages_median,isbn",
        },
    )
    docs = payload.get("docs")
    if not isinstance(docs, list) or not docs:
        return None
    first = docs[0]
    return first if isinstance(first, dict) else None


def _cover_url_from_id(cover_id: object) -> str | None:
    value = _cover_id_value(cover_id)
    if value is None:
        return None
    return _archive_cover_url(value)


def _authors_label(raw: object) -> str | None:
    if not isinstance(raw, list):
        return None
    names = [str(name).strip() for name in raw if str(name).strip()]
    if not names:
        return None
    return ", ".join(names[:4])


def _publish_year_label(raw: object) -> str:
    if isinstance(raw, int):
        return str(raw) if raw > 0 else ""
    if isinstance(raw, str):
        text = raw.strip()
        if len(text) >= 4 and text[:4].isdigit():
            return text[:4]
        return text
    if isinstance(raw, dict):
        value = raw.get("value")
        if value is not None:
            return _publish_year_label(value)
    return ""


def _description_text(raw: object) -> str | None:
    if isinstance(raw, str):
        text = raw.strip()
        return text or None
    if isinstance(raw, dict):
        value = raw.get("value")
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _first_sentence_text(raw: object) -> str | None:
    if isinstance(raw, list) and raw:
        raw = raw[0]
    if isinstance(raw, str):
        text = raw.strip()
        return text or None
    return None


def _book_from_search_doc(doc: dict[str, Any]) -> OpenLibraryBook:
    work_id = _normalize_work_id(str(doc.get("key") or ""))
    title = str(doc.get("title") or "").strip()
    if not work_id or not title:
        raise OpenLibraryError("Search row missing work id or title.")
    year = doc.get("first_publish_year")
    subtitle_parts: list[str] = []
    authors = _authors_label(doc.get("author_name"))
    if authors:
        subtitle_parts.append(authors)
    if isinstance(year, int):
        subtitle_parts.append(str(year))
    elif isinstance(year, str) and year.strip():
        subtitle_parts.append(year.strip())
    rating = doc.get("ratings_average")
    metadata: dict[str, object] = {
        "openLibraryWorkId": work_id,
        "openLibraryUrl": f"https://openlibrary.org/works/{work_id}",
    }
    if authors:
        metadata["authors"] = authors
    if isinstance(year, int):
        metadata["firstPublishYear"] = year
    if isinstance(rating, (int, float)):
        metadata["openLibraryRating"] = float(rating)
    edition_count = doc.get("edition_count")
    if isinstance(edition_count, int):
        metadata["editionCount"] = edition_count
    _apply_page_count(metadata, _page_count_from_search_doc(doc))
    synopsis = _first_sentence_text(doc.get("first_sentence"))
    return OpenLibraryBook(
        external_id=work_id,
        title=title,
        subtitle=" · ".join(subtitle_parts) if subtitle_parts else None,
        description=synopsis,
        image_url=_cover_url_from_search_doc(doc),
        metadata=metadata,
    )


def _book_from_author_work_entry(entry: dict[str, Any]) -> OpenLibraryBook:
    work_id = _normalize_work_id(str(entry.get("key") or ""))
    title = str(entry.get("title") or "").strip()
    if not work_id or not title:
        raise OpenLibraryError("Author work row missing work id or title.")
    year_raw = entry.get("first_publish_year")
    subtitle_parts: list[str] = []
    if isinstance(year_raw, int):
        subtitle_parts.append(str(year_raw))
    elif isinstance(year_raw, str) and year_raw.strip():
        subtitle_parts.append(year_raw.strip())
    metadata: dict[str, object] = {
        "openLibraryWorkId": work_id,
        "openLibraryUrl": f"https://openlibrary.org/works/{work_id}",
    }
    if isinstance(year_raw, int):
        metadata["firstPublishYear"] = year_raw
    cover_id = _cover_id_value(entry.get("cover_id") or entry.get("cover_i"))
    image_url = _cover_url_from_id(cover_id)
    return OpenLibraryBook(
        external_id=work_id,
        title=title,
        subtitle=" · ".join(subtitle_parts) if subtitle_parts else None,
        description=None,
        image_url=image_url,
        metadata=metadata,
    )


def _book_from_work_payload(work_id: str, payload: dict[str, Any]) -> OpenLibraryBook:
    title = str(payload.get("title") or "").strip()
    if not title:
        raise OpenLibraryError("Work missing title.")
    description = _description_text(payload.get("description"))
    covers = payload.get("covers")
    cover_id = None
    if isinstance(covers, list) and covers:
        cover_id = covers[0]
    image_url = _cover_url_from_id(cover_id)
    year = _publish_year_label(payload.get("first_publish_date") or payload.get("created"))
    subjects_raw = payload.get("subjects")
    subjects: list[str] = []
    if isinstance(subjects_raw, list):
        subjects = [str(s).strip() for s in subjects_raw if str(s).strip()][:12]
    metadata: dict[str, object] = {
        "openLibraryWorkId": work_id,
        "openLibraryUrl": f"https://openlibrary.org/works/{work_id}",
    }
    if year:
        metadata["firstPublishYear"] = year
    if subjects:
        metadata["subjects"] = ", ".join(subjects)
    _apply_page_count(metadata, _page_count_value(payload.get("number_of_pages")))
    return OpenLibraryBook(
        external_id=work_id,
        title=title,
        subtitle=year or None,
        description=description,
        image_url=image_url,
        metadata=metadata,
    )
