/**
 * Pure exam-grading logic.
 *
 * Kept free of I/O so it can be tested directly. Every mark the student sees is
 * computed here, on the server — the client is never trusted with grading.
 */

const { OPTION_LETTERS } = require('./validate');

/** Percentage floor -> letter grade. Ordered high to low. */
const DEFAULT_GRADE_BANDS = [
  { min: 90, grade: 'A+' },
  { min: 80, grade: 'A' },
  { min: 70, grade: 'B+' },
  { min: 60, grade: 'B' },
  { min: 50, grade: 'C' },
  { min: 40, grade: 'D' },
  { min: Number.NEGATIVE_INFINITY, grade: 'F' },
];

function round2(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

/** Normalise a submitted or stored answer to an uppercase letter, or null. */
function normalizeAnswer(value) {
  if (value === undefined || value === null) return null;
  const text = String(value).trim().toUpperCase();
  return text === '' ? null : text;
}

function gradeFor(percentage, bands = DEFAULT_GRADE_BANDS) {
  return bands.find((band) => percentage >= band.min).grade;
}

/**
 * Grade a submission.
 *
 * Each question is worth totalMarks / questionCount. A wrong answer costs
 * `negativeMarking` times that amount; an unanswered question costs nothing.
 *
 * The raw score is reported as computed and is NOT clamped at zero. Negative
 * marking exists precisely to push a score below zero when a student answers
 * badly enough, so hiding that would misreport the result. Clamping to zero is
 * a common alternative policy — change it here if the coursework expects it.
 *
 * @param {object} input
 * @param {Array<{id: string, questionNo?: number, question?: string, correctAnswer: string}>} input.questions
 * @param {Record<string, string>} input.answers questionId (or questionNo) -> chosen letter
 * @param {number} input.totalMarks
 * @param {number} input.passingMarks
 * @param {number} [input.negativeMarking] fraction of a question's marks, 0 to <1
 * @param {boolean} [input.includeAnswerKey] include correctAnswer in the breakdown
 * @returns {object}
 */
function calculateResult({
  questions,
  answers,
  totalMarks,
  passingMarks,
  negativeMarking = 0,
  includeAnswerKey = true,
}) {
  if (!Array.isArray(questions) || questions.length === 0) {
    throw new Error('calculateResult requires a non-empty questions array.');
  }

  const answerMap = answers && typeof answers === 'object' ? answers : {};
  const perQuestionMarks = totalMarks / questions.length;

  let correct = 0;
  let wrong = 0;
  let attempted = 0;
  let score = 0;

  const breakdown = questions.map((question, index) => {
    const questionNo = question.questionNo ?? index + 1;
    // Answers are keyed by question id; fall back to question number so a
    // client that posts { "1": "A" } still grades correctly.
    const raw = answerMap[question.id] ?? answerMap[String(questionNo)];
    const given = normalizeAnswer(raw);
    const key = normalizeAnswer(question.correctAnswer);

    let isCorrect = false;
    let marksAwarded = 0;

    if (given === null) {
      // Unattempted: no credit, no penalty.
    } else {
      attempted += 1;
      if (given === key) {
        isCorrect = true;
        correct += 1;
        marksAwarded = perQuestionMarks;
      } else {
        wrong += 1;
        marksAwarded = -(negativeMarking * perQuestionMarks);
      }
    }

    score += marksAwarded;

    return {
      questionId: question.id,
      questionNo,
      question: question.question ?? '',
      yourAnswer: given,
      ...(includeAnswerKey ? { correctAnswer: key } : {}),
      isCorrect,
      status: given === null ? 'unattempted' : isCorrect ? 'correct' : 'wrong',
      marksAwarded: round2(marksAwarded),
    };
  });

  const unattempted = questions.length - attempted;
  const roundedScore = round2(score);
  const percentage = totalMarks > 0 ? round2((roundedScore / totalMarks) * 100) : 0;

  return {
    totalQuestions: questions.length,
    attempted,
    correct,
    wrong,
    unattempted,
    score: roundedScore,
    totalMarks,
    percentage,
    status: roundedScore >= passingMarks ? 'PASS' : 'FAIL',
    grade: gradeFor(percentage),
    breakdown,
  };
}

module.exports = {
  calculateResult,
  gradeFor,
  normalizeAnswer,
  round2,
  DEFAULT_GRADE_BANDS,
  OPTION_LETTERS,
};
