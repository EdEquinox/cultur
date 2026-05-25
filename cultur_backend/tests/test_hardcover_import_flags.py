from app.hardcover_client import HardcoverImportSource, HardcoverLibraryBook
from app.services.hardcover_import_service import (
    _finalize_tracking_flags,
    _tracking_plan_for_targets,
    default_cultur_target,
)


def test_default_cultur_target_reading_shelf_by_slug() -> None:
    source = HardcoverImportSource(
        source_key="shelf:3",
        kind="shelf",
        name="Currently Reading",
        books_count=5,
        status_id=3,
        slug="currently-reading",
    )
    assert default_cultur_target(source) == "reading"


def test_reading_clears_watchlist_when_merged_with_want() -> None:
    plan = _tracking_plan_for_targets(
        {"later_priority", "reading"},
        hc_entry=HardcoverLibraryBook(book_id=1),
    )
    assert plan.status == "In progress"
    assert "doing" in plan.flags
    assert "watchlist" not in plan.flags
    assert "priority" in plan.flags


def test_finalize_tracking_flags_doing_removes_watchlist() -> None:
    flags = _finalize_tracking_flags({"doing", "watchlist"}, status="In progress")
    assert flags == {"doing"}
