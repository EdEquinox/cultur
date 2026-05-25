import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/models/person/user_follow_entry.dart';
import 'package:yamtrack/src/utils/follow_entity_utils.dart';

class FollowsApi {
  const FollowsApi(this._client);

  final ApiClient _client;

  Future<List<UserFollowEntry>> listFollows({
    required String username,
    String? entityKind,
  }) async {
    final payload = await _client.getJson(
      '/backend/follows',
      queryParameters: {
        'username': username,
        if (entityKind != null && entityKind.isNotEmpty) 'entityKind': entityKind,
      },
    );
    final items = payload['items'];
    if (items is! List) {
      return const [];
    }
    final rows = <UserFollowEntry>[];
    for (final raw in items) {
      if (raw is Map<String, dynamic>) {
        rows.add(_entryFromJson(raw));
      } else if (raw is Map) {
        rows.add(_entryFromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return rows;
  }

  Future<UserFollowEntry> follow({
    required String username,
    required String entityKind,
    String? personId,
    String? sourceCode,
    String? externalId,
    String? name,
    String? imageUrl,
  }) async {
    final payload = await _client.postJson(
      '/backend/follows',
      data: {
        'username': username,
        'entityKind': entityKind,
        if (personId != null && personId.isNotEmpty) 'personId': personId,
        if (sourceCode != null && sourceCode.isNotEmpty) 'sourceCode': sourceCode,
        if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
        if (name != null && name.isNotEmpty) 'name': name,
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      },
    );
    return _entryFromJson(payload);
  }

  Future<void> unfollow({
    required String username,
    required String routeOrServerPersonId,
  }) async {
    final encoded = Uri.encodeComponent(routeOrServerPersonId);
    await _client.delete(
      '/backend/follows/$encoded',
      queryParameters: {'username': username},
    );
  }

  static UserFollowEntry _entryFromJson(Map<String, dynamic> json) {
    final entityKind = json['entityKind']?.toString() ?? 'person';
    final sourceCode = json['sourceCode']?.toString();
    final externalId = json['externalId']?.toString();
    final serverPersonId = json['personId']?.toString() ?? '';
    return UserFollowEntry(
      followId: json['id']?.toString() ?? '',
      serverPersonId: serverPersonId,
      entityKind: entityKind,
      routePersonId: routePersonIdFromFollow(
        entityKind: entityKind,
        sourceCode: sourceCode,
        externalId: externalId,
      ),
      name: json['name']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString(),
      sourceCode: sourceCode,
      externalId: externalId,
    );
  }
}
