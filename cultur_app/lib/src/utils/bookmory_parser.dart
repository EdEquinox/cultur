/// Parses a single Bookmory export `.txt` file into a structured import row.
library;

class BookmoryParsedEntry {
  const BookmoryParsedEntry({
    required this.sourceFile,
    required this.title,
    this.authors,
    this.isbn,
    required this.status,
    this.wishlist = false,
    this.score,
    this.completedAtUtc,
    this.startedAtUtc,
    this.droppedAtUtc,
    this.collected = false,
    this.collectedPrice,
    this.lentBorrower,
    this.lentAtUtc,
  });

  final String sourceFile;
  final String title;
  final String? authors;
  final String? isbn;
  final String status;
  final bool wishlist;
  final double? score;
  final DateTime? completedAtUtc;
  final DateTime? startedAtUtc;
  final DateTime? droppedAtUtc;
  final bool collected;
  final String? collectedPrice;
  final String? lentBorrower;
  final DateTime? lentAtUtc;

  Map<String, dynamic> toImportJson() => {
        'sourceFile': sourceFile,
        'title': title,
        if (authors != null && authors!.isNotEmpty) 'authors': authors,
        if (isbn != null && isbn!.isNotEmpty) 'isbn': isbn,
        'status': status,
        'wishlist': wishlist,
        if (score != null) 'score': score,
        if (completedAtUtc != null)
          'completedAt': completedAtUtc!.toUtc().toIso8601String(),
        if (startedAtUtc != null) 'startedAt': startedAtUtc!.toUtc().toIso8601String(),
        if (droppedAtUtc != null) 'droppedAt': droppedAtUtc!.toUtc().toIso8601String(),
        'collected': collected,
        if (collectedPrice != null && collectedPrice!.isNotEmpty)
          'collectedPrice': collectedPrice,
        if (lentBorrower != null && lentBorrower!.isNotEmpty)
          'lentBorrower': lentBorrower,
        if (lentAtUtc != null) 'lentAt': lentAtUtc!.toUtc().toIso8601String(),
      };
}

class BookmoryParseFailure {
  const BookmoryParseFailure({required this.sourceFile, required this.message});

  final String sourceFile;
  final String message;
}

/// Result of parsing one file: either a row or a local parse error.
sealed class BookmoryParseOutcome {}

class BookmoryParseSuccess extends BookmoryParseOutcome {
  BookmoryParseSuccess(this.entry);
  final BookmoryParsedEntry entry;
}

class BookmoryParseError extends BookmoryParseOutcome {
  BookmoryParseError(this.failure);
  final BookmoryParseFailure failure;
}

String? normalizeBookmoryIsbn(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  final digits = value.replaceAll(RegExp(r'[\s\-]'), '');
  if ((digits.length == 10 || digits.length == 13) && RegExp(r'^\d+$').hasMatch(digits)) {
    return digits;
  }
  return null;
}

BookmoryParseOutcome parseBookmoryExportText({
  required String sourceFile,
  required String text,
}) {
  try {
    final entry = _parseBookmoryExportText(sourceFile: sourceFile, text: text);
    if (entry.title.trim().isEmpty) {
      return BookmoryParseError(
        BookmoryParseFailure(
          sourceFile: sourceFile,
          message: 'Missing book title in file.',
        ),
      );
    }
    return BookmoryParseSuccess(entry);
  } catch (e) {
    return BookmoryParseError(
      BookmoryParseFailure(
        sourceFile: sourceFile,
        message: e is FormatException ? e.message : 'Could not parse file: $e',
      ),
    );
  }
}

