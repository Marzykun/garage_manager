const pool = require('../config/db');

// Add generic service details. `items` = [{inventory_id, quantity}] picked from
// inventory: stock is checked + deducted and the lines stored in ONE transaction,
// and their "name ×qty" text is folded into parts_used (invoices read that column).
const createServiceDetail = async (job_card_id, service_type, remarks, parts_used, items = []) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const lines = [];
    for (const it of items) {
      const qty = parseInt(it.quantity, 10);
      if (!it.inventory_id || !(qty > 0)) throw new Error('Invalid inventory item or quantity');
      const inv = await client.query(
        `SELECT id, name, quantity FROM inventory WHERE id = $1 FOR UPDATE`, [it.inventory_id]);
      if (inv.rows.length === 0) throw new Error('Inventory item not found');
      const { name, quantity: stock } = inv.rows[0];
      if (stock < qty) {
        throw new Error(stock <= 0 ? `No stock for ${name}` : `Only ${stock} left for ${name}`);
      }
      await client.query(`UPDATE inventory SET quantity = quantity - $1 WHERE id = $2`, [qty, it.inventory_id]);
      lines.push({ inventory_id: it.inventory_id, quantity: qty, name });
    }
    const partsText = [...lines.map((l) => `${l.name} x${l.quantity}`), parts_used]
      .filter(Boolean).join(', ') || null;
    const result = await client.query(
      `INSERT INTO service_details (job_card_id, service_type, remarks, parts_used)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [job_card_id, service_type, remarks, partsText]
    );
    for (const l of lines) {
      await client.query(
        `INSERT INTO job_parts_used (job_card_id, service_detail_id, inventory_id, quantity, name)
         VALUES ($1, $2, $3, $4, $5)`,
        [job_card_id, result.rows[0].id, l.inventory_id, l.quantity, l.name]
      );
    }
    await client.query('COMMIT');
    return result.rows[0];
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
};

// Get service details for a job
const getServiceDetailByJobId = async (job_card_id) => {
  const result = await pool.query(
    `SELECT * FROM service_details
     WHERE job_card_id = $1
     ORDER BY created_at ASC`,
    [job_card_id]
  );
  return result.rows;
};

// Add tyre change details
const createTyreChange = async (job_card_id, tyre_id, quantity, remarks) => {
  const stockCheck = await pool.query(
    `SELECT quantity FROM tyre_stock WHERE id = $1`,
    [tyre_id]
  );

  if (stockCheck.rows.length === 0) throw new Error('Tyre not found');

  if (stockCheck.rows[0].quantity < quantity) {
    throw new Error(`Only ${stockCheck.rows[0].quantity} tyres available in stock`);
  }

  await pool.query(
    `UPDATE tyre_stock SET quantity = quantity - $1 WHERE id = $2`,
    [quantity, tyre_id]
  );

  const result = await pool.query(
    `INSERT INTO tyre_change_details (job_card_id, tyre_id, quantity, remarks)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [job_card_id, tyre_id, quantity, remarks]
  );
  return result.rows[0];
};

// Get tyre change details for a job
const getTyreChangeByJobId = async (job_card_id) => {
  const result = await pool.query(
    `SELECT
      tcd.*,
      t.brand,
      t.model,
      t.pattern,
      t.size,
      t.price
     FROM tyre_change_details tcd
     JOIN tyre_stock t ON t.id = tcd.tyre_id
     WHERE tcd.job_card_id = $1
     ORDER BY tcd.created_at ASC`,
    [job_card_id]
  );
  return result.rows;
};

module.exports = {
  createServiceDetail,
  getServiceDetailByJobId,
  createTyreChange,
  getTyreChangeByJobId,
};