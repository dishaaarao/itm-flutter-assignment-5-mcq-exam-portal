import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// A failed request, carrying whatever the server said about it.
///
/// `statusCode` is 0 when the request never reached the server, which is how
/// callers tell "the backend said no" apart from "the backend was not there".
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode = 0, this.errors = const []});

  final String message;
  final int statusCode;
  final List<String> errors;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isNetworkFailure => statusCode == 0;

  @override
  String toString() => message;
}

/// The unwrapped success envelope. The server always answers with
/// `{success, data, message?, count?, errors?}`; services work with this.
class ApiResponse {
  const ApiResponse({required this.data, this.message, this.count, this.errors = const []});

  final dynamic data;
  final String? message;
  final int? count;
  final List<String> errors;

  /// `data` as an object, or an empty one when the server sent something else.
  Map<String, dynamic> get asMap =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : <String, dynamic>{};

  List<dynamic> get asList => data is List ? data as List<dynamic> : const <dynamic>[];
}

/// Thin wrapper over `package:http`.
///
/// Two jobs: hold the JWT so services never pass it around, and unwrap the
/// response envelope so a failure surfaces as an exception instead of as a
/// `success: false` that some caller forgets to check.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _token;

  void setToken(String? token) => _token = token;
  String? get token => _token;
  void clearToken() => _token = null;

  Map<String, String> _headers({bool json = true}) {
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  /// Turns any thrown error into an [ApiException] with a message worth showing.
  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('The server took too long to respond. Check that it is running.');
    } catch (error) {
      throw ApiException(
        'Could not reach the server at ${AppConfig.apiBaseUrl}. '
        'Make sure the backend is running (cd backend && npm start).',
      );
    }
  }

  ApiResponse _decode(http.Response response) {
    if (response.body.isEmpty) {
      if (response.statusCode >= 400) {
        throw ApiException('Request failed (${response.statusCode}).', statusCode: response.statusCode);
      }
      return const ApiResponse(data: null);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      // A non-JSON body means something other than our API answered — a proxy
      // error page, most likely. Report the status rather than the HTML.
      throw ApiException(
        'Unexpected response from the server (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected response from the server.', statusCode: response.statusCode);
    }

    if (response.statusCode >= 400 || decoded['success'] == false) {
      final rawErrors = decoded['errors'];
      throw ApiException(
        decoded['message'] as String? ?? 'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
        errors: rawErrors is List ? rawErrors.map((e) => e.toString()).toList() : const [],
      );
    }

    return ApiResponse(
      data: decoded['data'],
      message: decoded['message'] as String?,
      count: (decoded['count'] as num?)?.toInt(),
      errors: decoded['errors'] is List
          ? (decoded['errors'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }

  Future<ApiResponse> get(String path) {
    return _guard(() async {
      final response = await _client
          .get(_uri(path), headers: _headers(json: false))
          .timeout(AppConfig.requestTimeout);
      return _decode(response);
    });
  }

  Future<ApiResponse> post(String path, {Map<String, dynamic>? body}) {
    return _guard(() async {
      final response = await _client
          .post(_uri(path), headers: _headers(), body: jsonEncode(body ?? const {}))
          .timeout(AppConfig.requestTimeout);
      return _decode(response);
    });
  }

  Future<ApiResponse> put(String path, {Map<String, dynamic>? body}) {
    return _guard(() async {
      final response = await _client
          .put(_uri(path), headers: _headers(), body: jsonEncode(body ?? const {}))
          .timeout(AppConfig.requestTimeout);
      return _decode(response);
    });
  }

  Future<ApiResponse> delete(String path) {
    return _guard(() async {
      final response = await _client
          .delete(_uri(path), headers: _headers(json: false))
          .timeout(AppConfig.requestTimeout);
      return _decode(response);
    });
  }

  /// Multipart upload, sent as bytes rather than a file path.
  ///
  /// `file_picker` and `image_picker` only give a real path on desktop and
  /// mobile — on web there is no filesystem, so a path-based upload would work
  /// everywhere except the one platform the app is most easily demoed on.
  Future<ApiResponse> upload(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    Map<String, String> fields = const {},
  }) {
    return _guard(() async {
      final request = http.MultipartRequest('POST', _uri(path));
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      request.headers['Accept'] = 'application/json';

      request.fields.addAll(fields);
      request.files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));

      final streamed = await request.send().timeout(AppConfig.uploadTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    });
  }
}
