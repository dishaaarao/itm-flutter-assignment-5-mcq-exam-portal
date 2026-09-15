/**
 * Error carrying an HTTP status code.
 *
 * Controllers throw these; the central error handler turns them into the
 * standard `{ success: false, message, errors? }` envelope. Anything thrown
 * that is not an HttpError is treated as a 500 and its message is not leaked.
 */
class HttpError extends Error {
  /**
   * @param {number} status
   * @param {string} message
   * @param {string[]} [errors] field-level detail safe to show the client
   */
  constructor(status, message, errors) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    if (errors) this.errors = errors;
  }

  static badRequest(message, errors) {
    return new HttpError(400, message, errors);
  }

  static unauthorized(message = 'Authentication required.') {
    return new HttpError(401, message);
  }

  static forbidden(message = 'You do not have access to this resource.') {
    return new HttpError(403, message);
  }

  static notFound(message = 'Resource not found.') {
    return new HttpError(404, message);
  }

  static conflict(message) {
    return new HttpError(409, message);
  }
}

module.exports = HttpError;
