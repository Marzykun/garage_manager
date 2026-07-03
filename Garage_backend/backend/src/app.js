const express      = require('express');
const cors         = require('cors');
require('dotenv').config();

const authRoutes     = require('./routes/authRoutes');
const customerRoutes = require('./routes/customerRoutes');
const vehicleRoutes  = require('./routes/vehicleRoutes');
const jobRoutes      = require('./routes/jobRoutes');
const errorHandler   = require('./middleware/errorHandler');
const protect        = require('./middleware/authMiddleware');
const inventoryRoutes = require('./routes/inventoryRoutes');
const balancingRoutes = require('./routes/balancingRoutes');
const alignmentRoutes = require('./routes/alignmentRoutes');
const tyreRoutes = require('./routes/tyreRoutes');
const invoiceRoutes = require('./routes/invoiceRoutes');
const appointmentRoutes = require('./routes/appointmentRoutes');
const reportRoutes = require('./routes/reportRoutes');
const ownerOnly    = require('./middleware/ownerMiddleware');
const settingsRoutes = require('./routes/settingsRoutes');
const serviceDetailRoutes = require('./routes/serviceDetailRoutes');
const paymentRoutes = require('./routes/paymentRoutes');
const botRoutes = require('./routes/botRoutes');
const botAuth = require('./middleware/botAuthMiddleware');

const app = express();

app.use(cors());
app.use(express.json());

// Public route — no token needed
app.use('/api/auth', authRoutes);

// WhatsApp bot — authenticated via shared API key, not the app JWT
app.use('/api/bot', botAuth, botRoutes);

// Protected routes — token required
app.use('/api/customers', protect, customerRoutes);
app.use('/api/vehicles',  protect, vehicleRoutes);
app.use('/api/jobs',      protect, jobRoutes);

app.get('/', (req, res) => {
  res.json({ message: 'Garage Management System API is running! ✅' });
});

app.use('/api/inventory', protect, inventoryRoutes);
app.use('/api/balancing', protect, balancingRoutes);
app.use('/api/alignment', protect, alignmentRoutes);
app.use('/api/tyres', protect, tyreRoutes);
app.use('/api/invoices', protect, invoiceRoutes);
app.use('/api/appointments', protect, appointmentRoutes);
app.use('/api/reports', ownerOnly, reportRoutes);
app.use('/api/settings', ownerOnly, settingsRoutes);
app.use('/api/service-details', protect, serviceDetailRoutes);
app.use('/api/payments', protect, paymentRoutes);

app.use(errorHandler);

module.exports = app;