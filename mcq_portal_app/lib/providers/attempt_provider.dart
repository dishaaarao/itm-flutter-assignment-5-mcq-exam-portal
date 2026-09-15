import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/attempt.dart';
import '../models/exam.dart';
import '../models/question.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';

enum SessionStatus { idle, loading, active, submitting, submitted, failed }

/// How a question appears in the palette.
enum PaletteState { unanswered, answered, markedForReview, answeredAndMarked }

/// The live exam: the paper, the answers, the clock, and the submission.
///
/// This is the state a student can lose work to, so the design rules are:
/// answers are held in memory as they are tapped, the countdown is derived from
/// a wall-clock deadline rather than a decrementing counter, and exactly one
/// submit is ever in flight.
class AttemptProvider extends ChangeNotifier {
  AttemptProvider(this._services);

  final AppServices _services;

  static const Duration _tickInterval = Duration(seconds: 1);

  SessionStatus _status = SessionStatus.idle;
  ExamSession? _session;
  AttemptSubmission? _submission;

  int _currentIndex = 0;
  final Map<String, String> _answers = <String, String>{};
  final Set<String> _markedForReview = <String>{};

  Duration _remaining = Duration.zero;
  DateTime? _deadline;
  Timer? _timer;

  String? _error;
  bool _submitting = false;

  // --- Read-only state ----------------------------------------------------

  SessionStatus get status => _status;
  ExamSession? get session => _session;
  AttemptSubmission? get submission => _submission;
  String? get error => _error;

  List<Question> get questions => _session?.questions ?? const <Question>[];
  int get questionCount => questions.length;
  int get currentIndex => _currentIndex;
  Question? get currentQuestion =>
      questionCount == 0 || _currentIndex >= questionCount ? null : questions[_currentIndex];

  Map<String, String> get answers => Map.unmodifiable(_answers);
  Set<String> get markedForReview => Set.unmodifiable(_markedForReview);

  Duration get remaining => _remaining;
  bool get isSubmitting => _submitting || _status == SessionStatus.submitting;

  int get answeredCount => _answers.length;
  int get unansweredCount => questionCount - answeredCount;

  /// True once the countdown hits zero — input is locked from this point,
  /// because the server would only clamp the submission anyway.
  bool get timeExpired => _remaining <= Duration.zero;

  String get formattedRemaining {
    final seconds = _remaining.inSeconds.clamp(0, 86400);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  PaletteState paletteStateFor(int index) {
    if (index < 0 || index >= questionCount) return PaletteState.unanswered;

    final question = questions[index];
    final answered = _answers.containsKey(question.id);
    final marked = _markedForReview.contains(question.id);

    if (answered && marked) return PaletteState.answeredAndMarked;
    if (marked) return PaletteState.markedForReview;
    if (answered) return PaletteState.answered;
    return PaletteState.unanswered;
  }

  String? answerFor(Question question) => _answers[question.id];

  // --- Lifecycle ----------------------------------------------------------

  /// Starts or resumes the exam. Safe to call again: the server resumes the
  /// existing attempt rather than issuing a second timer.
  Future<bool> start(String examId) async {
    _status = SessionStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final session = await _services.exams.startExam(examId);

      _session = session;
      _submission = null;
      _currentIndex = 0;
      _markedForReview.clear();
      _answers
        ..clear()
        // Restore answers the server already holds, so resuming shows the
        // student their previous selections instead of a blank paper.
        ..addAll(session.savedAnswers);

      _deadline = DateTime.now().add(Duration(seconds: session.remainingSeconds));
      _remaining = Duration(seconds: session.remainingSeconds);

      _status = SessionStatus.active;
      _startTimer();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      _status = SessionStatus.failed;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Could not start the exam.';
      _status = SessionStatus.failed;
      notifyListeners();
      return false;
    }
  }

  void goTo(int index) {
    if (index < 0 || index >= questionCount) return;
    _currentIndex = index;
    notifyListeners();
  }

