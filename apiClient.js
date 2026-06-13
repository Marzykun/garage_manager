// apiClient.js
// Updated to pass vehicle_type, km_run, tyre_size, wash_type to backend

require('dotenv').config();
const axios = require('axios');

const BASE_URL = process.env.BACKEND_URL || 'http://localhost:3002';

const api = axios.create({
  baseURL: BASE_URL,
  timeout: 5000,
  headers: { 'Content-Type': 'application/json' },
});

/**
 * Create a new job card
 * @param {string} phone
 * @param {string} vehicleNumber
 * @param {string} serviceName
 * @param {string} customerName
 * @param {boolean} isCustom
 * @param {object} extra - { vehicleType, kmRun, tyreSize, washType }
 */
async function createJob(phone, vehicleNumber, serviceName, customerName = 'Customer', isCustom = false, extra = {}) {
  try {
    const response = await api.post('/jobs/create', {
      customer_phone:  phone,
      customer_name:   customerName,
      vehicle_number:  vehicleNumber,
      service:         serviceName,
      source:          'whatsapp',
      is_custom:       isCustom,
      status:          isCustom ? 'pending_approval' : 'queued',
      vehicle_type:    extra.vehicleType || null,
      km_run:          extra.kmRun       || null,
      tyre_size:       extra.tyreSize    || null,
      wash_type:       extra.washType    || null,
    });
    return { success: true, data: response.data };
  } catch (error) {
    console.error('[apiClient] createJob error:', error.message);
    return { success: false, error: error.message };
  }
}

async function getJobStatus(vehicleNumber) {
  try {
    const response = await api.get(`/customers/search?q=${vehicleNumber}`);
    return { success: true, data: response.data };
  } catch (error) {
    console.error('[apiClient] getJobStatus error:', error.message);
    return { success: false, error: error.message };
  }
}

async function cancelJob(jobId) {
  try {
    const response = await api.patch(`/jobs/${jobId}/cancel`);
    return { success: true, data: response.data };
  } catch (error) {
    console.error('[apiClient] cancelJob error:', error.message);
    return { success: false, error: error.message };
  }
}

module.exports = { createJob, getJobStatus, cancelJob };
