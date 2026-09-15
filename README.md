# MCQ Exam Portal

A full-stack online MCQ examination system: an admin uploads an Excel question
sheet to create a timed exam, and students take that exam against a server-enforced
clock and receive an auto-graded result the moment they submit.

Built for **Assignment 5** of the ITM Skills University Flutter course.

| | |
|---|---|
| **Student** | Sayuj Pillai |
| **Roll number** | 150096724107 |
| **Stack** | Flutter · Node.js/Express · Firestore · Cloudinary |

---

## The one thing to know before reading further

The brief specifies Firebase Firestore, Firebase Auth and Cloudinary. None of
those can run without a cloud project, and a project that only runs after you
supply credentials is a project nobody can check.

So the backend is built around **two swappable seams**, selected by environment
variable:

| Seam | Demo (default) | Production |
|---|---|---|
| Data | `DATA_BACKEND=memory` — an in-process document store | `DATA_BACKEND=firestore` |
| Storage | `STORAGE_BACKEND=local` — files under `uploads/` | `STORAGE_BACKEND=cloudinary` |

Both implementations sit behind one interface and are exercised by the same
controllers, models and tests. **The default configuration runs the entire
application — admin upload, exam engine, grading, reports — with zero
credentials and zero cloud accounts.** Switching to real Firestore and
Cloudinary is a `.env` change, not a code change.

What is genuinely different in demo mode is that data lives in memory and is
gone when the process exits. That is the honest limitation.

---

## Quick start

```bash
cd backend
npm install
npm start
```

That is the whole setup. There is no `.env` to create — every setting has a
working default.

The server prints its URLs and the seeded admin credentials on boot:

```
MCQ Exam Portal API listening on http://localhost:5050
  data backend    : memory
  storage backend : local
  admin login     : admin@mcq.local / Admin@123
```

`npm start` seeds that admin automatically. It has to: admins cannot
self-register (see *Auth design*), so without a seeded account there would be no
way into the admin panel at all.

### Verifying it works

```bash
cd backend
npm test
```

Three test files run: two pure-function suites and one end-to-end walk.

```
✓ excelParser.test.js       12 passed
✓ resultCalculator.test.js  17 passed
✓ api.smoke.test.js         75 checks passed
```

The smoke test is the interesting one. It boots the real app on an ephemeral
port, **generates a genuine `.xlsx` file with the `xlsx` library** (so the
multipart upload path is really exercised, not mocked), and walks the full
journey over HTTP:

admin login → create exam from the sheet → student registers → start exam →
submit answers → assert the exact score → read the admin report → delete the
exam and confirm the cascade.

### Running the Flutter app

```bash
cd mcq_portal_app
flutter pub get
flutter run -d chrome      # or: -d macos, or a connected Android device
```

The backend must be running first. The app finds it automatically: `localhost`
on web and desktop, `10.0.2.2` on an Android emulator. To point at a different
host, pass `--dart-define=API_BASE_URL=http://192.168.1.5:5050`.

Check the client the same way:

```bash
cd mcq_portal_app
flutter analyze            # 0 issues
flutter test               # 21 passed
```

> Flutter web renders into a canvas, so no widget can be addressed by DOM
> selector. The UI was therefore walked by screen coordinate in a browser, with
> a screenshot at each step — see *What is verified* below for exactly how far
> that goes.

---

## Architecture

```
                    ┌──────────────────────┐
   Flutter app ────▶│  Express REST API    │
   (students and    │  /api/auth           │
    admins)         │  /api/admin          │
                    │  /api/student        │
                    └──────────┬───────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
      ┌───────▼────────┐               ┌────────▼────────┐
      │  data seam     │               │  storage seam   │
      │  memoryStore   │               │  localStorage   │
      │  firestoreStore│               │  cloudinary     │
      └────────────────┘               └─────────────────┘
        DATA_BACKEND                     STORAGE_BACKEND
```

Everything above the seams is written once. The controllers never know which
backend is active.

### Why the data interface is not Firestore-shaped

Both stores export the same seven methods:

```js
insert(collection, doc)                          -> { id, ...doc }
insertMany(collection, docs)                     -> { id, ...doc }[]
findById(collection, id)                         -> doc | null
find(collection, { where?, orderBy?, limit? })   -> doc[]
update(collection, id, patch)                    -> doc
remove(collection, id)                           -> void
removeWhere(collection, { where })               -> number
```

