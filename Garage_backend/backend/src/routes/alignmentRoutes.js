const express    = require('express');
const router     = express.Router();
const alignmentController = require('../controllers/alignmentController');

router.post('/',                    alignmentController.createAlignment);
router.get('/job/:job_card_id',     alignmentController.getAlignmentByJob);
router.delete('/:id',               alignmentController.deleteAlignment);

module.exports = router;