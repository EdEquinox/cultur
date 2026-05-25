"""Scrape public Musicboard.app profile pages (ported from musicboard-extract/extract_data_musicboard.py)."""

from __future__ import annotations

import json
import logging
import os
import re
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)

MUSICBOARD_BASE_URL = "https://musicboard.app"

# Custom list slugs vary per account (path after /{username}/). Override via MUSICBOARD_LIST_PATHS JSON.
DEFAULT_MUSICBOARD_LIST_PATHS: tuple[tuple[str, str, str], ...] = (
    ("story", "list/story-songs", "musicboardStory.csv"),
    ("owned", "list/owned", "musicboardOwned.csv"),
    ("fav", "list/fav-songs", "musicboardFav.csv"),
    ("tobuy", "list/need-money-to-get-them", "musicboardTobuy.csv"),
)

_VIEW_MORE_XPATH = '//*[@id="root"]/div/div/div/div/div[2]/div/div[1]/div/div[1]/div[7]/div'


class MusicboardScrapeError(RuntimeError):
    pass


@dataclass(slots=True)
class MusicboardListPath:
    key: str
    path: str
    source_file: str


@dataclass(slots=True)
class MusicboardScrapedRow:
    source_file: str
    source_key: str
    title: str
    artist: str | None = None
    image_url: str | None = None
    rating: float | None = None
    review: str | None = None
    completed_at: str | None = None
    review_target: str | None = None


@dataclass(slots=True)
class MusicboardImportSource:
    source_key: str
    kind: str
    name: str
    path: str
    source_file: str
    use_view_more: bool = False
    page_kind: str = "content_options"


def builtin_musicboard_sources() -> list[MusicboardImportSource]:
    return [
        MusicboardImportSource(
            source_key="builtin:wantlist",
            kind="builtin",
            name="Later (wantlist)",
            path="wantlist",
            source_file="musicboardLater.csv",
            use_view_more=False,
            page_kind="content_options",
        ),
        MusicboardImportSource(
            source_key="builtin:albums",
            kind="builtin",
            name="Albums",
            path="albums",
            source_file="musicboardAlbum.csv",
            use_view_more=False,
            page_kind="album",
        ),
        MusicboardImportSource(
            source_key="builtin:history",
            kind="builtin",
            name="Listen history",
            path="history",
            source_file="musicboardHistory.csv",
            page_kind="history",
        ),
        MusicboardImportSource(
            source_key="builtin:reviews",
            kind="builtin",
            name="Reviews",
            path="reviews",
            source_file="musicboardReviews.csv",
            use_view_more=False,
            page_kind="reviews",
        ),
    ]


def optional_configured_list_paths(raw: str) -> list[MusicboardListPath]:
    """Parse MUSICBOARD_LIST_PATHS env JSON; returns [] when unset (does not apply defaults)."""
    text = (raw or "").strip()
    if not text:
        return []
    return parse_musicboard_list_paths_json(text)


def sources_from_list_paths(paths: list[MusicboardListPath]) -> list[MusicboardImportSource]:
    return [
        MusicboardImportSource(
            source_key=f"list:{spec.key}",
            kind="list",
            name=_slug_to_label(spec.key),
            path=spec.path.strip().lstrip("/"),
            source_file=spec.source_file,
            use_view_more=True,
            page_kind="content_options",
        )
        for spec in paths
    ]


def merge_musicboard_sources(*groups: list[MusicboardImportSource]) -> list[MusicboardImportSource]:
    """Merge source groups; first occurrence wins per path and per source_key."""
    merged: list[MusicboardImportSource] = []
    seen_paths: set[str] = set()
    seen_keys: set[str] = set()
    for group in groups:
        for source in group:
            path_key = source.path.casefold()
            if path_key in seen_paths or source.source_key in seen_keys:
                continue
            merged.append(source)
            seen_paths.add(path_key)
            seen_keys.add(source.source_key)
    return merged