`where` is flat equality and `orderBy` is `{field, dir}` — deliberately **not**
a predicate function. Firestore cannot execute an arbitrary JS predicate, so an
interface that accepted one would be a memory-only design wearing a Firestore
costume. A query object maps cleanly onto both engines.

Two details worth knowing:

- **At most one equality filter is pushed down to Firestore.** Chaining two
  equality filters on different fields requires a composite index, which a fresh
  project does not have — the query would fail at runtime against exactly the
  person following the setup instructions. The first filter goes to Firestore;
  the rest is applied in memory on the (already narrowed) result set.
- **Documents are stored with ISO-string timestamps** in both backends, so the
  same document read from either store sorts identically and `orderBy` behaves
  the same way. A Firestore `Timestamp` object would sort differently from the
  string the memory store holds.

### Why Firebase is imported lazily

`firebase-admin` throws during initialisation when it cannot find credentials.
If `src/config/firebase.js` were required at startup, that throw would take down
the credential-free demo path on boot. So it is required only when
`DATA_BACKEND=firestore` — the same pattern for `cloudinary` under
`STORAGE_BACKEND=cloudinary`. This is the reason the zero-credential mode works
at all.

---

## Using real Firestore and Cloudinary

Create `backend/.env` from `backend/.env.example` and fill in:

```bash
DATA_BACKEND=firestore
FIREBASE_SERVICE_ACCOUNT_PATH=./serviceAccountKey.json
# or, for hosts where you cannot ship a file:
# FIREBASE_PROJECT_ID=...
# FIREBASE_CLIENT_EMAIL=...
# FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"

STORAGE_BACKEND=cloudinary
CLOUDINARY_CLOUD_NAME=...
CLOUDINARY_API_KEY=...
CLOUDINARY_API_SECRET=...

JWT_SECRET=<a long random string>
```

Get the service account key from **Firebase Console → Project Settings →
Service Accounts → Generate New Private Key**. Get the Cloudinary credentials
from your Cloudinary dashboard.

Then `npm start` as normal. The boot banner reports which backends are active,
so you can confirm the switch took effect.

Misconfiguration fails fast and says what is wrong: selecting
`STORAGE_BACKEND=cloudinary` without credentials exits at startup with a message
naming the missing variables, rather than failing on the first upload.

Collections created in Firestore: `users`, `exams`, `questions`, `attempts`.

---

## Auth design, and the deviation from the brief

The brief asks for **Firebase Auth on the client with Admin SDK verification on
the server.** That cannot run without a Firebase project, so the portal uses a
single backend-issued JWT flow that works identically in both modes.

- `POST /api/auth/register` — bcrypt-hashed password. **`role` is forced to
  `'student'`; any role sent by the client is ignored.** This is not a detail:
  without it, the register endpoint is a one-request path to an admin account.
- `POST /api/auth/login` — returns `{ token, user }`. HS256, claims
  `{ sub, role, email }`.
- `GET /api/auth/me`
- `POST /api/auth/firebase` — accepts a Firebase ID token, verifies it with the
  Admin SDK, upserts the user and returns a portal JWT. **Mounted only when
  Firebase credentials are present**, because a route that can only ever fail is
  worse than no route. This is the seam Google Sign-In would plug into.

Two consequences worth stating plainly:

1. It is a deviation from the brief's literal instruction. The trade is that the
   app runs with no accounts, and there is exactly one auth path to reason about
   instead of two that must agree.
2. The role is re-read from the database on every request rather than trusted
   from the token claim. A JWT is valid for a week; a demoted admin should lose
   access immediately, not whenever their token happens to expire.

---

## Correctness notes

These are the parts most likely to be quietly wrong, so they are handled
explicitly and covered by tests.

### The answer key never reaches the student

`GET /api/student/exams/:id/start` returns questions through a dedicated mapper
that **builds each object up from a whitelist** of `{id, questionNo, question,
imageUrl, options}` rather than deleting `correctAnswer` from a copy. Deleting
works today but silently leaks any similar field added later; building up cannot.

The smoke test asserts this on the raw response text — not on the parsed object
— so a key nested anywhere in the payload fails the test.

