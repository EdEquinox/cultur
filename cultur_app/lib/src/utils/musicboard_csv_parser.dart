/// Parses Musicboard CSV exports from [extract_data_musicboard.py].
library;

const _musicboardFileFlags = <String, List<String>>{
  'musicboardlater.csv': ['watchlist'],
  'musicboardtobuy.csv': ['buy'],
  'musicboardowned.csv': ['collected'],
  'musicboardalbum.csv': ['collected'],
  'musicboardstory.csv': ['watchlist'],
  'musicboardfav.csv': ['priority'],
  'musicboardhistory.csv': ['watched'],
};

class MusicboardMergedAlbum {
  MusicboardMergedAlbum({
    required this.title,
    this.artist,
    this.imageUrl,
    Set<String>? flags,
    this.score,
    this.review,
    this.completedAt,
    this.sourceFiles = const {},
  }) : flags = flags ?? <String>{};

  final String title;
  String? artist;
  final String? imageUrl;
  final Set<String> flags;
  double? score;
  String? review;
  String? completedAt;
  final Set<String> sourceFiles;

  String get primarySourceFile =>
      sourceFiles.isEmpty ? 'musicboard.csv' : sourceFiles.first;

  Map<String, dynamic> toImportJson() => {
        'sourceFile': primarySourceFile,
        'title': title,
        if (artist != null && artist!.isNotEmpty) 'artist': artist,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        'flags': flags.toList()..sort(),
        if (score != null && score! > 0) 'score': score,
        if (review != null && review!.isNotEmpty) 'review': review,
        if (completedAt != null && completedAt!.isNotEmpty) 'completedAt': completedAt,
      };
}

class MusicboardCsvParseFailure {
  const MusicboardCsvParseFailure({required this.sourceFile, required this.message});

  final String sourceFile;
  final String message;
}

sealed class MusicboardCsvParseOutcome {}

class MusicboardCsvParseSuccess extends MusicboardCsvParseOutcome {
  MusicboardCsvParseSuccess(this.albums, {this.failures = const []});

  final List<MusicboardMergedAlbum> albums;
  final List<MusicboardCsvParseFailure> failures;
}

class MusicboardCsvParseError extends MusicboardCsvParseOutcome {
  MusicboardCsvParseError(this.failure);

  final MusicboardCsvParseFailure failure;
}

void mergeMusicboardCsvInto(
  Map<String, MusicboardMergedAlbum> into, {
  required String sourceFile,
  required String text,
  List<MusicboardCsvParseFailure>? failures,
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
      MusicboardCsvParseFailure(sourceFile: sourceFile, message: 'Missing Title column.'),
    );
    return;
  }
  final artistIdx = _indexOf(header, {'artist'});
  final imageIdx = _indexOf(header, {'image url', 'imageurl'});
  final rateIdx = _indexOf(header, {'rate', 'rating'});
  final reviewIdx = _indexOf(header, {'review'});
  final dateIdx = _indexOf(header, {'date'});
  final targetIdx = _indexOf(header, {'target'});

  final isReviewFile = baseName.contains('review');
  final isHistoryFile = baseName.contains('history');
  final fileFlags = _musicboardFileFlags[baseName];

  for (final row in dataRows) {
    if (row.every((cell) => cell.trim().isEmpty)) {
      continue;
    }

    var title = _cell(row, titleIdx).trim();
    if (isReviewFile && targetIdx >= 0) {
      final target = _cell(row, targetIdx).trim();
      if (target.isNotEmpty) {
        title = target;
      }
    }
    if (title.isEmpty) {
      continue;
    }

    final artist = artistIdx >= 0 ? _cell(row, artistIdx).trim() : '';
    final imageUrl = imageIdx >= 0 ? _cell(row, imageIdx).trim() : '';
    final key = _dedupeKey(title, artist, imageUrl);

    final flags = <String>{};
    if (!isReviewFile && fileFlags != null) {
      flags.addAll(fileFlags);
    }

    final rating = rateIdx >= 0 ? _parseMusicboardRating(_cell(row, rateIdx)) : null;
    final review = reviewIdx >= 0 ? _cell(row, reviewIdx).trim() : null;
    final completedAt = isHistoryFile && dateIdx >= 0
        ? _parseHistoryDate(_cell(row, dateIdx).trim())
        : null;

    final existing = into[key];
    if (existing == null) {
      into[key] = MusicboardMergedAlbum(
        title: title,
        artist: artist.isEmpty ? null : artist,
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
        flags: flags,
        score: rating,
        review: review?.isEmpty ?? true ? null : review,
        completedAt: completedAt,
        sourceFiles: {sourceFile},
      );
    } else {
      existing.flags.addAll(flags);
      existing.sourceFiles.add(sourceFile);
      if (artist.isNotEmpty && (existing.artist == null || existing.artist!.isEmpty)) {
        existing.artist = artist;
      }
      if (rating != null && (existing.score == null || rating > existing.score!)) {
        existing.score = rating;
      }
      if (completedAt != null && (existing.completedAt == null || existing.completedAt!.isEmpty)) {
        existing.completedAt = completedAt;
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

MusicboardCsvParseOutcome parseMusicboardCsvFiles(List<({String name, String text})> files) {
  final merged = <String, MusicboardMergedAlbum>{};
  final failures = <MusicboardCsvParseFailure>[];

  for (final file in files) {
    try {
      mergeMusicboardCsvInto(
        merged,
        sourceFile: file.name,
        text: file.text,
        failures: failures,
      );
    } catch (e) {
      failures.add(
        MusicboardCsvParseFailure(
          sourceFile: file.name,
          message: 'Could not parse CSV: $e',
        ),
      );
    }
  }

  if (merged.isEmpty && failures.isEmpty) {
    return MusicboardCsvParseError(
      const MusicboardCsvParseFailure(
        sourceFile: 'import',
        message: 'No albums found in the selected CSV files.',
      ),
    );
  }

  final albums = merged.values.toList()
    ..sort((a, b) => a.title.compareTo(b.title));
  return MusicboardCsvParseSuccess(albums, failures: failures);
}

String _baseName(String path) {
  final slash = path.replaceAll('\\', '/');
  final name = slash.contains('/') ? slash.split('/').last : slash;
  return name.trim().toLowerCase();
}

String _dedupeKey(String title, String artist, String imageUrl) {
  if (imageUrl.isNotEmpty) {
    return 'image:${imageUrl.trim().toLowerCase()}';
  }
  final artistKey = _normalizeTitle(artist);
  final titleKey = _normalizeTitle(title);
  if (artistKey.isNotEmpty) {
    return 'album:$artistKey|$titleKey';
  }
  return 'album:$titleKey';
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

double? _parseMusicboardRating(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) {
    return null;
  }
  final value = double.tryParse(text);
  if (value == null || value <= 0) {
    return null;
  }
  if (value <= 5) {
    return value * 2;
  }
  return value;
}

String? _parseHistoryDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final now = DateTime.now();
  final months = {
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
  };
  final parts = text.split(RegExp(r'\s+'));
  if (parts.length < 2) {
    return null;
  }
  final day = int.tryParse(parts.first);
  final monthKey = parts[1].toLowerCase();
  final month = months[monthKey];
  if (day == null || month == null || day < 1 || day > 31) {
    return null;
  }
  final dt = DateTime.utc(now.year, month, day);
  return dt.toIso8601String();
}

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
