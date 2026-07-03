const pool = require('../config/db');

// Add generic service details
const createServiceDetail = async (job_card_id, service_type, remarks, parts_used) => {
  const result = await pool.query(
    `INSERT INTO service_details (job_card_id, service_type, remarks, parts_used)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [job_card_id, service_type, remarks, parts_used]
  );
  return result.rows[0];
};

// Get service details for a job
const getServiceDetailByJobId = async (job_card_id) => {
  const result = await pool.query(
    `SELECT * FROM service_details
     WHERE job_card_id = $1
     ORDER BY created_at ASC`,
    [job_card_id]
  );
  return result.rows;
};

// Add tyre change details
const createTyreChange = async (job_card_id, tyre_id, quantity, remarks) => {
  const stockCheck = await pool.query(
    `SELECT quantity FROM tyre_stock WHERE id = $1`,
    [tyre_id]
  );

  if (stockCheck.rows.length === 0) throw new Error('Tyre not found');

  if (stockCheck.rows[0].quantity < quantity) {
    throw new Error(`Only ${stockCheck.rows[0].quantity} tyres available in stock`);
  }

  await pool.query(
    `UPDATE tyre_stock SET quantity = quantity - $1 WHERE id = $2`,
    [quantity, tyre_id]
  );

  const result = await pool.query(
    `INSERT INTO tyre_change_details (job_card_id, tyre_id, quantity, remarks)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [job_card_id, tyre_id, quantity, remarks]
  );
  return result.rows[0];
};

// Get tyre change details for a job
const getTyreChangeByJobId = async (job_card_id) => {
  const result = await pool.query(
    `SELECT
      tcd.*,
      t.brand,
      t.model,
      t.size,
      t.price
     FROM tyre_change_details tcd
     JOIN tyre_stock t ON t.id = tcd.tyre_id
     WHERE tcd.job_card_id = $1
     ORDER BY tcd.created_at ASC`,
    [job_card_id]
  );
  return result.rows;
};

module.exports = {
  createServiceDetail,
  getServiceDetailByJobId,
  createTyreChange,
  getTyreChangeByJobId,
};