import 'question.dart';

/// A student's existing attempt on an exam, as summarised in the exam list.
class AttemptBrief {
  const AttemptBrief({
    required this.id,
    required this.status,
    this.submittedAt,
    this.score,
    this.percentage,
    this.passStatus,
  });

  final String id;
  final String status;
  final String? submittedAt;
  final num? score;
  final num? percentage;
  final String? passStatus;

  bool get isInProgress => status == 'in_progress';
  bool get isSubmitted => status == 'submitted';
  bool get isPass => passStatus == 'PASS';

  factory AttemptBrief.fromJson(Map<String, dynamic> json) {
    return AttemptBrief(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      submittedAt: json['submittedAt'] as String?,
      score: json['score'] as num?,
      percentage: json['percentage'] as num?,
      passStatus: json['passStatus'] as String?,
    );
  }
}

/// One exam as it appears in the student's list. Never carries questions.
class Exam {
  const Exam({
    required this.id,
    required this.title,
    required this.subject,
    required this.duration,
    required this.totalMarks,
    required this.passingMarks,
    required this.negativeMarking,
    required this.questionCount,
    this.description = '',
    this.imageUrl,
    this.startDate,
    this.endDate,
    this.myAttempt,
  });

  final String id;
  final String title;
  final String subject;
  final String description;
  final int duration;
  final num totalMarks;
  final num passingMarks;
  final num negativeMarking;
  final int questionCount;
  final String? imageUrl;
  final String? startDate;
  final String? endDate;
  final AttemptBrief? myAttempt;

  bool get isAvailable => myAttempt == null;
  bool get hasNegativeMarking => negativeMarking > 0;

  factory Exam.fromJson(Map<String, dynamic> json) {
    final attempt = json['myAttempt'];
    return Exam(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      description: json['description'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      totalMarks: json['totalMarks'] as num? ?? 0,
      passingMarks: json['passingMarks'] as num? ?? 0,
      negativeMarking: json['negativeMarking'] as num? ?? 0,
      questionCount: (json['questionCount'] as num?)?.toInt() ?? 0,
      imageUrl: json['imageUrl'] as String?,
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      myAttempt: attempt is Map<String, dynamic> ? AttemptBrief.fromJson(attempt) : null,
    );
  }
}

/// The response to starting or resuming an exam: the paper, the clock, and the
/// attempt it belongs to.
class ExamSession {
  const ExamSession({
    required this.exam,
    required this.questions,
    required this.remainingSeconds,
    required this.durationSeconds,
    required this.attemptId,
    required this.resumed,
    this.savedAnswers = const <String, String>{},
  });

  final Exam exam;
  final List<Question> questions;
  final int remainingSeconds;
  final int durationSeconds;
  final String attemptId;
  final bool resumed;

  /// Answers already stored on the server, restored when resuming.
  final Map<String, String> savedAnswers;

  factory ExamSession.fromJson(Map<String, dynamic> json) {
    final rawExam = json['exam'] as Map<String, dynamic>? ?? const {};
    final rawAttempt = json['attempt'] as Map<String, dynamic>? ?? const {};
    final rawQuestions = json['questions'];

    final rawAnswers = rawAttempt['answers'];

    return ExamSession(
      exam: Exam.fromJson(rawExam),
      questions: rawQuestions is List
          ? rawQuestions
              .whereType<Map<String, dynamic>>()
              .map(Question.fromJson)
              .toList()
          : const <Question>[],
      remainingSeconds: (json['remainingSeconds'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      attemptId: rawAttempt['id'] as String? ?? '',
      resumed: rawAttempt['resumed'] as bool? ?? false,
      savedAnswers: rawAnswers is Map
          ? rawAnswers.map((key, value) => MapEntry(key.toString(), value.toString()))
          : const <String, String>{},
    );
  }
}

/// An exam plus its answer key — the admin-only view.
class AdminExamDetail {
  const AdminExamDetail({required this.exam, required this.questions});

  final Exam exam;
  final List<AdminQuestion> questions;

  factory AdminExamDetail.fromJson(Map<String, dynamic> json) {
    final rawExam = json['exam'] as Map<String, dynamic>? ?? const {};
    final rawQuestions = json['questions'];

    return AdminExamDetail(
      exam: Exam.fromJson(rawExam),
      questions: rawQuestions is List
          ? rawQuestions
              .whereType<Map<String, dynamic>>()
              .map(AdminQuestion.fromJson)
              .toList()
          : const <AdminQuestion>[],
    );
  }
}

/// A question including its correct answer. Only ever built from an admin
/// endpoint that already required the admin role.
class AdminQuestion extends Question {
  const AdminQuestion({
    required super.id,
    required super.questionNo,
    required super.question,
    required super.options,
    required this.correctAnswer,
    super.imageUrl,
  });

  final String correctAnswer;

  factory AdminQuestion.fromJson(Map<String, dynamic> json) {
    final base = Question.fromJson(json);
    return AdminQuestion(
      id: base.id,
      questionNo: base.questionNo,
      question: base.question,
      options: base.options,
      imageUrl: base.imageUrl,
      correctAnswer: json['correctAnswer'] as String? ?? '',
    );
  }
}
