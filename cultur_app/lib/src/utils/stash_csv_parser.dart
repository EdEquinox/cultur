/// Parses Stash.games CSV exports from [extract_data_stash.py].
library;

const _statusFileCategories = <String, String>{
  'stashgames.csv': 'Want',
  'stashplaying.csv': 'Playing',
  'stashbeaten.csv': 'Beaten',
  'stasharchived.csv': 'Archived',
};

const _collectionFileFlags = <String, List<String>>{
  'stashprioridades.csv': ['priority'],
  'stashtop.csv': ['priority'],
  'stashabandonados.csv': ['dropped'],
  'stashgaveta.csv': ['dropped'],
  'stashfisical.csv': ['collected'],
  'stashnon_fisical.csv': ['collected'],
};

const _statusCategoryFlags = <String, List<String>>{
  'Want': ['watchlist'],
  'Playing': ['doing'],
  'Beaten': ['watched'],
  'Archived': ['dropped'],
};

class StashMergedGame {
  StashMergedGame({
    required this.title,
    this.imageUrl,
    Set<String>? flags,
    this.score,
    this.review,
    this.sourceFiles = const {},
  }) : flags = flags ?? <String>{};

  final String title;
  final String? imageUrl;
  final Set<String> flags;
  double? score;
  String? review;
  final Set<String> sourceFiles;

  String get primarySourceFile =>
      sourceFiles.isEmpty ? 'stash.csv' : sourceFiles.first;

  Map<String, dynamic> toImportJson() => {
        'sourceFile': primarySourceFile,
        'title': title,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        'flags': flags.toList()..sort(),
        if (score != null && score! > 0) 'score': score,
        if (review != null && review!.isNotEmpty) 'review': review,
      };
}

class StashCsvParseFailure {
  const StashCsvParseFailure({required this.sourceFile, required this.message});

  final String sourceFile;
  final String message;
}

sealed class StashCsvParseOutcome {}

class StashCsvParseSuccess extends StashCsvParseOutcome {
  StashCsvParseSuccess(this.games, {this.failures = const []});

  final List<StashMergedGame> games;
  final List<StashCsvParseFailure> failures;
}

class StashCsvParseError extends StashCsvParseOutcome {
  StashCsvParseError(this.failure);

  final StashCsvParseFailure failure;
}

/// Parse one CSV file and merge into [into].
void mergeStashCsvInto(
  Map<String, StashMergedGame> into,
  {
  required String sourceFile,
  required String text,
  List<StashCsvParseFailure>? failures,
}) {
  final baseName = _baseName(sourceFile);
  final rows = _parseCsv(text);
  if (rows.isEmpty) {
    return;
  }

  final header = rows.first.map((c) => c.trim().toLowerCase()).toList();
  final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];

  final titleIdx = _indexOf(header, {'title'});
  if (titleIdx < 0) {
    failures?.add(
      StashCsvParseFailure(sourceFile: sourceFile, message: 'Missing Title column.'),
    );
    return;
  }
  final imageIdx = _indexOf(header, {'image url', 'imageurl'});
  final categoryIdx = _indexOf(header, {'category'});
  final ratingIdx = _indexOf(header, {'rating'});
  final reviewIdx = _indexOf(header, {'review'});

  final isReviewFile = baseName.contains('review');
  final statusFlags = _statusFileCategories[baseName];
  final collectionFlags = _collectionFileFlags[baseName];

  for (final row in dataRows) {
    if (row.every((cell) => cell.trim().isEmpty)) {
      continue;
    }
    final title = _cell(row, titleIdx).trim();
    if (title.isEmpty) {
      continue;
    }
    final imageUrl = imageIdx >= 0 ? _cell(row, imageIdx).trim() : '';
    final key = _dedupeKey(title, imageUrl);

    final flags = <String>{};
    if (isReviewFile) {
      // flags come from other files; only score/review here
    } else if (statusFlags != null) {
      flags.addAll(_statusCategoryFlags[statusFlags] ?? const []);
    } else if (collectionFlags != null) {
      flags.addAll(collectionFlags);
    } else if (categoryIdx >= 0) {
      final category = _cell(row, categoryIdx).trim();
      flags.addAll(_statusCategoryFlags[category] ?? const []);
    }

    final rating = ratingIdx >= 0 ? _parseRating(_cell(row, ratingIdx)) : null;
    final review = reviewIdx >= 0 ? _cell(row, reviewIdx).trim() : null;

    final existing = into[key];
    if (existing == null) {
      into[key] = StashMergedGame(
        title: title,
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
        flags: flags,
        score: rating,
        review: review?.isEmpty ?? true ? null : review,
        sourceFiles: {sourceFile},
      );
    } else {
      existing.flags.addAll(flags);
      existing.sourceFiles.add(sourceFile);
      if (rating != null && (existing.score == null || rating > existing.score!)) {
        existing.score = rating;
      }
      if (review != null && review.isNotEmpty) {
        if (existing.review != null &&
            existing.review!.isNotEmpty &&
            existing.review != review) {
          existing.review = '${existing.review}\n\n$review';
        } else {
          existing.review = review;
        }
      }
    }
  }
}