def extract_list_sources_from_html(handle: str, html: str) -> list[MusicboardImportSource]:
    """Parse custom list links from a Musicboard HTML page."""
    soup = BeautifulSoup(html, "html.parser")
    custom: list[MusicboardImportSource] = []
    seen_paths: set[str] = set()
    for anchor in soup.find_all("a", href=True):
        href = str(anchor.get("href") or "").strip()
        if not href:
            continue
        path = _list_path_from_href(handle, href)
        if not path or path in seen_paths:
            continue
        seen_paths.add(path)
        slug = path.removeprefix("list/").strip("/")
        label = anchor.get_text(strip=True) or _slug_to_label(slug)
        custom.append(
            MusicboardImportSource(
                source_key=f"list:{slug}",
                kind="list",
                name=label,
                path=path,
                source_file=f"musicboardList_{slug}.csv",
                use_view_more=True,
                page_kind="content_options",
            ),
        )
    return custom


def discover_musicboard_sources(
    musicboard_username: str,
    *,
    configured_list_paths_json: str = "",
) -> list[MusicboardImportSource]:
    """Discover built-in areas, server-configured lists, and lists linked on the profile."""
    handle = (musicboard_username or "").strip().lstrip("@")
    if not handle:
        raise MusicboardScrapeError("musicboard username is required.")

    builtins = builtin_musicboard_sources()
    configured = sources_from_list_paths(optional_configured_list_paths(configured_list_paths_json))
    scraped: list[MusicboardImportSource] = []
    driver = _create_driver()
    try:
        for suffix in ("", "lists"):
            driver.get(_profile_url(handle, suffix))
            time.sleep(5)
            _scroll_page_for_lazy_load(driver)
            scraped.extend(extract_list_sources_from_html(handle, driver.page_source))
    finally:
        driver.quit()

    return merge_musicboard_sources(builtins, configured, scraped)


def scrape_musicboard_sources(
    musicboard_username: str,
    sources: list[MusicboardImportSource],
    *,
    scroll_pause_seconds: float = 2.0,
    page_load_seconds: float = 5.0,
) -> list[MusicboardScrapedRow]:
    handle = (musicboard_username or "").strip().lstrip("@")
    if not handle:
        raise MusicboardScrapeError("musicboard username is required.")
    if not sources:
        return []

    rows: list[MusicboardScrapedRow] = []
    driver = _create_driver()
    try:
        for source in sources:
            url = _profile_url(handle, source.path)
            try:
                if source.page_kind == "history":
                    parsed = _scrape_history(driver, url, page_load_seconds, source=source)
                else:
                    html = _fetch_list_page_html(
                        driver,
                        url,
                        use_view_more=source.use_view_more,
                        scroll_pause_seconds=scroll_pause_seconds,
                        page_load_seconds=page_load_seconds,
                    )
                    if source.page_kind == "album":
                        parsed = _parse_album_page(html, source=source)
                    elif source.page_kind == "reviews":
                        parsed = _parse_reviews_page(html, source=source)
                    else:
                        parsed = _parse_content_options(html, source=source)
                logger.info("Musicboard scrape: %s → %d rows", source.source_key, len(parsed))
                rows.extend(parsed)
            except MusicboardScrapeError as exc:
                logger.warning("Musicboard scrape: skipped %s (%s)", source.source_key, exc)
    finally:
        driver.quit()
    return rows


def scrape_musicboard_profile(
    musicboard_username: str,
    *,
    list_paths: list[MusicboardListPath] | None = None,
    include_wantlist: bool = True,
    include_albums: bool = True,
    include_reviews: bool = True,
    include_history: bool = True,
    scroll_pause_seconds: float = 2.0,
    page_load_seconds: float = 5.0,
) -> list[MusicboardScrapedRow]:
    """Scrape albums/tracks from a public Musicboard user profile."""
    handle = (musicboard_username or "").strip().lstrip("@")
    if not handle:
        raise MusicboardScrapeError("musicboard username is required.")

    paths = list_paths if list_paths else [
        MusicboardListPath(key=key, path=path, source_file=source)
        for key, path, source in DEFAULT_MUSICBOARD_LIST_PATHS
    ]

    sources: list[MusicboardImportSource] = [
        MusicboardImportSource(
            source_key=f"list:{spec.key}",
            kind="list",
            name=_slug_to_label(spec.key),
            path=spec.path,
            source_file=spec.source_file,
            use_view_more=True,
            page_kind="content_options",
        )
        for spec in paths
    ]
    builtins = {source.source_key: source for source in builtin_musicboard_sources()}
    if include_wantlist and "builtin:wantlist" in builtins:
        sources.append(builtins["builtin:wantlist"])
    if include_albums and "builtin:albums" in builtins:
        sources.append(builtins["builtin:albums"])
    if include_reviews and "builtin:reviews" in builtins:
        sources.append(builtins["builtin:reviews"])
    if include_history and "builtin:history" in builtins:
        sources.append(builtins["builtin:history"])

    return scrape_musicboard_sources(
        handle,
        sources,
        scroll_pause_seconds=scroll_pause_seconds,
        page_load_seconds=page_load_seconds,
    )


