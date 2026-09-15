const jwt = require('jsonwebtoken');
const { config } = require('../config/env');
const HttpError = require('../utils/HttpError');
const userModel = require('../models/userModel');

/**
 * Verifies the Bearer token and loads the user fresh on every request.
 *
 * The role is read from the database rather than trusted from the token claim:
 * a token is valid for a week, and a demoted or deleted admin must lose access
 * immediately, not when their token happens to expire.
 */
async function authMiddleware(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    const [scheme, token] = header.split(' ');

    if (!token || scheme.toLowerCase() !== 'bearer') {
      throw HttpError.unauthorized('Missing or malformed Authorization header.');
    }

    let payload;
    try {
      payload = jwt.verify(token, config.jwt.secret);
    } catch (error) {
      const expired = error.name === 'TokenExpiredError';
      throw HttpError.unauthorized(
        expired ? 'Your session has expired. Please log in again.' : 'Invalid authentication token.',
      );
    }

    const user = await userModel.findById(payload.sub);
    if (!user) throw HttpError.unauthorized('This account no longer exists.');

    req.user = userModel.toPublicUser(user);
    req.userId = user.id;
    next();
  } catch (error) {
    next(error);
  }
}

/** Populates req.user when a valid token is present, but never rejects. */
async function optionalAuthMiddleware(req, res, next) {
  const header = req.headers.authorization || '';
  if (!header) return next();

  return authMiddleware(req, res, (error) => {
    if (error && error.status === 401) {
      req.user = null;
      return next();
    }
    return next(error);
  });
}

module.exports = { authMiddleware, optionalAuthMiddleware };
