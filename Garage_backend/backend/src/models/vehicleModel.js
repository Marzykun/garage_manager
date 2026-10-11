const pool = require('../config/db');

const addVehicle = async (customer_id, vehicle_number, vehicle_type, brand, model, year, km_run, tyre_size) => {
  const result = await pool.query(
    `INSERT INTO vehicles 
      (customer_id, vehicle_number, vehicle_type, brand, model, year, km_run, tyre_size)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [customer_id, vehicle_number, vehicle_type, brand, model, year, km_run, tyre_size]
  );
  return result.rows[0];
};

const getVehicleByNumber = async (vehicle_number) => {
  const result = await pool.query(
    `SELECT * FROM vehicles WHERE vehicle_number = $1`,
    [vehicle_number]
  );
  return result.rows[0];
};
const getVehiclesByCustomer = async (customer_id) => {
  const result = await pool.query(
    `SELECT * FROM vehicles 
     WHERE customer_id = $1 
     ORDER BY created_at DESC`,
    [customer_id]
  );
  return result.rows;
};

const updateVehicleKm = async (id, km_run) => {
  const result = await pool.query(
    `UPDATE vehicles
     SET km_run = $1
     WHERE id = $2
     RETURNING *`,
    [km_run, id]
  );
  return result.rows[0];
};

// Fill in / correct type, make and model. Fields not sent are left as-is.
const updateVehicleDetails = async (id, vehicle_type, brand, model) => {
  const result = await pool.query(
    `UPDATE vehicles
     SET vehicle_type = COALESCE($1, vehicle_type),
         brand        = COALESCE($2, brand),
         model        = COALESCE($3, model)
     WHERE id = $4
     RETURNING *`,
    [vehicle_type, brand, model, id]
  );
  return result.rows[0];
};

module.exports = {
  addVehicle,
  updateVehicleDetails,
  getVehiclesByCustomer,
  updateVehicleKm,
  getVehicleByNumber,
};