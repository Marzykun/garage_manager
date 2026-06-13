// messageHandler.js
// Updated with: vehicle type, km run, tyre size, wash type selection

require('dotenv').config();
const {
  STATES, getSession, updateSession, resetSession,
  getServiceName, getWashTypeName, getVehicleTypeName,
  needsTyreSize, isCarWash,
} = require('./flowManager');
const { createJob, getJobStatus, cancelJob } = require('./apiClient');

const GARAGE_NAME     = process.env.GARAGE_NAME     || 'Sundar Auto Care';
const GARAGE_LOCATION = process.env.GARAGE_LOCATION || 'Musiri, Trichy District, Tamil Nadu';

// ─── Message Templates ────────────────────────────────────────────────────────

const MSG = {

  askLanguage: () =>
    `👋 Welcome to *${GARAGE_NAME}*! / *${GARAGE_NAME}*-க்கு வரவேற்கிறோம்!\n\n` +
    `Please select your language:\nமொழியை தேர்ந்தெடுக்கவும்:\n\n` +
    `1️⃣ - English\n2️⃣ - தமிழ் (Tamil)`,

  serviceMenu: (lang) => lang === 'ta'
    ? `🔧 சேவையை தேர்ந்தெடுக்கவும்:\n\n` +
      `1️⃣ - கார் கழுவுதல்\n2️⃣ - டயர் மாற்றுதல்\n` +
      `3️⃣ - சக்கர சீரமைப்பு\n4️⃣ - சக்கர சமநிலைப்படுத்துதல்\n` +
      `5️⃣ - வாகனத்தின் நிலையை அறிய\n6️⃣ - பிற சேவைகள்\n\n_எண்ணை அனுப்பவும்._`
    : `🔧 Please select a service:\n\n` +
      `1️⃣ - Car Washing\n2️⃣ - Tyre Changing\n` +
      `3️⃣ - Tyre Alignment\n4️⃣ - Tyre Balancing\n` +
      `5️⃣ - Check my vehicle status\n6️⃣ - Other service\n\n_Reply with the number of your choice._`,

  askVehicleNumber: (service, lang) => lang === 'ta'
    ? `✅ தேர்வு: *${service}*\n\nஉங்கள் *வாகன பதிவு எண்ணை* அனுப்பவும்.\n_(எடுத்துக்காட்டு: TN45AB1234)_`
    : `✅ You selected: *${service}*\n\nPlease send your *vehicle registration number*.\n_(Example: TN45AB1234)_`,

  askVehicleType: (lang) => lang === 'ta'
    ? `🚗 வாகன வகையை தேர்ந்தெடுக்கவும்:\n\n1️⃣ - கார்\n2️⃣ - வேன்\n3️⃣ - லாரி`
    : `🚗 Please select your vehicle type:\n\n1️⃣ - Car\n2️⃣ - Van\n3️⃣ - Lorry`,

  askKm: (lang) => lang === 'ta'
    ? `🔢 உங்கள் வாகனம் எத்தனை கிலோமீட்டர் ஓடியது?\n_(எடுத்துக்காட்டு: 45000)_`
    : `🔢 How many kilometres has your vehicle run?\n_(Example: 45000)_`,

  askTyreSize: (lang) => lang === 'ta'
    ? `🔧 டயர் சைஸ் அனுப்பவும்.\n_(எடுத்துக்காட்டு: 185/65 R15)_`
    : `🔧 Please send your tyre size.\n_(Example: 185/65 R15)_`,

  askWashType: (lang) => lang === 'ta'
    ? `🚿 கழுவுதல் வகையை தேர்ந்தெடுக்கவும்:\n\n1️⃣ - தண்ணீர் கழுவுதல்\n2️⃣ - பாடி வாஷ்\n3️⃣ - முழு கழுவுதல்`
    : `🚿 Please select wash type:\n\n1️⃣ - Water Wash\n2️⃣ - Body Wash\n3️⃣ - Full Wash`,

  askName: (lang) => lang === 'ta'
    ? `👤 உங்கள் *பெயரை* அனுப்பவும்.`
    : `👤 Please send your *name*.`,

  askCustomService: (lang) => lang === 'ta'
    ? `🔧 உங்களுக்கு என்ன சேவை தேவை என்று விவரிக்கவும்.\n_(நிர்வாகி கிடைக்கிறதா என்று சரிபார்த்து தெரிவிப்பார்கள்)_`
    : `🔧 Please describe the service you need.\n_(Admin will check if it's available and let you know)_`,

  bookingReceived: (vehicleNumber, service, name, lang, extra = {}) => {
    const washLine   = extra.washType   ? (lang === 'ta' ? `\n🚿 கழுவுதல்: *${extra.washType}*`   : `\n🚿 Wash Type: *${extra.washType}*`)   : '';
    const tyreLine   = extra.tyreSize   ? (lang === 'ta' ? `\n🔩 டயர் சைஸ்: *${extra.tyreSize}*`  : `\n🔩 Tyre Size: *${extra.tyreSize}*`)  : '';
    const kmLine     = extra.kmRun      ? (lang === 'ta' ? `\n📍 கி.மீ: *${extra.kmRun}*`          : `\n📍 KM Run: *${extra.kmRun}*`)         : '';
    const vtypeLine  = extra.vehicleType? (lang === 'ta' ? `\n🚙 வாகன வகை: *${extra.vehicleType}*` : `\n🚙 Vehicle Type: *${extra.vehicleType}*`) : '';
    return lang === 'ta'
      ? `🙏 நன்றி *${name}*! உங்கள் கோரிக்கை அனுப்பப்பட்டது.\n\n🚗 வாகனம்: *${vehicleNumber}*${vtypeLine}${kmLine}${tyreLine}\n🔧 சேவை: *${service}*${washLine}\n📋 நிலை: _உறுதிப்படுத்தல் காத்திருக்கிறது..._\n\nஉறுதிப்படுத்தியதும் தெரிவிக்கிறோம்!\nரத்து செய்ய *cancel* என்று அனுப்பவும்.`
      : `🙏 Thank you *${name}*! Your request has been sent.\n\n🚗 Vehicle: *${vehicleNumber}*${vtypeLine}${kmLine}${tyreLine}\n🔧 Service: *${service}*${washLine}\n📋 Status: _Waiting for confirmation..._\n\nWe will notify you once confirmed!\nTo cancel your booking, reply *cancel*.`;
  },

  customServiceReceived: (vehicleNumber, name, description, lang) => lang === 'ta'
    ? `🙏 நன்றி *${name}*! உங்கள் சேவை கோரிக்கை அனுப்பப்பட்டது.\n\n🚗 வாகனம்: *${vehicleNumber}*\n🔧 சேவை விவரம்: _${description}_\n📋 நிலை: _நிர்வாகி ஆய்வு செய்கிறார்..._\n\nகிடைக்கிறதா என்று தெரிவிக்கிறோம்!\nரத்து செய்ய *cancel* என்று அனுப்பவும்.`
    : `🙏 Thank you *${name}*! Your custom service request has been sent.\n\n🚗 Vehicle: *${vehicleNumber}*\n🔧 Service described: _${description}_\n📋 Status: _Admin is reviewing..._\n\nWe'll let you know if it's available!\nTo cancel your booking, reply *cancel*.`,

  bookingError: (lang) => lang === 'ta'
    ? `⚠️ மன்னிக்கவும், சிக்கல் ஏற்பட்டது. மீண்டும் முயற்சிக்கவும்.\n*Hi* என்று அனுப்பி தொடங்கவும்.`
    : `⚠️ Sorry, something went wrong. Please try again.\nReply *Hi* to start again.`,

  statusFound: (vehicleNumber, service, status, lang) => {
    const emoji = status === 'queued' ? '⏳' : status === 'in_progress' ? '🔧' : status === 'cancelled' ? '❌' : '✅';
    if (lang === 'ta') {
      const label = status === 'queued' ? 'காத்திருக்கிறது' : status === 'in_progress' ? 'செயல்பாட்டில்' : status === 'cancelled' ? 'ரத்து செய்யப்பட்டது' : 'முடிந்தது';
      return `🔍 *வாகன நிலை*\n\n🚗 வாகனம்: *${vehicleNumber}*\n🔧 சேவை: *${service}*\n${emoji} நிலை: *${label}*\n\nதகவல் வந்தால் தெரிவிக்கிறோம்!`;
    }
    const label = status === 'queued' ? 'In Queue' : status === 'in_progress' ? 'In Progress' : status === 'cancelled' ? 'Cancelled' : 'Completed';
    return `🔍 *Vehicle Status*\n\n🚗 Vehicle: *${vehicleNumber}*\n🔧 Service: *${service}*\n${emoji} Status: *${label}*\n\nWe will notify you when there's an update!`;
  },

  statusNotFound: (vehicleNumber, lang) => lang === 'ta'
    ? `❌ *${vehicleNumber}* க்கு செயலில் உள்ள பணி இல்லை.\nஎண்ணை சரிபார்த்து மீண்டும் முயற்சிக்கவும்.\n*Hi* என்று அனுப்பி தொடங்கவும்.`
    : `❌ No active job found for vehicle: *${vehicleNumber}*\n\nPlease check the number and try again.\nReply *Hi* to start over.`,

  askVehicleForStatus: (lang) => lang === 'ta'
    ? `🔍 நிலை அறிய *வாகன பதிவு எண்ணை* அனுப்பவும்.\n_(எடுத்துக்காட்டு: TN45AB1234)_`
    : `🔍 Please send your *vehicle registration number* to check status.\n_(Example: TN45AB1234)_`,

  unknown: (lang) => lang === 'ta'
    ? `🤔 புரியவில்லை.\n*Hi* என்று அனுப்பி மெனுவை காணவும்.`
    : `🤔 Sorry, I didn't understand that.\n\nReply *Hi* to see the main menu.`,

  alreadyBooked: (vehicleNumber, service, lang) => lang === 'ta'
    ? `✅ உங்களுக்கு ஏற்கனவே பதிவு உள்ளது!\n\n🚗 வாகனம்: *${vehicleNumber}*\n🔧 சேவை: *${service}*\n\nநிலை அறிய *5* அனுப்பவும்.\nரத்து செய்ய *cancel* அனுப்பவும்.`
    : `✅ You already have an active booking!\n\n🚗 Vehicle: *${vehicleNumber}*\n🔧 Service: *${service}*\n\nReply *5* to check status.\nReply *cancel* to cancel your booking.`,

  cancelConfirmImmediate: (vehicleNumber, lang) => lang === 'ta'
    ? `⚠️ *${vehicleNumber}* பதிவை ரத்து செய்கிறீர்களா?\n\n1️⃣ - ஆம், ரத்து செய்\n2️⃣ - இல்லை, தொடர்க`
    : `⚠️ Are you sure you want to cancel your booking for *${vehicleNumber}*?\n\n1️⃣ - Yes, cancel it\n2️⃣ - No, keep my booking`,

  cancelConfirmWarning: (vehicleNumber, lang) => lang === 'ta'
    ? `⚠️ உங்கள் பதிவு உறுதிப்படுத்தப்பட்டது ஆனால் வேலை இன்னும் தொடங்கவில்லை.\n\n*${vehicleNumber}* ரத்து செய்கிறீர்களா?\n\n1️⃣ - ஆம், ரத்து செய்\n2️⃣ - இல்லை, தொடர்க`
    : `⚠️ Your booking is confirmed but work hasn't started yet.\n\nAre you sure you want to cancel *${vehicleNumber}*?\n\n1️⃣ - Yes, cancel it\n2️⃣ - No, keep my booking`,

  cancelBlocked: (lang) => lang === 'ta'
    ? `❌ மன்னிக்கவும், உங்கள் வாகனில் வேலை தொடங்கிவிட்டது.\nஇப்போது ரத்து செய்ய முடியாது.\n\nநேரடியாக தொடர்பு கொள்ளவும்:\n📍 *${GARAGE_NAME}*, ${GARAGE_LOCATION}`
    : `❌ Sorry, work has already started on your vehicle.\nCancellation is not possible at this stage.\n\nPlease call us directly:\n📍 *${GARAGE_NAME}*, ${GARAGE_LOCATION}`,

  cancelSuccess: (vehicleNumber, lang) => lang === 'ta'
    ? `✅ *${vehicleNumber}* பதிவு ரத்து செய்யப்பட்டது.\n\nமீண்டும் பதிவு செய்ய *Hi* அனுப்பவும்.`
    : `✅ Your booking for *${vehicleNumber}* has been cancelled.\n\nReply *Hi* to make a new booking.`,

  cancelAborted: (lang) => lang === 'ta'
    ? `👍 சரி! உங்கள் பதிவு தொடர்கிறது.`
    : `👍 Okay! Your booking is still active.`,

  cancelError: (lang) => lang === 'ta'
    ? `⚠️ ரத்து செய்வதில் சிக்கல். நேரடியாக தொடர்பு கொள்ளவும்.`
    : `⚠️ Could not cancel. Please contact us directly.`,

  invalidVehicle: (lang) => lang === 'ta'
    ? `⚠️ தவறான வாகன எண். *TN45AB1234* வடிவத்தில் அனுப்பவும்.`
    : `⚠️ That doesn't look like a valid vehicle number.\nPlease send it in this format: *TN45AB1234*`,

  invalidVehicleType: (lang) => lang === 'ta'
    ? `⚠️ 1, 2 அல்லது 3 என்று அனுப்பவும்.`
    : `⚠️ Please reply with 1, 2, or 3 to select vehicle type.`,

  invalidWashType: (lang) => lang === 'ta'
    ? `⚠️ 1, 2 அல்லது 3 என்று அனுப்பவும்.`
    : `⚠️ Please reply with 1, 2, or 3 to select wash type.`,

  invalidKm: (lang) => lang === 'ta'
    ? `⚠️ சரியான கிலோமீட்டர் எண்ணை அனுப்பவும். (எடுத்துக்காட்டு: 45000)`
    : `⚠️ Please send a valid kilometre number. (Example: 45000)`,
};

