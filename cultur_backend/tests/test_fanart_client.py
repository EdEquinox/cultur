from app.fanart_client import FanartClient, _pick_image_url


def test_pick_image_url_prefers_artistthumb() -> None:
    payload = {
        "artistbackground": [{"url": "https://example.com/bg.jpg", "likes": "99"}],
        "artistthumb": [{"url": "https://example.com/thumb.jpg", "likes": "1"}],
    }
    assert _pick_image_url(payload) == "https://example.com/thumb.jpg"


def test_pick_image_url_chooses_highest_likes_within_field() -> None:
    payload = {
        "artistthumb": [
            {"url": "https://example.com/low.jpg", "likes": "2"},
            {"url": "https://example.com/high.jpg", "likes": "40"},
        ],
    }
    assert _pick_image_url(payload) == "https://example.com/high.jpg"


def test_artist_thumb_url_uses_cache(monkeypatch) -> None:
    calls: list[str] = []

    def fake_fetch(mbid: str) -> str | None:
        calls.append(mbid)
        return "https://example.com/cached.jpg"

    client = FanartClient(api_key="test-key")
    monkeypatch.setattr(client, "_fetch_artist_image_url", fake_fetch)

    assert client.artist_thumb_url("a74b1b7f-71a5-4011-9441-d0b5e4122711") == "https://example.com/cached.jpg"
    assert client.artist_thumb_url("a74b1b7f-71a5-4011-9441-d0b5e4122711") == "https://example.com/cached.jpg"
    assert calls == ["a74b1b7f-71a5-4011-9441-d0b5e4122711"]
