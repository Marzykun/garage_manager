const express          = require('express');
const router           = express.Router();
const reportController = require('../controllers/reportController');

router.get('/daily',            reportController.getDailyReport);
router.get('/service-analysis', reportController.getServiceAnalysis);
router.get('/sales',            reportController.getSalesAnalysis);
router.get('/customers',        reportController.getCustomerReport);
router.get('/summary',          reportController.getAdminSummary);
router.get('/unpaid',           reportController.getUnpaidInvoices);
router.get('/new-customers',       reportController.getNewCustomers);
router.get('/revenue-by-category', reportController.getRevenueByCategory);
router.get('/payment-modes', reportController.getPaymentModes);
router.get('/tyre-sales',          reportController.getTyreSales);
router.get('/tyre-purchases',      reportController.getTyrePurchases);
router.get('/revenue-trend',    reportController.getRevenueTrend);

module.exports = router;