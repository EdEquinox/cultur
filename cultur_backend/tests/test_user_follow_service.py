from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

from app.backend_models import AppUser, Base, Person, UserFollow
from app.schemas import UserFollowPayload
from app.services import user_follow_service


@pytest.fixture()
def db_session() -> Session:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    try:
        yield session
    finally:
        session.close()


def test_follow_user_by_identity(db_session: Session) -> None:
    db_session.add(AppUser(username="alice"))
    db_session.commit()
    settings = MagicMock()

    result = user_follow_service.follow_user(
        db_session,
        settings,
        payload=UserFollowPayload(
            username="alice",
            entityKind="person",
            sourceCode="tmdb",
            externalId="6384",
            name="Tom Hanks",
        ),
    )
    assert result.entityKind == "person"
    assert result.externalId == "6384"

    listed = user_follow_service.list_user_follows(
        db_session,
        settings,
        username="alice",
        entity_kind="person",
    )
    assert len(listed.items) == 1

    user_follow_service.unfollow_user(
        db_session,
        username="alice",
        person_id=result.personId,
    )
    assert db_session.scalar(select(UserFollow).where(UserFollow.id == result.id)) is None
