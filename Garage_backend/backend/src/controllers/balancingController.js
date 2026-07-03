const balancingModel = require('../models/balancingModel');

// POST /api/balancing
const createBalancing = async (req, res, next) => {
  try {
    const job_card_id = req.body.job_card_id;
    const fl_weight   = req.body.fl_weight;
    const fr_weight   = req.body.fr_weight;
    const rl_weight   = req.body.rl_weight;
    const rr_weight   = req.body.rr_weight;
    const remarks     = req.body.remarks;
    const round_type  = req.body.round_type;

    if (!job_card_id) {
      return res.status(400).json({
        success: false,
        message: 'job_card_id is required',
      });
    }

    const validRoundTypes = ['before', 'after'];
    if (round_type && !validRoundTypes.includes(round_type)) {
      return res.status(400).json({
        success: false,
        message: 'round_type must be either "before" or "after"',
      });
    }

    const record = await balancingModel.createBalancing(
      job_card_id,
      fl_weight   || null,
      fr_weight   || null,
      rl_weight   || null,
      rr_weight   || null,
      remarks     || null,
      round_type  || 'before'
    );

    res.status(201).json({
      success: true,
      message: 'Wheel balancing record saved',
      data: record,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/balancing/job/:job_card_id
const getBalancingByJob = async (req, res, next) => {
  try {
    const records = await balancingModel.getBalancingByJobId(req.params.job_card_id);

    res.status(200).json({
      success: true,
      count: records.length,
      data: records,
    });

  } catch (err) {
    next(err);
  }
};

// DELETE /api/balancing/:id
const deleteBalancing = async (req, res, next) => {
  try {
    const record = await balancingModel.deleteBalancing(req.params.id);

    if (!record) {
      return res.status(404).json({
        success: false,
        message: 'Record not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Balancing record deleted',
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  createBalancing,
  getBalancingByJob,
  deleteBalancing,
};