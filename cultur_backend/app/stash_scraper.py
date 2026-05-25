"""Scrape public Stash.games profile pages (ported from stash-extract/extract_data_stash.py)."""

from __future__ import annotations

import logging
import os
import re
import time
from pathlib import Path
from dataclasses import dataclass
from typing import Any
from urllib.parse import urljoin

from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)

STASH_BASE_URL = "https://stash.games"

# Collection path suffixes are per Stash account (slug after /collections/).
# Override via STASH_COLLECTION_PATHS env JSON: [{"key":"prioridades","path":"collections/..."}]
DEFAULT_STASH_COLLECTION_PATHS: tuple[tuple[str, str], ...] = (
    ("prioridades", "collections/prioridade-enxns"),
    ("abandonados", "collections/abandonados-fhbry"),
    ("gaveta", "collections/na-gaveta-foetp"),
    ("fisical", "collections/colecao-fisica-qvwoj"),
    ("non_fisical", "collections/colecao-nao-fisica-xegql"),
)

_LIBRARY_TAB_SPECS: tuple[tuple[str, str, str], ...] = (
    ("stashGames.csv", "Want", ""),
    ("stashPlaying.csv", "Playing", "playing-tab"),  # element id, not raw xpath
    ("stashBeaten.csv", "Beaten", '//*[@id="profileTab"]/li[3]'),
    ("stashArchived.csv", "Archived", '//*[@id="profileTab"]/li[4]'),
)


class StashScrapeError(RuntimeError):
    pass


@dataclass(slots=True)
class StashCollectionPath:
    key: str
    path: str


@dataclass(slots=True)
class StashScrapedRow:
    source_file: str
    title: str
    image_url: str | None = None
    category: str | None = None
    rating: float | None = None
    review: str | None = None


def scrape_stash_profile(
    stash_username: str,
    *,
    collection_paths: list[StashCollectionPath] | None = None,
    include_reviews: bool = True,
    include_library_tabs: bool = True,
    scroll_pause_seconds: float = 2.0,
    page_load_seconds: float = 5.0,
) -> list[StashScrapedRow]:
    """Scrape games from a public Stash.games user profile."""
    handle = (stash_username or "").strip().lstrip("@")
    if not handle:
        raise StashScrapeError("stash username is required.")

    paths = collection_paths if collection_paths else [
        StashCollectionPath(key=key, path=path) for key, path in DEFAULT_STASH_COLLECTION_PATHS
    ]

    rows: list[StashScrapedRow] = []
    driver = _create_driver()
    try:
        if paths:
            logger.info("Stash scrape: %d collection(s) for @%s", len(paths), handle)
            for spec in paths:
                url = _user_url(handle, spec.path)
                html = _scroll_page_html(
                    driver,
                    url,
                    scroll_pause_seconds=scroll_pause_seconds,
                    page_load_seconds=page_load_seconds,
                )
                parsed = _parse_collection_page(html, collection_key=spec.key)
                logger.info("Stash scrape: %s → %d games", spec.key, len(parsed))
                rows.extend(parsed)

        if include_reviews:
            url = _user_url(handle, "reviews")
            html = _scroll_page_html(
                driver,
                url,
                scroll_pause_seconds=scroll_pause_seconds,
                page_load_seconds=page_load_seconds,
            )
            parsed = _parse_reviews_page(html)
            logger.info("Stash scrape: reviews → %d", len(parsed))
            rows.extend(parsed)

        if include_library_tabs:
            games_url = _user_url(handle, "games")
            for source_file, category, tab_selector in _LIBRARY_TAB_SPECS:
                try:
                    html = _scrape_library_tab_html(
                        driver,
                        games_url=games_url,
                        tab_selector=tab_selector,
                        scroll_pause_seconds=scroll_pause_seconds,
                        page_load_seconds=page_load_seconds,
                    )
                except StashScrapeError as exc:
                    logger.warning("Stash scrape: skipped %s (%s)", source_file, exc)
                    continue
                parsed = _parse_library_tab(html, source_file=source_file, category=category)
                logger.info("Stash scrape: %s → %d games", source_file, len(parsed))
                rows.extend(parsed)
    finally:
        driver.quit()

    return rows


