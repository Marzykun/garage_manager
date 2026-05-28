// apiClient.js
// Handles all communication between the bot and the backend API

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
 * @param {boolean} isCustom - true if customer typed a custom service
 */
async function createJob(phone, vehicleNumber, serviceName, customerName = 'Customer', isCustom = false) {
  try {
    const response = await api.post('/jobs/create', {
      customer_phone: phone,
      customer_name: customerName,
      vehicle_number: vehicleNumber,
      service: serviceName,
      source: 'whatsapp',
      is_custom: isCustom,
      status: isCustom ? 'pending_approval' : 'queued',
    });
    return { success: true, data: response.data };
  } catch (error) {
    console.error('[apiClient] createJob error:', error.message);
    return { success: false, error: error.message };
  }
}

/**
 * Get the current status of a vehicle
 * @param {string} vehicleNumber
 */
async function getJobStatus(vehicleNumber) {
  try {
    const response = await api.get(`/customers/search?q=${vehicleNumber}`);
    return { success: true, data: response.data };
  } catch (error) {
    console.error('[apiClient] getJobStatus error:', error.message);
    return { success: false, error: error.message };
  }
}

/**
 * Cancel a job (only works if status is queued or confirmed)
 * @param {string} jobId
 */
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
