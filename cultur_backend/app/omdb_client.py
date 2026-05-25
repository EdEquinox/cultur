from __future__ import annotations

from dataclasses import dataclass

import requests


class OmdbError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class OmdbMovie:
    subtitle: str | None
    description: str | None
    image_url: str | None
    metadata: dict[str, object]


class OmdbClient:
    def __init__(self, *, api_key: str, timeout_seconds: float = 20) -> None:
        self.api_key = api_key
        self.timeout_seconds = timeout_seconds
        self.base_url = "https://www.omdbapi.com/"

    def lookup_movie(self, *, title: str, year: str | None = None) -> OmdbMovie | None:
        response = requests.get(
            self.base_url,
            params={
                "apikey": self.api_key,
                "t": title,
                "y": year or None,
                "plot": "short",
                "type": "movie",
            },
            timeout=self.timeout_seconds,
        )
        response.raise_for_status()
        payload = response.json()
        if payload.get("Response") == "False":
            return None

        poster = str(payload.get("Poster") or "").strip()
        imdb_rating = str(payload.get("imdbRating") or "").strip()
        runtime = str(payload.get("Runtime") or "").strip()
        genre = str(payload.get("Genre") or "").strip()
        released = str(payload.get("Released") or "").strip()
        metascore = str(payload.get("Metascore") or "").strip()
        ratings_payload = payload.get("Ratings")
        rotten_tomatoes = None
        if isinstance(ratings_payload, list):
            for rating in ratings_payload:
                if not isinstance(rating, dict):
                    continue
                if str(rating.get("Source") or "").strip() == "Rotten Tomatoes":
                    candidate = str(rating.get("Value") or "").strip()
                    rotten_tomatoes = candidate or None
                    break
        subtitle_parts = [part for part in (released, f"IMDb {imdb_rating}" if imdb_rating and imdb_rating != "N/A" else None) if part]

        return OmdbMovie(
            subtitle=" • ".join(subtitle_parts) if subtitle_parts else None,
            description=str(payload.get("Plot") or "").strip() or None,
            image_url=None if not poster or poster == "N/A" else poster,
            metadata={
                "imdbRating": None if not imdb_rating or imdb_rating == "N/A" else imdb_rating,
                "runtime": None if not runtime or runtime == "N/A" else runtime,
                "genre": None if not genre or genre == "N/A" else genre,
                "released": None if not released or released == "N/A" else released,
                "imdbId": str(payload.get("imdbID") or "").strip() or None,
                "metascore": None if not metascore or metascore == "N/A" else metascore,
                "rottenTomatoes": rotten_tomatoes,
            },
        )
