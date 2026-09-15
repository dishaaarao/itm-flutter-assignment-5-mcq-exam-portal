const HttpError = require('../utils/HttpError');
const { validateExamMetadata } = require('../utils/validate');
const { parseQuestionsFromBuffer } = require('../utils/excelParser');
const { storage } = require('../storage');
const examModel = require('../models/examModel');
const questionModel = require('../models/questionModel');
const attemptModel = require('../models/attemptModel');
const userModel = require('../models/userModel');
const { sheetFrom, imageFrom } = require('../middlewares/uploadMiddleware');

/**
 * Admin-facing endpoints: create exams from a spreadsheet, manage them, and
 * read the report for one exam.
 */

/**
 * Create an exam from an uploaded question sheet.
 *
 * The sheet is parsed before anything is written, so a sheet with missing
 * columns leaves no half-built exam behind. A cover image is optional and is
 * uploaded through the storage seam (local folder or Cloudinary).
 */
async function createExamFromUpload(req, res, next) {
  let uploadedImage = null;
  try {
    const sheet = sheetFrom(req);
    if (!sheet) {
      throw HttpError.badRequest(
        'Attach the question sheet as the "sheet" field of a multipart/form-data request.',
      );
    }

    const errors = validateExamMetadata(req.body);
    if (errors.length > 0) throw HttpError.badRequest('Please correct the errors below.', errors);

    // Parse first: cheap, side-effect free, and it rejects a bad sheet before
    // an exam document or any uploaded image exists.
    const { questions, errors: rowErrors, sheetName } = parseQuestionsFromBuffer(sheet.buffer);

    if (questions.length === 0) {
      throw HttpError.badRequest(
        `No usable questions were found in sheet "${sheetName}".`,
        rowErrors.slice(0, 20).map((entry) => `Row ${entry.row}: ${entry.reason}`),
      );
    }

    const image = imageFrom(req);
    if (image) {
      uploadedImage = await storage.upload(image.buffer, {
        folder: 'exam-covers',
        filename: image.originalname,
        mimetype: image.mimetype,
      });
    }

    const exam = await examModel.createExam({
      ...req.body,
      questionCount: questions.length,
      imageUrl: uploadedImage?.url || null,
      imagePublicId: uploadedImage?.publicId || null,
      createdBy: req.user.id,
    });

    await questionModel.insertQuestions(exam.id, questions);
    await examModel.setQuestionCount(exam.id, questions.length);

    res.status(201).json({
      success: true,
      message:
        rowErrors.length > 0
          ? `Exam created with ${questions.length} question(s). ${rowErrors.length} row(s) were skipped.`
          : `Exam created with ${questions.length} question(s).`,
      data: {
        exam: { ...exam, questionCount: questions.length },
        imported: questions.length,
        skippedRows: rowErrors,
      },
      // Surfaced so the admin UI can list exactly which rows need fixing.
      ...(rowErrors.length > 0
        ? { errors: rowErrors.map((entry) => `Row ${entry.row}: ${entry.reason}`) }
        : {}),
    });
  } catch (error) {
    // The exam was never created, so an uploaded cover image is now orphaned.
    if (uploadedImage?.publicId) {
      await storage.destroy(uploadedImage.publicId).catch(() => {});
    }
    next(error);
  }
}

async function listExams(req, res, next) {
  try {
    const exams = await examModel.listAll();
    res.json({ success: true, count: exams.length, data: { exams } });
  } catch (error) {
    next(error);
  }
}

/** Full exam including the answer key — admin only. */
async function getExam(req, res, next) {
  try {
    const exam = await examModel.findById(req.params.id);
    if (!exam) throw HttpError.notFound('Exam not found.');

    const questions = await questionModel.listByExam(exam.id);
    res.json({
      success: true,
      data: {
        exam: { ...exam, questionCount: questions.length },
        questions: questions.map(questionModel.toAdminQuestion),
      },
    });
  } catch (error) {
    next(error);
  }
}

async function updateExam(req, res, next) {
  try {
    const exam = await examModel.findById(req.params.id);
    if (!exam) throw HttpError.notFound('Exam not found.');

    // Validate the merged view: a request that only changes passingMarks still
    // has to respect the existing totalMarks.
    const merged = { ...exam, ...req.body };
    const errors = validateExamMetadata(merged);
    if (errors.length > 0) throw HttpError.badRequest('Please correct the errors below.', errors);

    const updated = await examModel.updateExam(exam.id, req.body);
    res.json({ success: true, message: 'Exam updated.', data: { exam: updated } });
  } catch (error) {
    next(error);
  }
}

/** Cascades to the exam's questions and attempts, and frees the cover image. */
async function deleteExam(req, res, next) {
  try {
    const exam = await examModel.findById(req.params.id);
    if (!exam) throw HttpError.notFound('Exam not found.');

    const [questionsRemoved, attemptsRemoved] = await Promise.all([
      questionModel.removeByExam(exam.id),
      attemptModel.removeByExam(exam.id),
    ]);

    await examModel.removeExam(exam.id);

    // Best effort: a failed remote delete must not fail the exam deletion, or
    // the exam would be gone from the response but present in the database.
    if (exam.imagePublicId) {
      await storage.destroy(exam.imagePublicId).catch((error) => {
        console.warn(`[admin] could not delete image ${exam.imagePublicId}:`, error.message);
      });
    }

    res.json({
      success: true,
      message: `Exam deleted (${questionsRemoved} question(s), ${attemptsRemoved} attempt(s)).`,
      data: { id: exam.id },
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Per-exam report: one row per attempt plus the aggregate the dashboard shows.
 */
async function getExamReport(req, res, next) {
  try {
    const exam = await examModel.findById(req.params.id);
    if (!exam) throw HttpError.notFound('Exam not found.');

    const attempts = await attemptModel.listByExam(exam.id);

    res.json({
      success: true,
      count: attempts.length,
      data: {
        exam: {
          id: exam.id,
          title: exam.title,
          subject: exam.subject,
          totalMarks: exam.totalMarks,
          passingMarks: exam.passingMarks,
          negativeMarking: exam.negativeMarking,
        },
        summary: attemptModel.summarise(attempts),
        rows: attempts.map(attemptModel.toReportRow),
      },
    });
  } catch (error) {
    next(error);
  }
}

async function listStudents(req, res, next) {
  try {
    const students = await userModel.listStudents();
    res.json({ success: true, count: students.length, data: { students } });
  } catch (error) {
    next(error);
  }
}

async function getStudentAttempts(req, res, next) {
  try {
    const student = await userModel.findById(req.params.id);
    if (!student) throw HttpError.notFound('Student not found.');

    const attempts = await attemptModel.listByStudent(student.id);

    res.json({
      success: true,
      count: attempts.length,
      data: {
        student: userModel.toPublicUser(student),
        attempts: attempts.map(attemptModel.toReportRow),
      },
    });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  createExamFromUpload,
  listExams,
  getExam,
  updateExam,
  deleteExam,
  getExamReport,
  listStudents,
  getStudentAttempts,
};
