const pool = require('../config/db');

// Match key: lower-cased name with trimmed + collapsed whitespace, plus category.
// Shared by add-merge, edit-merge and the duplicates tools.
const keyOf = (n) => `lower(regexp_replace(btrim(${n}), '\\s+', ' ', 'g'))`;
const KEY = keyOf('name');
const clean = (n) => n.trim().replace(/\s+/g, ' ');

// Merge rows (given in created_at,id order, already locked FOR UPDATE) into the oldest:
// qty summed, price = newest row's if > 0 else kept row's, min stock = max, FKs repointed.
const mergeRows = async (client, rows) => {
  const keep = rows[0];
  const newest = rows[rows.length - 1];
  const price = parseFloat(newest.price) > 0 ? newest.price : keep.price;
  const qty = rows.reduce((a, r) => a + (r.quantity || 0), 0);
  const min = Math.max(...rows.map((r) => r.min_stock ?? 0));
  const ids = rows.slice(1).map((r) => r.id);
  await client.query(`UPDATE job_parts_used SET inventory_id = $1 WHERE inventory_id = ANY($2::uuid[])`, [keep.id, ids]);
  await client.query(`DELETE FROM inventory WHERE id = ANY($1::uuid[])`, [ids]);
  return (await client.query(
    `UPDATE inventory SET quantity = $2, price = $3, min_stock = $4 WHERE id = $1 RETURNING *`,
    [keep.id, qty, price, min])).rows[0];
};

// Same name + category => add to the existing row (oldest first) instead of a new card.
// `unit`/`min_stock`/`price` may be null = not provided; unit/min_stock only apply to a
// new row, a non-zero price also updates the existing one.
const addItem = async (name, category, quantity, unit, min_stock, price) => {
  name = clean(name);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SELECT pg_advisory_xact_lock(hashtext('inventory_add'))`);
    const hit = await client.query(
      `UPDATE inventory SET quantity = COALESCE(quantity, 0) + $3,
              price = CASE WHEN $4::numeric > 0 THEN $4::numeric ELSE price END
       WHERE id = (SELECT id FROM inventory
                   WHERE ${KEY} = ${keyOf('$1::text')} AND category = $2
                   ORDER BY created_at, id LIMIT 1)
       RETURNING *`,
      [name, category, quantity, price || 0]
    );
    if (hit.rows.length) {
      await client.query('COMMIT');
      return { ...hit.rows[0], merged: true, added: quantity };
    }
    const result = await client.query(
      `INSERT INTO inventory (name, category, quantity, unit, min_stock, price)
       VALUES ($1, $2, $3, COALESCE($4, 'pcs'), COALESCE($5, 5), $6)
       RETURNING *`,
      [name, category, quantity, unit, min_stock, price || 0]
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

// Groups of rows sharing name key + category (only groups with 2+ rows), oldest first.
const duplicateGroups = async (db) => {
  const r = await db.query(`SELECT *, ${KEY} AS mkey FROM inventory ORDER BY created_at, id`);
  const m = new Map();
  for (const row of r.rows) {
    const k = `${row.mkey}|${row.category}`;
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(row);
  }
  return [...m.values()].filter((g) => g.length > 1);
};

const getDuplicates = async () => {
  const groups = await duplicateGroups(pool);
  return groups.map((g) => ({
    name: g[0].name,
    category: g[0].category,
    merged_quantity: g.reduce((a, r) => a + (r.quantity || 0), 0),
    rows: g,
  }));
};

const mergeDuplicates = async () => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SELECT pg_advisory_xact_lock(hashtext('inventory_add'))`);
    await client.query(`SELECT 1 FROM inventory FOR UPDATE`);
    let merged_groups = 0, removed_rows = 0;
    for (const g of await duplicateGroups(client)) {
      await mergeRows(client, g);
      merged_groups++;
      removed_rows += g.length - 1;
    }
    await client.query('COMMIT');
    return { merged_groups, removed_rows };
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

// Editing a name+category onto another existing item merges the two (oldest kept).
// price null = leave unchanged.
const updateItem = async (id, name, category, quantity, unit, min_stock, price) => {
  name = clean(name);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SELECT pg_advisory_xact_lock(hashtext('inventory_add'))`);
    const r = await client.query(
      `UPDATE inventory SET name=$1, category=$2, quantity=$3, unit=$4, min_stock=$5, price=COALESCE($6::numeric, price)
       WHERE id=$7 RETURNING *`,
      [name, category, quantity, unit, min_stock, price, id]
    );
    if (!r.rows[0]) { await client.query('ROLLBACK'); return undefined; }
    const same = await client.query(
      `SELECT * FROM inventory WHERE ${KEY} = ${keyOf('$1::text')} AND category = $2
       ORDER BY created_at, id FOR UPDATE`, [name, category]);
    let item = r.rows[0], merged = false;
    if (same.rows.length > 1) {
      item = await mergeRows(client, same.rows);
      merged = true;
    }
    await client.query('COMMIT');
    return { ...item, merged };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
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
  getDuplicates,
  mergeDuplicates,
  updateStock,
  deleteItem,
};
