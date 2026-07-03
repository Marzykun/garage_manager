const serviceDetailModel = require('../models/serviceDetailModel');

// POST /api/service-details
const createServiceDetail = async (req, res, next) => {
  try {
    const job_card_id = req.body.job_card_id;
    const service_type = req.body.service_type;
    const remarks     = req.body.remarks;
    const parts_used  = req.body.parts_used;

    if (!job_card_id || !service_type) {
      return res.status(400).json({
        success: false,
        message: 'job_card_id and service_type are required',
      });
    }

    const validTypes = ['car_wash', 'water_wash', 'full_service', 'other'];
    if (!validTypes.includes(service_type)) {
      return res.status(400).json({
        success: false,
        message: `service_type must be one of: ${validTypes.join(', ')}`,
      });
    }

    const detail = await serviceDetailModel.createServiceDetail(
      job_card_id,
      service_type,
      remarks   || null,
      parts_used || null
    );

    res.status(201).json({
      success: true,
      message: 'Service details saved',
      data: detail,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/service-details/job/:job_card_id
const getServiceDetailByJob = async (req, res, next) => {
  try {
    const details = await serviceDetailModel.getServiceDetailByJobId(req.params.job_card_id);

    res.status(200).json({
      success: true,
      count: details.length,
      data: details,
    });

  } catch (err) {
    next(err);
  }
};

// POST /api/service-details/tyre-change
const createTyreChange = async (req, res, next) => {
  try {
    const job_card_id = req.body.job_card_id;
    const tyre_id     = req.body.tyre_id;
    const quantity    = req.body.quantity;
    const remarks     = req.body.remarks;

    if (!job_card_id || !tyre_id || !quantity) {
      return res.status(400).json({
        success: false,
        message: 'job_card_id, tyre_id and quantity are required',
      });
    }

    const detail = await serviceDetailModel.createTyreChange(
      job_card_id,
      tyre_id,
      quantity,
      remarks || null
    );

    res.status(201).json({
      success: true,
      message: 'Tyre change recorded and stock updated',
      data: detail,
    });

  } catch (err) {
    if (err.message.includes('available in stock') || err.message === 'Tyre not found') {
      return res.status(400).json({
        success: false,
        message: err.message,
      });
    }
    next(err);
  }
};

// GET /api/service-details/tyre-change/job/:job_card_id
const getTyreChangeByJob = async (req, res, next) => {
  try {
    const details = await serviceDetailModel.getTyreChangeByJobId(req.params.job_card_id);

    res.status(200).json({
      success: true,
      count: details.length,
      data: details,
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  createServiceDetail,
  getServiceDetailByJob,
  createTyreChange,
  getTyreChangeByJob,
};