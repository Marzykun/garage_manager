const pool = require('../config/db');

// ONE match key for add / edit / duplicate preview / merge: lower-cased, all whitespace runs
// collapsed to one space; size has all whitespace removed ('144 / 88' = '144/88').
const normSql = (c, noSpace) => noSpace
  ? `LOWER(regexp_replace(COALESCE(${c}, ''), '[[:space:]]+', '', 'g'))`
  : `LOWER(regexp_replace(TRIM(COALESCE(${c}, '')), '[[:space:]]+', ' ', 'g'))`;
const keyOf = (cols) => `concat_ws('|', ${cols.map((c, i) => normSql(c, i === 2)).join(', ')})`;
const KEY_SQL = keyOf(['brand', 'model', 'size', 'vehicle_type', 'pattern']);

// Adds stock. A tyre with the same brand/model/size/type/pattern (trimmed,
// case-insensitive) is merged into instead of duplicated. Always logs a purchase.
const addTyre = async (brand, model, size, vehicle_type, quantity, price, offer, pattern, unit_cost, dealer) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const found = await client.query(
      `SELECT id FROM tyre_stock WHERE ${KEY_SQL} = ${keyOf(['$1::text', '$2::text', '$3::text', '$4::text', '$5::text'])}
       ORDER BY created_at, id LIMIT 1 FOR UPDATE`,
      [brand, model, size, vehicle_type, pattern]
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

// Same match key as addTyre; groups with >1 row, oldest first (created_at, id).
const findDuplicateGroups = async (db) => {
  const { rows } = await db.query(
    `SELECT id, brand, model, size, vehicle_type, pattern, quantity, price, created_at,
            ${KEY_SQL} AS key
     FROM tyre_stock ORDER BY created_at, id`
  );
  const groups = new Map();
  for (const r of rows) {
    if (!groups.has(r.key)) groups.set(r.key, []);
    groups.get(r.key).push(r);
  }
  return [...groups.values()].filter((g) => g.length > 1);
};

const getDuplicateGroups = async () =>
  (await findDuplicateGroups(pool)).map((g) => ({
    brand: g[0].brand, model: g[0].model, size: g[0].size,
    vehicle_type: g[0].vehicle_type, pattern: g[0].pattern,
    merged_quantity: g.reduce((s, r) => s + (r.quantity || 0), 0),
    rows: g.map((r) => ({ id: r.id, quantity: r.quantity, price: r.price })),
  }));

// g = rows of one group, oldest first. Keep g[0], sum qty, price = newest row's price if > 0.
const mergeGroup = async (client, g) => {
  const keep = g[0].id;
  const others = g.slice(1).map((r) => r.id);
  await client.query('SELECT id FROM tyre_stock WHERE id = ANY($1) FOR UPDATE', [g.map((r) => r.id)]);
  const qty = g.reduce((s, r) => s + (r.quantity || 0), 0);
  const newest = [...g].reverse().find((r) => Number(r.price) > 0);
  const price = newest ? newest.price : g[0].price;
  for (const t of ['tyre_change_details', 'tyre_sales', 'tyre_purchases']) {
    await client.query(`UPDATE ${t} SET tyre_id = $1 WHERE tyre_id = ANY($2)`, [keep, others]);
  }
  await client.query('DELETE FROM tyre_stock WHERE id = ANY($1)', [others]);
  return (await client.query('UPDATE tyre_stock SET quantity = $1, price = $2 WHERE id = $3 RETURNING *', [qty, price, keep])).rows[0];
};

// Keeps the oldest row, sums quantity, price = newest row's price if > 0 (else kept row's),
// repoints all FKs to tyre_stock, deletes the rest. One transaction.
const mergeDuplicates = async () => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('LOCK TABLE tyre_stock IN SHARE ROW EXCLUSIVE MODE');
    const groups = await findDuplicateGroups(client);
    let removed = 0;
    for (const g of groups) {
      await mergeGroup(client, g);
      removed += g.length - 1;
    }
    await client.query('COMMIT');
    return { merged_groups: groups.length, removed_rows: removed };
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
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('LOCK TABLE tyre_stock IN SHARE ROW EXCLUSIVE MODE');
    const upd = await client.query(
      `UPDATE tyre_stock
       SET brand = $1, model = $2, size = $3, vehicle_type = $4,
           quantity = $5, price = $6, offer = $7, pattern = $8
       WHERE id = $9
       RETURNING *`,
      [brand, model, size, vehicle_type, quantity, price, offer, pattern, id]
    );
    let row = upd.rows[0];
    let merged = false;
    if (row) {
      // edit may have made this row equal to another one: merge into the oldest
      const g = (await findDuplicateGroups(client)).find((grp) => grp.some((r) => r.id === row.id));
      if (g) {
        row = await mergeGroup(client, g);
        merged = true;
      }
    }
    await client.query('COMMIT');
    return row && { ...row, merged };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
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

module.exports = { getDuplicateGroups, mergeDuplicates, getPurchases, addTyre, getAllTyres, getTyreById, updateTyre, reduceStock, deleteTyre };
