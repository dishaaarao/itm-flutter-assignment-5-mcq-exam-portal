const { store } = require('../data');

const COLLECTION = 'questions';

/**
 * The answer key lives on every stored question document. Everything that
 * leaves the server towards a student goes through toPublicQuestion(), which
 * builds the object up from an explicit whitelist. Deleting `correctAnswer`
 * from a copy would work today but silently leaks any similar field added
 * later; building up cannot.
 */
function toPublicQuestion(question, index = 0) {
  if (!question) return null;
  return {
    id: question.id,
    questionNo: question.questionNo ?? index + 1,
    question: question.question,
    imageUrl: question.imageUrl ?? null,
    options: Array.isArray(question.options) ? [...question.options] : [],
  };
}

function toPublicQuestions(questions) {
  return questions.map((question, index) => toPublicQuestion(question, index));
}

/** Admin view — includes the answer key. */
function toAdminQuestion(question) {
  if (!question) return null;
  return { ...question };
}

/**
 * @param {string} examId
 * @param {Array<{questionNo: number, question: string, options: string[], correctAnswer: string, imageUrl?: string|null}>} questions
 */
async function insertQuestions(examId, questions) {
  if (!Array.isArray(questions) || questions.length === 0) return [];

  const docs = questions.map((question, index) => ({
    examId,
    questionNo: question.questionNo ?? index + 1,
    question: question.question,
    imageUrl: question.imageUrl ?? null,
    options: question.options,
    correctAnswer: question.correctAnswer,
  }));

  return store.insertMany(COLLECTION, docs);
}

/** Ordered by questionNo so the paper renders in the order the admin wrote it. */
async function listByExam(examId) {
  const questions = await store.find(COLLECTION, { where: { examId } });
  return questions
    .slice()
    .sort((a, b) => (a.questionNo ?? 0) - (b.questionNo ?? 0));
}

async function countByExam(examId) {
  const questions = await store.find(COLLECTION, { where: { examId } });
  return questions.length;
}

/** Cascade helper used when an exam is deleted. Returns the number removed. */
async function removeByExam(examId) {
  return store.removeWhere(COLLECTION, { where: { examId } });
}

module.exports = {
  COLLECTION,
  toPublicQuestion,
  toPublicQuestions,
  toAdminQuestion,
  insertQuestions,
  listByExam,
  countByExam,
  removeByExam,
};
