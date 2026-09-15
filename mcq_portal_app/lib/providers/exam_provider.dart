import 'package:flutter/foundation.dart';

import '../models/attempt.dart';
import '../models/exam.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';

/// Exam lists for both roles, plus admin exam management.
///
/// Kept separate from the live attempt state: browsing a catalogue and sitting
/// an exam have completely different lifecycles, and mixing them means a
/// refreshed list can clobber a paper in progress.
class ExamProvider extends ChangeNotifier {
  ExamProvider(this._services);

  final AppServices _services;

  List<Exam> _studentExams = const [];
  List<Exam> _adminExams = const [];
  bool _loading = false;
  String? _error;

  List<Exam> get studentExams => _studentExams;
  List<Exam> get adminExams => _adminExams;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasError => _error != null;

  Future<void> loadStudentExams() => _load(() async {
        _studentExams = await _services.exams.listStudentExams();
      });

  Future<void> loadAdminExams() => _load(() async {
        _adminExams = await _services.exams.listAllExams();
      });

  Future<void> _load(Future<void> Function() action) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await action();
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Could not load exams.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Deletes an exam and refreshes the list. Returns null on success, or the
  /// message to show the admin on failure.
  Future<String?> deleteExam(String examId) async {
    try {
      final message = await _services.exams.deleteExam(examId);
      await loadAdminExams();
      return message;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  Future<ExamReport?> loadReport(String examId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      return await _services.attempts.getExamReport(examId);
    } on ApiException catch (error) {
      _error = error.message;
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
