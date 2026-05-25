/// App routes and API paths for `/people/:personId`.
///
/// Last.fm artist ids embed slashes (`lfm-artist:n/System+of+a+Down`). HTTP clients
/// and proxies often turn `%2F` back into `/`, splitting the path. We escape `/`
/// as `|` before [Uri.encodeComponent] so the id stays one segment.
const _personIdSlashEscape = '|';

String encodePersonIdForPath(String personId) {
  final id = personId.trim();
  if (id.isEmpty) {
    return '';
  }
  return Uri.encodeComponent(id.replaceAll('/', _personIdSlashEscape));
}

String decodePersonIdFromPath(String segment) {
  return Uri.decodeComponent(segment.trim()).replaceAll(_personIdSlashEscape, '/');
}

String personAppRoutePath(String personId) {
  final encoded = encodePersonIdForPath(personId);
  if (encoded.isEmpty) {
    return '/people/';
  }
  return '/people/$encoded';
}

String personCatalogApiPath(String personId) {
  final encoded = encodePersonIdForPath(personId);
  return '/catalog/people/$encoded';
}

/// Decode [personId] from a matched `/people/:personId` route segment.
String personIdFromRouteParam(String routeParam) {
  return decodePersonIdFromPath(routeParam);
}
