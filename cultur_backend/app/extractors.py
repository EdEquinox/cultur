from __future__ import annotations

import base64
from dataclasses import dataclass
from typing import Iterable
from urllib.parse import urljoin

from bs4 import BeautifulSoup, Tag


KNOWN_STATUSES = [
    "Completed",
    "In progress",
    "Planning",
    "Paused",
    "Dropped",
]

MEDIA_TYPE_LABELS = {
    "tv": "TV",
    "season": "TV Seasons",
    "episode": "Episodes",
    "movie": "Movies",
    "anime": "Anime",
    "manga": "Manga",
    "game": "Games",
    "book": "Books",
    "comic": "Comics",
    "boardgame": "Board Games",
    "music": "Music",
    "podcast": "Podcasts",
}


def extract_csrf_token(html: str) -> str | None:
    soup = BeautifulSoup(html, "html.parser")
    input_node = soup.select_one('input[name="csrfmiddlewaretoken"]')
    return _clean_text(input_node.get("value") if input_node else None)


def extract_media_cards(html: str, base_url: str, limit: int = 40) -> list[dict[str, str | None]]:
    soup = BeautifulSoup(html, "html.parser")
    seen_paths: set[str] = set()
    items: list[dict[str, str | None]] = []

    for anchor in soup.select("a[href]"):
      href = _clean_text(anchor.get("href"))
      if not href or not _is_interesting_media_link(href):
        continue

      path = _normalized_path(href)
      if path in seen_paths:
        continue

      title = _pick_title(anchor)
      if not title:
        continue

      seen_paths.add(path)
      surrounding_text = _collect_nearby_text(anchor)
      status = next((value for value in KNOWN_STATUSES if value in surrounding_text), None)
      media_type = detect_media_type(path)
      items.append(
          {
              "mediaRef": encode_media_ref(path),
              "title": title,
              "subtitle": _pick_subtitle(anchor, title),
              "imageUrl": _pick_image(anchor, base_url),
              "detailPath": path,
              "status": status,
              "mediaType": media_type,
              "mediaTypeLabel": media_type_label(media_type),
          },
      )

      if len(items) >= limit:
        break

    return items


def extract_home_sections(
    html: str,
    base_url: str,
    *,
    limit_per_row: int = 20,
) -> list[dict[str, object]]:
    soup = BeautifulSoup(html, "html.parser")
    sections: list[dict[str, object]] = []

    for row in soup.select('[data-home-row="true"]'):
        items = extract_media_cards(str(row), base_url, limit=limit_per_row)
        if not items:
            continue

        title_main, title_detail, sort_label = _extract_home_row_heading(row)
        media_type = next(
            (item.get("mediaType") for item in items if item.get("mediaType")),
            None,
        )
        heading_parts = [value for value in (title_main, title_detail) if value]
        subtitle_parts = []
        if heading_parts:
            subtitle_parts.append(" • ".join(heading_parts))
        if sort_label:
            subtitle_parts.append(sort_label)

        sections.append(
            {
                "title": media_type_label(media_type) or "Library",
                "subtitle": " • ".join(subtitle_parts) or None,
                "mediaType": media_type,
                "items": items,
            },
        )

    return sections


def extract_discover_sections(
    html: str,
    base_url: str,
    *,
    selected_media_type: str,
    limit_per_row: int = 20,
) -> list[dict[str, object]]:
    soup = BeautifulSoup(html, "html.parser")
    sections: list[dict[str, object]] = []

    for row in soup.select('[id^="discover-row-"][data-discover-row-key]'):
        items = extract_media_cards(str(row), base_url, limit=limit_per_row)
        title = _clean_text(_select_text(row, ["h2", "h3"]))
        subtitle = _clean_text(_select_text(row, ["p"]))
        media_type = next(
            (item.get("mediaType") for item in items if item.get("mediaType")),
            selected_media_type if selected_media_type != "all" else None,
        )
        if not title:
            continue

        sections.append(
            {
                "title": title,
                "subtitle": subtitle,
                "mediaType": media_type,
                "items": items,
            },
        )

    return sections


