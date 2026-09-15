/**
 * End-to-end API smoke test.
 *
 * Run: npm run smoke
 *
 * Boots the real Express app on an ephemeral port with DATA_BACKEND=memory and
 * STORAGE_BACKEND=local, then walks the entire portal over real HTTP: admin
 * login, exam creation from a genuine .xlsx file, student registration, exam
 * start, submission, grading and the admin report.
 *
 * The spreadsheet is generated with the xlsx library rather than mocked, so
 * the upload path — multipart parsing, buffer handling, sheet reading and row
 * validation — is exercised for real.
 */

// Must be set before anything requires config/env, which reads at import time.
process.env.NODE_ENV = 'test';
process.env.DATA_BACKEND = 'memory';
process.env.STORAGE_BACKEND = 'local';
process.env.JWT_SECRET = 'smoke-test-secret-not-for-production';
process.env.PORT = '0';
process.env.SUBMIT_GRACE_SECONDS = '30';

const assert = require('assert');
const xlsx = require('xlsx');

const { createApp } = require('../server');
const { seedAdmin } = require('../src/utils/seed');
const { config } = require('../src/config/env');

let passed = 0;
let failed = 0;

function check(label, condition, detail = '') {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${label}`);
  } else {
    failed += 1;
    console.error(`  ✗ ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

function section(name) {
  console.log(`\n${name}`);
}

// ---------------------------------------------------------------------------
// Fixture: a real .xlsx question sheet
// ---------------------------------------------------------------------------

const SHEET_ROWS = [
  {
    'Question No.': 1,
    Question: 'What is 2 + 2?',
    'Option A': '3',
    'Option B': '4',
    'Option C': '5',
    'Option D': '6',
    'Correct Answer': 'B',
  },
  {
    'Question No.': 2,
    Question: 'Capital of France?',
    'Option A': 'Paris',
    'Option B': 'Rome',
    'Option C': 'Madrid',
    'Option D': 'Berlin',
    'Correct Answer': 'A',
  },
  {
    'Question No.': 3,
    Question: 'Largest planet?',
    'Option A': 'Earth',
    'Option B': 'Mars',
    'Option C': 'Jupiter',
    'Option D': 'Venus',
    'Correct Answer': 'C',
  },
  {
    'Question No.': 4,
    Question: 'Chemical symbol for water?',
    'Option A': 'CO2',
    'Option B': 'O2',
    'Option C': 'NaCl',
    'Option D': 'H2O',
    'Correct Answer': 'D',
  },
  // Deliberately malformed: proves bad rows are reported, not swallowed.
  {
    'Question No.': 5,
    Question: 'This row has no correct answer',
    'Option A': 'a',
    'Option B': 'b',
    'Option C': 'c',
    'Option D': 'd',
    'Correct Answer': 'E',
  },
];

function buildSheetBuffer() {
  const sheet = xlsx.utils.json_to_sheet(SHEET_ROWS);
  const workbook = xlsx.utils.book_new();
  xlsx.utils.book_append_sheet(workbook, sheet, 'Questions');
  return xlsx.write(workbook, { type: 'buffer', bookType: 'xlsx' });
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

function makeClient(baseUrl) {
  /** @returns {{status:number, body:any, text:string}} */
  async function request(method, path, { token, body, form } = {}) {
    const headers = {};
    if (token) headers.Authorization = `Bearer ${token}`;

    let payload;
    if (form) {
      // Let fetch set the multipart boundary itself.
      payload = form;
    } else if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
      payload = JSON.stringify(body);
    }

    const response = await fetch(`${baseUrl}${path}`, { method, headers, body: payload });
    const text = await response.text();

    let parsed = null;
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = null;
    }

    return { status: response.status, body: parsed, text };
  }

  return {
    get: (path, options) => request('GET', path, options),
    post: (path, options) => request('POST', path, options),
    put: (path, options) => request('PUT', path, options),
    del: (path, options) => request('DELETE', path, options),
  };
}

// ---------------------------------------------------------------------------
// The walk
// ---------------------------------------------------------------------------