### The timer is the server's, not the client's

On start, an attempt is created with `startedAt` and `deadline = startedAt +
duration`. On submit, the server recomputes elapsed time from its own clock and
clamps `timeTakenSeconds` to the duration. A client claiming to have finished in
ten seconds, and a tab left open for three hours, both land on the same
authoritative answer.

Details:

- Past the deadline the submission is **graded and flagged `autoSubmitted:
  true`, not rejected.** Rejecting throws away the student's answers, which is
  strictly worse than a flagged late submit.
- `SUBMIT_GRACE_SECONDS` (default 30) absorbs network latency. Inside that
  window a submit is treated as on time — the slack is for the network, not for
  extra working time.
- Starting an exam twice **resumes the existing attempt** with its original
  deadline. A page reload costs nothing; a second tab buys no extra time.
- If an attempt's timer expired while the student was away, starting again
  grades and closes that attempt rather than deleting it. A graded zero is
  recoverable information; a vanished attempt is not.

### Excel parsing reports bad rows instead of failing the upload

A 50-question sheet with one typo should import 49 questions and tell the admin
which row to fix — not reject the whole file. So each row is validated
individually and failures are collected:

```json
{
  "success": true,
  "data": { "imported": 49, "skippedRows": [{ "row": 27, "reason": "Correct Answer must be A, B, C or D (got \"E\")" }] },
  "errors": ["Row 27: Correct Answer must be A, B, C or D (got \"E\")"]
}
```

The request fails outright only when the sheet is unreadable, has no data rows,
or is **missing a required column** — because in those cases there is nothing to
partially import.

Column headers are matched tolerantly: lowercased, punctuation stripped, then
looked up against aliases. `Question No.`, `Q No`, `q_no` and `sno` all resolve
to the same column, as do `Correct Answer`, `Ans` and `correct-option`.

Cells are read with `raw: false` so every value arrives as a string. Without it
a numeric option would lose leading zeros and a numeric answer would arrive as a
number rather than a letter.

### Grading

Each question is worth `totalMarks / questionCount`. A wrong answer costs
`negativeMarking` times that amount. An unanswered question costs nothing.

**The score is reported as computed and is not clamped at zero.** Negative
marking exists precisely to push a score below zero when a student answers badly
enough; hiding that would misreport the result. If your coursework expects
clamping, it is a one-line change in `src/utils/resultCalculator.js` and the
comment there says so.

All grading happens on the server. The client is never asked for, or trusted
with, a score.

---

## API reference

`●` requires a Bearer token · `◆` requires the admin role.

### Auth

| Method | Path | | Description |
|---|---|---|---|
| POST | `/api/auth/register` | | Create a student account (role forced to `student`) |
| POST | `/api/auth/login` | | Returns `{ token, user }` |
| GET | `/api/auth/me` | ● | Current user |
| POST | `/api/auth/firebase` | | Exchange a Firebase ID token — only mounted when Firebase is configured |

### Admin

| Method | Path | | Description |
|---|---|---|---|
| POST | `/api/admin/exams` | ●◆ | multipart: question sheet + metadata → creates the exam |
| GET | `/api/admin/exams` | ●◆ | All exams |
| GET | `/api/admin/exams/:id` | ●◆ | One exam **including the answer key** |
| PUT | `/api/admin/exams/:id` | ●◆ | Update metadata |
| DELETE | `/api/admin/exams/:id` | ●◆ | Delete, cascading to questions and attempts |
| GET | `/api/admin/exams/:id/report` | ●◆ | Per-student rows + aggregate statistics |
| GET | `/api/admin/students` | ●◆ | Student roster |
| GET | `/api/admin/students/:id/attempts` | ●◆ | One student's attempts |

**Creating an exam** — `multipart/form-data`:

| Field | Required | Notes |
|---|---|---|
| `sheet` | yes | `.xlsx`, `.xls` or `.csv`, max 10 MB |
| `image` | no | Cover image; stored through the storage seam |
| `title` | yes | max 120 characters |
| `subject` | yes | |
| `duration` | yes | minutes, 1–600 |
| `totalMarks` | yes | 1–1000 |
| `passingMarks` | yes | 0 to `totalMarks` |
| `negativeMarking` | no | fraction of a question, 0 to <1. Default 0 |
| `startDate` / `endDate` | no | ISO dates; the exam is only visible inside this window |
| `published` | no | default `true` |

