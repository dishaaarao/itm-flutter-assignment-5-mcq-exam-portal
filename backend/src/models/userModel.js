const bcrypt = require('bcryptjs');
const { store } = require('../data');

/**
 * Users are the only collection holding a secret, so every read path funnels
 * through toPublicUser() rather than relying on callers to delete the hash.
 */

const COLLECTION = 'users';
const SALT_ROUNDS = 10;
const ROLES = ['student', 'admin'];

/** Lowercased so "Admin@MCQ.local" and "admin@mcq.local" cannot coexist. */
function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

/** Strip the password hash — and anything else secret added later. */
function toPublicUser(user) {
  if (!user) return null;
  const { passwordHash, ...safe } = user;
  return safe;
}

function hashPassword(plain) {
  return bcrypt.hash(plain, SALT_ROUNDS);
}

function verifyPassword(plain, passwordHash) {
  if (!passwordHash) return Promise.resolve(false);
  return bcrypt.compare(plain, passwordHash);
}

async function findByEmail(email) {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;
  const matches = await store.find(COLLECTION, { where: { email: normalized }, limit: 1 });
  return matches[0] ?? null;
}

async function findById(id) {
  return store.findById(COLLECTION, id);
}

/**
 * Create a user. Callers must pass an already-hashed password.
 * @param {{name: string, email: string, passwordHash: string, role?: string, photoUrl?: string|null}} input
 */
async function createUser({ name, email, passwordHash, role = 'student', photoUrl = null }) {
  const normalized = normalizeEmail(email);
  const now = new Date().toISOString();

  return store.insert(COLLECTION, {
    name: String(name).trim(),
    email: normalized,
    passwordHash,
    role: ROLES.includes(role) ? role : 'student',
    photoUrl,
    createdAt: now,
    updatedAt: now,
  });
}

/** Convenience wrapper: hash, then create. */
async function registerUser({ name, email, password, role = 'student' }) {
  return createUser({
    name,
    email,
    passwordHash: await hashPassword(password),
    role,
  });
}

async function updateUser(id, patch) {
  const safePatch = { ...patch };
  delete safePatch.id;
  delete safePatch.passwordHash;
  delete safePatch.role;
  safePatch.updatedAt = new Date().toISOString();
  return store.update(COLLECTION, id, safePatch);
}

/** Overwrite the password hash. Kept separate so role can never ride along. */
async function setPassword(id, plain) {
  return store.update(COLLECTION, id, {
    passwordHash: await hashPassword(plain),
    updatedAt: new Date().toISOString(),
  });
}

async function listStudents() {
  const students = await store.find(COLLECTION, { where: { role: 'student' } });
  // Newest first — matches what an admin expects when they open the roster.
  return students
    .map(toPublicUser)
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
}

async function countByRole(role) {
  const users = await store.find(COLLECTION, { where: { role } });
  return users.length;
}

module.exports = {
  COLLECTION,
  ROLES,
  normalizeEmail,
  toPublicUser,
  hashPassword,
  verifyPassword,
  findByEmail,
  findById,
  createUser,
  registerUser,
  updateUser,
  setPassword,
  listStudents,
  countByRole,
};
