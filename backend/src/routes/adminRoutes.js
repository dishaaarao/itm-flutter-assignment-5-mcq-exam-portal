const express = require('express');
const { authMiddleware } = require('../middlewares/authMiddleware');
const adminMiddleware = require('../middlewares/adminMiddleware');
const { uploadExamFiles } = require('../middlewares/uploadMiddleware');
const adminController = require('../controllers/adminController');

const router = express.Router();

// Every admin route needs a valid token AND the admin role.
router.use(authMiddleware, adminMiddleware);

router.post('/exams', uploadExamFiles, adminController.createExamFromUpload);
router.get('/exams', adminController.listExams);
router.get('/exams/:id', adminController.getExam);
router.put('/exams/:id', adminController.updateExam);
router.delete('/exams/:id', adminController.deleteExam);
router.get('/exams/:id/report', adminController.getExamReport);

router.get('/students', adminController.listStudents);
router.get('/students/:id/attempts', adminController.getStudentAttempts);

module.exports = router;
