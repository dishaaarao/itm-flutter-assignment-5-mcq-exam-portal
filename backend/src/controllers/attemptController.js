const { config } = require('../config/env');
const HttpError = require('../utils/HttpError');
const { calculateResult } = require('../utils/resultCalculator');
const examModel = require('../models/examModel');
const questionModel = require('../models/questionModel');
const attemptModel = require('../models/attemptModel');

/**
 * Student attempt lifecycle: submit, history, and one stored result.
 *
 * Grading happens here and only here. The client receives the graded result
 * after the fact; it is never asked for, or trusted with, a score.
 */

/** Keep only answers that map to a real question and are non-empty. */
function sanitizeAnswers(rawAnswers, questions) {
  if (!rawAnswers || typeof rawAnswers !== 'object' || Array.isArray(rawAnswers)) return {};

  const knownIds = new Set(questions.map((question) => question.id));
  const knownNumbers = new Set(questions.map((question, index) => String(question.questionNo ?? index + 1)));

  const clean = {};
  Object.entries(rawAnswers).forEach(([key, value]) => {
    if (!knownIds.has(key) && !knownNumbers.has(key)) return;
    if (value === null || value === undefined) return;
    const text = String(value).trim().toUpperCase();
    if (text === '') return;
    clean[key] = text;
  });
  return clean;
}

/**
 * Grade one attempt against its exam's questions and persist the outcome.
 *
 * Shared by submit() and by start(), which has to close out an attempt whose
 * timer ran out while the student was away.
 *
 * @param {object} attempt
 * @param {object} exam
 * @param {object[]} questions full question docs, including the answer key
 * @param {{answers?: object, forceAutoSubmit?: boolean}} [options]
 */
async function finaliseAttempt(attempt, exam, questions, { answers, forceAutoSubmit = false } = {}) {
  const submittedAt = new Date();
  const startedAt = new Date(attempt.startedAt);
  const durationSeconds = Number(exam.duration) * 60;

  const elapsedSeconds = Math.max(0, Math.round((submittedAt.getTime() - startedAt.getTime()) / 1000));
  // The server's elapsed time is authoritative: a client that claims to have
  // finished early, or a tab left open past the deadline, both land here.
  const timeTakenSeconds = Math.min(elapsedSeconds, durationSeconds);

  const deadline = new Date(attempt.deadline).getTime();
  const graceMs = config.submitGraceSeconds * 1000;
  // Inside the grace window the submit is treated as on time — that slack is
  // for network latency, not for extra working time.
  const autoSubmitted = forceAutoSubmit || submittedAt.getTime() > deadline + graceMs;

  const submittedAnswers = sanitizeAnswers(answers ?? attempt.answers, questions);

  const result = calculateResult({
    questions,
    answers: submittedAnswers,
    totalMarks: Number(exam.totalMarks),
    passingMarks: Number(exam.passingMarks),
    negativeMarking: Number(exam.negativeMarking) || 0,
  });

  const updated = await attemptModel.submitAttempt(attempt.id, {
    answers: submittedAnswers,
    result,
    timeTakenSeconds,
    autoSubmitted,
    submittedAt,
  });

  return { attempt: updated, result, autoSubmitted, timeTakenSeconds };
}

async function submit(req, res, next) {
  try {
    const attempt = await attemptModel.findById(req.params.id);
    if (!attempt) throw HttpError.notFound('Attempt not found.');

    // 404 rather than 403 for someone else's attempt, so the response does not
    // confirm that the id exists.
    if (attempt.studentId !== req.user.id) {
      throw HttpError.notFound('Attempt not found.');
    }

    if (attempt.status === attemptModel.STATUS.SUBMITTED) {
      throw HttpError.conflict('This attempt has already been submitted.');
    }

    const exam = await examModel.findById(attempt.examId);
    if (!exam) throw HttpError.notFound('The exam for this attempt no longer exists.');

    const questions = await questionModel.listByExam(exam.id);

    const { attempt: updated, result, autoSubmitted, timeTakenSeconds } = await finaliseAttempt(
      attempt,
      exam,
      questions,
      { answers: req.body?.answers },
    );

    res.json({
      success: true,
      message: autoSubmitted
        ? 'Time ran out, so your answers were submitted automatically.'
        : 'Submitted successfully.',
      data: {
        attemptId: updated.id,
        examId: exam.id,
        examTitle: exam.title,
        status: updated.status,
        autoSubmitted,
        submittedAt: updated.submittedAt,
        timeTakenSeconds,
        durationSeconds: Number(exam.duration) * 60,
        result,
      },
    });
  } catch (error) {
    next(error);
  }
}

async function history(req, res, next) {
  try {
    const attempts = await attemptModel.listByStudent(req.user.id);

    res.json({
      success: true,
      count: attempts.length,
      data: { attempts: attempts.map(attemptModel.toReportRow) },
    });
  } catch (error) {
    next(error);
  }
}

async function getResult(req, res, next) {
  try {
    const attempt = await attemptModel.findById(req.params.id);
    if (!attempt || attempt.studentId !== req.user.id) {
      throw HttpError.notFound('Attempt not found.');
    }

    if (attempt.status !== attemptModel.STATUS.SUBMITTED) {
      throw HttpError.conflict('This attempt has not been submitted yet.');
    }

    const exam = await examModel.findById(attempt.examId);

    res.json({
      success: true,
      data: {
        attemptId: attempt.id,
        examId: attempt.examId,
        examTitle: attempt.examTitle,
        exam: exam
          ? { subject: exam.subject, duration: exam.duration, passingMarks: exam.passingMarks }
          : null,
        autoSubmitted: attempt.autoSubmitted,
        submittedAt: attempt.submittedAt,
        timeTakenSeconds: attempt.timeTakenSeconds,
        result: attempt.result,
      },
    });
  } catch (error) {
    next(error);
  }
}

module.exports = { submit, history, getResult, finaliseAttempt, sanitizeAnswers };
