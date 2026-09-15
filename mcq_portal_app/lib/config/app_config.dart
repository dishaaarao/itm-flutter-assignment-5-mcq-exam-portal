import 'package:flutter/foundation.dart';

/// Where the app looks for the backend.
///
/// The Android emulator cannot reach the host's `localhost` — it routes
/// `10.0.2.2` to the host machine instead — so the base URL has to be
/// platform-aware rather than hardcoded.
///
/// Override for a physical device or a deployed backend:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.5:5050
/// ```
class AppConfig {
  const AppConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static const String _defaultHost = 'http://localhost:5050';
  static const String _androidEmulatorHost = 'http://10.0.2.2:5050';

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return _defaultHost;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _androidEmulatorHost;
    }
    return _defaultHost;
  }

  /// The seeded administrator, offered as a hint on the login screen because
  /// there is no way to reach the admin panel without it on a fresh install.
  static const String demoAdminEmail = 'admin@mcq.local';
  static const String demoAdminPassword = 'Admin@123';

  /// Matches the backend's `SUBMIT_GRACE_SECONDS`. The client stops accepting
  /// input this many seconds after the deadline, so a slow submit is still
  /// within the window the server allows.
  static const int submitGraceSeconds = 30;

  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 2);
}
