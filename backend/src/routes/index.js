const express = require('express');
const { config } = require('../config/env');
const authRoutes = require('./authRoutes');
const adminRoutes = require('./adminRoutes');
const studentRoutes = require('./studentRoutes');

const router = express.Router();

/** Lets the Flutter client — and a human with curl — confirm the active mode. */
router.get('/health', (req, res) => {
  res.json({
    success: true,
    data: {
      status: 'ok',
      dataBackend: config.dataBackend,
      storageBackend: config.storageBackend,
      uptimeSeconds: Math.round(process.uptime()),
    },
  });
});

router.use('/auth', authRoutes);
router.use('/admin', adminRoutes);
router.use('/student', studentRoutes);

module.exports = router;
