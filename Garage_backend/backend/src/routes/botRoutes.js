// Routes for the WhatsApp bot — authenticated via a shared API key (botAuthMiddleware),
// not the owner/mechanic JWT used by the app.
const express = require('express');
const router = express.Router();

const appointmentController = require('../controllers/appointmentController');
const vehicleController = require('../controllers/vehicleController');
const jobController = require('../controllers/jobController');

router.post('/appointments', appointmentController.createAppointment);
router.get('/appointments', appointmentController.getAllAppointments);
router.patch('/appointments/:id/cancel', appointmentController.cancelAppointment);

router.get('/vehicles/number/:plate', vehicleController.getVehicleByNumber);

router.get('/customers/:id/jobs', jobController.getJobsByCustomer);
router.patch('/jobs/:id/cancel', jobController.cancelJob);

module.exports = router;
