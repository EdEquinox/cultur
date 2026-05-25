"""Shared title/author matching for catalog import lookups."""

from __future__ import annotations

import re

from .openlibrary_client import OpenLibraryBook


def build_title_author_query(title: str, authors: str | None = None) -> str:
    text = (title or "").strip()
    if not text:
        return ""
    primary = primary_author_name(authors)
    if primary:
        return f"{text} {primary}"
    return text


def primary_author_name(authors: str | None) -> str | None:
    raw = (authors or "").strip()
    if not raw:
        return None
    first = raw.split(",")[0].strip()
    return first or None


def pick_best_catalog_match(
    books: list[OpenLibraryBook],
    *,
    title: str,
    authors: str | None = None,
    min_score: float = 0.45,
) -> OpenLibraryBook | None:
    if not books:
        return None
    scored = sorted(
        books,
        key=lambda book: catalog_match_score(book, title=title, authors=authors),
        reverse=True,
    )
    best = scored[0]
    if catalog_match_score(best, title=title, authors=authors) < min_score:
        return None
    return best


def catalog_match_score(
    book: OpenLibraryBook,
    *,
    title: str,
    authors: str | None = None,
) -> float:
    title_score = title_similarity(book.title, title)
    author_score = author_similarity(
        authors,
        book.metadata.get("authors") if isinstance(book.metadata.get("authors"), str) else None,
    )
    if authors and author_score <= 0:
        return title_score * 0.85
    if authors:
        return title_score * 0.72 + author_score * 0.28
    return title_score


def author_similarity(wanted: str | None, candidate: str | None) -> float:
    primary = primary_author_name(wanted)
    if not primary:
        return 1.0
    cand = (candidate or "").strip()
    if not cand:
        return 0.0
    primary_norm = _normalize_person_name(primary)
    for part in re.split(r"[,;&]", cand):
        part_norm = _normalize_person_name(part)
        if not part_norm:
            continue
        if primary_norm == part_norm:
            return 1.0
        if primary_norm in part_norm or part_norm in primary_norm:
            return 0.9
        pw = set(primary_norm.split())
        cw = set(part_norm.split())
        if pw and cw:
            overlap = len(pw & cw) / max(len(pw), len(cw))
            if overlap >= 0.5:
                return max(0.55, overlap)
    return 0.0


def title_similarity(a: str, b: str) -> float:
    na = normalize_title(a)
    nb = normalize_title(b)
    if not na or not nb:
        return 0.0
    if na == nb:
        return 1.0
    if na in nb or nb in na:
        return 0.85
    aw = set(na.split())
    bw = set(nb.split())
    if not aw or not bw:
        return 0.0
    return len(aw & bw) / max(len(aw), len(bw))


def normalize_title(value: str) -> str:
    t = value.casefold()
    t = re.sub(r"\([^)]*\)", "", t)
    t = re.sub(r"[^a-z0-9\s]", " ", t)
    return " ".join(t.split())


def _normalize_person_name(value: str) -> str:
    t = value.casefold()
    t = re.sub(r"[^a-z\s]", " ", t)
    parts = [p for p in t.split() if p and p not in {"de", "da", "do", "dos", "das", "van", "von"}]
    if len(parts) >= 2:
        return " ".join(parts[:2])
    return " ".join(parts)