def _user_url(handle: str, suffix: str) -> str:
    cleaned = suffix.strip().lstrip("/")
    return f"{STASH_BASE_URL}/users/{handle}/{cleaned}"


def _create_driver() -> Any:
    try:
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
    except ImportError as exc:
        raise StashScrapeError(
            "Selenium is not installed. Install selenium and Chromium/Chrome for Stash profile import.",
        ) from exc

    options = Options()
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1920,1080")
    chrome_bin = os.environ.get("CHROME_BIN", "").strip()
    candidates = [
        chrome_bin,
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            options.binary_location = candidate
            break
    try:
        return webdriver.Chrome(options=options)
    except Exception as exc:
        raise StashScrapeError(
            "Could not start Chrome/Chromium for Stash scrape. "
            "Install chromium and chromedriver (or google-chrome) on the server.",
        ) from exc


def _scroll_page_html(
    driver: Any,
    url: str,
    *,
    scroll_pause_seconds: float,
    page_load_seconds: float,
) -> str:
    from selenium.webdriver.common.by import By
    from selenium.webdriver.common.keys import Keys

    driver.get(url)
    time.sleep(page_load_seconds)
    last_height = driver.execute_script("return document.body.scrollHeight")
    while True:
        driver.find_element(By.TAG_NAME, "body").send_keys(Keys.END)
        time.sleep(scroll_pause_seconds)
        new_height = driver.execute_script("return document.body.scrollHeight")
        if new_height == last_height:
            break
        last_height = new_height
    return driver.page_source


def _click_library_tab(driver: Any, tab_selector: str) -> None:
    from selenium.common.exceptions import NoSuchElementException
    from selenium.webdriver.common.by import By

    if not tab_selector:
        return

    attempts: list[tuple[str, str]] = []
    if tab_selector.startswith("/") or tab_selector.startswith("("):
        attempts.append((By.XPATH, tab_selector))
    else:
        attempts.extend(
            [
                (By.ID, tab_selector),
                (By.XPATH, f'//*[@id="{tab_selector}"]'),
                (By.CSS_SELECTOR, f"#{tab_selector}"),
            ],
        )

    last_error: Exception | None = None
    for by, value in attempts:
        try:
            tab = driver.find_element(by, value)
            tab.click()
            return
        except NoSuchElementException as exc:
            last_error = exc
            continue

    raise StashScrapeError(
        f'Could not find Stash library tab "{tab_selector}"',
    ) from last_error


def _scrape_library_tab_html(
    driver: Any,
    *,
    games_url: str,
    tab_selector: str,
    scroll_pause_seconds: float,
    page_load_seconds: float,
) -> str:
    from selenium.webdriver.common.by import By
    from selenium.webdriver.common.keys import Keys

    driver.get(games_url)
    time.sleep(page_load_seconds)
    if tab_selector:
        _click_library_tab(driver, tab_selector)
        time.sleep(scroll_pause_seconds)
    last_height = driver.execute_script("return document.body.scrollHeight")
    while True:
        driver.find_element(By.TAG_NAME, "body").send_keys(Keys.END)
        time.sleep(scroll_pause_seconds)
        new_height = driver.execute_script("return document.body.scrollHeight")
        if new_height == last_height:
            break
        last_height = new_height
    return driver.page_source


def _parse_collection_page(html: str, *, collection_key: str) -> list[StashScrapedRow]:
    soup = BeautifulSoup(html, "html.parser")
    source_file = f"stash{collection_key}.csv"
    rows: list[StashScrapedRow] = []
    for div in soup.find_all("div", class_="games-list__item"):
        title, image_url = _extract_list_item(div)
        if title:
            rows.append(
                StashScrapedRow(
                    source_file=source_file,
                    title=title,
                    image_url=image_url,
                ),
            )
    return rows


def _parse_reviews_page(html: str) -> list[StashScrapedRow]:
    soup = BeautifulSoup(html, "html.parser")
    rows: list[StashScrapedRow] = []
    for div in soup.find_all("div", class_="recent-review"):
        if "p-0" not in (div.get("class") or []):
            continue
        img = div.find("img", class_="recent-review__image")
        image_url = _image_src(img)
        title_node = div.find("div", class_="font-semibold")
        title = title_node.get_text(strip=True) if title_node else None
        rating_raw = div.find("span", class_="game__review-rating")
        rating = _parse_rating(rating_raw.get_text(strip=True) if rating_raw else None)
        review_node = div.find("p", class_="review-text")
        review = review_node.get_text(strip=True) if review_node else None
        if title:
            rows.append(
                StashScrapedRow(
                    source_file="stashReviews.csv",
                    title=title,
                    image_url=image_url,
                    rating=rating,
                    review=review,
                ),
            )
    return rows


def _parse_library_tab(html: str, *, source_file: str, category: str) -> list[StashScrapedRow]:
    soup = BeautifulSoup(html, "html.parser")
    rows: list[StashScrapedRow] = []
    if source_file == "stashGames.csv":
        panel = soup.find("div", class_="tab-panel")
        divs = panel.find_all("div", class_="games-list__item") if panel else []
    else:
        panels = soup.find_all("div", class_="tab-panel")
        divs = []
        if len(panels) > 1:
            divs = panels[1].find_all("div", class_="games-list__item")
    for div in divs:
        title, image_url = _extract_list_item(div, use_span_name=source_file == "stashGames.csv")
        if title:
            rows.append(
                StashScrapedRow(
                    source_file=source_file,
                    title=title,
                    image_url=image_url,
                    category=category,
                ),
            )
    return rows


def _extract_list_item(div: Any, *, use_span_name: bool = False) -> tuple[str | None, str | None]:
    img = div.find("img", class_="games-list__item-image")
    image_url = _image_src(img)
    if use_span_name:
        title_node = div.find("span", class_="games-list__item-name")
    else:
        title_node = div.find("h3", class_="games-list__item-name") or div.find(
            "span",
            class_="games-list__item-name",
        )
    title = title_node.get_text(strip=True) if title_node else None
    return title, image_url


def _image_src(img: Any) -> str | None:
    if img is None:
        return None
    for attr in ("data-src", "src"):
        raw = img.get(attr)
        if isinstance(raw, str) and raw.strip():
            text = raw.strip()
            if text.startswith("//"):
                return f"https:{text}"
            if text.startswith("/"):
                return urljoin(STASH_BASE_URL, text)
            return text
    return None


def _parse_rating(raw: str | None) -> float | None:
    if not raw:
        return None
    match = re.search(r"(\d+(?:\.\d+)?)", raw.replace(",", "."))
    if not match:
        return None
    try:
        value = float(match.group(1))
    except ValueError:
        return None
    if value <= 0:
        return None
    if value > 10:
        return value / 10.0
    return value


def parse_collection_paths_json(raw: str) -> list[StashCollectionPath]:
    import json

    text = (raw or "").strip()
    if not text:
        return [StashCollectionPath(key=k, path=p) for k, p in DEFAULT_STASH_COLLECTION_PATHS]
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise StashScrapeError(f"Invalid STASH_COLLECTION_PATHS JSON: {exc}") from exc
    if not isinstance(payload, list):
        raise StashScrapeError("STASH_COLLECTION_PATHS must be a JSON array.")
    out: list[StashCollectionPath] = []
    for row in payload:
        if not isinstance(row, dict):
            continue
        key = str(row.get("key") or "").strip()
        path = str(row.get("path") or "").strip().lstrip("/")
        if key and path:
            out.append(StashCollectionPath(key=key, path=path))
    if not out:
        raise StashScrapeError("STASH_COLLECTION_PATHS is empty.")
    return out
