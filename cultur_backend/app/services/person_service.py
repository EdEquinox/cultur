"""Resolve or create person rows for unified user_follow."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..backend_models import CatalogSource, Person, PersonIdentity


def _ensure_catalog_source(db: Session, code: str) -> None:
    if db.get(CatalogSource, code) is None:
        db.add(CatalogSource(code=code, label=code))
        db.flush()


def upsert_person(
    db: Session,
    *,
    entity_kind: str,
    source_code: str,
    external_id: str,
    display_name: str,
    image_url: str | None = None,
) -> Person:
    ext = external_id.strip()
    name = display_name.strip()
    if not ext or not name:
        raise ValueError("external_id and display_name are required")

    _ensure_catalog_source(db, source_code)

    identity = db.scalar(
        select(PersonIdentity).where(
            PersonIdentity.source_code == source_code,
            PersonIdentity.external_id == ext,
        ),
    )
    if identity is not None:
        person = identity.person
        person.display_name = name
        if image_url:
            person.image_url = image_url.strip()
        person.entity_kind = entity_kind
        return person

    person = Person(
        entity_kind=entity_kind,
        display_name=name,
        image_url=image_url.strip() if image_url else None,
    )
    db.add(person)
    db.flush()
    db.add(
        PersonIdentity(
            person_id=person.id,
            source_code=source_code,
            external_id=ext,
        ),
    )
    return person
