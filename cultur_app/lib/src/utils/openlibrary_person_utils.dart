/// Open Library authors use person ids prefixed with `ol-` (e.g. `ol-OL23919A`).
bool isOpenLibraryPersonId(String personId) {
  return personId.trim().startsWith('ol-');
}

/// Hardcover authors use person ids prefixed with `hc-` (e.g. `hc-42`).
bool isHardcoverPersonId(String personId) {
  return personId.trim().startsWith('hc-');
}

String hardcoverPersonId(String authorId) {
  final token = authorId.trim();
  if (token.isEmpty) {
    return '';
  }
  if (isHardcoverPersonId(token)) {
    return token;
  }
  return 'hc-$token';
}

/// Book catalog author pages (Open Library or Hardcover).
bool isBookAuthorPersonId(String personId) {
  final normalized = personId.trim();
  return isOpenLibraryPersonId(normalized) || isHardcoverPersonId(normalized);
}
