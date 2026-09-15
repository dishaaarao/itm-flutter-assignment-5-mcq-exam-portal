const express = require('express');
const { authMiddleware } = require('../middlewares/authMiddleware');
const { isFirebaseConfigured } = require('../config/firebase');
const authController = require('../controllers/authController');

const router = express.Router();

router.post('/register', authController.register);
router.post('/login', authController.login);
router.get('/me', authMiddleware, authController.me);

// Mounted only when credentials look present: without them the handler could
// only ever return an error, and a permanently broken route is worse than a
// missing one. Google Sign-In plugs in here without touching anything else.
if (isFirebaseConfigured()) {
  router.post('/firebase', authController.firebaseExchange);
}

module.exports = router;
