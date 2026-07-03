const pool = require('../config/db');

const createInvoice = async (job_card_id, labour_charge, parts_charge, gst_percent, discount, payment_method) => {
  const subtotal   = parseFloat(labour_charge) + parseFloat(parts_charge);
  const gst_amount = (subtotal * parseFloat(gst_percent)) / 100;
  const total_amount = subtotal + gst_amount - parseFloat(discount);

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
  const subtotal    = parseFloat(labour_charge) + parseFloat(parts_charge);
  const gst_amount  = (subtotal * parseFloat(gst_percent)) / 100;
  const total_amount = subtotal + gst_amount - parseFloat(discount);

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
  createInvoice,
  updateInvoice,
  getInvoiceByJobId,
  getInvoiceById,
  markAsPaid,
  getAllInvoices,
};