async function run() {
  const app = createApp();
  await seedAdmin({ quiet: true });

  const server = await new Promise((resolve) => {
    const listening = app.listen(0, () => resolve(listening));
  });

  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const api = makeClient(baseUrl);

  console.log(`Smoke test server: ${baseUrl}`);

  try {
    section('Health');

    const health = await api.get('/api/health');
    check('GET /api/health returns 200', health.status === 200, `got ${health.status}`);
    check('health reports the memory data backend', health.body?.data?.dataBackend === 'memory');
    check('health reports the local storage backend', health.body?.data?.storageBackend === 'local');

    section('Admin authentication');

    const badLogin = await api.post('/api/auth/login', {
      body: { email: config.seedAdmin.email, password: 'wrong-password' },
    });
    check('wrong password is rejected with 401', badLogin.status === 401, `got ${badLogin.status}`);
    check('rejection uses the failure envelope', badLogin.body?.success === false);

    const adminLogin = await api.post('/api/auth/login', {
      body: { email: config.seedAdmin.email, password: config.seedAdmin.password },
    });
    check('seeded admin can log in', adminLogin.status === 200, `got ${adminLogin.status}`);
    const adminToken = adminLogin.body?.data?.token;
    check('login returns a token', typeof adminToken === 'string' && adminToken.length > 20);
    check('login never returns a password hash', !adminLogin.text.includes('passwordHash'));

    const adminMe = await api.get('/api/auth/me', { token: adminToken });
    check('GET /api/auth/me returns the admin', adminMe.body?.data?.user?.role === 'admin');

    section('Exam creation from an .xlsx upload');

    const form = new FormData();
    form.append(
      'sheet',
      new Blob([buildSheetBuffer()], {
        type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      }),
      'questions.xlsx',
    );
    form.append('title', 'General Knowledge Quiz');
    form.append('subject', 'General Knowledge');
    form.append('description', 'A short smoke-test paper.');
    form.append('duration', '30');
    form.append('totalMarks', '40');
    form.append('passingMarks', '16');
    form.append('negativeMarking', '0.25');

    const created = await api.post('/api/admin/exams', { token: adminToken, form });
    check('admin uploads a sheet and creates an exam', created.status === 201, `got ${created.status} ${created.text.slice(0, 400)}`);
    check('4 valid rows were imported', created.body?.data?.imported === 4, `got ${created.body?.data?.imported}`);
    check('the malformed row was reported, not fatal', created.body?.data?.skippedRows?.length === 1);
    check(
      'the skipped row names its sheet row',
      /Row 6/.test(created.body?.errors?.[0] || ''),
      created.body?.errors?.[0],
    );

    const examId = created.body?.data?.exam?.id;
    check('the exam has an id', typeof examId === 'string' && examId.length > 0);
    check('questionCount reflects the imported rows', created.body?.data?.exam?.questionCount === 4);

    const metadataErrors = await api.post('/api/admin/exams', {
      token: adminToken,
      form: (() => {
        const bad = new FormData();
        bad.append('sheet', new Blob([buildSheetBuffer()]), 'questions.xlsx');
        bad.append('title', '');
        bad.append('duration', '0');
        return bad;
      })(),
    });
    check('invalid metadata is rejected with 400', metadataErrors.status === 400, `got ${metadataErrors.status}`);

    section('Admin exam management');

    const adminExam = await api.get(`/api/admin/exams/${examId}`, { token: adminToken });
    check('admin can read the exam', adminExam.status === 200);
    check('admin view includes the answer key', adminExam.body?.data?.questions?.[0]?.correctAnswer === 'B');
    check('admin view lists every question', adminExam.body?.data?.questions?.length === 4);
    check(
      'questions come back in questionNo order',
      adminExam.body?.data?.questions?.map((q) => q.questionNo).join(',') === '1,2,3,4',
    );

    section('Student registration and access control');

    const signup = await api.post('/api/auth/register', {
      body: {
        name: 'Test Student',
        email: 'student@example.com',
        password: 'Student@123',
        // A client asking for admin must be ignored.
        role: 'admin',
      },
    });
    check('student registers', signup.status === 201, `got ${signup.status} ${signup.text.slice(0, 200)}`);
    check('role is forced to student', signup.body?.data?.user?.role === 'student');
    const studentToken = signup.body?.data?.token;

    const duplicate = await api.post('/api/auth/register', {
      body: { name: 'Test Student', email: 'student@example.com', password: 'Student@123' },
    });
    check('duplicate email is rejected with 409', duplicate.status === 409, `got ${duplicate.status}`);

    const forbidden = await api.get('/api/admin/exams', { token: studentToken });
    check('a student cannot reach admin routes', forbidden.status === 403, `got ${forbidden.status}`);

    const anonymous = await api.get('/api/student/exams');
    check('student routes require a token', anonymous.status === 401, `got ${anonymous.status}`);

    const mixedCaseLogin = await api.post('/api/auth/login', {
      body: { email: 'STUDENT@Example.com', password: 'Student@123' },
    });
    check('email matching is case-insensitive', mixedCaseLogin.status === 200);

    section('Student exam list');

    const list = await api.get('/api/student/exams', { token: studentToken });
    check('student sees the published exam', list.status === 200 && list.body?.count === 1);
    check('the list carries no questions', list.body?.data?.exams?.[0]?.questions === undefined);
    check('the list never leaks the answer key', !list.text.includes('correctAnswer'));

    section('Starting the exam');

    const start = await api.get(`/api/student/exams/${examId}/start`, { token: studentToken });
    check('start returns 201 for a new attempt', start.status === 201, `got ${start.status}`);
    const attemptId = start.body?.data?.attempt?.id;
    check('start returns an attempt id', typeof attemptId === 'string');

    // The single most important assertion in this file.
    check(
      'THE START RESPONSE CONTAINS NO ANSWER KEY',
      !start.text.includes('correctAnswer'),
      'correctAnswer leaked to the student',
    );
    check('start returns 4 questions', start.body?.data?.questions?.length === 4);
    check(
      'public questions expose only whitelisted fields',
      Object.keys(start.body?.data?.questions?.[0] || {}).sort().join(',') ===
        'id,imageUrl,options,question,questionNo',
    );
    check('remainingSeconds is roughly the full duration', start.body?.data?.remainingSeconds <= 1800 && start.body?.data?.remainingSeconds > 1700);

    const resume = await api.get(`/api/student/exams/${examId}/start`, { token: studentToken });
    check('starting again resumes the same attempt', resume.body?.data?.attempt?.id === attemptId);
    check('resuming is flagged', resume.body?.data?.attempt?.resumed === true);

    // Question ids, taken from the public payload, are what a student submits.
    // Q1's key is B, Q2's is A, Q3's is C — so this answers Q1 and Q2 correctly,
    // Q3 wrongly, and leaves Q4 blank.
    const [q1, q2, q3] = start.body.data.questions;

    section('Submitting and grading');

    // 2 correct (10 each), 1 wrong (-0.25 * 10), 1 left blank → 17.5 / 40.
    const submission = await api.post(`/api/student/attempts/${attemptId}/submit`, {
      token: studentToken,
      body: { answers: { [q1.id]: 'B', [q2.id]: 'A', [q3.id]: 'A' } },
    });

    check('submit succeeds', submission.status === 200, `got ${submission.status} ${submission.text.slice(0, 300)}`);
    const result = submission.body?.data?.result;
    check('score is 17.5 with negative marking applied', result?.score === 17.5, `got ${result?.score}`);
    check('2 questions graded correct', result?.correct === 2, `got ${result?.correct}`);
    check('1 question graded wrong', result?.wrong === 1, `got ${result?.wrong}`);
    check('1 question left unattempted', result?.unattempted === 1, `got ${result?.unattempted}`);
    check('percentage is 43.75', result?.percentage === 43.75, `got ${result?.percentage}`);
    check('the student passed (17.5 >= 16)', result?.status === 'PASS', `got ${result?.status}`);
    check('the grade band is D', result?.grade === 'D', `got ${result?.grade}`);
    check('the breakdown has one row per question', result?.breakdown?.length === 4);
    check('the wrong row is marked wrong', result?.breakdown?.[2]?.status === 'wrong');
    check('the blank row is marked unattempted', result?.breakdown?.[3]?.status === 'unattempted');
    check('timeTakenSeconds was measured by the server', typeof submission.body?.data?.timeTakenSeconds === 'number');

    const doubleSubmit = await api.post(`/api/student/attempts/${attemptId}/submit`, {
      token: studentToken,
      body: { answers: {} },
    });
    check('a second submit is rejected with 409', doubleSubmit.status === 409, `got ${doubleSubmit.status}`);

    const restart = await api.get(`/api/student/exams/${examId}/start`, { token: studentToken });
    check('a submitted exam cannot be retaken', restart.status === 409, `got ${restart.status}`);

    section('Student result and history');

    const storedResult = await api.get(`/api/student/attempts/${attemptId}`, { token: studentToken });
    check('the stored result matches the submit response', storedResult.body?.data?.result?.score === 17.5);
    check('the stored result carries the exam title', storedResult.body?.data?.examTitle === 'General Knowledge Quiz');

    const history = await api.get('/api/student/attempts', { token: studentToken });
    check('history lists the attempt', history.body?.count === 1);
    check('history carries the percentage', history.body?.data?.attempts?.[0]?.percentage === 43.75);
    check('history carries the pass status', history.body?.data?.attempts?.[0]?.passStatus === 'PASS');

    section('Cross-student isolation');

    await api.post('/api/auth/register', {
      body: { name: 'Other Student', email: 'other@example.com', password: 'Student@123' },
    });
    const otherLogin = await api.post('/api/auth/login', {
      body: { email: 'other@example.com', password: 'Student@123' },
    });
    const otherToken = otherLogin.body?.data?.token;

    const stolen = await api.get(`/api/student/attempts/${attemptId}`, { token: otherToken });
    check('another student cannot read the attempt', stolen.status === 404, `got ${stolen.status}`);
    check('the refusal does not confirm the attempt exists', stolen.body?.message === 'Attempt not found.');

    const otherHistory = await api.get('/api/student/attempts', { token: otherToken });
    check('another student sees an empty history', otherHistory.body?.count === 0);

    section('Admin students and report');

    const students = await api.get('/api/admin/students', { token: adminToken });
    check('admin sees both students', students.body?.count === 2, `got ${students.body?.count}`);
    check('student records never include a hash', !students.text.includes('passwordHash'));

    const studentId = signup.body.data.user.id;
    const studentAttempts = await api.get(`/api/admin/students/${studentId}/attempts`, { token: adminToken });
    check('admin sees the student attempt', studentAttempts.body?.count === 1);
    check('the admin row carries the score', studentAttempts.body?.data?.attempts?.[0]?.score === 17.5);

    const report = await api.get(`/api/admin/exams/${examId}/report`, { token: adminToken });
    check('report returns 200', report.status === 200);
    check('report has one row', report.body?.data?.rows?.length === 1);
    const summary = report.body?.data?.summary;
    check('summary counts the graded attempt', summary?.graded === 1, `got ${summary?.graded}`);
    check('summary reports the pass rate', summary?.passPercentage === 100, `got ${summary?.passPercentage}`);
    check('summary average score is 17.5', summary?.averageScore === 17.5, `got ${summary?.averageScore}`);
    check('summary names the topper', summary?.topper?.studentName === 'Test Student', `got ${summary?.topper?.studentName}`);
    check('summary counts one pass and no failures', summary?.passCount === 1 && summary?.failCount === 0);

    const examReport = await api.get(`/api/admin/exams/${examId}/report`, { token: studentToken });
    check('a student cannot read the exam report', examReport.status === 403, `got ${examReport.status}`);

    section('Cleanup and cascade');

    const deleted = await api.del(`/api/admin/exams/${examId}`, { token: adminToken });
    check('admin deletes the exam', deleted.status === 200, `got ${deleted.status}`);

    const gone = await api.get(`/api/admin/exams/${examId}`, { token: adminToken });
    check('the deleted exam is gone', gone.status === 404, `got ${gone.status}`);

    const afterDelete = await api.get('/api/student/attempts', { token: studentToken });
    check('deleting the exam cascades to attempts', afterDelete.body?.count === 0, `got ${afterDelete.body?.count}`);

    section('Unknown routes');

    const missing = await api.get('/api/does-not-exist');
    check('an unknown route returns 404 in the envelope', missing.status === 404 && missing.body?.success === false);
  } finally {
    server.close();
  }
}

run()
  .then(() => {
    console.log(`\n${'─'.repeat(60)}`);
    if (failed > 0) {
      console.error(`\n  ${passed} passed, ${failed} FAILED\n`);
      process.exit(1);
    }
    console.log(`\n  All ${passed} smoke checks passed.\n`);
  })
  .catch((error) => {
    console.error('\nSmoke test crashed:', error);
    process.exit(1);
  });
