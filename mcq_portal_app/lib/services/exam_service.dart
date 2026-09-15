import '../models/exam.dart';
import 'api_client.dart';

/// Exam endpoints for both roles. The admin routes require an admin token —
/// the server enforces it, this client just does not pretend otherwise.
class ExamService {
  ExamService(this._api);

  final ApiClient _api;

  // --- Student ------------------------------------------------------------

  /// Published exams inside their date window, annotated with this student's
  /// attempt state. Contains no questions.
  Future<List<Exam>> listStudentExams() async {
    final response = await _api.get('/api/student/exams');
    return _examsFrom(response.asMap['exams']);
  }

  /// Starts an exam, or resumes the attempt already in progress.
  Future<ExamSession> startExam(String examId) async {
    final response = await _api.get('/api/student/exams/$examId/start');
    return ExamSession.fromJson(response.asMap);
  }

  // --- Admin --------------------------------------------------------------

  Future<List<Exam>> listAllExams() async {
    final response = await _api.get('/api/admin/exams');
    return _examsFrom(response.asMap['exams']);
  }

  /// One exam including its answer key. Admin only.
  Future<AdminExamDetail> getExam(String examId) async {
    final response = await _api.get('/api/admin/exams/$examId');
    return AdminExamDetail.fromJson(response.asMap);
  }

  /// Create an exam from an uploaded spreadsheet.
  ///
  /// Returns the created exam plus which rows were skipped, so the admin can
  /// fix a typo and re-upload rather than discovering the gap later.
  Future<({Exam exam, int imported, List<String> skippedRows})> createExam({
    required List<int> fileBytes,
    required String filename,
    required String title,
    required String subject,
    required String duration,
    required String totalMarks,
    required String passingMarks,
    String description = '',
    String negativeMarking = '0',
    String startDate = '',
    String endDate = '',
  }) async {
    final response = await _api.upload(
      '/api/admin/exams',
      field: 'sheet',
      bytes: fileBytes,
      filename: filename,
      fields: {
        'title': title,
        'subject': subject,
        'description': description,
        'duration': duration,
        'totalMarks': totalMarks,
        'passingMarks': passingMarks,
        'negativeMarking': negativeMarking,
        if (startDate.isNotEmpty) 'startDate': startDate,
        if (endDate.isNotEmpty) 'endDate': endDate,
      },
    );

    final data = response.asMap;
    final rawSkipped = data['skippedRows'];

    return (
      exam: Exam.fromJson(data['exam'] as Map<String, dynamic>? ?? const {}),
      imported: (data['imported'] as num?)?.toInt() ?? 0,
      // The server sends these in the top-level `errors` list; either source
      // produces the same human-readable lines.
      skippedRows: response.errors.isNotEmpty
          ? response.errors
          : rawSkipped is List
              ? rawSkipped
                  .whereType<Map<String, dynamic>>()
                  .map((row) => 'Row ${row['row']}: ${row['reason']}')
                  .toList()
              : const <String>[],
    );
  }

  Future<Exam> updateExam(String examId, Map<String, dynamic> patch) async {
    final response = await _api.put('/api/admin/exams/$examId', body: patch);
    return Exam.fromJson(response.asMap['exam'] as Map<String, dynamic>? ?? const {});
  }

  /// Deletes the exam and everything hanging off it. Returns the server's
  /// summary of what was removed.
  Future<String> deleteExam(String examId) async {
    final response = await _api.delete('/api/admin/exams/$examId');
    return response.message ?? 'Exam deleted.';
  }

  List<Exam> _examsFrom(dynamic raw) {
    if (raw is! List) return const <Exam>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Exam.fromJson)
        .toList(growable: false);
  }
}
