const xlsx = require('xlsx');
const HttpError = require('./HttpError');
const { OPTION_LETTERS } = require('./validate');

/**
 * Parses the admin's question sheet.
 *
 * Expected columns (header spelling is tolerant — see HEADER_ALIASES):
 *   Question No. | Question | Option A | Option B | Option C | Option D | Correct Answer
 *
 * Malformed rows are reported individually rather than failing the whole
 * upload: a 50-question sheet with one typo should import 49 questions and name
 * the bad row, not reject everything. The request only fails outright when
 * required columns are missing or no row is usable.
 */

const REQUIRED_COLUMNS = [
  'question',
  'optionA',
  'optionB',
  'optionC',
  'optionD',
  'correctAnswer',
];

const REQUIRED_COLUMN_LABELS = {
  question: 'Question',
  optionA: 'Option A',
  optionB: 'Option B',
  optionC: 'Option C',
  optionD: 'Option D',
  correctAnswer: 'Correct Answer',
  questionNo: 'Question No.',
};

/**
 * Canonical column -> accepted spellings, after normalisation
 * (lowercased, non-alphanumerics stripped).
 */
const HEADER_ALIASES = {
  questionNo: ['questionno', 'qno', 'qnumber', 'questionnumber', 'srno', 'sno', 'no'],
  question: ['question', 'questiontext', 'questionstatement'],
  optionA: ['optiona', 'opta', 'choicea', 'a'],
  optionB: ['optionb', 'optb', 'choiceb', 'b'],
  optionC: ['optionc', 'optc', 'choicec', 'c'],
  optionD: ['optiond', 'optd', 'choiced', 'd'],
  correctAnswer: ['correctanswer', 'correctoption', 'correctchoice', 'answer', 'ans', 'correct'],
};

function normalizeHeaderKey(key) {
  return String(key).toLowerCase().replace(/[^a-z0-9]/g, '');
}

/**
 * Map canonical column names onto the actual header strings in the sheet.
 * @param {string[]} headers
 * @returns {Record<string, string>}
 */
function buildColumnMap(headers) {
  const normalizedToActual = new Map();
  headers.forEach((header) => {
    const key = normalizeHeaderKey(header);
    if (!normalizedToActual.has(key)) normalizedToActual.set(key, header);
  });

  const columnMap = {};
  Object.entries(HEADER_ALIASES).forEach(([canonical, aliases]) => {
    const match = aliases.find((alias) => normalizedToActual.has(alias));
    if (match) columnMap[canonical] = normalizedToActual.get(match);
  });
  return columnMap;
}

/**
 * @param {Buffer} buffer raw bytes of an .xlsx or .csv upload
 * @returns {{questions: object[], errors: {row: number, reason: string}[], headers: string[], sheetName: string}}
 * @throws {HttpError} 400 when the file is unreadable or required columns are absent
 */
function parseQuestionsFromBuffer(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw HttpError.badRequest('The uploaded file is empty.');
  }

  let workbook;
  try {
    workbook = xlsx.read(buffer, { type: 'buffer' });
  } catch {
    throw HttpError.badRequest(
      'Could not read the uploaded file. Upload a valid .xlsx or .csv sheet.',
    );
  }

  const sheetName = workbook.SheetNames[0];
  if (!sheetName) throw HttpError.badRequest('The uploaded workbook contains no sheets.');

  // raw:false forces every cell to a string, so a numeric "1" answer does not
  // arrive as a number and numeric options keep their leading zeros.
  const rows = xlsx.utils.sheet_to_json(workbook.Sheets[sheetName], {
    defval: '',
    raw: false,
  });

  if (rows.length === 0) {
    throw HttpError.badRequest(`Sheet "${sheetName}" has no data rows.`);
  }

  const headers = Object.keys(rows[0] || {});
  const columnMap = buildColumnMap(headers);

  const missing = REQUIRED_COLUMNS.filter((column) => !columnMap[column]);
  if (missing.length > 0) {
    throw HttpError.badRequest(
      `The sheet is missing required column(s): ${missing
        .map((column) => REQUIRED_COLUMN_LABELS[column])
        .join(', ')}.`,
      [`Columns found: ${headers.join(', ') || '(none)'}`],
    );
  }

  const questions = [];
  const errors = [];
  const seenQuestionNos = new Set();

  rows.forEach((row, index) => {
    // Header sits on row 1, so data row i is sheet row i + 2.
    const rowNumber = index + 2;
    const read = (canonical) =>
      columnMap[canonical] ? String(row[columnMap[canonical]] ?? '').trim() : '';

    const questionText = read('question');
    const options = ['optionA', 'optionB', 'optionC', 'optionD'].map(read);
    const correctAnswer = read('correctAnswer').toUpperCase();
    const rawNumber = read('questionNo');

    // Ignore rows that are entirely blank — trailing rows are common in Excel.
    if (!questionText && options.every((option) => !option) && !correctAnswer && !rawNumber) {
      return;
    }

    const rowErrors = [];
    if (!questionText) rowErrors.push('Question text is empty');

    const emptyOptionIndex = options.findIndex((option) => !option);
    if (emptyOptionIndex !== -1) {
      rowErrors.push(`Option ${OPTION_LETTERS[emptyOptionIndex]} is empty`);
    }

    if (!OPTION_LETTERS.includes(correctAnswer)) {
      rowErrors.push(
        `Correct Answer must be A, B, C or D (got "${correctAnswer || 'nothing'}")`,
      );
    }

    const parsedNumber = rawNumber === '' ? null : Number.parseInt(rawNumber, 10);
    const questionNo =
      parsedNumber !== null && Number.isFinite(parsedNumber) && parsedNumber > 0
        ? parsedNumber
        : index + 1;

    if (rawNumber !== '' && seenQuestionNos.has(questionNo)) {
      rowErrors.push(`Duplicate Question No. ${questionNo}`);
    }

    if (rowErrors.length > 0) {
      errors.push({ row: rowNumber, reason: rowErrors.join('; ') });
      return;
    }

    seenQuestionNos.add(questionNo);
    questions.push({ questionNo, question: questionText, options, correctAnswer });
  });

  return { questions, errors, headers, sheetName };
}

module.exports = {
  parseQuestionsFromBuffer,
  buildColumnMap,
  normalizeHeaderKey,
  REQUIRED_COLUMNS,
  HEADER_ALIASES,
};
