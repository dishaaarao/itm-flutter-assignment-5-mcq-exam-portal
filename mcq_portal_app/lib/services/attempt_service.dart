import '../models/attempt.dart';
import '../models/user.dart';
import 'api_client.dart';

/// Submitting an attempt, reading it back, and the admin-side reports.
class AttemptService {
  AttemptService(this._api);

  final ApiClient _api;

  /// Grades and stores the submission. Returns the result the server computed —
  /// the client never calculates a score.
  Future<AttemptSubmission> submit({
    required String attemptId,
    required Map<String, String> answers,
  }) async {
    final response = await _api.post(
      '/api/student/attempts/$attemptId/submit',
      body: {'answers': answers},
    );

    final data = response.asMap;
    return AttemptSubmission.fromJson({
      ...data,
      'attemptId': data['attemptId'] ?? attemptId,
    });
  }

  Future<List<AttemptRow>> history() async {
    final response = await _api.get('/api/student/attempts');
    final raw = response.asMap['attempts'];
    if (raw is! List) return const <AttemptRow>[];
    return raw.whereType<Map<String, dynamic>>().map(AttemptRow.fromJson).toList();
  }

  /// One stored result. Throws with a 409 conflict when the attempt exists but
  /// has not been submitted yet.
  Future<AttemptSubmission> getResult(String attemptId) async {
    final response = await _api.get('/api/student/attempts/$attemptId');
    return AttemptSubmission.fromJson(response.asMap);
  }

  // --- Admin --------------------------------------------------------------

  Future<ExamReport> getExamReport(String examId) async {
    final response = await _api.get('/api/admin/exams/$examId/report');
    return ExamReport.fromJson(response.asMap);
  }

  Future<List<AppUser>> listStudents() async {
    final response = await _api.get('/api/admin/students');
    final raw = response.asMap['students'];
    if (raw is! List) return const <AppUser>[];
    return raw.whereType<Map<String, dynamic>>().map(AppUser.fromJson).toList();
  }

  /// One student's attempts, for the admin drill-down.
  Future<({AppUser student, List<AttemptRow> attempts})> getStudentAttempts(
    String studentId,
  ) async {
    final response = await _api.get('/api/admin/students/$studentId/attempts');
    final data = response.asMap;
    final raw = data['attempts'];

    return (
      student: AppUser.fromJson(data['student'] as Map<String, dynamic>? ?? const {}),
      attempts: raw is List
          ? raw.whereType<Map<String, dynamic>>().map(AttemptRow.fromJson).toList()
          : const <AttemptRow>[],
    );
  }
}
