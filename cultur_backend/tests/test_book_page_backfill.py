from __future__ import annotations

from pathlib import Path

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

from app.backend_models import Base, MediaItem
from app.openlibrary_client import OpenLibraryBook, OpenLibraryClient
from app.services.catalog_service import backfill_openlibrary_book_page_counts


class _FakeOlClient(OpenLibraryClient):
    def __init__(self) -> None:
        super().__init__(min_request_interval_seconds=0)

    def fetch_book_by_work_id(self, work_id: str) -> OpenLibraryBook | None:
        if work_id != "OL17625829W":
            return None
        return OpenLibraryBook(
            external_id=work_id,
            title="Empire of Storms",
            subtitle=None,
            description=None,
            image_url=None,
            metadata={"pageCount": 704, "authors": "Sarah J. Maas"},
        )


def test_backfill_openlibrary_book_page_counts(tmp_path: Path) -> None:
    db_path = tmp_path / "backfill.sqlite3"
    engine = create_engine(f"sqlite:///{db_path}")
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)

    with session_factory() as db:
        item = MediaItem(
            source="openlibrary",
            external_id="OL17625829W",
            media_type="book",
            title="Empire of Storms",
            provider_payload={"authors": "Sarah J. Maas"},
        )
        db.add(item)
        db.commit()
        item_id = item.id

    with session_factory() as db:
        item = db.scalar(select(MediaItem).where(MediaItem.id == item_id))
        assert item is not None
        updated = backfill_openlibrary_book_page_counts(
            db,
            [item],
            ol_client=_FakeOlClient(),
        )
        assert updated == 1
        db.commit()

    with session_factory() as db:
        item = db.scalar(select(MediaItem).where(MediaItem.id == item_id))
        assert item is not None
        meta = item.provider_payload if isinstance(item.provider_payload, dict) else {}
        assert meta.get("pageCount") == 704
