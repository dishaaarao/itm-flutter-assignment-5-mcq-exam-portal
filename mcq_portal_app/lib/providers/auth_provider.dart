import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';

enum AuthStatus {
  /// The stored token has not been checked yet — the splash screen.
  unknown,
  signedOut,
  signedIn,
}

/// Owns the session: the token, the user, and the sign-in/out transitions.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._services);

  final AppServices _services;

  static const String _tokenKey = 'mcq_portal_token';

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  String? _errorMessage;
  bool _busy = false;

  AuthStatus get status => _status;
  AppUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get busy => _busy;

  bool get isSignedIn => _status == AuthStatus.signedIn && _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;

  /// Restores a stored token and resolves it to a user.
  ///
  /// A token the server rejects is discarded rather than retried: an expired
  /// session should land on the login screen, not on a screen full of failing
  /// requests.
  Future<void> restoreSession() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final token = preferences.getString(_tokenKey);

      if (token == null || token.isEmpty) {
        _status = AuthStatus.signedOut;
        notifyListeners();
        return;
      }

      _services.apiClient.setToken(token);
      _user = await _services.auth.me();
      _status = AuthStatus.signedIn;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _clearSession();
      } else {
        // The backend is unreachable. Do not destroy a valid token over what
        // is most likely a server that is not running yet.
        _status = AuthStatus.signedOut;
      }
    } catch (_) {
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<bool> login({required String email, required String password}) {
    return _run(() => _services.auth.login(email: email, password: password));
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _run(() => _services.auth.register(name: name, email: email, password: password));
  }

  /// Shared sign-in path for login and register so both handle the token,
  /// errors and loading state identically.
  Future<bool> _run(Future<({AppUser user, String token})> Function() action) async {
    _busy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final session = await action();

      _services.apiClient.setToken(session.token);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_tokenKey, session.token);

      _user = session.user;
      _status = AuthStatus.signedIn;
      return true;
    } on ApiException catch (error) {
      // Field-level detail is more useful than "please correct the errors", so
      // it is preferred when the server sent it.
      _errorMessage = error.errors.isNotEmpty ? error.errors.join('\n') : error.message;
      return false;
    } catch (error) {
      _errorMessage = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _services.apiClient.clearToken();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    _user = null;
    _status = AuthStatus.signedOut;
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Replaces the cached user after a profile photo change.
  void updateUser(AppUser user) {
    _user = user;
    notifyListeners();
  }
}
