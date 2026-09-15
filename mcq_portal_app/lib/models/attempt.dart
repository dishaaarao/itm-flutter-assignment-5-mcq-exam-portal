/// Per-question outcome in a graded result.
class BreakdownRow {
  const BreakdownRow({
    required this.questionId,
    required this.questionNo,
    required this.question,
    required this.status,
    required this.isCorrect,
    required this.marksAwarded,
    this.yourAnswer,
    this.correctAnswer,
  });

  final String questionId;
  final int questionNo;
  final String question;
  final String status; // correct | wrong | unattempted
  final bool isCorrect;
  final num marksAwarded;
  final String? yourAnswer;
  final String? correctAnswer;

  bool get wasAttempted => status != 'unattempted';

  factory BreakdownRow.fromJson(Map<String, dynamic> json) {
    return BreakdownRow(
      questionId: json['questionId'] as String? ?? '',
      questionNo: (json['questionNo'] as num?)?.toInt() ?? 0,
      question: json['question'] as String? ?? '',
      status: json['status'] as String? ?? 'unattempted',
      isCorrect: json['isCorrect'] as bool? ?? false,
      marksAwarded: json['marksAwarded'] as num? ?? 0,
      yourAnswer: json['yourAnswer'] as String?,
      correctAnswer: json['correctAnswer'] as String?,
    );
  }
}

/// The graded outcome of one attempt, exactly as the server computed it.
class AttemptResult {
  const AttemptResult({
    required this.totalQuestions,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.unattempted,
    required this.score,
    required this.totalMarks,
    required this.percentage,
    required this.status,
    required this.grade,
    required this.breakdown,
  });

  final int totalQuestions;
  final int attempted;
  final int correct;
  final int wrong;
  final int unattempted;
  final num score;
  final num totalMarks;
  final num percentage;
  final String status; // PASS | FAIL
  final String grade;
  final List<BreakdownRow> breakdown;

  bool get isPass => status == 'PASS';
  bool get isNegative => score < 0;

  /// 0..1, for the progress bar. Clamped because a negative-marked score can
  /// fall below zero and a bar cannot be drawn with a negative width.
  double get progress {
    if (totalMarks <= 0) return 0;
    final ratio = score / totalMarks;
    return ratio.clamp(0.0, 1.0).toDouble();
  }

