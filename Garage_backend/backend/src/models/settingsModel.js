const pool = require('../config/db');

// Get garage settings
const getGarageSettings = async () => {
  const result = await pool.query(
    `SELECT id, garage_name, open_time, close_time, working_days, gst_percent,
            address, phone, gstin
     FROM garage_settings LIMIT 1`
  );
  return result.rows[0];
};

// Update garage settings
const updateGarageSettings = async (garage_name, open_time, close_time, working_days, gst_percent, address, phone, gstin) => {
  const result = await pool.query(
    `UPDATE garage_settings
     SET garage_name  = $1,
         open_time    = $2,
         close_time   = $3,
         working_days = $4,
         gst_percent  = $5,
         address      = $6,
         phone        = $7,
         gstin        = $8
     WHERE id = 1
     RETURNING id, garage_name, open_time, close_time, working_days, gst_percent,
               address, phone, gstin`,
    [garage_name, open_time, close_time, working_days, gst_percent, address, phone, gstin]
  );
  return result.rows[0];
};

// Change mechanic garage password
const updateGaragePassword = async (new_password) => {
  const result = await pool.query(
    `UPDATE garage_settings
     SET password = $1
     WHERE id = 1
     RETURNING id`,
    [new_password]
  );
  return result.rows[0];
};

// Change owner username and password
const updateOwnerCredentials = async (username, new_password) => {
  const result = await pool.query(
    `UPDATE owner_credentials
     SET username = $1,
         password = $2
     WHERE id = 1
     RETURNING id, username`,
    [username, new_password]
  );
  return result.rows[0];
};

module.exports = {
  getGarageSettings,
  updateGarageSettings,
  updateGaragePassword,
  updateOwnerCredentials,
};