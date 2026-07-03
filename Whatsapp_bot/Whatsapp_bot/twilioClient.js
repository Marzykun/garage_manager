// twilioClient.js
// Handles sending WhatsApp messages via Twilio Sandbox
// Replaces whatsapp-web.js — same logic, different sender

require('dotenv').config();
const twilio = require('twilio');

const accountSid = process.env.TWILIO_ACCOUNT_SID;
const authToken  = process.env.TWILIO_AUTH_TOKEN;
const fromNumber = process.env.TWILIO_WHATSAPP_FROM; // whatsapp:+14155238886

const client = twilio(accountSid, authToken);

/**
 * Send a WhatsApp message to a customer
 * @param {string} toPhone - customer phone e.g. "919876543210"
 * @param {string} message - text to send
 */
async function sendMessage(toPhone, message) {
  // Twilio needs format: whatsapp:+919876543210
  const cleaned = toPhone.replace(/\D/g, '');
  const to = `whatsapp:+${cleaned.startsWith('91') ? cleaned : '91' + cleaned}`;

  try {
    const result = await client.messages.create({
      from: fromNumber,
      to,
      body: message,
    });
    console.log(`[Twilio] ✅ Sent to ${to} | SID: ${result.sid}`);
    return { success: true, sid: result.sid };
  } catch (error) {
    console.error(`[Twilio] ❌ Failed to send to ${to}:`, error.message);
    return { success: false, error: error.message };
  }
}

module.exports = { sendMessage };
