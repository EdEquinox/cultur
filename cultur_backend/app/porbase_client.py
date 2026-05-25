"""PORBASE / BNP URN service — Portuguese national bibliography by ISBN."""

from __future__ import annotations

import re
import time
from dataclasses import dataclass
from typing import Any
from xml.dom.minidom import parseString

import requests

from .openlibrary_client import BOOK_DETAIL_ENRICHED_KEY, OpenLibraryBook, _normalize_isbn

DEFAULT_PORBASE_ISBN_URL = "http://urn.porbase.org/isbn/dc/xml?id={isbn}"
_USER_AGENT = "Cultur/1.0 (+https://github.com)"
_REQUEST_RETRIES = 3
_RETRYABLE_STATUS = {429, 500, 502, 503, 504}
_RECORD_ID_RE = re.compile(r"Id\.\s*do\s*registo:\s*(\d+)", re.IGNORECASE)
_BN_IMAGE_RE = re.compile(r"https?://rnod\.bnportugal\.gov\.pt/[^\s<\"']+", re.IGNORECASE)


class PorbaseError(RuntimeError):
    pass


@dataclass(slots=True)
class PorbaseClient:
    isbn_url_template: str = DEFAULT_PORBASE_ISBN_URL
    timeout_seconds: float = 25.0
    min_request_interval_seconds: float = 0.2
    _last_request_at: float = 0.0

    def fetch_by_isbn(self, isbn: str) -> OpenLibraryBook | None:
        normalized = _normalize_isbn(isbn)
        if not normalized:
            return None
        url = self.isbn_url_template.format(isbn=normalized)
        xml = self._get_xml(url)
        if not xml:
            return None
        return _book_from_porbase_xml(xml, normalized)

    def _get_xml(self, url: str) -> str | None:
        if self.min_request_interval_seconds > 0:
            now = time.monotonic()
            elapsed = now - self._last_request_at
            if elapsed < self.min_request_interval_seconds:
                time.sleep(self.min_request_interval_seconds - elapsed)
            self._last_request_at = time.monotonic()

        headers = {"User-Agent": _USER_AGENT, "Accept": "application/xml,text/xml,*/*"}
        last_response: requests.Response | None = None
        for attempt in range(_REQUEST_RETRIES):
            try:
                response = requests.get(url, headers=headers, timeout=self.timeout_seconds)
            except requests.RequestException as exc:
                if attempt + 1 >= _REQUEST_RETRIES:
                    raise PorbaseError(f"PORBASE request failed: {exc}") from exc
                time.sleep(1.0 * (attempt + 1))
                continue
            last_response = response
            if response.status_code in _RETRYABLE_STATUS and attempt + 1 < _REQUEST_RETRIES:
                time.sleep(1.5 * (attempt + 1))
                continue
            if response.status_code == 404:
                return None
            if response.status_code >= 400:
                raise PorbaseError(
                    f"PORBASE request failed ({response.status_code}): "
                    f"{(response.text or '')[:200]}",
                )
            return _decode_porbase_xml(response)
        return None


def _decode_porbase_xml(response: requests.Response) -> str:
    raw = response.content
    if not raw:
        return ""
    for encoding in ("utf-8", "iso-8859-1", "windows-1252"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def porbase_book_from_media_item(item: object) -> OpenLibraryBook:
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


def _book_from_porbase_xml(xml: str, isbn: str) -> OpenLibraryBook | None:
    if "Registo inexistente" in xml or "<dc" not in xml.lower():
        return None
    try:
        dom = parseString(xml)
    except Exception as exc:
        raise PorbaseError(f"Invalid PORBASE XML: {exc}") from exc

    dc_nodes = dom.getElementsByTagName("dc")
    if not dc_nodes:
        return None
    root = dc_nodes[0]

    title = _first_dc_text(root, "title")
    if not title:
        return None
    title = title.lstrip("?").strip()

    creators = _all_dc_text(root, "creator")
    authors = _clean_porbase_authors(creators)
    publishers = _all_dc_text(root, "publisher")
    publisher = publishers[0] if publishers else None
    dates = _all_dc_text(root, "date")
    year: int | None = None
    for raw in dates:
        digits = "".join(c for c in raw if c.isdigit())[:4]
        if len(digits) == 4:
            year = int(digits)
            break
    languages = _all_dc_text(root, "language")
    language_code = languages[0][:3].lower() if languages else None
    descriptions = [d for d in _all_dc_text(root, "description") if d]
    description = descriptions[0] if descriptions else None
    identifiers = _all_dc_text(root, "identifier")
    record_id: str | None = None
    image_url: str | None = None
    for ident in identifiers:
        m = _RECORD_ID_RE.search(ident)
        if m:
            record_id = m.group(1)
        img = _BN_IMAGE_RE.search(ident)
        if img and image_url is None:
            image_url = img.group(0).replace("&amp;", "&")

    external_id = record_id or isbn
    author_entries = [{"id": "", "name": name} for name in authors[:8]]
    meta: dict[str, object] = {
        "importSource": "porbase",
        "isbn": isbn,
        BOOK_DETAIL_ENRICHED_KEY: True,
        "porbaseUrl": f"http://urn.porbase.org/isbn/dc/xml?id={isbn}",
    }
    if authors:
        meta["authors"] = ", ".join(authors)
    if author_entries:
        meta["authorEntries"] = author_entries
    if publisher:
        meta["publisher"] = publisher
    if year is not None:
        meta["firstPublishYear"] = year
    if language_code:
        meta["bookLanguageCode"] = language_code
    subjects = _all_dc_text(root, "subject")
    if subjects:
        meta["subjects"] = subjects[:12]
    relations = _all_dc_text(root, "relation")
    if relations:
        meta["seriesNames"] = relations[:6]

    return OpenLibraryBook(
        external_id=external_id,
        title=title,
        subtitle=None,
        description=description,
        image_url=image_url,
        metadata=meta,
    )


def _first_dc_text(node: Any, tag: str) -> str | None:
    values = _all_dc_text(node, tag)
    return values[0] if values else None


def _all_dc_text(node: Any, tag: str) -> list[str]:
    out: list[str] = []
    candidates = node.getElementsByTagName(tag)
    if not candidates:
        candidates = node.getElementsByTagName(f"dc:{tag}")
    for child in candidates:
        parts: list[str] = []
        for sub in child.childNodes:
            if sub.nodeType == sub.TEXT_NODE:
                parts.append(str(sub.data))
        text = "".join(parts).strip()
        if text:
            out.append(text)
    return out


def _clean_porbase_authors(raw: list[str]) -> list[str]:
    cleaned: list[str] = []
    for item in raw:
        name = re.sub(r"\d{4}-?$", "", item).strip(" ,-")
        if name and name not in cleaned:
            cleaned.append(name)
    return cleaned
