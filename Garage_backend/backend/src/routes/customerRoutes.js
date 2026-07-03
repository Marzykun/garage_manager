const express          = require('express');
const router           = express.Router();
const customerController = require('../controllers/customerController');
const jobController    = require('../controllers/jobController');

router.get('/search',        customerController.searchCustomers);
router.get('/lookup/:phone', customerController.lookupCustomer);
router.get('/:id/jobs',      jobController.getJobsByCustomer);
router.post('/',             customerController.createCustomer);

module.exports = router;