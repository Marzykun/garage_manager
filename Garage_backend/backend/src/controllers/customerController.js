const customerModel = require('../models/customerModel');
const lookupCustomer = async (req, res) => {
  try {
    const { phone } = req.params;

    // Check if customer exists
    const customer = await customerModel.getCustomerWithVehicles(phone);

    if (customer) {
      // Returning customer found!
      res.json({
        success: true,
        isReturning: true,
        message: 'Returning customer found',
        data: customer
      });
    } else {
      // New customer
      res.json({
        success: true,
        isReturning: false,
        message: 'New customer',
        data: null
      });
    }
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message
    });
  }
};

// GET /api/customers/search?q=
const searchCustomers = async (req, res, next) => {
  try {
    const { q } = req.query;

    if (!q || q.trim().length < 1) {
      return res.status(400).json({
        success: false,
        message: 'Search query must be at least 1 character',
      });
    }

    const customers = await customerModel.searchCustomers(q.trim());

    res.status(200).json({
      success: true,
      count: customers.length,
      data: customers,
    });

  } catch (err) {
    next(err);
  }
};

// Create new customer
const createCustomer = async (req, res) => {
  try {
    const { name, phone, language_pref } = req.body;

    // Check if phone already exists
    const existing = await customerModel.getCustomerByPhone(phone);
    if (existing) {
      return res.status(400).json({
        success: false,
        message: 'Customer with this phone already exists'
      });
    }

    const customer = await customerModel.createCustomer(
      name,
      phone,
      language_pref || 'EN'
    );

    res.status(201).json({
      success: true,
      message: 'Customer created successfully',
      data: customer
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message
    });
  }
};

module.exports = {
  lookupCustomer,
  createCustomer,
  searchCustomers,
};