const { store } = require('../data');

/**
 * An attempt is one student's sitting of one exam.
 *
 * The server owns the clock: `startedAt` and `deadline` are written at start
 * time and the student's own view of elapsed time is never trusted. Answers
 * are persisted on submit; the graded result is stored next to them so the
 * report and the student's result screen read the same numbers.
 */

const COLLECTION = 'attempts';

const STATUS = {
  IN_PROGRESS: 'in_progress',
  SUBMITTED: 'submitted',
};

/** ISO string `seconds` from the given instant. */
function isoAfter(from, seconds) {
  return new Date(from.getTime() + seconds * 1000).toISOString();
}

/**
 * @param {object} input
 * @param {object} input.exam the exam document (used to snapshot title/duration)
 * @param {object} input.student the user document
 */
async function createAttempt({ exam, student }) {
  const startedAt = new Date();
  const deadline = isoAfter(startedAt, Number(exam.duration) * 60);

  return store.insert(COLLECTION, {
    examId: exam.id,
    // Snapshot the title so a renamed or deleted exam still reads correctly in
    // the student's history and in the admin report.
    examTitle: exam.title,
    studentId: student.id,
    studentName: student.name,
    studentEmail: student.email,
    status: STATUS.IN_PROGRESS,
    startedAt: startedAt.toISOString(),
    deadline,
    submittedAt: null,
    answers: {},
    result: null,
    autoSubmitted: false,
    timeTakenSeconds: null,
  });
}

async function findById(id) {
  return store.findById(COLLECTION, id);
}

/**
 * The student's live attempt for this exam, if any. Used to resume rather than
 * hand out a second timer.
 */
async function findInProgress(examId, studentId) {
  const matches = await store.find(COLLECTION, {
    where: { examId, studentId, status: STATUS.IN_PROGRESS },
  });
  // Oldest wins, so a stray duplicate can never mask the original timer.
  return matches.sort((a, b) => String(a.startedAt).localeCompare(String(b.startedAt)))[0] ?? null;
}

async function findSubmitted(examId, studentId) {
  const matches = await store.find(COLLECTION, {
    where: { examId, studentId, status: STATUS.SUBMITTED },
  });
  return matches.sort((a, b) => String(b.submittedAt).localeCompare(String(a.submittedAt)))[0] ?? null;
}

async function listByStudent(studentId) {
  const attempts = await store.find(COLLECTION, { where: { studentId } });
  return attempts.sort((a, b) => String(b.startedAt).localeCompare(String(a.startedAt)));
}

async function listByExam(examId) {
  const attempts = await store.find(COLLECTION, { where: { examId } });
  return attempts.sort((a, b) => String(a.startedAt).localeCompare(String(b.startedAt)));
}

/**
 * Persist a graded submission.
 *
 * @param {string} id
 * @param {object} input
 * @param {Record<string,string>} input.answers
 * @param {object} input.result output of calculateResult
 * @param {number} input.timeTakenSeconds already clamped by the controller
 * @param {boolean} input.autoSubmitted true when the deadline had passed
 * @param {Date} [input.submittedAt]
 */
async function submitAttempt(id, { answers, result, timeTakenSeconds, autoSubmitted = false, submittedAt = new Date() }) {
  return store.update(COLLECTION, id, {
    status: STATUS.SUBMITTED,
    answers: answers || {},
    result,
    timeTakenSeconds,
    autoSubmitted: Boolean(autoSubmitted),
    submittedAt: submittedAt.toISOString(),
  });
}

/**
 * Refresh the deadline of an attempt whose stored timer has already expired,
 * so a returning student is not stuck with a zero-second countdown and a
 * guaranteed auto-submit. Only ever called for in-progress attempts.
 */
async function extendDeadline(id, exam, from = new Date()) {
  return store.update(COLLECTION, id, {
    deadline: isoAfter(from, Number(exam.duration) * 60),
  });
}

async function removeByExam(examId) {
  return store.removeWhere(COLLECTION, { where: { examId } });
}

/**
 * Flat row for the admin report table and the student's history — only what
 * those views render.
 */
function toReportRow(attempt) {
  const result = attempt.result || {};
  return {
    attemptId: attempt.id,
    examId: attempt.examId ?? null,
    // Snapshotted when the attempt was created, so a renamed or deleted exam
    // still names itself in the student's history.
    examTitle: attempt.examTitle ?? null,
    studentId: attempt.studentId,
    studentName: attempt.studentName,
    studentEmail: attempt.studentEmail,
    status: attempt.status,
    submittedAt: attempt.submittedAt,
    startedAt: attempt.startedAt,
    autoSubmitted: attempt.autoSubmitted,
    score: result.score ?? null,
    totalMarks: result.totalMarks ?? null,
    percentage: result.percentage ?? null,
    grade: result.grade ?? null,
    passStatus: result.status ?? null,
    correct: result.correct ?? null,
    wrong: result.wrong ?? null,
    unattempted: result.unattempted ?? null,
    timeTakenSeconds: attempt.timeTakenSeconds ?? null,
  };
}

/**
 * Aggregate statistics over graded attempts. Purely derived from the rows, so
 * the memory and Firestore backends report identical numbers.
 */
function summarise(attempts) {
  const graded = attempts.filter((attempt) => attempt.result);

  if (graded.length === 0) {
    return {
      studentsAttempted: attempts.length,
      submitted: attempts.filter((a) => a.status === STATUS.SUBMITTED).length,
      graded: 0,
      topper: null,
      averageScore: null,
      averagePercentage: null,
      highestScore: null,
      lowestScore: null,
      passCount: 0,
      failCount: 0,
      passPercentage: null,
    };
  }

  const scored = graded.map((attempt) => attempt.result);
  const scores = scored.map((result) => Number(result.score) || 0);
  const percentages = scored.map((result) => Number(result.percentage) || 0);

  const highest = Math.max(...scores);
  const lowest = Math.min(...scores);
  const passCount = scored.filter((result) => result.status === 'PASS').length;

  // Highest scorer, earliest submission breaking a tie.
  const topperAttempt = graded
    .slice()
    .sort((a, b) => {
      const diff = (Number(b.result.score) || 0) - (Number(a.result.score) || 0);
      if (diff !== 0) return diff;
      return String(a.submittedAt).localeCompare(String(b.submittedAt));
    })[0];

  const round2 = (value) => Math.round(value * 100) / 100;

  return {
    studentsAttempted: attempts.length,
    submitted: attempts.filter((a) => a.status === STATUS.SUBMITTED).length,
    graded: graded.length,
    topper: {
      studentId: topperAttempt.studentId,
      studentName: topperAttempt.studentName,
      score: topperAttempt.result.score,
      percentage: topperAttempt.result.percentage,
      grade: topperAttempt.result.grade,
    },
    averageScore: round2(scores.reduce((sum, value) => sum + value, 0) / scores.length),
    averagePercentage: round2(
      percentages.reduce((sum, value) => sum + value, 0) / percentages.length,
    ),
    highestScore: highest,
    lowestScore: lowest,
    passCount,
    failCount: graded.length - passCount,
    passPercentage: round2((passCount / graded.length) * 100),
  };
}

module.exports = {
  COLLECTION,
  STATUS,
  createAttempt,
  findById,
  findInProgress,
  findSubmitted,
  listByStudent,
  listByExam,
  submitAttempt,
  extendDeadline,
  removeByExam,
  toReportRow,
  summarise,
};