def parse_musicboard_list_paths_json(raw: str) -> list[MusicboardListPath]:
    text = (raw or "").strip()
    if not text:
        return [
            MusicboardListPath(key=key, path=path, source_file=source)
            for key, path, source in DEFAULT_MUSICBOARD_LIST_PATHS
        ]
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise MusicboardScrapeError(f"Invalid MUSICBOARD_LIST_PATHS JSON: {exc}") from exc
    if not isinstance(payload, list):
        raise MusicboardScrapeError("MUSICBOARD_LIST_PATHS must be a JSON array.")
    out: list[MusicboardListPath] = []
    for row in payload:
        if not isinstance(row, dict):
            continue
        key = str(row.get("key") or "").strip()
        path = str(row.get("path") or "").strip().lstrip("/")
        source = str(row.get("sourceFile") or row.get("source_file") or "").strip()
        if not source and key:
            source = f"musicboard{key.title()}.csv"
        if key and path and source:
            out.append(MusicboardListPath(key=key, path=path, source_file=source))
    if not out:
        raise MusicboardScrapeError("MUSICBOARD_LIST_PATHS is empty.")
    return out


def _list_path_from_href(handle: str, href: str) -> str | None:
    text = href.strip()
    if text.startswith("http"):
        if MUSICBOARD_BASE_URL not in text:
            return None
        text = text.split(MUSICBOARD_BASE_URL, 1)[-1]
    text = text.split("?", 1)[0].split("#", 1)[0].strip()
    if not text:
        return None
    if not text.startswith("/"):
        text = f"/{text}"

    prefix = f"/{handle}/list/"
    if text.casefold().startswith(prefix.casefold()):
        slug = text[len(prefix) :].strip("/")
        if slug and "/" not in slug:
            return f"list/{slug}"

    bare = text.lstrip("/")
    if bare.casefold().startswith("list/"):
        slug = bare[5:].strip("/")
        if slug and "/" not in slug:
            return f"list/{slug}"

    return None


def _scroll_page_for_lazy_load(driver: Any, *, pause_seconds: float = 1.5, max_rounds: int = 12) -> None:
    from selenium.webdriver.common.by import By
    from selenium.webdriver.common.keys import Keys

    last_height = driver.execute_script("return document.body.scrollHeight")
    for _ in range(max_rounds):
        driver.find_element(By.TAG_NAME, "body").send_keys(Keys.END)
        time.sleep(pause_seconds)
        new_height = driver.execute_script("return document.body.scrollHeight")
        if new_height == last_height:
            break
        last_height = new_height


def _slug_to_label(slug: str) -> str:
    text = (slug or "").replace("-", " ").replace("_", " ").strip()
    return text.title() if text else "List"


def _profile_url(handle: str, suffix: str) -> str:
    cleaned = suffix.strip().strip("/")
    return f"{MUSICBOARD_BASE_URL}/{handle}/{cleaned}" if cleaned else f"{MUSICBOARD_BASE_URL}/{handle}"


def _create_driver() -> Any:
    try:
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
    except ImportError as exc:
        raise MusicboardScrapeError(
            "Selenium is not installed. Install selenium and Chromium/Chrome for Musicboard profile import.",
        ) from exc

    options = Options()
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1920,1080")
    chrome_bin = os.environ.get("CHROME_BIN", "").strip()
    for candidate in (
        chrome_bin,
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
    ):
        if candidate and Path(candidate).is_file():
            options.binary_location = candidate
            break
    try:
        return webdriver.Chrome(options=options)
    except Exception as exc:
        raise MusicboardScrapeError(
            "Could not start Chrome/Chromium for Musicboard scrape. "
            "Install chromium and chromedriver on the server.",
        ) from exc


