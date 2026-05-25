import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';

/// A followed person/company/publisher row from `/backend/follows`.
class UserFollowEntry {
  const UserFollowEntry({
    required this.followId,
    required this.serverPersonId,
    required this.entityKind,
    required this.routePersonId,
    required this.name,
    this.imageUrl,
    this.sourceCode,
    this.externalId,
    this.companyRole,
  });

  final String followId;
  final String serverPersonId;
  final String entityKind;
  final String routePersonId;
  final String name;
  final String? imageUrl;
  final String? sourceCode;
  final String? externalId;
  final String? companyRole;

  CatalogDetailPerson toPerson() {
    return CatalogDetailPerson(
      personId: routePersonId,
      name: name,
      imageUrl: imageUrl,
    );
  }
}
