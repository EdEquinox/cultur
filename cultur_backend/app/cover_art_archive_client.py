"""Cover Art Archive — artwork for MusicBrainz releases and release groups."""

from __future__ import annotations

import logging
import threading
import time
from typing import Any

import httpx

from .musicbrainz_client import normalize_mbid

logger = logging.getLogger(__name__)

CAA_BASE = "https://coverartarchive.org"


class CoverArtArchiveError(RuntimeError):
    pass


class CoverArtArchiveClient:
    def __init__(
        self,
        *,
        user_agent: str,
        timeout_seconds: float = 15.0,
        min_request_interval_seconds: float = 0.5,
    ) -> None:
        self._user_agent = (user_agent or "Cultur/1.0").strip()
        self._timeout = timeout_seconds
        self._min_interval = max(0.0, min_request_interval_seconds)
        self._lock = threading.Lock()
        self._last_request_at = 0.0

    def front_url_for_release(self, release_mbid: str, *, size: str = "") -> str | None:
        """Return front cover URL for a release MBID. size: '', '/medium', '/small', '/large'."""
        mbid = normalize_mbid(release_mbid)
        payload = self._get_json(f"/release/{mbid}")
        return self._pick_front_url(payload, size_suffix=size)

    def front_url_for_release_group(self, release_group_mbid: str, *, size: str = "") -> str | None:
        mbid = normalize_mbid(release_group_mbid)
        payload = self._get_json(f"/release-group/{mbid}")
        return self._pick_front_url(payload, size_suffix=size)

    def gallery_urls_for_release(self, release_mbid: str) -> list[str]:
        mbid = normalize_mbid(release_mbid)
        payload = self._get_json(f"/release/{mbid}")
        return self._all_image_urls(payload)

    def _pick_front_url(self, payload: dict[str, Any], *, size_suffix: str) -> str | None:
        images = payload.get("images")
        if not isinstance(images, list):
            return None
        suffix = size_suffix if size_suffix in {"", "/medium", "/small", "/large", "/250", "/500", "/1200"} else ""
        for image in images:
            if not isinstance(image, dict):
                continue
            if image.get("front") is not True:
                continue
            if image.get("approved") is False:
                continue
            thumbs = image.get("thumbnails")
            if suffix and isinstance(thumbs, dict):
                sized = thumbs.get(suffix.strip("/"))
                if isinstance(sized, str) and sized.strip():
                    return sized.strip()
            url = str(image.get("image") or "").strip()
            if url:
                return url
        for image in images:
            if not isinstance(image, dict):
                continue
            url = str(image.get("image") or "").strip()
            if url:
                return url
        return None

    def _all_image_urls(self, payload: dict[str, Any]) -> list[str]:
        images = payload.get("images")
        if not isinstance(images, list):
            return []
        urls: list[str] = []
        seen: set[str] = set()
        for image in images:
            if not isinstance(image, dict):
                continue
            if image.get("approved") is False:
                continue
            url = str(image.get("image") or "").strip()
            if url and url not in seen:
                seen.add(url)
                urls.append(url)
        return urls

    def _get_json(self, path: str) -> dict[str, Any]:
        with self._lock:
            elapsed = time.monotonic() - self._last_request_at
            if elapsed < self._min_interval:
                time.sleep(self._min_interval - elapsed)
            url = f"{CAA_BASE}{path}"
            headers = {
                "User-Agent": self._user_agent,
                "Accept": "application/json",
            }
            try:
                response = httpx.get(
                    url,
                    headers=headers,
                    timeout=self._timeout,
                    follow_redirects=True,
                )
            except httpx.HTTPError as exc:
                raise CoverArtArchiveError(str(exc)) from exc
            finally:
                self._last_request_at = time.monotonic()

        if response.status_code == 404:
            return {}
        if response.status_code >= 400:
            raise CoverArtArchiveError(f"Cover Art Archive HTTP {response.status_code}")
        try:
            data = response.json()
        except ValueError as exc:
            raise CoverArtArchiveError("Invalid JSON from Cover Art Archive.") from exc
        return data if isinstance(data, dict) else {}
