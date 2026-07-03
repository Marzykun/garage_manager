const pool = require('../config/db');
const jwt  = require('jsonwebtoken');

// Mechanic login — shared garage password
const login = async (req, res, next) => {
  try {
    const { password } = req.body;

    if (!password) {
      return res.status(400).json({
        success: false,
        message: 'Password is required',
      });
    }

    const result = await pool.query(
      'SELECT * FROM garage_settings LIMIT 1'
    );

    if (result.rows.length === 0) {
      return res.status(500).json({
        success: false,
        message: 'Garage not configured',
      });
    }

    if (password !== result.rows[0].password) {
      return res.status(401).json({
        success: false,
        message: 'Incorrect password',
      });
    }

    const token = jwt.sign(
      { role: 'mechanic' },
      process.env.JWT_SECRET,
      { expiresIn: '12h' }
    );

    res.status(200).json({
      success: true,
      message: 'Login successful',
      role: 'mechanic',
      token,
    });

  } catch (err) {
    next(err);
  }
};

// Owner login — username + password
const ownerLogin = async (req, res, next) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({
        success: false,
        message: 'Username and password are required',
      });
    }

    const result = await pool.query(
      'SELECT * FROM owner_credentials WHERE username = $1',
      [username]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({
        success: false,
        message: 'Invalid credentials',
      });
    }

    if (password !== result.rows[0].password) {
      return res.status(401).json({
        success: false,
        message: 'Invalid credentials',
      });
    }

    const token = jwt.sign(
      { role: 'owner', username },
      process.env.JWT_SECRET,
      { expiresIn: '12h' }
    );

    res.status(200).json({
      success: true,
      message: 'Owner login successful',
      role: 'owner',
      token,
    });

  } catch (err) {
    next(err);
  }
};

module.exports = { login, ownerLogin };