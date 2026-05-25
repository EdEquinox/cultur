from __future__ import annotations

import logging
import re
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from html import unescape
from urllib.parse import urlencode

import requests

logger = logging.getLogger(__name__)

BGG_API_BASE = "https://boardgamegeek.com/xmlapi2"
_MAX_THING_IDS_PER_REQUEST = 20
_COLLECTION_POLL_ATTEMPTS = 12
_COLLECTION_POLL_SLEEP_SECONDS = 2.0
_REQUEST_RETRIES = 3
_RETRYABLE_STATUS = {429, 500, 502, 503, 504}
_USER_AGENT = "Cultur/1.0 (+https://github.com)"


class BggError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class BggBoardgame:
    external_id: str
    title: str
    subtitle: str | None
    description: str | None
    image_url: str | None
    metadata: dict[str, object] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class BggCollectionRow:
    external_id: str
    title: str
    flags: frozenset[str]
    bgg_rating: float | None = None


# BGG returns an empty collection when some combined filters match nothing (e.g. own=1
# with zero owned games cancels wishlist). Fetch each slice separately and merge.
_COLLECTION_FILTER_SLICES: tuple[tuple[str, str], ...] = (
    ("wishlist", "1"),
    ("own", "1"),
    ("wanttoplay", "1"),
    ("wanttobuy", "1"),
    ("rated", "1"),
)


def _pick_collection_rating(
    left: float | None,
    right: float | None,
) -> float | None:
    if left is None:
        return right
    if right is None:
        return left
    return max(left, right)


def _merge_collection_row(
    merged: dict[str, BggCollectionRow],
    row: BggCollectionRow,
) -> None:
    existing = merged.get(row.external_id)
    if existing is None:
        merged[row.external_id] = row
        return
    merged[row.external_id] = BggCollectionRow(
        external_id=row.external_id,
        title=existing.title or row.title,
        flags=existing.flags | row.flags,
        bgg_rating=_pick_collection_rating(existing.bgg_rating, row.bgg_rating),
    )


