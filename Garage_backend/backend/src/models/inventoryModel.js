const pool = require('../config/db');

// Same name (case-insensitive, trimmed) + same category => add to the existing
// row (oldest first, so pre-existing duplicates are left alone) instead of a new card.
// `unit`/`min_stock` may be null = not provided; they only apply to a new row.
const addItem = async (name, category, quantity, unit, min_stock) => {
  name = name.trim();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SELECT pg_advisory_xact_lock(hashtext('inventory_add'))`);
    const hit = await client.query(
      `UPDATE inventory SET quantity = COALESCE(quantity, 0) + $3
       WHERE id = (SELECT id FROM inventory
                   WHERE lower(btrim(name)) = lower($1) AND category = $2
                   ORDER BY created_at, id LIMIT 1)
       RETURNING *`,
      [name, category, quantity]
    );
    if (hit.rows.length) {
      await client.query('COMMIT');
      return { ...hit.rows[0], merged: true, added: quantity };
    }
    const result = await client.query(
      `INSERT INTO inventory (name, category, quantity, unit, min_stock)
       VALUES ($1, $2, $3, COALESCE($4, 'pcs'), COALESCE($5, 5))
       RETURNING *`,
      [name, category, quantity, unit, min_stock]
    );
    await client.query('COMMIT');
    return { ...result.rows[0], merged: false };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
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