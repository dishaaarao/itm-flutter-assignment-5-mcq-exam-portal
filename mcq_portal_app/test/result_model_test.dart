import 'package:flutter_test/flutter_test.dart';
import 'package:mcq_portal_app/models/attempt.dart';
import 'package:mcq_portal_app/models/exam.dart';
import 'package:mcq_portal_app/models/question.dart';
import 'package:mcq_portal_app/models/user.dart';

/// Model-level tests.
///
/// The client is never trusted with grading, so these do not re-check any
/// arithmetic the server owns. They cover the parts this app *is* responsible
/// for: turning the server's payload into state correctly, and not falling over
/// on the figures it can legitimately receive — a clamped progress ring, a
/// below-zero score, a resumed session's saved answers.
void main() {
  group('AttemptResult', () {
    Map<String, dynamic> resultJson({
      num score = 22,
      num totalMarks = 40,
      num percentage = 55,
      String status = 'PASS',
      String grade = 'C',
    }) {
      return {
        'totalQuestions': 4,
        'attempted': 4,
        'correct': 2,
        'wrong': 2,
        'unattempted': 0,
        'score': score,
        'totalMarks': totalMarks,
        'percentage': percentage,
        'status': status,
        'grade': grade,
        'breakdown': [
          {
            'questionId': 'q1',
            'questionNo': 1,
            'question': 'What is 2 + 2?',
            'status': 'correct',
            'isCorrect': true,
            'marksAwarded': 10,
            'yourAnswer': 'B',
            'correctAnswer': 'B',
          },
        ],
      };
    }

    test('maps every field the result screen renders', () {
      final result = AttemptResult.fromJson(resultJson());

      expect(result.totalQuestions, 4);
      expect(result.correct, 2);
      expect(result.wrong, 2);
      expect(result.unattempted, 0);
      expect(result.score, 22);
      expect(result.totalMarks, 40);
      expect(result.percentage, 55);
      expect(result.grade, 'C');
      expect(result.isPass, isTrue);
    });

    test('progress is the score as a fraction of the total', () {
      final result = AttemptResult.fromJson(resultJson(score: 20, totalMarks: 40));

      expect(result.progress, 0.5);
    });

    test('a negative-marked score clamps progress to zero rather than going negative', () {
      // Negative marking can drive the score below zero, and a CircularProgress
      // indicator cannot be drawn with a negative value.
      final result = AttemptResult.fromJson(resultJson(score: -50, percentage: -125));

      expect(result.score, -50);
      expect(result.isNegative, isTrue);
      expect(result.progress, 0.0);
    });

    test('progress clamps at one when the score exceeds the paper', () {
      final result = AttemptResult.fromJson(resultJson(score: 60, totalMarks: 40));

      expect(result.progress, 1.0);
    });

    test('a zero-mark paper does not divide by zero', () {
      final result = AttemptResult.fromJson(resultJson(score: 0, totalMarks: 0));

      expect(result.progress, 0.0);
    });

    test('a failing result reads as a failure', () {
      final result = AttemptResult.fromJson(resultJson(status: 'FAIL', grade: 'F'));

      expect(result.isPass, isFalse);
    });

    test('an empty payload degrades to a safe default instead of throwing', () {
      final result = AttemptResult.fromJson(const <String, dynamic>{});

      expect(result.totalQuestions, 0);
      expect(result.score, 0);
      expect(result.status, 'FAIL');
      expect(result.breakdown, isEmpty);
    });

    test('breakdown rows distinguish attempted from skipped', () {
      final result = AttemptResult.fromJson({
        ...resultJson(),
        'breakdown': [
          {
            'questionId': 'q1',
            'questionNo': 1,
            'question': 'Answered',
            'status': 'wrong',
            'isCorrect': false,
            'marksAwarded': -2.5,
            'yourAnswer': 'A',
            'correctAnswer': 'C',
          },
          {
            'questionId': 'q2',
            'questionNo': 2,
            'question': 'Skipped',
            'status': 'unattempted',
            'isCorrect': false,
            'marksAwarded': 0,
          },
        ],
      });

      expect(result.breakdown[0].wasAttempted, isTrue);
      expect(result.breakdown[0].marksAwarded, -2.5);
      expect(result.breakdown[0].yourAnswer, 'A');
      expect(result.breakdown[1].wasAttempted, isFalse);
      expect(result.breakdown[1].yourAnswer, isNull);
    });
  });

  group('ExamSession', () {
    test('restores the answers the server already holds', () {
      final session = ExamSession.fromJson({
        'exam': {'id': 'e1', 'title': 'Midterm', 'subject': 'Maths', 'duration': 30},
        'attempt': {
          'id': 'a1',
          'status': 'in_progress',
          'resumed': true,
          'answers': {'q1': 'B', 'q2': 'A'},
        },
        'remainingSeconds': 900,
        'durationSeconds': 1800,
        'questions': [
          {
            'id': 'q1',
            'questionNo': 1,
            'question': 'Question one',
            'options': ['one', 'two', 'three', 'four'],
          },
        ],
      });

      expect(session.attemptId, 'a1');
      expect(session.resumed, isTrue);
      expect(session.remainingSeconds, 900);
      expect(session.savedAnswers, {'q1': 'B', 'q2': 'A'});
      expect(session.questions, hasLength(1));
      expect(session.questions.first.options, ['one', 'two', 'three', 'four']);
    });

    test('a fresh attempt has no saved answers', () {
      final session = ExamSession.fromJson({
        'exam': {'id': 'e1'},
        'attempt': {'id': 'a1', 'resumed': false},
        'remainingSeconds': 60,
        'questions': const <Map<String, dynamic>>[],
      });

      expect(session.savedAnswers, isEmpty);
      expect(session.resumed, isFalse);
      expect(session.questions, isEmpty);
    });

    test('a leaked answer key never reaches the student-facing question type', () {
      // Belt and braces: the server is asserted to strip this field, but if it
      // ever did not, the client model still has nowhere to put it and the
      // served question must not become the answer-bearing admin type.
      final session = ExamSession.fromJson({
        'exam': {'id': 'e1'},
        'attempt': {'id': 'a1'},
        'remainingSeconds': 60,
        'questions': [
          {
            'id': 'q1',
            'questionNo': 1,
            'question': 'Leaky?',
            'options': ['a', 'b', 'c', 'd'],
            'correctAnswer': 'C',
          },
        ],
      });

      final question = session.questions.single;
      expect(question, isNot(isA<AdminQuestion>()));
      expect(question.options, ['a', 'b', 'c', 'd']);
    });
  });

  group('Exam', () {
    test('reads the student brief attached to an exam', () {
      final exam = Exam.fromJson({
        'id': 'e1',
        'title': 'Midterm',
        'subject': 'Maths',
        'duration': 30,
        'totalMarks': 40,
        'passingMarks': 16,
        'negativeMarking': 0.25,
        'questionCount': 4,
        'myAttempt': {
          'id': 'a1',
          'status': 'submitted',
          'score': 17.5,
          'percentage': 43.75,
          'passStatus': 'PASS',
        },
      });

      expect(exam.hasNegativeMarking, isTrue);
      expect(exam.isAvailable, isFalse);
      expect(exam.myAttempt!.isSubmitted, isTrue);
      expect(exam.myAttempt!.isPass, isTrue);
      expect(exam.myAttempt!.isInProgress, isFalse);
    });

    test('an exam with no attempt is available', () {
      final exam = Exam.fromJson({
        'id': 'e1',
        'title': 'Midterm',
        'subject': 'Maths',
        'duration': 30,
        'totalMarks': 40,
        'passingMarks': 16,
        'negativeMarking': 0,
        'questionCount': 4,
      });

      expect(exam.isAvailable, isTrue);
      expect(exam.hasNegativeMarking, isFalse);
    });
  });

  group('Question', () {
    test('letters map to positions and stop at the end of the alphabet', () {
      expect(Question.letterFor(0), 'A');
      expect(Question.letterFor(3), 'D');
      expect(Question.letterFor(4), '?');
      expect(Question.letterFor(-1), '?');
    });

    test('finds the letter for an option by its text', () {
      const question = Question(
        id: 'q1',
        questionNo: 1,
        question: 'Pick one',
        options: ['first', 'second', 'third', 'fourth'],
      );

      expect(question.letterForOption('third'), 'C');
      expect(question.letterForOption('absent'), isNull);
      expect(question.letterForOption(null), isNull);
    });
  });

  group('AttemptRow', () {
    test('carries the snapshotted exam title and the auto-submit flag', () {
      final row = AttemptRow.fromJson({
        'attemptId': 'a1',
        'examId': 'e1',
        'examTitle': 'Midterm',
        'studentId': 's1',
        'studentName': 'Sayuj Pillai',
        'studentEmail': 'sayuj@example.com',
        'status': 'submitted',
        'autoSubmitted': true,
        'score': 17.5,
        'totalMarks': 40,
        'percentage': 43.75,
        'grade': 'D',
        'passStatus': 'PASS',
      });

      expect(row.examTitle, 'Midterm');
      expect(row.autoSubmitted, isTrue);
      expect(row.isSubmitted, isTrue);
      expect(row.isPass, isTrue);
      expect(row.grade, 'D');
    });

    test('a missing score stays null rather than becoming zero', () {
      // An attempt still in progress has no score, and showing 0 would
      // misreport a student who has not finished.
      final row = AttemptRow.fromJson({
        'attemptId': 'a1',
        'studentId': 's1',
        'studentName': 'Sayuj Pillai',
        'studentEmail': 'sayuj@example.com',
        'status': 'in_progress',
        'autoSubmitted': false,
      });

      expect(row.score, isNull);
      expect(row.isSubmitted, isFalse);
      expect(row.isPass, isFalse);
    });
  });

  group('AppUser', () {
    test('initials come from the first two words', () {
      expect(
        const AppUser(id: '1', name: 'Sayuj Pillai', email: 'a@b.c', role: 'student').initials,
        'SP',
      );
      expect(
        const AppUser(id: '1', name: 'Sayuj', email: 'a@b.c', role: 'student').initials,
        'S',
      );
      expect(
        const AppUser(id: '1', name: '  ', email: 'a@b.c', role: 'student').initials,
        '?',
      );
    });

    test('role decides who is an admin', () {
      expect(
        const AppUser(id: '1', name: 'A', email: 'a@b.c', role: 'admin').isAdmin,
        isTrue,
      );
      expect(
        const AppUser(id: '1', name: 'A', email: 'a@b.c', role: 'student').isAdmin,
        isFalse,
      );
    });
  });

  group('ExamReport', () {
    test('reads the aggregate and its rows', () {
      final report = ExamReport.fromJson({
        'exam': {'id': 'e1', 'title': 'Midterm'},
        'summary': {
          'studentsAttempted': 3,
          'submitted': 2,
          'graded': 2,
          'passCount': 1,
          'failCount': 1,
          'averageScore': 21.25,
          'averagePercentage': 53.13,
          'highestScore': 30,
          'lowestScore': 12.5,
          'passPercentage': 50,
          'topper': {'studentName': 'Sayuj Pillai', 'score': 30},
        },
        'rows': [
          {
            'attemptId': 'a1',
            'studentId': 's1',
            'studentName': 'Sayuj Pillai',
            'studentEmail': 'sayuj@example.com',
            'status': 'submitted',
            'autoSubmitted': false,
            'score': 30,
            'passStatus': 'PASS',
          },
        ],
      });

      expect(report.examTitle, 'Midterm');
      expect(report.summary.studentsAttempted, 3);
      expect(report.summary.topperName, 'Sayuj Pillai');
      expect(report.summary.topperScore, 30);
      expect(report.summary.passPercentage, 50);
      expect(report.rows, hasLength(1));
      expect(report.rows.single.studentName, 'Sayuj Pillai');
    });

    test('an exam nobody has sat reports empty aggregates, not zeros', () {
      final report = ExamReport.fromJson({
        'exam': {'id': 'e1', 'title': 'Midterm'},
        'summary': {
          'studentsAttempted': 0,
          'submitted': 0,
          'graded': 0,
          'passCount': 0,
          'failCount': 0,
          'averageScore': null,
          'highestScore': null,
          'topper': null,
        },
        'rows': const <Map<String, dynamic>>[],
      });

      expect(report.summary.averageScore, isNull);
      expect(report.summary.topperName, isNull);
      expect(report.rows, isEmpty);
    });
  });
}
