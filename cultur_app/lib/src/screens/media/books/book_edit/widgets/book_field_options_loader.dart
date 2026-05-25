import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/books/book_edit_models.dart';

Future<BookFieldOptionsResponse> loadBookFieldOptions(
  WidgetRef ref, {
  required String mediaId,
  required BookEditFieldInfo field,
  BookEditSearchHit? lookup,
  String? search,
}) async {
  final params = <String, dynamic>{};
  if (lookup != null) {
    params['lookupSource'] = lookup.source;
    params['lookupExternalId'] = lookup.externalId;
    if (lookup.isbn != null && lookup.isbn!.isNotEmpty) {
      params['lookupIsbn'] = lookup.isbn;
    }
    if (lookup.title.isNotEmpty) {
      params['lookupTitle'] = lookup.title;
    }
    if (lookup.authors != null && lookup.authors!.isNotEmpty) {
      params['lookupAuthors'] = lookup.authors;
    }
  }
  final searchText = (search ?? '').trim();
  if (searchText.isNotEmpty) {
    params['search'] = searchText;
  }

  final client = ref.read(apiClientProvider);
  final payload = await client.getJson(
    '/catalog/books/$mediaId/fields/${Uri.encodeComponent(field.key)}/options',
    queryParameters: params,
  );
  return BookFieldOptionsResponse.fromJson(payload);
}

String providerLabel(String provider) {
  final index = provider.indexOf(':');
  final base = index > 0 ? provider.substring(0, index) : provider;
  return switch (base) {
    'openlibrary' => 'Open Library',
    'hardcover' => 'Hardcover',
    'porbase' => 'PORBASE',
    'current' => 'Saved',
    'manual' => 'Custom',
    _ => base,
  };
}
