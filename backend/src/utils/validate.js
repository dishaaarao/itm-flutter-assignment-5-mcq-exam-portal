/**
 * Shared input validators.
 *
 * Each validator is a pure function returning an array of human-readable error
 * strings — empty means valid. Controllers turn a non-empty array into a 400.
 *
 * These live in one module (rather than inline in each controller) so tests can
 * import the real thing. The previous assignment duplicated its validator
 * between controller and test, which meant the test only ever proved the copy
 * agreed with itself.
 */

const OPTION_LETTERS = ['A', 'B', 'C', 'D'];
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isValidEmail(value) {
  return isNonEmptyString(value) && EMAIL_PATTERN.test(value.trim());
}

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

/** Accepts a number or numeric string; returns null when not coercible. */
function toNumber(value) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

/**
 * @param {object} data
 * @param {{requirePassword?: boolean}} [options]
 * @returns {string[]}
 */
function validateRegistration(data, { requirePassword = true } = {}) {
  const errors = [];
  const body = data || {};

  if (!isNonEmptyString(body.name)) errors.push('name is required.');
  else if (body.name.trim().length > 80) errors.push('name must be 80 characters or fewer.');

  if (!isValidEmail(body.email)) errors.push('A valid email address is required.');

  if (requirePassword) {
    if (!isNonEmptyString(body.password)) errors.push('password is required.');
    else if (body.password.length < 6) {
      errors.push('password must be at least 6 characters.');
    }
  }

  return errors;
}

/**
 * @param {object} data
 * @returns {string[]}
 */
function validateLogin(data) {
  const errors = [];
  const body = data || {};
  if (!isValidEmail(body.email)) errors.push('A valid email address is required.');
  if (!isNonEmptyString(body.password)) errors.push('password is required.');
  return errors;
}

/**
 * Validate exam metadata supplied alongside an Excel upload.
 * @param {object} data
 * @returns {string[]}
 */
function validateExamMetadata(data) {
  const errors = [];
  const body = data || {};

  if (!isNonEmptyString(body.title)) errors.push('title is required.');
  else if (body.title.trim().length > 120) {
    errors.push('title must be 120 characters or fewer.');
  }

  if (!isNonEmptyString(body.subject)) errors.push('subject is required.');

  const duration = toNumber(body.duration);
  if (duration === null) errors.push('duration (minutes) is required and must be a number.');
  else if (duration <= 0) errors.push('duration must be greater than 0.');
  else if (duration > 600) errors.push('duration must be 600 minutes or fewer.');

  const totalMarks = toNumber(body.totalMarks);
  if (totalMarks === null) errors.push('totalMarks is required and must be a number.');
  else if (totalMarks <= 0) errors.push('totalMarks must be greater than 0.');
  else if (totalMarks > 1000) errors.push('totalMarks must be 1000 or fewer.');

  const passingMarks = toNumber(body.passingMarks);
  if (passingMarks === null) errors.push('passingMarks is required and must be a number.');
  else if (passingMarks < 0) errors.push('passingMarks cannot be negative.');
  else if (totalMarks !== null && passingMarks > totalMarks) {
    errors.push('passingMarks cannot exceed totalMarks.');
  }

  // Optional: absent means no negative marking.
  if (body.negativeMarking !== undefined && body.negativeMarking !== '') {
    const negativeMarking = toNumber(body.negativeMarking);
    if (negativeMarking === null) errors.push('negativeMarking must be a number.');
    else if (negativeMarking < 0) errors.push('negativeMarking cannot be negative.');
    else if (negativeMarking >= 1) {
      errors.push('negativeMarking must be less than 1 (it is a fraction of each question).');
    }
  }

  const start = parseDateField(body.startDate);
  if (body.startDate && start === null) errors.push('startDate is not a valid date.');

  const end = parseDateField(body.endDate);
  if (body.endDate && end === null) errors.push('endDate is not a valid date.');

  if (start && end && end <= start) errors.push('endDate must be after startDate.');

  return errors;
}

/** @returns {Date|null} */
function parseDateField(value) {
  if (value === undefined || value === null || value === '') return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

module.exports = {
  OPTION_LETTERS,
  isNonEmptyString,
  isPlainObject,
  isValidEmail,
  isFiniteNumber,
  toNumber,
  parseDateField,
  validateRegistration,
  validateLogin,
  validateExamMetadata,
};
