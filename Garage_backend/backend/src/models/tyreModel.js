const pool = require('../config/db');

const addTyre = async (brand, model, size, vehicle_type, quantity, price, offer) => {
  const result = await pool.query(
    `INSERT INTO tyre_stock
      (brand, model, size, vehicle_type, quantity, price, offer)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING *`,
    [brand, model, size, vehicle_type, quantity, price, offer]
  );
  return result.rows[0];
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

const updateTyre = async (id, brand, model, size, vehicle_type, quantity, price, offer) => {
  const result = await pool.query(
    `UPDATE tyre_stock
     SET brand = $1, model = $2, size = $3, vehicle_type = $4,
         quantity = $5, price = $6, offer = $7
     WHERE id = $8
     RETURNING *`,
    [brand, model, size, vehicle_type, quantity, price, offer, id]
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

module.exports = { addTyre, getAllTyres, getTyreById, updateTyre, reduceStock, deleteTyre };
