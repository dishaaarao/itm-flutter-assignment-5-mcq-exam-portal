const HttpError = require('../utils/HttpError');
const { config } = require('../config/env');

/** Terminal middleware for unmatched routes. */
function notFoundHandler(req, res, next) {
  next(HttpError.notFound(`No route matches ${req.method} ${req.originalUrl}.`));
}

/**
 * Central error handler — the single place the response envelope is built for
 * a failure.
 *
 * Anything that is not an HttpError is treated as an internal fault and its
 * message is withheld: a stack trace or a driver error string can disclose
 * paths, queries and configuration. Those are logged server-side instead.
 */
// eslint-disable-next-line no-unused-vars -- Express identifies this by arity.
function errorHandler(error, req, res, next) {
  const isHttpError = error instanceof HttpError;
  const status = isHttpError ? error.status : 500;

  if (!isHttpError) {
    console.error(`[error] ${req.method} ${req.originalUrl} →`, error);
  }

  const message = isHttpError
    ? error.message
    : 'Something went wrong on the server. Please try again.';

  const payload = { success: false, message };
  if (isHttpError && error.errors) payload.errors = error.errors;

  // Surface the reason a 500 happened in development; never in production.
  if (!isHttpError && !config.isProduction && error.message) {
    payload.debug = error.message;
  }

  res.status(status).json(payload);
}

module.exports = { notFoundHandler, errorHandler };
