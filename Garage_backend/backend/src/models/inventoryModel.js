const pool = require('../config/db');

const addItem = async (name, category, quantity, unit, min_stock) => {
  const result = await pool.query(
    `INSERT INTO inventory (name, category, quantity, unit, min_stock)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING *`,
    [name, category, quantity, unit, min_stock]
  );
  return result.rows[0];
};

const getAllItems = async (category) => {
  let query = `SELECT * FROM inventory ORDER BY category, name`;
  let params = [];

  if (category) {
    query = `SELECT * FROM inventory WHERE category = $1 ORDER BY name`;
    params = [category];
  }

  const result = await pool.query(query, params);
  return result.rows;
};

const getLowStockItems = async () => {
  const result = await pool.query(
    `SELECT * FROM inventory
     WHERE quantity <= min_stock
     ORDER BY quantity ASC`
  );
  return result.rows;
};

const updateItem = async (id, name, category, quantity, unit, min_stock) => {
  const result = await pool.query(
    `UPDATE inventory SET name=$1, category=$2, quantity=$3, unit=$4, min_stock=$5 WHERE id=$6 RETURNING *`,
    [name, category, quantity, unit, min_stock, id]
  );
  return result.rows[0];
};

const updateStock = async (id, quantity) => {
  const result = await pool.query(
    `UPDATE inventory
     SET quantity = $1
     WHERE id = $2
     RETURNING *`,
    [quantity, id]
  );
  return result.rows[0];
};

const deleteItem = async (id) => {
  const result = await pool.query(
    `DELETE FROM inventory
     WHERE id = $1
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

module.exports = {
  addItem,
  getAllItems,
  getLowStockItems,
  updateItem,
  updateStock,
  deleteItem,
};