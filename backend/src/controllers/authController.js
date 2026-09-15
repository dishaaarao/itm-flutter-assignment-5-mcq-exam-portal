const jwt = require('jsonwebtoken');
const { config } = require('../config/env');
const HttpError = require('../utils/HttpError');
const { validateRegistration, validateLogin } = require('../utils/validate');
const { storage } = require('../storage');
const userModel = require('../models/userModel');

/**
 * One auth flow, in both demo and credentialed mode.
 *
 * The brief specifies Firebase Auth on the client with Admin SDK verification
 * server-side. That cannot run without a Firebase project, so the portal uses
 * a backend-issued JWT for both modes; /firebase is the seam a real Firebase
 * sign-in plugs into without disturbing anything else. See README.
 */

function signToken(user) {
  return jwt.sign(
    { sub: user.id, role: user.role, email: user.email },
    config.jwt.secret,
    { expiresIn: config.jwt.expiresIn },
  );
}

/** The shape every auth response returns. */
function authPayload(user) {
  return { token: signToken(user), user: userModel.toPublicUser(user) };
}

async function register(req, res, next) {
  try {
    const errors = validateRegistration(req.body);
    if (errors.length > 0) throw HttpError.badRequest('Please correct the errors below.', errors);

    const email = userModel.normalizeEmail(req.body.email);
    if (await userModel.findByEmail(email)) {
      throw HttpError.conflict('An account with this email already exists.');
    }

    // role is forced to 'student': any role sent by the client is ignored, so
    // the register endpoint cannot be used to mint an admin.
    const user = await userModel.registerUser({
      name: req.body.name,
      email,
      password: req.body.password,
      role: 'student',
    });

    res.status(201).json({
      success: true,
      message: 'Account created successfully.',
      data: authPayload(user),
    });
  } catch (error) {
    next(error);
  }
}

async function login(req, res, next) {
  try {
    const errors = validateLogin(req.body);
    if (errors.length > 0) throw HttpError.badRequest('Please correct the errors below.', errors);

    const user = await userModel.findByEmail(req.body.email);

    // Same message whether the email is unknown or the password is wrong, so
    // the endpoint cannot be used to enumerate registered addresses.
    const genericFailure = HttpError.unauthorized('Incorrect email or password.');
    if (!user) throw genericFailure;

    const matches = await userModel.verifyPassword(req.body.password, user.passwordHash);
    if (!matches) throw genericFailure;

    res.json({
      success: true,
      message: `Welcome back, ${user.name}.`,
      data: authPayload(user),
    });
  } catch (error) {
    next(error);
  }
}

async function me(req, res, next) {
  try {
    res.json({ success: true, data: { user: req.user } });
  } catch (error) {
    next(error);
  }
}

/**
 * Exchange a Firebase ID token for a portal JWT.
 *
 * Only mounted when Firebase is configured. The Firebase token proves identity;
 * the role and profile still come from our own users collection, so a Firebase
 * account cannot grant itself admin rights here either.
 */
async function firebaseExchange(req, res, next) {
  try {
    const idToken = req.body?.idToken;
    if (typeof idToken !== 'string' || idToken.trim() === '') {
      throw HttpError.badRequest('idToken is required.');
    }

    // Lazy so firebase-admin is never loaded unless this route is reachable.
    const { getAuth } = require('../config/firebase');
    const decoded = await getAuth().verifyIdToken(idToken);

    const email = userModel.normalizeEmail(decoded.email);
    if (!email) {
      throw HttpError.badRequest('The Firebase account has no email address.');
    }

    let user = await userModel.findByEmail(email);
    if (!user) {
      user = await userModel.createUser({
        name: decoded.name || email.split('@')[0],
        email,
        // Firebase owns this account's credentials, so there is no local
        // password to store. Login must go through Firebase.
        passwordHash: null,
        role: 'student',
        photoUrl: decoded.picture || null,
      });
    }

    res.json({
      success: true,
      message: `Signed in as ${user.name}.`,
      data: authPayload(user),
    });
  } catch (error) {
    // Firebase failures carry operator-facing detail; present them as a 401.
    if (error && typeof error.code === 'string' && error.code.startsWith('auth/')) {
      return next(HttpError.unauthorized('The Firebase sign-in token could not be verified.'));
    }
    return next(error);
  }
}

/**
 * Replace the signed-in user's profile photo through the storage seam.
 * The previous image is deleted afterwards so repeated uploads do not
 * accumulate orphaned files.
 */
async function uploadProfilePhoto(req, res, next) {
  try {
    if (!req.file) {
      throw HttpError.badRequest('Attach an image as the "image" field.');
    }

    const previousUrl = req.user.photoUrl;
    const uploaded = await storage.upload(req.file.buffer, {
      folder: 'profile-photos',
      filename: req.file.originalname,
      mimetype: req.file.mimetype,
    });

    const updated = await userModel.updateUser(req.user.id, { photoUrl: uploaded.url });

    // Best effort — a failed cleanup must not undo a successful upload.
    if (previousUrl && previousUrl !== uploaded.url) {
      await storage.destroy(previousUrl).catch(() => {});
    }

    res.json({
      success: true,
      message: 'Profile photo updated.',
      data: { user: userModel.toPublicUser(updated) },
    });
  } catch (error) {
    next(error);
  }
}

module.exports = { register, login, me, firebaseExchange, uploadProfilePhoto, signToken };
