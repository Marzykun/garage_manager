const pool = require('../config/db');

// Add a balancing record for a job
const createBalancing = async (job_card_id, fl_weight, fr_weight, rl_weight, rr_weight, remarks, round_type) => {
  const result = await pool.query(
    `INSERT INTO wheel_balancing
      (job_card_id, fl_weight, fr_weight, rl_weight, rr_weight, remarks, round_type)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING *`,
    [job_card_id, fl_weight, fr_weight, rl_weight, rr_weight, remarks, round_type]
  );
  return result.rows[0];
};

const getBalancingByJobId = async (job_card_id) => {
  const result = await pool.query(
    `SELECT * FROM wheel_balancing
     WHERE job_card_id = $1
     ORDER BY created_at ASC`,
    [job_card_id]
  );
  return result.rows;
};

const deleteBalancing = async (id) => {
  const result = await pool.query(
    `DELETE FROM wheel_balancing
     WHERE id = $1
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

module.exports = {
  createBalancing,
  getBalancingByJobId,
  deleteBalancing,
};