class BggClient:
    """Minimal BoardGameGeek XML API2 client (Bearer token required since 2025)."""

    def __init__(
        self,
        *,
        api_token: str,
        base_url: str = BGG_API_BASE,
        timeout_seconds: float = 25.0,
        min_request_interval_seconds: float = 2.0,
        hot_cache_ttl_seconds: int = 3600,
    ) -> None:
        token = api_token.strip()
        if not token:
            raise BggError(
                "BGG API token is required. Register an app at "
                "https://boardgamegeek.com/applications and set BGG_API_TOKEN.",
            )
        self.api_token = token
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.min_request_interval_seconds = max(0.5, min_request_interval_seconds)
        self.hot_cache_ttl_seconds = max(60, hot_cache_ttl_seconds)
        self._last_request_at = 0.0
        self._hot_cache: tuple[float, list[BggBoardgame]] | None = None

    def fetch_hot_boardgames(self, *, limit: int = 48) -> list[BggBoardgame]:
        now = time.monotonic()
        if self._hot_cache is not None:
            cached_at, cached_rows = self._hot_cache
            if now - cached_at < self.hot_cache_ttl_seconds:
                return cached_rows[:limit]

        root = self._get("hot", {"type": "boardgame"})
        games: list[BggBoardgame] = []
        for item in root.findall("item"):
            try:
                games.append(_boardgame_from_hot_item(item))
            except BggError:
                continue
            if len(games) >= limit:
                break

        if not games:
            raise BggError("BGG hot list returned no board games.")

        self._hot_cache = (now, games)
        return games[:limit]

    def search_boardgames(self, query: str, *, limit: int = 24) -> list[BggBoardgame]:
        safe_query = query.strip()
        if not safe_query:
            return []
        root = self._get(
            "search",
            {
                "query": safe_query,
                "type": "boardgame",
                "exact": "0",
            },
        )
        games: list[BggBoardgame] = []
        for item in root.findall("item"):
            try:
                games.append(_boardgame_from_search_item(item))
            except BggError:
                continue
            if len(games) >= limit:
                break
        if not games:
            return []
        return self._enrich_with_images(games)

    def fetch_boardgames_by_ids(self, ids: list[str]) -> list[BggBoardgame]:
        normalized = [value for value in dict.fromkeys(value.strip() for value in ids if value.strip().isdigit())]
        if not normalized:
            return []
        merged: list[BggBoardgame] = []
        for offset in range(0, len(normalized), _MAX_THING_IDS_PER_REQUEST):
            batch = normalized[offset : offset + _MAX_THING_IDS_PER_REQUEST]
            root = self._get("thing", {"id": ",".join(batch), "stats": "1"})
            for item in root.findall("item"):
                try:
                    merged.append(_boardgame_from_thing(item))
                except BggError:
                    continue
        return merged

    def fetch_boardgame_by_id(self, external_id: str) -> BggBoardgame | None:
        safe_id = external_id.strip()
        if not safe_id.isdigit():
            return None
        rows = self.fetch_boardgames_by_ids([safe_id])
        return rows[0] if rows else None

    def fetch_user_collection(self, username: str) -> list[BggCollectionRow]:
        safe_username = username.strip()
        if not safe_username:
            raise BggError("BGG username is required.")
        merged: dict[str, BggCollectionRow] = {}
        for filter_key, filter_value in _COLLECTION_FILTER_SLICES:
            root = self._get_collection(
                {
                    "username": safe_username,
                    "stats": "1",
                    filter_key: filter_value,
                },
            )
            for item in root.findall("item"):
                parsed = _collection_row_from_item(item)
                if parsed is not None:
                    _merge_collection_row(merged, parsed)
        return list(merged.values())

    def _enrich_with_images(self, games: list[BggBoardgame]) -> list[BggBoardgame]:
        missing_ids = [game.external_id for game in games if not game.image_url]
        if not missing_ids:
            return games
        details_by_id = {row.external_id: row for row in self.fetch_boardgames_by_ids(missing_ids)}
        return [
            details_by_id.get(game.external_id, game)
            if not game.image_url
            else game
            for game in games
        ]

    def _get_collection(self, params: dict[str, str]) -> ET.Element:
        for attempt in range(_COLLECTION_POLL_ATTEMPTS):
            response = self._request("collection", params)
            if response.status_code == 202:
                time.sleep(_COLLECTION_POLL_SLEEP_SECONDS)
                continue
            if response.status_code >= 400:
                raise _http_error("collection", response)
            return _parse_xml(response.text)
        raise BggError("BGG collection is still processing. Try again in a minute.")

    def _get(self, path: str, params: dict[str, str | int]) -> ET.Element:
        response = self._request(path, params)
        if response.status_code >= 400:
            raise _http_error(path, response)
        return _parse_xml(response.text)

    def _request(self, path: str, params: dict[str, str | int]) -> requests.Response:
        query = urlencode({key: str(value) for key, value in params.items()})
        url = f"{self.base_url}/{path.strip('/')}"
        if query:
            url = f"{url}?{query}"
        headers = {
            "Authorization": f"Bearer {self.api_token}",
            "User-Agent": _USER_AGENT,
            "Accept": "application/xml,text/xml,*/*",
        }
        last_response: requests.Response | None = None
        for attempt in range(_REQUEST_RETRIES):
            self._throttle()
            try:
                response = requests.get(url, headers=headers, timeout=self.timeout_seconds)
            except requests.RequestException as exc:
                if attempt + 1 >= _REQUEST_RETRIES:
                    raise BggError(f"BGG request failed: {exc}") from exc
                time.sleep(1.5 * (attempt + 1))
                continue
            last_response = response
            if response.status_code in _RETRYABLE_STATUS and attempt + 1 < _REQUEST_RETRIES:
                time.sleep(2.0 * (attempt + 1))
                continue
            return response
        assert last_response is not None
        return last_response

    def _throttle(self) -> None:
        now = time.monotonic()
        elapsed = now - self._last_request_at
        if elapsed < self.min_request_interval_seconds:
            time.sleep(self.min_request_interval_seconds - elapsed)
        self._last_request_at = time.monotonic()


def _http_error(path: str, response: requests.Response) -> BggError:
    snippet = (response.text or "").strip()[:240]
    if response.status_code == 401:
        return BggError(
            "BGG rejected the API token (401). Register at https://boardgamegeek.com/applications "
            "and set BGG_API_TOKEN on the server.",
        )
    return BggError(f"BGG {path} failed ({response.status_code}): {snippet or response.reason}")


def _parse_xml(payload: str) -> ET.Element:
    try:
        return ET.fromstring(payload)
    except ET.ParseError as exc:
        raise BggError("BGG returned invalid XML.") from exc


def _name_value(item: ET.Element) -> str:
    name_el = item.find("name")
    if name_el is not None:
        value = (name_el.get("value") or name_el.text or "").strip()
        if value:
            return value
    for name in item.findall("name"):
        value = (name.get("value") or name.text or "").strip()
        if value:
            return value
    return ""


def _year_value(item: ET.Element) -> str:
    year_el = item.find("yearpublished")
    return ((year_el.get("value") if year_el is not None else None) or "").strip()


def _image_value(item: ET.Element) -> str | None:
    return _text_content(item.find("thumbnail")) or _text_content(item.find("image"))


