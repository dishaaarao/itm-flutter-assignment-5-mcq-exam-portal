const { store } = require('../data');

/**
 * Exam metadata. Questions live in their own collection keyed by examId so an
 * exam document stays small and a 200-question paper does not have to be
 * fetched to render a list.
 */

const COLLECTION = 'exams';

function toIsoOrNull(value) {
  if (value === undefined || value === null || value === '') return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

/**
 * @param {object} input
 * @param {string} input.createdBy admin user id
 */
async function createExam(input) {
  const now = new Date().toISOString();

  return store.insert(COLLECTION, {
    title: String(input.title).trim(),
    subject: String(input.subject).trim(),
    description: input.description ? String(input.description).trim() : '',
    duration: Number(input.duration),
    totalMarks: Number(input.totalMarks),
    passingMarks: Number(input.passingMarks),
    negativeMarking: Number(input.negativeMarking) || 0,
    startDate: toIsoOrNull(input.startDate),
    endDate: toIsoOrNull(input.endDate),
    published: input.published === undefined ? true : Boolean(input.published),
    questionCount: Number(input.questionCount) || 0,
    // Set when the upload included an optional cover image.
    imageUrl: input.imageUrl || null,
    imagePublicId: input.imagePublicId || null,
    createdBy: input.createdBy,
    createdAt: now,
    updatedAt: now,
  });
}

async function findById(id) {
  return store.findById(COLLECTION, id);
}

async function listAll() {
  const exams = await store.find(COLLECTION, { orderBy: { field: 'createdAt', dir: 'desc' } });
  return exams;
}

/**
 * Exams a student is allowed to see right now: published, and inside their
 * date window if one is set.
 *
 * The window is applied in JS rather than in the query because the store's
 * `where` is flat equality, which cannot express `start <= now <= end` — and
 * pushing range comparisons into Firestore would need an index per field.
 */
async function listAvailableForStudent(now = new Date()) {
  const published = await store.find(COLLECTION, {
    where: { published: true },
    orderBy: { field: 'createdAt', dir: 'desc' },
  });

  const timestamp = now.getTime();
  return published.filter((exam) => {
    if (exam.startDate) {
      const start = new Date(exam.startDate);
      if (!Number.isNaN(start.getTime()) && timestamp < start.getTime()) return false;
    }
    if (exam.endDate) {
      const end = new Date(exam.endDate);
      if (!Number.isNaN(end.getTime()) && timestamp > end.getTime()) return false;
    }
    return true;
  });
}

/** Human-readable reason an exam is currently closed, or null when open. */
function availabilityFor(exam, now = new Date()) {
  if (!exam) return 'not-found';
  if (!exam.published) return 'unpublished';

  const timestamp = now.getTime();
  if (exam.startDate && timestamp < new Date(exam.startDate).getTime()) return 'not-started';
  if (exam.endDate && timestamp > new Date(exam.endDate).getTime()) return 'closed';
  return null;
}

/**
 * Update metadata only. `questionCount` and ownership are deliberately not
 * updatable here — questionCount is derived from the questions collection.
 */
async function updateExam(id, patch) {
  const allowed = [
    'title',
    'subject',
    'description',
    'duration',
    'totalMarks',
    'passingMarks',
    'negativeMarking',
    'startDate',
    'endDate',
    'published',
  ];

  const safePatch = {};
  allowed.forEach((field) => {
    if (patch[field] === undefined) return;
    safePatch[field] = ['startDate', 'endDate'].includes(field)
      ? toIsoOrNull(patch[field])
      : patch[field];
  });

  if (typeof safePatch.title === 'string') safePatch.title = safePatch.title.trim();
  if (typeof safePatch.subject === 'string') safePatch.subject = safePatch.subject.trim();

  safePatch.updatedAt = new Date().toISOString();
  return store.update(COLLECTION, id, safePatch);
}

async function setQuestionCount(id, count) {
  return store.update(COLLECTION, id, {
    questionCount: count,
    updatedAt: new Date().toISOString(),
  });
}

async function removeExam(id) {
  return store.remove(COLLECTION, id);
}

module.exports = {
  COLLECTION,
  createExam,
  findById,
  listAll,
  listAvailableForStudent,
  availabilityFor,
  updateExam,
  setQuestionCount,
  removeExam,
};
