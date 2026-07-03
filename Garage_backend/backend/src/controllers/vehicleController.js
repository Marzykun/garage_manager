const vehicleModel = require('../models/vehicleModel');

// POST /api/vehicles
const addVehicle = async (req, res, next) => {
  try {
    const {
      customer_id,
      vehicle_number,
      vehicle_type,
      brand,
      model,
      year,
      km_run,
      tyre_size,
    } = req.body;

    if (!customer_id || !vehicle_number) {
      return res.status(400).json({
        success: false,
        message: 'customer_id and vehicle_number are required',
      });
    }

    const existing = await vehicleModel.getVehicleByNumber(vehicle_number);
    if (existing) {
      return res.status(409).json({
        success: false,
        message: 'Vehicle already registered',
      });
    }

    const vehicle = await vehicleModel.addVehicle(
      customer_id,
      vehicle_number,
      vehicle_type || null,
      brand || null,
      model || null,
      year || null,
      km_run || 0,
      tyre_size || null
    );

    res.status(201).json({
      success: true,
      message: 'Vehicle added successfully',
      data: vehicle,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/vehicles/customer/:customer_id
const getVehiclesByCustomer = async (req, res, next) => {
  try {
    const { customer_id } = req.params;
    const vehicles = await vehicleModel.getVehiclesByCustomer(customer_id);

    res.status(200).json({
      success: true,
      count: vehicles.length,
      data: vehicles,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/vehicles/number/:plate
// GET /api/vehicles/number/:plate
const getVehicleByNumber = async (req, res, next) => {
  try {
    const vehicle = await vehicleModel.getVehicleByNumber(req.params.plate);

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found',
      });
    }

    res.status(200).json({
      success: true,
      data: vehicle,
    });

  } catch (err) {
    next(err);
  }
};
// PATCH /api/vehicles/:id/km
const updateVehicleKm = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { km_run } = req.body;

    if (!km_run) {
      return res.status(400).json({
        success: false,
        message: 'km_run is required',
      });
    }

    const vehicle = await vehicleModel.updateVehicleKm(id, km_run);

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Kilometer updated',
      data: vehicle,
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  addVehicle,
  getVehiclesByCustomer,
  updateVehicleKm,
  getVehicleByNumber,
};