const { config } = require('../config/env');
const HttpError = require('../utils/HttpError');
const examModel = require('../models/examModel');
const questionModel = require('../models/questionModel');
const attemptModel = require('../models/attemptModel');
const { finaliseAttempt } = require('./attemptController');

/**
 * Student-facing exam endpoints.
 *
 * The two things that must not go wrong here: the answer key never leaves the
 * server, and the timer is measured by the server rather than reported by the
 * client.
 */

/** Where the exam is in its lifecycle, from the student's point of view. */
function closedReasonMessage(reason) {
  switch (reason) {
    case 'unpublished':
      return 'This exam has not been published yet.';
    case 'not-started':
      return 'This exam has not opened yet.';
    case 'closed':
      return 'This exam has closed.';
    default:
      return 'This exam is not available.';
  }
}

/**
 * Published exams inside their date window, each annotated with this student's
 * attempt state so the list can offer "Start", "Resume" or "View result"
 * without a second request per row. Never includes questions.
 */
async function listExams(req, res, next) {
  try {
    const exams = await examModel.listAvailableForStudent();
    const myAttempts = await attemptModel.listByStudent(req.user.id);

    const byExam = new Map();
    myAttempts.forEach((attempt) => {
      const current = byExam.get(attempt.examId);
      // Prefer an in-progress attempt; otherwise the most recent submitted one.
      if (!current) byExam.set(attempt.examId, attempt);
      else if (current.status !== attemptModel.STATUS.IN_PROGRESS
        && attempt.status === attemptModel.STATUS.IN_PROGRESS) {
        byExam.set(attempt.examId, attempt);
      }
    });

    const rows = exams.map((exam) => {
      const mine = byExam.get(exam.id) || null;
      return {
        id: exam.id,
        title: exam.title,
        subject: exam.subject,
        description: exam.description,
        duration: exam.duration,
        totalMarks: exam.totalMarks,
        passingMarks: exam.passingMarks,
        negativeMarking: exam.negativeMarking,
        questionCount: exam.questionCount,
        imageUrl: exam.imageUrl,
        startDate: exam.startDate,
        endDate: exam.endDate,
        myAttempt: mine
          ? {
              id: mine.id,
              status: mine.status,
              submittedAt: mine.submittedAt,
              score: mine.result?.score ?? null,
              percentage: mine.result?.percentage ?? null,
              passStatus: mine.result?.status ?? null,
            }
          : null,
      };
    });

    res.json({ success: true, count: rows.length, data: { exams: rows } });
  } catch (error) {
    next(error);
  }
}

/**
 * Begin — or resume — an attempt.
 *
 * Calling this twice does not hand out a second timer: an in-progress attempt
 * is returned as-is with its original deadline, so a page reload costs nothing
 * but a new tab cannot buy extra time.
 */
async function startExam(req, res, next) {
  try {
    const exam = await examModel.findById(req.params.id);
    if (!exam) throw HttpError.notFound('Exam not found.');

    const closed = examModel.availabilityFor(exam);
    if (closed) throw HttpError.forbidden(closedReasonMessage(closed));

    const questions = await questionModel.listByExam(exam.id);
    if (questions.length === 0) {
      throw HttpError.conflict('This exam has no questions yet. Please contact your administrator.');
    }

    const existing = await attemptModel.findInProgress(exam.id, req.user.id);

    if (existing) {
      const deadlinePassed = new Date(existing.deadline).getTime() < Date.now();

      if (!deadlinePassed) {
        return res.json({
          success: true,
          message: 'Resuming your attempt.',
          data: buildStartPayload(exam, questions, existing, { resumed: true }),
        });
      }

      // The timer expired while the student was away. Close the attempt out
      // with whatever answers were stored rather than deleting it — a graded
      // zero is recoverable information; a vanished attempt is not.
      const { attempt: closedAttempt, result } = await finaliseAttempt(existing, exam, questions, {
        forceAutoSubmit: true,
      });

      if (!config.allowReattempt) {
        throw HttpError.conflict(
          'Your previous attempt ran out of time and has been submitted. Retakes are disabled for this exam.',
        );
      }

      return res.json({
        success: true,
        message: 'Your previous attempt ran out of time and was submitted. Starting a new attempt.',
        data: buildStartPayload(exam, questions, null, {
          resumed: false,
          previousAttempt: { id: closedAttempt.id, score: result.score, autoSubmitted: true },
        }),
      });
    }

    const previous = await attemptModel.findSubmitted(exam.id, req.user.id);
    if (previous && !config.allowReattempt) {
      throw HttpError.conflict(
        'You have already submitted this exam. Retakes are disabled for this exam.',
      );
    }

    const attempt = await attemptModel.createAttempt({ exam, student: req.user });

    res.status(201).json({
      success: true,
      message: 'Attempt started. Good luck!',
      data: buildStartPayload(exam, questions, attempt, { resumed: false }),
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Assemble the start response. Questions pass through the public mapper, which
 * whitelists fields — the stored `correctAnswer` is never copied across.
 */
function buildStartPayload(exam, questions, attempt, { resumed, previousAttempt = null }) {
  const remainingSeconds = attempt
    ? Math.max(0, Math.round((new Date(attempt.deadline).getTime() - Date.now()) / 1000))
    : Number(exam.duration) * 60;

  return {
    exam: {
      id: exam.id,
      title: exam.title,
      subject: exam.subject,
      description: exam.description,
      duration: exam.duration,
      totalMarks: exam.totalMarks,
      passingMarks: exam.passingMarks,
      negativeMarking: exam.negativeMarking,
      questionCount: questions.length,
      imageUrl: exam.imageUrl,
    },
    attempt: attempt
      ? {
          id: attempt.id,
          status: attempt.status,
          startedAt: attempt.startedAt,
          deadline: attempt.deadline,
          answers: attempt.answers || {},
          resumed,
        }
      : null,
    remainingSeconds,
    durationSeconds: Number(exam.duration) * 60,
    questions: questionModel.toPublicQuestions(questions),
    ...(previousAttempt ? { previousAttempt } : {}),
  };
}

/** Sanitized question list on its own, for a client that started already. */
async function getExamQuestions(req, res, next) {
  try {
    const exam = await examModel.findById(req.params.id);
    if (!exam) throw HttpError.notFound('Exam not found.');

    const attempt = await attemptModel.findInProgress(exam.id, req.user.id);
    if (!attempt) {
      throw HttpError.conflict('Start this exam before requesting its questions.');
    }

    const questions = await questionModel.listByExam(exam.id);
    res.json({
      success: true,
      data: {
        attemptId: attempt.id,
        deadline: attempt.deadline,
        remainingSeconds: Math.max(0, Math.round((new Date(attempt.deadline).getTime() - Date.now()) / 1000)),
        questions: questionModel.toPublicQuestions(questions),
      },
    });
  } catch (error) {
    next(error);
  }
}

module.exports = { listExams, startExam, getExamQuestions };
