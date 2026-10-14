const express = require('express');
const router  = express.Router();
const ownerOnly = require('../middleware/ownerMiddleware');
const inventoryController = require('../controllers/inventoryController');

router.post('/',              inventoryController.addItem);
router.get('/duplicates',      inventoryController.getDuplicates);
router.post('/merge-duplicates', ownerOnly, inventoryController.mergeDuplicates);
router.get('/low-stock',      inventoryController.getLowStockItems);
router.get('/',               inventoryController.getAllItems);
router.put('/:id',            inventoryController.updateItem);
router.patch('/:id/stock',    inventoryController.updateStock);
router.delete('/:id',         inventoryController.deleteItem);

module.exports = router;