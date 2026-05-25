"""Unified follow/favorites (music artists today; extensible to all person kinds)."""

from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy import delete, select
from sqlalchemy.orm import Session, selectinload

from ..backend_models import AppUser, Person, PersonIdentity, UserFollow
from ..config import Settings
from ..lastfm_client import LastfmError, compact_lfm_artist_storage_id
from ..musicbrainz_client import compact_mbid, normalize_mbid
from ..schemas import (
    FollowedArtistPayload,
    FollowedArtistResponse,
    FollowedArtistsListResponse,
    UserFollowListResponse,
    UserFollowPayload,
    UserFollowResponse,
)
from .music_catalog_service import (
    build_fanart_client,
    build_lastfm_client,
    invalidate_music_home_cache,
    resolve_artist_display_image_url,
)
from .person_service import upsert_person

_VALID_ENTITY_KINDS = frozenset({"person", "music_artist", "company", "publisher"})


def list_user_follows(
    db: Session,
    settings: Settings,
    *,
    username: str,
    entity_kind: str | None = None,
) -> UserFollowListResponse:
    user = _require_user(db, username)
    query = (
        select(UserFollow)
        .where(UserFollow.user_id == user.id)
        .options(selectinload(UserFollow.person).selectinload(Person.identities))
        .order_by(UserFollow.created_at.desc())
    )
    rows = db.scalars(query).all()
    items: list[UserFollowResponse] = []
    for row in rows:
        person = row.person
        if entity_kind is not None and person.entity_kind != entity_kind.strip().lower():
            continue
        items.append(_serialize_user_follow(db, settings, row))
    items.sort(key=lambda item: item.name.lower())
    return UserFollowListResponse(items=items)


def follow_user(
    db: Session,
    settings: Settings,
    *,
    payload: UserFollowPayload,
) -> UserFollowResponse:
    user = _require_user(db, payload.username)
    kind = _normalize_entity_kind(payload.entityKind)

    if kind == "music_artist" and not (payload.personId or "").strip() and (payload.externalId or "").strip():
        legacy = FollowedArtistPayload(
            username=payload.username,
            discogsArtistId=payload.externalId or "",
            name=payload.name,
            imageUrl=payload.imageUrl,
        )
        result = follow_artist(db, settings, username=payload.username, payload=legacy)
        follow_row = db.scalar(
            select(UserFollow)
            .where(UserFollow.id == result.id)
            .options(selectinload(UserFollow.person).selectinload(Person.identities)),
        )
        assert follow_row is not None
        return _serialize_user_follow(db, settings, follow_row)

    person = _resolve_or_create_person(db, settings, payload=payload, entity_kind=kind)
    existing = db.scalar(
        select(UserFollow).where(
            UserFollow.user_id == user.id,
            UserFollow.person_id == person.id,
        ),
    )
    if existing is None:
        db.add(UserFollow(user_id=user.id, person_id=person.id))
    db.commit()
    follow_row = db.scalar(
        select(UserFollow)
        .where(UserFollow.user_id == user.id, UserFollow.person_id == person.id)
        .options(selectinload(UserFollow.person).selectinload(Person.identities)),
    )
    assert follow_row is not None
    if kind == "music_artist":
        invalidate_music_home_cache(payload.username)
    return _serialize_user_follow(db, settings, follow_row)


def _looks_like_uuid(value: str) -> bool:
    text = (value or "").strip()
    return len(text) == 36 and text.count("-") >= 4


