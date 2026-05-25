"""Fanart.tv — artist photos and artwork keyed by MusicBrainz ID."""

from __future__ import annotations

import logging
import threading
import time
from typing import Any

import httpx

from .musicbrainz_client import normalize_mbid

logger = logging.getLogger(__name__)

FANART_MUSIC_BASE = "https://webservice.fanart.tv/v3/music"

# Prefer portrait-like assets for person/artist avatars.
_IMAGE_FIELD_PRIORITY = (
    "artistthumb",
    "hdmusiclogo",
    "musiclogo",
    "artistbackground",
    "musicbanner",
)


class FanartError(RuntimeError):
    pass


class FanartClient:
    def __init__(
        self,
        *,
        api_key: str,
        client_key: str | None = None,
        timeout_seconds: float = 15.0,
        min_request_interval_seconds: float = 0.35,
    ) -> None:
        self._api_key = (api_key or "").strip()
        if not self._api_key:
            raise FanartError("Fanart.tv API key is required.")
        self._client_key = (client_key or "").strip() or None
        self._timeout = timeout_seconds
        self._min_interval = max(0.0, min_request_interval_seconds)
        self._lock = threading.Lock()
        self._last_request_at = 0.0
        self._thumb_cache: dict[str, str | None] = {}

    def artist_thumb_url(self, artist_mbid: str) -> str | None:
        """Return a portrait-friendly image URL for the artist MBID, or None."""
        mbid = normalize_mbid(artist_mbid)
        if not mbid:
            return None
        if mbid in self._thumb_cache:
            return self._thumb_cache[mbid]
        url = self._fetch_artist_image_url(mbid)
        self._thumb_cache[mbid] = url
        return url

    def _fetch_artist_image_url(self, mbid: str) -> str | None:
        params: dict[str, str] = {"api_key": self._api_key}
        if self._client_key:
            params["client_key"] = self._client_key
        try:
            payload = self._get_json(f"/{mbid}", params=params)
        except FanartError as exc:
            logger.debug("Fanart lookup failed for %s: %s", mbid, exc)
            return None
        return _pick_image_url(payload)

    def _get_json(self, path: str, *, params: dict[str, str]) -> dict[str, Any]:
        with self._lock:
            elapsed = time.monotonic() - self._last_request_at
            if elapsed < self._min_interval:
                time.sleep(self._min_interval - elapsed)
            url = f"{FANART_MUSIC_BASE}{path}"
            try:
                response = httpx.get(url, params=params, timeout=self._timeout)
            except httpx.HTTPError as exc:
                raise FanartError(str(exc)) from exc
            finally:
                self._last_request_at = time.monotonic()

        if response.status_code == 404:
            return {}
        if response.status_code == 429:
            raise FanartError("Fanart.tv rate limit exceeded.")
        if response.status_code >= 400:
            raise FanartError(f"Fanart.tv HTTP {response.status_code}")
        try:
            data = response.json()
        except ValueError as exc:
            raise FanartError("Invalid JSON from Fanart.tv.") from exc
        return data if isinstance(data, dict) else {}


def _pick_image_url(payload: dict[str, Any]) -> str | None:
    for field in _IMAGE_FIELD_PRIORITY:
        images = payload.get(field)
        if not isinstance(images, list) or not images:
            continue
        url = _best_url_from_entries(images)
        if url:
            return url
    return None


def _best_url_from_entries(entries: list[Any]) -> str | None:
    best_url: str | None = None
    best_likes = -1
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        url = str(entry.get("url") or "").strip()
        if not url:
            continue
        likes_raw = entry.get("likes")
        try:
            likes = int(str(likes_raw).strip()) if likes_raw is not None else 0
        except ValueError:
            likes = 0
        if likes > best_likes:
            best_likes = likes
            best_url = url
    return best_url
