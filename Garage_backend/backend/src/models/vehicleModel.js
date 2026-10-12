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

// Number plates match ignoring case, spaces and dashes, so "ka 01-ab 1234"
// finds KA01AB1234 instead of creating a duplicate vehicle.
const PLATE_KEY = `regexp_replace(upper(vehicle_number), '[^A-Z0-9]', '', 'g')`;
const plateKey  = (plate) => String(plate || '').toUpperCase().replace(/[^A-Z0-9]/g, '');

const getVehicleByNumber = async (vehicle_number) => {
  const result = await pool.query(
    `SELECT * FROM vehicles WHERE ${PLATE_KEY} = $1 ORDER BY created_at LIMIT 1`,
    [plateKey(vehicle_number)]
  );
  return result.rows[0];
};

// Everything New Job needs to pre-fill for a returning vehicle: the vehicle,
// its owner, and the last 3 visits (service, date, km, amount).
const lookupByPlate = async (plate) => {
  const vehicle = await getVehicleByNumber(plate);
  if (!vehicle) return null;

  const [customerRes, jobsRes] = await Promise.all([
    // Same shape as a Customers-list row, so the app can open the customer's
    // details screen straight from New Job.
    pool.query(
      `SELECT
         c.id, c.name, c.phone,
         COALESCE((
           SELECT json_agg(json_build_object(
                    'vehicle_number', v.vehicle_number,
                    'vehicle_type',   v.vehicle_type,
                    'brand',          v.brand,
                    'model',          v.model
                  ) ORDER BY v.created_at)
           FROM vehicles v WHERE v.customer_id = c.id
         ), '[]') AS vehicles,
         (SELECT COUNT(*)::int FROM job_cards j
          WHERE j.customer_id = c.id AND j.status <> 'cancelled') AS visit_count,
         (SELECT MAX(j.created_at) FROM job_cards j
          WHERE j.customer_id = c.id AND j.status <> 'cancelled') AS last_visit,
         (SELECT COALESCE(SUM(i.total_amount), 0)
          FROM invoices i JOIN job_cards j ON j.id = i.job_card_id
          WHERE j.customer_id = c.id) AS total_spent
       FROM customers c WHERE c.id = $1`,
      [vehicle.customer_id]
    ),
    pool.query(
      `SELECT j.id, j.service_type, j.status, j.created_at, j.km_reading, i.total_amount
       FROM job_cards j
       LEFT JOIN invoices i ON i.job_card_id = j.id
       WHERE j.vehicle_id = $1 AND j.status <> 'cancelled'
       ORDER BY j.created_at DESC
       LIMIT 3`,
      [vehicle.id]
    ),
  ]);

  const countRes = await pool.query(
    `SELECT COUNT(*)::int AS n FROM job_cards WHERE vehicle_id = $1 AND status <> 'cancelled'`,
    [vehicle.id]
  );

  return {
    vehicle,
    customer: customerRes.rows[0] || null,
    recent_jobs: jobsRes.rows,
    visit_count: countRes.rows[0].n,
  };
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
  lookupByPlate,
  updateVehicleDetails,
  getVehiclesByCustomer,
  updateVehicleKm,
  getVehicleByNumber,
};