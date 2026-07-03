const pool = require('../config/db');

const createAppointment = async (customer_name, phone, vehicle_number, service_type, preferred_date, preferred_time, issue, language_pref) => {
  const result = await pool.query(
    `INSERT INTO appointments
      (customer_name, phone, vehicle_number, service_type, preferred_date, preferred_time, issue, language_pref, status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
     RETURNING *`,
    [customer_name, phone, vehicle_number, service_type, preferred_date, preferred_time, issue, language_pref]
  );
  return result.rows[0];
};

const getAllAppointments = async (status) => {
  let query = `SELECT * FROM appointments ORDER BY created_at DESC`;
  let params = [];

  if (status) {
    query = `SELECT * FROM appointments WHERE status = $1 ORDER BY created_at DESC`;
    params = [status];
  }

  const result = await pool.query(query, params);
  return result.rows;
};

const getAppointmentById = async (id) => {
  const result = await pool.query(
    `SELECT * FROM appointments WHERE id = $1`,
    [id]
  );
  return result.rows[0];
};

const updateStatus = async (id, status) => {
  const result = await pool.query(
    `UPDATE appointments
     SET status = $1
     WHERE id = $2
     RETURNING *`,
    [status, id]
  );
  return result.rows[0];
};

const deleteAppointment = async (id) => {
  const result = await pool.query(
    `DELETE FROM appointments
     WHERE id = $1
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

module.exports = {
  createAppointment,
  getAllAppointments,
  getAppointmentById,
  updateStatus,
  deleteAppointment,
};