def extract_list_summaries(html: str, base_url: str) -> list[dict[str, str | int | None]]:
    soup = BeautifulSoup(html, "html.parser")
    seen_paths: set[str] = set()
    items: list[dict[str, str | int | None]] = []

    for anchor in soup.select("a[href]"):
      href = _clean_text(anchor.get("href"))
      if not href or not _is_interesting_list_link(href):
        continue

      path = _normalized_path(href)
      if path in seen_paths:
        continue

      title = _pick_title(anchor)
      if not title:
        continue

      seen_paths.add(path)
      text = _collect_nearby_text(anchor)
      items_count = _extract_items_count(text)
      items.append(
          {
              "title": title,
              "path": path,
              "subtitle": _pick_subtitle(anchor, title),
              "itemsCount": items_count,
          },
      )

    return items


def extract_media_detail(
    html: str,
    base_url: str,
    *,
    path: str,
) -> dict[str, object]:
    soup = BeautifulSoup(html, "html.parser")
    title = _pick_page_title(soup, path)
    metadata: dict[str, str] = {}

    for key_node in soup.select("dt"):
      key = _clean_text(key_node.get_text(" ", strip=True))
      value = _clean_text(key_node.find_next_sibling("dd").get_text(" ", strip=True) if key_node.find_next_sibling("dd") else None)
      if key and value:
        metadata[key] = value

    if not metadata:
      for row in soup.select("tr"):
        cells = row.find_all(["th", "td"])
        if len(cells) >= 2:
          key = _clean_text(cells[0].get_text(" ", strip=True))
          value = _clean_text(cells[1].get_text(" ", strip=True))
          if key and value:
            metadata[key] = value

    facts: list[str] = []
    for node in soup.select("p, li, dd"):
      text = _clean_text(node.get_text(" ", strip=True))
      if not text or text == title or len(text) < 12:
        continue
      if text in facts:
        continue
      facts.append(text)
      if len(facts) >= 10:
        break

    parsed_ref = ParsedMediaRef.try_parse(path)
    body_text = soup.get_text(" ", strip=True)
    current_status = next((value for value in KNOWN_STATUSES if value in body_text), None)

    return {
        "mediaRef": encode_media_ref(path),
        "title": title,
        "subtitle": _clean_text(_select_text(soup, ["h2", "h3", '[class*="subtitle"]', '[class*="tagline"]'])),
        "imageUrl": _pick_first_image(soup, base_url),
        "currentStatus": current_status,
        "source": parsed_ref.source if parsed_ref else None,
        "mediaType": parsed_ref.media_type if parsed_ref else None,
        "mediaId": parsed_ref.media_id if parsed_ref else None,
        "canUpdateProgress": parsed_ref is not None,
        "facts": facts,
        "metadata": metadata,
    }


def encode_media_ref(path: str) -> str:
    normalized = _normalized_path(path)
    return base64.urlsafe_b64encode(normalized.encode("utf-8")).decode("utf-8").rstrip("=")


def decode_media_ref(media_ref: str) -> str:
    padded = media_ref + "=" * (-len(media_ref) % 4)
    decoded = base64.urlsafe_b64decode(padded.encode("utf-8")).decode("utf-8")
    return _normalized_path(decoded)


@dataclass(slots=True)
class ParsedMediaRef:
    path: str
    source: str
    media_type: str
    media_id: str

    @classmethod
    def try_parse(cls, path: str) -> "ParsedMediaRef | None":
        normalized = _normalized_path(path)
        parts = [part for part in normalized.split("/") if part]
        if len(parts) < 5 or parts[0] != "details":
            return None
        return cls(
            path=normalized,
            source=parts[1],
            media_type=parts[2],
            media_id=parts[3],
        )


def detect_media_type(path: str) -> str | None:
    normalized = _normalized_path(path)
    parsed = ParsedMediaRef.try_parse(normalized)
    if parsed is not None:
        if parsed.media_type == "tv" and "/season/" in normalized:
            return "season"
        if parsed.media_type == "tv" and "/episode/" in normalized:
            return "episode"
        return parsed.media_type

    parts = [part for part in normalized.split("/") if part]
    if len(parts) >= 2 and parts[0] == "music":
        return "music"
    if len(parts) >= 2 and parts[0] == "podcast":
        return "podcast"
    return None


def media_type_label(media_type: str | None) -> str | None:
    if not media_type:
        return None
    return MEDIA_TYPE_LABELS.get(media_type, media_type.replace("-", " ").title())


