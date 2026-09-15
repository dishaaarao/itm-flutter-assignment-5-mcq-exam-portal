import 'api_client.dart';
import 'attempt_service.dart';
import 'auth_service.dart';
import 'exam_service.dart';

/// Holds the one [ApiClient] and the services built on it.
///
/// A single client matters: it owns the JWT, so a second instance would mean a
/// second token to keep in sync — and a request that mysteriously goes out
/// unauthenticated.
class AppServices {
  AppServices({ApiClient? apiClient}) : apiClient = apiClient ?? ApiClient() {
    auth = AuthService(this.apiClient);
    exams = ExamService(this.apiClient);
    attempts = AttemptService(this.apiClient);
  }

  final ApiClient apiClient;

  late final AuthService auth;
  late final ExamService exams;
  late final AttemptService attempts;
}
