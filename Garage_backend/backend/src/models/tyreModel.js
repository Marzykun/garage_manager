const pool = require('../config/db');

// Adds stock. A tyre with the same brand/model/size/type/pattern (trimmed,
// case-insensitive) is merged into instead of duplicated. Always logs a purchase.
const addTyre = async (brand, model, size, vehicle_type, quantity, price, offer, pattern, unit_cost, dealer) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const norm = (c) => `LOWER(TRIM(COALESCE(${c}, '')))`;
    const key = [brand, model, size, vehicle_type, pattern].map((v) => (v || '').trim().toLowerCase());
    const found = await client.query(
      `SELECT id FROM tyre_stock
       WHERE ${norm('brand')} = $1 AND ${norm('model')} = $2 AND ${norm('size')} = $3
         AND ${norm('vehicle_type')} = $4 AND ${norm('pattern')} = $5
       ORDER BY created_at LIMIT 1 FOR UPDATE`,
      key
    );
    let row, merged = false;
    if (found.rows.length) {
      merged = true;
      row = (await client.query(
        `UPDATE tyre_stock SET quantity = COALESCE(quantity, 0) + $1, price = COALESCE($2, price)
         WHERE id = $3 RETURNING *`,
        [quantity, price, found.rows[0].id]
      )).rows[0];
    } else {
      row = (await client.query(
        `INSERT INTO tyre_stock
          (brand, model, size, vehicle_type, quantity, price, offer, pattern)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING *`,
        [brand, model, size, vehicle_type, quantity, price, offer, pattern]
      )).rows[0];
    }
    await client.query(
      `INSERT INTO tyre_purchases (tyre_id, brand, name, size, quantity, unit_cost, dealer)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [row.id, row.brand, row.model, row.size, quantity, unit_cost, dealer]
    );
    await client.query('COMMIT');
    return { ...row, merged };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

const getAllTyres = async (brand, size) => {
  let query = `SELECT * FROM tyre_stock`;
  const params = [];
  const conditions = [];

  if (brand) {
    params.push(brand);
    conditions.push(`LOWER(brand) = LOWER($${params.length})`);
  }
  if (size) {
    params.push(size);
    conditions.push(`size = $${params.length}`);
  }

  if (conditions.length > 0) query += ` WHERE ` + conditions.join(' AND ');
  query += ` ORDER BY brand, size`;

  const result = await pool.query(query, params);
  return result.rows;
};

const getTyreById = async (id) => {
  const result = await pool.query(`SELECT * FROM tyre_stock WHERE id = $1`, [id]);
  return result.rows[0];
};

const updateTyre = async (id, brand, model, size, vehicle_type, quantity, price, offer, pattern) => {
  const result = await pool.query(
    `UPDATE tyre_stock
     SET brand = $1, model = $2, size = $3, vehicle_type = $4,
         quantity = $5, price = $6, offer = $7, pattern = $8
     WHERE id = $9
     RETURNING *`,
    [brand, model, size, vehicle_type, quantity, price, offer, pattern, id]
  );
  return result.rows[0];
};

const reduceStock = async (id, quantity_used) => {
  const result = await pool.query(
    `UPDATE tyre_stock
     SET quantity = quantity - $1
     WHERE id = $2 AND quantity >= $1
     RETURNING *`,
    [quantity_used, id]
  );
  return result.rows[0];
};

const deleteTyre = async (id) => {
  const result = await pool.query(
    `DELETE FROM tyre_stock WHERE id = $1 RETURNING *`,
    [id]
  );
  return result.rows[0];
};

const getPurchases = async () =>
  (await pool.query(`SELECT * FROM tyre_purchases ORDER BY created_at DESC LIMIT 50`)).rows;

module.exports = { getPurchases, addTyre, getAllTyres, getTyreById, updateTyre, reduceStock, deleteTyre };