  factory AttemptResult.fromJson(Map<String, dynamic> json) {
    final rawBreakdown = json['breakdown'];
    return AttemptResult(
      totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 0,
      attempted: (json['attempted'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      wrong: (json['wrong'] as num?)?.toInt() ?? 0,
      unattempted: (json['unattempted'] as num?)?.toInt() ?? 0,
      score: json['score'] as num? ?? 0,
      totalMarks: json['totalMarks'] as num? ?? 0,
      percentage: json['percentage'] as num? ?? 0,
      status: json['status'] as String? ?? 'FAIL',
      grade: json['grade'] as String? ?? '-',
      breakdown: rawBreakdown is List
          ? rawBreakdown
              .whereType<Map<String, dynamic>>()
              .map(BreakdownRow.fromJson)
              .toList()
          : const <BreakdownRow>[],
    );
  }
}

/// The submit response, and also the shape returned when reading a stored
/// result — the two must agree, and the server stores what it graded.
class AttemptSubmission {
  const AttemptSubmission({
    required this.attemptId,
    required this.examTitle,
    required this.autoSubmitted,
    required this.timeTakenSeconds,
    required this.durationSeconds,
    required this.result,
    this.subject,
  });

  final String attemptId;
  final String examTitle;
  final bool autoSubmitted;
  final int timeTakenSeconds;
  final int durationSeconds;
  final AttemptResult result;
  final String? subject;

  factory AttemptSubmission.fromJson(Map<String, dynamic> json) {
    final rawExam = json['exam'] as Map<String, dynamic>?;
    return AttemptSubmission(
      attemptId: json['attemptId'] as String? ?? '',
      examTitle: json['examTitle'] as String? ?? '',
      autoSubmitted: json['autoSubmitted'] as bool? ?? false,
      timeTakenSeconds: (json['timeTakenSeconds'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      subject: rawExam?['subject'] as String?,
      result: AttemptResult.fromJson(
        json['result'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }
}

/// One row of attempt history, and one row of the admin report. The server
/// returns the same flat shape for both.
class AttemptRow {
  const AttemptRow({
    required this.attemptId,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.status,
    required this.autoSubmitted,
    this.examId,
    this.examTitle,
    this.startedAt,
    this.submittedAt,
    this.score,
    this.totalMarks,
    this.percentage,
    this.grade,
    this.passStatus,
    this.correct,
    this.wrong,
    this.unattempted,
    this.timeTakenSeconds,
  });

  final String attemptId;
  final String studentId;
  final String studentName;
  final String studentEmail;
  final String status;
  final bool autoSubmitted;
  final String? examId;

  /// Snapshotted on the attempt, so it survives the exam being renamed.
  final String? examTitle;
  final String? startedAt;
  final String? submittedAt;
  final num? score;
  final num? totalMarks;
  final num? percentage;
  final String? grade;
  final String? passStatus;
  final int? correct;
  final int? wrong;
  final int? unattempted;
  final int? timeTakenSeconds;

  bool get isSubmitted => status == 'submitted';
  bool get isPass => passStatus == 'PASS';

  factory AttemptRow.fromJson(Map<String, dynamic> json) {
    return AttemptRow(
      attemptId: json['attemptId'] as String? ?? '',
      examId: json['examId'] as String?,
      examTitle: json['examTitle'] as String?,
      studentId: json['studentId'] as String? ?? '',
      studentName: json['studentName'] as String? ?? '',
      studentEmail: json['studentEmail'] as String? ?? '',
      status: json['status'] as String? ?? '',
      autoSubmitted: json['autoSubmitted'] as bool? ?? false,
      startedAt: json['startedAt'] as String?,
      submittedAt: json['submittedAt'] as String?,
      score: json['score'] as num?,
      totalMarks: json['totalMarks'] as num?,
      percentage: json['percentage'] as num?,
      grade: json['grade'] as String?,
      passStatus: json['passStatus'] as String?,
      correct: (json['correct'] as num?)?.toInt(),
      wrong: (json['wrong'] as num?)?.toInt(),
      unattempted: (json['unattempted'] as num?)?.toInt(),
      timeTakenSeconds: (json['timeTakenSeconds'] as num?)?.toInt(),
    );
  }
}

/// Aggregate statistics for one exam, shown above the report table.
class ReportSummary {
  const ReportSummary({
    required this.studentsAttempted,
    required this.submitted,
    required this.graded,
    required this.passCount,
    required this.failCount,
    this.topperName,
    this.topperScore,
    this.averageScore,
    this.averagePercentage,
    this.highestScore,
    this.lowestScore,
    this.passPercentage,
  });

  final int studentsAttempted;
  final int submitted;
  final int graded;
  final int passCount;
  final int failCount;
  final String? topperName;
  final num? topperScore;
  final num? averageScore;
  final num? averagePercentage;
  final num? highestScore;
  final num? lowestScore;
  final num? passPercentage;

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    final topper = json['topper'] as Map<String, dynamic>?;
    return ReportSummary(
      studentsAttempted: (json['studentsAttempted'] as num?)?.toInt() ?? 0,
      submitted: (json['submitted'] as num?)?.toInt() ?? 0,
      graded: (json['graded'] as num?)?.toInt() ?? 0,
      passCount: (json['passCount'] as num?)?.toInt() ?? 0,
      failCount: (json['failCount'] as num?)?.toInt() ?? 0,
      topperName: topper?['studentName'] as String?,
      topperScore: topper?['score'] as num?,
      averageScore: json['averageScore'] as num?,
      averagePercentage: json['averagePercentage'] as num?,
      highestScore: json['highestScore'] as num?,
      lowestScore: json['lowestScore'] as num?,
      passPercentage: json['passPercentage'] as num?,
    );
  }
}

/// The full admin report for one exam.
class ExamReport {
  const ExamReport({
    required this.examId,
    required this.examTitle,
    required this.summary,
    required this.rows,
  });

  final String examId;
  final String examTitle;
  final ReportSummary summary;
  final List<AttemptRow> rows;

  factory ExamReport.fromJson(Map<String, dynamic> json) {
    final rawExam = json['exam'] as Map<String, dynamic>? ?? const {};
    final rawRows = json['rows'];

    return ExamReport(
      examId: rawExam['id'] as String? ?? '',
      examTitle: rawExam['title'] as String? ?? '',
      summary: ReportSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      rows: rawRows is List
          ? rawRows.whereType<Map<String, dynamic>>().map(AttemptRow.fromJson).toList()
          : const <AttemptRow>[],
    );
  }
}
