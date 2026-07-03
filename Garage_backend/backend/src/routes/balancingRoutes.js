const express    = require('express');
const router     = express.Router();
const balancingController = require('../controllers/balancingController');

router.post('/',                    balancingController.createBalancing);
router.get('/job/:job_card_id',     balancingController.getBalancingByJob);
router.delete('/:id',               balancingController.deleteBalancing);

module.exports = router;