def _pick_page_title(soup: BeautifulSoup, path: str) -> str:
    for candidate in (
        _select_text(soup, ["h1"]),
        _select_text(soup, ["title"]),
    ):
        text = _clean_text(candidate)
        if text:
            return text.replace(" - Yamtrack", "")

    fallback = next((part for part in reversed(path.split("/")) if part), "Untitled")
    return fallback.replace("-", " ")


def _extract_home_row_heading(row: Tag) -> tuple[str | None, str | None, str | None]:
    heading_container = row.find_previous_sibling("div")
    if heading_container is None:
        parent = row.parent
        if isinstance(parent, Tag):
            heading_container = parent.find_previous_sibling("div")

    if heading_container is None:
        return None, None, None

    title_main = _clean_text(
        heading_container.select_one(".home-row-heading-title").get_text(" ", strip=True)
        if heading_container.select_one(".home-row-heading-title")
        else None,
    )
    title_detail = _clean_text(
        heading_container.select_one(".home-row-heading-detail").get_text(" ", strip=True)
        if heading_container.select_one(".home-row-heading-detail")
        else None,
    )
    sort_label = _clean_text(
        heading_container.select_one(".home-row-heading-sort-label").get_text(" ", strip=True)
        if heading_container.select_one(".home-row-heading-sort-label")
        else None,
    )
    return title_main, title_detail, sort_label


def _pick_title(anchor: Tag) -> str | None:
    candidates: Iterable[str | None] = (
        anchor.get("aria-label"),
        anchor.get("title"),
        anchor.select_one("img").get("alt") if anchor.select_one("img") else None,
        _select_text(anchor, ["h1", "h2", "h3", "h4", '[class*="title"]']),
        anchor.get_text(" ", strip=True),
        _select_text(anchor.parent, ["h1", "h2", "h3", "h4", '[class*="title"]']),
    )

    for candidate in candidates:
        text = _clean_text(candidate)
        if text:
            return text

    return None


def _pick_subtitle(anchor: Tag, title: str) -> str | None:
    nearby = _collect_nearby_text(anchor)
    if not nearby:
        return None

    normalized = nearby.replace(title, "").strip()
    for status in KNOWN_STATUSES:
        normalized = normalized.replace(status, "").strip()

    normalized = " ".join(normalized.split())
    if not normalized:
        return None
    if len(normalized) > 160:
        return f"{normalized[:157]}..."
    return normalized


def _collect_nearby_text(anchor: Tag) -> str:
    for scope in (anchor.parent, anchor.parent.parent if anchor.parent else None):
        text = _clean_text(scope.get_text(" ", strip=True) if scope else None)
        if text:
            return text
    return ""


def _pick_image(anchor: Tag, base_url: str) -> str | None:
    for scope in (anchor, anchor.parent, anchor.parent.parent if anchor.parent else None):
        if not scope:
            continue
        image = scope.select_one("img")
        source = _clean_text(image.get("src") if image else None)
        if source:
            return urljoin(base_url, source)
    return None


def _pick_first_image(soup: BeautifulSoup, base_url: str) -> str | None:
    image = soup.select_one("img")
    source = _clean_text(image.get("src") if image else None)
    if not source:
        return None
    return urljoin(base_url, source)


def _extract_items_count(text: str) -> int | None:
    for token, next_token in zip(text.split(), text.split()[1:]):
        if next_token.lower().startswith("item") and token.isdigit():
            return int(token)
    return None


def _normalized_path(path: str) -> str:
    return path if path.startswith("/") else f"/{path}"


def _clean_text(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = " ".join(value.split()).strip()
    return normalized or None


def _select_text(scope: Tag | BeautifulSoup | None, selectors: list[str]) -> str | None:
    if scope is None:
        return None
    for selector in selectors:
        node = scope.select_one(selector)
        if node:
            return node.get_text(" ", strip=True)
    return None


def _is_interesting_media_link(href: str) -> bool:
    return href.startswith("/details/") or href.startswith("/music/artist/") or href.startswith("/music/album/") or href.startswith("/podcast/show/")


def _is_interesting_list_link(href: str) -> bool:
    return (
        href.startswith("/list/")
        and not href.endswith("/json")
        and not href.endswith("/rss")
        and "/add" not in href
        and "/recommend" not in href
    )
