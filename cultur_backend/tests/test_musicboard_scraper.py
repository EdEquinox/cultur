from __future__ import annotations

from app.musicboard_scraper import (
    MusicboardImportSource,
    MusicboardListPath,
    _list_path_from_href,
    extract_list_sources_from_html,
    merge_musicboard_sources,
    optional_configured_list_paths,
    sources_from_list_paths,
)


def test_list_path_from_href_accepts_profile_and_relative_links() -> None:
    handle = "edequinox"
    assert _list_path_from_href(handle, "https://musicboard.app/edequinox/list/story-songs/") == "list/story-songs"
    assert _list_path_from_href(handle, "/edequinox/list/owned") == "list/owned"
    assert _list_path_from_href(handle, "list/fav-songs") == "list/fav-songs"
    assert _list_path_from_href(handle, "/wantlist") is None
    assert _list_path_from_href(handle, "https://example.com/list/x") is None


def test_extract_list_sources_from_html_finds_list_links() -> None:
    html = """
    <html><body>
      <a href="/edequinox/list/story-songs">Story Songs</a>
      <a href="list/owned">Owned</a>
      <a href="/edequinox/wantlist">Later</a>
    </body></html>
    """
    sources = extract_list_sources_from_html("edequinox", html)
    keys = {source.source_key for source in sources}
    assert "list:story-songs" in keys
    assert "list:owned" in keys
    assert "builtin:wantlist" not in keys


def test_merge_musicboard_sources_dedupes_by_path() -> None:
    builtins = [
        MusicboardImportSource(
            source_key="builtin:wantlist",
            kind="builtin",
            name="Later",
            path="wantlist",
            source_file="musicboardLater.csv",
        ),
    ]
    configured = sources_from_list_paths(
        [MusicboardListPath(key="story", path="list/story-songs", source_file="musicboardStory.csv")],
    )
    scraped = [
        MusicboardImportSource(
            source_key="list:story-songs",
            kind="list",
            name="Story from profile",
            path="list/story-songs",
            source_file="musicboardList_story-songs.csv",
        ),
        MusicboardImportSource(
            source_key="list:owned",
            kind="list",
            name="Owned",
            path="list/owned",
            source_file="musicboardList_owned.csv",
        ),
    ]
    merged = merge_musicboard_sources(builtins, configured, scraped)
    paths = [source.path for source in merged]
    assert "wantlist" in paths
    assert "list/story-songs" in paths
    assert "list/owned" in paths
    assert len([source for source in merged if source.path == "list/story-songs"]) == 1
    assert merged[1].name == "Story"  # configured wins over scraped duplicate path


def test_optional_configured_list_paths_empty_when_unset() -> None:
    assert optional_configured_list_paths("") == []
    assert optional_configured_list_paths("   ") == []


def test_optional_configured_list_paths_parses_json() -> None:
    raw = '[{"key":"fav","path":"list/fav-songs","sourceFile":"musicboardFav.csv"}]'
    paths = optional_configured_list_paths(raw)
    assert len(paths) == 1
    assert paths[0].key == "fav"


def test_parse_album_page_includes_source_key() -> None:
    from app.musicboard_scraper import MusicboardImportSource, _parse_album_page

    source = MusicboardImportSource(
        source_key="builtin:albums",
        kind="builtin",
        name="Albums",
        path="albums",
        source_file="musicboardAlbum.csv",
        page_kind="album",
    )
    html = """
    <div class="content-options-wrapper">
      <h6 class="bigbackenditem_title">OK Computer</h6>
      <img class="albumcover_cover" src="https://example.com/cover.jpg" />
    </div>
    """
    rows = _parse_album_page(html, source=source)
    assert len(rows) == 1
    assert rows[0].source_key == "builtin:albums"
    assert rows[0].source_file == "musicboardAlbum.csv"
