import '../models/user.dart';
import 'api_client.dart';

/// Authentication against the portal's own endpoints.
///
/// There is no Firebase SDK in this app by design: the client talks only to
/// this backend, which keeps an unsigned upload preset and a pile of platform
/// build configuration out of the shipped app. See the README.
class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  /// The created account and its token. Registration always produces a student;
  /// the server ignores any role in the request body.
  Future<({AppUser user, String token})> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _api.post('/api/auth/register', body: {
      'name': name,
      'email': email,
      'password': password,
    });

    return _sessionFrom(response.asMap);
  }

  Future<({AppUser user, String token})> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post('/api/auth/login', body: {
      'email': email,
      'password': password,
    });

    return _sessionFrom(response.asMap);
  }

  /// Resolves the stored token to the current user, for a cold start.
  Future<AppUser> me() async {
    final response = await _api.get('/api/auth/me');
    return AppUser.fromJson(response.asMap['user'] as Map<String, dynamic>? ?? const {});
  }

  Future<AppUser> uploadPhoto({required List<int> bytes, required String filename}) async {
    final response = await _api.upload(
      '/api/student/profile/photo',
      field: 'image',
      bytes: bytes,
      filename: filename,
    );

    return AppUser.fromJson(response.asMap['user'] as Map<String, dynamic>? ?? const {});
  }

  ({AppUser user, String token}) _sessionFrom(Map<String, dynamic> data) {
    final user = AppUser.fromJson(data['user'] as Map<String, dynamic>? ?? const {});
    final token = data['token'] as String? ?? '';
    return (user: user, token: token);
  }
}
