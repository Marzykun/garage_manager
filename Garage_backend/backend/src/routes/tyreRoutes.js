const express    = require('express');
const router     = express.Router();
const tyreController = require('../controllers/tyreController');
const ownerOnly  = require('../middleware/ownerMiddleware');

router.post('/',          tyreController.addTyre);
router.get('/',            tyreController.getAllTyres);
router.get('/purchases',   tyreController.getPurchases);
router.get('/duplicates',          ownerOnly, tyreController.getDuplicates);
router.post('/merge-duplicates',   ownerOnly, tyreController.mergeDuplicates);
router.get('/:id',         tyreController.getTyreById);
router.put('/:id',         tyreController.updateTyre);
router.patch('/:id/fit',   tyreController.fitTyre);
router.delete('/:id',      tyreController.deleteTyre);

module.exports = router;