def _fetch_list_page_html(
    driver: Any,
    url: str,
    *,
    use_view_more: bool,
    scroll_pause_seconds: float,
    page_load_seconds: float,
) -> str:
    from selenium.common.exceptions import NoSuchElementException
    from selenium.webdriver.common.by import By
    from selenium.webdriver.common.keys import Keys

    driver.get(url)
    time.sleep(page_load_seconds)

    if use_view_more:
        while True:
            try:
                element = driver.find_element(By.XPATH, _VIEW_MORE_XPATH)
                driver.execute_script("arguments[0].click();", element)
                time.sleep(scroll_pause_seconds)
            except NoSuchElementException:
                break
            except Exception:
                break
    else:
        last_height = driver.execute_script("return document.body.scrollHeight")
        while True:
            driver.find_element(By.TAG_NAME, "body").send_keys(Keys.END)
            time.sleep(scroll_pause_seconds)
            new_height = driver.execute_script("return document.body.scrollHeight")
            if new_height == last_height:
                break
            last_height = new_height

    return driver.page_source


def _scrape_history(
    driver: Any,
    url: str,
    page_load_seconds: float,
    *,
    source: MusicboardImportSource,
) -> list[MusicboardScrapedRow]:
    from selenium.webdriver.common.by import By

    driver.get(url)
    time.sleep(page_load_seconds)

    rows: list[MusicboardScrapedRow] = []
    seen: set[tuple[str, str]] = set()
    page = 0

    while True:
        soup = BeautifulSoup(driver.page_source, "html.parser")
        items = soup.find_all("div", class_=re.compile(r"^historyitem_container"))
        page_rows = 0

        for item in items:
            parsed = _extract_history_row(item)
            if parsed is None:
                continue
            date_str, title, rating, image_url = parsed
            key = (date_str, title)
            if key in seen:
                continue
            seen.add(key)
            rows.append(
                MusicboardScrapedRow(
                    source_file=source.source_file,
                    source_key=source.source_key,
                    title=title,
                    image_url=image_url,
                    rating=rating if rating and rating > 0 else None,
                    completed_at=_history_date_to_iso(date_str),
                ),
            )
            page_rows += 1

        logger.info(
            "Musicboard history page %d: %d items (%d new, %d total)",
            page + 1,
            len(items),
            page_rows,
            len(rows),
        )

        if not _click_history_next(driver):
            break
        page += 1
        if page > 100:
            break

    return rows


def _click_history_next(driver: Any) -> bool:
    from selenium.webdriver.common.by import By

    next_buttons = driver.find_elements(
        By.XPATH,
        "//h5[contains(@class,'button_text') and normalize-space()='Next']",
    )
    if not next_buttons:
        return False
    btn = next_buttons[0]
    driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", btn)
    time.sleep(0.3)
    driver.execute_script("arguments[0].click();", btn)
    time.sleep(2.5)
    return True


def _parse_content_options(html: str, *, source: MusicboardImportSource) -> list[MusicboardScrapedRow]:
    soup = BeautifulSoup(html, "html.parser")
    rows: list[MusicboardScrapedRow] = []
    for div in soup.find_all("div", class_="content-options-wrapper"):
        parsed = _extract_track_row(div)
        if parsed is None:
            continue
        title, artist, image_url = parsed
        rows.append(
            MusicboardScrapedRow(
                source_file=source.source_file,
                source_key=source.source_key,
                title=title,
                artist=artist or None,
                image_url=image_url,
            ),
        )
    return rows


def _parse_album_page(html: str, *, source: MusicboardImportSource) -> list[MusicboardScrapedRow]:
    soup = BeautifulSoup(html, "html.parser")
    rows: list[MusicboardScrapedRow] = []
    for div in soup.find_all("div", class_="content-options-wrapper"):
        title_el = _find_by_class_prefix(div, "h6", "bigbackenditem_title")
        img_el = _find_by_class_prefix(div, "img", "albumcover_cover")
        if not title_el or not img_el or not img_el.get("src"):
            continue
        rating = _star_rating(div)
        rows.append(
            MusicboardScrapedRow(
                source_file=source.source_file,
                source_key=source.source_key,
                title=title_el.get_text(strip=True),
                image_url=img_el["src"],
                rating=rating if rating > 0 else None,
            ),
        )
    return rows