BookmoryParsedEntry _parseBookmoryExportText({
  required String sourceFile,
  required String text,
}) {
  final fields = <String, String>{};
  String? readingLogBlock;
  String? purchaseBlock;
  String? loanBlock;

  final lines = text.split('\n');
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.startsWith('### Reading log')) {
      final buf = StringBuffer(line);
      i++;
      while (i < lines.length && !lines[i].startsWith('### ')) {
        buf.writeln();
        buf.writeln(lines[i]);
        i++;
      }
      readingLogBlock = buf.toString();
      continue;
    }
    if (line.startsWith('### Purchase logs')) {
      final buf = StringBuffer(line);
      i++;
      while (i < lines.length && !lines[i].startsWith('### ')) {
        buf.writeln();
        buf.writeln(lines[i]);
        i++;
      }
      purchaseBlock = buf.toString();
      continue;
    }
    if (line.startsWith('### Loan records')) {
      final buf = StringBuffer(line);
      i++;
      while (i < lines.length && !lines[i].startsWith('### ')) {
        buf.writeln();
        buf.writeln(lines[i]);
        i++;
      }
      loanBlock = buf.toString();
      continue;
    }
    final kv = _parseBulletLine(line);
    if (kv != null) {
      fields[kv.$1] = kv.$2;
    }
    i++;
  }

  final title = fields['Title']?.trim() ?? '';
  final status = fields['Status']?.trim() ?? 'To read';
  final wishlist = (fields['Wishlist']?.trim().toLowerCase() ?? '') == 'yes';

  final reading = readingLogBlock == null ? null : _parseReadingLog(readingLogBlock);
  final purchase = purchaseBlock == null ? null : _parsePurchaseLog(purchaseBlock);
  final loan = loanBlock == null ? null : _parseLoanBlock(loanBlock);

  var collected = purchase != null;
  var collectedPrice = purchase?.price;
  String? lentBorrower;
  DateTime? lentAtUtc;
  if (loan != null) {
    collected = true;
    lentBorrower = loan.borrower;
    lentAtUtc = loan.loanDate;
  }

  double? score = reading?.stars;
  if (score != null && score <= 0) {
    score = null;
  }

  DateTime? completedAtUtc;
  DateTime? startedAtUtc;
  DateTime? droppedAtUtc;

  if (status == "I've read it all!") {
    completedAtUtc = reading?.periodEnd ?? reading?.periodStart;
  } else if (status == 'Gave up') {
    droppedAtUtc = reading?.periodEnd ?? reading?.periodStart;
  } else if (status == 'Reading') {
    startedAtUtc = reading?.periodStart;
  }

  return BookmoryParsedEntry(
    sourceFile: sourceFile,
    title: title,
    authors: _emptyToNull(fields['Authors']),
    isbn: normalizeBookmoryIsbn(fields['ISBN']),
    status: status,
    wishlist: wishlist,
    score: score,
    completedAtUtc: completedAtUtc,
    startedAtUtc: startedAtUtc,
    droppedAtUtc: droppedAtUtc,
    collected: collected,
    collectedPrice: collectedPrice,
    lentBorrower: lentBorrower,
    lentAtUtc: lentAtUtc,
  );
}

(String, String)? _parseBulletLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('- ')) {
    return null;
  }
  final body = trimmed.substring(2);
  final colon = body.indexOf(':');
  if (colon <= 0) {
    return null;
  }
  final key = body.substring(0, colon).trim();
  final value = body.substring(colon + 1).trim();
  return (key, value);
}

class _ReadingLogData {
  const _ReadingLogData({this.periodStart, this.periodEnd, this.stars});

  final DateTime? periodStart;
  final DateTime? periodEnd;
  final double? stars;
}

_ReadingLogData? _parseReadingLog(String block) {
  DateTime? start;
  DateTime? end;
  double? stars;
  for (final line in block.split('\n')) {
    final kv = _parseBulletLine(line);
    if (kv == null) {
      continue;
    }
    switch (kv.$1) {
      case 'Read period':
        final parts = kv.$2.split('~').map((s) => s.trim()).toList();
        if (parts.isNotEmpty && parts.first.isNotEmpty) {
          start = _parseBookmoryDate(parts.first);
        }
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = _parseBookmoryDate(parts[1]);
        }
      case 'Star ratings':
        final v = double.tryParse(kv.$2.trim());
        if (v != null) {
          stars = v;
        }
    }
  }
  if (start == null && end == null && stars == null) {
    return null;
  }
  return _ReadingLogData(periodStart: start, periodEnd: end, stars: stars);
}

class _PurchaseLogData {
  const _PurchaseLogData({this.price});

  final String? price;
}

_PurchaseLogData? _parsePurchaseLog(String block) {
  String? price;
  for (final line in block.split('\n')) {
    final kv = _parseBulletLine(line);
    if (kv == null) {
      continue;
    }
    if (kv.$1 == 'Price') {
      final p = kv.$2.trim();
      if (p.isNotEmpty && p != '?') {
        price = p;
      }
    }
  }
  if (price == null) {
    // Purchase section without price still means owned in Bookmory.
    return const _PurchaseLogData();
  }
  return _PurchaseLogData(price: price);
}

class _LoanData {
  const _LoanData({this.borrower, this.loanDate});

  final String? borrower;
  final DateTime? loanDate;
}

_LoanData? _parseLoanBlock(String block) {
  String? borrower;
  DateTime? loanDate;
  for (final line in block.split('\n')) {
    final kv = _parseBulletLine(line);
    if (kv == null) {
      continue;
    }
    switch (kv.$1) {
      case 'Lender':
        borrower = _emptyToNull(kv.$2);
      case 'Loan date':
        loanDate = _parseBookmoryDate(kv.$2);
    }
  }
  if (borrower == null && loanDate == null) {
    return null;
  }
  return _LoanData(borrower: borrower, loanDate: loanDate);
}

String? _emptyToNull(String? value) {
  final t = value?.trim() ?? '';
  return t.isEmpty ? null : t;
}

/// Bookmory dates like `Dec 12, 2025` or `Apr 20, 2026`.
DateTime? _parseBookmoryDate(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t == '?') {
    return null;
  }
  const months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  final m = RegExp(r'^([A-Za-z]{3})\s+(\d{1,2}),\s*(\d{4})$').firstMatch(t);
  if (m == null) {
    return null;
  }
  final mon = months[m.group(1)!.toLowerCase()];
  if (mon == null) {
    return null;
  }
  final day = int.tryParse(m.group(2)!);
  final year = int.tryParse(m.group(3)!);
  if (day == null || year == null) {
    return null;
  }
  return DateTime.utc(year, mon, day);
}
