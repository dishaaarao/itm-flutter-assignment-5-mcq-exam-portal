const multer = require('multer');
const path = require('path');
const HttpError = require('../utils/HttpError');

/**
 * Uploads are held in memory, never written to disk by Multer.
 *
 * The buffer is handed to the storage seam, which decides whether it lands in
 * uploads/ (local) or Cloudinary. That keeps exactly one write path to reason
 * about, and means a rejected file never hits the filesystem.
 */

const MAX_FILE_BYTES = 10 * 1024 * 1024; // 10 MB

const SPREADSHEET_EXTENSIONS = ['.xlsx', '.xls', '.csv'];
const SPREADSHEET_MIME_TYPES = [
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel',
  'text/csv',
  'application/csv',
  // Browsers and the Flutter file picker are inconsistent about CSV; the
  // extension check below is the real gate.
  'application/octet-stream',
  'text/plain',
];

/** @returns {multer.Options} */
function baseOptions() {
  return {
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_FILE_BYTES, files: 1 },
  };
}

/**
 * Wraps a configured Multer middleware so its errors arrive as HttpErrors and
 * therefore render through the standard envelope instead of a bare 500.
 */
function withErrorMapping(middleware) {
  return (req, res, next) =>
    middleware(req, res, (error) => {
      if (!error) return next();

      if (error instanceof multer.MulterError) {
        if (error.code === 'LIMIT_FILE_SIZE') {
          return next(
            HttpError.badRequest(`The file is too large. The limit is ${MAX_FILE_BYTES / (1024 * 1024)} MB.`),
          );
        }
        if (error.code === 'LIMIT_UNEXPECTED_FILE') {
          return next(HttpError.badRequest(`Unexpected file field "${error.field}".`));
        }
        return next(HttpError.badRequest(`Upload failed: ${error.message}`));
      }

      return next(error);
    });
}

/** Excel/CSV question sheet + optional cover image on the same request. */
const uploadExamFiles = withErrorMapping(
  multer({
    ...baseOptions(),
    fileFilter(req, file, cb) {
      if (file.fieldname === 'sheet' || file.fieldname === 'file') {
        const extension = path.extname(file.originalname || '').toLowerCase();
        const typeAllowed = SPREADSHEET_MIME_TYPES.includes(file.mimetype);
        if (!SPREADSHEET_EXTENSIONS.includes(extension) && !typeAllowed) {
          return cb(
            HttpError.badRequest(
              'The question sheet must be an .xlsx, .xls or .csv file.',
            ),
          );
        }
        return cb(null, true);
      }

      if (file.fieldname === 'image' || file.fieldname === 'cover') {
        if (!String(file.mimetype || '').startsWith('image/')) {
          return cb(HttpError.badRequest('The cover image must be an image file.'));
        }
        return cb(null, true);
      }

      return cb(HttpError.badRequest(`Unexpected file field "${file.fieldname}".`));
    },
  }).fields([
    { name: 'sheet', maxCount: 1 },
    { name: 'file', maxCount: 1 },
    { name: 'image', maxCount: 1 },
    { name: 'cover', maxCount: 1 },
  ]),
);

/** Single image upload, used for the student profile photo. */
const uploadImage = withErrorMapping(
  multer({
    ...baseOptions(),
    fileFilter(req, file, cb) {
      if (!String(file.mimetype || '').startsWith('image/')) {
        return cb(HttpError.badRequest('Only image files can be uploaded here.'));
      }
      return cb(null, true);
    },
  }).single('image'),
);

/** The question sheet from an uploadExamFiles request, under either spelling. */
function sheetFrom(req) {
  return req.files?.sheet?.[0] || req.files?.file?.[0] || null;
}

/** The optional cover image from an uploadExamFiles request. */
function imageFrom(req) {
  return req.files?.image?.[0] || req.files?.cover?.[0] || null;
}

module.exports = {
  MAX_FILE_BYTES,
  uploadExamFiles,
  uploadImage,
  sheetFrom,
  imageFrom,
};
