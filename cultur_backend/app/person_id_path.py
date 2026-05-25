"""Encode/decode person ids in URL paths (Last.fm ids contain `/`)."""

from __future__ import annotations

from urllib.parse import quote, unquote

# Slashes in person ids break single-segment routes when proxies decode %2F.
_PERSON_ID_SLASH_ESCAPE = "|"


def encode_person_id_for_path(person_id: str) -> str:
    escaped = (person_id or "").strip().replace("/", _PERSON_ID_SLASH_ESCAPE)
    return quote(escaped, safe="")


def decode_person_id_from_path(segment: str) -> str:
    return unquote((segment or "").strip()).replace(_PERSON_ID_SLASH_ESCAPE, "/")