def unfollow_user(
    db: Session,
    *,
    username: str,
    person_id: str | None = None,
    external_id: str | None = None,
) -> None:
    user = _require_user(db, username)
    resolved_person_id = (person_id or "").strip()
    external_key = (external_id or "").strip()
    if resolved_person_id and not _looks_like_uuid(resolved_person_id) and not external_key:
        external_key = resolved_person_id
        resolved_person_id = ""

    if resolved_person_id and _looks_like_uuid(resolved_person_id):
        db.execute(
            delete(UserFollow).where(
                UserFollow.user_id == user.id,
                UserFollow.person_id == resolved_person_id,
            ),
        )
        db.commit()
        invalidate_music_home_cache(username)
        return

    keys = _stored_id_lookup_keys(external_key or resolved_person_id)
    if not keys:
        return
    person_ids = list(
        db.scalars(
            select(PersonIdentity.person_id).where(PersonIdentity.external_id.in_(keys)),
        ).all(),
    )
    if not person_ids:
        return
    db.execute(
        delete(UserFollow).where(
            UserFollow.user_id == user.id,
            UserFollow.person_id.in_(person_ids),
        ),
    )
    db.commit()
    invalidate_music_home_cache(username)


def list_followed_artists(
    db: Session,
    settings: Settings,
    *,
    username: str,
) -> FollowedArtistsListResponse:
    user = _require_user(db, username)
    rows = db.scalars(
        select(UserFollow)
        .where(UserFollow.user_id == user.id)
        .options(
            selectinload(UserFollow.person).selectinload(Person.identities),
        )
        .order_by(UserFollow.created_at.desc()),
    ).all()
    items: list[FollowedArtistResponse] = []
    for row in rows:
        person = row.person
        if person.entity_kind != "music_artist":
            continue
        stored = _music_storage_id(person)
        artist_mbid = normalize_mbid(stored) if stored and len(stored.replace("-", "")) == 32 else None
        image_url = (person.image_url or "").strip() or resolve_artist_display_image_url(
            db,
            artist_name=person.display_name,
            artist_mbid=artist_mbid,
            explicit=person.image_url,
            fanart=None,
        )
        items.append(
            FollowedArtistResponse(
                id=row.id,
                discogsArtistId=stored or "",
                name=person.display_name,
                imageUrl=image_url,
            ),
        )
    items.sort(key=lambda item: item.name.lower())
    return FollowedArtistsListResponse(items=items)


def follow_artist(
    db: Session,
    settings: Settings,
    *,
    username: str,
    payload: FollowedArtistPayload,
) -> FollowedArtistResponse:
    user = _require_user(db, username)
    lastfm = build_lastfm_client(settings)
    if lastfm is None:
        raise HTTPException(
            status_code=503,
            detail="Last.fm is not configured. Set LASTFM_API_KEY on the server.",
        )

    raw_id = str(payload.discogsArtistId).strip()
    name = (payload.name or "").strip()
    artist_mbid = normalize_mbid(raw_id) if raw_id else None

    try:
        artist = lastfm.fetch_artist(artist_name=name or None, artist_mbid=artist_mbid)
    except LastfmError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    name = name or artist.name
    stored_id = compact_lfm_artist_storage_id(
        artist_name=name,
        artist_mbid=artist.artist_mbid or artist_mbid,
    )
    source_code = "musicbrainz" if artist.artist_mbid or artist_mbid else "lastfm"

    person = upsert_person(
        db,
        entity_kind="music_artist",
        source_code=source_code,
        external_id=stored_id,
        display_name=name,
        image_url=payload.imageUrl,
    )

    fanart = build_fanart_client(settings)
    resolved_image = (payload.imageUrl or "").strip() or resolve_artist_display_image_url(
        db,
        artist_name=name,
        artist_mbid=artist.artist_mbid,
        explicit=payload.imageUrl,
        fanart=fanart,
    )
    if resolved_image:
        person.image_url = resolved_image

    existing = db.scalar(
        select(UserFollow).where(
            UserFollow.user_id == user.id,
            UserFollow.person_id == person.id,
        ),
    )
    if existing is not None:
        db.commit()
        db.refresh(existing)
        return FollowedArtistResponse(
            id=existing.id,
            discogsArtistId=stored_id,
            name=person.display_name,
            imageUrl=person.image_url,
        )

    row = UserFollow(user_id=user.id, person_id=person.id)
    db.add(row)
    db.commit()
    db.refresh(row)
    invalidate_music_home_cache(username)
    return FollowedArtistResponse(
        id=row.id,
        discogsArtistId=stored_id,
        name=person.display_name,
        imageUrl=person.image_url,
    )


