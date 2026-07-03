const pool = require('../config/db');

const createJob = async (customer_id, vehicle_id, service_type, service_date, service_time, notes, source) => {
  const result = await pool.query(
    `INSERT INTO job_cards 
      (customer_id, vehicle_id, service_type, service_date, service_time, notes, source, status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending')
     RETURNING *`,
    [customer_id, vehicle_id, service_type, service_date, service_time, notes, source]
  );
  return result.rows[0];
};

const getAllJobs = async (date) => {
  // date = 'YYYY-MM-DD' in IST. If provided, filter to that day only.
  const query = date
    ? `SELECT
        j.*,
        c.name        AS customer_name,
        c.phone       AS customer_phone,
        v.vehicle_number,
        v.brand,
        v.model,
        v.vehicle_type,
        v.km_run,
        v.tyre_size
       FROM job_cards j
       JOIN customers c ON c.id = j.customer_id
       JOIN vehicles  v ON v.id = j.vehicle_id
       WHERE DATE(j.created_at AT TIME ZONE 'Asia/Kolkata') = $1
       ORDER BY j.created_at DESC`
    : `SELECT
        j.*,
        c.name        AS customer_name,
        c.phone       AS customer_phone,
        v.vehicle_number,
        v.brand,
        v.model,
        v.vehicle_type,
        v.km_run,
        v.tyre_size
       FROM job_cards j
       JOIN customers c ON c.id = j.customer_id
       JOIN vehicles  v ON v.id = j.vehicle_id
       ORDER BY j.created_at DESC`;

  const result = await pool.query(query, date ? [date] : []);
  return result.rows;
};

const getJobById = async (id) => {
  const result = await pool.query(
    `SELECT 
      j.*,
      c.name        AS customer_name,
      c.phone       AS customer_phone,
      v.vehicle_number,
      v.brand,
      v.model,
      v.vehicle_type,
      v.km_run,
      v.tyre_size
     FROM job_cards j
     JOIN customers c ON c.id = j.customer_id
     JOIN vehicles  v ON v.id = j.vehicle_id
     WHERE j.id = $1`,
    [id]
  );
  return result.rows[0];
};

const getJobsByCustomerId = async (customer_id) => {
  const result = await pool.query(
    `SELECT
      j.*,
      v.vehicle_number,
      v.brand,
      v.model
     FROM job_cards j
     JOIN vehicles v ON v.id = j.vehicle_id
     WHERE j.customer_id = $1
     ORDER BY j.created_at DESC`,
    [customer_id]
  );
  return result.rows;
};

const startJob = async (id) => {
  const result = await pool.query(
    `UPDATE job_cards
     SET status = 'in_progress'
     WHERE id = $1 AND status = 'pending'
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

const completeJob = async (id) => {
  const result = await pool.query(
    `UPDATE job_cards
     SET status = 'completed',
         completed_at = now()
     WHERE id = $1 AND status = 'in_progress'
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

const cancelJob = async (id) => {
  const result = await pool.query(
    `UPDATE job_cards
     SET status = 'cancelled'
     WHERE id = $1
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

const markReadyForDelivery = async (id) => {
  const result = await pool.query(
    `UPDATE job_cards
     SET ready_for_delivery = TRUE
     WHERE id = $1
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

module.exports = {
  createJob,
  getAllJobs,
  getJobById,
  getJobsByCustomerId,
  startJob,
  completeJob,
  cancelJob,
  markReadyForDelivery,
};