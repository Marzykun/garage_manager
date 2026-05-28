// messageHandler.js
// Core bot brain — all 4 changes implemented:
// 1. Language preference (English / Tamil)
// 2. Owner name collection
// 3. Custom service + pending admin approval
// 4. Customer cancellation (before work starts only)

require('dotenv').config();
const {
  STATES, getSession, updateSession, resetSession, getServiceName,
} = require('./flowManager');
const { createJob, getJobStatus, cancelJob } = require('./apiClient');

const GARAGE_NAME     = process.env.GARAGE_NAME     || 'Sundar Auto Care';
const GARAGE_LOCATION = process.env.GARAGE_LOCATION || 'Musiri, Trichy District, Tamil Nadu';

// ─── Bilingual Message Templates ─────────────────────────────────────────────

const MSG = {

  // ── Language selection (always in both languages) ──
  askLanguage: () =>
    `👋 Welcome to *${GARAGE_NAME}*! / *${GARAGE_NAME}*-க்கு வரவேற்கிறோம்!\n\n` +
    `Please select your language:\n` +
    `மொழியை தேர்ந்தெடுக்கவும்:\n\n` +
    `1️⃣ - English\n` +
    `2️⃣ - தமிழ் (Tamil)`,

  // ── Service menu ──
  serviceMenu: (lang) => lang === 'ta'
    ? `🔧 சேவையை தேர்ந்தெடுக்கவும்:\n\n` +
      `1️⃣ - கார் கழுவுதல்\n` +
      `2️⃣ - டயர் மாற்றுதல்\n` +
      `3️⃣ - சக்கர சீரமைப்பு\n` +
      `4️⃣ - சக்கர சமநிலைப்படுத்துதல்\n` +
      `5️⃣ - வாகனத்தின் நிலையை அறிய\n` +
      `6️⃣ - பிற சேவைகள்\n\n` +
      `_எண்ணை அனுப்பவும்._`
    : `🔧 Please select a service:\n\n` +
      `1️⃣ - Car Washing\n` +
      `2️⃣ - Tyre Changing\n` +
      `3️⃣ - Tyre Alignment\n` +
      `4️⃣ - Tyre Balancing\n` +
      `5️⃣ - Check my vehicle status\n` +
      `6️⃣ - Other service\n\n` +
      `_Reply with the number of your choice._`,

  // ── Ask vehicle number ──
  askVehicleNumber: (service, lang) => lang === 'ta'
    ? `✅ தேர்வு: *${service}*\n\n` +
      `உங்கள் *வாகன பதிவு எண்ணை* அனுப்பவும்.\n` +
      `_(எடுத்துக்காட்டு: TN45AB1234)_`
    : `✅ You selected: *${service}*\n\n` +
      `Please send your *vehicle registration number*.\n` +
      `_(Example: TN45AB1234)_`,

  // ── Ask owner name ──
  askName: (lang) => lang === 'ta'
    ? `👤 உங்கள் *பெயரை* அனுப்பவும்.`
    : `👤 Please send your *name*.`,

  // ── Ask custom service description ──
  askCustomService: (lang) => lang === 'ta'
    ? `🔧 உங்களுக்கு என்ன சேவை தேவை என்று விவரிக்கவும்.\n` +
      `_(நிர்வாகி கிடைக்கிறதா என்று சரிபார்த்து தெரிவிப்பார்கள்)_`
    : `🔧 Please describe the service you need.\n` +
      `_(Admin will check if it's available and let you know)_`,

  // ── Booking received ──
  bookingReceived: (vehicleNumber, service, name, lang) => lang === 'ta'
    ? `🙏 நன்றி *${name}*! உங்கள் கோரிக்கை அனுப்பப்பட்டது.\n\n` +
      `🚗 வாகனம்: *${vehicleNumber}*\n` +
      `🔧 சேவை: *${service}*\n` +
      `📋 நிலை: _உறுதிப்படுத்தல் காத்திருக்கிறது..._\n\n` +
      `உறுதிப்படுத்தியதும் தெரிவிக்கிறோம்!\n` +
      `ரத்து செய்ய *cancel* என்று அனுப்பவும்.`
    : `🙏 Thank you *${name}*! Your request has been sent.\n\n` +
      `🚗 Vehicle: *${vehicleNumber}*\n` +
      `🔧 Service: *${service}*\n` +
      `📋 Status: _Waiting for confirmation..._\n\n` +
      `We will notify you once confirmed!\n` +
      `To cancel your booking, reply *cancel*.`,

  // ── Custom service received ──
  customServiceReceived: (vehicleNumber, name, description, lang) => lang === 'ta'
    ? `🙏 நன்றி *${name}*! உங்கள் சேவை கோரிக்கை அனுப்பப்பட்டது.\n\n` +
      `🚗 வாகனம்: *${vehicleNumber}*\n` +
      `🔧 சேவை விவரம்: _${description}_\n` +
      `📋 நிலை: _நிர்வாகி ஆய்வு செய்கிறார்..._\n\n` +
      `கிடைக்கிறதா என்று தெரிவிக்கிறோம்!\n` +
      `ரத்து செய்ய *cancel* என்று அனுப்பவும்.`
    : `🙏 Thank you *${name}*! Your custom service request has been sent.\n\n` +
      `🚗 Vehicle: *${vehicleNumber}*\n` +
      `🔧 Service described: _${description}_\n` +
      `📋 Status: _Admin is reviewing..._\n\n` +
      `We'll let you know if it's available!\n` +
      `To cancel your booking, reply *cancel*.`,

  // ── Booking error ──
  bookingError: (lang) => lang === 'ta'
    ? `⚠️ மன்னிக்கவும், சிக்கல் ஏற்பட்டது. மீண்டும் முயற்சிக்கவும்.\n` +
      `*Hi* என்று அனுப்பி தொடங்கவும்.`
    : `⚠️ Sorry, something went wrong. Please try again.\n` +
      `Reply *Hi* to start again.`,

  // ── Status found ──
  statusFound: (vehicleNumber, service, status, lang) => {
    const emoji = status === 'queued' ? '⏳' : status === 'in_progress' ? '🔧' : status === 'cancelled' ? '❌' : '✅';
    if (lang === 'ta') {
      const labelTa = status === 'queued' ? 'காத்திருக்கிறது' : status === 'in_progress' ? 'செயல்பாட்டில்' : status === 'cancelled' ? 'ரத்து செய்யப்பட்டது' : 'முடிந்தது';
      return `🔍 *வாகன நிலை*\n\n🚗 வாகனம்: *${vehicleNumber}*\n🔧 சேவை: *${service}*\n${emoji} நிலை: *${labelTa}*\n\nதகவல் வந்தால் தெரிவிக்கிறோம்!`;
    }
    const labelEn = status === 'queued' ? 'In Queue' : status === 'in_progress' ? 'In Progress' : status === 'cancelled' ? 'Cancelled' : 'Completed';
    return `🔍 *Vehicle Status*\n\n🚗 Vehicle: *${vehicleNumber}*\n🔧 Service: *${service}*\n${emoji} Status: *${labelEn}*\n\nWe will notify you when there's an update!`;
  },

  // ── Status not found ──
  statusNotFound: (vehicleNumber, lang) => lang === 'ta'
    ? `❌ *${vehicleNumber}* க்கு செயலில் உள்ள பணி இல்லை.\n` +
      `எண்ணை சரிபார்த்து மீண்டும் முயற்சிக்கவும்.\n` +
      `*Hi* என்று அனுப்பி தொடங்கவும்.`
    : `❌ No active job found for vehicle: *${vehicleNumber}*\n\n` +
      `Please check the number and try again.\n` +
      `Reply *Hi* to start over.`,

  // ── Ask vehicle for status check ──
  askVehicleForStatus: (lang) => lang === 'ta'
    ? `🔍 நிலை அறிய *வாகன பதிவு எண்ணை* அனுப்பவும்.\n_(எடுத்துக்காட்டு: TN45AB1234)_`
    : `🔍 Please send your *vehicle registration number* to check status.\n_(Example: TN45AB1234)_`,

  // ── Unknown input ──
  unknown: (lang) => lang === 'ta'
    ? `🤔 புரியவில்லை.\n*Hi* என்று அனுப்பி மெனுவை காணவும்.`
    : `🤔 Sorry, I didn't understand that.\n\nReply *Hi* to see the main menu.`,

  // ── Already booked ──
  alreadyBooked: (vehicleNumber, service, lang) => lang === 'ta'
    ? `✅ உங்களுக்கு ஏற்கனவே பதிவு உள்ளது!\n\n` +
      `🚗 வாகனம்: *${vehicleNumber}*\n` +
      `🔧 சேவை: *${service}*\n\n` +
      `நிலை அறிய *5* அனுப்பவும்.\n` +
      `ரத்து செய்ய *cancel* அனுப்பவும்.`
    : `✅ You already have an active booking!\n\n` +
      `🚗 Vehicle: *${vehicleNumber}*\n` +
      `🔧 Service: *${service}*\n\n` +
      `Reply *5* to check status.\n` +
      `Reply *cancel* to cancel your booking.`,

  // ── Cancel confirm (before admin accepts) ──
  cancelConfirmImmediate: (vehicleNumber, lang) => lang === 'ta'
    ? `⚠️ *${vehicleNumber}* பதிவை ரத்து செய்கிறீர்களா?\n\n1️⃣ - ஆம், ரத்து செய்\n2️⃣ - இல்லை, தொடர்க`
    : `⚠️ Are you sure you want to cancel your booking for *${vehicleNumber}*?\n\n1️⃣ - Yes, cancel it\n2️⃣ - No, keep my booking`,

  // ── Cancel confirm (after accepted, before in progress) ──
  cancelConfirmWarning: (vehicleNumber, lang) => lang === 'ta'
    ? `⚠️ உங்கள் பதிவு உறுதிப்படுத்தப்பட்டது ஆனால் வேலை இன்னும் தொடங்கவில்லை.\n\n` +
      `*${vehicleNumber}* ரத்து செய்கிறீர்களா?\n\n` +
      `1️⃣ - ஆம், ரத்து செய்\n2️⃣ - இல்லை, தொடர்க`
    : `⚠️ Your booking is confirmed but work hasn't started yet.\n\n` +
      `Are you sure you want to cancel *${vehicleNumber}*?\n\n` +
      `1️⃣ - Yes, cancel it\n2️⃣ - No, keep my booking`,

  // ── Cancel blocked (work started) ──
  cancelBlocked: (lang) => lang === 'ta'
    ? `❌ மன்னிக்கவும், உங்கள் வாகனில் வேலை தொடங்கிவிட்டது.\n` +
      `இப்போது ரத்து செய்ய முடியாது.\n\n` +
      `நேரடியாக தொடர்பு கொள்ளவும்:\n📍 *${GARAGE_NAME}*, ${GARAGE_LOCATION}`
    : `❌ Sorry, work has already started on your vehicle.\n` +
      `Cancellation is not possible at this stage.\n\n` +
      `Please call us directly:\n📍 *${GARAGE_NAME}*, ${GARAGE_LOCATION}`,

  // ── Cancel success ──
  cancelSuccess: (vehicleNumber, lang) => lang === 'ta'
    ? `✅ *${vehicleNumber}* பதிவு ரத்து செய்யப்பட்டது.\n\nமீண்டும் பதிவு செய்ய *Hi* அனுப்பவும்.`
    : `✅ Your booking for *${vehicleNumber}* has been cancelled.\n\nReply *Hi* to make a new booking.`,

  // ── Cancel aborted ──
  cancelAborted: (lang) => lang === 'ta'
    ? `👍 சரி! உங்கள் பதிவு தொடர்கிறது.`
    : `👍 Okay! Your booking is still active.`,

  // ── Cancel error ──
  cancelError: (lang) => lang === 'ta'
    ? `⚠️ ரத்து செய்வதில் சிக்கல். நேரடியாக தொடர்பு கொள்ளவும்.`
    : `⚠️ Could not cancel. Please contact us directly.`,

  // ── Invalid vehicle number ──
  invalidVehicle: (lang) => lang === 'ta'
    ? `⚠️ தவறான வாகன எண். *TN45AB1234* வடிவத்தில் அனுப்பவும்.`
    : `⚠️ That doesn't look like a valid vehicle number.\nPlease send it in this format: *TN45AB1234*`,
};

