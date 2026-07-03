const alignmentModel = require('../models/alignmentModel');

// POST /api/alignment
const createAlignment = async (req, res, next) => {
  try {
    const job_card_id      = req.body.job_card_id;
    const alignment_report = req.body.alignment_report;
    const remarks          = req.body.remarks;

    if (!job_card_id) {
      return res.status(400).json({
        success: false,
        message: 'job_card_id is required',
      });
    }

    const record = await alignmentModel.createAlignment(
      job_card_id,
      alignment_report || null,
      remarks          || null
    );

    res.status(201).json({
      success: true,
      message: 'Wheel alignment record saved',
      data: record,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/alignment/job/:job_card_id
const getAlignmentByJob = async (req, res, next) => {
  try {
    const records = await alignmentModel.getAlignmentByJobId(req.params.job_card_id);

    res.status(200).json({
      success: true,
      count: records.length,
      data: records,
    });

  } catch (err) {
    next(err);
  }
};

// DELETE /api/alignment/:id
const deleteAlignment = async (req, res, next) => {
  try {
    const record = await alignmentModel.deleteAlignment(req.params.id);

    if (!record) {
      return res.status(404).json({
        success: false,
        message: 'Record not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Alignment record deleted',
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  createAlignment,
  getAlignmentByJob,
  deleteAlignment,
};