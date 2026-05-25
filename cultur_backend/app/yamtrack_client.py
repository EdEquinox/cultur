from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from urllib.parse import urljoin

import requests

from .extractors import (
    ParsedMediaRef,
    decode_media_ref,
    extract_csrf_token,
    extract_discover_sections,
    extract_home_sections,
    extract_list_summaries,
    extract_media_cards,
    extract_media_detail,
)


class YamtrackError(RuntimeError):
    """Base exception for Yamtrack integration failures."""


class YamtrackAuthExpired(YamtrackError):
    """Raised when the stored Yamtrack session is no longer valid."""


@dataclass(slots=True)
class LoginResult:
    cookies: dict[str, str]
    csrf_token: str | None


class YamtrackClient:
    def __init__(self, base_url: str, timeout_seconds: float = 20) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds

    def login(self, username: str, password: str) -> LoginResult:
        session = requests.Session()
        session.headers.update(
            {
                "Accept": "text/html,application/json",
                "User-Agent": "yamtrack-api/1.0",
            },
        )
        login_url = self._url("/accounts/login/")
        response = session.get(login_url, timeout=self.timeout_seconds)
        csrf_token = extract_csrf_token(response.text) or session.cookies.get("csrftoken")
        if not csrf_token:
            raise YamtrackError("Could not extract a CSRF token from Yamtrack.")

        post_response = session.post(
            login_url,
            data={
                "csrfmiddlewaretoken": csrf_token,
                "login": username,
                "password": password,
            },
            headers={"Referer": login_url},
            timeout=self.timeout_seconds,
            allow_redirects=True,
        )
        self._raise_for_auth(post_response, "Could not sign in to Yamtrack.")
        return LoginResult(
            cookies=requests.utils.dict_from_cookiejar(session.cookies),
            csrf_token=session.cookies.get("csrftoken") or csrf_token,
        )

    def validate_session(self, cookies: dict[str, str]) -> None:
        session = self._session(cookies)
        response = session.get(self._url("/"), timeout=self.timeout_seconds)
        self._raise_for_auth(response, "The Yamtrack session is no longer valid.")

    def fetch_dashboard(self, cookies: dict[str, str]) -> dict[str, object]:
        session = self._session(cookies)
        home = session.get(self._url("/"), timeout=self.timeout_seconds)
        self._raise_for_auth(home, "Could not fetch the Yamtrack home page.")

        active_playback = None
        playback = session.get(
            self._url("/api/active-playback/"),
            timeout=self.timeout_seconds,
        )
        if not self._is_login_page(playback):
            cards = extract_media_cards(playback.text, self.base_url, limit=1)
            if cards:
                active_playback = cards[0]

        sections = extract_home_sections(home.text, self.base_url, limit_per_row=20)
        if not sections:
            sections = [
                {
                    "title": "Progress",
                    "subtitle": "Extracted from the Yamtrack home page",
                    "items": extract_media_cards(home.text, self.base_url, limit=36),
                },
            ]

        return {
            "activePlayback": active_playback,
            "sections": sections,
        }

    def fetch_history(self, cookies: dict[str, str]) -> dict[str, object]:
        session = self._session(cookies)
        now = datetime.now()
        response = session.get(
            self._url("/history"),
            params={"year": str(now.year), "m": str(now.month)},
            timeout=self.timeout_seconds,
        )
        self._raise_for_auth(response, "Could not fetch Yamtrack history.")
        return {
            "sections": [
                {
                    "title": "Recent activity",
                    "subtitle": "Current month from Yamtrack history",
                    "items": extract_media_cards(response.text, self.base_url, limit=60),
                },
            ],
        }

    def fetch_discover(
        self,
        cookies: dict[str, str],
        *,
        media_type: str,
    ) -> dict[str, object]:
        session = self._session(cookies)
        response = session.get(
            self._url("/discover"),
            params={"media_type": media_type, "show_more": "0"},
            timeout=self.timeout_seconds,
        )
        self._raise_for_auth(response, "Could not fetch Yamtrack discover.")
        return {
            "activePlayback": None,
            "sections": extract_discover_sections(
                response.text,
                self.base_url,
                selected_media_type=media_type,
                limit_per_row=20,
            ),
        }

    def search(
        self,
        cookies: dict[str, str],
        *,
        query: str,
        media_type: str,
    ) -> dict[str, object]:
        session = self._session(cookies)
        response = session.get(
            self._url("/search"),
            params={
                "q": query,
                "media_type": media_type,
                "page": "1",
                "layout": "grid",
            },
            timeout=self.timeout_seconds,
        )
        self._raise_for_auth(response, "Could not search Yamtrack.")
        items = extract_media_cards(response.text, self.base_url, limit=80)
        return {
            "items": items,
            "emptyMessage": None
            if items
            else "No search cards were detected in the Yamtrack response.",
        }

    def fetch_lists(self, cookies: dict[str, str]) -> dict[str, object]:
        session = self._session(cookies)
        response = session.get(self._url("/lists"), timeout=self.timeout_seconds)
        self._raise_for_auth(response, "Could not fetch Yamtrack lists.")
        return {"items": extract_list_summaries(response.text, self.base_url)}

    def fetch_media_detail(
        self,
        cookies: dict[str, str],
        *,
        media_ref: str,
    ) -> dict[str, object]:
        path = decode_media_ref(media_ref)
        session = self._session(cookies)
        response = session.get(self._url(path), timeout=self.timeout_seconds)
        self._raise_for_auth(response, "Could not fetch the Yamtrack detail page.")
        return extract_media_detail(response.text, self.base_url, path=path)

    def update_progress(
        self,
        cookies: dict[str, str],
        *,
        csrf_token: str | None,
        media_ref: str,
        status: str,
        progress: int | None,
        score: float | None,
    ) -> LoginResult:
        path = decode_media_ref(media_ref)
        parsed_ref = ParsedMediaRef.try_parse(path)
        if parsed_ref is None:
            raise YamtrackError(
                "The current API can only save progress for /details/... media routes.",
            )

        session = self._session(cookies)
        token = csrf_token or session.cookies.get("csrftoken")
        if not token:
            detail_page = session.get(self._url(path), timeout=self.timeout_seconds)
            self._raise_for_auth(detail_page, "Could not load media details before saving.")
            token = extract_csrf_token(detail_page.text) or session.cookies.get("csrftoken")

        response = session.post(
            self._url("/media_save"),
            data={
                "csrfmiddlewaretoken": token or "",
                "media_id": parsed_ref.media_id,
                "source": parsed_ref.source,
                "media_type": parsed_ref.media_type,
                "status": status,
                **({"progress": str(progress)} if progress is not None else {}),
                **({"score": str(score)} if score is not None else {}),
            },
            headers={"Referer": self._url(path)},
            timeout=self.timeout_seconds,
            allow_redirects=True,
        )
        self._raise_for_auth(response, "Yamtrack rejected the progress update.")
        return LoginResult(
            cookies=requests.utils.dict_from_cookiejar(session.cookies),
            csrf_token=session.cookies.get("csrftoken") or token,
        )

    def run_watch_action(
        self,
        cookies: dict[str, str],
        *,
        csrf_token: str | None,
        media_ref: str,
        action: str,
    ) -> LoginResult:
        if action == "mark_completed":
            return self.update_progress(
                cookies,
                csrf_token=csrf_token,
                media_ref=media_ref,
                status="Completed",
                progress=None,
                score=None,
            )
        raise YamtrackError(f"Unsupported watch action: {action}")

    def _session(self, cookies: dict[str, str]) -> requests.Session:
        session = requests.Session()
        session.headers.update(
            {
                "Accept": "text/html,application/json",
                "User-Agent": "yamtrack-api/1.0",
            },
        )
        session.cookies.update(cookies)
        return session

    def _url(self, path: str) -> str:
        return urljoin(f"{self.base_url}/", path.lstrip("/"))

    def _raise_for_auth(self, response: requests.Response, fallback_message: str) -> None:
        if self._is_login_page(response):
            raise YamtrackAuthExpired(
                "Your Yamtrack session expired and needs to be renewed.",
            )
        response.raise_for_status()
        if "Please enter a correct username and password" in response.text:
            raise YamtrackError("Invalid Yamtrack username or password.")
        if "csrf" in response.text.lower() and response.status_code >= 400:
            raise YamtrackError("The Yamtrack request failed because of CSRF validation.")
        if response.status_code >= 400:
            raise YamtrackError(fallback_message)

    def _is_login_page(self, response: requests.Response) -> bool:
        return "/accounts/login" in str(response.url)
