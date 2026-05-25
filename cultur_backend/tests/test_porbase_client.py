from app.porbase_client import PorbaseClient, _book_from_porbase_xml

_SAMPLE = """<?xml version="1.0" encoding="UTF-8"?>
<dc xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>?O Sangue dos elfos</dc:title>
<dc:creator>Sapkowski, Andrzej, 1948-</dc:creator>
<dc:publisher>Saída de Emergência</dc:publisher>
<dc:date>2018</dc:date>
<dc:language>por</dc:language>
<dc:identifier>Id. do registo: 2808776</dc:identifier>
<dc:identifier>URN:ISBN:978-989-773-087-0</dc:identifier>
</dc>"""


def test_book_from_porbase_xml() -> None:
    book = _book_from_porbase_xml(_SAMPLE, "9789897730870")
    assert book is not None
    assert book.external_id == "2808776"
    assert "elfos" in book.title.casefold()
    assert book.metadata.get("isbn") == "9789897730870"
    assert book.metadata.get("importSource") == "porbase"


def test_missing_record() -> None:
    assert _book_from_porbase_xml(
        '<?xml version="1.0"?><urn-response><error>Registo inexistente</error></urn-response>',
        "9780000000000",
    ) is None
