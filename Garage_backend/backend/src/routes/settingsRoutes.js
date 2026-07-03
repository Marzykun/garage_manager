const express             = require('express');
const router              = express.Router();
const settingsController  = require('../controllers/settingsController');

router.get('/',                      settingsController.getSettings);
router.put('/',                      settingsController.updateSettings);
router.patch('/garage-password',     settingsController.updateGaragePassword);
router.patch('/owner-credentials',   settingsController.updateOwnerCredentials);

module.exports = router;