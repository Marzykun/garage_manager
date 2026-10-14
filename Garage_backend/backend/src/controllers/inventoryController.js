const inventoryModel = require('../models/inventoryModel');

// empty => null (not provided); otherwise must be a number >= 0
const parsePrice = (v) => (v === undefined || v === null || v === '' ? null : Number(v));
const badPrice = (p) => p !== null && (!Number.isFinite(p) || p < 0);

// POST /api/inventory
const addItem = async (req, res, next) => {
  try {
    const { name, category, quantity, unit, min_stock } = req.body;
    const price = parsePrice(req.body.price);
    if (badPrice(price)) return res.status(400).json({ success: false, message: 'price must be a number >= 0' });

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
      Math.max(parseInt(quantity, 10) || 0, 0),
      unit || null,
      min_stock || null,
      price
    );

    res.status(item.merged ? 200 : 201).json({
      success: true,
      merged: item.merged,
      message: item.merged ? 'Added to existing item' : 'Item added to inventory',
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
    const price = parsePrice(req.body.price);
    if (badPrice(price)) return res.status(400).json({ success: false, message: 'price must be a number >= 0' });

    if (!name || !category) {
      return res.status(400).json({ success: false, message: 'name and category are required' });
    }

    const validCategories = ['tyre', 'wheel_weight', 'foam', 'lubricant', 'other'];
    if (!validCategories.includes(category)) {
      return res.status(400).json({ success: false, message: `category must be one of: ${validCategories.join(', ')}` });
    }

    const item = await inventoryModel.updateItem(req.params.id, name, category, quantity ?? 0, unit || 'pcs', min_stock ?? 5, price);

    if (!item) return res.status(404).json({ success: false, message: 'Item not found' });

    res.status(200).json({
      success: true,
      merged: item.merged,
      message: item.merged ? `Merged into existing ${item.name}` : 'Item updated',
      data: item,
    });
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

// GET /api/inventory/duplicates
const getDuplicates = async (req, res, next) => {
  try {
    const groups = await inventoryModel.getDuplicates();
    res.status(200).json({ success: true, count: groups.length, data: groups });
  } catch (err) { next(err); }
};

// POST /api/inventory/merge-duplicates (owner only, see route)
const mergeDuplicates = async (req, res, next) => {
  try {
    res.status(200).json({ success: true, ...(await inventoryModel.mergeDuplicates()) });
  } catch (err) { next(err); }
};

module.exports = {
  getDuplicates,
  mergeDuplicates,
  addItem,
  getAllItems,
  getLowStockItems,
  updateStock,
  updateItem,
  deleteItem,
};