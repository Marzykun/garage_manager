const reportModel = require('../models/reportModel');

// Get today's date string in IST (YYYY-MM-DD)
const todayIST = () => {
  const ist = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
  return `${ist.getFullYear()}-${String(ist.getMonth()+1).padStart(2,'0')}-${String(ist.getDate()).padStart(2,'0')}`;
};

// Helper to get date range in IST
const getDateRange = (range) => {
  const today = todayIST();

  if (range === 'today') {
    return { from_date: today, to_date: today };
  } else if (range === 'week') {
    const ist = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
    ist.setDate(ist.getDate() - 7);
    const weekAgo = `${ist.getFullYear()}-${String(ist.getMonth()+1).padStart(2,'0')}-${String(ist.getDate()).padStart(2,'0')}`;
    return { from_date: weekAgo, to_date: today };
  } else if (range === 'month') {
    const ist = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
    ist.setDate(ist.getDate() - 30);
    const monthAgo = `${ist.getFullYear()}-${String(ist.getMonth()+1).padStart(2,'0')}-${String(ist.getDate()).padStart(2,'0')}`;
    return { from_date: monthAgo, to_date: today };
  }
  return null;
};

// GET /api/reports/daily?range=today|week|month
const getDailyReport = async (req, res, next) => {
  try {
    const range = req.query.range || 'today';
    const dates = getDateRange(range);

    if (!dates) {
      return res.status(400).json({
        success: false,
        message: 'range must be today, week or month',
      });
    }

    const jobs     = await reportModel.getDailyReport(dates.to_date);
    const revenue  = await reportModel.getRevenueReport(dates.from_date, dates.to_date);
    const services = await reportModel.getServiceBreakdown(dates.from_date, dates.to_date);

    res.status(200).json({
      success: true,
      range,
      from_date: dates.from_date,
      to_date: dates.to_date,
      data: { jobs, revenue, services },
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/reports/service-analysis?range=today|week|month
const getServiceAnalysis = async (req, res, next) => {
  try {
    const range = req.query.range || 'month';
    const dates = getDateRange(range);

    if (!dates) {
      return res.status(400).json({
        success: false,
        message: 'range must be today, week or month',
      });
    }

    const services = await reportModel.getServiceAnalysis(dates.from_date, dates.to_date);

    res.status(200).json({
      success: true,
      range,
      from_date: dates.from_date,
      to_date: dates.to_date,
      data: services,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/reports/sales?range=today|week|month
const getSalesAnalysis = async (req, res, next) => {
  try {
    const range = req.query.range || 'month';
    const dates = getDateRange(range);

    if (!dates) {
      return res.status(400).json({
        success: false,
        message: 'range must be today, week or month',
      });
    }

    const sales = await reportModel.getSalesAnalysis(dates.from_date, dates.to_date);

    res.status(200).json({
      success: true,
      range,
      from_date: dates.from_date,
      to_date: dates.to_date,
      data: sales,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/reports/customers
const getCustomerReport = async (req, res, next) => {
  try {
    const report = await reportModel.getCustomerReport();

    res.status(200).json({
      success: true,
      data: report,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/reports/summary
const getAdminSummary = async (req, res, next) => {
  try {
    const summary = await reportModel.getAdminSummary();

    res.status(200).json({
      success: true,
      data: summary,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/reports/unpaid
const getUnpaidInvoices = async (req, res, next) => {
  try {
    const invoices = await reportModel.getUnpaidInvoices();

    res.status(200).json({
      success: true,
      count: invoices.length,
      data: invoices,
    });

  } catch (err) {
    next(err);
  }
};

// GET /api/reports/revenue-trend
const getRevenueTrend = async (req, res, next) => {
  try {
    const trend = await reportModel.getRevenueTrend();

    res.status(200).json({
      success: true,
      data: trend,
    });

  } catch (err) {
    next(err);
  }
};

module.exports = {
  getDailyReport,
  getServiceAnalysis,
  getSalesAnalysis,
  getCustomerReport,
  getAdminSummary,
  getUnpaidInvoices,
  getRevenueTrend,
};