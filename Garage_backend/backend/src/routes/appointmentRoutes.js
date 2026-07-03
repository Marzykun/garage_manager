const express               = require('express');
const router                = express.Router();
const appointmentController = require('../controllers/appointmentController');

router.post('/',               appointmentController.createAppointment);
router.get('/',                appointmentController.getAllAppointments);
router.get('/:id',             appointmentController.getAppointmentById);
router.patch('/:id/accept',    appointmentController.acceptAppointment);
router.patch('/:id/reject',    appointmentController.rejectAppointment);
router.patch('/:id/cancel',    appointmentController.cancelAppointment);

module.exports = router;