def unfollow_artist(db: Session, *, username: str, discogs_artist_id: str) -> None:
    user = _require_user(db, username)
    keys = _stored_id_lookup_keys(discogs_artist_id)
    if not keys:
        return
    person_ids = db.scalars(
        select(PersonIdentity.person_id).where(PersonIdentity.external_id.in_(keys)),
    ).all()
    if not person_ids:
        return
    db.execute(
        delete(UserFollow).where(
            UserFollow.user_id == user.id,
            UserFollow.person_id.in_(person_ids),
        ),
    )
    db.commit()
    invalidate_music_home_cache(username)


def _music_storage_id(person: Person) -> str:
    for identity in person.identities:
        if identity.source_code in {"musicbrainz", "lastfm"}:
            return identity.external_id.strip()
    return ""


def _stored_id_lookup_keys(raw: str) -> list[str]:
    text = (raw or "").strip()
    if not text:
        return []
    keys = {text, text.replace("-", "").lower()}
    try:
        mb = normalize_mbid(text)
        keys.add(compact_mbid(mb))
    except ValueError:
        pass
    return [k for k in keys if k]


def _normalize_entity_kind(value: str) -> str:
    kind = (value or "").strip().lower()
    if kind not in _VALID_ENTITY_KINDS:
        allowed = ", ".join(sorted(_VALID_ENTITY_KINDS))
        raise HTTPException(status_code=400, detail=f"entityKind must be one of: {allowed}.")
    return kind


def _resolve_or_create_person(
    db: Session,
    settings: Settings,
    *,
    payload: UserFollowPayload,
    entity_kind: str,
) -> Person:
    person_id = (payload.personId or "").strip()
    if person_id:
        person = db.scalar(
            select(Person)
            .where(Person.id == person_id)
            .options(selectinload(Person.identities)),
        )
        if person is None:
            raise HTTPException(status_code=404, detail="Person not found.")
        if payload.name:
            person.display_name = payload.name.strip()
        if payload.imageUrl:
            person.image_url = payload.imageUrl.strip()
        return person

    source_code = (payload.sourceCode or "").strip().lower()
    external_id = (payload.externalId or "").strip()
    name = (payload.name or "").strip()
    if not source_code or not external_id or not name:
        raise HTTPException(
            status_code=400,
            detail="personId or (sourceCode, externalId, name) required.",
        )
    return upsert_person(
        db,
        entity_kind=entity_kind,
        source_code=source_code,
        external_id=external_id,
        display_name=name,
        image_url=payload.imageUrl,
    )


def _serialize_user_follow(
    db: Session,
    settings: Settings,
    row: UserFollow,
) -> UserFollowResponse:
    person = row.person
    identity = person.identities[0] if person.identities else None
    image_url = (person.image_url or "").strip()
    if person.entity_kind == "music_artist" and not image_url:
        stored = _music_storage_id(person)
        artist_mbid = normalize_mbid(stored) if stored and len(stored.replace("-", "")) == 32 else None
        image_url = resolve_artist_display_image_url(
            db,
            artist_name=person.display_name,
            artist_mbid=artist_mbid,
            explicit=person.image_url,
            fanart=None,
        )
    return UserFollowResponse(
        id=row.id,
        personId=person.id,
        entityKind=person.entity_kind,
        name=person.display_name,
        imageUrl=image_url or None,
        sourceCode=identity.source_code if identity else None,
        externalId=identity.external_id if identity else None,
    )


def _require_user(db: Session, username: str) -> AppUser:
    user = db.scalar(select(AppUser).where(AppUser.username == username.strip()))
    if user is None:
        raise HTTPException(status_code=404, detail="User not found.")
    return user
