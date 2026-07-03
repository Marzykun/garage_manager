const express    = require('express');
const router     = express.Router();
const tyreController = require('../controllers/tyreController');

router.post('/',           tyreController.addTyre);
router.get('/',            tyreController.getAllTyres);
router.get('/:id',         tyreController.getTyreById);
router.put('/:id',         tyreController.updateTyre);
router.patch('/:id/fit',   tyreController.fitTyre);
router.delete('/:id',      tyreController.deleteTyre);

module.exports = router;