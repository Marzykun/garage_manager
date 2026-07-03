const pool = require('../config/db');

const createAlignment = async (job_card_id, alignment_report, remarks) => {
  const result = await pool.query(
    `INSERT INTO wheel_alignment (job_card_id, alignment_report, remarks)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [job_card_id, alignment_report, remarks]
  );
  return result.rows[0];
};

const getAlignmentByJobId = async (job_card_id) => {
  const result = await pool.query(
    `SELECT * FROM wheel_alignment
     WHERE job_card_id = $1
     ORDER BY created_at ASC`,
    [job_card_id]
  );
  return result.rows;
};

const deleteAlignment = async (id) => {
  const result = await pool.query(
    `DELETE FROM wheel_alignment
     WHERE id = $1
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

module.exports = {
  createAlignment,
  getAlignmentByJobId,
  deleteAlignment,
};