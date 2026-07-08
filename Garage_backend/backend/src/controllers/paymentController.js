const Razorpay = require('razorpay');
const crypto   = require('crypto');
const pool     = require('../config/db');
const paymentModel   = require('../models/paymentModel');
const whatsappService = require('../services/whatsappService');

// Payments are optional (on hold for the local-only delivery). The backend
// runs without Razorpay keys — payment routes just return 503.
const razorpay = (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET)
  ? new Razorpay({
      key_id:     process.env.RAZORPAY_KEY_ID,
      key_secret: process.env.RAZORPAY_KEY_SECRET,
    })
  : null;

// POST /api/payments/create-order
// Mechanic triggers this to send payment request to customer
const createOrder = async (req, res, next) => {
  try {
    if (!razorpay) {
      return res.status(503).json({
        success: false,
        message: 'Online payments are not enabled on this server',
      });
    }

    const invoice_id = req.body.invoice_id;

    if (!invoice_id) {
      return res.status(400).json({
        success: false,
        message: 'invoice_id is required',
      });
    }

    // Get invoice details
    const invoiceResult = await pool.query(
      `SELECT 
        i.*,
        c.name  AS customer_name,
        c.phone AS customer_phone,
        v.vehicle_number
       FROM invoices i
       JOIN job_cards j ON j.id = i.job_card_id
       JOIN customers c ON c.id = j.customer_id
       JOIN vehicles  v ON v.id = j.vehicle_id
       WHERE i.id = $1`,
      [invoice_id]
    );

    if (invoiceResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Invoice not found',
      });
    }

    const invoice = invoiceResult.rows[0];

    if (invoice.payment_status === 'paid') {
      return res.status(400).json({
        success: false,
        message: 'Invoice already paid',
      });
    }

    // Create Razorpay order
    // Amount must be in paise (multiply by 100)
    const order = await razorpay.orders.create({
      amount:   Math.round(invoice.total_amount * 100),
      currency: 'INR',
      receipt: `inv_${invoice_id.slice(0, 30)}`,
      notes: {
        customer_name:  invoice.customer_name,
        vehicle_number: invoice.vehicle_number,
        invoice_id:     invoice_id,
      },
    });

    // Save order to DB
    await paymentModel.createPaymentOrder(
      invoice_id,
      order.id,
      invoice.total_amount
    );

    // Send WhatsApp payment link to customer
    const paymentLink = `https://rzp.io/${order.id}`;
    await whatsappService.sendPaymentLink(
      invoice.customer_phone,
      invoice.customer_name,
      invoice.vehicle_number,
      invoice.total_amount,
      paymentLink
    );

    res.status(201).json({
      success: true,
      message: 'Payment order created and link sent to customer via WhatsApp',
      data: {
        order_id:       order.id,
        amount:         invoice.total_amount,
        currency:       'INR',
        customer_name:  invoice.customer_name,
        customer_phone: invoice.customer_phone,
      },
    });

 } catch (err) {
  console.error('Payment error details:', err);
  next(err);
}
};

// POST /api/payments/verify
// Razorpay calls this webhook after payment is done
const verifyPayment = async (req, res, next) => {
  try {
    if (!razorpay) {
      return res.status(503).json({
        success: false,
        message: 'Online payments are not enabled on this server',
      });
    }

    const {
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
    } = req.body;

    // Verify signature to confirm payment is genuine
    const body      = razorpay_order_id + '|' + razorpay_payment_id;
    const expected  = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(body)
      .digest('hex');

    if (expected !== razorpay_signature) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment signature',
      });
    }

    // Update payment order status
    const paymentOrder = await paymentModel.updatePaymentStatus(
      razorpay_order_id,
      razorpay_payment_id,
      'paid'
    );

    // Mark invoice as paid
    await pool.query(
      `UPDATE invoices
       SET payment_status = 'paid',
           payment_method = 'upi'
       WHERE id = $1`,
      [paymentOrder.invoice_id]
    );

    // Get customer details for WhatsApp receipt
    const invoiceResult = await pool.query(
      `SELECT
        i.total_amount,
        c.name  AS customer_name,
        c.phone AS customer_phone,
        v.vehicle_number,
        j.service_type
       FROM invoices i
       JOIN job_cards j ON j.id = i.job_card_id
       JOIN customers c ON c.id = j.customer_id
       JOIN vehicles  v ON v.id = j.vehicle_id
       WHERE i.id = $1`,
      [paymentOrder.invoice_id]
    );

    const invoice = invoiceResult.rows[0];

    // Send WhatsApp receipt to customer
    await whatsappService.sendPaymentReceipt(
      invoice.customer_phone,
      invoice.customer_name,
      invoice.vehicle_number,
      invoice.total_amount,
      razorpay_payment_id
    );

    res.status(200).json({
      success: true,
      message: 'Payment verified and receipt sent to customer',
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/payments/status/:invoice_id
const getPaymentStatus = async (req, res, next) => {
  try {
    const order = await paymentModel.getPaymentOrderByInvoiceId(req.params.invoice_id);

    if (!order) {
      return res.status(404).json({
        success: false,
        message: 'No payment order found for this invoice',
      });
    }

    res.status(200).json({
      success: true,
      data: order,
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  createOrder,
  verifyPayment,
  getPaymentStatus,
};