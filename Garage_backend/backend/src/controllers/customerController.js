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

const SERVICE_TYPES = [
  'wheel_alignment', 'wheel_balancing', 'tyre_change',
  'water_wash', 'full_service', 'car_wash', 'other',
];

// GET /api/customers/search?q=&service=&vehicle_type=&limit=&offset=
// All filters optional — with none, lists every customer (latest visit first).
const searchCustomers = async (req, res, next) => {
  try {
    const q           = (req.query.q || '').trim();
    const service     = (req.query.service || '').trim();
    const vehicleType = (req.query.vehicle_type || '').trim();
    const limit       = Math.min(Math.max(parseInt(req.query.limit, 10) || 30, 1), 100);
    const offset      = Math.max(parseInt(req.query.offset, 10) || 0, 0);

    if (service && !SERVICE_TYPES.includes(service)) {
      return res.status(400).json({
        success: false,
        message: `service must be one of: ${SERVICE_TYPES.join(', ')}`,
      });
    }

    const customers = await customerModel.searchCustomers({ q, service, vehicleType, limit, offset });

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