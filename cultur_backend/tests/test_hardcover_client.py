from unittest.mock import patch

from app.hardcover_client import (
    HardcoverClient,
    _book_from_search_document,
    _books_from_search_results,
)


def test_books_from_search_results() -> None:
    raw = {
        "found": 1,
        "hits": [
            {
                "document": {
                    "id": 445065,
                    "title": "Blood of Elves",
                    "author_names": ["Andrzej Sapkowski"],
                    "isbns": ["9789897730870", "9788370540791"],
                    "pages": 284,
                    "release_year": 2018,
                    "slug": "blood-of-elves",
                    "description": "Witcher novel",
                    "image": {
                        "url": "https://assets.hardcover.app/edition/1/cover.jpg",
                    },
                },
            },
        ],
    }
    books = _books_from_search_results(raw, limit=5)
    assert len(books) == 1
    assert books[0].title == "Blood of Elves"
    assert books[0].metadata.get("isbn") == "9789897730870"
    assert books[0].metadata.get("authors") == "Andrzej Sapkowski"


def test_book_from_search_document_minimal() -> None:
    book = _book_from_search_document(
        {
            "id": 1,
            "title": "O Sangue dos Elfos",
            "author_names": ["Andrzej Sapkowski"],
            "isbns": ["9789897730870"],
        },
    )
    assert book is not None
    assert book.external_id == "1"
    assert book.metadata.get("isbn") == "9789897730870"


def test_fetch_by_isbn10_uses_isbn10_query_only() -> None:
    client = HardcoverClient(api_token="test-token")
    edition = {
        "id": 99,
        "title": "Murdle: Volume 1",
        "isbn_10": "1250892317",
        "isbn_13": None,
        "book": {
            "id": 817972,
            "title": "Murdle: Volume 1",
            "contributions": [{"author": {"name": "Steven W. Levitt"}}],
        },
    }

    with patch(
        "app.hardcover_client.HardcoverClient._graphql",
        return_value={"data": {"editions": [edition]}},
    ) as graphql:
        book = client.fetch_by_isbn("1250892317")

    assert book is not None
    assert book.title == "Murdle: Volume 1"
    graphql.assert_called_once()
    query, variables = graphql.call_args[0]
    assert "isbn_10" in query
    assert variables == {"isbn10": "1250892317"}


def test_fetch_author_books_skips_edition_only_contributions() -> None:
    client = HardcoverClient(api_token="test-token")
    payload = {
        "data": {
            "authors_by_pk": {
                "id": 80626,
                "name": "J.K. Rowling",
                "contributions": [
                    {
                        "contributable_id": 1,
                        "contributable_type": "Edition",
                        "book": None,
                    },
                    {
                        "contributable_id": 42,
                        "contributable_type": "Book",
                        "book": {
                            "id": 42,
                            "title": "Sample Book",
                            "slug": "sample-book",
                            "contributions": [{"author": {"id": 80626, "name": "J.K. Rowling"}}],
                            "default_cover_edition": {"isbn_13": "9780000000000"},
                        },
                    },
                ],
            },
        },
    }

    with patch(
        "app.hardcover_client.HardcoverClient._graphql",
        return_value=payload,
    ):
        books = client.fetch_author_books("80626", limit=10)

    assert len(books) == 1
    assert books[0].title == "Sample Book"
    assert books[0].external_id == "42"


def test_authorization_header_adds_bearer() -> None:
    from app.hardcover_client import _authorization_header

    assert _authorization_header("abc").startswith("Bearer ")
    assert _authorization_header("Bearer xyz") == "Bearer xyz"
