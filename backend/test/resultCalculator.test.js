/**
 * Pure-function tests for resultCalculator.
 *
 * Run: node test/resultCalculator.test.js
 *
 * This is where every mark a student sees is decided, so the cases that matter
 * are the ones that are easy to get subtly wrong: negative marking driving a
 * score below zero, unattempted questions costing nothing, and the pass/fail
 * boundary landing on the right side.
 */

const assert = require('assert');

const { calculateResult, gradeFor, normalizeAnswer, round2 } = require('../src/utils/resultCalculator');

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

/** Four questions, 25 marks each, answer key A B C D. */
const QUESTIONS = [
  { id: 'q1', questionNo: 1, question: 'Q1', correctAnswer: 'A' },
  { id: 'q2', questionNo: 2, question: 'Q2', correctAnswer: 'B' },
  { id: 'q3', questionNo: 3, question: 'Q3', correctAnswer: 'C' },
  { id: 'q4', questionNo: 4, question: 'Q4', correctAnswer: 'D' },
];

const BASE = { questions: QUESTIONS, totalMarks: 100, passingMarks: 40 };

console.log('\nresultCalculator');

test('normalizes answers to uppercase letters', () => {
  assert.strictEqual(normalizeAnswer(' a '), 'A');
  assert.strictEqual(normalizeAnswer(''), null);
  assert.strictEqual(normalizeAnswer(undefined), null);
  assert.strictEqual(normalizeAnswer(null), null);
});

test('rounds to two decimals', () => {
  assert.strictEqual(round2(1.005), 1.01);
  assert.strictEqual(round2(2.344), 2.34);
});

test('awards full marks for an all-correct submission', () => {
  const result = calculateResult({
    ...BASE,
    answers: { q1: 'A', q2: 'B', q3: 'C', q4: 'D' },
  });

  assert.strictEqual(result.score, 100);
  assert.strictEqual(result.correct, 4);
  assert.strictEqual(result.wrong, 0);
  assert.strictEqual(result.unattempted, 0);
  assert.strictEqual(result.percentage, 100);
  assert.strictEqual(result.status, 'PASS');
  assert.strictEqual(result.grade, 'A+');
});

test('scores zero for a blank submission', () => {
  const result = calculateResult({ ...BASE, answers: {} });

  assert.strictEqual(result.score, 0);
  assert.strictEqual(result.attempted, 0);
  assert.strictEqual(result.unattempted, 4);
  assert.strictEqual(result.status, 'FAIL');
});

test('unanswered questions are never penalised', () => {
  const withBlanks = calculateResult({ ...BASE, answers: { q1: 'A' }, negativeMarking: 0.25 });
  assert.strictEqual(withBlanks.score, 25);
  assert.strictEqual(withBlanks.unattempted, 3);
  assert.strictEqual(withBlanks.wrong, 0);
});

test('negative marking subtracts a fraction of a question, not of totalMarks', () => {
  // One right (25), one wrong (-25 * 0.25 = -6.25) → 18.75.
  const result = calculateResult({
    ...BASE,
    answers: { q1: 'A', q2: 'A' },
    negativeMarking: 0.25,
  });

  assert.strictEqual(result.score, 18.75);
  assert.strictEqual(result.correct, 1);
  assert.strictEqual(result.wrong, 1);
  assert.strictEqual(result.breakdown[1].marksAwarded, -6.25);
});

test('negative marking can drive the score below zero and is not clamped', () => {
  const result = calculateResult({
    ...BASE,
    answers: { q1: 'B', q2: 'C', q3: 'D', q4: 'A' },
    negativeMarking: 0.5,
  });

  // 4 wrong at -12.5 each.
  assert.strictEqual(result.score, -50);
  assert.strictEqual(result.percentage, -50);
  assert.strictEqual(result.status, 'FAIL');
  assert.strictEqual(result.grade, 'F');
});

