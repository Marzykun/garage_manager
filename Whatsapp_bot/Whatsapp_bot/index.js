// index.js
// Main entry point — Twilio Sandbox version
// No QR code needed! Twilio receives messages and forwards to this server via webhook

require('dotenv').config();
const express = require('express');
const cors    = require('cors');

const { handleMessage } = require('./messageHandler');
const { sendMessage }   = require('./twilioClient');
const { createNotifierServer } = require('./notifier');

const BOT_PORT  = process.env.BOT_PORT  || 3001;

console.log('\n🚀 Starting Garage Bot System (Twilio Sandbox Mode)...\n');

// ─── Step 1: Start Notifier Server ───────────────────────────────────────────
const notifierApp = createNotifierServer(sendMessage);
notifierApp.listen(3003, () => {
  console.log(`[Notifier] 🟢 Notifier server running on http://localhost:3003`);
  console.log(`[Notifier] Backend calls: POST http://localhost:3003/notify\n`);
});

// ─── Step 2: Webhook Server — Twilio forwards messages here ──────────────────
const app = express();
app.use(cors());
app.use(express.urlencoded({ extended: false })); // Twilio sends URL-encoded POST
app.use(express.json());

// Health check
app.get('/', (req, res) => {
  res.json({
    status: 'Garage Bot is running!',
    mode: 'Twilio Sandbox',
    garage: process.env.GARAGE_NAME,
    webhook: `POST /webhook`,
    instructions: 'Set this server URL as your Twilio sandbox webhook',
  });
});

// Twilio webhook — every WhatsApp message hits this endpoint
app.post('/webhook', async (req, res) => {
  // Twilio sends: From (whatsapp:+91...), Body (message text)
  const from    = req.body.From || '';   // e.g. "whatsapp:+919876543210"
  const msgBody = req.body.Body || '';

  // Extract clean phone number
  const phone = from.replace('whatsapp:+', '').trim();

  if (!phone || !msgBody) {
    return res.status(200).send('<Response></Response>');
  }

  console.log(`[Bot] 📩 From: ${phone} | Message: "${msgBody}"`);

  try {
    const reply = await handleMessage(phone, msgBody.trim());
    if (reply) {
      await sendMessage(phone, reply);
      console.log(`[Bot] 📤 Replied to ${phone}`);
    }
  } catch (err) {
    console.error('[Bot] Error:', err.message);
    await sendMessage(phone, '⚠️ Something went wrong. Please try again or call us directly.');
  }

  // Twilio expects empty TwiML response (we send manually via API above)
  res.status(200).send('<Response></Response>');
});

// ─── Start Webhook Server ─────────────────────────────────────────────────────
app.listen(BOT_PORT, () => {
  console.log('─'.repeat(55));
  console.log('📋 System Status:');
  console.log(`   Webhook Server   → http://localhost:${BOT_PORT}/webhook`);
  console.log(`   Notifier Server  → http://localhost:3003/notify`);
  console.log(`   Backend          → ${process.env.BACKEND_URL || 'http://localhost:3000/api'}`);
  console.log('─'.repeat(55));
  console.log('\n⚠️  NEXT STEP: Expose this server using ngrok');
  console.log('   Run: npx ngrok http ' + BOT_PORT);
  console.log('   Then paste the ngrok URL into Twilio sandbox webhook\n');
});
