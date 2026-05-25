import 'package:flutter_test/flutter_test.dart';
import 'package:yamtrack/src/utils/bookmory_parser.dart';

const _readSample = '''
### Book information
- Title: A Estalagem no Fim do Mundo (The Sandman #8)
- Authors: Neil Gaiman
- ISBN: 9789896826031
- Wishlist: No
- Status: I've read it all!

### Reading log 1
- Read period: Dec 12, 2025 ~ Dec 31, 2025
- Star ratings: 4.0

### Purchase logs #1
- Price: €19.90
''';

const _loanSample = '''
### Book information
- Title: 1984 - A Novela Gráfica
- Authors: 
- ISBN: 9789725648123
- Status: To read

### Loan records #1
- Loan date: Apr 20, 2026
- Lender: Mariana
''';

const _noIsbnSample = '''
### Book information
- Title: Homo Deus: A Brief History of Tomorrow
- Authors: Yuval Noah Harari
- ISBN: 
- Status: To read
''';

void main() {
  test('parses read book with score, dates, and purchase', () {
    final outcome = parseBookmoryExportText(
      sourceFile: 'sandman.txt',
      text: _readSample,
    );
    expect(outcome, isA<BookmoryParseSuccess>());
    final entry = (outcome as BookmoryParseSuccess).entry;
    expect(entry.title, contains('Sandman'));
    expect(entry.isbn, '9789896826031');
    expect(entry.status, "I've read it all!");
    expect(entry.score, 4.0);
    expect(entry.collected, isTrue);
    expect(entry.collectedPrice, '€19.90');
    expect(entry.completedAtUtc, DateTime.utc(2025, 12, 31));
  });

  test('parses loan as collected + lent', () {
    final outcome = parseBookmoryExportText(
      sourceFile: '1984.txt',
      text: _loanSample,
    );
    final entry = (outcome as BookmoryParseSuccess).entry;
    expect(entry.collected, isTrue);
    expect(entry.lentBorrower, 'Mariana');
    expect(entry.lentAtUtc, DateTime.utc(2026, 4, 20));
  });

  test('empty ISBN becomes null', () {
    final entry = (parseBookmoryExportText(
      sourceFile: 'homo.txt',
      text: _noIsbnSample,
    ) as BookmoryParseSuccess)
        .entry;
    expect(entry.isbn, isNull);
  });

  test('normalizeBookmoryIsbn strips hyphens', () {
    expect(normalizeBookmoryIsbn('978-0-1234567-8-9'), '9780123456789');
  });
}
