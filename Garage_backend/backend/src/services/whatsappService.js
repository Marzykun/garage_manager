// Sends WhatsApp notifications via the bot's notifier server (Whatsapp_bot/notifier.js)
const NOTIFIER_URL = process.env.NOTIFIER_URL || 'http://localhost:3003/notify';

const notify = async (phone, vehicleNumber, service, type, extra = {}) => {
  if (!phone || !vehicleNumber) return;
  try {
    const res = await fetch(NOTIFIER_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone, vehicleNumber, service, type, ...extra }),
    });
    if (!res.ok) {
      console.error(`[WhatsApp] Notifier responded ${res.status} for '${type}' to ${phone}`);
    }
  } catch (err) {
    console.error(`[WhatsApp] Could not reach notifier for '${type}':`, err.message);
  }
};

const sendCompletionMessage = async (phone, customerName, vehicleNumber, service) => {
  console.log(`[WhatsApp] Vehicle ready — ${customerName} (${phone}) — ${vehicleNumber}`);
  await notify(phone, vehicleNumber, service || 'Service', 'completed');
};

const sendInvoiceMessage = async (phone, customerName, vehicleNumber, service, bill = {}) => {
  console.log(`[WhatsApp] Invoice — ${customerName} (${phone}) — ${vehicleNumber} — ₹${bill.total}`);
  await notify(phone, vehicleNumber, service || 'Service', 'invoice', {
    labour:        bill.labour,
    parts:         bill.parts,
    gst:           bill.gst,
    discount:      bill.discount,
    total:         bill.total,
    paymentStatus: bill.paymentStatus,
  });
};

const sendBookingConfirmation = async (phone, customerName, date, time) => {
  console.log(`[WhatsApp] Booking received — ${customerName} (${phone}) — ${date} at ${time}`);
};

const sendAppointmentAccepted = async (phone, customerName, date, time, vehicleNumber, service) => {
  console.log(`[WhatsApp] Appointment accepted — ${customerName} (${phone}) — ${date} at ${time}`);
  await notify(phone, vehicleNumber, service || 'Service', 'confirmed');
};

const sendAppointmentRejected = async (phone, customerName, vehicleNumber, service, reason) => {
  console.log(`[WhatsApp] Appointment rejected — ${customerName} (${phone})`);
  await notify(phone, vehicleNumber, service || 'Service', 'rejected', { reason });
};

const sendJobStarted = async (phone, vehicleNumber, service) => {
  console.log(`[WhatsApp] Job started — ${phone} — ${vehicleNumber}`);
  await notify(phone, vehicleNumber, service || 'Service', 'in_progress');
};

const sendJobCancelled = async (phone, vehicleNumber, service) => {
  console.log(`[WhatsApp] Job cancelled — ${phone} — ${vehicleNumber}`);
  await notify(phone, vehicleNumber, service || 'Service', 'cancelled');
};

const sendPaymentLink = async (phone, customerName, vehicleNumber, amount, paymentLink) => {
  console.log(`[WhatsApp] Payment link sent to ${customerName} (${phone}) — ₹${amount} — ${paymentLink}`);
};

const sendPaymentReceipt = async (phone, customerName, vehicleNumber, amount, paymentId) => {
  console.log(`[WhatsApp] Receipt sent to ${customerName} (${phone}) — ₹${amount} — Payment ID: ${paymentId}`);
};

module.exports = {
  sendCompletionMessage,
  sendInvoiceMessage,
  sendBookingConfirmation,
  sendAppointmentAccepted,
  sendAppointmentRejected,
  sendJobStarted,
  sendJobCancelled,
  sendPaymentLink,
  sendPaymentReceipt,
};
