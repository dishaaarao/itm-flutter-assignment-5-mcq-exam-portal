const express = require('express');
const { authMiddleware } = require('../middlewares/authMiddleware');
const { uploadImage } = require('../middlewares/uploadMiddleware');
const examController = require('../controllers/examController');
const attemptController = require('../controllers/attemptController');
const authController = require('../controllers/authController');

const router = express.Router();

router.use(authMiddleware);

router.get('/exams', examController.listExams);
router.get('/exams/:id/start', examController.startExam);
router.get('/exams/:id/questions', examController.getExamQuestions);

router.post('/attempts/:id/submit', attemptController.submit);
router.get('/attempts', attemptController.history);
router.get('/attempts/:id', attemptController.getResult);

router.post('/profile/photo', uploadImage, authController.uploadProfilePhoto);

module.exports = router;