StashCsvParseOutcome parseStashCsvFiles(List<({String name, String text})> files) {
  final merged = <String, StashMergedGame>{};
  final failures = <StashCsvParseFailure>[];

  for (final file in files) {
    try {
      mergeStashCsvInto(
        merged,
        sourceFile: file.name,
        text: file.text,
        failures: failures,
      );
    } catch (e) {
      failures.add(
        StashCsvParseFailure(
          sourceFile: file.name,
          message: 'Could not parse CSV: $e',
        ),
      );
    }
  }

  if (merged.isEmpty && failures.isEmpty) {
    return StashCsvParseError(
      const StashCsvParseFailure(
        sourceFile: 'import',
        message: 'No games found in the selected CSV files.',
      ),
    );
  }

  final games = merged.values.toList()
    ..sort((a, b) => a.title.compareTo(b.title));
  return StashCsvParseSuccess(games, failures: failures);
}

String _baseName(String path) {
  final slash = path.replaceAll('\\', '/');
  final name = slash.contains('/') ? slash.split('/').last : slash;
  return name.trim().toLowerCase();
}

String _dedupeKey(String title, String imageUrl) {
  final coverMatch = RegExp(r'/co([a-z0-9]+)\.', caseSensitive: false).firstMatch(imageUrl);
  if (coverMatch != null) {
    return 'cover:co${coverMatch.group(1)!.toLowerCase()}';
  }
  return 'title:${_normalizeTitle(title)}';
}

String _normalizeTitle(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

int _indexOf(List<String> header, Set<String> names) {
  for (var i = 0; i < header.length; i++) {
    if (names.contains(header[i])) {
      return i;
    }
  }
  return -1;
}

String _cell(List<String> row, int index) {
  if (index < 0 || index >= row.length) {
    return '';
  }
  return row[index];
}

double? _parseRating(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) {
    return null;
  }
  final value = double.tryParse(text);
  if (value == null || value <= 0) {
    return null;
  }
  return value;
}

/// Minimal RFC-style CSV parser (quoted fields, commas).
List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      cell.write(ch);
      i++;
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
      i++;
      continue;
    }
    if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
      i++;
      continue;
    }
    if (ch == '\n' || ch == '\r') {
      row.add(cell.toString());
      cell.clear();
      if (row.any((c) => c.trim().isNotEmpty)) {
        rows.add(List<String>.from(row));
      }
      row.clear();
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
        i += 2;
      } else {
        i++;
      }
      continue;
    }
    cell.write(ch);
    i++;
  }
  row.add(cell.toString());
  if (row.any((c) => c.trim().isNotEmpty)) {
    rows.add(row);
  }
  return rows;
}
