/// Catalog API ``sources`` values for book browse/search (Hardcover-only in the app).
enum BookCatalogSource {
  hardcover('hardcover', 'Hardcover');

  const BookCatalogSource(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static BookCatalogSource? fromApiValue(String? raw) {
    final token = (raw ?? '').trim().toLowerCase();
    if (token.isEmpty) {
      return BookCatalogSource.hardcover;
    }
    for (final source in BookCatalogSource.values) {
      if (source.apiValue == token) {
        return source;
      }
    }
    return null;
  }
}
