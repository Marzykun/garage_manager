const pool = require('../config/db');

// Check if customer exists by phone
const getCustomerByPhone = async (phone) => {
  const result = await pool.query(
    'SELECT * FROM customers WHERE phone = $1',
    [phone]
  );
  return result.rows[0];
};

const searchCustomers = async (query) => {
  const result = await pool.query(
    `SELECT * FROM customers
     WHERE name ILIKE $1
     OR phone ILIKE $1
     ORDER BY name ASC
     LIMIT 20`,
    [`%${query}%`]
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