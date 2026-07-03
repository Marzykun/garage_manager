const express        = require('express');
const router         = express.Router();
const authController = require('../controllers/authController');

router.post('/login',        authController.login);
router.post('/owner-login',  authController.ownerLogin);

module.exports = router;