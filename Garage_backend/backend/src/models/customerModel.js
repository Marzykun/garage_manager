const pool = require('../config/db');

// Check if customer exists by phone
const getCustomerByPhone = async (phone) => {
  const result = await pool.query(
    'SELECT * FROM customers WHERE phone = $1',
    [phone]
  );
  return result.rows[0];
};

// Customer list for the Customers screen. With no filters it lists everyone,
// A–Z by name (sort='name', default) or most recent visit first (sort='recent'). Filters (any combination): free text (name, phone,
// number plate, vehicle make/model/type), a service they've had done, and a
// vehicle type. Plates match ignoring spaces/dashes ("KA 01-AB 1234").
const searchCustomers = async ({ q, service, vehicleType, sort = 'name', limit = 30, offset = 0 }) => {
  const where  = [];
  const params = [];

  if (q) {
    params.push(`%${q}%`);
    const like = `$${params.length}`;
    params.push(`%${q.toUpperCase().replace(/[^A-Z0-9]/g, '')}%`);
    const plate = `$${params.length}`;
    params.push(`%${q.replace(/\D/g, '')}%`);
    const digits = `$${params.length}`;
    where.push(`(
      c.name ILIKE ${like}
      OR c.phone ILIKE ${like}
      OR (length(${digits}) > 5 AND regexp_replace(c.phone, '[^0-9]', '', 'g') LIKE ${digits})
      OR EXISTS (
        SELECT 1 FROM vehicles v
        WHERE v.customer_id = c.id
          AND (
            (length(${plate}) > 2 AND regexp_replace(upper(v.vehicle_number), '[^A-Z0-9]', '', 'g') LIKE ${plate})
            OR v.brand ILIKE ${like}
            OR v.model ILIKE ${like}
            OR concat_ws(' ', v.brand, v.model) ILIKE ${like}
            OR v.vehicle_type ILIKE ${like}
          )
      )
    )`);
  }

  if (service && vehicleType) {
    // Both set: the service must have been done on a vehicle of that type
    // (a tyre change on their car shouldn't match "Bike + Tyre Change").
    params.push(service, vehicleType);
    where.push(`EXISTS (
      SELECT 1 FROM job_cards j
      JOIN vehicles v ON v.id = j.vehicle_id
      WHERE j.customer_id = c.id
        AND j.service_type = $${params.length - 1}
        AND lower(v.vehicle_type) = lower($${params.length})
    )`);
  } else if (service) {
    params.push(service);
    where.push(`EXISTS (
      SELECT 1 FROM job_cards j
      WHERE j.customer_id = c.id AND j.service_type = $${params.length}
    )`);
  } else if (vehicleType) {
    params.push(vehicleType);
    where.push(`EXISTS (
      SELECT 1 FROM vehicles v
      WHERE v.customer_id = c.id AND lower(v.vehicle_type) = lower($${params.length})
    )`);
  }

  const result = await pool.query(
    `SELECT
       c.*,
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
       COALESCE((
         SELECT array_agg(DISTINCT j.service_type::text)
         FROM job_cards j WHERE j.customer_id = c.id
       ), '{}') AS services,
       (SELECT COALESCE(SUM(i.total_amount), 0)
        FROM invoices i JOIN job_cards j ON j.id = i.job_card_id
        WHERE j.customer_id = c.id) AS total_spent
     FROM customers c
     ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
     ORDER BY ${sort === 'recent'
       ? 'last_visit DESC NULLS LAST, lower(c.name) ASC'
       : 'lower(c.name) ASC, c.created_at ASC'}
     LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
    [...params, limit, offset]
  );
  return result.rows;
};

// Create new customer
const createCustomer = async (name, phone, language_pref) => {
  const result = await pool.query(
    `INSERT INTO customers (name, phone, language_pref) 
     VALUES ($1, $2, $3) 
     RETURNING *`,
    [name, phone, language_pref]
  );
  return result.rows[0];
};

// Get customer with vehicles
const getCustomerWithVehicles = async (phone) => {
  const result = await pool.query(
    `SELECT c.*, 
      json_agg(v.*) as vehicles
     FROM customers c
     LEFT JOIN vehicles v ON v.customer_id = c.id
     WHERE c.phone = $1
     GROUP BY c.id`,
    [phone]
  );
  return result.rows[0];
};

module.exports = {
  getCustomerByPhone,
  createCustomer,
  getCustomerWithVehicles,
  searchCustomers,
};