const settingsModel = require('../models/settingsModel');

// GET /api/settings
const getSettings = async (req, res, next) => {
  try {
    const settings = await settingsModel.getGarageSettings();

    res.status(200).json({
      success: true,
      data: settings,
    });

  } catch (err) {
    next(err);
  }
};

// PUT /api/settings
const updateSettings = async (req, res, next) => {
  try {
    const garage_name  = req.body.garage_name;
    const open_time    = req.body.open_time;
    const close_time   = req.body.close_time;
    const working_days = req.body.working_days;
    const gst_percent  = req.body.gst_percent;

    if (!garage_name) {
      return res.status(400).json({
        success: false,
        message: 'garage_name is required',
      });
    }

    const settings = await settingsModel.updateGarageSettings(
      garage_name,
      open_time    || '09:00',
      close_time   || '20:00',
      working_days || 'Mon-Sat',
      gst_percent  || 18
    );

    res.status(200).json({
      success: true,
      message: 'Garage settings updated',
      data: settings,
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/settings/garage-password
const updateGaragePassword = async (req, res, next) => {
  try {
    const new_password     = req.body.new_password;
    const confirm_password = req.body.confirm_password;

    if (!new_password || !confirm_password) {
      return res.status(400).json({
        success: false,
        message: 'new_password and confirm_password are required',
      });
    }

    if (new_password !== confirm_password) {
      return res.status(400).json({
        success: false,
        message: 'Passwords do not match',
      });
    }

    if (new_password.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters',
      });
    }

    await settingsModel.updateGaragePassword(new_password);

    res.status(200).json({
      success: true,
      message: 'Garage password updated successfully',
    });

  } catch (err) {
    next(err);
  }
};

// PATCH /api/settings/owner-credentials
const updateOwnerCredentials = async (req, res, next) => {
  try {
    const username         = req.body.username;
    const new_password     = req.body.new_password;
    const confirm_password = req.body.confirm_password;

    if (!username || !new_password || !confirm_password) {
      return res.status(400).json({
        success: false,
        message: 'username, new_password and confirm_password are required',
      });
    }

    if (new_password !== confirm_password) {
      return res.status(400).json({
        success: false,
        message: 'Passwords do not match',
      });
    }

    if (new_password.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters',
      });
    }

    const result = await settingsModel.updateOwnerCredentials(username, new_password);

    res.status(200).json({
      success: true,
      message: 'Owner credentials updated successfully',
      data: { username: result.username },
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  getSettings,
  updateSettings,
  updateGaragePassword,
  updateOwnerCredentials,
};