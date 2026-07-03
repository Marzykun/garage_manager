const pool = require('../config/db');

// Store payment order
const createPaymentOrder = async (invoice_id, razorpay_order_id, amount) => {
  const result = await pool.query(
    `INSERT INTO payment_orders
      (invoice_id, razorpay_order_id, amount, status)
     VALUES ($1, $2, $3, 'created')
     RETURNING *`,
    [invoice_id, razorpay_order_id, amount]
  );
  return result.rows[0];
};

// Get payment order by invoice id
const getPaymentOrderByInvoiceId = async (invoice_id) => {
  const result = await pool.query(
    `SELECT * FROM payment_orders
     WHERE invoice_id = $1
     ORDER BY created_at DESC
     LIMIT 1`,
    [invoice_id]
  );
  return result.rows[0];
};

// Update payment order status after webhook
const updatePaymentStatus = async (razorpay_order_id, razorpay_payment_id, status) => {
  const result = await pool.query(
    `UPDATE payment_orders
     SET status             = $1,
         razorpay_payment_id = $2,
         paid_at            = now()
     WHERE razorpay_order_id = $3
     RETURNING *`,
    [status, razorpay_payment_id, razorpay_order_id]
  );
  return result.rows[0];
};

module.exports = {
  createPaymentOrder,
  getPaymentOrderByInvoiceId,
  updatePaymentStatus,
};