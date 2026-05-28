// flowManager.js
// Tracks where each customer is in the conversation flow
// States: IDLE -> AWAITING_LANGUAGE -> AWAITING_SERVICE -> AWAITING_VEHICLE -> AWAITING_NAME -> AWAITING_CUSTOM_SERVICE -> BOOKED

require('dotenv').config();

const TIMEOUT_MS = (parseInt(process.env.SESSION_TIMEOUT_MINUTES) || 10) * 60 * 1000;

// In-memory store: { phoneNumber: { state, data, lastActive } }
const sessions = {};

const STATES = {
  IDLE: 'IDLE',
  AWAITING_LANGUAGE: 'AWAITING_LANGUAGE',
  AWAITING_SERVICE: 'AWAITING_SERVICE',
  AWAITING_VEHICLE: 'AWAITING_VEHICLE',
  AWAITING_NAME: 'AWAITING_NAME',
  AWAITING_CUSTOM_SERVICE: 'AWAITING_CUSTOM_SERVICE',
  AWAITING_CANCEL_CONFIRM: 'AWAITING_CANCEL_CONFIRM',
  BOOKED: 'BOOKED',
};

// Service map — standard services
const SERVICE_MAP = {
  '1': { en: 'Car Washing',   ta: 'கார் கழுவுதல்' },
  '2': { en: 'Tyre Changing', ta: 'டயர் மாற்றுதல்' },
  '3': { en: 'Tyre Alignment',ta: 'சக்கர சீரமைப்பு' },
  '4': { en: 'Tyre Balancing',ta: 'சக்கர சமநிலைப்படுத்துதல்' },
};

function getSession(phone) {
  _cleanupIfExpired(phone);
  if (!sessions[phone]) {
    sessions[phone] = {
      state: STATES.IDLE,
      data: { language: 'en' }, // default English
      lastActive: Date.now(),
    };
  }
  return sessions[phone];
}

function updateSession(phone, state, data = {}) {
  const session = getSession(phone);
  session.state = state;
  session.data = { ...session.data, ...data };
  session.lastActive = Date.now();
}

function resetSession(phone) {
  sessions[phone] = {
    state: STATES.IDLE,
    data: { language: 'en' },
    lastActive: Date.now(),
  };
}

function _cleanupIfExpired(phone) {
  if (sessions[phone]) {
    const elapsed = Date.now() - sessions[phone].lastActive;
    if (elapsed > TIMEOUT_MS) {
      delete sessions[phone];
    }
  }
}

// Returns service name in correct language, or null
function getServiceName(input, lang = 'en') {
  const service = SERVICE_MAP[input.trim()];
  if (!service) return null;
  return service[lang] || service['en'];
}

function getAllSessions() {
  return sessions;
}

module.exports = {
  STATES,
  SERVICE_MAP,
  getSession,
  updateSession,
  resetSession,
  getServiceName,
  getAllSessions,
};
