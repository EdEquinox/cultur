"""Tests for TMDB crew parsing."""

from app.tmdb_client import TmdbClient, _crew_groups_sorted


def test_parse_crew_includes_all_tmdb_departments() -> None:
    client = TmdbClient(api_key="test", language="en-US")
    groups = client._parse_crew(
        {
            "crew": [
                {"id": 1, "name": "Director One", "department": "Directing", "job": "Director"},
                {"id": 2, "name": "Editor One", "department": "Editing", "job": "Editor"},
                {"id": 3, "name": "VFX One", "department": "Visual Effects", "job": "VFX Artist"},
                {"id": 4, "name": "Camera One", "department": "Camera", "job": "Director of Photography"},
            ],
        },
    )
    titles = [g.title for g in groups]
    assert titles == ["Directing", "Camera", "Editing", "Visual Effects"]


def test_crew_groups_sorted_puts_known_departments_first() -> None:
    from app.tmdb_client import TmdbPerson

    grouped = {
        "Sound": [TmdbPerson(person_id="1", name="A", role=None, image_url=None)],
        "Directing": [TmdbPerson(person_id="2", name="B", role=None, image_url=None)],
        "Costume & Make-Up": [TmdbPerson(person_id="3", name="C", role=None, image_url=None)],
    }
    groups = _crew_groups_sorted(grouped)
    assert [g.title for g in groups] == ["Directing", "Sound", "Costume & Make-Up"]