def _parse_reviews_page(html: str, *, source: MusicboardImportSource) -> list[MusicboardScrapedRow]:
    soup = BeautifulSoup(html, "html.parser")
    rows: list[MusicboardScrapedRow] = []
    for div in soup.find_all("div", class_="link-inner"):
        target_el = _find_by_class_prefix(div, "h5", "reviewitem_a")
        if not target_el:
            continue
        title_el = _find_by_class_prefix(div, "h5", "textColor")
        artist_el = _find_by_class_prefix(div, "a", "reviewitem_artistLink")
        review_container = _find_by_class_prefix(div, "div", "truncate_container")
        review = None
        if review_container is not None:
            review_p = review_container.find("p")
            if review_p:
                review = review_p.get_text(strip=True)
        if title_el is None:
            continue
        rating = _star_rating(div)
        rows.append(
            MusicboardScrapedRow(
                source_file=source.source_file,
                source_key=source.source_key,
                title=title_el.get_text(strip=True),
                artist=artist_el.get_text(strip=True) if artist_el else None,
                review_target=target_el.get_text(strip=True),
                review=review,
                rating=rating if rating > 0 else None,
            ),
        )
    return rows


def _extract_track_row(div: Any) -> tuple[str, str, str] | None:
    title_el = _find_by_class_prefix(div, "h6", "bigbackenditem_title")
    if not title_el:
        return None
    artist_el = _find_by_class_prefix(div, "a", "bigbackenditem_artistLink")
    if not artist_el:
        artist_el = _find_by_class_prefix(div, "p", "bigbackenditem_artist")
    img_el = _find_by_class_prefix(div, "img", "albumcover_cover")
    if not img_el or not img_el.get("src"):
        return None
    return (
        title_el.get_text(strip=True),
        artist_el.get_text(strip=True) if artist_el else "",
        img_el["src"],
    )


def _extract_history_row(item: Any) -> tuple[str, str, float, str] | None:
    date_container = _find_by_class_prefix(item, "div", "historyitem_dateContainer")
    day, month = "", ""
    if date_container:
        date_parts = date_container.find_all("p", class_=re.compile("highDarkGrey"))
        if len(date_parts) >= 2:
            day = date_parts[0].get_text(strip=True)
            month = date_parts[1].get_text(strip=True)

    title_el = item.find("h5", class_=lambda c: c and "black" in str(c))
    img_el = _find_by_class_prefix(item, "img", "albumcover_cover")
    if not title_el and img_el and img_el.get("alt"):
        title = img_el["alt"]
    elif title_el:
        title = title_el.get_text(strip=True)
    else:
        return None

    if not img_el or not img_el.get("src"):
        return None

    date_str = f"{day} {month}".strip()
    return (date_str, title, _star_rating(item), img_el["src"])


def _find_by_class_prefix(parent: Any, tag: str, prefix: str) -> Any:
    return parent.find(tag, class_=re.compile(re.escape(prefix)))


def _star_rating(div: Any) -> float:
    halfstars = div.find_all(class_=re.compile(r"stars_show"))
    if halfstars:
        return len(halfstars) * 0.5
    for style in (
        "width: 7px; overflow: hidden; opacity: 1; height: 14px; z-index: 1;",
        "width: 10px; overflow: hidden; opacity: 1; height: 20px; z-index: 1;",
    ):
        halfstars = div.find_all("div", {"style": style})
        if halfstars:
            return len(halfstars) * 0.5
    return 0.0


def _history_date_to_iso(raw: str) -> str | None:
    text = (raw or "").strip()
    if not text:
        return None
    months = {
        "jan": 1,
        "january": 1,
        "feb": 2,
        "february": 2,
        "mar": 3,
        "march": 3,
        "apr": 4,
        "april": 4,
        "may": 5,
        "jun": 6,
        "june": 6,
        "jul": 7,
        "july": 7,
        "aug": 8,
        "august": 8,
        "sep": 9,
        "sept": 9,
        "september": 9,
        "oct": 10,
        "october": 10,
        "nov": 11,
        "november": 11,
        "dec": 12,
        "december": 12,
    }
    parts = text.split()
    if len(parts) < 2:
        return None
    day = int(parts[0]) if parts[0].isdigit() else None
    month = months.get(parts[1].casefold())
    if day is None or month is None:
        return None
    now = datetime.now(tz=UTC)
    return datetime(now.year, month, day, tzinfo=UTC).isoformat()
