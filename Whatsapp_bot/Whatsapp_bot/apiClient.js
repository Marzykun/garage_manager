// apiClient.js
// Talks to the real Garage Manager backend (Garage_backend/backend) instead of the mock API.

require('dotenv').config();
const axios = require('axios');

const BASE_URL = process.env.BACKEND_URL || 'http://localhost:3000/api/bot';

const api = axios.create({
  baseURL: BASE_URL,
  timeout: 8000,
  headers: {
    'Content-Type': 'application/json',
    'x-api-key': process.env.BOT_API_KEY || '',
  },
});

// Maps the bot's service names / wash types to the backend's service_type enum
const SERVICE_TYPE_MAP = {
  'Car Washing': 'car_wash',
  'கார் கழுவுதல்': 'car_wash',
  'Tyre Changing': 'tyre_change',
  'டயர் மாற்றுதல்': 'tyre_change',
  'Tyre Alignment': 'wheel_alignment',
  'சக்கர சீரமைப்பு': 'wheel_alignment',
  'Tyre Balancing': 'wheel_balancing',
  'சக்கர சமநிலைப்படுத்துதல்': 'wheel_balancing',
};

const WASH_TYPE_MAP = {
  'Water Wash': 'water_wash',
  'தண்ணீர் கழுவுதல்': 'water_wash',
  'Full Wash': 'full_service',
  'முழு கழுவுதல்': 'full_service',
  'Body Wash': 'car_wash',
  'பாடி வாஷ்': 'car_wash',
};

// Reverse map — for showing a friendly label in status replies
const ENUM_TO_LABEL = {
  car_wash: 'Car Washing',
  tyre_change: 'Tyre Changing',
  wheel_alignment: 'Tyre Alignment',
  wheel_balancing: 'Tyre Balancing',
  water_wash: 'Water Wash',
  full_service: 'Full Service',
  other: 'Other Service',
};

function mapServiceType(serviceName, washType) {
  if (washType && WASH_TYPE_MAP[washType]) return WASH_TYPE_MAP[washType];
  if (serviceName && SERVICE_TYPE_MAP[serviceName]) return SERVICE_TYPE_MAP[serviceName];
  return 'other';
}

function buildIssueText(extra = {}, customDescription = null) {
  const parts = [];
  if (customDescription) parts.push(customDescription);
  if (extra.vehicleType) parts.push(`Vehicle type: ${extra.vehicleType}`);
  if (extra.kmRun)       parts.push(`KM run: ${extra.kmRun}`);
  if (extra.tyreSize)    parts.push(`Tyre size: ${extra.tyreSize}`);
  return parts.length ? parts.join(' | ') : null;
}

/**
 * Create a booking — backend stores this as an "appointment" (pending),
 * which the owner accepts/rejects from the Appointments screen.
 * @param {string} phone
 * @param {string} vehicleNumber
 * @param {string} serviceName - display name, or free-text description if isCustom
 * @param {string} customerName
 * @param {boolean} isCustom
 * @param {object} extra - { vehicleType, kmRun, tyreSize, washType, language }
 */
async function createJob(phone, vehicleNumber, serviceName, customerName = 'Customer', isCustom = false, extra = {}) {
  try {
    const serviceType = isCustom ? 'other' : mapServiceType(serviceName, extra.washType);
    const issue = buildIssueText(extra, isCustom ? serviceName : null);

    const response = await api.post('/appointments', {
      customer_name: customerName,
      phone,
      vehicle_number: vehicleNumber,
      service_type: serviceType,
      issue,
      language_pref: (extra.language || 'en').toUpperCase(),
    });

    const appointment = response.data.data;
    return { success: true, data: { job_id: appointment.id, appointment } };
  } catch (error) {
    console.error('[apiClient] createJob error:', error.message);
    return { success: false, error: error.message };
  }
}

/**
 * Look up the status of a customer's most recent job/booking for a vehicle.
 * Checks active job cards first, then falls back to pending appointments.
 */
async function getJobStatus(vehicleNumber) {
  try {
    // 1) Try an existing job card via the vehicle record
    try {
      const vehicleRes = await api.get(`/vehicles/number/${vehicleNumber}`);
      const vehicle = vehicleRes.data.data;

      const jobsRes = await api.get(`/customers/${vehicle.customer_id}/jobs`);
      const jobs = (jobsRes.data.data || [])
        .filter(j => j.vehicle_id === vehicle.id)
        .sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

      if (jobs.length > 0) {
        const job = jobs[0];
        return {
          success: true,
          data: { job: { service: ENUM_TO_LABEL[job.service_type] || job.service_type, status: job.status } },
        };
      }
    } catch (innerErr) {
      // Vehicle not found yet — fall through to appointments
    }

    // 2) Fall back to a pending appointment (not yet accepted by owner)
    const apptRes = await api.get('/appointments', { params: { status: 'pending' } });
    const appt = (apptRes.data.data || []).find(
      a => (a.vehicle_number || '').toUpperCase() === vehicleNumber.toUpperCase()
    );

    if (appt) {
      return {
        success: true,
        data: { job: { service: ENUM_TO_LABEL[appt.service_type] || appt.service_type, status: 'queued' } },
      };
    }

    return { success: true, data: { job: null } };
  } catch (error) {
    console.error('[apiClient] getJobStatus error:', error.message);
    return { success: false, error: error.message };
  }
}

/**
 * Cancel a booking. `jobId` is the appointment id returned by createJob.
 * If the appointment has already been accepted (turned into a job card),
 * fall back to cancelling the job card itself.
 */
async function cancelJob(jobId, vehicleNumber = null) {
  try {
    const response = await api.patch(`/appointments/${jobId}/cancel`);
    return { success: true, data: response.data };
  } catch (error) {
    const status = error.response && error.response.status;

    // Appointment already accepted -> cancel the resulting job card instead
    if (status === 409 && vehicleNumber) {
      try {
        const vehicleRes = await api.get(`/vehicles/number/${vehicleNumber}`);
        const vehicle = vehicleRes.data.data;

        const jobsRes = await api.get(`/customers/${vehicle.customer_id}/jobs`);
        const job = (jobsRes.data.data || [])
          .filter(j => j.vehicle_id === vehicle.id && !['completed', 'cancelled'].includes(j.status))
          .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))[0];

        if (job) {
          const cancelRes = await api.patch(`/jobs/${job.id}/cancel`);
          return { success: true, data: cancelRes.data };
        }
      } catch (fallbackErr) {
        console.error('[apiClient] cancelJob fallback error:', fallbackErr.message);
      }
    }

    console.error('[apiClient] cancelJob error:', error.message);
    return { success: false, error: error.message };
  }
}

module.exports = { createJob, getJobStatus, cancelJob };
