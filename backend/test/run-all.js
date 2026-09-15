/**
 * Runs every backend test file in one process.
 *
 * Run: npm test
 *
 * Written as a small spawner rather than a test framework because the rest of
 * the project uses this style already (plain `assert`, run with node) and one
 * less dependency is one less thing that can fail to install.
 */

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const testDir = __dirname;

const files = fs
  .readdirSync(testDir)
  .filter((name) => name.endsWith('.test.js'))
  // run-all.js is not a .test.js, but smoke last keeps the fast unit output on
  // top and the slower end-to-end walk at the bottom where it reads naturally.
  .sort((a, b) => {
    const weight = (name) => (name.includes('smoke') ? 1 : 0);
    return weight(a) - weight(b) || a.localeCompare(b);
  });

console.log(`Running ${files.length} test file(s)...\n`);

const results = files.map((file) => {
  const started = Date.now();
  const run = spawnSync(process.execPath, [path.join(testDir, file)], {
    stdio: 'inherit',
    env: { ...process.env, NODE_ENV: 'test' },
  });
  return { file, code: run.status ?? 1, ms: Date.now() - started };
});

console.log('─'.repeat(60));
results.forEach(({ file, code, ms }) => {
  const icon = code === 0 ? '✓' : '✗';
  console.log(`${icon} ${file} (${ms}ms)`);
});

const failed = results.filter((result) => result.code !== 0);
console.log('─'.repeat(60));

if (failed.length > 0) {
  console.error(`\n${failed.length} of ${results.length} test file(s) FAILED.\n`);
  process.exit(1);
}

console.log(`\nAll ${results.length} test file(s) passed.\n`);
