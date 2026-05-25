import 'package:dio/dio.dart';

import 'api_exception.dart';

/// HTTP client for interacting with the server API.
/// Handles API base URL configuration, session token management, and request/response handling.
class ApiClient {
  /// Constructs an [ApiClient] with the given base URL and optional session token.
  ApiClient({required String baseUrl, String? sessionToken})
    : _configured = baseUrl.trim().isNotEmpty,
      _dio = Dio(
        BaseOptions(
          baseUrl: _normalizeBaseUrl(baseUrl),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            if (sessionToken != null && sessionToken.isNotEmpty)
              'Authorization': 'Bearer $sessionToken',
            'Content-Type': 'application/json',
          },
        ),
      );

  final Dio _dio;
  final bool _configured;

  /// Whether a non-empty API base URL was provided at construction.
  bool get isConfigured => _configured;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
        options: receiveTimeout != null
            ? Options(receiveTimeout: receiveTimeout)
            : null,
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) async {
    _ensureConfigured();
    try {
      Options? options;
      if (receiveTimeout != null || sendTimeout != null) {
        options = Options(
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
        );
      }
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: options,
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.put<Map<String, dynamic>>(path, data: data);
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    _ensureConfigured();
    try {
      await _dio.delete<void>(path, queryParameters: queryParameters);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  void _ensureConfigured() {
    if (!_configured) {
      throw ApiException.serverNotConfigured();
    }
  }

  static String _normalizeBaseUrl(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
