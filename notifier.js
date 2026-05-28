// notifier.js
// Updated with new notification types: approved, rejected, cancelled

require('dotenv').config();
const express = require('express');
const cors    = require('cors');

const GARAGE_NAME     = process.env.GARAGE_NAME     || 'Sundar Auto Care';
const GARAGE_LOCATION = process.env.GARAGE_LOCATION || 'Musiri, Trichy District, Tamil Nadu';

function getNotificationMessage(type, vehicleNumber, service, extra = {}) {
  switch (type) {
    case 'confirmed':
      return (
        `✅ *Booking Confirmed!*\n\n` +
        `🚗 Vehicle: *${vehicleNumber}*\n` +
        `🔧 Service: *${service}*\n\n` +
        `You are now in the queue.\n` +
        `We'll notify you when we start! 🙏`
      );
    case 'in_progress':
      return (
        `🔧 *Work Started!*\n\n` +
        `We've started working on your vehicle.\n\n` +
        `🚗 Vehicle: *${vehicleNumber}*\n` +
        `🔧 Service: *${service}*\n\n` +
        `We'll notify you when it's ready!`
      );
    case 'completed':
      return (
        `✅ *Your vehicle is ready for pickup!*\n\n` +
        `🚗 Vehicle: *${vehicleNumber}*\n` +
        `🔧 Service: *${service}*\n\n` +
        `📍 *${GARAGE_NAME}*\n` +
        `${GARAGE_LOCATION}\n\n` +
        `Thank you for choosing us! 🙏`
      );
    case 'approved':
      return (
        `✅ *Your service request has been accepted!*\n\n` +
        `🚗 Vehicle: *${vehicleNumber}*\n` +
        `🔧 Service: *${service}*\n\n` +
        `You are now in the queue.\n` +
        `We'll notify you when we start! 🙏`
      );
    case 'rejected':
      return (
        `❌ *Sorry, your service request was rejected.*\n\n` +
        `🚗 Vehicle: *${vehicleNumber}*\n` +
        `🔧 Requested: *${service}*\n` +
        `📝 Reason: _${extra.reason || 'Service not available'}_\n\n` +
        `Reply *Hi* to book a different service.`
      );
    case 'cancelled':
      return (
        `🚫 *Booking Cancelled*\n\n` +
        `🚗 Vehicle: *${vehicleNumber}*\n` +
        `🔧 Service: *${service}*\n\n` +
        `Your booking has been cancelled.\n` +
        `Reply *Hi* to make a new booking.`
      );
    default:
      return null;
  }
}

function createNotifierServer(sendMessage) {
  const app = express();
  app.use(cors());
  app.use(express.json());

  app.get('/health', (req, res) => {
    res.json({ status: 'ok', garage: GARAGE_NAME });
  });

  // POST /notify
  // Body: { phone, vehicleNumber, service, type, reason (optional for rejected) }
  app.post('/notify', async (req, res) => {
    const { phone, vehicleNumber, service, type, reason } = req.body;

    if (!phone || !vehicleNumber || !service || !type) {
      return res.status(400).json({
        success: false,
        error: 'Missing fields: phone, vehicleNumber, service, type',
      });
    }

    const message = getNotificationMessage(type, vehicleNumber, service, { reason });
    if (!message) {
      return res.status(400).json({
        success: false,
        error: `Unknown type: "${type}". Use: confirmed, in_progress, completed, approved, rejected, cancelled`,
      });
    }

    const result = await sendMessage(phone, message);
    if (result.success) {
      console.log(`[Notifier] ✅ Sent '${type}' to ${phone}`);
      res.json({ success: true });
    } else {
      res.status(500).json({ success: false, error: result.error });
    }
  });

  return app;
}

module.exports = { createNotifierServer };
