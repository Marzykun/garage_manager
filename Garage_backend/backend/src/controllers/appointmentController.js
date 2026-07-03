const appointmentModel = require('../models/appointmentModel');
const whatsappService  = require('../services/whatsappService');
const pool             = require('../config/db');

// POST /api/appointments
// Called by WhatsApp bot when customer books
const createAppointment = async (req, res, next) => {
  try {
    const customer_name  = req.body.customer_name;
    const phone          = req.body.phone;
    const vehicle_number = req.body.vehicle_number;
    const service_type   = req.body.service_type;
    const preferred_date = req.body.preferred_date;
    const preferred_time = req.body.preferred_time;
    const issue          = req.body.issue;
    const language_pref  = req.body.language_pref;

    if (!customer_name || !phone) {
      return res.status(400).json({
        success: false,
        message: 'customer_name and phone are required',
      });
    }

    const appointment = await appointmentModel.createAppointment(
      customer_name,
      phone,
      vehicle_number || null,
      service_type   || null,
      preferred_date || null,
      preferred_time || null,
      issue          || null,
      language_pref  || 'EN'
    );

    // Notify customer that booking is received
    await whatsappService.sendBookingConfirmation(
      phone,
      customer_name,
      preferred_date,
      preferred_time
    );

    res.status(201).json({
      success: true,
      message: 'Appointment created and customer notified',
      data: appointment,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/appointments
const getAllAppointments = async (req, res, next) => {
  try {
    const status = req.query.status;
    const appointments = await appointmentModel.getAllAppointments(status);

    res.status(200).json({
      success: true,
      count: appointments.length,
      data: appointments,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/appointments/:id
const getAppointmentById = async (req, res, next) => {
  try {
    const appointment = await appointmentModel.getAppointmentById(req.params.id);

    if (!appointment) {
      return res.status(404).json({
        success: false,
        message: 'Appointment not found',
      });
    }

    res.status(200).json({
      success: true,
      data: appointment,
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/appointments/:id/accept
// Auto creates customer, vehicle and job card from appointment data
const acceptAppointment = async (req, res, next) => {
  try {
    const appointment = await appointmentModel.getAppointmentById(req.params.id);

    if (!appointment) {
      return res.status(404).json({
        success: false,
        message: 'Appointment not found',
      });
    }

    if (appointment.status !== 'pending') {
      return res.status(400).json({
        success: false,
        message: 'Appointment is no longer pending',
      });
    }

    // Step 1 — find or create customer
    let customerResult = await pool.query(
      `SELECT * FROM customers WHERE phone = $1`,
      [appointment.phone]
    );

    let customer;
    if (customerResult.rows.length === 0) {
      const newCustomer = await pool.query(
        `INSERT INTO customers (name, phone)
         VALUES ($1, $2) RETURNING *`,
        [appointment.customer_name, appointment.phone]
      );
      customer = newCustomer.rows[0];
    } else {
      customer = customerResult.rows[0];
    }

    // Step 2 — find or create vehicle
    let vehicleResult = await pool.query(
      `SELECT * FROM vehicles WHERE vehicle_number = $1`,
      [appointment.vehicle_number]
    );

    let vehicle;
    if (vehicleResult.rows.length === 0 && appointment.vehicle_number) {
      const newVehicle = await pool.query(
        `INSERT INTO vehicles (customer_id, vehicle_number)
         VALUES ($1, $2) RETURNING *`,
        [customer.id, appointment.vehicle_number]
      );
      vehicle = newVehicle.rows[0];
    } else {
      vehicle = vehicleResult.rows[0];
    }

    // Step 3 — create job card
    const jobResult = await pool.query(
      `INSERT INTO job_cards
        (customer_id, vehicle_id, service_type, service_date, service_time, notes, source, status)
       VALUES ($1, $2, $3, $4, $5, $6, 'whatsapp', 'in_progress')
       RETURNING *`,
      [
        customer.id,
        vehicle ? vehicle.id : null,
        appointment.service_type || 'other',
        appointment.preferred_date || null,
        appointment.preferred_time || null,
        appointment.issue || null,
      ]
    );

    const job = jobResult.rows[0];

    // Step 4 — update appointment status
    await appointmentModel.updateStatus(appointment.id, 'accepted');

    // Step 5 — notify customer
    await whatsappService.sendAppointmentAccepted(
      appointment.phone,
      appointment.customer_name,
      appointment.preferred_date,
      appointment.preferred_time,
      appointment.vehicle_number,
      appointment.service_type
    );

    res.status(200).json({
      success: true,
      message: 'Appointment accepted and job card created',
      data: {
        appointment_id: appointment.id,
        job_card_id: job.id,
        customer_id: customer.id,
      },
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/appointments/:id/reject
const rejectAppointment = async (req, res, next) => {
  try {
    const appointment = await appointmentModel.getAppointmentById(req.params.id);

    if (!appointment) {
      return res.status(404).json({
        success: false,
        message: 'Appointment not found',
      });
    }

    // Notify customer
    await whatsappService.sendAppointmentRejected(
      appointment.phone,
      appointment.customer_name,
      appointment.vehicle_number,
      appointment.service_type,
      req.body.reason
    );

    // Delete appointment
    await appointmentModel.deleteAppointment(appointment.id);

    res.status(200).json({
      success: true,
      message: 'Appointment rejected and customer notified',
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/appointments/:id/cancel
// Self-service cancel by the customer via WhatsApp bot (no notification —
// the bot replies to the customer directly). Only allowed while pending.
const cancelAppointment = async (req, res, next) => {
  try {
    const appointment = await appointmentModel.getAppointmentById(req.params.id);

    if (!appointment) {
      return res.status(404).json({
        success: false,
        message: 'Appointment not found',
      });
    }

    if (appointment.status !== 'pending') {
      return res.status(409).json({
        success: false,
        message: 'Appointment already accepted — cannot cancel here',
      });
    }

    await appointmentModel.deleteAppointment(appointment.id);

    res.status(200).json({
      success: true,
      message: 'Appointment cancelled',
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  createAppointment,
  getAllAppointments,
  getAppointmentById,
  acceptAppointment,
  rejectAppointment,
  cancelAppointment,
};