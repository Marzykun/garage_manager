const express    = require('express');
const router     = express.Router();
const vehicleController = require('../controllers/vehicleController');

router.post('/',                     vehicleController.addVehicle);
router.get('/lookup/:plate',         vehicleController.lookupByPlate);
router.get('/number/:plate',         vehicleController.getVehicleByNumber);
router.get('/customer/:customer_id', vehicleController.getVehiclesByCustomer);
router.patch('/:id',                 vehicleController.updateVehicleDetails);
router.patch('/:id/km',              vehicleController.updateVehicleKm);

module.exports = router;