const jobModel = require('../models/jobModel');
const whatsappService = require('../services/whatsappService');

// Odometer value from the request: null if absent/blank, false if invalid.
const parseKm = (v) => {
  if (v === undefined || v === null || String(v).trim() === '') return null;
  const n = Number(String(v).replace(/[,\s]/g, ''));
  return Number.isInteger(n) && n >= 0 && n < 10000000 ? n : false;
};

// POST /api/jobs
const createJob = async (req, res, next) => {
  try {
    const {
      customer_id,
      vehicle_id,
      service_type,
      service_date,
      service_time,
      notes,
      source,
    } = req.body;
    const km_reading = parseKm(req.body.km_reading);
    if (km_reading === false) {
      return res.status(400).json({ success: false, message: 'km_reading must be a whole number of kilometres' });
    }

    if (!customer_id || !vehicle_id || !service_type) {
      return res.status(400).json({
        success: false,
        message: 'customer_id, vehicle_id and service_type are required',
      });
    }

    const job = await jobModel.createJob(
      customer_id,
      vehicle_id,
      service_type,
      service_date || null,
      service_time || null,
      notes || null,
      source || 'walkin',
      km_reading
    );

    res.status(201).json({
      success: true,
      message: 'Job card created',
      data: job,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/jobs?date=YYYY-MM-DD   (defaults to today in IST if omitted)
const getAllJobs = async (req, res, next) => {
  try {
    const { status, service_type, date } = req.query;

    // Default to today in IST when no date supplied
    const ist = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
    const todayIST = `${ist.getFullYear()}-${String(ist.getMonth()+1).padStart(2,'0')}-${String(ist.getDate()).padStart(2,'0')}`;
    const filterDate = date || todayIST;

    let jobs = await jobModel.getAllJobs(filterDate);

    if (status) {
      jobs = jobs.filter(job => job.status === status);
    }

    if (service_type) {
      jobs = jobs.filter(job => job.service_type === service_type);
    }

    res.status(200).json({
      success: true,
      count: jobs.length,
      data: jobs,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/jobs/:id
const getJobById = async (req, res, next) => {
  try {
    const job = await jobModel.getJobById(req.params.id);

    if (!job) {
      return res.status(404).json({
        success: false,
        message: 'Job not found',
      });
    }

    res.status(200).json({
      success: true,
      data: job,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/customers/:id/jobs
const getJobsByCustomer = async (req, res, next) => {
  try {
    const jobs = await jobModel.getJobsByCustomerId(req.params.id);

    res.status(200).json({
      success: true,
      count: jobs.length,
      data: jobs,
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/jobs/:id/start
const startJob = async (req, res, next) => {
  try {
    const job = await jobModel.startJob(req.params.id);

    if (!job) {
      return res.status(400).json({
        success: false,
        message: 'Job cannot be started — it may not exist or is not pending',
      });
    }

    const fullJob = await jobModel.getJobById(job.id);
    await whatsappService.sendJobStarted(
      fullJob.customer_phone,
      fullJob.vehicle_number,
      fullJob.service_type
    );

    res.status(200).json({
      success: true,
      message: 'Job moved to In Progress',
      data: job,
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/jobs/:id/complete
const completeJob = async (req, res, next) => {
  try {
    if (!(await jobModel.hasInvoice(req.params.id))) {
      return res.status(409).json({
        success: false,
        message: 'Invoice not generated. Generate the invoice before completing the job.',
      });
    }
    const job = await jobModel.completeJob(req.params.id);

    if (!job) {
      return res.status(400).json({
        success: false,
        message: 'Job cannot be completed — it may not exist or is not In Progress',
      });
    }

    const fullJob = await jobModel.getJobById(job.id);
    await whatsappService.sendCompletionMessage(
      fullJob.customer_phone,
      fullJob.customer_name,
      fullJob.vehicle_number,
      fullJob.service_type
    );

    res.status(200).json({
      success: true,
      message: 'Job completed and customer notified via WhatsApp',
      data: job,
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/jobs/:id/cancel
const cancelJob = async (req, res, next) => {
  try {
    const job = await jobModel.cancelJob(req.params.id);

    if (!job) {
      return res.status(404).json({
        success: false,
        message: 'Job not found',
      });
    }

    const fullJob = await jobModel.getJobById(job.id);
    await whatsappService.sendJobCancelled(
      fullJob.customer_phone,
      fullJob.vehicle_number,
      fullJob.service_type
    );

    res.status(200).json({
      success: true,
      message: 'Job cancelled',
      data: job,
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/jobs/:id/ready
const markReadyForDelivery = async (req, res, next) => {
  try {
    const job = await jobModel.markReadyForDelivery(req.params.id);

    if (!job) {
      return res.status(404).json({
        success: false,
        message: 'Job not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Job marked as ready for delivery',
      data: job,
    });

  } catch (err) {
    next(err);
  }
};

// PUT /api/jobs/:id/details — fix customer / vehicle / service details
const SERVICE_TYPES = [
  'wheel_alignment', 'wheel_balancing', 'tyre_change',
  'water_wash', 'full_service', 'car_wash', 'other',
];

const updateJobDetails = async (req, res, next) => {
  try {
    const text = (v) => (typeof v === 'string' && v.trim() ? v.trim() : null);
    const d = {
      customer_name:  text(req.body.customer_name),
      customer_phone: text(req.body.customer_phone),
      vehicle_number: text(req.body.vehicle_number)?.toUpperCase().replace(/[^A-Z0-9]/g, '') || null,
      vehicle_type:   text(req.body.vehicle_type)?.toLowerCase() ?? null,
      brand:          text(req.body.brand),
      model:          text(req.body.model),
      service_type:   text(req.body.service_type),
      // notes may be cleared on purpose, so an empty string is kept
      notes:          typeof req.body.notes === 'string' ? req.body.notes.trim() : undefined,
      // km may be cleared on purpose (empty string → null)
      km_reading:     req.body.km_reading === undefined ? undefined : parseKm(req.body.km_reading),
    };

    if (d.km_reading === false) {
      return res.status(400).json({ success: false, message: 'km_reading must be a whole number of kilometres' });
    }

    if (d.service_type && !SERVICE_TYPES.includes(d.service_type)) {
      return res.status(400).json({
        success: false,
        message: `service_type must be one of: ${SERVICE_TYPES.join(', ')}`,
      });
    }

    const job = await jobModel.updateJobDetails(req.params.id, d);
    res.status(200).json({ success: true, message: 'Job updated', data: job });
  } catch (err) {
    next(err);
  }
};

module.exports = {
  SERVICE_TYPES,
  updateJobDetails,
  createJob,
  getAllJobs,
  getJobById,
  getJobsByCustomer,
  startJob,
  completeJob,
  cancelJob,
  markReadyForDelivery,
};