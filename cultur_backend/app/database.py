from __future__ import annotations

from sqlalchemy import create_engine, select
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import Settings

_CATALOG_SOURCE_SEEDS: tuple[tuple[str, str], ...] = (
    ("tmdb", "TMDB"),
    ("igdb", "IGDB"),
    ("bgg", "BoardGameGeek"),
    ("lastfm", "Last.fm"),
    ("musicbrainz", "MusicBrainz"),
    ("hardcover", "Hardcover"),
    ("openlibrary", "Open Library"),
    ("manual", "Manual"),
    ("pending", "Pending import"),
)


class Base(DeclarativeBase):
    pass


class DatabaseManager:
    def __init__(self, settings: Settings) -> None:
        settings.data_dir.mkdir(parents=True, exist_ok=True)
        connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
        self.engine = create_engine(
            settings.database_url,
            future=True,
            connect_args=connect_args,
            pool_pre_ping=True,
        )
        self.session_factory = sessionmaker(
            bind=self.engine,
            autoflush=False,
            autocommit=False,
            expire_on_commit=False,
            class_=Session,
        )

    @property
    def dialect(self) -> str:
        return self.engine.dialect.name

    def initialize(self) -> None:
        from . import backend_models  # noqa: F401
        from .backend_models import CatalogSource

        Base.metadata.create_all(self.engine)
        with self.session() as db:
            for code, label in _CATALOG_SOURCE_SEEDS:
                if db.get(CatalogSource, code) is None:
                    db.add(CatalogSource(code=code, label=label))
            db.commit()

    def session(self) -> Session:
        return self.session_factory()
