const express          = require('express');
const router           = express.Router();
const backupController = require('../controllers/backupController');

router.get('/',               backupController.getBackups);
router.post('/',              backupController.createBackup);
router.get('/:name/download', backupController.downloadBackup);
router.post('/:name/restore', backupController.restoreBackup);

module.exports = router;
