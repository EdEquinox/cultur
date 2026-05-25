import 'package:dio/dio.dart';

enum ApiExceptionKind {
  serverNotConfigured,
  unauthorized,
  network,
  timeout,
  http,
  unknown,
}

/// Typed HTTP / client failure for UI and controllers.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.cause,
  });

  final ApiExceptionKind kind;
  final String message;
  final int? statusCode;
  final Object? cause;

  bool get isServerNotConfigured => kind == ApiExceptionKind.serverNotConfigured;
  bool get isUnauthorized => kind == ApiExceptionKind.unauthorized;
  bool get isNetwork => kind == ApiExceptionKind.network;
  bool get isTimeout => kind == ApiExceptionKind.timeout;

  factory ApiException.serverNotConfigured() {
    return const ApiException(
      kind: ApiExceptionKind.serverNotConfigured,
      message: 'Configure the server API URL first.',
    );
  }

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          kind: ApiExceptionKind.timeout,
          message: 'The request timed out. Check your connection and try again.',
          cause: error,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          kind: ApiExceptionKind.network,
          message: 'Could not reach the server. Check the URL and your network.',
          cause: error,
        );
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        final msg = messageFromDioResponse(error);
        if (code == 401 || code == 403) {
          return ApiException(
            kind: ApiExceptionKind.unauthorized,
            message: msg,
            statusCode: code,
            cause: error,
          );
        }
        return ApiException(
          kind: ApiExceptionKind.http,
          message: msg,
          statusCode: code,
          cause: error,
        );
      case DioExceptionType.cancel:
        return ApiException(
          kind: ApiExceptionKind.unknown,
          message: 'Request was cancelled.',
          cause: error,
        );
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ApiException(
          kind: ApiExceptionKind.unknown,
          message: messageFromDioResponse(error),
          cause: error,
        );
    }
  }

  static String messageFromDioResponse(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['error'] ?? data['message'];
      if (message != null) {
        return message.toString();
      }
    }
    return error.message ?? 'Unexpected network error.';
  }

  @override
  String toString() => message;
}
