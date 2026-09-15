const path = require('path');
require('dotenv').config();

const DATA_BACKENDS = ['memory', 'firestore'];
const STORAGE_BACKENDS = ['local', 'cloudinary'];
const FALLBACK_JWT_SECRET = 'change-this-to-a-long-random-string';

/**
 * Parse a boolean-ish environment variable.
 * @param {string|undefined} value
 * @param {boolean} fallback
 * @returns {boolean}
 */
function readBool(value, fallback) {
  if (value === undefined || value === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
}

/**
 * Parse an integer environment variable, falling back when unusable.
 * @param {string|undefined} value
 * @param {number} fallback
 * @returns {number}
 */
function readInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function readEnum(value, allowed, fallback, label) {
  const normalised = String(value || fallback).toLowerCase();
  if (!allowed.includes(normalised)) {
    throw new Error(
      `Invalid ${label} "${value}". Expected one of: ${allowed.join(', ')}`,
    );
  }
  return normalised;
}

const nodeEnv = process.env.NODE_ENV || 'development';
const jwtSecret = process.env.JWT_SECRET || FALLBACK_JWT_SECRET;

// Refuse to run in production on the well-known fallback secret. A predictable
// signing key means anyone can mint an admin token.
if (nodeEnv === 'production' && jwtSecret === FALLBACK_JWT_SECRET) {
  throw new Error(
    'JWT_SECRET must be set to a strong random value when NODE_ENV=production.',
  );
}

const config = {
  port: readInt(process.env.PORT, 5050),
  nodeEnv,
  isProduction: nodeEnv === 'production',
  isTest: nodeEnv === 'test',

  dataBackend: readEnum(process.env.DATA_BACKEND, DATA_BACKENDS, 'memory', 'DATA_BACKEND'),
  storageBackend: readEnum(process.env.STORAGE_BACKEND, STORAGE_BACKENDS, 'local', 'STORAGE_BACKEND'),

  jwt: {
    secret: jwtSecret,
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  },

  submitGraceSeconds: readInt(process.env.SUBMIT_GRACE_SECONDS, 30),
  allowReattempt: readBool(process.env.ALLOW_REATTEMPT, false),

  seedAdmin: {
    name: 'Portal Administrator',
    email: process.env.SEED_ADMIN_EMAIL || 'admin@mcq.local',
    password: process.env.SEED_ADMIN_PASSWORD || 'Admin@123',
  },

  firebase: {
    serviceAccountPath:
      process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './serviceAccountKey.json',
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY,
  },

  cloudinary: {
    cloudName: process.env.CLOUDINARY_CLOUD_NAME || '',
    apiKey: process.env.CLOUDINARY_API_KEY || '',
    apiSecret: process.env.CLOUDINARY_API_SECRET || '',
  },

  uploadsDir: path.join(__dirname, '..', '..', 'uploads'),
};

/** True when every Cloudinary credential needed for signed uploads is present. */
config.cloudinary.isConfigured = Boolean(
  config.cloudinary.cloudName && config.cloudinary.apiKey && config.cloudinary.apiSecret,
);

/** True when Cloudinary is the selected storage backend AND is fully configured. */
config.usesCloudinary = config.storageBackend === 'cloudinary';
config.usesFirestore = config.dataBackend === 'firestore';

/**
 * Fail fast with an actionable message when the selected backend is missing
 * its credentials, rather than throwing an opaque error on first request.
 */
function validate() {
  if (config.usesCloudinary && !config.cloudinary.isConfigured) {
    throw new Error(
      'STORAGE_BACKEND=cloudinary requires CLOUDINARY_CLOUD_NAME, ' +
        'CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET. See .env.example. ' +
        'Use STORAGE_BACKEND=local to run without a Cloudinary account.',
    );
  }
}

module.exports = { config, validate };
