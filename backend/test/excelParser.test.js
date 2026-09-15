/**
 * Pure-function tests for excelParser.
 *
 * Run: node test/excelParser.test.js
 *
 * The parser is the highest-risk piece of the upload path: it decides which
 * rows become exam questions and which are rejected. It has no I/O, so it is
 * tested directly with real workbooks built by the xlsx library rather than
 * with hand-written objects — the actual read path is what an admin exercises.
 */

const assert = require('assert');
const xlsx = require('xlsx');

const {
  parseQuestionsFromBuffer,
  buildColumnMap,
  normalizeHeaderKey,
} = require('../src/utils/excelParser');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  ✓ ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`  ✗ ${name}`);
    console.error(`      ${error.message}`);
  }
}

/** Build a real .xlsx buffer from an array of row objects. */
function makeWorkbook(rows, { sheetName = 'Questions' } = {}) {
  const sheet = xlsx.utils.json_to_sheet(rows);
  const workbook = xlsx.utils.book_new();
  xlsx.utils.book_append_sheet(workbook, sheet, sheetName);
  return xlsx.write(workbook, { type: 'buffer', bookType: 'xlsx' });
}

const GOOD_QUESTION = {
  'Question No.': 1,
  Question: 'What is 2 + 2?',
  'Option A': '3',
  'Option B': '4',
  'Option C': '5',
  'Option D': '6',
  'Correct Answer': 'B',
};

console.log('\nexcelParser');

test('normalizes header spellings to a comparable key', () => {
  assert.strictEqual(normalizeHeaderKey('Question No.'), 'questionno');
  assert.strictEqual(normalizeHeaderKey('  correct-answer '), 'correctanswer');
  assert.strictEqual(normalizeHeaderKey('OPTION_A'), 'optiona');
});

test('maps tolerant header spellings onto canonical columns', () => {
  const map = buildColumnMap(['Q No', 'question text', 'Opt A', 'Opt B', 'Opt C', 'Opt D', 'Ans']);
  assert.strictEqual(map.questionNo, 'Q No');
  assert.strictEqual(map.question, 'question text');
  assert.strictEqual(map.optionA, 'Opt A');
  assert.strictEqual(map.correctAnswer, 'Ans');
});

test('parses a well-formed sheet into questions', () => {
  const buffer = makeWorkbook([GOOD_QUESTION, { ...GOOD_QUESTION, 'Question No.': 2, Question: 'Capital of France?', 'Correct Answer': 'A' }]);
  const { questions, errors, sheetName } = parseQuestionsFromBuffer(buffer);

  assert.strictEqual(errors.length, 0);
  assert.strictEqual(questions.length, 2);
  assert.strictEqual(sheetName, 'Questions');
  assert.strictEqual(questions[0].question, 'What is 2 + 2?');
  assert.deepStrictEqual(questions[0].options, ['3', '4', '5', '6']);
  assert.strictEqual(questions[0].correctAnswer, 'B');
  assert.strictEqual(questions[1].questionNo, 2);
});

test('accepts a lowercase correct answer', () => {
  const buffer = makeWorkbook([{ ...GOOD_QUESTION, 'Correct Answer': 'c' }]);
  const { questions } = parseQuestionsFromBuffer(buffer);
  assert.strictEqual(questions[0].correctAnswer, 'C');
});

test('reports a bad row without discarding the good ones', () => {
  const buffer = makeWorkbook([
    GOOD_QUESTION,
    { ...GOOD_QUESTION, 'Question No.': 2, Question: '', 'Correct Answer': 'A' },
    { ...GOOD_QUESTION, 'Question No.': 3, Question: 'Third?', 'Correct Answer': 'Z' },
    { ...GOOD_QUESTION, 'Question No.': 4, Question: 'Fourth?', 'Option C': '' },
    { ...GOOD_QUESTION, 'Question No.': 5, Question: 'Fifth?', 'Correct Answer': 'A' },
  ]);
  const { questions, errors } = parseQuestionsFromBuffer(buffer);

  assert.strictEqual(questions.length, 2, 'rows 1 and 5 should survive');
  assert.strictEqual(errors.length, 3);
  // Header is row 1, so data row 2 (index 1) is sheet row 3.
  assert.strictEqual(errors[0].row, 3);
  assert.match(errors[0].reason, /Question text is empty/);
  assert.match(errors[1].reason, /must be A, B, C or D/);
  assert.match(errors[2].reason, /Option C is empty/);
});

test('flags a duplicate question number', () => {
  const buffer = makeWorkbook([GOOD_QUESTION, { ...GOOD_QUESTION, Question: 'A different question?' }]);
  const { questions, errors } = parseQuestionsFromBuffer(buffer);

  assert.strictEqual(questions.length, 1);
  assert.strictEqual(errors.length, 1);
  assert.match(errors[0].reason, /Duplicate Question No\. 1/);
});

test('skips entirely blank trailing rows', () => {
  const buffer = makeWorkbook([
    GOOD_QUESTION,
    { 'Question No.': '', Question: '', 'Option A': '', 'Option B': '', 'Option C': '', 'Option D': '', 'Correct Answer': '' },
  ]);
  const { questions, errors } = parseQuestionsFromBuffer(buffer);
  assert.strictEqual(questions.length, 1);
  assert.strictEqual(errors.length, 0);
});

test('numbers questions sequentially when the column is absent', () => {
  const rows = [
    { Question: 'One?', 'Option A': 'a', 'Option B': 'b', 'Option C': 'c', 'Option D': 'd', 'Correct Answer': 'A' },
    { Question: 'Two?', 'Option A': 'a', 'Option B': 'b', 'Option C': 'c', 'Option D': 'd', 'Correct Answer': 'B' },
  ];
  const { questions } = parseQuestionsFromBuffer(makeWorkbook(rows));
  assert.deepStrictEqual(questions.map((q) => q.questionNo), [1, 2]);
});

test('rejects a sheet missing required columns', () => {
  const buffer = makeWorkbook([{ Question: 'Only a question?', 'Correct Answer': 'A' }]);
  assert.throws(
    () => parseQuestionsFromBuffer(buffer),
    (error) => {
      assert.strictEqual(error.status, 400);
      assert.match(error.message, /missing required column/i);
      return true;
    },
  );
});

test('rejects an empty buffer', () => {
  assert.throws(
    () => parseQuestionsFromBuffer(Buffer.alloc(0)),
    (error) => error.status === 400,
  );
});

test('rejects a non-buffer', () => {
  assert.throws(
    () => parseQuestionsFromBuffer('not a buffer'),
    (error) => error.status === 400,
  );
});

test('treats a numeric correct answer as invalid rather than crashing', () => {
  const buffer = makeWorkbook([{ ...GOOD_QUESTION, 'Correct Answer': 1 }]);
  const { questions, errors } = parseQuestionsFromBuffer(buffer);
  assert.strictEqual(questions.length, 0);
  assert.match(errors[0].reason, /must be A, B, C or D/);
});

console.log(`\n  ${passed} passed, ${failed} failed\n`);
process.exitCode = failed === 0 ? 0 : 1;
