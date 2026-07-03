const express    = require('express');
const router     = express.Router();
const jobController = require('../controllers/jobController');

router.post('/',                   jobController.createJob);
router.get('/',                    jobController.getAllJobs);
router.get('/customer/:id/jobs',   jobController.getJobsByCustomer);
router.get('/:id',                 jobController.getJobById);
router.patch('/:id/start',         jobController.startJob);
router.patch('/:id/complete',      jobController.completeJob);
router.patch('/:id/cancel',        jobController.cancelJob);
router.patch('/:id/ready',         jobController.markReadyForDelivery);

module.exports = router;