test('passes exactly at the passing mark and fails one mark below', () => {
  const atBoundary = calculateResult({
    ...BASE,
    answers: { q1: 'A', q2: 'B' }, // 50
  });
  // 50 >= 40.
  assert.strictEqual(atBoundary.status, 'PASS');

  const belowBoundary = calculateResult({
    ...BASE,
    totalMarks: 100,
    passingMarks: 51,
    answers: { q1: 'A', q2: 'B' },
  });
  assert.strictEqual(belowBoundary.status, 'FAIL');
});

test('maps percentages onto the grade bands', () => {
  assert.strictEqual(gradeFor(95), 'A+');
  assert.strictEqual(gradeFor(90), 'A+');
  assert.strictEqual(gradeFor(89.99), 'A');
  assert.strictEqual(gradeFor(70), 'B+');
  assert.strictEqual(gradeFor(60), 'B');
  assert.strictEqual(gradeFor(50), 'C');
  assert.strictEqual(gradeFor(40), 'D');
  assert.strictEqual(gradeFor(39.99), 'F');
  assert.strictEqual(gradeFor(0), 'F');
});

test('answers may be keyed by question number instead of id', () => {
  const result = calculateResult({ ...BASE, answers: { '1': 'A', '2': 'B' } });
  assert.strictEqual(result.score, 50);
  assert.strictEqual(result.correct, 2);
});

test('a question id wins over a colliding question number', () => {
  const result = calculateResult({
    ...BASE,
    // q1 has questionNo 1; both keys are present and must not both apply.
    answers: { q1: 'A', '1': 'D' },
  });
  assert.strictEqual(result.breakdown[0].yourAnswer, 'A');
  assert.strictEqual(result.correct, 1);
});

test('lowercase and padded answers are graded correctly', () => {
  const result = calculateResult({ ...BASE, answers: { q1: ' a ', q2: 'b' } });
  assert.strictEqual(result.correct, 2);
  assert.strictEqual(result.score, 50);
});

test('per-question marks divide totalMarks evenly and round the display', () => {
  // 100 / 3 questions = 33.333...; two correct must not read as 66.666666.
  const three = [
    { id: 'a', correctAnswer: 'A' },
    { id: 'b', correctAnswer: 'B' },
    { id: 'c', correctAnswer: 'C' },
  ];
  const result = calculateResult({
    questions: three,
    answers: { a: 'A', b: 'B' },
    totalMarks: 100,
    passingMarks: 40,
  });

  assert.strictEqual(result.score, 66.67);
  assert.strictEqual(result.percentage, 66.67);
  assert.strictEqual(result.grade, 'B');
});

test('statuses are correct, wrong or unattempted', () => {
  const result = calculateResult({ ...BASE, answers: { q1: 'A', q2: 'C' } });
  assert.deepStrictEqual(
    result.breakdown.map((row) => row.status),
    ['correct', 'wrong', 'unattempted', 'unattempted'],
  );
});

test('the answer key can be withheld from the breakdown', () => {
  const hidden = calculateResult({
    ...BASE,
    answers: { q1: 'A' },
    includeAnswerKey: false,
  });
  assert.strictEqual('correctAnswer' in hidden.breakdown[0], false);

  const shown = calculateResult({ ...BASE, answers: { q1: 'A' } });
  assert.strictEqual(shown.breakdown[0].correctAnswer, 'A');
});

test('rejects an empty questions array', () => {
  assert.throws(() => calculateResult({ ...BASE, questions: [], answers: {} }), /non-empty questions/);
});

test('tolerates a missing or malformed answers object', () => {
  assert.strictEqual(calculateResult({ ...BASE, answers: null }).unattempted, 4);
  assert.strictEqual(calculateResult({ ...BASE, answers: 'nonsense' }).unattempted, 4);
  assert.strictEqual(calculateResult({ ...BASE, answers: [] }).unattempted, 4);
});

console.log(`\n  ${passed} passed, ${failed} failed\n`);
process.exitCode = failed === 0 ? 0 : 1;
