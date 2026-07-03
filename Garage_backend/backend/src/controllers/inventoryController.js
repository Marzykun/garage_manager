const inventoryModel = require('../models/inventoryModel');

// POST /api/inventory
const addItem = async (req, res, next) => {
  try {
    const { name, category, quantity, unit, min_stock } = req.body;

    if (!name || !category) {
      return res.status(400).json({
        success: false,
        message: 'name and category are required',
      });
    }

    const validCategories = ['tyre', 'wheel_weight', 'foam', 'lubricant', 'other'];
    if (!validCategories.includes(category)) {
      return res.status(400).json({
        success: false,
        message: `category must be one of: ${validCategories.join(', ')}`,
      });
    }

    const item = await inventoryModel.addItem(
      name,
      category,
      quantity || 0,
      unit || 'pcs',
      min_stock || 5
    );

    res.status(201).json({
      success: true,
      message: 'Item added to inventory',
      data: item,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/inventory
const getAllItems = async (req, res, next) => {
  try {
    const { category } = req.query;
    const items = await inventoryModel.getAllItems(category);

    res.status(200).json({
      success: true,
      count: items.length,
      data: items,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/inventory/low-stock
const getLowStockItems = async (req, res, next) => {
  try {
    const items = await inventoryModel.getLowStockItems();

    res.status(200).json({
      success: true,
      count: items.length,
      message: items.length > 0 ? 'These items need restocking' : 'All items are sufficiently stocked',
      data: items,
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/inventory/:id/stock
const updateStock = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { quantity } = req.body;

    if (quantity === undefined || quantity < 0) {
      return res.status(400).json({
        success: false,
        message: 'Valid quantity is required',
      });
    }

    const item = await inventoryModel.updateStock(id, quantity);

    if (!item) {
      return res.status(404).json({
        success: false,
        message: 'Item not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Stock updated',
      data: item,
    });

  } catch (err) {
    next(err);
  }
};

// PUT /api/inventory/:id
const updateItem = async (req, res, next) => {
  try {
    const { name, category, quantity, unit, min_stock } = req.body;

    if (!name || !category) {
      return res.status(400).json({ success: false, message: 'name and category are required' });
    }

    const validCategories = ['tyre', 'wheel_weight', 'foam', 'lubricant', 'other'];
    if (!validCategories.includes(category)) {
      return res.status(400).json({ success: false, message: `category must be one of: ${validCategories.join(', ')}` });
    }

    const item = await inventoryModel.updateItem(req.params.id, name, category, quantity ?? 0, unit || 'pcs', min_stock ?? 5);

    if (!item) return res.status(404).json({ success: false, message: 'Item not found' });

    res.status(200).json({ success: true, message: 'Item updated', data: item });
  } catch (err) { next(err); }
};

// DELETE /api/inventory/:id
const deleteItem = async (req, res, next) => {
  try {
    const item = await inventoryModel.deleteItem(req.params.id);

    if (!item) {
      return res.status(404).json({
        success: false,
        message: 'Item not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Item deleted from inventory',
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  addItem,
  getAllItems,
  getLowStockItems,
  updateStock,
  updateItem,
  deleteItem,
};