### Student

| Method | Path | | Description |
|---|---|---|---|
| GET | `/api/student/exams` | ● | Published exams in their date window; no questions |
| GET | `/api/student/exams/:id/start` | ● | Resume or create an attempt; sanitized questions + `remainingSeconds` |
| GET | `/api/student/exams/:id/questions` | ● | Sanitized questions for an attempt already in progress |
| POST | `/api/student/attempts/:id/submit` | ● | Grades server-side and returns the result |
| GET | `/api/student/attempts` | ● | Own attempt history |
| GET | `/api/student/attempts/:id` | ● | One stored result (own attempts only) |
| POST | `/api/student/profile/photo` | ● | multipart profile photo |

### Response envelope

Every response uses the same shape, matching the earlier assignment:

```json
{ "success": true,  "data": { }, "message": "optional", "count": 0 }
{ "success": false, "message": "what went wrong", "errors": ["field-level detail"] }
```

Errors are raised as `HttpError` and rendered by one central handler. Anything
that is not an `HttpError` becomes a generic 500 **whose message is not sent to
the client** — a stack trace or a driver error string can disclose paths,
queries and configuration. It is logged server-side instead.

---

## Environment variables

Every variable has a working default; `.env` is optional.

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `5050` | |
| `NODE_ENV` | `development` | In `production`, a fallback `JWT_SECRET` is refused at boot |
| `DATA_BACKEND` | `memory` | `memory` \| `firestore` |
| `STORAGE_BACKEND` | `local` | `local` \| `cloudinary` |
| `JWT_SECRET` | dev fallback | Must be set to a strong value in production |
| `JWT_EXPIRES_IN` | `7d` | |
| `SUBMIT_GRACE_SECONDS` | `30` | Network-latency slack on the deadline |
| `ALLOW_REATTEMPT` | `false` | Whether a student may retake a submitted exam |
| `SEED_ADMIN_EMAIL` | `admin@mcq.local` | |
| `SEED_ADMIN_PASSWORD` | `Admin@123` | |

---

## Project structure

```
mcq-exam-portal/
├── backend/
│   ├── server.js                 App factory + startup
│   ├── src/
│   │   ├── config/               env, lazy Firebase init, lazy Cloudinary init
│   │   ├── data/                 memoryStore, firestoreStore, shared query helpers
│   │   ├── storage/              localStorage, cloudinaryStorage
│   │   ├── models/               user, exam, question, attempt
│   │   ├── controllers/          auth, admin, exam, attempt
│   │   ├── middlewares/          auth, admin, upload, error handler
│   │   ├── routes/               auth, admin, student
│   │   └── utils/                excelParser, resultCalculator, validate, HttpError, seed
│   └── test/
│       ├── excelParser.test.js       pure parser unit tests
│       ├── resultCalculator.test.js  pure grading unit tests
│       └── api.smoke.test.js         full end-to-end HTTP walk
└── mcq_portal_app/               Flutter client
    └── lib/
        ├── config/               API base URL, platform-aware
        ├── models/               user, exam, question, attempt
        ├── services/             api_client, auth, exam, attempt
        ├── providers/            ChangeNotifier state
        ├── screens/              auth, admin, student
        └── widgets/              timer, question palette, option tile, states
```

---

## What is verified, and what is not

This section is deliberately specific. A "works" claim that has not been
executed is worth nothing.

### Verified — executed, with output

| What | How |
|---|---|
| Exam creation from a real `.xlsx` upload | End-to-end test generates a workbook with the `xlsx` library and posts it as multipart |
| **The answer key does not reach the student** | Asserted against the raw response text of the start endpoint |
| Grading, including negative marking and unattempted questions | Unit tests plus an end-to-end assertion of an exact score (17.5 with a -0.25 penalty) |
| Server-side timer and deadline handling | Attempt lifecycle exercised over HTTP; `timeTakenSeconds` asserted to be server-measured |
| Pass/fail boundary and grade bands | Unit tests either side of every band |
| Role escalation is impossible via register | Test registers with `role: "admin"` and asserts the stored role is `student` |
| Students cannot read other students' attempts, or reach admin routes | Asserted as 404 and 403 respectively |
| Deleting an exam cascades to its questions and attempts | Asserted after deletion |
| Malformed rows are reported without discarding valid ones | Test imports 4 of 5 rows and checks the skipped row is named |
| Flutter app compiles clean | `flutter analyze` — 0 issues |
| Flutter client logic | `flutter test` — 21 tests over the models and their edge cases |
| Flutter app builds for release | `flutter build web --release` succeeds |
| The whole journey through the UI, not just the API | The built web app was loaded in a real browser and driven end to end against the running server — described below |

