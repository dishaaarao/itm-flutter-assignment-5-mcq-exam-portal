const path = require('path');
const fs = require('fs');
const { config } = require('./env');

/**
 * Firebase Admin SDK initialisation.
 *
 * Deliberately lazy: nothing is required or initialised until getDb() is first
 * called. `firebase-admin` throws while initialising if it cannot find usable
 * credentials, so eager init would break the credential-free DATA_BACKEND=memory
 * path entirely. This module is only ever reached when DATA_BACKEND=firestore.
 */

let db = null;
let attempted = false;
let initialised = false;
let initError = null;

function tryServiceAccountFile() {
  const configured = config.firebase.serviceAccountPath;
  const resolved = path.isAbsolute(configured)
    ? configured
    : path.resolve(process.cwd(), configured);

  if (!fs.existsSync(resolved)) return null;

  // eslint-disable-next-line global-require
  const { initializeApp, cert, getApps } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');
  // eslint-disable-next-line global-require, import/no-dynamic-require
  const serviceAccount = require(resolved);

  if (!getApps().length) initializeApp({ credential: cert(serviceAccount) });
  return getFirestore();
}

function tryInlineCredentials() {
  const { projectId, clientEmail, privateKey } = config.firebase;
  if (!projectId || !clientEmail || !privateKey) return null;

  // eslint-disable-next-line global-require
  const { initializeApp, cert, getApps } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');

  if (!getApps().length) {
    initializeApp({
      credential: cert({
        projectId,
        clientEmail,
        // Env vars carry literal \n sequences that must become real newlines.
        privateKey: privateKey.replace(/\\n/g, '\n'),
      }),
    });
  }
  return getFirestore();
}

function tryApplicationDefault() {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) return null;

  // eslint-disable-next-line global-require
  const { initializeApp, applicationDefault, getApps } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');

  if (!getApps().length) initializeApp({ credential: applicationDefault() });
  return getFirestore();
}

function initialise() {
  attempted = true;
  try {
    db =
      tryServiceAccountFile() ?? tryInlineCredentials() ?? tryApplicationDefault() ?? null;
    initialised = Boolean(db);
    if (db && typeof db.settings === 'function') {
      db.settings({ ignoreUndefinedProperties: true });
    }
  } catch (error) {
    initError = error;
    db = null;
    initialised = false;
  }

  if (!initialised) {
    console.warn(
      '\n============================================================\n' +
        '[Firebase] DATA_BACKEND=firestore but no usable credentials found.\n' +
        '  1. Firebase Console -> Project Settings -> Service Accounts\n' +
        '  2. Generate New Private Key, save as backend/serviceAccountKey.json\n' +
        '  3. Or set FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY\n' +
        '  Alternatively run with DATA_BACKEND=memory for a credential-free demo.\n' +
        '============================================================\n',
    );
  }
}

/** @returns {import('firebase-admin/firestore').Firestore|null} */
function getDb() {
  if (!attempted) initialise();
  return db;
}

/**
 * Admin Auth handle, for verifying Firebase ID tokens.
 *
 * Shares the app initialised by getDb()/initialise() so there is only one
 * Firebase app; throws a clear error if no credentials were usable.
 */
function getAuth() {
  if (!attempted) initialise();
  if (!initialised) {
    throw new Error(
      'Firebase Auth is not available: no usable Firebase credentials were found. ' +
        'See the Firebase section of .env.example.',
    );
  }
  // eslint-disable-next-line global-require
  const { getAuth: adminGetAuth } = require('firebase-admin/auth');
  return adminGetAuth();
}

function isFirebaseInitialized() {
  if (!attempted) initialise();
  return initialised;
}

/**
 * True when credentials *look* present, without loading firebase-admin.
 *
 * Used to decide whether to mount POST /api/auth/firebase at all, so a
 * credential-free deployment does not expose a route that can only fail.
 */
function isFirebaseConfigured() {
  const { serviceAccountPath, projectId, clientEmail, privateKey } = config.firebase;

  const resolved = path.isAbsolute(serviceAccountPath)
    ? serviceAccountPath
    : path.resolve(process.cwd(), serviceAccountPath);
  if (fs.existsSync(resolved)) return true;
  if (projectId && clientEmail && privateKey) return true;
  return Boolean(process.env.GOOGLE_APPLICATION_CREDENTIALS);
}

function getInitError() {
  return initError;
}

module.exports = { getDb, getAuth, isFirebaseInitialized, isFirebaseConfigured, getInitError };
