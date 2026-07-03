const jobModel = require('../models/jobModel');
const whatsappService = require('../services/whatsappService');

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
      source || 'walkin'
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

module.exports = {
  createJob,
  getAllJobs,
  getJobById,
  getJobsByCustomer,
  startJob,
  completeJob,
  cancelJob,
  markReadyForDelivery,
};