def _boardgame_stub(
    *,
    external_id: str,
    title: str,
    year: str,
    image_url: str | None,
    rank: str | None = None,
) -> BggBoardgame:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    metadata: dict[str, object] = {
        "bggId": external_id,
        "slug": slug,
        "yearPublished": year,
        "bggUrl": f"https://boardgamegeek.com/boardgame/{external_id}",
    }
    if rank:
        metadata["bggRank"] = rank
    return BggBoardgame(
        external_id=external_id,
        title=title,
        subtitle=year or None,
        description=None,
        image_url=image_url,
        metadata=metadata,
    )


def _boardgame_from_hot_item(item: ET.Element) -> BggBoardgame:
    external_id = (item.get("id") or "").strip()
    title = _name_value(item)
    if not external_id.isdigit() or not title:
        raise BggError("BGG hot row missing id or title.")
    rank = (item.get("rank") or "").strip() or None
    return _boardgame_stub(
        external_id=external_id,
        title=title,
        year=_year_value(item),
        image_url=_image_value(item),
        rank=rank,
    )


def _boardgame_from_search_item(item: ET.Element) -> BggBoardgame:
    external_id = (item.get("id") or "").strip()
    title = _name_value(item)
    if not external_id.isdigit() or not title:
        raise BggError("BGG search row missing id or title.")
    return _boardgame_stub(
        external_id=external_id,
        title=title,
        year=_year_value(item),
        image_url=_image_value(item),
    )


def _primary_name(item: ET.Element) -> str:
    for name in item.findall("name"):
        if name.get("type") == "primary":
            value = (name.get("value") or "").strip()
            if value:
                return value
    for name in item.findall("name"):
        value = (name.get("value") or "").strip()
        if value:
            return value
    return ""


def _text_content(element: ET.Element | None) -> str | None:
    if element is None:
        return None
    raw = "".join(element.itertext()).strip()
    if not raw:
        return None
    plain = unescape(re.sub(r"<[^>]+>", " ", raw))
    plain = re.sub(r"\s+", " ", plain).strip()
    return plain or None


def _boardgame_from_thing(item: ET.Element) -> BggBoardgame:
    external_id = (item.get("id") or "").strip()
    title = _primary_name(item)
    if not external_id.isdigit() or not title:
        raise BggError("BGG thing row missing id or title.")
    year = _year_value(item)
    image = _image_value(item)
    description = _text_content(item.find("description"))
    ratings = item.find("statistics/ratings")
    average = (ratings.find("average").get("value") if ratings is not None else None) or ""
    bayes = (ratings.find("bayesaverage").get("value") if ratings is not None else None) or ""
    rank_value = ""
    if ratings is not None:
        for rank in ratings.findall("ranks/rank"):
            if rank.get("type") == "subtype" and rank.get("name") == "boardgame":
                rank_value = (rank.get("value") or "").strip()
                break
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    metadata: dict[str, object] = {
        "bggId": external_id,
        "slug": slug,
        "yearPublished": year,
        "bggAverage": average,
        "bggBayesAverage": bayes,
        "bggRank": rank_value,
        "bggUrl": f"https://boardgamegeek.com/boardgame/{external_id}",
    }
    return BggBoardgame(
        external_id=external_id,
        title=title,
        subtitle=year or None,
        description=description,
        image_url=image,
        metadata=metadata,
    )


def _truthy(value: str | None) -> bool:
    return (value or "").strip() == "1"


def _collection_row_from_item(item: ET.Element) -> BggCollectionRow | None:
    external_id = (item.get("objectid") or item.get("id") or "").strip()
    name_el = item.find("name")
    title = (name_el.text or "").strip() if name_el is not None else ""
    if not external_id.isdigit() or not title:
        return None
    status = item.find("status")
    flags: set[str] = set()
    if status is not None:
        if _truthy(status.get("wishlist")) or _truthy(status.get("want")):
            flags.add("watchlist")
        if _truthy(status.get("wanttoplay")):
            flags.add("watchlist")
        if _truthy(status.get("wanttobuy")):
            flags.add("buy")
        if _truthy(status.get("own")):
            flags.add("collected")
        wishlist_priority = (status.get("wishlistpriority") or "").strip()
        if wishlist_priority.isdigit() and int(wishlist_priority) > 0:
            flags.add("priority")
    stats = item.find("stats")
    rating: float | None = None
    if stats is not None:
        rating_raw = (stats.get("rating") or "").strip()
        try:
            parsed = float(rating_raw) if rating_raw else None
            if parsed is not None and parsed > 0:
                rating = parsed
        except ValueError:
            rating = None
    if not flags and rating is None:
        return None
    return BggCollectionRow(
        external_id=external_id,
        title=title,
        flags=frozenset(flags),
        bgg_rating=rating,
    )


def build_tracking_notes(flags: frozenset[str]) -> str | None:
    if not flags:
        return None
    ordered = sorted(flags)
    return f"[cult.flags]{','.join(ordered)}"