Reproduce the test-backed rows with `cd backend && npm test`, then
`cd mcq_portal_app && flutter analyze && flutter test`. The walkthrough below is
not scripted, so it is described rather than re-runnable.

#### The UI walkthrough

The built app was served and driven in a browser against the live backend.
Screens were exercised by screen coordinate rather than by DOM selector (the
canvas caveat below), with a screenshot captured at each step:

admin sign-in · admin exam list · exam report · student sign-in · student exam
list · start-exam dialog · live exam with a running countdown · question palette
· option selection · mark-for-review · submit confirmation · graded result with
the per-question breakdown · result history · sign-out.

The counts were checked against the server rather than eyeballed. A paper
answered 7 correct, 1 wrong and 2 skipped on a 10-mark exam with a 0.25 penalty
graded to **6.75 / 67.5% / grade B / PASS**, and a second paper answered 1
correct and 8 wrong graded to **−1 / −10% / grade F** — the negative total being
the intended `not clamped at zero` policy, with the score ring correctly
flattening its arc instead of drawing backwards.

Two defects were found this way and fixed: the student history list went stale
after a submission because its tab stays alive inside an `IndexedStack`, and the
dashboard's Refresh button silently did nothing on any tab but the first.

### Not verified — and why

| What | Why not |
|---|---|
| `firestoreStore` against a real Firestore project | No Firebase project available. It is written to the same interface as `memoryStore` and is the one part of the backend that has never executed against its real backend. |
| `cloudinaryStorage` against real Cloudinary | No Cloudinary account available. Same situation. |
| Firebase ID token exchange (`POST /api/auth/firebase`) | Requires a real Firebase project and a signed-in client. |
| Selector-based UI automation | Flutter web renders into a canvas, so no widget can be addressed by DOM selector. The walkthrough above was driven by screen coordinates instead. That proves the screens work and talk to the API, but it is not a regression suite anyone should re-run. |
| Pixel-level layout on physical devices | Driven in a desktop browser window only. No device farm, and the iOS target was never built. |

If you want to close the first three gaps, pointing the app at a real Firebase
project and Cloudinary account is a `.env` change — the code path is the same
one the tests exercise against the local implementations.

### Known limitations

- Demo mode keeps data in memory. Restarting the server empties the database and
  re-seeds the admin.
- Uploaded files in local storage mode are written to `backend/uploads/`, which
  is gitignored.
- No rate limiting on the auth endpoints. That would be the first thing to add
  before any real deployment.
- Out of scope by agreement with the assignment scope: PDF result cards,
  charts, certificates, anti-cheating measures, dark mode, internationalisation,
  offline mode and push notifications.

---

## Deliberate deviations from the brief

Collected in one place so nothing looks like an oversight:

1. **Auth.** Backend-issued JWT instead of Firebase Auth on the client, with a
   `/api/auth/firebase` exchange endpoint as the migration seam. Reason above.
2. **Flutter dependencies.** No `firebase_*`, `google_sign_in` or
   `cloudinary_public` packages. The Flutter app talks only to this backend.
   This removes a large class of build failures — Firebase Flutter needs
   platform config files and Gradle edits — and it is more secure: no unsigned
   Cloudinary upload preset ships inside the client. Uploads still reach
   Cloudinary, via the backend.
3. **`fl_chart`, `pdf` and `path_provider` omitted**, because the features that
   needed them are out of scope.
4. **Dependency versions resolve from `pub` and `npm`** rather than the pinned
   versions in the brief, which date from 2023 and no longer resolve against a
   current SDK.

---

## License

MIT — written as coursework for ITM Skills University.
