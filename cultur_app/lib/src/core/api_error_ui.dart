import 'package:flutter/material.dart';

import 'api_exception.dart';

/// User-facing text for errors from [ApiClient] and other failures.
/// Converts [ApiException] types into human-readable error messages.
String apiErrorMessage(Object error) {
  if (error is ApiException) {
    return switch (error.kind) {
      ApiExceptionKind.serverNotConfigured =>
        'Set up your server in Profile before using this feature.',
      ApiExceptionKind.unauthorized => error.statusCode == 403
          ? 'You do not have permission to do that.'
          : 'Your session may have expired. Sign in again.',
      ApiExceptionKind.network =>
        'Could not reach the server. Check the server URL and your connection.',
      ApiExceptionKind.timeout =>
        'The request timed out. Check your connection and try again.',
      ApiExceptionKind.http => error.message,
      ApiExceptionKind.unknown => error.message,
    };
  }

  final text = error.toString();
  const exceptionPrefix = 'Exception: ';
  if (text.startsWith(exceptionPrefix)) {
    return text.substring(exceptionPrefix.length);
  }
  return text;
}

/// Builds a [SnackBar] with a friendly API / network message.
SnackBar apiErrorSnackBar(
  Object error, {
  String? prefix,
}) {
  final body = prefix == null
      ? apiErrorMessage(error)
      : '$prefix ${apiErrorMessage(error)}';
  return SnackBar(content: Text(body));
}

/// Shows a [SnackBar] for [error]; no-op if [context] is not mounted.
void showApiErrorSnackBar(
  BuildContext context,
  Object error, {
  String? prefix,
}) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    apiErrorSnackBar(error, prefix: prefix),
  );
}
