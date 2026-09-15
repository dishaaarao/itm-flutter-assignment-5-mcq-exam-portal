require('dotenv').config();

const { config } = require('../config/env');
const userModel = require('../models/userModel');

/**
 * Seed the one account that cannot bootstrap itself.
 *
 * Students register themselves, but an admin cannot — the register endpoint
 * forces role to 'student' — so without a seeded admin there is no way into
 * the admin panel at all. Idempotent: re-running never resets an existing
 * admin's password, so a demo store keeps any password change it was given.
 */
async function seedAdmin({ quiet = false } = {}) {
  const { name, email, password } = config.seedAdmin;

  const existing = await userModel.findByEmail(email);
  if (existing) {
    if (!quiet) console.log(`[seed] admin already present: ${email}`);
    return userModel.toPublicUser(existing);
  }

  const admin = await userModel.registerUser({ name, email, password, role: 'admin' });
  if (!quiet) {
    console.log(`[seed] created admin: ${email} / ${password}`);
  }
  return userModel.toPublicUser(admin);
}

/** Only runs when invoked directly (`npm run seed`), not on import. */
async function main() {
  const { validate } = require('../config/env');
  validate();
  await seedAdmin();
  console.log('[seed] done.');
}

if (require.main === module) {
  main().catch((error) => {
    console.error('[seed] failed:', error.message);
    process.exitCode = 1;
  });
}

module.exports = { seedAdmin };
