const invoiceModel   = require('../models/invoiceModel');
const whatsappService = require('../services/whatsappService');

// POST /api/invoices
const createInvoice = async (req, res, next) => {
  try {
    const job_card_id    = req.body.job_card_id;
    const labour_charge  = req.body.labour_charge  || 0;
    const parts_charge   = req.body.parts_charge   || 0;
    const gst_percent    = req.body.gst_percent    || 18;
    const discount       = req.body.discount       || 0;
    const payment_method = req.body.payment_method;

    if (!job_card_id) {
      return res.status(400).json({
        success: false,
        message: 'job_card_id is required',
      });
    }

    const validPaymentMethods = ['cash', 'upi', 'card', 'net_banking'];
    if (payment_method && !validPaymentMethods.includes(payment_method)) {
      return res.status(400).json({
        success: false,
        message: `payment_method must be one of: ${validPaymentMethods.join(', ')}`,
      });
    }

    // If invoice already exists for this job, return it instead of creating a duplicate
    const existing = await invoiceModel.getInvoiceByJobId(job_card_id);
    if (existing) {
      return res.status(200).json({
        success: true,
        message: 'Invoice already exists for this job',
        data: existing,
      });
    }

    const invoice = await invoiceModel.createInvoice(
      job_card_id,
      labour_charge,
      parts_charge,
      gst_percent,
      discount,
      payment_method || null
    );

    // Get full invoice with customer details for WhatsApp
    const fullInvoice = await invoiceModel.getInvoiceById(invoice.id);

    res.status(201).json({
      success: true,
      message: 'Invoice created',
      data: fullInvoice,
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/invoices/:id/send — sends the bill breakdown to the customer via WhatsApp
const sendInvoiceWhatsApp = async (req, res, next) => {
  try {
    const invoice = await invoiceModel.getInvoiceById(req.params.id);

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found' });
    }

    await whatsappService.sendInvoiceMessage(
      invoice.customer_phone,
      invoice.customer_name,
      invoice.vehicle_number,
      invoice.service_type,
      {
        labour:        invoice.labour_charge,
        parts:         invoice.parts_charge,
        gst:           invoice.gst_amount,
        discount:      invoice.discount,
        total:         invoice.total_amount,
        paymentStatus: invoice.payment_status,
      }
    );

    res.status(200).json({ success: true, message: 'Invoice sent via WhatsApp' });

  } catch (err) {
    next(err);
  }
};

// GET /api/invoices
const getAllInvoices = async (req, res, next) => {
  try {
    const invoices = await invoiceModel.getAllInvoices();

    res.status(200).json({
      success: true,
      count: invoices.length,
      data: invoices,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/invoices/:id
const getInvoiceById = async (req, res, next) => {
  try {
    const invoice = await invoiceModel.getInvoiceById(req.params.id);

    if (!invoice) {
      return res.status(404).json({
        success: false,
        message: 'Invoice not found',
      });
    }

    res.status(200).json({
      success: true,
      data: invoice,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/invoices/job/:job_card_id
const getInvoiceByJob = async (req, res, next) => {
  try {
    const invoice = await invoiceModel.getInvoiceByJobId(req.params.job_card_id);

    if (!invoice) {
      return res.status(404).json({
        success: false,
        message: 'No invoice found for this job',
      });
    }

    res.status(200).json({
      success: true,
      data: invoice,
    });

  } catch (err) {
    next(err);
  }
};

// PUT /api/invoices/:id  — update charges on an existing unpaid invoice
const updateInvoice = async (req, res, next) => {
  try {
    const labour_charge = req.body.labour_charge ?? 0;
    const parts_charge  = req.body.parts_charge  ?? 0;
    const gst_percent   = req.body.gst_percent   ?? 18;
    const discount      = req.body.discount      ?? 0;

    const invoice = await invoiceModel.updateInvoice(
      req.params.id, labour_charge, parts_charge, gst_percent, discount
    );

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found' });
    }

    const fullInvoice = await invoiceModel.getInvoiceById(invoice.id);

    res.status(200).json({ success: true, message: 'Invoice updated', data: fullInvoice });
  } catch (err) {
    next(err);
  }
};

// PATCH /api/invoices/:id/pay
const markAsPaid = async (req, res, next) => {
  try {
    const payment_method = req.body.payment_method;

    if (!payment_method) {
      return res.status(400).json({
        success: false,
        message: 'payment_method is required',
      });
    }

    const invoice = await invoiceModel.markAsPaid(req.params.id, payment_method);

    if (!invoice) {
      return res.status(404).json({
        success: false,
        message: 'Invoice not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Invoice marked as paid',
      data: invoice,
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  createInvoice,
  updateInvoice,
  getAllInvoices,
  getInvoiceById,
  getInvoiceByJob,
  markAsPaid,
  sendInvoiceWhatsApp,
};