// ─── Validators ───────────────────────────────────────────────────────────────

function isValidVehicleNumber(text) {
  const cleaned = text.replace(/\s+/g, '').toUpperCase();
  return /^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$/.test(cleaned);
}

function normalizeVehicleNumber(text) {
  return text.replace(/\s+/g, '').toUpperCase();
}

function isValidKm(text) {
  return /^\d{1,7}$/.test(text.trim());
}

// ─── Main Handler ─────────────────────────────────────────────────────────────

async function handleMessage(phone, messageText) {
  const input      = messageText.trim();
  const inputLower = input.toLowerCase();
  const session    = getSession(phone);
  const lang       = session.data.language || 'en';

  console.log(`[Bot] From: ${phone} | State: ${session.state} | Lang: ${lang} | Input: "${input}"`);

  // ── Global: hi/hello restarts ──
  if (['hi', 'hello', 'hey', 'start', 'menu', 'வணக்கம்'].includes(inputLower)) {
    updateSession(phone, STATES.AWAITING_LANGUAGE, {});
    return MSG.askLanguage();
  }

  // ── Global: cancel ──
  if (inputLower === 'cancel' || inputLower === 'ரத்து') {
    if (session.state === STATES.BOOKED) {
      const status = session.data.jobStatus || 'queued';
      if (status === 'in_progress') return MSG.cancelBlocked(lang);
      updateSession(phone, STATES.AWAITING_CANCEL_CONFIRM);
      return status === 'confirmed'
        ? MSG.cancelConfirmWarning(session.data.vehicleNumber, lang)
        : MSG.cancelConfirmImmediate(session.data.vehicleNumber, lang);
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
    if (input === '1') { updateSession(phone, STATES.AWAITING_SERVICE, { language: 'en' }); return MSG.serviceMenu('en'); }
    if (input === '2') { updateSession(phone, STATES.AWAITING_SERVICE, { language: 'ta' }); return MSG.serviceMenu('ta'); }
    return MSG.askLanguage();
  }

  // ── AWAITING_SERVICE ──
  if (session.state === STATES.AWAITING_SERVICE) {
    if (input === '5') { updateSession(phone, STATES.AWAITING_VEHICLE, { flowType: 'status' }); return MSG.askVehicleForStatus(lang); }
    if (input === '6') { updateSession(phone, STATES.AWAITING_VEHICLE, { flowType: 'custom' }); return MSG.askVehicleNumber('Custom Service', lang); }
    const serviceName = getServiceName(input, lang);
    if (!serviceName) return MSG.unknown(lang) + '\n\n' + MSG.serviceMenu(lang);
    updateSession(phone, STATES.AWAITING_VEHICLE, { service: serviceName, flowType: 'booking' });
    return MSG.askVehicleNumber(serviceName, lang);
  }

  // ── AWAITING_VEHICLE ──
  if (session.state === STATES.AWAITING_VEHICLE) {
    if (!isValidVehicleNumber(input)) return MSG.invalidVehicle(lang);
    const vehicleNumber = normalizeVehicleNumber(input);

    if (session.data.flowType === 'status') {
      const result = await getJobStatus(vehicleNumber);
      resetSession(phone);
      if (result.success && result.data && result.data.job) {
        return MSG.statusFound(vehicleNumber, result.data.job.service, result.data.job.status, lang);
      }
      return MSG.statusNotFound(vehicleNumber, lang);
    }

    // Ask vehicle type next
    updateSession(phone, STATES.AWAITING_VEHICLE_TYPE, { vehicleNumber });
    return MSG.askVehicleType(lang);
  }

  // ── AWAITING_VEHICLE_TYPE ──
  if (session.state === STATES.AWAITING_VEHICLE_TYPE) {
    const vehicleType = getVehicleTypeName(input, lang);
    if (!vehicleType) return MSG.invalidVehicleType(lang);
    updateSession(phone, STATES.AWAITING_KM, { vehicleType });
    return MSG.askKm(lang);
  }

  // ── AWAITING_KM ──
  if (session.state === STATES.AWAITING_KM) {
    if (!isValidKm(input)) return MSG.invalidKm(lang);
    const kmRun = input.trim();

    // Tyre service → ask tyre size
    if (needsTyreSize(session.data.service)) {
      updateSession(phone, STATES.AWAITING_TYRE_SIZE, { kmRun });
      return MSG.askTyreSize(lang);
    }

    // Car wash → ask wash type
    if (isCarWash(session.data.service)) {
      updateSession(phone, STATES.AWAITING_WASH_TYPE, { kmRun });
      return MSG.askWashType(lang);
    }

    // Custom service or others → ask name
    updateSession(phone, STATES.AWAITING_NAME, { kmRun });
    return MSG.askName(lang);
  }

  // ── AWAITING_TYRE_SIZE ──
  if (session.state === STATES.AWAITING_TYRE_SIZE) {
    const tyreSize = input.trim();
    if (tyreSize.length < 3) {
      return lang === 'ta'
        ? `⚠️ சரியான டயர் சைஸ் அனுப்பவும். (எடுத்துக்காட்டு: 185/65 R15)`
        : `⚠️ Please send a valid tyre size. (Example: 185/65 R15)`;
    }
    updateSession(phone, STATES.AWAITING_NAME, { tyreSize });
    return MSG.askName(lang);
  }

  // ── AWAITING_WASH_TYPE ──
  if (session.state === STATES.AWAITING_WASH_TYPE) {
    const washType = getWashTypeName(input, lang);
    if (!washType) return MSG.invalidWashType(lang);
    updateSession(phone, STATES.AWAITING_NAME, { washType });
    return MSG.askName(lang);
  }

  // ── AWAITING_NAME ──
  if (session.state === STATES.AWAITING_NAME) {
    const name = input.trim();
    if (name.length < 2) {
      return lang === 'ta' ? `⚠️ சரியான பெயரை அனுப்பவும்.` : `⚠️ Please send a valid name.`;
    }

    if (session.data.flowType === 'custom') {
      updateSession(phone, STATES.AWAITING_CUSTOM_SERVICE, { customerName: name });
      return MSG.askCustomService(lang);
    }

    const { vehicleNumber, service, vehicleType, kmRun, tyreSize, washType } = session.data;
    const result = await createJob(phone, vehicleNumber, service, name, false, {
      vehicleType, kmRun, tyreSize, washType,
    });

    if (result.success) {
      updateSession(phone, STATES.BOOKED, {
        customerName: name,
        jobId: result.data.job_id,
        jobStatus: 'queued',
      });
      return MSG.bookingReceived(vehicleNumber, service, name, lang, { washType, tyreSize, kmRun, vehicleType });
    }
    resetSession(phone);
    return MSG.bookingError(lang);
  }

  // ── AWAITING_CUSTOM_SERVICE ──
  if (session.state === STATES.AWAITING_CUSTOM_SERVICE) {
    const description = input.trim();
    if (description.length < 3) {
      return lang === 'ta' ? `⚠️ கொஞ்சம் விரிவாக விவரிக்கவும்.` : `⚠️ Please describe the service in a bit more detail.`;
    }
    const { vehicleNumber, customerName, vehicleType, kmRun } = session.data;
    const result = await createJob(phone, vehicleNumber, description, customerName, true, { vehicleType, kmRun });
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
      return result.success ? MSG.cancelSuccess(vehicleNumber, lang) : MSG.cancelError(lang);
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
    return MSG.alreadyBooked(
      session.data.vehicleNumber,
      session.data.service || session.data.customDescription,
      lang
    );
  }

  return MSG.unknown(lang);
}

module.exports = { handleMessage };
