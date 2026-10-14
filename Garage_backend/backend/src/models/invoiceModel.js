const pool = require('../config/db');

const jobHasTyres = async (job_card_id) => {
  const r = await pool.query(
    `SELECT 1 FROM tyre_change_details WHERE job_card_id = $1 LIMIT 1`, [job_card_id]);
  return r.rowCount > 0;
};

const r2 = (v) => Math.round((v + Number.EPSILON) * 100) / 100;

// Tyre bill: GST on parts only (labour untaxed). Service bill: GST on labour + parts.
const calcTotals = async (job_card_id, labour_charge, parts_charge, gst_percent, discount) => {
  const labour = parseFloat(labour_charge), parts = parseFloat(parts_charge);
  const base = (await jobHasTyres(job_card_id)) ? parts : labour + parts;
  const gst_amount = r2(base * parseFloat(gst_percent) / 100);
  return { gst_amount, total_amount: r2(labour + parts + gst_amount - parseFloat(discount)) };
};

const createInvoice = async (job_card_id, labour_charge, parts_charge, gst_percent, discount, payment_method) => {
  const { gst_amount, total_amount } = await calcTotals(job_card_id, labour_charge, parts_charge, gst_percent, discount);

  const result = await pool.query(
    `INSERT INTO invoices
      (job_card_id, labour_charge, parts_charge, gst_percent, gst_amount, discount, total_amount, payment_method, payment_status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
     RETURNING *`,
    [
      job_card_id,
      labour_charge,
      parts_charge,
      gst_percent,
      gst_amount.toFixed(2),
      discount,
      total_amount.toFixed(2),
      payment_method,
    ]
  );
  return result.rows[0];
};

const getInvoiceByJobId = async (job_card_id) => {
  const result = await pool.query(
    `SELECT 
      i.*,
      c.name        AS customer_name,
      c.phone       AS customer_phone,
      v.vehicle_number,
      v.brand,
      v.model,
      j.service_type
     FROM invoices i
     JOIN job_cards j ON j.id = i.job_card_id
     JOIN customers c ON c.id = j.customer_id
     JOIN vehicles  v ON v.id = j.vehicle_id
     WHERE i.job_card_id = $1`,
    [job_card_id]
  );
  return result.rows[0];
};

const getInvoiceById = async (id) => {
  const result = await pool.query(
    `SELECT 
      i.*,
      c.name        AS customer_name,
      c.phone       AS customer_phone,
      v.vehicle_number,
      v.brand,
      v.model,
      j.service_type
     FROM invoices i
     JOIN job_cards j ON j.id = i.job_card_id
     JOIN customers c ON c.id = j.customer_id
     JOIN vehicles  v ON v.id = j.vehicle_id
     WHERE i.id = $1`,
    [id]
  );
  return result.rows[0];
};

const updateInvoice = async (id, labour_charge, parts_charge, gst_percent, discount) => {
  const job = await pool.query(`SELECT job_card_id FROM invoices WHERE id = $1`, [id]);
  if (!job.rows[0]) return undefined;
  const { gst_amount, total_amount } = await calcTotals(job.rows[0].job_card_id, labour_charge, parts_charge, gst_percent, discount);

  const result = await pool.query(
    `UPDATE invoices
     SET labour_charge = $1,
         parts_charge  = $2,
         gst_percent   = $3,
         gst_amount    = $4,
         discount      = $5,
         total_amount  = $6
     WHERE id = $7
     RETURNING *`,
    [labour_charge, parts_charge, gst_percent, gst_amount.toFixed(2), discount, total_amount.toFixed(2), id]
  );
  return result.rows[0];
};

const markAsPaid = async (id, payment_method) => {
  const result = await pool.query(
    `UPDATE invoices
     SET payment_status = 'paid',
         payment_method = $1
     WHERE id = $2
     RETURNING *`,
    [payment_method, id]
  );
  return result.rows[0];
};

// Everything needed to render a printable invoice: the invoice with customer,
// vehicle and job details, the garage's own header details, and the itemised
// tyres/parts logged on the job.
const getInvoicePrintData = async (id) => {
  const invResult = await pool.query(
    `SELECT
      i.*,
      c.name           AS customer_name,
      c.phone          AS customer_phone,
      v.vehicle_number,
      v.brand,
      v.model,
      COALESCE(j.km_reading, v.km_run) AS km_run,
      j.service_type,
      j.notes          AS job_notes,
      j.created_at     AS job_created_at,
      j.completed_at   AS job_completed_at
     FROM invoices i
     JOIN job_cards j ON j.id = i.job_card_id
     JOIN customers c ON c.id = j.customer_id
     JOIN vehicles  v ON v.id = j.vehicle_id
     WHERE i.id = $1`,
    [id]
  );
  const invoice = invResult.rows[0];
  if (!invoice) return null;

  const [garageResult, tyreResult, partsResult, partLinesResult] = await Promise.all([
    pool.query(
      `SELECT garage_name, address, phone, gstin FROM garage_settings LIMIT 1`
    ),
    pool.query(
      `SELECT t.brand, t.model, t.pattern, t.size, t.price, tcd.quantity
       FROM tyre_change_details tcd
       JOIN tyre_stock t ON t.id = tcd.tyre_id
       WHERE tcd.job_card_id = $1
       ORDER BY tcd.created_at ASC`,
      [invoice.job_card_id]
    ),
    pool.query(
      `SELECT parts_used FROM service_details
       WHERE job_card_id = $1 AND parts_used IS NOT NULL AND parts_used <> ''
       ORDER BY created_at ASC`,
      [invoice.job_card_id]
    ),
    pool.query(
      `SELECT name, quantity, COALESCE(unit_price, 0) AS unit_price FROM job_parts_used
       WHERE job_card_id = $1 ORDER BY created_at ASC`,
      [invoice.job_card_id]
    ),
  ]);

  return {
    bill_type: tyreResult.rows.length > 0 ? 'tyre' : 'service',
    invoice,
    garage: garageResult.rows[0] || {},
    tyres: tyreResult.rows,
    parts_lines: partLinesResult.rows,
    parts_used: partsResult.rows.map((r) => r.parts_used),
  };
};

const getAllInvoices = async () => {
  const result = await pool.query(
    `SELECT 
      i.*,
      c.name        AS customer_name,
      c.phone       AS customer_phone,
      v.vehicle_number,
      j.service_type
     FROM invoices i
     JOIN job_cards j ON j.id = i.job_card_id
     JOIN customers c ON c.id = j.customer_id
     JOIN vehicles  v ON v.id = j.vehicle_id
     ORDER BY i.created_at DESC`
  );
  return result.rows;
};

module.exports = {
  jobHasTyres,
  createInvoice,
  updateInvoice,
  getInvoiceByJobId,
  getInvoiceById,
  getInvoicePrintData,
  markAsPaid,
  getAllInvoices,
};