// ─── Validators ───────────────────────────────────────────────────────────────

function isValidVehicleNumber(text) {
  const cleaned = text.replace(/\s+/g, '').toUpperCase();
  return /^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$/.test(cleaned);
}

function normalizeVehicleNumber(text) {
  return text.replace(/\s+/g, '').toUpperCase();
}

// ─── Main Handler ─────────────────────────────────────────────────────────────

async function handleMessage(phone, messageText) {
  const input     = messageText.trim();
  const inputLower = input.toLowerCase();
  const session   = getSession(phone);
  const lang      = session.data.language || 'en';

  console.log(`[Bot] From: ${phone} | State: ${session.state} | Lang: ${lang} | Input: "${input}"`);

  // ── Global: "hi/hello/menu" always restarts ──
  if (['hi', 'hello', 'hey', 'start', 'menu', 'வணக்கம்'].includes(inputLower)) {
    updateSession(phone, STATES.AWAITING_LANGUAGE, {});
    return MSG.askLanguage();
  }

  // ── Global: "cancel" keyword ──
  if (inputLower === 'cancel' || inputLower === 'ரத்து') {
    if (session.state === STATES.BOOKED) {
      const status = session.data.jobStatus || 'queued';
      if (status === 'in_progress') {
        return MSG.cancelBlocked(lang);
      }
      updateSession(phone, STATES.AWAITING_CANCEL_CONFIRM);
      if (status === 'confirmed') {
        return MSG.cancelConfirmWarning(session.data.vehicleNumber, lang);
      }
      return MSG.cancelConfirmImmediate(session.data.vehicleNumber, lang);
    }
    return MSG.unknown(lang);
  }

  // ── IDLE ──
  if (session.state === STATES.IDLE) {
    updateSession(phone, STATES.AWAITING_LANGUAGE, {});
    return MSG.askLanguage();
  }

  // ── AWAITING_LANGUAGE ──
  if (session.state === STATES.AWAITING_LANGUAGE) {
    if (input === '1') {
      updateSession(phone, STATES.AWAITING_SERVICE, { language: 'en' });
      return MSG.serviceMenu('en');
    }
    if (input === '2') {
      updateSession(phone, STATES.AWAITING_SERVICE, { language: 'ta' });
      return MSG.serviceMenu('ta');
    }
    return MSG.askLanguage();
  }

  // ── AWAITING_SERVICE ──
  if (session.state === STATES.AWAITING_SERVICE) {
    // Status check
    if (input === '5') {
      updateSession(phone, STATES.AWAITING_VEHICLE, { flowType: 'status' });
      return MSG.askVehicleForStatus(lang);
    }
    // Custom service
    if (input === '6') {
      updateSession(phone, STATES.AWAITING_VEHICLE, { flowType: 'custom' });
      return MSG.askVehicleNumber('Custom Service', lang);
    }
    // Standard services 1-4
    const serviceName = getServiceName(input, lang);
    if (!serviceName) {
      return MSG.unknown(lang) + '\n\n' + MSG.serviceMenu(lang);
    }
    updateSession(phone, STATES.AWAITING_VEHICLE, {
      service: serviceName,
      flowType: 'booking',
    });
    return MSG.askVehicleNumber(serviceName, lang);
  }

  // ── AWAITING_VEHICLE ──
  if (session.state === STATES.AWAITING_VEHICLE) {
    if (!isValidVehicleNumber(input)) {
      return MSG.invalidVehicle(lang);
    }
    const vehicleNumber = normalizeVehicleNumber(input);

    // Status check flow
    if (session.data.flowType === 'status') {
      const result = await getJobStatus(vehicleNumber);
      resetSession(phone);
      if (result.success && result.data && result.data.job) {
        const job = result.data.job;
        return MSG.statusFound(vehicleNumber, job.service, job.status, lang);
      }
      return MSG.statusNotFound(vehicleNumber, lang);
    }

    // Booking / custom — ask name next
    updateSession(phone, STATES.AWAITING_NAME, { vehicleNumber });
    return MSG.askName(lang);
  }

  // ── AWAITING_NAME ──
  if (session.state === STATES.AWAITING_NAME) {
    const name = input.trim();
    if (name.length < 2) {
      return lang === 'ta'
        ? `⚠️ சரியான பெயரை அனுப்பவும்.`
        : `⚠️ Please send a valid name.`;
    }

    // Custom service — ask description
    if (session.data.flowType === 'custom') {
      updateSession(phone, STATES.AWAITING_CUSTOM_SERVICE, { customerName: name });
      return MSG.askCustomService(lang);
    }

    // Standard booking — create job
    const { vehicleNumber, service } = session.data;
    const result = await createJob(phone, vehicleNumber, service, name);
    if (result.success) {
      updateSession(phone, STATES.BOOKED, {
        customerName: name,
        jobId: result.data.job_id,
        jobStatus: 'queued',
      });
      return MSG.bookingReceived(vehicleNumber, service, name, lang);
    }
    resetSession(phone);
    return MSG.bookingError(lang);
  }

  // ── AWAITING_CUSTOM_SERVICE ──
  if (session.state === STATES.AWAITING_CUSTOM_SERVICE) {
    const description = input.trim();
    if (description.length < 3) {
      return lang === 'ta'
        ? `⚠️ கொஞ்சம் விரிவாக விவரிக்கவும்.`
        : `⚠️ Please describe the service in a bit more detail.`;
    }
    const { vehicleNumber, customerName } = session.data;
    const result = await createJob(phone, vehicleNumber, description, customerName, true);
    if (result.success) {
      updateSession(phone, STATES.BOOKED, {
        jobId: result.data.job_id,
        jobStatus: 'pending_approval',
        isCustom: true,
        customDescription: description,
      });
      return MSG.customServiceReceived(vehicleNumber, customerName, description, lang);
    }
    resetSession(phone);
    return MSG.bookingError(lang);
  }

  // ── AWAITING_CANCEL_CONFIRM ──
  if (session.state === STATES.AWAITING_CANCEL_CONFIRM) {
    if (input === '1') {
      const { jobId, vehicleNumber } = session.data;
      const result = await cancelJob(jobId);
      resetSession(phone);
      if (result.success) {
        return MSG.cancelSuccess(vehicleNumber, lang);
      }
      return MSG.cancelError(lang);
    }
    if (input === '2') {
      updateSession(phone, STATES.BOOKED);
      return MSG.cancelAborted(lang);
    }
    return lang === 'ta'
      ? `1️⃣ ரத்து செய் அல்லது 2️⃣ தொடர்க என்று அனுப்பவும்.`
      : `Please reply *1* to confirm cancel or *2* to keep your booking.`;
  }

  // ── BOOKED ──
  if (session.state === STATES.BOOKED) {
    if (input === '5') {
      updateSession(phone, STATES.AWAITING_VEHICLE, { flowType: 'status' });
      return MSG.askVehicleForStatus(lang);
    }
    return MSG.alreadyBooked(session.data.vehicleNumber, session.data.service || session.data.customDescription, lang);
  }

  return MSG.unknown(lang);
}

module.exports = { handleMessage };
