const HttpError = require('../utils/HttpError');

/**
 * Requires req.user.role === 'admin'. Must run after authMiddleware.
 *
 * Separate from authMiddleware so that a missing token (401) and an
 * authenticated non-admin (403) stay distinguishable to the client.
 */
function adminMiddleware(req, res, next) {
  if (!req.user) {
    return next(HttpError.unauthorized());
  }
  if (req.user.role !== 'admin') {
    return next(HttpError.forbidden('This action requires an administrator account.'));
  }
  return next();
}

module.exports = adminMiddleware;
