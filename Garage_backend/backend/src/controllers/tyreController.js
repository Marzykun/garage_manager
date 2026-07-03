const tyreModel = require('../models/tyreModel');

// POST /api/tyres
const addTyre = async (req, res, next) => {
  try {
    const { brand, model, size, vehicle_type, quantity, price, offer } = req.body;

    if (!brand || !size) {
      return res.status(400).json({ success: false, message: 'brand and size are required' });
    }

    const tyre = await tyreModel.addTyre(
      brand, model || null, size, vehicle_type || null,
      quantity || 0, price || null, offer || null
    );

    res.status(201).json({ success: true, message: 'Tyre added to stock', data: tyre });
  } catch (err) { next(err); }
};

// GET /api/tyres
const getAllTyres = async (req, res, next) => {
  try {
    const tyres = await tyreModel.getAllTyres(req.query.brand, req.query.size);
    res.status(200).json({ success: true, count: tyres.length, data: tyres });
  } catch (err) { next(err); }
};

// GET /api/tyres/:id
const getTyreById = async (req, res, next) => {
  try {
    const tyre = await tyreModel.getTyreById(req.params.id);
    if (!tyre) return res.status(404).json({ success: false, message: 'Tyre not found' });
    res.status(200).json({ success: true, data: tyre });
  } catch (err) { next(err); }
};

// PUT /api/tyres/:id
const updateTyre = async (req, res, next) => {
  try {
    const { brand, model, size, vehicle_type, quantity, price, offer } = req.body;

    if (!brand || !size) {
      return res.status(400).json({ success: false, message: 'brand and size are required' });
    }

    const tyre = await tyreModel.updateTyre(
      req.params.id, brand, model || null, size, vehicle_type || null,
      quantity || 0, price || null, offer || null
    );

    if (!tyre) return res.status(404).json({ success: false, message: 'Tyre not found' });
    res.status(200).json({ success: true, message: 'Tyre updated', data: tyre });
  } catch (err) { next(err); }
};

// PATCH /api/tyres/:id/fit
const fitTyre = async (req, res, next) => {
  try {
    const { quantity_used } = req.body;
    if (!quantity_used || quantity_used < 1) {
      return res.status(400).json({ success: false, message: 'quantity_used must be at least 1' });
    }
    const tyre = await tyreModel.reduceStock(req.params.id, quantity_used);
    if (!tyre) return res.status(400).json({ success: false, message: 'Not enough stock or tyre not found' });
    res.status(200).json({ success: true, message: `Stock reduced by ${quantity_used}. Remaining: ${tyre.quantity}`, data: tyre });
  } catch (err) { next(err); }
};

// DELETE /api/tyres/:id
const deleteTyre = async (req, res, next) => {
  try {
    const tyre = await tyreModel.deleteTyre(req.params.id);
    if (!tyre) return res.status(404).json({ success: false, message: 'Tyre not found' });
    res.status(200).json({ success: true, message: 'Tyre removed from stock' });
  } catch (err) {
    // FK violation — tyre is referenced in job records or sales
    if (err.code === '23503') {
      return res.status(409).json({
        success: false,
        message: 'Cannot delete — this tyre has been used in job records. Set quantity to 0 instead.',
      });
    }
    next(err);
  }
};

module.exports = { addTyre, getAllTyres, getTyreById, updateTyre, fitTyre, deleteTyre };
