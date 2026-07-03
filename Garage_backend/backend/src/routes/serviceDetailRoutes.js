const express                = require('express');
const router                 = express.Router();
const serviceDetailController = require('../controllers/serviceDetailController');

router.post('/',                          serviceDetailController.createServiceDetail);
router.get('/job/:job_card_id',           serviceDetailController.getServiceDetailByJob);
router.post('/tyre-change',               serviceDetailController.createTyreChange);
router.get('/tyre-change/job/:job_card_id', serviceDetailController.getTyreChangeByJob);

module.exports = router;