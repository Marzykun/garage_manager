const express         = require('express');
const router          = express.Router();
const invoiceController = require('../controllers/invoiceController');

router.post('/',                    invoiceController.createInvoice);
router.get('/',                     invoiceController.getAllInvoices);
router.get('/job/:job_card_id',     invoiceController.getInvoiceByJob);
router.get('/:id',                  invoiceController.getInvoiceById);
router.put('/:id',                  invoiceController.updateInvoice);
router.patch('/:id/pay',            invoiceController.markAsPaid);
router.patch('/:id/send',           invoiceController.sendInvoiceWhatsApp);

module.exports = router;