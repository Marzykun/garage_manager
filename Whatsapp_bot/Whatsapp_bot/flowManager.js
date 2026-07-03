// flowManager.js
// Updated with new states for vehicle type, km run, tyre size, wash type

require('dotenv').config();

const TIMEOUT_MS = (parseInt(process.env.SESSION_TIMEOUT_MINUTES) || 10) * 60 * 1000;

const sessions = {};

const STATES = {
  IDLE:                    'IDLE',
  AWAITING_LANGUAGE:       'AWAITING_LANGUAGE',
  AWAITING_SERVICE:        'AWAITING_SERVICE',
  AWAITING_VEHICLE:        'AWAITING_VEHICLE',
  AWAITING_VEHICLE_TYPE:   'AWAITING_VEHICLE_TYPE',
  AWAITING_KM:             'AWAITING_KM',
  AWAITING_TYRE_SIZE:      'AWAITING_TYRE_SIZE',
  AWAITING_WASH_TYPE:      'AWAITING_WASH_TYPE',
  AWAITING_NAME:           'AWAITING_NAME',
  AWAITING_CUSTOM_SERVICE: 'AWAITING_CUSTOM_SERVICE',
  AWAITING_CANCEL_CONFIRM: 'AWAITING_CANCEL_CONFIRM',
  BOOKED:                  'BOOKED',
};

// Standard services
const SERVICE_MAP = {
  '1': { en: 'Car Washing',   ta: 'கார் கழுவுதல்' },
  '2': { en: 'Tyre Changing', ta: 'டயர் மாற்றுதல்' },
  '3': { en: 'Tyre Alignment',ta: 'சக்கர சீரமைப்பு' },
  '4': { en: 'Tyre Balancing',ta: 'சக்கர சமநிலைப்படுத்துதல்' },
};

// Services that need tyre size
const TYRE_SERVICES = ['Tyre Changing', 'Tyre Alignment', 'Tyre Balancing',
                       'டயர் மாற்றுதல்', 'சக்கர சீரமைப்பு', 'சக்கர சமநிலைப்படுத்துதல்'];

// Wash types
const WASH_TYPE_MAP = {
  '1': { en: 'Water Wash',  ta: 'தண்ணீர் கழுவுதல்' },
  '2': { en: 'Body Wash',   ta: 'பாடி வாஷ்' },
  '3': { en: 'Full Wash',   ta: 'முழு கழுவுதல்' },
};

// Vehicle types
const VEHICLE_TYPE_MAP = {
  '1': { en: 'Car',   ta: 'கார்' },
  '2': { en: 'Van',   ta: 'வேன்' },
  '3': { en: 'Lorry', ta: 'லாரி' },
};

function getSession(phone) {
  _cleanupIfExpired(phone);
  if (!sessions[phone]) {
    sessions[phone] = {
      state: STATES.IDLE,
      data: { language: 'en' },
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
    if (elapsed > TIMEOUT_MS) delete sessions[phone];
  }
}

function getServiceName(input, lang = 'en') {
  const service = SERVICE_MAP[input.trim()];
  if (!service) return null;
  return service[lang] || service['en'];
}

function getWashTypeName(input, lang = 'en') {
  const wash = WASH_TYPE_MAP[input.trim()];
  if (!wash) return null;
  return wash[lang] || wash['en'];
}

function getVehicleTypeName(input, lang = 'en') {
  const vtype = VEHICLE_TYPE_MAP[input.trim()];
  if (!vtype) return null;
  return vtype[lang] || vtype['en'];
}

function needsTyreSize(serviceName) {
  return TYRE_SERVICES.includes(serviceName);
}

function isCarWash(serviceName) {
  return serviceName === 'Car Washing' || serviceName === 'கார் கழுவுதல்';
}

function getAllSessions() { return sessions; }

module.exports = {
  STATES, SERVICE_MAP, WASH_TYPE_MAP, VEHICLE_TYPE_MAP,
  getSession, updateSession, resetSession,
  getServiceName, getWashTypeName, getVehicleTypeName,
  needsTyreSize, isCarWash, getAllSessions,
};