  void next() => goTo(_currentIndex + 1);
  void previous() => goTo(_currentIndex - 1);

  /// Selects [letter] for [question]. Selecting the current answer again clears
  /// it, which is how a student un-answers a question.
  void selectAnswer(Question question, String letter) {
    if (_status != SessionStatus.active || timeExpired) return;

    if (_answers[question.id] == letter) {
      _answers.remove(question.id);
    } else {
      _answers[question.id] = letter;
    }
    notifyListeners();
  }

  void clearAnswer(Question question) {
    if (_answers.remove(question.id) != null) notifyListeners();
  }

  void toggleMarkForReview(Question question) {
    if (_markedForReview.contains(question.id)) {
      _markedForReview.remove(question.id);
    } else {
      _markedForReview.add(question.id);
    }
    notifyListeners();
  }

  // --- Timer --------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  /// Recomputes the remaining time from the deadline rather than subtracting a
  /// second. A periodic timer that fires late — a busy frame, or an app that
  /// was backgrounded — would otherwise let the displayed clock drift away from
  /// the server's, which is the clock that decides when the exam ends.
  void _tick() {
    final deadline = _deadline;
    if (deadline == null) return;

    final left = deadline.difference(DateTime.now());
    _remaining = left.isNegative ? Duration.zero : left;

    if (_remaining <= Duration.zero) {
      _timer?.cancel();
      _timer = null;
      notifyListeners();
      // The server grades a late submit and flags it; the student's answers are
      // not thrown away. Waiting here would only make it later.
      unawaited(submit(auto: true));
      return;
    }

    notifyListeners();
  }

  // --- Submission ---------------------------------------------------------

  /// Sends the answers for grading.
  ///
  /// Guarded so only one submit is ever in flight: the timer firing at the same
  /// moment the student taps Submit must not produce two requests, the second
  /// of which the server would reject as a duplicate.
  Future<bool> submit({bool auto = false}) async {
    final session = _session;
    if (session == null || _submitting) return false;
    if (_status == SessionStatus.submitted) return true;

    _submitting = true;
    _status = SessionStatus.submitting;
    _error = null;
    _timer?.cancel();
    _timer = null;
    notifyListeners();

    try {
      final submission = await _services.attempts.submit(
        attemptId: session.attemptId,
        answers: Map<String, String>.from(_answers),
      );

      _submission = submission;
      _status = SessionStatus.submitted;
      return true;
    } on ApiException catch (error) {
      // A duplicate-submit conflict means the server already has this attempt
      // graded; fetch that rather than showing the student an error for
      // something that actually succeeded.
      if (error.isConflict) {
        final recovered = await _recoverSubmission(session.attemptId);
        if (recovered) return true;
      }

      _error = auto
          ? 'Time ran out and the automatic submission failed: ${error.message}'
          : error.message;
      _status = SessionStatus.failed;
      // Put the paper back so the student can retry rather than losing it.
      if (!auto) {
        _status = SessionStatus.active;
        _resumeTimerIfTimeRemains();
      }
      return false;
    } catch (_) {
      _error = 'Could not submit your answers. Please try again.';
      _status = SessionStatus.active;
      _resumeTimerIfTimeRemains();
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<bool> _recoverSubmission(String attemptId) async {
    try {
      _submission = await _services.attempts.getResult(attemptId);
      _status = SessionStatus.submitted;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _resumeTimerIfTimeRemains() {
    if (_deadline == null) return;
    if (_deadline!.difference(DateTime.now()).isNegative) return;
    _startTimer();
  }

  /// Discards the in-memory session, for leaving the exam screen.
  ///
  /// Does not touch the server: an attempt left in progress is resumed by the
  /// next start call, with its original deadline intact.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _session = null;
    _submission = null;
    _answers.clear();
    _markedForReview.clear();
    _currentIndex = 0;
    _remaining = Duration.zero;
    _deadline = null;
    _error = null;
    _status = SessionStatus.idle;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
