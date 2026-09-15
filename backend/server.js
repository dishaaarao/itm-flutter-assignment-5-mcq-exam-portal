const fs = require('fs');
const express = require('express');
const cors = require('cors');

const { config, validate } = require('./src/config/env');
const routes = require('./src/routes');
const { notFoundHandler, errorHandler } = require('./src/middlewares/errorHandler');
const { seedAdmin } = require('./src/utils/seed');

/**
 * Builds the Express app without binding a port, so tests can drive the real
 * application over HTTP on an ephemeral port.
 */
function createApp() {
  const app = express();

  // Behind a proxy (ngrok, Render, a container) the client IP and protocol are
  // on the forwarded headers rather than the socket.
  app.set('trust proxy', true);
  app.disable('x-powered-by');

  app.use(cors());
  app.use(express.json({ limit: '2mb' }));
  app.use(express.urlencoded({ extended: true }));

  // Uploaded files are served straight off disk in local storage mode. In
  // cloudinary mode nothing is ever written here and this is a no-op.
  fs.mkdirSync(config.uploadsDir, { recursive: true });
  app.use('/uploads', express.static(config.uploadsDir, { maxAge: '1h' }));

  app.get('/', (req, res) => {
    res.json({
      success: true,
      message: 'MCQ Exam Portal API',
      data: {
        health: '/api/health',
        mode: { data: config.dataBackend, storage: config.storageBackend },
        endpoints: ['/api/auth', '/api/admin', '/api/student'],
      },
    });
  });

  app.use('/api', routes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

async function start() {
  // Fail fast on a misconfigured backend rather than on the first request.
  validate();

  const app = createApp();

  // The admin account cannot be created through the API (register forces the
  // student role), so without this the admin panel would be unreachable.
  await seedAdmin();

  const server = app.listen(config.port, () => {
    console.log(`\nMCQ Exam Portal API listening on http://localhost:${config.port}`);
    console.log(`  data backend    : ${config.dataBackend}`);
    console.log(`  storage backend : ${config.storageBackend}`);
    console.log(`  admin login     : ${config.seedAdmin.email} / ${config.seedAdmin.password}\n`);
  });

  return server;
}

if (require.main === module) {
  start().catch((error) => {
    console.error('[server] failed to start:', error.message);
    process.exitCode = 1;
  });
}

module.exports = { createApp, start };
